import CommonCrypto
import CryptoKit
import Foundation
import Security

enum PatchPackageCodec {
    private static let magic = Data("3105PATCH\0".utf8)
    private static let contentEncryptionAlgorithm = "AES-256-GCM"
    private static let keyDerivationAlgorithm = "PBKDF2-HMAC-SHA256"
    static let latestSchemaVersion = 3
    private static let minimumSchemaVersion = 1

    private struct Envelope: Codable {
        let schemaVersion: Int
        let keyAADVersion: Int?
        let packageID: UUID
        let isPasswordProtected: Bool
        let kdfSalt: Data?
        let kdfIterations: Int?
        let wrappedContentKey: Data?
        let publicContentKey: Data?
        let keyFingerprint: Data
        let encryptedPayload: Data
        // Optional so v1/v2 and early v3 packages remain readable.
        let contentEncryptionAlgorithm: String?
        let keyDerivationAlgorithm: String?
    }

    private struct Payload: Codable {
        // v1/v2 payloads use `project`; v3 payloads use `variants`.
        let project: PatchProject?
        let variants: [PatchProject]?
        let replacementDigests: [String: Data]
    }

    static func encodeNew(
        project: PatchProject,
        password: String?,
        kdfIterations: Int = PatchPackageLimits.defaultKDFIterations
    ) throws -> EncodedPatchPackage {
        try encode(
            variants: [project],
            packageID: project.id,
            password: password,
            schemaVersion: 2,
            kdfIterations: kdfIterations
        )
    }

    static func encodeNew(
        variants: [PatchProject],
        password: String?,
        kdfIterations: Int = PatchPackageLimits.defaultKDFIterations
    ) throws -> EncodedPatchPackage {
        guard variants.count >= 2 else { throw PatchPackageError.invalidProject }
        return try encode(
            variants: variants,
            packageID: UUID(),
            password: password,
            schemaVersion: 3,
            kdfIterations: kdfIterations
        )
    }

    static func encodeLegacyV1(
        project: PatchProject,
        password: String?,
        kdfIterations: Int = PatchPackageLimits.defaultKDFIterations
    ) throws -> EncodedPatchPackage {
        try encode(
            variants: [project],
            packageID: project.id,
            password: password,
            schemaVersion: 1,
            kdfIterations: kdfIterations
        )
    }

    private static func encode(
        variants: [PatchProject],
        packageID: UUID,
        password: String?,
        schemaVersion: Int,
        kdfIterations: Int
    ) throws -> EncodedPatchPackage {
        try validate(variants, requireMultiple: schemaVersion >= 3)
        guard (minimumSchemaVersion...latestSchemaVersion).contains(schemaVersion) else {
            throw PatchPackageError.unsupportedVersion
        }
        let contentKey = try randomData(count: 32)
        let protected = !(password ?? "").isEmpty
        let salt: Data?
        let iterations: Int?
        let wrappedKey: Data?
        let publicKey: Data?

        if protected {
            guard let password, password.utf8.count <= PatchPackageLimits.maximumPasswordBytes,
                  kdfIterations >= PatchPackageLimits.minimumKDFIterations,
                  kdfIterations <= PatchPackageLimits.maximumKDFIterations
            else {
                throw PatchPackageError.invalidProject
            }
            salt = try randomData(count: 16)
            iterations = kdfIterations
            let wrappingKey = try deriveKey(password: password, salt: salt!, iterations: kdfIterations)
            wrappedKey = try seal(
                contentKey,
                key: wrappingKey,
                aad: keyAAD(for: packageID, version: schemaVersion)
            )
            publicKey = nil
        } else {
            salt = nil
            iterations = nil
            wrappedKey = nil
            publicKey = contentKey
        }

        let envelope = try makeEnvelope(
            packageID: packageID,
            variants: variants,
            schemaVersion: schemaVersion,
            keyAADVersion: protected ? schemaVersion : nil,
            contentKey: contentKey,
            isPasswordProtected: protected,
            kdfSalt: salt,
            kdfIterations: iterations,
            wrappedContentKey: wrappedKey,
            publicContentKey: publicKey
        )
        return EncodedPatchPackage(data: try serialize(envelope), contentKey: contentKey)
    }

    static func inspect(_ data: Data) throws -> PatchPackageSummary {
        let envelope = try parseEnvelope(data)
        return PatchPackageSummary(
            packageID: envelope.packageID,
            schemaVersion: envelope.schemaVersion,
            isPasswordProtected: envelope.isPasswordProtected,
            keyFingerprint: envelope.keyFingerprint
        )
    }

    static func decode(_ data: Data, password: String?) throws -> DecodedPatchPackage {
        do {
            let envelope = try parseEnvelope(data)
            let contentKey: Data
            if envelope.isPasswordProtected {
                guard let password,
                      !password.isEmpty,
                      password.utf8.count <= PatchPackageLimits.maximumPasswordBytes,
                      let salt = envelope.kdfSalt,
                      let iterations = envelope.kdfIterations,
                      let wrappedKey = envelope.wrappedContentKey
                else {
                    throw PatchPackageError.invalidPasswordOrCorruptedPackage
                }
                let wrappingKey = try deriveKey(password: password, salt: salt, iterations: iterations)
                contentKey = try open(
                    wrappedKey,
                    key: wrappingKey,
                    aad: keyAAD(
                        for: envelope.packageID,
                        version: envelope.keyAADVersion ?? envelope.schemaVersion
                    )
                )
            } else {
                guard let storedKey = envelope.publicContentKey else {
                    throw PatchPackageError.invalidPasswordOrCorruptedPackage
                }
                contentKey = storedKey
            }
            return try decode(envelope: envelope, contentKey: contentKey)
        } catch let error as PatchPackageError {
            switch error {
            case .unsupportedFormat, .unsupportedVersion, .sizeLimitExceeded:
                throw error
            default:
                throw PatchPackageError.invalidPasswordOrCorruptedPackage
            }
        } catch {
            throw PatchPackageError.invalidPasswordOrCorruptedPackage
        }
    }

    static func decode(_ data: Data, contentKey: Data) throws -> DecodedPatchPackage {
        do {
            let envelope = try parseEnvelope(data)
            return try decode(envelope: envelope, contentKey: contentKey)
        } catch let error as PatchPackageError {
            switch error {
            case .unsupportedFormat, .unsupportedVersion, .sizeLimitExceeded:
                throw error
            default:
                throw PatchPackageError.invalidPasswordOrCorruptedPackage
            }
        } catch {
            throw PatchPackageError.invalidPasswordOrCorruptedPackage
        }
    }

    static func changePassword(
        _ originalData: Data,
        contentKey: Data,
        newPassword: String,
        kdfIterations: Int = PatchPackageLimits.defaultKDFIterations
    ) throws -> EncodedPatchPackage {
        let oldEnvelope = try parseEnvelope(originalData)
        guard !newPassword.isEmpty,
              newPassword.utf8.count <= PatchPackageLimits.maximumPasswordBytes,
              kdfIterations >= PatchPackageLimits.minimumKDFIterations,
              kdfIterations <= PatchPackageLimits.maximumKDFIterations else {
            throw PatchPackageError.invalidProject
        }

        let decoded = try decode(originalData, contentKey: contentKey)
        let newContentKey = try randomData(count: 32)
        let salt = try randomData(count: 16)
        let wrappingKey = try deriveKey(
            password: newPassword,
            salt: salt,
            iterations: kdfIterations
        )
        let wrappedKey = try seal(
            newContentKey,
            key: wrappingKey,
            aad: keyAAD(
                for: oldEnvelope.packageID,
                version: oldEnvelope.schemaVersion
            )
        )
        let envelope = try makeEnvelope(
            packageID: oldEnvelope.packageID,
            variants: decoded.variants,
            schemaVersion: oldEnvelope.schemaVersion,
            keyAADVersion: oldEnvelope.schemaVersion,
            contentKey: newContentKey,
            isPasswordProtected: true,
            kdfSalt: salt,
            kdfIterations: kdfIterations,
            wrappedContentKey: wrappedKey,
            publicContentKey: nil
        )
        return EncodedPatchPackage(
            data: try serialize(envelope),
            contentKey: newContentKey
        )
    }

    static func update(
        _ originalData: Data,
        project: PatchProject,
        contentKey: Data,
        schemaVersion requestedSchemaVersion: Int? = nil
    ) throws -> Data {
        let oldEnvelope = try parseEnvelope(originalData)
        guard oldEnvelope.schemaVersion < 3 else {
            throw PatchPackageError.invalidProject
        }
        return try update(
            originalData,
            variants: [project],
            contentKey: contentKey,
            schemaVersion: requestedSchemaVersion
        )
    }

    static func update(
        _ originalData: Data,
        variants: [PatchProject],
        contentKey: Data,
        schemaVersion requestedSchemaVersion: Int? = nil
    ) throws -> Data {
        let oldEnvelope = try parseEnvelope(originalData)
        guard fingerprint(contentKey) == oldEnvelope.keyFingerprint else {
            throw PatchPackageError.invalidPasswordOrCorruptedPackage
        }
        let schemaVersion = requestedSchemaVersion ?? oldEnvelope.schemaVersion
        guard (minimumSchemaVersion...latestSchemaVersion).contains(schemaVersion) else {
            throw PatchPackageError.unsupportedVersion
        }
        guard schemaVersion >= 3 || (variants.count == 1 && variants[0].id == oldEnvelope.packageID) else {
            throw PatchPackageError.invalidProject
        }
        try validate(variants, requireMultiple: schemaVersion >= 3)
        let envelope = try makeEnvelope(
            packageID: oldEnvelope.packageID,
            variants: variants,
            schemaVersion: schemaVersion,
            keyAADVersion: oldEnvelope.isPasswordProtected
                ? (oldEnvelope.keyAADVersion ?? oldEnvelope.schemaVersion)
                : nil,
            contentKey: contentKey,
            isPasswordProtected: oldEnvelope.isPasswordProtected,
            kdfSalt: oldEnvelope.kdfSalt,
            kdfIterations: oldEnvelope.kdfIterations,
            wrappedContentKey: oldEnvelope.wrappedContentKey,
            publicContentKey: oldEnvelope.publicContentKey
        )
        return try serialize(envelope)
    }

    private static func makeEnvelope(
        packageID: UUID,
        variants: [PatchProject],
        schemaVersion: Int,
        keyAADVersion: Int?,
        contentKey: Data,
        isPasswordProtected: Bool,
        kdfSalt: Data?,
        kdfIterations: Int?,
        wrappedContentKey: Data?,
        publicContentKey: Data?
    ) throws -> Envelope {
        let allRules = variants.flatMap(\.rules)
        let digests = Dictionary(uniqueKeysWithValues: allRules.map {
            ($0.id.uuidString, Data(SHA256.hash(data: $0.replacementData)))
        })
        let payload = Payload(
            project: schemaVersion >= 3 ? nil : variants[0],
            variants: schemaVersion >= 3 ? variants : nil,
            replacementDigests: digests
        )
        let encoder = PropertyListEncoder()
        encoder.outputFormat = .binary
        let payloadData = try encoder.encode(payload)
        let encryptedPayload = try seal(
            payloadData,
            key: contentKey,
            aad: payloadAAD(for: packageID, version: schemaVersion)
        )

        return Envelope(
            schemaVersion: schemaVersion,
            keyAADVersion: keyAADVersion,
            packageID: packageID,
            isPasswordProtected: isPasswordProtected,
            kdfSalt: kdfSalt,
            kdfIterations: kdfIterations,
            wrappedContentKey: wrappedContentKey,
            publicContentKey: publicContentKey,
            keyFingerprint: fingerprint(contentKey),
            encryptedPayload: encryptedPayload,
            contentEncryptionAlgorithm: schemaVersion >= 3 ? contentEncryptionAlgorithm : nil,
            keyDerivationAlgorithm: schemaVersion >= 3 && isPasswordProtected ? keyDerivationAlgorithm : nil
        )
    }

    private static func decode(envelope: Envelope, contentKey: Data) throws -> DecodedPatchPackage {
        guard contentKey.count == 32,
              fingerprint(contentKey) == envelope.keyFingerprint
        else {
            throw PatchPackageError.invalidPasswordOrCorruptedPackage
        }
        let payloadData = try open(
            envelope.encryptedPayload,
            key: contentKey,
            aad: payloadAAD(for: envelope.packageID, version: envelope.schemaVersion)
        )
        let decoder = PropertyListDecoder()
        let payload = try decoder.decode(Payload.self, from: payloadData)
        let variants: [PatchProject]
        if let storedVariants = payload.variants {
            guard envelope.schemaVersion >= 3, payload.project == nil else {
                throw PatchPackageError.invalidPasswordOrCorruptedPackage
            }
            variants = storedVariants
        } else if let project = payload.project {
            guard envelope.schemaVersion < 3 else {
                throw PatchPackageError.invalidPasswordOrCorruptedPackage
            }
            variants = [project]
        } else {
            throw PatchPackageError.invalidPasswordOrCorruptedPackage
        }
        if envelope.schemaVersion < 3 {
            guard variants.count == 1, variants[0].id == envelope.packageID else {
                throw PatchPackageError.invalidPasswordOrCorruptedPackage
            }
        } else {
            guard variants.count >= 2 else {
                throw PatchPackageError.invalidPasswordOrCorruptedPackage
            }
        }
        try validate(variants, requireMultiple: envelope.schemaVersion >= 3)
        guard payload.replacementDigests.count == variants.flatMap(\.rules).count else {
            throw PatchPackageError.invalidPasswordOrCorruptedPackage
        }
        for rule in variants.flatMap(\.rules) {
            let actual = Data(SHA256.hash(data: rule.replacementData))
            guard payload.replacementDigests[rule.id.uuidString] == actual else {
                throw PatchPackageError.invalidPasswordOrCorruptedPackage
            }
        }
        return DecodedPatchPackage(variants: variants, contentKey: contentKey)
    }

    static func validate(_ project: PatchProject) throws {
        let name = project.name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty,
              name.utf8.count <= 120,
              !project.allBundleIdentifiers.isEmpty else {
            throw PatchPackageError.invalidProject
        }
        var bundles = Set<String>()
        for suppliedBundleID in project.bundleIdentifiers {
            let bundleID = try PatchPathValidator.canonicalBundleIdentifier(suppliedBundleID)
            guard bundleID == suppliedBundleID,
                  bundles.insert(bundleID).inserted else {
                throw PatchPackageError.invalidProject
            }
        }
        var targets = Set<String>()
        var ruleIDs = Set<UUID>()
        var directoryIDs = Set<UUID>()
        var directoryTargets = Set<String>()
        for directory in project.directories {
            let bundleID = try PatchPathValidator.canonicalBundleIdentifier(directory.bundleID)
            let relativePath = try PatchPathValidator.canonicalRelativePath(directory.relativePath)
            guard bundleID == directory.bundleID,
                  relativePath == directory.relativePath,
                  directoryIDs.insert(directory.id).inserted else {
                throw PatchPackageError.invalidProject
            }
            if !bundles.isEmpty, !bundles.contains(bundleID) {
                throw PatchPackageError.invalidProject
            }
            guard directoryTargets.insert(bundleID + "\0" + relativePath).inserted else {
                throw PatchPackageError.duplicateTarget
            }
        }
        for rule in project.rules {
            let bundleID = try PatchPathValidator.canonicalBundleIdentifier(rule.bundleID)
            let relativePath = try PatchPathValidator.canonicalRelativePath(rule.relativePath)
            guard bundleID == rule.bundleID,
                  relativePath == rule.relativePath,
                  ruleIDs.insert(rule.id).inserted,
                  !rule.replacementFilename.isEmpty,
                  rule.replacementFilename.utf8.count <= 255,
                  !rule.replacementFilename.contains("/"),
                  !rule.replacementFilename.contains("\\"),
                  !rule.replacementFilename.unicodeScalars.contains(where: CharacterSet.controlCharacters.contains)
            else {
                throw PatchPackageError.invalidProject
            }
            if !bundles.isEmpty, !bundles.contains(bundleID) {
                throw PatchPackageError.invalidProject
            }
            let targetKey = bundleID + "\0" + relativePath
            guard targets.insert(targetKey).inserted,
                  !directoryTargets.contains(targetKey) else {
                throw PatchPackageError.duplicateTarget
            }
        }
    }

    private static func validate(
        _ variants: [PatchProject],
        requireMultiple: Bool
    ) throws {
        guard !variants.isEmpty, !requireMultiple || variants.count >= 2 else {
            throw PatchPackageError.invalidProject
        }
        var variantIDs = Set<UUID>()
        var ruleIDs = Set<UUID>()
        for variant in variants {
            guard variantIDs.insert(variant.id).inserted else {
                throw PatchPackageError.duplicateTarget
            }
            try validate(variant)
            for rule in variant.rules {
                guard ruleIDs.insert(rule.id).inserted else {
                    throw PatchPackageError.duplicateTarget
                }
            }
        }
    }

    private static func parseEnvelope(_ data: Data) throws -> Envelope {
        guard data.count > magic.count,
              data.prefix(magic.count) == magic
        else {
            throw PatchPackageError.unsupportedFormat
        }
        let encoded = data.dropFirst(magic.count)
        let envelope: Envelope
        do {
            envelope = try PropertyListDecoder().decode(Envelope.self, from: Data(encoded))
        } catch {
            throw PatchPackageError.invalidPasswordOrCorruptedPackage
        }
        guard (minimumSchemaVersion...latestSchemaVersion).contains(envelope.schemaVersion) else {
            throw PatchPackageError.unsupportedVersion
        }
        guard envelope.keyFingerprint.count == 32,
              envelope.encryptedPayload.count >= 28
        else {
            throw PatchPackageError.invalidPasswordOrCorruptedPackage
        }
        if envelope.schemaVersion >= 3 {
            if let algorithm = envelope.contentEncryptionAlgorithm {
                guard algorithm == contentEncryptionAlgorithm else {
                    throw PatchPackageError.invalidPasswordOrCorruptedPackage
                }
            }
            if let algorithm = envelope.keyDerivationAlgorithm {
                guard algorithm == keyDerivationAlgorithm else {
                    throw PatchPackageError.invalidPasswordOrCorruptedPackage
                }
            }
        }
        if envelope.isPasswordProtected {
            guard envelope.publicContentKey == nil,
                  (minimumSchemaVersion...latestSchemaVersion).contains(
                    envelope.keyAADVersion ?? envelope.schemaVersion
                  ),
                  envelope.kdfSalt?.count == 16,
                  let iterations = envelope.kdfIterations,
                  iterations >= PatchPackageLimits.minimumKDFIterations,
                  iterations <= PatchPackageLimits.maximumKDFIterations,
                  envelope.wrappedContentKey != nil
            else {
                throw PatchPackageError.invalidPasswordOrCorruptedPackage
            }
        } else {
            guard envelope.kdfSalt == nil,
                  envelope.kdfIterations == nil,
                  envelope.wrappedContentKey == nil,
                  envelope.publicContentKey?.count == 32
            else {
                throw PatchPackageError.invalidPasswordOrCorruptedPackage
            }
        }
        return envelope
    }

    private static func serialize(_ envelope: Envelope) throws -> Data {
        let encoder = PropertyListEncoder()
        encoder.outputFormat = .binary
        let body = try encoder.encode(envelope)
        var result = magic
        result.append(body)
        return result
    }

    private static func seal(_ plaintext: Data, key: Data, aad: Data) throws -> Data {
        guard key.count == 32 else {
            throw PatchPackageError.invalidPasswordOrCorruptedPackage
        }
        let sealed = try AES.GCM.seal(plaintext, using: SymmetricKey(data: key), authenticating: aad)
        guard let combined = sealed.combined else {
            throw PatchPackageError.invalidPasswordOrCorruptedPackage
        }
        return combined
    }

    private static func open(_ ciphertext: Data, key: Data, aad: Data) throws -> Data {
        guard key.count == 32 else {
            throw PatchPackageError.invalidPasswordOrCorruptedPackage
        }
        let box = try AES.GCM.SealedBox(combined: ciphertext)
        return try AES.GCM.open(box, using: SymmetricKey(data: key), authenticating: aad)
    }

    private static func deriveKey(password: String, salt: Data, iterations: Int) throws -> Data {
        guard iterations >= PatchPackageLimits.minimumKDFIterations,
              iterations <= PatchPackageLimits.maximumKDFIterations else {
            throw PatchPackageError.invalidPasswordOrCorruptedPackage
        }
        let passwordData = Data(password.utf8)
        let derivedKeyLength = 32
        var output = Data(count: derivedKeyLength)
        let status = output.withUnsafeMutableBytes { outputBuffer in
            passwordData.withUnsafeBytes { passwordBuffer in
                salt.withUnsafeBytes { saltBuffer in
                    CCKeyDerivationPBKDF(
                        CCPBKDFAlgorithm(kCCPBKDF2),
                        passwordBuffer.bindMemory(to: Int8.self).baseAddress,
                        passwordData.count,
                        saltBuffer.bindMemory(to: UInt8.self).baseAddress,
                        salt.count,
                        CCPseudoRandomAlgorithm(kCCPRFHmacAlgSHA256),
                        UInt32(iterations),
                        outputBuffer.bindMemory(to: UInt8.self).baseAddress,
                        derivedKeyLength
                    )
                }
            }
        }
        guard status == kCCSuccess else {
            throw PatchPackageError.invalidPasswordOrCorruptedPackage
        }
        return output
    }

    private static func randomData(count: Int) throws -> Data {
        var data = Data(count: count)
        let status = data.withUnsafeMutableBytes { buffer in
            SecRandomCopyBytes(kSecRandomDefault, count, buffer.baseAddress!)
        }
        guard status == errSecSuccess else {
            throw PatchPackageError.invalidProject
        }
        return data
    }

    private static func fingerprint(_ key: Data) -> Data {
        Data(SHA256.hash(data: key))
    }

    private static func keyAAD(for packageID: UUID, version: Int) -> Data {
        Data("3105PATCH/v\(version)/key/\(packageID.uuidString)".utf8)
    }

    private static func payloadAAD(for packageID: UUID, version: Int) -> Data {
        Data("3105PATCH/v\(version)/payload/\(packageID.uuidString)".utf8)
    }
}
