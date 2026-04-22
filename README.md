# BigBroTest

A minimal iOS test app demonstrating the [BigBroKit](https://github.com/nagata-inc/bigbro-kit) framework. Connects to a BigBro Mac on the local network and provides a simple chat interface backed by the Mac's local LLM.

## Purpose

This app exists to validate the end-to-end BigBro flow:

1. Bonjour discovery of a BigBro Mac
2. Pairing with manual approval on the Mac
3. Streaming chat via the Mac's LLM backend

It is not intended for distribution — use BigBroKit in your own app instead.

## Requirements

- iOS 17.0+
- A Mac running the [BigBro](https://github.com/nagata-inc/bigbro) app on the same local network
- An LLM backend running on that Mac (e.g. Ollama, LM Studio)

## Setup

1. Open `bigbro-test.xcodeproj` in Xcode
2. Add the BigBroKit framework under **Frameworks, Libraries, and Embedded Content** (or via Swift Package Manager pointing at the local `bigbro-kit` repo)
3. Select your device as the run destination and build

The app's `Info.plist` must include (already configured):
```xml
<key>NSLocalNetworkUsageDescription</key>
<string>Used to discover and connect to BigBro on your local network.</string>
<key>NSBonjourServices</key>
<array>
    <string>_bigbro._tcp</string>
</array>
```
