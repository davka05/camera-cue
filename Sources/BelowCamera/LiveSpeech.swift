import AVFoundation
import Foundation
import Speech

@MainActor
final class LiveSpeech {
    private let audioSink = AudioRequestSink()
    private var engine: AVAudioEngine?
    private var recognizer: SFSpeechRecognizer?
    private var recognition: SFSpeechRecognitionTask?
    private var startup: Task<Void, Never>?
    private var restart: Task<Void, Never>?
    private var sessionID = UUID()
    private var recognitionID = UUID()
    private var retriedFailure = false
    private var onPhrase: ((String, Bool) -> Void)?
    private var onStatus: ((String) -> Void)?

    func start(
        localeIdentifier: String,
        onPhrase: @escaping (String, Bool) -> Void,
        onStatus: @escaping (String) -> Void
    ) {
        stop()
        self.onPhrase = onPhrase
        self.onStatus = onStatus
        retriedFailure = false

        let session = sessionID
        onStatus("Checking microphone and speech permissions…")
        startup = Task { [weak self] in
            await self?.prepare(localeIdentifier: localeIdentifier, session: session)
        }
    }

    func stop() {
        sessionID = UUID()
        startup?.cancel()
        startup = nil
        endRequest()
        if let engine {
            engine.stop()
            engine.inputNode.removeTap(onBus: 0)
        }
        engine = nil
        recognizer = nil
        onPhrase = nil
        onStatus = nil
    }

    private func prepare(localeIdentifier: String, session: UUID) async {
        guard session == sessionID else { return }
        let microphoneAllowed = await AVCaptureDevice.requestAccess(for: .audio)
        guard session == sessionID else { return }
        guard microphoneAllowed else {
            fail("Speech unavailable: allow microphone access in System Settings › Privacy & Security.")
            return
        }

        let authorization = await withCheckedContinuation { continuation in
            SFSpeechRecognizer.requestAuthorization { continuation.resume(returning: $0) }
        }
        guard session == sessionID else { return }
        guard authorization == .authorized else {
            fail("Speech unavailable: allow Speech Recognition in System Settings › Privacy & Security.")
            return
        }

        let locale = Locale(identifier: localeIdentifier)
        guard let recognizer = SFSpeechRecognizer(locale: locale), recognizer.isAvailable else {
            fail("Speech unavailable: this recognition language is unavailable on the Mac right now.")
            return
        }
        self.recognizer = recognizer

        let engine = AVAudioEngine()
        let input = engine.inputNode
        let format = input.outputFormat(forBus: 0)
        guard format.channelCount > 0, format.sampleRate > 0 else {
            fail("Speech unavailable: select a working microphone in System Settings › Sound.")
            return
        }
        let sink = audioSink
        input.installTap(onBus: 0, bufferSize: 1_024, format: nil) { buffer, _ in
            sink.append(buffer)
        }
        self.engine = engine
        engine.prepare()
        do {
            try engine.start()
        } catch {
            fail("Speech unavailable: could not start the microphone. \(error.localizedDescription)")
            return
        }

        beginRequest(session: session)
        onStatus?(recognizer.supportsOnDeviceRecognition
                  ? "Listening on this Mac"
                  : "Listening with Apple’s speech service")
    }

    private func beginRequest(session: UUID) {
        guard session == sessionID, let recognizer else { return }
        let request = SFSpeechAudioBufferRecognitionRequest()
        request.shouldReportPartialResults = true
        request.requiresOnDeviceRecognition = recognizer.supportsOnDeviceRecognition
        request.taskHint = .dictation
        audioSink.replace(with: request)

        let requestID = recognitionID
        recognition = recognizer.recognitionTask(with: request) { [weak self] result, error in
            let text = result?.bestTranscription.formattedString
            let isFinal = result?.isFinal ?? false
            let failure = error.map { $0 as NSError }
            let noSpeech = failure?.domain == "kAFAssistantErrorDomain" && failure?.code == 1110
            let message = failure?.localizedDescription
            DispatchQueue.main.async { [weak self] in
                self?.receive(text, isFinal: isFinal, failure: message, noSpeech: noSpeech,
                              session: session, requestID: requestID)
            }
        }

        // Each request has a one-minute limit. Keep the microphone open across requests.
        restart = Task { [weak self] in
            try? await Task.sleep(for: .seconds(54))
            guard !Task.isCancelled else { return }
            self?.renew(session: session, requestID: requestID, after: .milliseconds(250),
                        resetTranscript: true)
        }
    }

    private func receive(
        _ text: String?, isFinal: Bool, failure: String?, noSpeech: Bool,
        session: UUID, requestID: UUID
    ) {
        guard session == sessionID, requestID == recognitionID else { return }
        if let text {
            if !text.isEmpty { retriedFailure = false }
            onPhrase?(text, isFinal)
        }
        guard session == sessionID, requestID == recognitionID else { return }
        if isFinal || noSpeech {
            renew(session: session, requestID: requestID, after: .milliseconds(200),
                  resetTranscript: !isFinal || text == nil)
        } else if let failure {
            guard !retriedFailure, recognizer?.isAvailable == true else {
                fail("Speech stopped: \(failure)")
                return
            }
            retriedFailure = true
            renew(session: session, requestID: requestID, after: .milliseconds(700),
                  resetTranscript: true)
        }
    }

    private func renew(session: UUID, requestID: UUID, after delay: Duration, resetTranscript: Bool) {
        guard session == sessionID, requestID == recognitionID else { return }
        endRequest()
        if resetTranscript { onPhrase?("", true) }
        guard session == sessionID else { return }
        restart = Task { [weak self] in
            try? await Task.sleep(for: delay)
            guard !Task.isCancelled else { return }
            self?.beginRequest(session: session)
        }
    }

    private func endRequest() {
        recognitionID = UUID()
        restart?.cancel()
        restart = nil
        audioSink.replace(with: nil)
        recognition?.cancel()
        recognition = nil
    }

    private func fail(_ message: String) {
        let status = onStatus
        stop()
        status?(message)
    }
}

// The audio tap and the main actor share the active request. End the old request
// under the same lock used to append so audio cannot arrive after endAudio().
private final class AudioRequestSink: @unchecked Sendable {
    private let lock = NSLock()
    private var request: SFSpeechAudioBufferRecognitionRequest?

    func replace(with newRequest: SFSpeechAudioBufferRecognitionRequest?) {
        lock.withLock {
            request?.endAudio()
            request = newRequest
        }
    }

    func append(_ buffer: AVAudioPCMBuffer) {
        lock.withLock { request?.append(buffer) }
    }
}
