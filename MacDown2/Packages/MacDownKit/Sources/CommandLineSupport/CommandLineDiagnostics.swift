import Foundation

public enum CommandLineDiagnostics {
    public static var invalidArguments: String {
        String(
            localized: "Invalid command-line arguments. Use --help for usage.",
            bundle: CommandLineLocalization.bundle
        )
    }

    public static var invalidInput: String {
        String(localized: "Unable to read bounded UTF-8 stdin.", bundle: CommandLineLocalization.bundle)
    }

    public static var unavailable: String {
        String(
            localized: "MostlyText is unavailable. Use the command embedded in the installed app.",
            bundle: CommandLineLocalization.bundle
        )
    }

    public static var openFailed: String {
        String(localized: "One or more request targets could not be opened.", bundle: CommandLineLocalization.bundle)
    }

    public static var unbundledVersion: String {
        String(localized: "macdown2 (unbundled development build)", bundle: CommandLineLocalization.bundle)
    }
}
