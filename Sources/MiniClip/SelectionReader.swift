import AppKit
import ApplicationServices

enum SelectionReader {
    static func read() -> String? {
        // NOTE: アクセシビリティ API が空文字を返したら選択なしと確定する。Cmd+C を送ると警告音やファイルのコピーが起きる
        if let text = readViaAccessibility() {
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

        // NOTE: 相手のアプリはクリアと書き込みを分けて行うので、changeCount が変わった直後は文字列がまだないことがある
        var text = pasteboard.string(forType: .string)
        while text == nil && Date() < deadline {
            Thread.sleep(forTimeInterval: 0.01)
            text = pasteboard.string(forType: .string)
        }
        // NOTE: Finder でファイルを選んだまま Cmd+C が届くと、ファイル名が文字列として取れる。ファイルなら選択なしとする
        let copiedFiles = pasteboard.canReadObject(
            forClasses: [NSURL.self],
            options: [.urlReadingFileURLsOnly: true])
        restore(pasteboard, saved)
        return copiedFiles ? nil : text
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
