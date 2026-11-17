// swift-tools-version: 6.0
import PackageDescription

let package = Package(
  name: "Blip",
  platforms: [.macOS("26.0")],  // `.v26` needs tools-version 6.2; the string form is the 6.0 equivalent
  targets: [
    .target(name: "BlipCore"),
    .executableTarget(name: "Blip", dependencies: ["BlipCore"]),
    .executableTarget(name: "blip-snap", dependencies: ["BlipCore"], path: "Sources/BlipSnap"),
    .testTarget(name: "BlipCoreTests", dependencies: ["BlipCore"]),
  ],
  swiftLanguageModes: [.v5]
)
