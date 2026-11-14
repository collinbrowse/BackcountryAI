import Foundation
import FoundationModels

/// A short name for a chat, like "Sprained ankle on the trail", shown as the chat's title and in the Chats list.
/// Apple's model writes it once, after the first answer; without the model it's the question's first words.
enum ChatTopic {
    /// Two lines of the top bar's title font fit about this many characters without being cut off.
    static let maxLength = 40

    static let instructions = """
    You name chats. Reply with a title of 2 to 5 words for the person's question, the way a chat app titles a \
    conversation: its main subject, like "Sprained ankle on the trail", "Snowmobile oil change" or "Treating \
    stream water". No quotes, no ending punctuation, nothing else.
    """

    static func make(for question: String, model: SystemLanguageModel) async -> String {
        let session = LanguageModelSession(model: model, instructions: instructions)
        let reply = try? await session.respond(to: "Question: \(question)",
                                               options: GenerationOptions(temperature: 0, maximumResponseTokens: 20))
        let title = reply.map { trim($0.content) } ?? ""
        return title.isEmpty ? fallback(question) : title
    }

    /// The question's opening words, when the model can't name it.
    static func fallback(_ question: String) -> String {
        trim(question.split(separator: " ").prefix(6).joined(separator: " "))
    }

    /// One line of plain text, at most `maxLength` characters, cut at a word so it never ends mid-word.
    static func trim(_ text: String) -> String {
        var s = text.split(whereSeparator: \.isNewline).first.map(String.init) ?? ""
        s = s.trimmingCharacters(in: CharacterSet(charactersIn: "\"'“”*#.:!?").union(.whitespaces))
        s = s.replacing(/^(?i:title)\s*:\s*/, with: "")
        guard s.count > maxLength else { return s.prefix(1).uppercased() + s.dropFirst() }
        var cut = ""
        for word in s.split(separator: " ") {
            let next = cut.isEmpty ? String(word) : cut + " " + word
            if next.count > maxLength { break }
            cut = next
        }
        if cut.isEmpty { cut = String(s.prefix(maxLength)) }
        cut = cut.trimmingCharacters(in: CharacterSet(charactersIn: ",;:-–— "))
        return cut.prefix(1).uppercased() + cut.dropFirst()
    }
}
