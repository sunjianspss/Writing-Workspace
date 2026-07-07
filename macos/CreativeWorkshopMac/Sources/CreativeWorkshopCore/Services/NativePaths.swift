import Foundation

package enum NativePaths {
    package static let appSupportName = "CreativeWorkshopMac"

    package static var applicationSupportDirectory: URL {
        get throws {
            let base = try FileManager.default.url(
                for: .applicationSupportDirectory,
                in: .userDomainMask,
                appropriateFor: nil,
                create: true
            )
            let directory = base.appending(path: appSupportName, directoryHint: .isDirectory)
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            return directory
        }
    }

    package static var databaseURL: URL {
        get throws {
            let supportURL = try applicationSupportDirectory
            return supportURL.appending(path: "creative_workshop.sqlite3")
        }
    }
}
