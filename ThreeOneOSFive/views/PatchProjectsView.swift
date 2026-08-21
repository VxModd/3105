import SwiftUI
import UIKit
import UniformTypeIdentifiers

private enum PatchPackagePickerPolicy {
    static let packageType = UTType(filenameExtension: "3105") ?? .data
    static let allowedContentTypes: [UTType] = [packageType, .data]
    static let copiesSelectedDocument = true
}

struct PatchProjectsView: View {
    @Environment(\.appLanguage) private var language
    @EnvironmentObject private var draftCoordinator: PatchDraftCoordinator
    @StateObject private var store = PatchProjectStore()
    @State private var showCreate = false
    @State private var showVariantComposer = false
    @State private var showImporter = false
    @State private var searchText = ""

    private var filteredItems: [PatchLibraryItem] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return store.items }
        return store.items.filter { item in
            if item.packageURL.lastPathComponent.localizedCaseInsensitiveContains(query) {
                return true
            }
            guard !item.variants.isEmpty else { return false }
            return item.variants.contains { project in
                project.name.localizedCaseInsensitiveContains(query)
                    || project.allBundleIdentifiers.contains {
                        $0.localizedCaseInsensitiveContains(query)
                    }
                    || project.directories.contains {
                        $0.relativePath.localizedCaseInsensitiveContains(query)
                    }
                    || project.rules.contains {
                        $0.relativePath.localizedCaseInsensitiveContains(query)
                            || $0.replacementFilename.localizedCaseInsensitiveContains(query)
                    }
            }
        }
    }

    init() {
#if targetEnvironment(simulator)
        _showCreate = State(
            initialValue: ProcessInfo.processInfo.arguments.contains("--simulate-patch-editor")
        )
#endif
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                AppSearchField(
                    text: $searchText,
                    prompt: language.text("patch.search"),
                    clearLabel: language.text("common.clear")
                )
                Divider()
                List {
                    if store.items.isEmpty && !store.isBusy {
                        emptyState
                            .listRowSeparator(.hidden)
                    } else if filteredItems.isEmpty && !store.isBusy {
                        searchEmptyState
                            .listRowSeparator(.hidden)
                    } else {
                        ForEach(filteredItems) { item in
                            itemRow(item)
                        }
                        .onDelete { offsets in
                            offsets.map { filteredItems[$0] }.forEach(store.delete)
                        }
                    }
                }
                .listStyle(.insetGrouped)
            }
            .navigationTitle(language.text("patch.title"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Menu {
                        Button {
                            showCreate = true
                        } label: {
                            Label(language.text("patch.new"), systemImage: "doc.badge.plus")
                        }
                        Button {
                            showVariantComposer = true
                        } label: {
                            Label(language.text("patch.new_variants"), systemImage: "square.stack.3d.up")
                        }
                        Button {
                            showImporter = true
                        } label: {
                            Label(language.text("patch.import"), systemImage: "square.and.arrow.down")
                        }
                    } label: {
                        if store.isBusy {
                            ProgressView()
                        } else {
                            Image(systemName: "plus")
                        }
                    }
                    .disabled(store.isBusy)
                    .accessibilityLabel(language.text("patch.add"))
                }
            }
            .sheet(isPresented: $showImporter) {
                FileDocumentPicker(
                    allowedContentTypes: PatchPackagePickerPolicy.allowedContentTypes,
                    copiesSelectedDocument: PatchPackagePickerPolicy.copiesSelectedDocument,
                    allowsMultipleSelection: false,
                    onSelection: { result in
                        showImporter = false
                        if case .success(let urls) = result, let url = urls.first {
                            store.importPackage(at: url)
                        }
                    },
                    onCancel: {
                        showImporter = false
                    }
                )
                .ignoresSafeArea()
            }
            .sheet(isPresented: $showVariantComposer) {
                PatchVariantComposerView { variants, password in
                    store.create(variants: variants, password: password)
                }
            }
            .sheet(isPresented: $showCreate) {
                PatchProjectEditorView(
                    existingProject: nil,
                    passwordIsProtected: false
                ) { project, password in
                    store.create(project: project, password: password)
                }
            }
            .sheet(item: $draftCoordinator.request) { request in
                PatchProjectEditorView(
                    existingProject: nil,
                    passwordIsProtected: false,
                    initialDraft: request.draft
                ) { project, password in
                    store.create(project: project, password: password)
                    draftCoordinator.clear()
                }
            }
            .sheet(item: $store.passwordRequest, onDismiss: store.cancelUnlock) { _ in
                PatchUnlockView(store: store)
            }
            .sheet(item: $store.passwordChangeRequest, onDismiss: store.cancelPasswordChange) { _ in
                PatchPasswordChangeView(store: store)
            }
            .alert(item: $store.alert) { alert in
                Alert(
                    title: Text(language.text(alert.titleKey)),
                    message: Text(alert.message(language: language)),
                    dismissButton: .default(Text(language.text("common.ok")))
                )
            }
            .onAppear(perform: consumeExternalImport)
            .onChange(of: draftCoordinator.importRequest?.id) { _ in
                consumeExternalImport()
            }
        }
    }

    private func consumeExternalImport() {
        guard let request = draftCoordinator.importRequest else { return }
        draftCoordinator.clearImport()
        store.importPackage(from: request.source)
    }

    @ViewBuilder
    private func itemRow(_ item: PatchLibraryItem) -> some View {
        if item.isLocked {
            Button { store.requestUnlock(for: item) } label: {
                PatchProjectRow(item: item, language: language)
            }
            .buttonStyle(.plain)
        } else {
            NavigationLink {
                PatchProjectDetailView(store: store, projectID: item.id)
            } label: {
                PatchProjectRow(item: item, language: language)
            }
        }
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "shippingbox")
                .font(.system(size: AppTheme.emptyIconSize, weight: .light))
                .foregroundStyle(AppTheme.accent)
            Text(language.text("patch.empty_title"))
                .font(.headline)
            Text(language.text("patch.empty_message"))
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            Button(language.text("patch.new")) { showCreate = true }
                .buttonStyle(.bordered)
                .controlSize(.large)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 64)
    }

    private var searchEmptyState: some View {
        VStack(spacing: 10) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: AppTheme.emptyIconSize, weight: .light))
                .foregroundStyle(.secondary)
            Text(language.text("patch.search_empty"))
                .font(.headline)
            Text(language.text("patch.search_empty_message"))
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 64)
    }
}

private struct PatchProjectRow: View {
    let item: PatchLibraryItem
    let language: AppLanguage

    var body: some View {
        HStack(spacing: 12) {
            AppRowIcon(systemName: item.isLocked ? "lock.doc.fill" : "shippingbox.fill")
            VStack(alignment: .leading, spacing: 3) {
                Text(item.project?.name ?? language.text("patch.locked_project"))
                    .font(.body.weight(.semibold))
                    .foregroundStyle(.primary)
                Text(item.isLocked
                     ? language.text("patch.tap_to_unlock")
                     : item.hasVariants
                        ? language.text("patch.variants_count", Int64(item.variants.count))
                        : language.text(
                            item.summary.schemaVersion >= 2 ? "patch.workspace_items_count" : "patch.rules_count",
                            Int64((item.project?.rules.count ?? 0) + (item.project?.directories.count ?? 0))
                        ))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            if item.summary.isPasswordProtected {
                Image(systemName: "key.fill")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .accessibilityLabel(language.text("patch.password_protected"))
            }
        }
        .padding(.vertical, 4)
    }
}

private struct PatchUnlockView: View {
    @Environment(\.appLanguage) private var language
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var store: PatchProjectStore
    @State private var password = ""

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    SecureField(language.text("patch.password"), text: $password)
                        .textContentType(.password)
                        .submitLabel(.done)
                        .onSubmit(unlock)
                        .onChange(of: password) { _ in
                            store.clearUnlockError()
                        }
                    if let errorKey = store.unlockErrorKey {
                        Text(language.text(errorKey))
                            .font(.footnote)
                            .foregroundStyle(.red)
                    }
                } footer: {
                    Text(language.text("patch.password_once_message"))
                }
            }
            .navigationTitle(language.text("patch.unlock"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(language.text("common.cancel")) { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(language.text("patch.unlock"), action: unlock)
                        .disabled(password.isEmpty || store.isBusy)
                }
            }
        }
    }

    private func unlock() {
        guard !password.isEmpty else { return }
        store.unlock(password: password)
    }
}

private struct PatchPasswordChangeView: View {
    @Environment(\.appLanguage) private var language
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var store: PatchProjectStore
    @State private var newPassword = ""
    @State private var confirmation = ""
    @State private var showMismatch = false

    private var canSubmit: Bool {
        !newPassword.isEmpty && newPassword == confirmation && !store.isBusy
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    SecureField(language.text("patch.new_password"), text: $newPassword)
                        .textContentType(.newPassword)
                        .onChange(of: newPassword) { _ in
                            showMismatch = false
                            store.clearPasswordChangeError()
                        }
                    SecureField(language.text("patch.confirm_password"), text: $confirmation)
                        .textContentType(.newPassword)
                        .onChange(of: confirmation) { _ in
                            showMismatch = false
                            store.clearPasswordChangeError()
                        }
                    if showMismatch {
                        Text(language.text("patch.password_mismatch"))
                            .font(.footnote)
                            .foregroundStyle(.red)
                    }
                    if let errorKey = store.passwordChangeErrorKey {
                        Text(language.text(errorKey))
                            .font(.footnote)
                            .foregroundStyle(.red)
                    }
                } footer: {
                    Text(language.text("patch.password_recovery_warning"))
                }
            }
            .navigationTitle(language.text("patch.change_password"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(language.text("common.cancel")) { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(language.text("common.done"), action: change)
                        .disabled(!canSubmit)
                }
            }
        }
    }

    private func change() {
        guard !newPassword.isEmpty else { return }
        guard newPassword == confirmation else {
            showMismatch = true
            return
        }
        store.changePassword(newPassword: newPassword)
    }
}

private struct PatchProjectDetailView: View {
    @Environment(\.appLanguage) private var language
    @ObservedObject var store: PatchProjectStore
    let projectID: UUID
    @State private var showEditor = false
    @State private var editingRule: PatchRule?
    @State private var showApplyConfirmation = false
    @State private var showRestoreConfirmation = false
    @State private var selectedVariantIndex = 0
    @State private var isWorking = false
    @State private var actionAlert: PatchStoreAlert?
    @State private var shareRequest: PatchShareRequest?

    private var item: PatchLibraryItem? {
        store.items.first(where: { $0.id == projectID })
    }

    private var selectedProject: PatchProject? {
        guard let item, !item.variants.isEmpty else { return nil }
        let index = min(selectedVariantIndex, item.variants.count - 1)
        return item.variants[index]
    }

    private var receipt: PatchTransactionReceipt? {
        DevicePatchService.latestReceipt(projectID: selectedProject?.id ?? projectID)
    }

    private var isWorkspaceProject: Bool {
        (item?.summary.schemaVersion ?? 1) >= 2
    }

    var body: some View {
        List {
            if let item, let project = selectedProject {
                if item.hasVariants {
                    Section {
                        Picker(language.text("patch.variant"), selection: $selectedVariantIndex) {
                            ForEach(item.variants.indices, id: \.self) { index in
                                Text(item.variants[index].name).tag(index)
                            }
                        }
                    } header: {
                        Text(language.text("patch.variants"))
                    } footer: {
                        Text(language.text("patch.variant_footer"))
                    }
                }

                if isWorkspaceProject {
                    Section {
                        ForEach(project.allBundleIdentifiers, id: \.self) { bundleID in
                            Label {
                                Text(bundleID)
                                    .font(.subheadline.monospaced())
                            } icon: {
                                Image(systemName: "app.dashed")
                                    .foregroundStyle(AppTheme.accent)
                            }
                        }
                        LabeledContent(language.text("patch.files")) {
                            Text("\(project.rules.count)")
                        }
                        LabeledContent(language.text("patch.folders")) {
                            Text("\(project.directories.count)")
                        }
                        if let workspaceURL = PatchWorkspaceService.workspaceURL(projectID: project.id) {
                            NavigationLink {
                                FileBrowserView(
                                    containerPath: workspaceURL.path,
                                    title: project.name,
                                    bundleID: nil
                                )
                            } label: {
                                Label(
                                    language.text("patch.open_workspace"),
                                    systemImage: "folder"
                                )
                            }
                        }
                    } header: {
                        Text(language.text("patch.workspace"))
                    } footer: {
                        Text(language.text("patch.workspace_detail_footer"))
                    }
                } else {
                    Section {
                        ForEach(project.rules) { rule in
                            Button {
                                editingRule = rule
                            } label: {
                                HStack(spacing: 10) {
                                    ruleSummary(rule)
                                    Spacer(minLength: 8)
                                    Image(systemName: "chevron.right")
                                        .font(.caption.weight(.semibold))
                                        .foregroundStyle(.tertiary)
                                }
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            .accessibilityHint(language.text("patch.edit_rule_hint"))
                        }
                    } header: {
                        Text(language.text("patch.rules"))
                    } footer: {
                        Text(language.text("patch.legacy_footer"))
                    }
                }

                Section(language.text("patch.password")) {
                    HStack(spacing: 12) {
                        Image(systemName: item.summary.isPasswordProtected ? "lock.fill" : "lock.open")
                            .foregroundStyle(AppTheme.accent)
                            .frame(width: 24)
                        VStack(alignment: .leading, spacing: 3) {
                            Text(language.text(item.summary.isPasswordProtected
                                ? "patch.password_locked"
                                : "patch.no_password"))
                                .font(.subheadline)
                            if item.summary.isPasswordProtected {
                                Text(language.text("patch.unlocked"))
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                    if item.contentKey != nil {
                        Button {
                            store.requestPasswordChange(for: item)
                        } label: {
                            Label(
                                language.text(item.summary.isPasswordProtected
                                    ? "patch.change_password"
                                    : "patch.set_password"),
                                systemImage: "key.fill"
                            )
                        }
                        .disabled(isWorking || store.isBusy)
                    }
                }

                Section {
                    Button {
                        showApplyConfirmation = true
                    } label: {
                        actionLabel("patch.apply", systemImage: "checkmark.shield.fill")
                    }
                    .disabled(isWorking)

                    if receipt != nil {
                        Button(role: .destructive) {
                            showRestoreConfirmation = true
                        } label: {
                            actionLabel("patch.restore", systemImage: "arrow.uturn.backward.circle")
                        }
                        .disabled(isWorking)
                    }

                    Button(action: prepareExport) {
                        actionLabel("patch.export", systemImage: "square.and.arrow.up")
                    }
                    .disabled(isWorking)
                } footer: {
                    Text(language.text("patch.apply_footer"))
                }
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle(selectedProject?.name ?? language.text("patch.title"))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                if isWorking {
                    ProgressView()
                } else if !isWorkspaceProject {
                    Button(language.text("patch.edit")) { showEditor = true }
                        .disabled(item?.project == nil)
                }
            }
        }
        .sheet(isPresented: $showEditor) {
            if let item, let project = selectedProject {
                PatchProjectEditorView(
                    existingProject: project,
                    passwordIsProtected: item.summary.isPasswordProtected
                ) { updatedProject, _ in
                    store.update(project: updatedProject, packageID: projectID)
                }
            }
        }
        .sheet(item: $editingRule) { rule in
            PatchRuleEditorView(rule: rule) { updatedRule in
                updateRule(updatedRule)
            }
        }
        .confirmationDialog(
            language.text("patch.apply_confirm_title"),
            isPresented: $showApplyConfirmation,
            titleVisibility: .visible
        ) {
            Button(language.text("patch.apply")) { apply() }
            Button(language.text("common.cancel"), role: .cancel) {}
        } message: {
            Text(language.text("patch.apply_confirm_message"))
        }
        .confirmationDialog(
            language.text("patch.restore_confirm_title"),
            isPresented: $showRestoreConfirmation,
            titleVisibility: .visible
        ) {
            Button(language.text("patch.restore"), role: .destructive) { restore() }
            Button(language.text("common.cancel"), role: .cancel) {}
        }
        .alert(item: $actionAlert) { alert in
            Alert(
                title: Text(language.text(alert.titleKey)),
                message: Text(alert.message(language: language)),
                dismissButton: .default(Text(language.text("common.ok")))
            )
        }
        .sheet(item: $shareRequest) { request in
            PatchActivityView(items: [request.url])
                .ignoresSafeArea()
        }
    }

    private func actionLabel(_ key: String, systemImage: String) -> some View {
        Label(language.text(key), systemImage: systemImage)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func ruleSummary(_ rule: PatchRule) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(rule.bundleID)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.primary)
            Text(rule.relativePath)
                .font(.caption.monospaced())
                .foregroundStyle(.secondary)
                .lineLimit(2)
            Label(rule.replacementFilename, systemImage: "arrow.triangle.2.circlepath")
                .font(.caption)
                .foregroundStyle(AppTheme.accent)
        }
        .padding(.vertical, 3)
    }

    private func updateRule(_ updatedRule: PatchRule) {
        guard var project = selectedProject,
              let index = project.rules.firstIndex(where: { $0.id == updatedRule.id }) else {
            return
        }
        project.rules[index] = updatedRule
        project.updatedAt = Date()
        do {
            try PatchPackageCodec.validate(project)
            store.update(project: project, packageID: projectID)
        } catch let error as PatchPackageError {
            actionAlert = PatchStoreAlert(
                titleKey: "common.failed",
                messageKey: error.localizationKey,
                messageArgument: error.localizationArgument
            )
        } catch {
            actionAlert = PatchStoreAlert(
                titleKey: "common.failed",
                messageKey: "patch.error.invalid_project"
            )
        }
    }

    private func apply() {
        guard let item, let baseProject = selectedProject else { return }
        isWorking = true
        Task.detached(priority: .userInitiated) {
            do {
                let project = item.summary.schemaVersion >= 2
                    ? try PatchProjectLibrary.synchronizeWorkspace(item: item, variantID: baseProject.id)
                    : baseProject
                _ = try DevicePatchService.apply(project: project)
                await MainActor.run {
                    store.reload()
                    isWorking = false
                    actionAlert = PatchStoreAlert(titleKey: "common.done", messageKey: "patch.applied_message")
                }
            } catch let error as PatchPackageError {
                await MainActor.run {
                    isWorking = false
                    actionAlert = PatchStoreAlert(
                        titleKey: "common.failed",
                        messageKey: error.localizationKey,
                        messageArgument: error.localizationArgument
                    )
                }
            } catch {
                await MainActor.run {
                    isWorking = false
                    actionAlert = PatchStoreAlert(titleKey: "common.failed", messageKey: "patch.error.apply")
                }
            }
        }
    }

    private func prepareExport() {
        guard let item else { return }
        isWorking = true
        Task.detached(priority: .userInitiated) {
            do {
                if item.summary.schemaVersion >= 2 {
                    _ = try PatchProjectLibrary.synchronizeWorkspace(item: item)
                }
                await MainActor.run {
                    store.reload()
                    isWorking = false
                    shareRequest = PatchShareRequest(url: item.packageURL)
                }
            } catch let error as PatchPackageError {
                await MainActor.run {
                    isWorking = false
                    actionAlert = PatchStoreAlert(
                        titleKey: "common.failed",
                        messageKey: error.localizationKey,
                        messageArgument: error.localizationArgument
                    )
                }
            } catch {
                await MainActor.run {
                    isWorking = false
                    actionAlert = PatchStoreAlert(
                        titleKey: "common.failed",
                        messageKey: "patch.error.invalid_project"
                    )
                }
            }
        }
    }

    private func restore() {
        guard let receipt else { return }
        isWorking = true
        Task.detached(priority: .userInitiated) {
            do {
                try DevicePatchService.restore(receipt: receipt)
                await MainActor.run {
                    isWorking = false
                    actionAlert = PatchStoreAlert(titleKey: "common.done", messageKey: "patch.restored_message")
                }
            } catch let error as PatchPackageError {
                await MainActor.run {
                    isWorking = false
                    actionAlert = PatchStoreAlert(
                        titleKey: "common.failed",
                        messageKey: error.localizationKey,
                        messageArgument: error.localizationArgument
                    )
                }
            } catch {
                await MainActor.run {
                    isWorking = false
                    actionAlert = PatchStoreAlert(titleKey: "common.failed", messageKey: "patch.error.restore")
                }
            }
        }
    }
}

private struct PatchVariantEditorContext: Identifiable {
    let id = UUID()
    let index: Int
    let project: PatchProject?
}

private struct PatchVariantComposerView: View {
    @Environment(\.appLanguage) private var language
    @Environment(\.dismiss) private var dismiss
    let onCreate: ([PatchProject], String?) -> Void

    @State private var variants: [PatchProject?] = [nil, nil]
    @State private var password = ""
    @State private var editor: PatchVariantEditorContext?
    @State private var validationMessageKey: String?

    private var canCreate: Bool {
        variants.allSatisfy { $0 != nil }
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    ForEach(variants.indices, id: \.self) { index in
                        Button {
                            editor = PatchVariantEditorContext(index: index, project: variants[index])
                        } label: {
                            HStack(spacing: 10) {
                                Image(systemName: variants[index] == nil ? "plus.circle" : "checkmark.circle.fill")
                                    .foregroundStyle(variants[index] == nil ? Color.secondary : AppTheme.accent)
                                VStack(alignment: .leading, spacing: 3) {
                                    Text(variants[index]?.name ?? language.text("patch.variant_empty"))
                                        .foregroundStyle(.primary)
                                    Text(variants[index]?.allBundleIdentifiers.joined(separator: ", ") ?? language.text("patch.variant_tap_to_edit"))
                                        .font(.caption.monospaced())
                                        .foregroundStyle(.secondary)
                                        .lineLimit(2)
                                }
                                Spacer()
                                Image(systemName: "chevron.right")
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(.tertiary)
                            }
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                    Button {
                        variants.append(nil)
                    } label: {
                        Label(language.text("patch.add_variant"), systemImage: "plus.circle.fill")
                    }
                } header: {
                    Text(language.text("patch.variants"))
                } footer: {
                    Text(language.text("patch.variant_composer_footer"))
                }

                Section(language.text("patch.password")) {
                    SecureField(language.text("patch.password_optional"), text: $password)
                        .textContentType(.newPassword)
                }

                if let validationMessageKey {
                    Section {
                        Label(language.text(validationMessageKey), systemImage: "exclamationmark.triangle.fill")
                            .foregroundStyle(.red)
                    }
                }
            }
            .navigationTitle(language.text("patch.new_variants"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(language.text("common.cancel")) { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(language.text("common.done"), action: create)
                        .disabled(!canCreate)
                }
            }
            .sheet(item: $editor) { context in
                PatchProjectEditorView(
                    existingProject: context.project,
                    passwordIsProtected: false
                ) { project, _ in
                    variants[context.index] = project
                    editor = nil
                }
            }
        }
    }

    private func create() {
        let projects = variants.compactMap { $0 }
        guard projects.count == variants.count, projects.count >= 2 else {
            validationMessageKey = "patch.error.invalid_project"
            return
        }
        onCreate(projects, password.isEmpty ? nil : password)
        dismiss()
    }
}

private struct PatchShareRequest: Identifiable {
    let id = UUID()
    let url: URL
}

private struct PatchActivityView: UIViewControllerRepresentable {
    let items: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }

    func updateUIViewController(
        _ uiViewController: UIActivityViewController,
        context: Context
    ) {}
}
