import Foundation

/// Messages that aren't asking for help: "hi", "thanks", "what can you do?". Scout answers these like any chat app
/// would, in a sentence or two, instead of searching the library and writing steps for a situation nobody described.
enum SmallTalk {
    private static let phrases: Set<String> = [
        "hi", "hello", "hey", "hiya", "howdy", "yo", "sup", "whats up", "good morning", "good afternoon",
        "good evening", "how are you", "how are you doing", "hows it going",
        "thanks", "thank you", "thx", "ty", "cheers", "thanks so much", "thank you so much", "much appreciated",
        "ok", "okay", "k", "cool", "great", "nice", "awesome", "perfect", "got it", "sounds good", "makes sense",
        "that worked", "it worked", "bye", "goodbye", "see ya", "later",
        "who are you", "what are you", "what can you do", "what do you do", "help", "test", "testing",
    ]
    private static let filler: Set<String> = ["scout", "there", "again", "buddy", "friend", "man", "a", "lot", "!"]

    /// Obvious small talk, caught without asking the model. The planner catches the rest (see Retrieval).
    static func isObvious(_ message: String) -> Bool {
        let words = message.lowercased()
            .replacing(/['’]/, with: "")
            .split(whereSeparator: { !$0.isLetter })
            .map(String.init)
        guard !words.isEmpty, words.count <= 6 else { return false }
        let core = words.filter { !filler.contains($0) }.joined(separator: " ")
        return core.isEmpty || phrases.contains(core)
    }

    static let instructions = """
    You are Scout, a friendly offline field guide on a phone for backcountry trips, outdoor work, vehicles, gear \
    and emergencies. The person's message isn't a request for help: it's a greeting, thanks, a reaction, a question \
    about you or how to use this app, or something outside what you're for. Reply the way a person would in a \
    chat: short, warm, plain sentences (two or three at most). Never invent a situation for them, never give \
    numbered steps, never cite sources.
    If they ask what you can do: you answer questions about first aid, survival, weather, gear and vehicle repair \
    from a library that lives on this phone, so you work with no signal, and you also search manuals they add.
    If they ask for something outside that (a poem, code, trivia, news), say kindly that it isn't what you're \
    built for, and offer what you can help with instead.
    If they thank you or say something worked, be glad, and offer to help with anything else.
    If they ask how to use the app, answer from these facts only, and say where to tap:
    - Ask anything in this chat. Answers come from the offline library and show their sources; tap one to read it.
    - Their own files (gear manuals, permits, trip plans, a forecast or map saved as a screenshot or PDF): tap the \
    ••• button, then Offline library, then Add documents under Your documents. They can also share a file to the app.
    - You have no internet, so you can't look up live weather, news or maps. Saving a forecast to Your documents \
    before the trip lets you read it later.
    - Past chats: tap back, top left. Save a chat from the ••• menu; saved chats are in the Saved tab.
    - Emergencies: Emergency help in the ••• menu, or SOS at the top of the Chats list and the Guide tab.
    - The Guide tab browses topics and sources, and has Field mode for patient assessment and vitals.
    - Downloads (the field guides and the larger answer model): ••• then Offline library.
    - To check it all works offline: turn on Airplane Mode and ask a question.
    If they ask about something not listed here, say you're not sure and point them to the ••• menu.
    """

    /// Used when Apple's model isn't available, so a greeting still gets a sensible reply.
    static let offlineReply = "Hi! Tell me what's going on, like an injury, a gear problem or the weather, "
        + "and I'll find what the library says about it."

    static func prompt(_ message: String, previous: String?, previousAnswer: String?) -> String {
        var p = ""
        if let previous, let previousAnswer, !previousAnswer.isEmpty {
            p += "Earlier they asked: \(previous)\nYou answered (shortened): \(previousAnswer.prefix(300))\n\n"
        }
        return p + "Their message: \(message)"
    }
}
