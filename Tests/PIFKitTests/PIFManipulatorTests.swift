import Foundation
import Testing
@testable import PIFKit

@Suite
struct PIFManipulatorTests {
    @Test
    func canUpdateProductTypes() throws {
        let jsonData = try FixtureLoader.load(named: "SimplePackage.pif")
        let manipulator = try PIFManipulator(jsonData: jsonData)

        var detectedTargets: [String] = []
        manipulator.updateTargets { target in
            detectedTargets.append(target.name)

            target.productType = .application
        }

        let dumpedData = try manipulator.dump()
        let dumpedString = try #require(String(data: dumpedData, encoding: .utf8))

        #expect(dumpedString.contains("product-type.application"))
        #expect(detectedTargets.count == 5)
    }

    @Test
    func canUpdateBuildConfiguration() throws {
        let jsonData = try FixtureLoader.load(named: "SimplePackage.pif")
        let fixtureString = try #require(String(data: jsonData, encoding: .utf8))
        let manipulator = try PIFManipulator(jsonData: jsonData)

        #expect(!fixtureString.contains("MY_VALUE"))

        manipulator.updateTargets { target in
            target.buildConfigurations[0].buildSettings["MY_VALUE"] = "YES"
            target.buildConfigurations[1].buildSettings["MY_VALUE"] = "YES"
        }

        let dumpedData = try manipulator.dump()
        let dumpedString = try #require(String(data: dumpedData, encoding: .utf8))

        #expect(dumpedString.contains("MY_VALUE"))
    }
}

extension PIFManipulatorTests {
    /// Runtime wrappers, resource bundles, and system headers survive while macro host edges are removed.
    @Test
    func preservesRuntimeGraphWithoutMacroImplementations() throws {
        func target(_ name: String, guid: String? = nil, dependencies: [String] = [], bundle: Bool = false) -> [String: Any] {
            ["type": "target", "contents": [
                "name": name, "guid": guid ?? name,
                "productTypeIdentifier": bundle ? "com.apple.product-type.bundle" : "com.apple.product-type.objfile",
                "dependencies": dependencies.map { ["guid": $0] },
            ]]
        }
        let input = [
            target("App", dependencies: ["PACKAGE-PRODUCT:Outer", "Macro", "SwiftSyntax", "Resources"]),
            target("OuterProduct", guid: "PACKAGE-PRODUCT:Outer", dependencies: ["PACKAGE-PRODUCT:Inner"]),
            target("InnerProduct", guid: "PACKAGE-PRODUCT:Inner", dependencies: ["Runtime"]),
            target("Runtime", dependencies: ["Headers", "Macro", "Resources"]),
            target("Headers"), target("Resources", bundle: true),
            target("Macro", dependencies: ["SwiftSyntax"]), target("SwiftSyntax"),
            // Disabled trait dependencies are absent from SwiftPM's resolved graph.
            target("DisabledTraitLibrary"),
        ]
        let manipulator = try PIFManipulator(jsonData: JSONSerialization.data(withJSONObject: input))
        manipulator.pruneDependencies(keepingTargetNames: ["App", "Runtime", "Headers"])
        let dependencies = manipulator.dependencyNamesByTarget()
        #expect(dependencies["App"] == ["OuterProduct", "InnerProduct", "Runtime", "Headers", "Resources"])
        #expect(dependencies["Runtime"] == ["Headers", "Resources"])
        #expect(dependencies["Headers"] == [])
    }

}
