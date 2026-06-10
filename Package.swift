// swift-tools-version: 5.9
// The swift-tools-version declares the minimum version of Swift required to build this package.

import Foundation
import PackageDescription

let package = Package(
    name: "MarkdownEditor",
    platforms: [
        .iOS(.v17)
    ],
    products: [
        // Products define the executables and libraries a package produces, making them visible to other packages.
        .library(
            name: "MarkdownEditor",
            targets: ["MarkdownEditor"]),
    ],
    dependencies: [
        // Pinned to the fork's 0.3.2 tag by revision (an exact-version pin is impossible
        // while the fork depends on swift-markdown@main). Bump deliberately: tag the fork,
        // then update this SHA. For local two-repo iteration, drag ../lexical-ios into the
        // Xcode workspace as a local package override; this pin only governs fresh resolves.
        .package(url: "https://github.com/jcfontecha/lexical-ios.git", revision: "1ac66f000fcb4cdbd508ba3b6c18ff67b748dd49")
    ],
    targets: [
        // Targets are the basic building blocks of a package, defining a module or a test suite.
        // Targets can depend on other targets in this package and products from dependencies.
        .target(
            name: "MarkdownEditor",
            dependencies: [
                .product(name: "Lexical", package: "lexical-ios", condition: .when(platforms: [.iOS])),
                .product(name: "LexicalListPlugin", package: "lexical-ios", condition: .when(platforms: [.iOS])),
                .product(name: "LexicalLinkPlugin", package: "lexical-ios", condition: .when(platforms: [.iOS])),
                .product(name: "LexicalMarkdown", package: "lexical-ios", condition: .when(platforms: [.iOS]))
            ]
        ),
        .testTarget(
            name: "MarkdownEditorTests",
            dependencies: ["MarkdownEditor"]
        ),
    ]
)
