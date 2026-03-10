import ProjectDescription

let project = Project(
    name: "turkeng",
    targets: [
        .target(
            name: "turkeng",
            destinations: .macOS,
            product: .app,
            bundleId: "com.bilalbayram.turkeng",
            deploymentTargets: .macOS("15.0"),
            infoPlist: .extendingDefault(with: [
                "LSUIElement": .boolean(true),
            ]),
            buildableFolders: [
                "turkeng/Sources",
                "turkeng/Resources",
            ],
            entitlements: .file(path: "turkeng/turkeng.entitlements"),
            dependencies: [
                .external(name: "HotKey"),
            ],
            settings: .settings(base: [
                "CODE_SIGN_IDENTITY": "-",
                "ENABLE_HARDENED_RUNTIME": "YES",
                "MARKETING_VERSION": "1.3.0",
            ])
        ),
        .target(
            name: "turkengTests",
            destinations: .macOS,
            product: .unitTests,
            bundleId: "dev.tuist.turkengTests",
            deploymentTargets: .macOS("15.0"),
            infoPlist: .default,
            buildableFolders: [
                "turkeng/Tests"
            ],
            dependencies: [.target(name: "turkeng")]
        ),
    ]
)
