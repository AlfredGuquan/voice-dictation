import AVFoundation
import Foundation

/// Records microphone audio to a WAV file (48kHz Int16 PCM).
final class AudioRecorder {
    private var engine: AVAudioEngine?
    private var audioFile: AVAudioFile?
    private var outputURL: URL?
    private(set) var isRecording = false

    /// Current audio level (0.0–1.0), updated on each buffer callback.
    /// Read from main thread for UI updates.
    var currentLevel: Float = 0.0

    /// History directory for saving audio on failure
    private var historyDir: URL {
        let dir = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".voice-dictation/history")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    /// Start recording. Returns the URL where audio will be saved.
    func startRecording() throws -> URL {
        let engine = AVAudioEngine()
        let inputNode = engine.inputNode
        let inputFormat = inputNode.outputFormat(forBus: 0)

        // Create temp file for recording
        let tempDir = FileManager.default.temporaryDirectory
        let filename = "dictation_\(Int(Date().timeIntervalSince1970)).wav"
        let url = tempDir.appendingPathComponent(filename)

        let settings: [String: Any] = [
            AVFormatIDKey: kAudioFormatLinearPCM,
            AVSampleRateKey: inputFormat.sampleRate,
            AVNumberOfChannelsKey: inputFormat.channelCount,
            AVLinearPCMBitDepthKey: 16,
            AVLinearPCMIsFloatKey: false,
            AVLinearPCMIsBigEndianKey: false,
        ]

        let file = try AVAudioFile(forWriting: url, settings: settings)

        inputNode.installTap(onBus: 0, bufferSize: 4096, format: inputFormat) {
            [weak self] buffer, _ in
            guard let self = self else { return }
            do {
                try file.write(from: buffer)
            } catch {
                print("[AudioRecorder] Write error: \(error)")
            }
            // Calculate RMS level
            if let channelData = buffer.floatChannelData?[0] {
                let frameCount = Int(buffer.frameLength)
                var sum: Float = 0
                for i in 0..<frameCount {
                    sum += channelData[i] * channelData[i]
                }
                let rms = sqrt(sum / Float(max(frameCount, 1)))
                // Normalize to 0–1 range (typical speech RMS is 0.01–0.3)
                let normalized = min(1.0, rms * 5.0)
                DispatchQueue.main.async {
                    self.currentLevel = normalized
                }
            }
        }

        try engine.start()

        self.engine = engine
        self.audioFile = file
        self.outputURL = url
        self.isRecording = true

        print("[AudioRecorder] Recording started: \(url.lastPathComponent)")
        return url
    }

    /// Stop recording and return the audio file URL.
    func stopRecording() -> URL? {
        guard isRecording else { return nil }
        isRecording = false
        currentLevel = 0

        engine?.inputNode.removeTap(onBus: 0)
        engine?.stop()
        audioFile = nil  // flush
        engine = nil

        let url = outputURL
        outputURL = nil

        if let url = url {
            let size = (try? FileManager.default.attributesOfItem(atPath: url.path)[.size] as? UInt64) ?? 0
            print("[AudioRecorder] Recording stopped: \(url.lastPathComponent) (\(size) bytes)")
        }
        return url
    }

    /// Cancel recording, discard the audio file.
    func cancelRecording() {
        guard isRecording else { return }
        let url = stopRecording()
        if let url = url {
            try? FileManager.default.removeItem(at: url)
            print("[AudioRecorder] Recording cancelled, file deleted")
        }
    }

    /// Move audio file to history directory (for retry on network failure).
    func moveToHistory(_ url: URL) -> URL? {
        let dest = historyDir.appendingPathComponent(url.lastPathComponent)
        do {
            try FileManager.default.moveItem(at: url, to: dest)
            print("[AudioRecorder] Audio saved to history: \(dest.path)")
            return dest
        } catch {
            print("[AudioRecorder] Failed to move to history: \(error)")
            return nil
        }
    }
}
