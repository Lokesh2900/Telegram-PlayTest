import Foundation

struct PlayableMedia: Identifiable, Hashable {
    let id: Int64
    let fileId: Int
    let title: String
    let durationSeconds: Int?
}

struct ChatSummary: Identifiable, Hashable {
    let id: Int64
    let title: String
}
