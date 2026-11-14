import Foundation
import AVFoundation
import SwiftUI

/// Nimmt Audio auf – entweder direkt in der App oder ferngesteuert von der Tastatur.
/// Für die Tastatur läuft eine „Diktat-Sitzung“: Die App hält die Audio-Engine im
/// Hintergrund aktiv, damit die Tastatur jederzeit eine Aufnahme starten kann.
@MainActor
final class DictationService: ObservableObject {
    static let shared = DictationService()

    enum State: Equatable {
        case idle
        case recording
        case processing
        case done(String)
        case failed(String)
    }

    @Published var state: State = .idle {
        didSet { writeStatus() }
    }
    @Published var sessionActive = false
    @Published var level: Float = 0
    @Published var sessionEndsAt: Date?
    @Published var lastTranscript: String = ""

    private let engine = AVAudioEngine()
    private let writer = AudioWriter()
    private var isWriting = false
    private var recordStart: Date?
    private var sessionTimer: Timer?
    private var fromKeyboard = false
    private var lastLevelWrite = Date.distantPast
    private let client = OpenAIClient()
    private let store = SharedStore.shared

    private init() {
        let n = DarwinNotifier.shared
        n.observe(.ping) { [weak self] in
            guard let self, self.sessionActive else { return }
            DarwinNotifier.shared.post(.pong)
        }
        n.observe(.start) { [weak self] in
            guard let self, self.sessionActive else { return }
            self.fromKeyboard = true
            self.beginRecording()
        }
        n.observe(.stop) { [weak self] in
            guard let self, self.fromKeyboard else { return }
            self.finishRecording()
        }
        n.observe(.cancel) { [weak self] in
            guard let self else { return }
            self.cancelRecording()
        }
    }

    // MARK: - Berechtigung

    func requestPermission() async -> Bool {
        await AVAudioApplication.requestRecordPermission()
    }

    // MARK: - Sitzung für die Tastatur

    /// Startet die Hintergrund-Sitzung. Optional sofort mit Aufnahme.
    func startKeyboardSession(recordImmediately: Bool) async {
        guard await requestPermission() else {
            state = .failed("Kein Mikrofonzugriff. Bitte in den Einstellungen erlauben.")
            DictationFiles.write("Kein Mikrofonzugriff für Tastatur KI erlaubt.", to: DictationFiles.error)
            DarwinNotifier.shared.post(.failed)
            return
        }
        do {
            try startEngine()
            sessionActive = true
            extendSession()
            DarwinNotifier.shared.post(.pong)
            if recordImmediately {
                fromKeyboard = true
                beginRecording()
            }
        } catch {
            state = .failed("Audio konnte nicht gestartet werden: \(error.localizedDescription)")
        }
    }

    func endSession() {
        sessionTimer?.invalidate()
        sessionTimer = nil
        sessionEndsAt = nil
        if isWriting { cancelRecording() }
        stopEngine()
        sessionActive = false
        state = .idle
        DictationFiles.write("ended", to: DictationFiles.status)
        DarwinNotifier.shared.post(.sessionEnded)
    }

    private func extendSession() {
        sessionTimer?.invalidate()
        let minutes = max(1, store.dictationSessionMinutes)
        let end = Date().addingTimeInterval(TimeInterval(minutes * 60))
        sessionEndsAt = end
        sessionTimer = Timer.scheduledTimer(withTimeInterval: 5, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard let self else { return }
                if self.isWriting { self.sessionEndsAt = Date().addingTimeInterval(TimeInterval(minutes * 60)); return }
                if let e = self.sessionEndsAt, Date() > e { self.endSession() }
            }
        }
    }

    // MARK: - Direktes Diktat in der App

    func toggleInAppRecording() async {
        if isWriting {
            finishRecording()
            return
        }
        guard await requestPermission() else {
            state = .failed("Kein Mikrofonzugriff. Bitte in den iOS-Einstellungen erlauben.")
            return
        }
        do {
            if !engine.isRunning { try startEngine() }
            fromKeyboard = false
            beginRecording()
        } catch {
            state = .failed(error.localizedDescription)
        }
    }

    var isRecording: Bool { isWriting }

    // MARK: - Engine

    private func startEngine() throws {
        let session = AVAudioSession.sharedInstance()
        try session.setCategory(.playAndRecord, mode: .spokenAudio, options: [.mixWithOthers, .defaultToSpeaker, .allowBluetooth])
        try session.setActive(true, options: [])
        guard !engine.isRunning else { return }
        let input = engine.inputNode
        let format = input.outputFormat(forBus: 0)
        input.removeTap(onBus: 0)
        let writer = self.writer
        input.installTap(onBus: 0, bufferSize: 2048, format: format) { [weak self] buffer, _ in
            writer.write(buffer)
            self?.handle(buffer: buffer)
        }
        engine.prepare()
        try engine.start()
    }

    private func stopEngine() {
        engine.inputNode.removeTap(onBus: 0)
        engine.stop()
        try? AVAudioSession.sharedInstance().setActive(false, options: [.notifyOthersOnDeactivation])
    }

    nonisolated private func handle(buffer: AVAudioPCMBuffer) {
        // Pegel berechnen
        var peak: Float = 0
        if let data = buffer.floatChannelData?[0] {
            let n = Int(buffer.frameLength)
            var sum: Float = 0
            for i in stride(from: 0, to: n, by: 4) { sum += data[i] * data[i] }
            peak = min(1, sqrt(sum / Float(max(1, n / 4))) * 6)
        }
        Task { @MainActor in
            self.level = peak
            if self.isWriting {
                if self.fromKeyboard, Date().timeIntervalSince(self.lastLevelWrite) > 0.1 {
                    self.lastLevelWrite = Date()
                    DictationFiles.write(String(format: "%.3f", peak), to: DictationFiles.level)
                }
            }
        }
    }

    // MARK: - Aufnahme

    private func beginRecording() {
        guard !isWriting else { return }
        let format = engine.inputNode.outputFormat(forBus: 0)
        try? FileManager.default.removeItem(at: DictationFiles.audio)
        try? FileManager.default.removeItem(at: DictationFiles.result)
        try? FileManager.default.removeItem(at: DictationFiles.error)
        let settings: [String: Any] = [
            AVFormatIDKey: kAudioFormatMPEG4AAC,
            AVSampleRateKey: format.sampleRate,
            AVNumberOfChannelsKey: format.channelCount,
            AVEncoderBitRateKey: 64000,
        ]
        do {
            let file = try AVAudioFile(forWriting: DictationFiles.audio, settings: settings, commonFormat: format.commonFormat, interleaved: format.isInterleaved)
            writer.begin(file)
            isWriting = true
            recordStart = Date()
            state = .recording
            DarwinNotifier.shared.post(.recording)
        } catch {
            fail("Aufnahme konnte nicht gestartet werden: \(error.localizedDescription)")
        }
    }

    private func cancelRecording() {
        guard isWriting else { return }
        isWriting = false
        writer.end()
        state = .idle
        if !sessionActive { stopEngine() }
    }

    private func finishRecording() {
        guard isWriting else { return }
        isWriting = false
        writer.end() // schließt die Datei
        let duration = Date().timeIntervalSince(recordStart ?? Date())
        if !sessionActive { stopEngine() }
        guard duration > 0.4 else {
            fail("Aufnahme zu kurz.")
            return
        }
        state = .processing
        DarwinNotifier.shared.post(.processing)
        let keyboard = fromKeyboard
        Task {
            do {
                var text = try await client.transcribe(fileURL: DictationFiles.audio)
                if store.dictationCleanup, !text.isEmpty {
                    text = (try? await client.polishDictation(text)) ?? text
                }
                lastTranscript = text
                if keyboard { DictationFiles.write(text, to: DictationFiles.result) }
                state = .done(text)
                store.incrementStat("dictations")
                store.incrementStat("dictationSeconds", by: Int(duration))
                if keyboard { DarwinNotifier.shared.post(.result) }
            } catch {
                fail(error.localizedDescription)
            }
        }
    }

    /// Schreibt den Status in den gemeinsamen Container, damit die Tastatur ihn auch
    /// nach einer Unterbrechung zuverlässig lesen kann.
    private func writeStatus() {
        let value: String
        switch state {
        case .idle: value = "idle"
        case .recording: value = "recording"
        case .processing: value = "processing"
        case .done: value = "done:" + UUID().uuidString
        case .failed: value = "failed:" + UUID().uuidString
        }
        DictationFiles.write(value, to: DictationFiles.status)
    }

    private func fail(_ message: String) {
        if fromKeyboard { DictationFiles.write(message, to: DictationFiles.error) }
        state = .failed(message)
        if fromKeyboard { DarwinNotifier.shared.post(.failed) }
    }
}

/// Thread-sicherer Schreiber für den Audio-Tap.
final class AudioWriter: @unchecked Sendable {
    private var file: AVAudioFile?
    private let lock = NSLock()

    func begin(_ file: AVAudioFile) {
        lock.lock(); self.file = file; lock.unlock()
    }

    func end() {
        lock.lock(); file = nil; lock.unlock()
    }

    func write(_ buffer: AVAudioPCMBuffer) {
        lock.lock(); defer { lock.unlock() }
        try? file?.write(from: buffer)
    }
}
