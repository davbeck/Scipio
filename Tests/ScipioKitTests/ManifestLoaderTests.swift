import Foundation
import Testing
@testable @_spi(Internals) import ScipioKit

struct ManifestLoaderTests {
    // A minimal dump-package payload whose top-level `traits` is the SwiftPM 6.1
    // object form, decoded via PackageManifestKit's TraitDescription model.
    private static let manifestWithObjectFormTraits = """
    {
      "name": "MyFramework",
      "toolsVersion": { "_version": "6.1.0" },
      "dependencies": [],
      "products": [],
      "targets": [],
      "packageKind": { "root": ["/tmp/MyFramework"] },
      "traits": [
        { "name": "default", "enabledTraits": ["Foo"] },
        { "name": "Foo", "description": "bar", "enabledTraits": [] }
      ]
    }
    """

    // Same manifest without a `traits` key.
    private static let manifestWithoutTraits = """
    {
      "name": "MyFramework",
      "toolsVersion": { "_version": "6.1.0" },
      "dependencies": [],
      "products": [],
      "targets": [],
      "packageKind": { "root": ["/tmp/MyFramework"] }
    }
    """

    @Test
    func decodesManifestDeclaringObjectFormTraits() async throws {
        let executor = StubbableExecutor { arguments in
            StubbableExecutorResult(arguments: arguments, success: Self.manifestWithObjectFormTraits)
        }
        let loader = ManifestLoader(executor: executor)

        let manifest = try await loader.loadManifest(for: URL(filePath: "/tmp/MyFramework"))

        #expect(manifest.name == "MyFramework")
        let traits = try #require(manifest.traits)
        #expect(traits.map(\.name) == ["default", "Foo"])
        #expect(traits[0].enabledTraits == ["Foo"])
        #expect(traits[1].description == "bar")
    }

    @Test
    func decodesManifestWithoutTraits() async throws {
        let executor = StubbableExecutor { arguments in
            StubbableExecutorResult(arguments: arguments, success: Self.manifestWithoutTraits)
        }
        let loader = ManifestLoader(executor: executor)

        let manifest = try await loader.loadManifest(for: URL(filePath: "/tmp/MyFramework"))

        #expect(manifest.name == "MyFramework")
    }
}

extension ManifestLoaderTests {
    /// SwiftPM emits positional provider arguments for both package and system-target providers.
    @Test(arguments: ["apt", "brew", "yum", "nuget"])
    func decodesSystemPackageProviders(provider: String) async throws {
        let packages = ["sqlite3", "another-library"]
        let providers: [[String: Any]] = [[provider: [packages]]]
        let payload: [String: Any] = [
            "name": "SystemLibrary", "toolsVersion": ["_version": "6.4.0"],
            "dependencies": [], "products": [], "providers": providers,
            "packageKind": ["root": ["/tmp/SystemLibrary"]],
            "targets": [[
                "name": "SQLite", "type": "system", "packageAccess": false,
                "dependencies": [], "resources": [], "exclude": [], "settings": [],
                "providers": providers,
            ]],
        ]
        let json = String(decoding: try JSONSerialization.data(withJSONObject: payload), as: UTF8.self)
        let executor = StubbableExecutor { arguments in
            StubbableExecutorResult(arguments: arguments, success: json)
        }
        let manifest = try await ManifestLoader(executor: executor).loadManifest(for: URL(filePath: "/tmp/SystemLibrary"))
        let encoded = try JSONEncoder().encode(manifest)
        let decoded = try #require(JSONSerialization.jsonObject(with: encoded) as? [String: Any])
        let packageProviders = try #require(decoded["providers"] as? [[String: [String: [String]]]])
        let targets = try #require(decoded["targets"] as? [[String: Any]])
        let target = try #require(targets.first)
        let targetProviders = try #require(target["providers"] as? [[String: [String: [String]]]])
        #expect(packageProviders.first?[provider]?["_0"] == packages)
        #expect(targetProviders.first?[provider]?["_0"] == packages)
    }
}
