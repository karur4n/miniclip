# MiniClip Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** テキストを選択するとカーソルの上に操作ボタンの小窓を出す、メニューバー常駐の macOS アプリを作る。

**Architecture:** Swift Package の実行ターゲット1つ。マウス監視（`SelectionWatcher`）→ 選択文字列の取得（`SelectionReader`）→ 表示する操作の決定（`Actions`）→ 小窓の表示（`PopupPanel`）の順に流れ、`main.swift` の `AppDelegate` がそれらをつなぐ。自動テストは `Actions` の判定だけにする。

**Tech Stack:** Swift 6.3 ツールチェーン（言語モード 5）、AppKit、ApplicationServices（アクセシビリティ API）、Swift Testing、Make、codesign

**Spec:** `docs/spec.md`

## Global Constraints

- 対象 OS: macOS 13 以上（`LSMinimumSystemVersion` 13.0）
- バンドル ID / ログの subsystem: `dev.karur4n.miniclip`
- 署名に使う証明書の名前: `MiniClip Dev`
- 置き場所: `~/Applications/MiniClip.app`
- `LSUIElement = true`（Dock に出さない）
- 外部の依存パッケージは使わない
- コメントは最小限。非自明な知見だけ `// NOTE:` で残す

## Review Focus

1. トリプルクリックで行末の改行まで選択される → 前後を取り除いてから判定し、URL なら「開く」が出る（Task 1 でテスト）
2. 空白や改行だけの選択 → 小窓を出さない（Task 1 でテスト）
3. 検索語に空白・`&`・日本語が含まれる → パーセントエンコードされ、検索語が途中で切れない（Task 1 でテスト）
4. 途中に改行を含む選択の先頭が URL → 「開く」は出ない（Task 1 でテスト）
5. Cmd+C で取得したあと → 元のクリップボードの内容が残る。画面の端で選択したとき → 小窓が画面内に収まる（Task 3 の手動確認）

---

### Task 0: 署名用の証明書を作る（手作業）

利用者が一度だけ行う。以降のタスクの前提になる。

- [ ] **Step 1: 証明書を作る**

キーチェーンアクセス → メニュー「キーチェーンアクセス > 証明書アシスタント > 証明書を作成...」
- 名前: `MiniClip Dev`
- 固有名のタイプ: 自己署名ルート
- 証明書のタイプ: コード署名

- [ ] **Step 2: 有効になっているか確かめる**

Run: `security find-identity -v -p codesigning`
Expected: `"MiniClip Dev"` を含む行が出る。

出ない場合は、キーチェーンアクセスで `MiniClip Dev` を開き、「信頼 > コード署名」を「常に信頼」にして、もう一度確かめる。

---

### Task 1: パッケージの土台と操作の判定

**Files:**
- Create: `Package.swift`
- Create: `.gitignore`
- Create: `Sources/MiniClip/main.swift`（この段階では空の起動処理）
- Create: `Sources/MiniClip/Actions.swift`
- Test: `Tests/MiniClipTests/ActionsTests.swift`

**Interfaces:**
- Produces:
  - `struct Action { let title: String; let condition: String?; let perform: (String) -> Void }`
  - `Actions.menu(for raw: String) -> (text: String, actions: [Action])?` — 前後の空白・改行を取り除き、空なら `nil`。条件に合う操作を表の順で返す
  - `Actions.fill(_ template: String, with text: String) -> String` — `{text}` をパーセントエンコードした文字列で置き換える

- [ ] **Step 1: パッケージを作る**

`Package.swift`:

```swift
// swift-tools-version:6.0
import PackageDescription

let package = Package(
    name: "MiniClip",
    platforms: [.macOS(.v13)],
    targets: [
        .executableTarget(name: "MiniClip"),
        .testTarget(name: "MiniClipTests", dependencies: ["MiniClip"]),
    ],
    swiftLanguageModes: [.v5]
)
```

`.gitignore`:

```
.build/
build/
```

`Sources/MiniClip/main.swift`:

```swift
import AppKit

NSApplication.shared.run()
```

- [ ] **Step 2: 失敗するテストを書く**

`Tests/MiniClipTests/ActionsTests.swift`:

```swift
import Testing
@testable import MiniClip

private func titles(_ raw: String) -> [String]? {
    Actions.menu(for: raw)?.actions.map(\.title)
}

@Test("URL には全操作が表の順で出る")
func urlShowsAllActions() {
    #expect(titles("https://example.com/a?b=1") == ["コピー", "開く", "Google", "翻訳", "辞書"])
}

@Test("行末の改行は取り除いてから判定する")
func trimsTrailingNewline() {
    let menu = Actions.menu(for: "https://example.com\n")
    #expect(menu?.text == "https://example.com")
    #expect(menu?.actions.map(\.title).contains("開く") == true)
}

@Test("途中に改行がある選択には「開く」を出さない")
func multilineIsNotURL() {
    #expect(titles("https://example.com\nfoo")?.contains("開く") == false)
}

@Test("空白と改行だけなら nil")
func whitespaceOnlyIsNil() {
    #expect(Actions.menu(for: "  \n\t ") == nil)
}

@Test("英文には翻訳を出し、空白を含むので辞書は出さない")
func englishSentence() {
    #expect(titles("hello world") == ["コピー", "Google", "翻訳"])
}

@Test("英字のない短い日本語には翻訳を出さず、辞書を出す")
func japaneseWord() {
    #expect(titles("形態素") == ["コピー", "Google", "辞書"])
}

@Test("31文字以上には辞書を出さない")
func longTextHasNoDictionary() {
    #expect(titles(String(repeating: "あ", count: 31)) == ["コピー", "Google"])
}

@Test("{text} を予約文字も含めてパーセントエンコードして埋め込む")
func fillEncodes() {
    #expect(Actions.fill("https://x.test/?q={text}", with: "a b&c=日本")
        == "https://x.test/?q=a%20b%26c%3D%E6%97%A5%E6%9C%AC")
}
```

- [ ] **Step 3: テストが失敗することを確かめる**

Run: `swift test`
Expected: コンパイルエラー（`cannot find 'Actions' in scope`）

- [ ] **Step 4: 実装する**

`Sources/MiniClip/Actions.swift`:

```swift
import AppKit
import os

struct Action {
    let title: String
    let condition: String?
    let perform: (String) -> Void

    func matches(_ text: String) -> Bool {
        guard let condition else { return true }
        return text.range(of: condition, options: .regularExpression) != nil
    }
}

enum Actions {
    private static let log = Logger(subsystem: "dev.karur4n.miniclip", category: "actions")

    static let all: [Action] = [
        Action(title: "コピー", condition: nil) { text in
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(text, forType: .string)
        },
        Action(title: "開く", condition: #"^https?://\S+$"#) { text in
            open(text)
        },
        Action(title: "Google", condition: nil) { text in
            open(fill("https://www.google.com/search?q={text}", with: text))
        },
        Action(title: "翻訳", condition: "[A-Za-z]") { text in
            open(fill("https://translate.google.com/?sl=auto&tl=ja&text={text}", with: text))
        },
        Action(title: "辞書", condition: #"^\S{1,30}$"#) { text in
            open(fill("dict://{text}", with: text))
        },
    ]

    static func menu(for raw: String) -> (text: String, actions: [Action])? {
        let text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return nil }
        return (text, all.filter { $0.matches(text) })
    }

    // NOTE: .urlQueryAllowed は & と = を通してしまうので、非予約文字だけを許可する
    private static let unreserved = CharacterSet(
        charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~")

    static func fill(_ template: String, with text: String) -> String {
        let encoded = text.addingPercentEncoding(withAllowedCharacters: unreserved)!
        return template.replacingOccurrences(of: "{text}", with: encoded)
    }

    private static func open(_ string: String) {
        guard let url = URL(string: string) else {
            log.error("URL を作れない: \(string, privacy: .public)")
            return
        }
        NSWorkspace.shared.open(url)
    }
}
```

- [ ] **Step 5: テストが通ることを確かめる**

Run: `swift test`
Expected: 8 件すべて PASS

- [ ] **Step 6: コミット**

```bash
git add Package.swift .gitignore Sources Tests
git commit -m "feat: 操作の一覧と表示条件の判定を追加"
```

---

### Task 2: メニューバー常駐と権限の確認、.app の組み立て

**Files:**
- Modify: `Sources/MiniClip/main.swift`（全体を置き換える）
- Create: `Resources/Info.plist`
- Create: `Makefile`

**Interfaces:**
- Consumes: なし（Task 3 で `SelectionWatcher` / `SelectionReader` / `PopupPanel` / `Actions.menu(for:)` をつなぐ）
- Produces: `AppDelegate.startWatching()` — 権限が確認できたときに呼ばれる。Task 3 で中身を足す

- [ ] **Step 1: Info.plist を書く**

`Resources/Info.plist`:

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleIdentifier</key>
    <string>dev.karur4n.miniclip</string>
    <key>CFBundleName</key>
    <string>MiniClip</string>
    <key>CFBundleExecutable</key>
    <string>MiniClip</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleShortVersionString</key>
    <string>0.1</string>
    <key>CFBundleVersion</key>
    <string>1</string>
    <key>LSMinimumSystemVersion</key>
    <string>13.0</string>
    <key>LSUIElement</key>
    <true/>
</dict>
</plist>
```

- [ ] **Step 2: Makefile を書く**

`Makefile`（字下げはタブ）:

```make
APP_NAME := MiniClip
BUNDLE := build/$(APP_NAME).app
DEST := $(HOME)/Applications/$(APP_NAME).app
IDENTITY := MiniClip Dev

.PHONY: build test install

build:
	swift build -c release

test:
	swift test

install: build
	rm -rf $(BUNDLE)
	mkdir -p $(BUNDLE)/Contents/MacOS
	cp Resources/Info.plist $(BUNDLE)/Contents/Info.plist
	cp .build/release/$(APP_NAME) $(BUNDLE)/Contents/MacOS/$(APP_NAME)
	codesign --force --sign "$(IDENTITY)" $(BUNDLE)
	-pkill -x $(APP_NAME)
	mkdir -p $(HOME)/Applications
	rm -rf "$(DEST)"
	cp -R $(BUNDLE) "$(DEST)"
	open "$(DEST)"
```

- [ ] **Step 3: main.swift を書く**

`Sources/MiniClip/main.swift`:

```swift
import AppKit
import ApplicationServices
import os

final class AppDelegate: NSObject, NSApplicationDelegate {
    private let log = Logger(subsystem: "dev.karur4n.miniclip", category: "app")
    private var statusItem: NSStatusItem!
    private var trustTimer: Timer?

    func applicationDidFinishLaunching(_ notification: Notification) {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        let menu = NSMenu()
        menu.addItem(withTitle: "終了", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        statusItem.menu = menu

        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        if AXIsProcessTrustedWithOptions(options) {
            startWatching()
            return
        }
        setIcon(trusted: false)
        log.error("アクセシビリティ権限がないため監視を始めない")
        trustTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] timer in
            guard AXIsProcessTrusted() else { return }
            timer.invalidate()
            self?.startWatching()
        }
    }

    private func startWatching() {
        setIcon(trusted: true)
        log.info("監視を開始")
    }

    private func setIcon(trusted: Bool) {
        let name = trusted ? "text.cursor" : "exclamationmark.triangle"
        statusItem.button?.image = NSImage(systemSymbolName: name, accessibilityDescription: "MiniClip")
    }
}

let delegate = AppDelegate()
NSApplication.shared.delegate = delegate
NSApplication.shared.run()
```

- [ ] **Step 4: テストがまだ通ることを確かめる**

Run: `swift test`
Expected: 8 件すべて PASS

- [ ] **Step 5: インストールして手動で確かめる**

Run: `make install`
Expected: `codesign` がエラーなく終わり、アプリが起動する。

確かめること:
1. Dock にアイコンが出ない
2. メニューバーに警告アイコンが出て、アクセシビリティ許可のダイアログが出る
3. システム設定 > プライバシーとセキュリティ > アクセシビリティで MiniClip を許可すると、1 秒ほどでアイコンが `text.cursor` に変わる
4. `make install` をもう一度実行しても、アイコンは最初から `text.cursor` になる（権限が外れていない）
5. メニューの「終了」でアプリが終わる

ログは `log stream --predicate 'subsystem == "dev.karur4n.miniclip"'` で見る。

- [ ] **Step 6: コミット**

```bash
git add Sources/MiniClip/main.swift Resources/Info.plist Makefile
git commit -m "feat: メニューバー常駐と権限確認、.app の組み立てを追加"
```

---

### Task 3: 選択の検知、文字列の取得、小窓の表示

**Files:**
- Create: `Sources/MiniClip/SelectionWatcher.swift`
- Create: `Sources/MiniClip/SelectionReader.swift`
- Create: `Sources/MiniClip/PopupPanel.swift`
- Modify: `Sources/MiniClip/main.swift`（`AppDelegate` に接続を足す）

**Interfaces:**
- Consumes: `Action`、`Actions.menu(for:) -> (text: String, actions: [Action])?`（Task 1）、`AppDelegate.startWatching()`（Task 2）
- Produces:
  - `SelectionWatcher(onSelect: @escaping (NSPoint) -> Void)`、`start()` — 座標は画面全体の座標（左下原点、`NSEvent.mouseLocation` と同じ）
  - `SelectionReader.read() -> String?`
  - `PopupPanel()`、`show(text: String, actions: [Action], at: NSPoint)`、`close()`

- [ ] **Step 1: SelectionWatcher を書く**

`Sources/MiniClip/SelectionWatcher.swift`:

```swift
import AppKit

final class SelectionWatcher {
    private let onSelect: (NSPoint) -> Void
    private var monitor: Any?
    private var downLocation: NSPoint = .zero

    init(onSelect: @escaping (NSPoint) -> Void) {
        self.onSelect = onSelect
    }

    func start() {
        monitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .leftMouseUp]) { [weak self] event in
            self?.handle(event)
        }
    }

    private func handle(_ event: NSEvent) {
        let location = NSEvent.mouseLocation
        switch event.type {
        case .leftMouseDown:
            downLocation = location
        case .leftMouseUp:
            let dragged = hypot(location.x - downLocation.x, location.y - downLocation.y) >= 5
            if dragged || event.clickCount >= 2 {
                onSelect(location)
            }
        default:
            break
        }
    }
}
```

- [ ] **Step 2: SelectionReader を書く**

`Sources/MiniClip/SelectionReader.swift`:

```swift
import AppKit
import ApplicationServices

enum SelectionReader {
    static func read() -> String? {
        if let text = readViaAccessibility(), !text.isEmpty {
            return text
        }
        return readViaCopy()
    }

    private static func readViaAccessibility() -> String? {
        let system = AXUIElementCreateSystemWide()
        var focused: CFTypeRef?
        guard AXUIElementCopyAttributeValue(system, kAXFocusedUIElementAttribute as CFString, &focused) == .success,
              let focused else { return nil }
        var selected: CFTypeRef?
        guard AXUIElementCopyAttributeValue(focused as! AXUIElement, kAXSelectedTextAttribute as CFString, &selected) == .success else {
            return nil
        }
        return selected as? String
    }

    private static func readViaCopy() -> String? {
        let pasteboard = NSPasteboard.general
        let saved = snapshot(pasteboard)
        let before = pasteboard.changeCount

        sendCommandC()
        let deadline = Date().addingTimeInterval(0.3)
        while pasteboard.changeCount == before && Date() < deadline {
            Thread.sleep(forTimeInterval: 0.01)
        }
        guard pasteboard.changeCount != before else { return nil }

        let text = pasteboard.string(forType: .string)
        restore(pasteboard, saved)
        return text
    }

    private static func snapshot(_ pasteboard: NSPasteboard) -> [NSPasteboardItem] {
        (pasteboard.pasteboardItems ?? []).map { item in
            let copy = NSPasteboardItem()
            for type in item.types {
                if let data = item.data(forType: type) {
                    copy.setData(data, forType: type)
                }
            }
            return copy
        }
    }

    private static func restore(_ pasteboard: NSPasteboard, _ items: [NSPasteboardItem]) {
        pasteboard.clearContents()
        if !items.isEmpty {
            pasteboard.writeObjects(items)
        }
    }

    private static func sendCommandC() {
        // NOTE: 仮想キーコード 8 は物理キー位置の C。JIS 配列でも同じ
        let source = CGEventSource(stateID: .combinedSessionState)
        for keyDown in [true, false] {
            let event = CGEvent(keyboardEventSource: source, virtualKey: 8, keyDown: keyDown)
            event?.flags = .maskCommand
            event?.post(tap: .cghidEventTap)
        }
    }
}
```

- [ ] **Step 3: PopupPanel を書く**

`Sources/MiniClip/PopupPanel.swift`:

```swift
import AppKit

final class PopupPanel {
    private let panel: NSPanel
    private var monitors: [Any] = []

    init() {
        panel = NSPanel(
            contentRect: .zero,
            styleMask: [.nonactivatingPanel, .borderless],
            backing: .buffered,
            defer: true)
        panel.level = .popUpMenu
        panel.isFloatingPanel = true
        panel.hidesOnDeactivate = false
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
    }

    func show(text: String, actions: [Action], at point: NSPoint) {
        close()

        let buttons = actions.map { action in
            ClosureButton(title: action.title) { [weak self] in
                self?.close()
                action.perform(text)
            }
        }
        let stack = NSStackView(views: buttons)
        stack.orientation = .horizontal
        stack.spacing = 4
        stack.edgeInsets = NSEdgeInsets(top: 4, left: 6, bottom: 4, right: 6)

        let background = NSVisualEffectView()
        background.material = .menu
        background.state = .active
        background.wantsLayer = true
        background.layer?.cornerRadius = 8
        background.addSubview(stack)
        stack.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: background.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: background.trailingAnchor),
            stack.topAnchor.constraint(equalTo: background.topAnchor),
            stack.bottomAnchor.constraint(equalTo: background.bottomAnchor),
        ])

        panel.contentView = background
        let size = stack.fittingSize
        panel.setFrame(frame(size: size, above: point), display: true)
        panel.orderFrontRegardless()

        monitors = [
            NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown, .keyDown]) { [weak self] _ in
                self?.close()
            },
        ].compactMap { $0 }
    }

    func close() {
        monitors.forEach(NSEvent.removeMonitor)
        monitors = []
        panel.orderOut(nil)
    }

    private func frame(size: NSSize, above point: NSPoint) -> NSRect {
        var origin = NSPoint(x: point.x - size.width / 2, y: point.y + 12)
        let screen = NSScreen.screens.first { NSMouseInRect(point, $0.frame, false) } ?? NSScreen.main
        if let visible = screen?.visibleFrame {
            origin.x = min(max(origin.x, visible.minX), visible.maxX - size.width)
            origin.y = min(max(origin.y, visible.minY), visible.maxY - size.height)
        }
        return NSRect(origin: origin, size: size)
    }
}

private final class ClosureButton: NSButton {
    private var handler: (() -> Void)?

    convenience init(title: String, handler: @escaping () -> Void) {
        self.init(title: title, target: nil, action: nil)
        self.handler = handler
        target = self
        action = #selector(fire)
        bezelStyle = .recessed
        controlSize = .small
    }

    @objc private func fire() {
        handler?()
    }
}
```

- [ ] **Step 4: AppDelegate につなぐ**

`Sources/MiniClip/main.swift` の `AppDelegate` に、次のプロパティを `trustTimer` の下に足す。

```swift
    private let popup = PopupPanel()
    private lazy var watcher = SelectionWatcher { [weak self] point in
        self?.selectionDidEnd(at: point)
    }
```

`startWatching()` を次に置き換え、その下に `selectionDidEnd(at:)` を足す。

```swift
    private func startWatching() {
        setIcon(trusted: true)
        watcher.start()
        log.info("監視を開始")
    }

    private func selectionDidEnd(at point: NSPoint) {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { [weak self] in
            guard let self,
                  let raw = SelectionReader.read(),
                  let menu = Actions.menu(for: raw) else { return }
            popup.show(text: menu.text, actions: menu.actions, at: point)
        }
    }
```

- [ ] **Step 5: テストがまだ通ることを確かめる**

Run: `swift test`
Expected: 8 件すべて PASS

- [ ] **Step 6: インストールして手動で確かめる**

Run: `make install`

テキストエディット、Chrome、Slack、ターミナルのそれぞれで確かめる。

1. ドラッグで選択すると、カーソルの上に小窓が出る
2. ダブルクリックで単語を選択すると、小窓が出る
3. 選択せずにクリックしただけでは、小窓が出ない
4. 「コピー」→ 別の場所に貼り付けると、選択した文字列が入る
5. `https://example.com` を選択 →「開く」でブラウザが開く
6. `hello world` を選択 →「Google」で検索結果、「翻訳」で日本語訳のページが開く
7. `apple` を選択 →「辞書」で辞書アプリが開く
8. 小窓の外をクリック、またはキーを押すと小窓が閉じる
9. 小窓が出ている間も、元のアプリの選択が残っている
10. 先に「ABC」をコピーしておき、Chrome で選択して小窓を出す → その後に貼り付けると「ABC」が入る（Cmd+C で取得する経路を通ったあとも、元の内容が残る）
11. 画面の右端と上端で選択すると、小窓が画面の中に収まる

- [ ] **Step 7: コミット**

```bash
git add Sources/MiniClip
git commit -m "feat: 選択の検知と小窓の表示を追加"
```
