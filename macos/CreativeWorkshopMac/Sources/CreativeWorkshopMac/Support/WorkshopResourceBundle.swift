import Foundation

/// Resolves SwiftPM resources from the conventional signed-app location while
/// retaining Bundle.module compatibility for command-line builds and tests.
enum WorkshopResourceBundle {
    static let bundle: Bundle = {
        let bundleName = "CreativeWorkshopMac_CreativeWorkshopMac.bundle"

        if let resourceURL = Bundle.main.resourceURL {
            let packagedURL = resourceURL.appendingPathComponent(bundleName, isDirectory: true)
            if let packagedBundle = Bundle(url: packagedURL) {
                return packagedBundle
            }
        }

        return .module
    }()
}
