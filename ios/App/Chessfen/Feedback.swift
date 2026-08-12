import AVFoundation
import ChessfenKit
import Foundation
import UIKit

/// What a move sounds and feels like.
///
/// The sounds are synthesised here rather than shipped as files. Partly because the app has
/// no business downloading anything — that is the whole premise — and partly because what a
/// piece landing on a board sounds like is a short noise burst with a low body under it, and
/// that is four lines of arithmetic. It also means the sounds scale, mix and never go out of
/// sync with a bundle.
///
/// Everything here fails quietly. An app that cannot make a noise is an app that cannot make
/// a noise; it is not an app that should refuse to play chess.
@MainActor final class Feedback {
    static let shared = Feedback()

    enum Sound: Hashable, CaseIterable {
        /// A piece landing on wood.
        case move
        /// A piece taking another: the same landing with a crack in front of it.
        case capture
        /// A check — a rising two-tone, because it is a warning rather than an event.
        case check
        case gameOver
        /// A tap that could not be played.
        case refused
    }

    /// Off is a setting people genuinely want, and it belongs somewhere that survives a
    /// launch.
    var isSoundOn: Bool {
        didSet { UserDefaults.standard.set(isSoundOn, forKey: Self.soundKey) }
    }

    private static let soundKey = "chessfen.sound"

    private let engine = AVAudioEngine()
    /// Three players so that two sounds in quick succession overlap instead of cutting each
    /// other off — which is what happens when the engine plays itself.
    private var players: [AVAudioPlayerNode] = []
    private var next = 0
    private var buffers: [Sound: AVAudioPCMBuffer] = [:]
    private var isRunning = false
    private let impact = UIImpactFeedbackGenerator(style: .light)
    private let heavyImpact = UIImpactFeedbackGenerator(style: .medium)

    private init() {
        if UserDefaults.standard.object(forKey: Self.soundKey) == nil {
            isSoundOn = true
        } else {
            isSoundOn = UserDefaults.standard.bool(forKey: Self.soundKey)
        }
    }

    // ------------------------------------------------------------------ using

    /// The sound a move makes, from what the move did. Checkmate is the end of the game
    /// rather than a check, so it says so.
    func play(_ move: Move, outcome: Outcome) {
        if outcome.isOver {
            play(move.isCapture ? .capture : .move)
            play(.gameOver)
        } else if move.givesCheck {
            play(move.isCapture ? .capture : .move)
            play(.check)
        } else {
            play(move.isCapture ? .capture : .move)
        }
    }

    func play(_ sound: Sound) {
        touch(sound)
        guard isSoundOn else { return }
        start()
        guard isRunning, let buffer = buffers[sound], !players.isEmpty else { return }
        let player = players[next % players.count]
        next += 1
        player.stop()
        player.scheduleBuffer(buffer, at: nil, options: [], completionHandler: nil)
        player.play()
    }

    /// The haptics, which are the half of this that works with the ringer off.
    private func touch(_ sound: Sound) {
        switch sound {
        case .move: impact.impactOccurred(intensity: 0.7)
        case .capture, .gameOver: heavyImpact.impactOccurred()
        case .check: heavyImpact.impactOccurred(intensity: 0.8)
        case .refused: impact.impactOccurred(intensity: 0.4)
        }
    }

    /// Started on first use rather than at launch: nothing should be holding an audio
    /// session open for a game that has not begun.
    private func start() {
        guard !isRunning else { return }
        // Ambient, mixing with others: a chess app has no business stopping anybody's music,
        // and it should go quiet when the ringer switch says so.
        let session = AVAudioSession.sharedInstance()
        try? session.setCategory(.ambient, mode: .default, options: [.mixWithOthers])
        try? session.setActive(true)

        let format = AVAudioFormat(standardFormatWithSampleRate: Self.sampleRate, channels: 1)
        guard let format else { return }

        for sound in Sound.allCases {
            buffers[sound] = Self.render(sound, format: format)
        }
        for _ in 0..<3 {
            let player = AVAudioPlayerNode()
            engine.attach(player)
            engine.connect(player, to: engine.mainMixerNode, format: format)
            players.append(player)
        }
        engine.prepare()
        do {
            try engine.start()
            isRunning = true
        } catch {
            players = []
            buffers = [:]
        }
    }

    // --------------------------------------------------------------- synthesis

    private static let sampleRate = 44100.0

    private static func render(_ sound: Sound, format: AVAudioFormat) -> AVAudioPCMBuffer? {
        let seconds: Double =
            switch sound {
            case .move: 0.10
            case .capture: 0.18
            case .check: 0.24
            case .gameOver: 0.60
            case .refused: 0.13
            }
        let frames = AVAudioFrameCount(seconds * sampleRate)
        guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frames),
              let samples = buffer.floatChannelData?[0]
        else { return nil }
        buffer.frameLength = frames

        // A fixed generator rather than a random one: the same tap should always make the
        // same noise, and a sound that varies run to run is a sound that cannot be judged.
        var seed: UInt64 = 0x2545_F491_4F6C_DD1D
        func noise() -> Double {
            seed = seed &* 6_364_136_223_846_793_005 &+ 1_442_695_040_888_963_407
            return Double(Int64(bitPattern: seed >> 11)) / Double(1 << 52) - 1
        }

        for frame in 0..<Int(frames) {
            let t = Double(frame) / sampleRate
            var value: Double
            switch sound {
            case .move:
                // The click of contact, then the wood under it.
                value = noise() * exp(-t * 260) * 0.55 + sin(2 * .pi * 190 * t) * exp(-t * 55) * 0.45
            case .capture:
                let crack = noise() * exp(-t * 110) * 0.6
                let body = sin(2 * .pi * 120 * t) * exp(-t * 26) * 0.5
                // The taken piece leaving, then the taking piece landing.
                let landing = t > 0.05 ? noise() * exp(-(t - 0.05) * 220) * 0.45 : 0
                value = crack + body + landing
            case .check:
                let first = t < 0.1 ? sin(2 * .pi * 880 * t) * exp(-t * 20) : 0
                let second = t >= 0.1 ? sin(2 * .pi * 1320 * (t - 0.1)) * exp(-(t - 0.1) * 16) : 0
                value = (first + second) * 0.32
            case .gameOver:
                // Three notes, falling: a game ending is not a fanfare.
                let step = 0.18
                let index = min(2, Int(t / step))
                let pitch = [660.0, 550.0, 440.0][index]
                let local = t - Double(index) * step
                value = sin(2 * .pi * pitch * local) * exp(-local * 9) * 0.28
            case .refused:
                value = sin(2 * .pi * 110 * t) * exp(-t * 24) * 0.35
            }
            // A short fade at the very end, so stopping the buffer never clicks.
            let tail = seconds - t
            if tail < 0.004 { value *= tail / 0.004 }
            samples[frame] = Float(max(-1, min(1, value)))
        }
        return buffer
    }
}
