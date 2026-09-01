import Foundation

public enum HyphaArtifactContentClassificationError: Error, Equatable, Sendable {
    case unreadable
    case typeMismatch(String)
}

public struct HyphaArtifactContentClassifier: Sendable {
    public init() {}

    public func validate(_ selections: [HyphaArtifactSelection]) throws {
        for selection in selections { try validate(selection) }
    }

    public func validate(_ selection: HyphaArtifactSelection) throws {
        guard let data = try? Data(contentsOf: selection.url, options: [.mappedIfSafe]) else {
            throw HyphaArtifactContentClassificationError.unreadable
        }
        let format = selection.format.lowercased().trimmingCharacters(in: CharacterSet(charactersIn: "."))
        let valid: Bool
        switch format {
        case "pptx", "ppsx":
            valid = data.starts(withBytes: [0x50, 0x4b])
                && data.range(of: Data("ppt/presentation.xml".utf8)) != nil
                && data.range(of: Data("[Content_Types].xml".utf8)) != nil
        case "ppt":
            valid = data.starts(withBytes: [0xd0, 0xcf, 0x11, 0xe0, 0xa1, 0xb1, 0x1a, 0xe1])
        case "pdf":
            valid = data.starts(with: Data("%PDF-".utf8))
        case "png":
            valid = data.starts(withBytes: [0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a])
        case "jpg", "jpeg":
            valid = data.starts(withBytes: [0xff, 0xd8, 0xff])
        case "gif":
            valid = data.starts(with: Data("GIF87a".utf8)) || data.starts(with: Data("GIF89a".utf8))
        case "heic":
            valid = Self.isHEIF(data)
        case "html", "htm":
            valid = Self.isText(data) && Self.looksLikeHTML(data)
        case "json":
            valid = Self.isText(data) && (try? JSONSerialization.jsonObject(with: data)) != nil
        case "md", "markdown", "txt", "log":
            valid = Self.isText(data)
        default:
            valid = false
        }
        guard valid else {
            throw HyphaArtifactContentClassificationError.typeMismatch(format)
        }
    }

    private static func isText(_ data: Data) -> Bool {
        !data.contains(0) && String(data: data, encoding: .utf8) != nil
    }

    private static func looksLikeHTML(_ data: Data) -> Bool {
        let prefix = String(decoding: data.prefix(16 * 1_024), as: UTF8.self).lowercased()
        return prefix.contains("<!doctype html")
            || prefix.contains("<html")
            || prefix.contains("<head")
            || prefix.contains("<body")
    }

    private static func isHEIF(_ data: Data) -> Bool {
        guard data.count >= 12,
              String(decoding: data[4..<8], as: UTF8.self) == "ftyp" else { return false }
        let brand = String(decoding: data[8..<12], as: UTF8.self)
        return ["heic", "heix", "hevc", "hevx", "mif1", "msf1"].contains(brand)
    }
}

private extension Data {
    func starts(withBytes bytes: [UInt8]) -> Bool {
        starts(with: Data(bytes))
    }
}
