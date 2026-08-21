import Foundation

enum AppSection: Int, CaseIterable, Identifiable {
    case home
    case patches

    // Home remains as an internal compatibility case, but Exploits is the only public section.
    static var allCases: [AppSection] { [.patches] }

    var id: Int { rawValue }
}

struct AppTabNavigationState: Equatable {
    private(set) var selectedTab: Int
    private(set) var filesTabs: FilesTabSession

    init(
        selectedTab: Int = AppSection.patches.rawValue,
        filesNavigationPath: [FileBrowserDestination] = []
    ) {
        self.selectedTab = selectedTab
        var session = FilesTabSession()
        session.setActiveNavigationPath(filesNavigationPath)
        filesTabs = session
    }

    mutating func select(_ tab: Int) {
        guard AppSection.allCases.contains(where: { $0.rawValue == tab }) else {
            selectedTab = AppSection.patches.rawValue
            return
        }
        selectedTab = tab
    }

    mutating func setFilesNavigationPath(_ path: [FileBrowserDestination]) {
        filesTabs.setActiveNavigationPath(path)
    }

    var filesNavigationPath: [FileBrowserDestination] {
        filesTabs.activeTab?.navigationPath ?? []
    }

    mutating func setFilesTabs(_ session: FilesTabSession) {
        filesTabs = session
    }

    mutating func reconcileSelection() {
        guard AppSection.allCases.contains(where: { $0.rawValue == selectedTab }) else {
            selectedTab = AppSection.patches.rawValue
            return
        }
    }
}

// Retained as internal compatibility types for the file-browser implementation.
// The Files tab is no longer exposed through the main navigation.
struct FileBrowserDestination: Hashable {
    let containerPath: String
    let startPath: String
    let title: String
    let bundleID: String?
}

struct FilesTabState: Identifiable, Equatable {
    let id: UUID
    var customTitle: String?
    var navigationPath: [FileBrowserDestination]

    func displayTitle(defaultTitle: String) -> String {
        customTitle ?? navigationPath.last?.title ?? defaultTitle
    }

    var currentPath: String? {
        navigationPath.last?.startPath
    }
}

struct FilesTabSession: Equatable {
    private(set) var tabs: [FilesTabState]
    private(set) var selectedTabID: UUID

    init(initialTabID: UUID = UUID()) {
        tabs = [FilesTabState(id: initialTabID, customTitle: nil, navigationPath: [])]
        selectedTabID = initialTabID
    }

    var activeTab: FilesTabState? {
        tabs.first { $0.id == selectedTabID }
    }

    mutating func setActiveNavigationPath(_ path: [FileBrowserDestination]) {
        guard let index = tabs.firstIndex(where: { $0.id == selectedTabID }) else { return }
        tabs[index].navigationPath = path
    }

    mutating func openTab(
        id: UUID = UUID(),
        navigationPath: [FileBrowserDestination] = []
    ) {
        tabs.append(FilesTabState(id: id, customTitle: nil, navigationPath: navigationPath))
        selectedTabID = id
    }

    mutating func selectTab(_ id: UUID) {
        guard tabs.contains(where: { $0.id == id }) else { return }
        selectedTabID = id
    }

    mutating func renameTab(_ id: UUID, to name: String) {
        guard let index = tabs.firstIndex(where: { $0.id == id }) else { return }
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        tabs[index].customTitle = trimmed.isEmpty ? nil : trimmed
    }

    mutating func closeTab(_ id: UUID, replacementID: UUID = UUID()) {
        guard let index = tabs.firstIndex(where: { $0.id == id }) else { return }
        if tabs.count == 1 {
            tabs = [FilesTabState(id: replacementID, customTitle: nil, navigationPath: [])]
            selectedTabID = replacementID
            return
        }

        tabs.remove(at: index)
        if selectedTabID == id {
            selectedTabID = tabs[min(index, tabs.count - 1)].id
        }
    }

    mutating func closeOtherTabs(keeping id: UUID) {
        guard let keptTab = tabs.first(where: { $0.id == id }) else { return }
        tabs = [keptTab]
        selectedTabID = id
    }
}
