import AVFoundation
import Foundation

/// Records microphone audio to a 16kHz mono Int16 WAV file.
/// Whisper-1 internally resamples to 16k mono anyway — downsampling at the
/// source cuts upload size ~10x vs native 48kHz stereo Float32, which is the
/// dominant component of asr latency for cloud transcription.
final class AudioRecorder {
    /// Target format for Whisper upload. Mono int16 PCM @ 16kHz.
    private static let uploadFormat: AVAudioFormat = {
        AVAudioFormat(
            commonFormat: .pcmFormatInt16,
            sampleRate: 16000,
            channels: 1,
            interleaved: true
        )!
    }()

    private var engine: AVAudioEngine?
    private var audioFile: AVAudioFile?
    private var converter: AVAudioConverter?
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
        let outputFormat = Self.uploadFormat

        guard let converter = AVAudioConverter(from: inputFormat, to: outputFormat) else {
            throw NSError(
                domain: "AudioRecorder",
                code: -1,
                userInfo: [NSLocalizedDescriptionKey: "Failed to create audio converter"]
            )
        }

        // Create temp file for recording
        let tempDir = FileManager.default.temporaryDirectory
        let filename = "dictation_\(Int(Date().timeIntervalSince1970)).wav"
        let url = tempDir.appendingPathComponent(filename)

        // file settings derive from outputFormat (16k mono int16), so the
        // resulting WAV is exactly what we'll upload — no extra transcode.
        let file = try AVAudioFile(forWriting: url, settings: outputFormat.settings)

        // Upper bound on converted frames per tap buffer; ceil + a few-frame
        // slack covers resampler edge cases without truncation.
        let ratio = outputFormat.sampleRate / inputFormat.sampleRate

        inputNode.installTap(onBus: 0, bufferSize: 4096, format: inputFormat) {
            [weak self] buffer, _ in
            guard let self = self else { return }

            // RMS level on the original (Float) buffer — cheaper than reading
            // back the converted Int16 frames, and the meter reads the same.
            if let channelData = buffer.floatChannelData?[0] {
                let frameCount = Int(buffer.frameLength)
                var sum: Float = 0
                for i in 0..<frameCount {
                    sum += channelData[i] * channelData[i]
                }
                let rms = sqrt(sum / Float(max(frameCount, 1)))
                let normalized = min(1.0, rms * 5.0)
                DispatchQueue.main.async {
                    self.currentLevel = normalized
                }
            }

            // Convert this tap buffer to 16kHz mono Int16 and write to disk.
            let outFrameCapacity = AVAudioFrameCount(
                ceil(Double(buffer.frameLength) * ratio) + 32
            )
            guard let outBuffer = AVAudioPCMBuffer(
                pcmFormat: outputFormat,
                frameCapacity: outFrameCapacity
            ) else { return }

            var fed = false
            var convertError: NSError?
            let status = converter.convert(to: outBuffer, error: &convertError) {
                _, outStatus in
                if fed {
                    outStatus.pointee = .noDataNow
                    return nil
                }
                fed = true
                outStatus.pointee = .haveData
                return buffer
            }

            if status == .error {
                print("[AudioRecorder] Convert error: \(convertError?.localizedDescription ?? "unknown")")
                return
            }
            guard outBuffer.frameLength > 0 else { return }

            do {
                try file.write(from: outBuffer)
            } catch {
                print("[AudioRecorder] Write error: \(error)")
            }
        }

        try engine.start()

        self.engine = engine
        self.audioFile = file
        self.converter = converter
        self.outputURL = url
        self.isRecording = true

        print("[AudioRecorder] Recording started: \(url.lastPathComponent) (input=\(Int(inputFormat.sampleRate))Hz \(inputFormat.channelCount)ch → output=16kHz mono)")
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
        converter = nil

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
