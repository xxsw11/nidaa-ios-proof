// swift-tools-version: 5.9
import PackageDescription
let package = Package(
    name: "ProofCore",
    platforms: [.iOS(.v16), .macOS(.v13)],
    products: [.library(name: "ProofCore", targets: ["ProofCore"])],
    targets: [.target(name: "ProofCore"), .testTarget(name: "ProofCoreTests", dependencies: ["ProofCore"])]
)
