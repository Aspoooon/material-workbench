// swift-tools-version: 6.0
import PackageDescription
let package = Package(name: "MaterialWorkbench", platforms: [.macOS(.v14)], products: [.executable(name: "MaterialWorkbench", targets: ["MaterialWorkbench"])], targets: [.executableTarget(name: "MaterialWorkbench", swiftSettings: [.swiftLanguageMode(.v5)])])
