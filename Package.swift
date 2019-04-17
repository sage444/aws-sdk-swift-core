// swift-tools-version:4.1
import PackageDescription

let package = Package(
    name: "AWSSDKSwiftCore",
    products: [
        .library(name: "AWSSDKSwiftCore", targets: ["AWSSDKSwiftCore"])
    ],
    dependencies: [
        .package(url: "https://github.com/apple/swift-nio.git", .upToNextMajor(from: "1.13.2")),
        .package(url: "https://github.com/apple/swift-nio-ssl.git", .upToNextMajor(from: "1.3.2")),
        .package(url: "https://github.com/Yasumoto/HypertextApplicationLanguage.git", .upToNextMajor(from: "1.1.0")),
        .package(url: "https://github.com/PerfectlySoft/Perfect-INIParser.git", .upToNextMajor(from: "3.0.0")),
    ],
    targets: [
        .target(
            name: "AWSSDKSwiftCore",
            dependencies: [
                "HypertextApplicationLanguage",
                "NIO",
                "NIOHTTP1",
                "NIOOpenSSL",
                "NIOFoundationCompat",
                "INIParser"
            ]),
        .testTarget(name: "AWSSDKSwiftCoreTests", dependencies: ["AWSSDKSwiftCore"])
    ]
)
