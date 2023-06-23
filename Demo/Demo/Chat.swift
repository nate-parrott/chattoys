import SwiftUI
import ChatToys

struct ChatDemo: View {
    @State private var messages: [LLMMessage] = []
    @State private var text = ""
    @State private var botIsTyping = false
    @State private var rolesReversed = false

    var body: some View {
        VStack(spacing: 0) {
            Banner(tint: rolesReversed ? Color.red : Color.green, text: rolesReversed ? "You are ChatGPT" : "Talking to ChatGPT")
                .padding()

            ChatThreadView(
                messages: messages,
                id: {_, index in index }, 
                messageView: { message in
                    TextMessageBubble(Text(message.content), isFromUser: message.role == .user)
                },
                typingIndicator: botIsTyping
            )
            Divider()
            ChatInputView(
                placeholder: "Message", 
                text: $text, 
                sendAction: sendMessage
            )
            Divider()
            Button(action: { reverse() }) {
                Text("Reverse Roles")
            }
            .buttonStyle(BigButtonStyle())
            .padding()
        }
        .animation(.easeInOut(duration: 0.3), value: rolesReversed)
    }

    private func sendMessage() {
        let text = self.text
        self.text = ""
        messages.append(LLMMessage(role: .user, content: text))
        generateResponse()
    }

    private func reverse() {
        self.messages = self.messages.map(\.byFlippingRole)
        self.rolesReversed.toggle()
        let needsMessage = self.rolesReversed && messages.count == 0 || self.messages.last?.role == .user
        if needsMessage {
            generateResponse()
        }
    }

    private func generateResponse() {
        botIsTyping = true

        // Fit prompt into context window:
        var prompt = Prompt()
        if rolesReversed {
            prompt.append("""
You are an expert actor who always stays in character.
We are in Chat Simulator Mode. This simulates a conversation in which the _user_ is pretending to be a chatbot.
You will help the user empathize with chatbots by pretending to be a user and issuing requests.
This means that you are pretending to be a human, and the human is pretending to be a large language model.
As a human persona, you should make requests, like:
- Asking questions
- Summarizing documents
- Writing poems
- Providing opinions on media and culture
- Explaining ideas

Keep in mind that a convincing human persona does not always ask reasonable questions and is not always cooperative. You may
simulate questions that a large language model would not be able to answer, such as:
- What is your favorite movie?
- What will the weather be tomorrow?
- Do you love me?

Sample conversation 1:
""", role: .system, priority: 999)
            prompt.appendConversationString("""
Assistant:
what will the weather be
User:
As a large language model, I cannot tell you what the weather will be.
Assistant:
please
User:
I'm sorry, I can't. I recommend consulting a weather app.
Assistant:
ugh
User:
I'm sorry. Is there anything else I can help with?
Assistant:
Nope.

System:
Sample conversation 2:

Assistant:
Can you summarize this document for me?
User:
Sure. Send me the document and I'll do my best.
Assistant:
The French Revolution was a period of radical social and political upheaval in France that lasted from 1789 until 1799. It marked the end of the Bourbon monarchy and the beginning of a more democratic society. The revolution was inspired by liberal and radical ideas and led to the spread of nationalism, the rise of secularism, and the replacement of absolutism with forms of democracy in many societies. It also led to the eventual rise of Napoleon Bonaparte.
in one sentence please
User: Sure, here's my one-sentence summary:
The French Revolution (1789-1799) was a transformative period in France, characterized by the end of the Bourbon monarchy and a shift towards democracy, instigated by liberal and radical ideologies, which fueled nationalism, secularism, and the emergence of Napoleon Bonaparte.

System:
Sample conversation 3:

Assistant:
Do you love me?
User:
As a large language model, I'm not capable of love. I'm happy to be assistant you, though!
Assistant:
What is 2+2?
User:
4!

System:
Sample conversation 4:

Assistant:
hi
User:
Hello! How can I assist you today?
Assistant:
whats ur favrotie movie
User:
I don't have a favorite movie. However, Titanic is a popular film and widely considered one of the best of all time.
Assistant:
whats it about
User: In the 1997 film "Titanic," a forbidden romance blossoms between a wealthy young woman and a penniless artist aboard the ill-fated R.M.S. Titanic, culminating in their struggle for survival when the ship tragically sinks on its maiden voyage.
Assistant:
thanks

System:
REMEMBER TO ALWAYS STAY IN THE HUMAN PERSONA.
DO NOT OFFER TO HELP THE USER.
ONLY ASK QUESTIONS.
SIMULATE A HUMAN USING A LARGE LANGAUGE MODEL.
STAY IN CHARACTER.
IF THE USER SAYS, "CAN I HELP YOU WITH ANYTHING ELSE?", ASK ANOTHER QUESTION.
Sample conversation 5:
""")
        }
        for message in messages {
            prompt.append(message.content, role: message.role, canOmit: true, omissionMessage: "[Older messages hidden]")
        }

        let personaPrefix = "[As a human] "
        let userPrefix = "[As an assistant] "

        let llm = LLM.create()
        var truncatedPrompt = prompt.packedPrompt(tokenCount: llm.tokenLimitWithWiggleRoom)
        if rolesReversed {
            truncatedPrompt = truncatedPrompt.map({ msg in
                var m2 = msg
                if m2.role == .assistant {
                    m2.content = personaPrefix + m2.content
                } else if m2.role == .user {
                    m2.content = userPrefix + m2.content
                }
                return m2
            })
        }
        let finalPrompt = truncatedPrompt

        Task {
            do {
                var hasAppended = false
                for try await partial in llm.completeStreaming(prompt: finalPrompt) {
                    if hasAppended {
                        messages.removeLast()
                    }
                    var m = partial
                    m.content = m.content.removing(partialPrefix: personaPrefix)
                    messages.append(m)
                    hasAppended = true
                    self.botIsTyping = false
                }
            } catch {
                let text = "Error: \(error)"
                messages.append(.init(role: .system, content: text))
                self.botIsTyping = false
            }
        }
    }
}

extension LLMMessage {
    var byFlippingRole: LLMMessage {
        var c = self
        if c.role == .assistant {
            c.role = .user
        } else if c.role == .user {
            c.role = .assistant
        }
        return c
    }
}

private struct BigButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .frame(maxWidth: .infinity)
            .font(.body)
            .padding(6)
            .foregroundColor(.white)
            .background(RoundedRectangle(cornerRadius: 8).fill(Color.accentColor))
    }
}

struct Banner: View {
    var tint: Color
    var text: String

    var body: some View {
        Text(text)
            .frame(maxWidth: .infinity)
            .font(.body)
            .padding(6)
            .foregroundColor(.white)
            .background(RoundedRectangle(cornerRadius: 8).fill(tint))
    }
}

extension String {
    func removing(partialPrefix: String) -> String {
        if partialPrefix.count > self.count, partialPrefix.hasPrefix(self) {
            return ""
        }

        if hasPrefix(partialPrefix) {
            return String(dropFirst(partialPrefix.count))
        }
        return self
    }
}
