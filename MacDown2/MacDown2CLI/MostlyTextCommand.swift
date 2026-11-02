import CommandBridge
import CommandLineSupport
import Darwin
import Dispatch
import FileCore
import Foundation
import Synchronization

@main
struct MostlyTextCommand {
    static func main() async {
        let arguments = Array(CommandLine.arguments.dropFirst())
        let directory = FileManager.default.currentDirectoryPath
        let interactive = isatty(STDIN_FILENO) == 1
        let mode = await Task.detached { CommandLineArguments.parse(arguments) }.value
        let code: Int32
        switch mode {
        case let .display(text, value):
            write(text, error: value != 0)
            code = value
        case .formats:
            for format in FileFormatRegistry().formats {
                let extensions = format.extensions.joined(separator: ",")
                print("\(format.id)\textensions=\(extensions)\tpreview=\(format.previewCapability)")
            }
            code = 0
        case .version:
            print((try? EmbeddedCommandApplication.current().displayVersion) ?? CommandLineDiagnostics.unbundledVersion)
            code = 0
        case let .open(arguments):
            do {
                let plan = try arguments.inputPlan(workingDirectory: directory, stdinIsTerminal: interactive)
                code = await open(plan)
            } catch {
                write(CommandLineDiagnostics.invalidArguments, error: true)
                code = 2
            }
        }
        exit(code)
    }

    private static func open(_ plan: CommandLineInputPlan) async -> Int32 {
        let cancellation = Cancellation()
        let previousInterrupt = signal(SIGINT, SIG_IGN)
        let previousTerminate = signal(SIGTERM, SIG_IGN)
        let interrupt = DispatchSource.makeSignalSource(signal: SIGINT, queue: .global())
        let terminate = DispatchSource.makeSignalSource(signal: SIGTERM, queue: .global())
        interrupt.setEventHandler { cancellation.cancel() }
        terminate.setEventHandler { cancellation.cancel() }
        interrupt.resume(); terminate.resume()
        defer {
            interrupt.cancel(); terminate.cancel()
            signal(SIGINT, previousInterrupt); signal(SIGTERM, previousTerminate)
        }
        do {
            let outcome = try await Task.detached {
                let input = plan.readsStdin ? try CommandLineStdin.read(
                    descriptor: STDIN_FILENO, until: .now.advanced(by: .seconds(30)),
                    isCancelled: { cancellation.isCancelled }
                ) : nil
                let request = try plan.request(stdin: input)
                let app = try EmbeddedCommandApplication.current()
                let endpoint = try await CommandLineConnection.connect(application: app,
                                                                       until: .now.advanced(by: .seconds(10)),
                                                                       isCancelled: { cancellation.isCancelled })
                return try CommandClientExchange.execute(request, stdin: input, endpoint: endpoint,
                                                         inputDeadline: .now.advanced(by: .seconds(30)),
                                                         acceptanceDeadline: .now.advanced(by: .seconds(40)),
                                                         isCancelled: { cancellation.isCancelled })
            }.value
            return outcomeCode(outcome)
        } catch {
            return failureCode(error, cancelled: cancellation.isCancelled)
        }
    }

    private static func outcomeCode(_ outcome: CommandClientOutcome) -> Int32 {
        switch outcome {
        case let .finished(_, failures) where failures.isEmpty: return 0
        case .rejected(.unavailable):
            write(CommandLineDiagnostics.unavailable, error: true)
            return 5
        default:
            write(CommandLineDiagnostics.openFailed, error: true)
            return 4
        }
    }

    private static func failureCode(_ error: any Error, cancelled: Bool) -> Int32 {
        if cancelled || error is CancellationError || (error as? CommandSocketError) == .cancelled {
            return 130
        }
        if let failure = error as? CommandLineInputFailure {
            if failure == .cancelled {
                return 130
            }
            write(CommandLineDiagnostics.invalidInput, error: true)
            return 3
        }
        write(CommandLineDiagnostics.unavailable, error: true)
        return 5
    }

    private static func write(_ message: String, error: Bool) {
        let text = message.hasSuffix("\n") ? message : message + "\n"
        (error ? FileHandle.standardError : .standardOutput).write(Data(text.utf8))
    }
}

private final class Cancellation: Sendable {
    private let value = Mutex(false)
    var isCancelled: Bool {
        value.withLock { $0 }
    }

    func cancel() {
        value.withLock { $0 = true }
    }
}
