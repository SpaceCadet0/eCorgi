// swift-tools-version: 5.10
import PackageDescription

let package = Package(
    name: "eCorgi",
    platforms: [.macOS(.v13)],
    targets: [
        // Вся логика живёт в библиотеке — так её можно покрыть unit-тестами.
        .target(
            name: "eCorgiKit",
            path: "Sources/eCorgiKit",
            // Черновики и запасные кадры лежат рядом с паком, но в сборку не идут.
            exclude: [
                "Resources/Sprites\u{00A0}— reserve",
                "Resources/run"
            ],
            resources: [
                .copy("Resources/Sprites"),
                .process("Resources/behaviors.json")
            ]
        ),
        // Тонкая обёртка-исполняемый файл, который потом кладётся в .app
        .executableTarget(
            name: "eCorgi",
            dependencies: ["eCorgiKit"],
            path: "Sources/eCorgi"
        ),
        .testTarget(
            name: "eCorgiKitTests",
            dependencies: ["eCorgiKit"],
            path: "Tests/eCorgiKitTests"
        )
    ]
)
