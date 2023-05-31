# ChatToys

a simple library for playing with LLMs in Swift

![Image of a chat thread](Images/Chat.png)

### Features

- A single async/await API for generating chat completions using the OpenAI or Anthropic APIs
- Utilities for generating structured data from chat completions using JSON
- A `Prompt`-packer for dealing with situations where you have more data than fits in the context window. Declare priorities for different messages in the prompt, then drop or truncate lower-priority messages to fit within the token limit.
- A simple drop-in SwiftUI chat view for iOS and macOS

### Usage

See `Demo/Chat.swift`

