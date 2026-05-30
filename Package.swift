// swift-tools-version:5.3
import PackageDescription

let package = Package(
    name: "TreeSitterIrules",
    platforms: [.macOS(.v10_13), .iOS(.v11)],
    products: [
        .library(name: "TreeSitterIrules", targets: ["TreeSitterIrules"]),
    ],
    dependencies: [
        .package(url: "https://github.com/ChimeHQ/SwiftTreeSitter", from: "0.8.0"),
    ],
    targets: [
        .target(name: "TreeSitterIrules",
                path: ".",
                exclude: [
                    "Cargo.toml",
                    "Makefile",
                    "binding.gyp",
                    "bindings/c/tree-sitter-irules.pc.in",
                    "bindings/go",
                    "bindings/node",
                    "bindings/python",
                    "bindings/rust",
                    "bindings/swift/TreeSitterIrulesTests",
                    "prebuilds",
                    "grammar.js",
                    "package.json",
                    "package-lock.json",
                    "pyproject.toml",
                    "setup.py",
                    "test",
                    "examples",
                    ".editorconfig",
                    ".github",
                    ".gitignore",
                    ".gitattributes",
                    ".gitmodules",
                ],
                sources: [
                    "src/parser.c",
                    "src/scanner.c",
                ],
                resources: [
                    .copy("queries")
                ],
                // Single source of truth for the public header is
                // bindings/c/tree-sitter-irules.h. The Swift target
                // re-exports it via this publicHeadersPath instead
                // of carrying its own copy.
                publicHeadersPath: "bindings/c",
                cSettings: [.headerSearchPath("src")]),
        .testTarget(name: "TreeSitterIrulesTests",
                    dependencies: [
                        "SwiftTreeSitter",
                        "TreeSitterIrules",
                    ],
                    path: "bindings/swift/TreeSitterIrulesTests"),
    ],
    cLanguageStandard: .c11
)
