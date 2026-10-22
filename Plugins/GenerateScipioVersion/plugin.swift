import Foundation
import PackagePlugin

@main
struct GenerateScipioVersion: BuildToolPlugin {
    func createBuildCommands(context: PluginContext, target: Target) async throws -> [Command] {
        let zshPath = URL(filePath: "/bin/zsh") // execute dummy command
        
        let generatedSourceDir = context.pluginWorkDirectoryURL
        
        let generatedSourcePath = generatedSourceDir
            .appending(component: "ScipioVersion.generated.swift")

        let revision = try? fetchRepositoryVersion(context: context)

        let fileContents: String
        if let revision {
            fileContents = #"let currentScipioVersion: String? = "\#(revision)""#
        } else {
            fileContents = #"let currentScipioVersion: String? = nil"#
        }

        // Preserve the timestamp when unchanged so app builds do not recompile ScipioKit.
        let data = Data(fileContents.utf8)
        if (try? Data(contentsOf: generatedSourcePath)) != data {
            try data.write(to: generatedSourcePath)
        }

        return [
            .prebuildCommand(
                displayName: "Generate Scipio Version",
                executable: zshPath,
                arguments: [],
                outputFilesDirectory: generatedSourceDir
            ),
        ]
    }

    private func fetchRepositoryVersion(context: PluginContext) throws -> String? {
        let standardOutput = Pipe()
        let process = Process()
        
        let repositoryPath = context.package.directoryURL.path()
        
        process.executableURL = URL(fileURLWithPath: "/usr/bin/git")
        process.arguments = [
            "-C",
            repositoryPath,
            "rev-parse",
            "HEAD",
        ]
        process.standardOutput = standardOutput

        try process.run()
        process.waitUntilExit()
        let outputData = try standardOutput.fileHandleForReading.readToEnd()
        guard let outputData else { return nil }
        let revision = String(data: outputData, encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return revision
    }
}
