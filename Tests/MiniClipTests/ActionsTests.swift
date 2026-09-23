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
