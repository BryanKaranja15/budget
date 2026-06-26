import Foundation

/// Screen 4 — Chat. Session-only message list (never persisted). The on-device LLM
/// (Phase 4) turns a question into query params; the app runs a parameterized query and
/// the LLM narrates the figure. This view-model is the UI contract for that exchange.
public struct ChatViewModel: Codable, Hashable, Sendable {
    public var messages: [Message]
    public init(messages: [Message] = []) { self.messages = messages }

    public struct Message: Codable, Hashable, Identifiable, Sendable {
        public var id: UUID
        public var role: Role
        /// What the user sees: the question, or the narrated answer.
        public var text: String
        /// For assistant turns, the exact figure SQLite returned (so the UI can render it
        /// distinctly and we can prove the model didn't invent it).
        public var figure: Money?

        public init(id: UUID = UUID(), role: Role, text: String, figure: Money? = nil) {
            self.id = id; self.role = role; self.text = text; self.figure = figure
        }
    }

    public enum Role: String, Codable, Sendable { case user, assistant }
}

public extension ChatViewModel {
    static var preview: ChatViewModel {
        ChatViewModel(messages: [
            .init(role: .user, text: "How much did I spend on food last month?"),
            .init(role: .assistant,
                  text: "You spent $103.35 on Food in May, $296.65 under your $400 budget.",
                  figure: Money(103.35, "USD"))
        ])
    }
}
