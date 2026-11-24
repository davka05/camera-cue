import SwiftUI

@main
struct CameraCueApp: App {
    @StateObject private var controller = PrompterController()

    var body: some Scene {
        Window("Camera Cue", id: "script") {
            EditorView(controller: controller)
        }
        .defaultSize(width: 750, height: 565)
        .windowStyle(.hiddenTitleBar)
        .windowResizability(.contentMinSize)
        .commands {
            CommandMenu("Prompter") {
                Button(controller.primaryTitle) { controller.primaryAction() }
                    .keyboardShortcut(.return, modifiers: [.command, .shift])
                    .disabled(!controller.canStart)

                Button("Previous cue") { controller.move(by: -1) }
                    .keyboardShortcut(.upArrow, modifiers: [.command, .option])
                    .disabled(!controller.canMoveBackward)

                Button("Next cue") { controller.move(by: 1) }
                    .keyboardShortcut(.downArrow, modifiers: [.command, .option])
                    .disabled(!controller.canMoveForward)

                Button("Close prompter") { controller.close() }
                    .disabled(controller.mode == .idle)
            }
        }
    }
}

@MainActor
final class PrompterController: ObservableObject {
    enum Language: String, CaseIterable, Identifiable {
        case english = "en-US"
        case korean = "ko-KR"

        var id: String { rawValue }

        var label: String {
            switch self {
            case .english: "English"
            case .korean: "한국어"
            }
        }

        var sample: String {
            switch self {
            case .english:
                """
                Thanks for making time today.
                I’ll start with a quick update.
                Then we can talk through the next steps.

                We finished the first draft this week.
                I’d like to hear your feedback.
                What should we adjust before Friday?
                """
            case .korean:
                """
                오늘 시간 내주셔서 감사합니다.
                먼저 진행 상황을 간단히 말씀드릴게요.
                그리고 다음 단계를 함께 정리하겠습니다.

                이번 주에 첫 번째 초안을 완성했습니다.
                여러분의 의견을 듣고 싶습니다.
                금요일 전까지 무엇을 수정하면 좋을까요?
                """
            }
        }
    }

    enum Mode {
        case idle
        case preview
        case listening
        case paused
    }

    @Published var script: String {
        didSet { UserDefaults.standard.set(script, forKey: "script") }
    }

    @Published var language: Language {
        didSet { UserDefaults.standard.set(language.rawValue, forKey: "language") }
    }

    @Published private(set) var mode: Mode = .idle
    @Published private(set) var status = "Ready"
    @Published private(set) var cueIndex = 0
    @Published private(set) var cueCount = 0

    private let panel = PrompterPanel()
    private let speech = LiveSpeech()
    private var follower = ScriptFollower(lines: [])

    init() {
        let savedLanguage = UserDefaults.standard.string(forKey: "language")
        let language = savedLanguage.flatMap(Language.init(rawValue:)) ?? .english
        self.language = language
        self.script = UserDefaults.standard.string(forKey: "script") ?? language.sample
    }

    var canStart: Bool { script.contains { !$0.isWhitespace } }
    var canMoveBackward: Bool { mode != .idle && cueIndex > 0 }
    var canMoveForward: Bool { mode != .idle && cueIndex + 1 < cueCount }

    var primaryTitle: String {
        switch mode {
        case .idle, .preview: "Start listening"
        case .listening: "Pause listening"
        case .paused: "Resume listening"
        }
    }

    func loadSample(_ language: Language) {
        guard mode == .idle else { return }
        self.language = language
        script = language.sample
    }

    func preview() {
        guard mode == .idle, prepareScript() else { return }
        mode = .preview
        status = "Preview · microphone off"
        refreshPanel()
    }

    func primaryAction() {
        switch mode {
        case .idle:
            guard prepareScript() else { return }
            startListening()
        case .preview, .paused:
            startListening()
        case .listening:
            speech.stop()
            follower.accept("", isFinal: true)
            mode = .paused
            status = "Paused · microphone off"
            refreshPanel()
        }
    }

    func move(by offset: Int) {
        guard mode != .idle else { return }
        follower.move(by: offset)
        refreshPanel()
    }

    func close() {
        speech.stop()
        panel.dismiss()
        follower = ScriptFollower(lines: [])
        mode = .idle
        status = "Ready"
        cueIndex = 0
        cueCount = 0
    }

    private func prepareScript() -> Bool {
        let lines = ScriptLayout.cues(in: script)
        guard !lines.isEmpty else { return false }
        follower = ScriptFollower(lines: lines)
        return true
    }

    private func startListening() {
        mode = .listening
        status = "Starting microphone…"
        refreshPanel()
        speech.start(localeIdentifier: language.rawValue, onPhrase: { [weak self] text, isFinal in
            guard let self, self.mode == .listening else { return }
            let previousProgress = self.follower.progress
            let moved = self.follower.accept(text, isFinal: isFinal)
            if moved || self.follower.progress != previousProgress {
                self.refreshPanel()
            }
        }, onStatus: { [weak self] status in
            guard let self, self.mode == .listening else { return }
            self.status = status
            if status.hasPrefix("Speech unavailable:") || status.hasPrefix("Speech stopped:") {
                self.follower.accept("", isFinal: true)
                self.mode = .paused
                self.refreshPanel()
            }
        })
    }

    private func refreshPanel() {
        let lines = follower.lines
        let index = follower.index
        guard lines.indices.contains(index) else { return }
        if index != cueIndex { cueIndex = index }
        if lines.count != cueCount { cueCount = lines.count }
        panel.present(
            lines: lines,
            index: index,
            progress: follower.progress,
            isPaused: mode != .listening,
            onMove: { [weak self] offset in self?.move(by: offset) },
            onTogglePause: { [weak self] in self?.primaryAction() },
            onClose: { [weak self] in self?.close() }
        )
    }
}

enum ScriptLayout {
    static func cues(in script: String) -> [String] {
        script.split(whereSeparator: \.isNewline).flatMap { line in
            line.split(whereSeparator: \.isWhitespace)
                .flatMap(splitLongWord)
                .reduce(into: [Cue]()) { cues, word in
                    let width = measure(word)
                    if let last = cues.last, last.width + width + 1 <= 43 {
                        cues[cues.count - 1].text += " " + word
                        cues[cues.count - 1].width += width + 1
                    } else {
                        cues.append(Cue(text: word, width: width))
                    }
                }
                .map(\.text)
        }
    }

    private struct Cue {
        var text: String
        var width: Int
    }

    private static func splitLongWord(_ word: Substring) -> [String] {
        if measure(word) <= 43 { return [String(word)] }
        var parts = [String]()
        var part = ""
        var width = 0
        for character in word {
            let characterWidth = measure(CollectionOfOne(character))
            if width + characterWidth > 43 {
                parts.append(part)
                part = ""
                width = 0
            }
            part.append(character)
            width += characterWidth
        }
        parts.append(part)
        return parts
    }

    private static func measure<S: Sequence>(_ characters: S) -> Int where S.Element == Character {
        characters.reduce(0) { total, character in
            let wide = character.unicodeScalars.contains {
                (0x1100...0x11FF).contains($0.value) ||
                (0x3130...0x318F).contains($0.value) ||
                (0xAC00...0xD7FF).contains($0.value)
            }
            return total + (wide ? 2 : 1)
        }
    }
}
