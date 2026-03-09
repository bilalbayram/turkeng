import ProjectDescription

let project = Project(
    name: "turkeng",
    targets: [
        .target(
            name: "turkeng",
            destinations: .macOS,
            product: .app,
            bundleId: "com.bilalbayram.turkeng",
            deploymentTargets: .macOS("14.0"),
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
                "DEVELOPMENT_TEAM": "3N28465E96",
                "CODE_SIGN_STYLE": "Manual",
                "CODE_SIGN_IDENTITY": "Developer ID Application",
                "ENABLE_HARDENED_RUNTIME": "YES",
            ])
        ),
        .target(
            name: "turkengTests",
            destinations: .macOS,
            product: .unitTests,
            bundleId: "dev.tuist.turkengTests",
            infoPlist: .default,
            buildableFolders: [
                "turkeng/Tests"
            ],
            dependencies: [.target(name: "turkeng")]
        ),
    ]
)
