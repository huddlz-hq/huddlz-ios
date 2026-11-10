// swift-tools-version: 6.2
import Foundation
import PackageDescription

// `swift test` checks the store rules on the Mac in seconds, with no Simulator.
// The package compiles the app's own stores and clients in place: every Swift
// file under Huddlz/Huddlz that does not import SwiftUI. The Xcode project
// remains the only way to build the app and run its UI tests.

let appDirectory = "Huddlz/Huddlz"
let packageRoot = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
let appRoot = packageRoot.appendingPathComponent(appDirectory)

let storeSources: [String] = (FileManager.default.enumerator(atPath: appRoot.path)?.allObjects ?? [])
    .compactMap { $0 as? String }
    .filter { $0.hasSuffix(".swift") }
    .filter { path in
        let source = (try? String(contentsOf: appRoot.appendingPathComponent(path), encoding: .utf8)) ?? ""
        return !source.contains("import SwiftUI")
    }
    .sorted()

// The same language settings as the Xcode targets.
let approachableConcurrency: [SwiftSetting] = [
    .enableUpcomingFeature("NonisolatedNonsendingByDefault"),
    .enableUpcomingFeature("InferIsolatedConformances"),
    .enableUpcomingFeature("MemberImportVisibility"),
]

let package = Package(
    name: "Huddlz",
    platforms: [.macOS("26.0")],
    targets: [
        .target(
            name: "Huddlz",
            path: appDirectory,
            sources: storeSources,
            swiftSettings: approachableConcurrency + [.defaultIsolation(MainActor.self)]
        ),
        .testTarget(
            name: "HuddlzTests",
            dependencies: ["Huddlz"],
            path: "Huddlz/HuddlzTests",
            swiftSettings: approachableConcurrency
        ),
    ],
    swiftLanguageModes: [.v6]
)
