# MiniClip 仕様

テキストを選択すると、カーソルの上に小さなメニューを出す macOS アプリ。PopClip の最小限の代替として、自分の Mac でだけ使う。

## 動作

1. 画面全体のマウス操作を監視する
   - 左ボタンを離したとき、押した位置から 5pt 以上動いていれば「ドラッグ選択」とみなす
   - ただし、押してから離すまでにドラッグ用クリップボード（`NSPasteboard(name: .drag)`）の `changeCount` が変わっていたら、ファイルや文字をドラッグして落とす操作なので無視する
   - 左ボタンのダブルクリック・トリプルクリックも対象にする
2. 50ms 待ってから選択文字列を取得する（アプリ側の選択更新を待つ）
3. 選択文字列が空なら何もしない
4. 表示条件に合う操作だけをボタンとして並べ、カーソルの少し上に小窓を出す
5. 次のいずれかで小窓を閉じる
   - ボタンを押して操作を実行した
   - 小窓の外でマウスボタンを押した
   - いずれかのキーを押した

小窓はフォーカスを奪わない（`NSPanel` の `.nonactivatingPanel`）。元のアプリの選択とフォーカスは保たれる。

小窓の見た目:

- 背景はすりガラス（`NSVisualEffectView` の `.popover`）。角の半径は 10pt、縁に 0.5pt の区切り線の色の線
- ボタンは枠なしのアイコンと文字（13pt のシステムフォント、アイコンと文字の間 4pt、上下 4pt・左右 10pt の余白）
- カーソルを乗せたボタンは、角丸 5pt のアクセント色の下地に白いアイコンと文字
- ボタンは押してその上で離したときだけ実行する
- 0.1 秒で薄い状態から表示する
- 色はシステムの色を使い、ライト／ダークモードとアクセントカラーの設定に従う

## 選択文字列の取得

次の順に試す。

1. アクセシビリティ API: フォーカス中の要素の `kAXSelectedTextAttribute` を読む
   - 読めたら、その値を選択文字列とする。空文字なら「選択なし」で終え、Cmd+C は送らない（警告音やファイルのコピーを防ぐ）
2. 1 で読めなかった場合（要素や属性を取得できない）: Cmd+C を送る
   - 送る前にクリップボードの全項目（全型のデータ）と `changeCount` を保存する
   - `changeCount` が変わるまで待つ。変わった後も、文字列が入るまで待つ（相手のアプリはクリアと書き込みを分けて行う）。待つのは合わせて最大 300ms
   - 文字列を読んだら、保存しておいた内容をクリップボードに書き戻す
   - コピーされた中身にファイル URL が含まれていたら（Finder でファイルを選んでいた）、「選択なし」とする
   - `changeCount` が変わらなければ「選択なし」とする

## 操作

操作は Swift コード内の配列で定義する。各操作は次を持つ。

- `id`: 変わらない識別子。並びと非表示の保存に使う
- `title`: ボタンの表示名
- `symbol`: ボタンのアイコン（SF Symbols の名前）
- `condition`: 表示条件の正規表現（`nil` なら常に表示）
- `perform`: 実行内容

| id | title | symbol | condition | 実行内容 |
|---|---|---|---|---|
| copy | コピー | `doc.on.doc` | なし | 選択文字列をクリップボードに書き込む |
| open | 開く | `arrow.up.right.square` | `^https?://\S+$` | 選択文字列を URL として既定のブラウザで開く |
| google | Google 検索 | `magnifyingglass` | なし | `https://www.google.com/search?q={text}` を開く |
| translate | 翻訳 | `translate` | `[A-Za-z]` | `https://translate.google.com/?sl=auto&tl=ja&text={text}` を開く |
| dictionary | 辞書 | `book` | `^\S{1,30}$` | `dict://{text}` を開く（macOS の辞書アプリ） |

- ボタンの並びと表示・非表示は設定画面で変えられる（下の「設定画面」）。変えていなければこの表の順で、すべて表示する
- 表示条件の判定前に、選択文字列の前後の空白・改行を取り除く
- `{text}` は選択文字列をパーセントエンコードして置き換える

## 設定画面

- メニューバーのメニューの「設定…」（⌘,）で開く。開くときに MiniClip を前面に出す
- macOS の環境設定の形にする。ツールバーにアイコン付きのタブを並べ（`NSTabViewController` の `.toolbar`、ウインドウの `toolbarStyle = .preference`）、各タブの中身は SwiftUI で作る。タブを切り替えるとウインドウの大きさが中身に合わせて変わる
- 「一般」タブ（`gearshape`）
  - ログイン時に起動: チェックボックス。`SMAppService.mainApp` の `register` / `unregister`。失敗したら理由を赤字で出す
  - アクセシビリティ: 許可済み／未許可の表示（1 秒ごとに確認）と、システム設定のアクセシビリティの画面を開くボタン
- 「操作」タブ（`list.bullet`）
  - すべての操作を一覧にする。各行はチェックボックス、アイコンと操作名、右端に並べ替えの目印（`line.3.horizontal`）
  - 行をドラッグして並べ替える（SwiftUI の `List` と `.onMove`）
  - チェックを外した操作は小窓に出さない
- 変えたらすぐ `UserDefaults` に保存し、次に小窓を出すときから使う
  - 並び: 操作の `id` の配列（キー `actionOrderIDs`）。保存にない操作（コードで足した）はコードの順で末尾に付け、保存にあっていまない `id` と重複は無視する
  - 非表示: 操作の `id` の配列（キー `hiddenActionIDs`）

## 権限

- アクセシビリティ権限が必要（マウス監視、選択文字列の読み取り、Cmd+C の送信）
- 起動時に `AXIsProcessTrustedWithOptions` で確認し、未許可ならシステムの許可ダイアログを出す
- 未許可の間は監視を始めず、メニューバーのアイコンを警告表示にする。許可されたら 1 秒ごとの確認で検知して監視を始める

## アプリの形

- Dock に出さない（`Info.plist` の `LSUIElement = true`）
- メニューバーにアイコンを置く。メニューは「設定…」と「終了」
- ログは `os.Logger`（subsystem: `dev.karur4n.miniclip`）に出し、Console.app で見る

## ファイル構成

```
miniclip/
├── Package.swift
├── Makefile
├── Resources/Info.plist
├── Sources/MiniClip/
│   ├── main.swift             起動、権限確認、メニューバー
│   ├── SelectionWatcher.swift マウス監視、選択操作の検知
│   ├── SelectionReader.swift  選択文字列の取得
│   ├── Actions.swift          操作の一覧、表示条件の判定、並びと非表示の保存
│   ├── SettingsView.swift     設定画面（タブのウインドウと各タブの SwiftUI）
│   └── PopupPanel.swift       小窓の表示と閉じる処理
└── Tests/MiniClipTests/
    └── ActionsTests.swift     表示条件の判定
```

## ビルドと署名

Xcode のプロジェクトファイルは使わない。Swift Package でビルドし、Makefile で `.app` を組み立てる。

- `make install`: `swift build -c release` → `MiniClip.app` を組み立てる → 署名 → `~/Applications/MiniClip.app` に置く
- 署名には自己署名のコード署名用証明書 `MiniClip Dev` を使う。署名が毎回同じなので、作り直してもアクセシビリティ権限は外れない
- 証明書はコマンドで作る（キーチェーンアクセスの証明書アシスタントは「指定された項目がキーチェーン内に見つかりませんでした」で失敗した）

```sh
openssl req -x509 -newkey rsa:2048 -nodes -keyout key.pem -out cert.pem -days 3650 \
  -subj "/CN=MiniClip Dev" \
  -addext "keyUsage=critical,digitalSignature" \
  -addext "extendedKeyUsage=critical,codeSigning" \
  -addext "basicConstraints=critical,CA:false"
openssl pkcs12 -export -legacy -inkey key.pem -in cert.pem -name "MiniClip Dev" -out miniclip.p12 -passout pass:miniclip
security import miniclip.p12 -k ~/Library/Keychains/login.keychain-db -P miniclip -T /usr/bin/codesign
security add-trusted-cert -p codeSign -k ~/Library/Keychains/login.keychain-db cert.pem
rm key.pem miniclip.p12 cert.pem
security find-identity -v -p codesigning   # "MiniClip Dev" が出れば完了
```

- `-legacy` は OpenSSL 3 で必要（macOS の `security import` が新しい暗号方式の p12 を読めない）
- `add-trusted-cert` で macOS のパスワード入力が出る
- ログイン時の自動起動は、システム設定の「ログイン項目」に手で追加する

## テスト

- 自動テスト: 各操作の表示条件の判定（URL、英字、1語の判定）、保存した並びの反映、非表示の除外
- 手動確認: テキストエディット、Chrome、Slack、ターミナルで、ドラッグ選択とダブルクリック選択のそれぞれについて、小窓が出ること、各操作が動くこと、クリップボードの元の内容が残ることを確かめる

## 対象外

- 貼り付け
- 設定ファイル
- アプリごとの除外
