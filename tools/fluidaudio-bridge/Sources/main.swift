import Foundation
import FluidAudio
import ArgumentParser
import AVFoundation

@main
struct FluidAudioBridge: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "fluidaudio-bridge",
        abstract: "Transcribe audio using FluidAudio (local, on-device)"
    )

    @Argument(help: "Path to the input audio file (WAV format)")
    var inputFile: String

    @Option(name: .shortAndLong, help: "Output format: json or text")
    var format: String = "json"

    func run() async throws {
        guard FileManager.default.fileExists(atPath: inputFile) else {
            printErr("Error: file not found: \(inputFile)")
            throw ExitCode.failure
        }

        do {
            let converter = AudioConverter()
            let samples = try converter.resampleAudioFile(path: inputFile)

            let asrManager = AsrManager(config: .default)
            let models = try await AsrModels.downloadAndLoad(version: .v3)
            try await asrManager.initialize(models: models)

            let start = CFAbsoluteTimeGetCurrent()
            let result = try await asrManager.transcribe(samples)
            let elapsed = CFAbsoluteTimeGetCurrent() - start

            if format.lowercased() == "json" {
                let output: [String: Any] = [
                    "ok": true,
                    "transcript": result.text,
                    "transcription_time": elapsed,
                ]
                let jsonData = try JSONSerialization.data(withJSONObject: output, options: [])
                if let jsonString = String(data: jsonData, encoding: .utf8) {
                    print(jsonString)
                }
            } else {
                print(result.text)
            }
        } catch {
            printErr("Error: \(error)")
            throw ExitCode.failure
        }
    }

    private func printErr(_ msg: String) {
        var stderr = FileHandle.standardError
        Swift.print(msg, to: &stderr)
    }
}

extension FileHandle: @retroactive TextOutputStream {
    public func write(_ string: String) {
        write(Data(string.utf8))
    }
}
