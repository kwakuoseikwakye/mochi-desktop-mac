import Foundation

public enum EmoteCategory: String, CaseIterable, Equatable {
    case all = "All"
    case reactions = "Reactions"
    case work = "Work"
    case moods = "Moods"
    case playful = "Playful"
}

public struct Emote: Identifiable, Equatable {
    public let id: String
    public let displayName: String
    public let category: EmoteCategory
    public let isLooping: Bool
    public let playbackDuration: TimeInterval

    public init(id: String, displayName: String, category: EmoteCategory, isLooping: Bool, playbackDuration: TimeInterval = 6.0) {
        self.id = id
        self.displayName = displayName
        self.category = category
        self.isLooping = isLooping
        self.playbackDuration = playbackDuration
    }
}

public struct EmoteCatalog {
    public static let all: [Emote] = [
        Emote(id: "this_is_fine", displayName: "This Is Fine", category: .moods, isLooping: true, playbackDuration: 6.0),
        Emote(id: "table_flip", displayName: "Table Flip", category: .reactions, isLooping: false, playbackDuration: 2.0),
        Emote(id: "coffee", displayName: "Coffee Break", category: .work, isLooping: true, playbackDuration: 6.0),
        Emote(id: "dance", displayName: "Happy Dance", category: .playful, isLooping: true, playbackDuration: 6.0),
        Emote(id: "party", displayName: "Party Time", category: .playful, isLooping: true, playbackDuration: 6.0),
        Emote(id: "popcorn", displayName: "Popcorn", category: .playful, isLooping: true, playbackDuration: 6.0),
        Emote(id: "rage", displayName: "Rage", category: .reactions, isLooping: true, playbackDuration: 5.0),
        Emote(id: "crying", displayName: "Crying", category: .moods, isLooping: true, playbackDuration: 5.0),
        Emote(id: "sparkle", displayName: "Sparkle", category: .playful, isLooping: true, playbackDuration: 5.0),
        Emote(id: "salute", displayName: "Salute", category: .reactions, isLooping: false, playbackDuration: 2.5),
        Emote(id: "shrug", displayName: "Shrug", category: .reactions, isLooping: false, playbackDuration: 2.5),
        Emote(id: "headpat", displayName: "Headpat", category: .playful, isLooping: true, playbackDuration: 5.0),
        Emote(id: "terminal", displayName: "Terminal", category: .work, isLooping: false, playbackDuration: 3.0),
        Emote(id: "typing", displayName: "Fast Typing", category: .work, isLooping: true, playbackDuration: 6.0),
        Emote(id: "vs_code", displayName: "VS Code", category: .work, isLooping: false, playbackDuration: 2.5),
        Emote(id: "watch", displayName: "Looking at Watch", category: .work, isLooping: true, playbackDuration: 5.0),
        Emote(id: "dizzy", displayName: "Dizzy", category: .moods, isLooping: true, playbackDuration: 5.0),
        Emote(id: "explode", displayName: "Mind Blown", category: .reactions, isLooping: false, playbackDuration: 2.5),
        Emote(id: "firework", displayName: "Celebration", category: .playful, isLooping: false, playbackDuration: 3.0),
        Emote(id: "wave", displayName: "Friendly Wave", category: .reactions, isLooping: false, playbackDuration: 2.5)
    ]

    public static func search(query: String, category: EmoteCategory) -> [Emote] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return all.filter { emote in
            let matchesCategory = (category == .all) || (emote.category == category)
            let matchesQuery = trimmed.isEmpty || emote.displayName.lowercased().contains(trimmed) || emote.id.lowercased().contains(trimmed)
            return matchesCategory && matchesQuery
        }
    }
}
