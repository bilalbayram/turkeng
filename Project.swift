import ProjectDescription

let project = Project(
    name: "turkeng",
    targets: [
        .target(
            name: "turkeng",
            destinations: .macOS,
            product: .app,
            bundleId: "dev.tuist.turkeng",
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
            ]
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
