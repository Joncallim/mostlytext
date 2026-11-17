import Themes

extension AppDelegate {
    func makeThemeCatalog(controller: ThemeController, args: [String]) -> ThemeCatalogModel {
        let location: ThemeCatalogModel.Location = if args
            .contains("-UITesting") {
            .isolatedSession(Self.sessionDirectory(from: args))
        } else if let locations = startup.locations {
            .managedInstallation(locations.dataDirectory)
        } else {
            .applicationSupport
        }
        return ThemeCatalogModel(controller: controller, location: location)
    }
}
