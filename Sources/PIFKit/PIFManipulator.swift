import Foundation
import SwiftyJSON

/// Manipulates PIF JSON data
package final class PIFManipulator {
    private var topLevelObject: JSON

    /// Initialize PIFManipulator with JSON data
    /// - Parameters jsonData: JSON data
    package init(jsonData: Data) throws {
        self.topLevelObject = try JSON(data: jsonData)
    }

    /// Update targets in PIF JSON data
    /// - Parameters modifier: Closure to modify Target
    package func updateTargets(_ modifier: (inout Target) -> Void) {
        for index in 0..<topLevelObject.arrayValue.count {
            guard topLevelObject[index]["type"].stringValue == "target", var target = try? Target(from: topLevelObject[index]["contents"]) else {
                continue
            }

            modifier(&target)
            apply(target, to: &topLevelObject[index])
        }
    }

    /// Host macro implementations are supplied separately; omit their framework build edges.
    package func pruneDependencies(keepingTargetNames names: Set<String>) {
        let targets = topLevelObject.arrayValue.filter { $0["type"].stringValue == "target" }
        var allowedGUIDs = Set(targets.compactMap { object -> String? in
            let contents = object["contents"]
            guard names.contains(contents["name"].stringValue)
                || contents["productTypeIdentifier"].stringValue == "com.apple.product-type.bundle" else { return nil }
            return contents["guid"].stringValue
        })
        // SwiftPM gives product wrappers generated names; retain wrappers that lead to runtime targets.
        var changed: Bool
        repeat {
            changed = false
            for object in targets {
                let contents = object["contents"]
                let guid = contents["guid"].stringValue
                guard guid.hasPrefix("PACKAGE-PRODUCT:"),
                      contents["dependencies"].arrayValue.contains(where: { allowedGUIDs.contains($0["guid"].stringValue) }) else { continue }
                if allowedGUIDs.insert(guid).inserted { changed = true }
            }
        } while changed
        for index in 0..<topLevelObject.arrayValue.count {
            guard topLevelObject[index]["type"].stringValue == "target" else { continue }
            let dependencies = topLevelObject[index]["contents"]["dependencies"].arrayValue
            topLevelObject[index]["contents"]["dependencies"] = JSON(dependencies.filter {
                allowedGUIDs.contains($0["guid"].stringValue)
            })
        }
    }

    /// Use SwiftPM's resolved graph so disabled package traits do not add linker flags.
    package func dependencyNamesByTarget() -> [String: Set<String>] {
        let targets = topLevelObject.arrayValue.filter { $0["type"].stringValue == "target" }.map { $0["contents"] }
        let byGUID = Dictionary(uniqueKeysWithValues: targets.map { ($0["guid"].stringValue, $0) })
        return Dictionary(uniqueKeysWithValues: targets.map { target in
            var names = Set<String>()
            var visited = Set<String>()
            func visit(_ guid: String) {
                guard visited.insert(guid).inserted, let dependency = byGUID[guid] else { return }
                names.insert(dependency["name"].stringValue)
                for child in dependency["dependencies"].arrayValue { visit(child["guid"].stringValue) }
            }
            for dependency in target["dependencies"].arrayValue { visit(dependency["guid"].stringValue) }
            return (target["name"].stringValue, names)
        })
    }

    /// Dump manipulating JSON data
    /// - Returns: JSON data
    package func dump() throws -> Data {
        try topLevelObject.rawData(options: [.prettyPrinted])
    }

    /// Apply target to JSON object
    /// Currently, Target is a subset of an actual PIF target. So, we have to apply only the properties that are present in the Target.
    /// - Parameters target: Target to apply
    /// - Parameters pifObject: JSON object to apply the target to
    private func apply(_ target: Target, to pifObject: inout JSON) {
        pifObject["contents"]["name"].string = target.name
        pifObject["contents"]["productTypeIdentifier"].string = target.productType?.rawValue

        let jsonEncoder = JSONEncoder()
        pifObject["contents"]["buildConfigurations"].arrayObject = target.buildConfigurations.compactMap { try? $0.toJSON(using: jsonEncoder) }
    }
}

extension BuildConfiguration {
    fileprivate func toJSON(using encoder: JSONEncoder = JSONEncoder()) throws -> JSON {
        let data = try encoder.encode(self)
        return try JSON(data: data)
    }
}
