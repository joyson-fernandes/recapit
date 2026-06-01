import Foundation

enum ActionItemExtractor {
    struct Decoded: Decodable {
        struct Item: Decodable {
            let task: String
            let owner: String?
            let due: String?
        }
        let action_items: [Item]
    }

    static func parse(_ json: String) -> [ActionItem]? {
        guard let data = json.data(using: .utf8) else { return nil }
        guard let decoded = try? JSONDecoder().decode(Decoded.self, from: data) else { return nil }
        return decoded.action_items.enumerated().map { (idx, item) in
            ActionItem(
                id: nil,
                meetingId: "",
                task: item.task,
                owner: item.owner,
                due: item.due,
                done: false,
                position: idx
            )
        }
    }
}
