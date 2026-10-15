// swift-tools-version: 5.9
import PackageDescription
let package = Package(name: "OrbitConvert", platforms: [.macOS(.v13)], products: [.executable(name: "OrbitConvert", targets: ["OrbitConvert"])], targets: [.executableTarget(name: "OrbitConvert")])
