// swift-tools-version: 5.9
import PackageDescription
let package = Package(name: "Mafus", platforms: [.macOS(.v14)], products: [.executable(name: "Mafus", targets: ["Mafus"])], targets: [.executableTarget(name: "Mafus")])
