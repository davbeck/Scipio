import Foundation
import PackageManifestKit
import ScipioKitCore

/// Loads the `Manifest` of a Swift package
struct ManifestLoader: @unchecked Sendable {
    private let executor: any Executor
    private let jsonDecoder = JSONDecoder()

    init(executor: some Executor) {
        self.executor = executor
    }

    /// Loads the manifest for a package at a local path.
    /// - Parameter packagePath: The file path of the package.
    /// - Returns: A decoded `Manifest` object.
    func loadManifest(for packagePath: URL) async throws -> Manifest {
        try await loadManifest(path: packagePath.path(percentEncoded: false))
    }

    /// Loads the manifest for a dependency package.
    /// - Parameter dependencyPackage: A package from the dependencies.
    /// - Returns: A decoded `Manifest` object.
    @_disfavoredOverload
    func loadManifest(for dependencyPackage: DependencyPackage) async throws -> Manifest {
        try await loadManifest(path: dependencyPackage.path)
    }

    private func loadManifest(path: String) async throws -> Manifest {
        let commands = [
            "/usr/bin/xcrun",
            "swift",
            "package",
            "dump-package",
            "--package-path",
            path,
        ]

        let manifestData = try await executor.execute(commands)
            .unwrapOutput()
            .data(using: .utf8)

        guard let manifestData else {
            throw Error.utf8EncodingFailed
        }

        return try jsonDecoder.decode(Manifest.self, from: normalizeSystemPackageProviders(in: manifestData))
    }

    /// Bridge SwiftPM's positional enum payloads to PackageManifestKit 0.3.2's synthesized Codable format.
    private func normalizeSystemPackageProviders(in data: Data) throws -> Data {
        guard var manifest = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return data
        }

        func normalize(_ value: Any?) -> Any? {
            guard let providers = value as? [[String: Any]] else { return value }
            return providers.map { provider in
                provider.mapValues { arguments -> Any in
                    guard let positional = arguments as? [[String]], positional.count == 1,
                          let packages = positional.first else { return arguments }
                    return ["_0": packages]
                }
            }
        }

        // Providers can be declared on the package itself or on individual system-library targets.
        manifest["providers"] = normalize(manifest["providers"])
        if var targets = manifest["targets"] as? [[String: Any]] {
            for index in targets.indices {
                targets[index]["providers"] = normalize(targets[index]["providers"])
            }
            manifest["targets"] = targets
        }
        return try JSONSerialization.data(withJSONObject: manifest)
    }

    enum Error: LocalizedError {
        case utf8EncodingFailed

        var errorDescription: String? {
            switch self {
            case .utf8EncodingFailed:
                "Failed to convert the command output string to UTF-8 encoded data"
            }
        }
    }
}
