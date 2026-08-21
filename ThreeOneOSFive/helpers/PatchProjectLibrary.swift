import Foundation

struct PatchLibraryItem: Identifiable {
    let summary: PatchPackageSummary
    var variants: [PatchProject]
    var contentKey: Data?
    var packageURL: URL

    var id: UUID { summary.packageID }
    var project: PatchProject? { variants.first }
    var isLocked: Bool { variants.isEmpty }
    var hasVariants: Bool { variants.count > 1 }
    var workspaceURL: URL? {
        project.flatMap { PatchWorkspaceService.workspaceURL(projectID: $0.id) }
    }
}

struct PatchPasswordRequest: Identifiable {
    let summary: PatchPackageSummary
    var id: UUID { summary.packageID }
}

struct PatchPasswordChangeRequest: Identifiable {
    let summary: PatchPackageSummary
    var id: UUID { summary.packageID }
}

enum PatchProjectLibrary {
    static func packageRootURL(fileManager: FileManager = .default) throws -> URL {
        let base = try fileManager.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        let root = base.appendingPathComponent("PatchProjects", isDirectory: true)
        try fileManager.createDirectory(at: root, withIntermediateDirectories: true)
        return root
    }

    static func backupRootURL(fileManager: FileManager = .default) throws -> URL {
        let root = try packageRootURL(fileManager: fileManager)
            .appendingPathComponent("Backups", isDirectory: true)
        try fileManager.createDirectory(at: root, withIntermediateDirectories: true)
        return root
    }

    static func load(fileManager: FileManager = .default) -> [PatchLibraryItem] {
        guard let root = try? packageRootURL(fileManager: fileManager),
              let urls = try? fileManager.contentsOfDirectory(
                at: root,
                includingPropertiesForKeys: [.contentModificationDateKey, .fileSizeKey],
                options: [.skipsHiddenFiles, .skipsSubdirectoryDescendants]
              ) else { return [] }

        var byID: [UUID: PatchLibraryItem] = [:]
        for url in urls where url.pathExtension.lowercased() == "3105" {
            do {
                let data = try readPackage(at: url)
                let summary = try PatchPackageCodec.inspect(data)
                let decoded: DecodedPatchPackage?
                if let contentKey = try PatchKeyStore.load(for: summary) {
                    decoded = try PatchPackageCodec.decode(data, contentKey: contentKey)
                } else if summary.isPasswordProtected {
                    decoded = nil
                } else {
                    decoded = try PatchPackageCodec.decode(data, password: nil)
                }
                let item = PatchLibraryItem(
                    summary: summary,
                    variants: decoded?.variants ?? [],
                    contentKey: decoded?.contentKey,
                    packageURL: url
                )
                if summary.schemaVersion >= 2 {
                    for variant in decoded?.variants ?? [] {
                        do {
                            _ = try PatchWorkspaceService.ensureWorkspace(for: variant)
                        } catch {
                            log("patch: workspace unavailable for \(variant.id.uuidString)")
                        }
                    }
                }
                byID[summary.packageID] = item
            } catch {
                log("patch: skipped invalid local package \(url.lastPathComponent)")
            }
        }
        return byID.values.sorted {
            ($0.project?.updatedAt ?? .distantPast) > ($1.project?.updatedAt ?? .distantPast)
        }
    }

    static func readPackage(at url: URL) throws -> Data {
        let values = try url.resourceValues(forKeys: [.isDirectoryKey, .isRegularFileKey, .isSymbolicLinkKey])
        guard values.isDirectory != true,
              values.isSymbolicLink != true,
              values.isRegularFile == true else {
            throw PatchPackageError.invalidProject
        }
        return try Data(contentsOf: url, options: .mappedIfSafe)
    }

    static func save(
        data: Data,
        projectName: String,
        existingURL: URL? = nil,
        fileManager: FileManager = .default
    ) throws -> URL {
        let destination: URL
        if let existingURL {
            destination = existingURL
        } else {
            let root = try packageRootURL(fileManager: fileManager)
            let baseName = sanitizedFilename(projectName)
            var candidate = root.appendingPathComponent(baseName).appendingPathExtension("3105")
            var suffix = 2
            while fileManager.fileExists(atPath: candidate.path) {
                candidate = root.appendingPathComponent("\(baseName)-\(suffix)").appendingPathExtension("3105")
                suffix += 1
            }
            destination = candidate
        }
        try data.write(to: destination, options: [.atomic, .completeFileProtection])
        return destination
    }

    static func installImportedPackage(
        data: Data,
        decoded: DecodedPatchPackage,
        summary: PatchPackageSummary,
        existingURL: URL?,
        fileManager: FileManager = .default
    ) throws {
        let previousData = try existingURL.map { try readPackage(at: $0) }
        var savedURL: URL?
        do {
            savedURL = try save(
                data: data,
                projectName: decoded.project.name,
                existingURL: existingURL,
                fileManager: fileManager
            )
            if summary.schemaVersion >= 2 {
                for variant in decoded.variants {
                    _ = try PatchWorkspaceService.replaceWorkspace(
                        with: variant,
                        fileManager: fileManager
                    )
                }
            } else {
                try? PatchWorkspaceService.deleteWorkspace(
                    projectID: decoded.project.id,
                    fileManager: fileManager
                )
            }
        } catch {
            if let previousData, let existingURL {
                try? previousData.write(
                    to: existingURL,
                    options: [.atomic, .completeFileProtection]
                )
            } else if let savedURL, fileManager.fileExists(atPath: savedURL.path) {
                try? fileManager.removeItem(at: savedURL)
            }
            throw error
        }
    }

    static func delete(_ item: PatchLibraryItem, fileManager: FileManager = .default) throws {
        if fileManager.fileExists(atPath: item.packageURL.path) {
            try fileManager.removeItem(at: item.packageURL)
        }
        for variant in item.variants {
            try? PatchWorkspaceService.deleteWorkspace(projectID: variant.id, fileManager: fileManager)
        }
        try? PatchWorkspaceService.deleteWorkspace(projectID: item.id, fileManager: fileManager)
        try? PatchKeyStore.delete(for: item.summary)
    }

    @discardableResult
    static func synchronizeWorkspace(
        item: PatchLibraryItem,
        variantID: UUID? = nil,
        fileManager: FileManager = .default
    ) throws -> PatchProject {
        guard item.summary.schemaVersion >= 2,
              let contentKey = item.contentKey else {
            throw PatchPackageError.invalidProject
        }
        let original = try readPackage(at: item.packageURL)
        var updatedVariants = item.variants
        guard !updatedVariants.isEmpty else { throw PatchPackageError.invalidProject }
        let selectedID = variantID ?? updatedVariants[0].id
        let idsToSync: [UUID] = variantID.map { [$0] } ?? updatedVariants.map(\.id)
        for id in idsToSync {
            guard let index = updatedVariants.firstIndex(where: { $0.id == id }) else {
                throw PatchPackageError.invalidProject
            }
            let baseProject = updatedVariants[index]
            let workspace = try PatchWorkspaceService.ensureWorkspace(
                for: baseProject,
                fileManager: fileManager
            )
            updatedVariants[index] = try PatchWorkspaceService.snapshot(
                baseProject: baseProject,
                workspaceURL: workspace,
                fileManager: fileManager
            )
        }
        let updatedData: Data
        if item.summary.schemaVersion >= 3 {
            updatedData = try PatchPackageCodec.update(
                original,
                variants: updatedVariants,
                contentKey: contentKey,
                schemaVersion: PatchPackageCodec.latestSchemaVersion
            )
        } else {
            updatedData = try PatchPackageCodec.update(
                original,
                project: updatedVariants[0],
                contentKey: contentKey,
                schemaVersion: 2
            )
        }
        _ = try save(
            data: updatedData,
            projectName: updatedVariants[0].name,
            existingURL: item.packageURL,
            fileManager: fileManager
        )
        return updatedVariants.first(where: { $0.id == selectedID }) ?? updatedVariants[0]
    }

    private static func sanitizedFilename(_ rawName: String) -> String {
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-_ "))
        let scalars = rawName.unicodeScalars.map { allowed.contains($0) ? Character(String($0)) : "-" }
        let result = String(scalars)
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .prefix(80)
        return result.isEmpty ? "Patch" : String(result)
    }
}
