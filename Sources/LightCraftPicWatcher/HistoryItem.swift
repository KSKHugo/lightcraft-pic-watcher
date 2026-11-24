import Foundation

/// One image the app handled, for the list in the menu.
struct HistoryItem: Identifiable, Codable, Equatable {
    enum Status: Codable, Equatable {
        case copying
        case copied
        case duplicate
        case failed(String)
    }

    var id: UUID
    var name: String
    var date: Date
    var status: Status
    /// The copy, or the file it duplicates.
    var file: URL?
    var format: String?
    var size: Int64?
    var trashedOriginal = false
}

extension Array where Element == HistoryItem {
    static func load() -> [HistoryItem] {
        guard let data = UserDefaults.standard.data(forKey: "history"),
              let items = try? JSONDecoder().decode([HistoryItem].self, from: data) else { return [] }
        return items.filter { $0.status != .copying }
    }

    func save() {
        let kept = filter { $0.status != .copying }.prefix(30)
        if let data = try? JSONEncoder().encode(Array(kept)) {
            UserDefaults.standard.set(data, forKey: "history")
        }
    }
}
