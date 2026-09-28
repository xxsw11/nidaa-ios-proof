// swift-tools-version: 6.1
import PackageDescription

let package = Package(
    name: "NidaaIntegration",
    platforms: [.iOS(.v16), .macOS(.v13)],
    products: [
        .library(name: "NidaaIntegration", targets: ["NidaaIntegration"]),
        .executable(name: "IntegrationTrialCLI", targets: ["IntegrationTrialCLI"])
    ],
    dependencies: [.package(url: "https://github.com/supabase/supabase-swift.git", exact: "2.55.2")],
    targets: [
        .target(name: "NidaaIntegration", dependencies: [.product(name: "Auth", package: "supabase-swift")]),
        .executableTarget(name: "IntegrationTrialCLI", dependencies: ["NidaaIntegration"]),
        .testTarget(name: "NidaaIntegrationTests", dependencies: ["NidaaIntegration"])
    ]
)
