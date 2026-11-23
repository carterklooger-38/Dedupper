import Foundation

public enum ValidationResult: Equatable, Sendable {
    case valid
    case invalid(String)
}

public protocol SafetyValidating: Sendable {
    func validate(_ item: PlannedDeletion) -> ValidationResult
}

public struct SafetyValidator: SafetyValidating {
    private let hasher: any ContentHashing

    public init(hasher: any ContentHashing = SHA256FileHasher()) {
        self.hasher = hasher
    }

    public func validate(_ item: PlannedDeletion) -> ValidationResult {
        guard FileManager.default.fileExists(atPath: item.file.url.path) else {
            return .invalid("File is missing")
        }

        do {
            let attributes = try FileManager.default.attributesOfItem(
                atPath: item.file.url.path
            )
            guard attributes[.type] as? FileAttributeType == .typeRegular else {
                return .invalid("File is no longer a regular file")
            }
            guard let size = attributes[.size] as? NSNumber,
                  size.uint64Value == item.file.byteSize else {
                return .invalid("File size changed after scanning")
            }
            guard attributes[.modificationDate] as? Date == item.file.modificationDate else {
                return .invalid("File modification date changed after scanning")
            }
            guard try hasher.digest(of: item.file.url) == item.expectedDigest else {
                return .invalid("File contents changed after scanning")
            }
            return .valid
        } catch {
            return .invalid("File could not be revalidated: \(error.localizedDescription)")
        }
    }
}
