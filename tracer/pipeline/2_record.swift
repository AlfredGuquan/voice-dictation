// Tracer: Microphone recording + audio encoding
// Proves: AVAudioEngine can capture mic and save to m4a/wav
import AVFoundation
import Foundation

let engine = AVAudioEngine()
let inputNode = engine.inputNode
let bus = 0
let inputFormat = inputNode.outputFormat(forBus: bus)

print("[RECORD] Input format: \(inputFormat)")

// Record to a WAV file (Whisper accepts wav)
let outputURL = URL(fileURLWithPath: "/Users/alfred.gu/Desktop/2-projects/voice-dictation/tracer/pipeline/test_recording.wav")

// Use a buffer to collect audio
let bufferSize: AVAudioFrameCount = 4096
var audioFile: AVAudioFile?

do {
    // Create output file with input format settings for WAV
    let settings: [String: Any] = [
        AVFormatIDKey: kAudioFormatLinearPCM,
        AVSampleRateKey: inputFormat.sampleRate,
        AVNumberOfChannelsKey: inputFormat.channelCount,
        AVLinearPCMBitDepthKey: 16,
        AVLinearPCMIsFloatKey: false,
        AVLinearPCMIsBigEndianKey: false
    ]
    audioFile = try AVAudioFile(forWriting: outputURL, settings: settings)
    print("[RECORD] Output file created: \(outputURL.path)")
} catch {
    print("[RECORD] ERROR creating file: \(error)")
    exit(1)
}

inputNode.installTap(onBus: bus, bufferSize: bufferSize, format: inputFormat) { buffer, time in
    do {
        try audioFile?.write(from: buffer)
    } catch {
        print("[RECORD] Write error: \(error)")
    }
}

do {
    try engine.start()
    print("[RECORD] Recording for 3 seconds... Speak now!")
} catch {
    print("[RECORD] ERROR starting engine: \(error)")
    exit(1)
}

// Record for 3 seconds
Thread.sleep(forTimeInterval: 3)

inputNode.removeTap(onBus: bus)
engine.stop()
audioFile = nil // flush

// Check file
let fileManager = FileManager.default
if fileManager.fileExists(atPath: outputURL.path) {
    let attrs = try! fileManager.attributesOfItem(atPath: outputURL.path)
    let size = attrs[.size] as! UInt64
    print("[RECORD] SUCCESS: Recorded file size = \(size) bytes")
    if size > 1000 {
        print("[RECORD] File looks valid (>1KB)")
    } else {
        print("[RECORD] WARNING: File very small, may be silence")
    }
} else {
    print("[RECORD] ERROR: Output file not found")
}
