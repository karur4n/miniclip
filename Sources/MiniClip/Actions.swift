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
