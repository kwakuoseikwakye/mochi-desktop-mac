import Foundation

/// Turns "seconds since last input" and the frontmost app into at most one action per
/// poll. It holds no clock and reads no system state, so tests drive it directly. Only
/// elapsed time and a bundle id go in: nothing typed is ever seen or stored.
public struct Awareness {
    public enum Activity: Equatable { case typing, present, away }
    public enum AppKind: Equatable { case editor, terminal, browser, other }
    public enum Action: Equatable { case react(String), doze, wake }

    public static let typingWindow = 2.0
    public static let awayAfter = 300.0

    public var enabled = true
    public private(set) var activity = Activity.present
    private var lastKind: AppKind?
    private var dozedByUs = false

    public init() {}

    // ponytail: starting list of bundle ids; anything unlisted is .other. Add ids as users report them.
    private static let editors: Set<String> = ["com.microsoft.VSCode", "com.apple.dt.Xcode", "dev.zed.Zed"]
    private static let editorPrefixes = ["com.jetbrains.", "com.sublimetext."]
    private static let terminals: Set<String> = ["com.apple.Terminal", "com.googlecode.iterm2", "com.mitchellh.ghostty",
                                                 "dev.warp.Warp-Stable", "net.kovidgoyal.kitty", "org.alacritty",
                                                 "com.github.wez.wezterm"]
    private static let browsers: Set<String> = ["com.apple.Safari", "com.google.Chrome", "org.mozilla.firefox",
                                                "company.thebrowser.Browser", "com.brave.Browser", "com.microsoft.edgemac"]

    public static func kind(of bundleId: String?) -> AppKind {
        guard let id = bundleId else { return .other }
        if editors.contains(id) || editorPrefixes.contains(where: id.hasPrefix) { return .editor }
        if terminals.contains(id) { return .terminal }
        if browsers.contains(id) { return .browser }
        return .other
    }

    /// `secondsSinceInput` is the shortest idle time across keyboard, mouse and scroll, so
    /// reading code with the mouse still counts as being present.
    public mutating func update(secondsSinceKey: Double, secondsSinceInput: Double,
                                frontmost: String?, sleeping: Bool) -> Action? {
        guard secondsSinceKey >= 0, secondsSinceInput >= 0 else { return nil }
        let idle = min(secondsSinceKey, secondsSinceInput)
        // Tracked even when switched off, so roaming can still stop while you type.
        activity = secondsSinceKey < Self.typingWindow ? .typing : idle >= Self.awayAfter ? .away : .present
        guard enabled else { return nil }

        var reaction: Action?
        let kind = Self.kind(of: frontmost)
        if let previous = lastKind, previous != kind, !sleeping {
            reaction = .react(kind == .editor || kind == .terminal ? "look" : "blink")
        }
        lastKind = kind

        // Only ever wake a Mochi that we put to sleep; a user's own sleep choice stays.
        if !sleeping { dozedByUs = false }
        if activity == .away, !sleeping { dozedByUs = true; return .doze }
        if activity != .away, sleeping, dozedByUs { dozedByUs = false; return .wake }
        return reaction
    }
}
