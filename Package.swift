// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "PortableDiskTest",
    platforms: [.macOS(.v14)],
    products: [.executable(name: "PortableDiskTest", targets: ["DiskApp"]),
               .executable(name: "DiskCoreChecks", targets: ["DiskCoreChecks"])],
    targets: [
        .target(name: "DiskCore"),
        .executableTarget(name: "DiskApp", dependencies: ["DiskCore"]),
        .executableTarget(name: "DiskCoreChecks", dependencies: ["DiskCore"], path: "Tests/DiskCoreTests", resources: [.copy("Fixtures")])
    ]
)
