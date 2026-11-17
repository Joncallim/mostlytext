import SwiftUI

struct UpdateCommands: Commands {
    @ObservedObject var updateChannel: UpdateChannelController

    var body: some Commands {
        CommandGroup(after: .appInfo) {
            Button("Check for Updates…") { updateChannel.checkForUpdates() }
                .disabled(!updateChannel.canCheckForUpdates)
        }
    }
}
