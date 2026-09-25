import AppKit
import os

struct Action {
    let id: String
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
        Action(id: "copy", title: "コピー", condition: nil) { text in
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(text, forType: .string)
        },
        Action(id: "open", title: "開く", condition: #"^https?://\S+$"#) { text in
            open(text)
        },
        Action(id: "google", title: "Google 検索", condition: nil) { text in
            open(fill("https://www.google.com/search?q={text}", with: text))
        },
        Action(id: "translate", title: "翻訳", condition: "[A-Za-z]") { text in
            open(fill("https://translate.google.com/?sl=auto&tl=ja&text={text}", with: text))
        },
        Action(id: "dictionary", title: "辞書", condition: #"^\S{1,30}$"#) { text in
            open(fill("dict://{text}", with: text))
        },
    ]

    private static let orderKey = "actionOrderIDs"
    private static let hiddenKey = "hiddenActionIDs"

    static var savedOrder: [String] {
        get { UserDefaults.standard.stringArray(forKey: orderKey) ?? [] }
        set { UserDefaults.standard.set(newValue, forKey: orderKey) }
    }

    static var hiddenIDs: Set<String> {
        get { Set(UserDefaults.standard.stringArray(forKey: hiddenKey) ?? []) }
        set { UserDefaults.standard.set(newValue.sorted(), forKey: hiddenKey) }
    }

    static func menu(
        for raw: String,
        order: [String] = savedOrder,
        hidden: Set<String> = hiddenIDs
    ) -> (text: String, actions: [Action])? {
        let text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return nil }
        let actions = ordered(all, by: order).filter { !hidden.contains($0.id) && $0.matches(text) }
        return (text, actions)
    }

    static func ordered(_ actions: [Action], by saved: [String]) -> [Action] {
        var result: [Action] = []
        for id in saved where !result.contains(where: { $0.id == id }) {
            if let action = actions.first(where: { $0.id == id }) {
                result.append(action)
            }
        }
        let rest = actions.filter { action in !result.contains { $0.id == action.id } }
        return result + rest
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
