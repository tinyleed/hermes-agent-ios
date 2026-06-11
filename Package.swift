// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "HermesAgentIOS",
    platforms: [
        .macOS(.v14),
        .iOS(.v17)
    ],
    products: [
        .library(name: "HermesAgentCore", targets: ["HermesAgentCore"])
    ],
    targets: [
        .target(name: "HermesAgentCore"),
        .executableTarget(name: "HermesAgentCoreContractTest", dependencies: ["HermesAgentCore"])
    ]
)
