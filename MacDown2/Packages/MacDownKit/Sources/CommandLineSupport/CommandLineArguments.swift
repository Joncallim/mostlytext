import ArgumentParser
import CommandBridge
import Foundation

public struct CommandLineOpenArguments: Sendable, Equatable {
    public let files: [String]
    public let wait: Bool

    public func inputPlan(workingDirectory: String, stdinIsTerminal: Bool) throws -> CommandLineInputPlan {
        let explicit = files.contains("-")
        let paths = try CommandOpenRequest.resolve(files.filter { $0 != "-" }, relativeTo: workingDirectory)
        let readsStdin = explicit || (paths.isEmpty && !stdinIsTerminal)
        let descriptor = readsStdin ? try CommandStdinDescriptor(byteCount: CommandProtocol.maximumStdinBytes,
                                                                 sha256: String(repeating: "0", count: 64)) : nil
        _ = try CommandRequestCodec.encode(CommandOpenRequest(paths: paths, stdin: descriptor, wait: wait))
        return CommandLineInputPlan(paths: paths, wait: wait, readsStdin: readsStdin)
    }
}

public struct CommandLineInputPlan: Sendable, Equatable {
    public let paths: [String]
    public let wait: Bool
    public let readsStdin: Bool

    public func request(stdin: Data?) throws -> CommandOpenRequest {
        guard readsStdin == (stdin != nil) else { throw CommandProtocolError.invalidStdinDescriptor }
        return try CommandOpenRequest(
            paths: paths,
            stdin: stdin.map { try CommandStdinDescriptor(bytes: $0) },
            wait: wait
        )
    }
}

public enum CommandLineMode: Sendable, Equatable {
    case open(CommandLineOpenArguments)
    case formats
    case version
    case display(String, exitCode: Int32)
}

/// ArgumentParser stays behind this immutable interface. Parsing never reads
/// stdin, resolves an app, launches a process or opens a socket.
public enum CommandLineArguments {
    public static func parse(_ arguments: [String]) -> CommandLineMode {
        do {
            let command = try Root.parseAsRoot(arguments)
            if command is Formats {
                return .formats
            }
            if let command = command as? Open {
                if command.version {
                    return .version
                }
                return .open(CommandLineOpenArguments(files: command.files, wait: command.wait))
            }
            return .display(Root.helpMessage(), exitCode: 0)
        } catch {
            return .display(Root.fullMessage(for: error), exitCode: Root.exitCode(for: error).rawValue == 0 ? 0 : 2)
        }
    }

    private struct Root: ParsableCommand {
        static var configuration: CommandConfiguration {
            CommandConfiguration(commandName: "mostlytext", abstract: String(localized: "Open documents in MostlyText.",
                                                                             bundle: CommandLineLocalization.bundle),
                                 discussion: String(localized: "Use --version to show the enclosing app version.",
                                                    bundle: CommandLineLocalization.bundle),
                                 subcommands: [Open.self, Formats.self], defaultSubcommand: Open.self)
        }
    }

    private struct Open: ParsableCommand {
        static var configuration: CommandConfiguration {
            CommandConfiguration(commandName: "open", abstract: String(localized: "Open files or UTF-8 stdin.",
                                                                       bundle: CommandLineLocalization.bundle))
        }

        @Flag(help: ArgumentHelp(String(
            localized: "Wait until the opened documents close.",
            bundle: CommandLineLocalization.bundle
        ))) var wait = false
        @Flag(help: ArgumentHelp(String(
            localized: "Show the enclosing app version.",
            bundle: CommandLineLocalization.bundle
        ))) var version =
            false
        @Argument(help: ArgumentHelp(String(
            localized: "File paths; - reads stdin. Use -- before option-like paths.",
            bundle: CommandLineLocalization.bundle
        ))) var files: [String] = []

        mutating func validate() throws {
            guard files.filter({ $0 == "-" }).count <= 1 else {
                throw ValidationError(String(
                    localized: "Only one stdin stream may be requested.",
                    bundle: CommandLineLocalization.bundle
                ))
            }
            guard !version || (files.isEmpty && !wait) else {
                throw ValidationError(String(
                    localized: "Use --version on its own.",
                    bundle: CommandLineLocalization.bundle
                ))
            }
            guard files.filter({ $0 != "-" }).count <= CommandProtocol.maximumPaths else {
                throw ValidationError(String(localized: "At most 32 file paths may be opened in one request.",
                                             bundle: CommandLineLocalization.bundle))
            }
        }
    }

    private struct Formats: ParsableCommand {
        static var configuration: CommandConfiguration {
            CommandConfiguration(commandName: "formats", abstract: String(localized: "List supported file formats.",
                                                                          bundle: CommandLineLocalization.bundle))
        }
    }
}
