import SwiftUI
import UIKit

struct ContentView: View {
    @Environment(\.appLanguage) private var language
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @EnvironmentObject private var patchDraftCoordinator: PatchDraftCoordinator
    @State private var tabNavigation: AppTabNavigationState

    init() {
#if targetEnvironment(simulator)
        let initialTab = AppSection.patches.rawValue
        _tabNavigation = State(initialValue: AppTabNavigationState(selectedTab: initialTab))
#else
        _tabNavigation = State(initialValue: AppTabNavigationState())
#endif
    }

    var body: some View {
        Group {
            if horizontalSizeClass == .regular {
                regularLayout
            } else {
                compactLayout
            }
        }
        .tint(AppTheme.accent)
        .imageScale(.small)
        .onChange(of: patchDraftCoordinator.request?.id) { requestID in
            if requestID != nil {
                tabNavigation.select(AppSection.patches.rawValue)
            }
        }
        .onChange(of: patchDraftCoordinator.importRequest?.id) { requestID in
            if requestID != nil {
                tabNavigation.select(AppSection.patches.rawValue)
            }
        }
        .onAppear {
            tabNavigation.reconcileSelection()
        }
    }

    private var compactLayout: some View {
        sectionContent(.patches)
    }

    private var regularLayout: some View {
        sectionContent(.patches)
    }

    @ViewBuilder
    private func sectionContent(_ section: AppSection) -> some View {
        switch section {
        case .home:
            DashboardView()
        case .patches:
            PatchAccessGateView()
        }
    }

    private var tabSelection: Binding<Int> {
        Binding(
            get: { tabNavigation.selectedTab },
            set: { tabNavigation.select($0) }
        )
    }

}

private struct CompactTabLabel: View {
    let title: String
    let systemImage: String

    @ViewBuilder
    var body: some View {
        if let image = UIImage(
            systemName: systemImage,
            withConfiguration: UIImage.SymbolConfiguration(pointSize: 17, weight: .medium)
        )?.withRenderingMode(.alwaysTemplate) {
            Image(uiImage: image)
        } else {
            Image(systemName: systemImage)
                .font(.system(size: 17, weight: .medium))
        }
        Text(title)
    }
}

private extension AppSection {
    var titleKey: String {
        switch self {
        case .home: return "tab.home"
        case .patches: return "tab.exploits"
        }
    }

    var systemImage: String {
        switch self {
        case .home: return "house.fill"
        case .patches: return "bolt.fill"
        }
    }
}

private struct PatchAccessGateView: View {
    @Environment(\.appLanguage) private var language
    @State private var username = ""
    @State private var password = ""
    @State private var isAuthenticated = false
    @State private var isLoading = false
    @State private var showInvalidCredentials = false

    var body: some View {
        Group {
            if isAuthenticated {
                ExploitsView()
            } else {
                loginView
            }
        }
    }

    private var loginView: some View {
        ZStack {
            Color.black
                .ignoresSafeArea()
            ScrollView {
                VStack(spacing: 24) {
                    AppLogo(size: 86)
                        .shadow(color: AppTheme.accent.opacity(0.32), radius: 22, y: 8)
                        .padding(.top, 34)

                    VStack(spacing: 8) {
                        Text("Zscript")
                            .font(.system(size: 32, weight: .bold, design: .rounded))
                            .foregroundStyle(.white)
                        Text(language.text("patch.login_subtitle"))
                            .font(.subheadline)
                            .foregroundStyle(Color.white.opacity(0.62))
                            .multilineTextAlignment(.center)
                    }

                    VStack(spacing: 14) {
                        loginField(
                            title: language.text("patch.login_username"),
                            systemImage: "person.fill",
                            text: $username,
                            isSecure: false
                        )
                        loginField(
                            title: language.text("patch.login_password"),
                            systemImage: "lock.fill",
                            text: $password,
                            isSecure: true
                        )
                    }
                    .padding(18)
                    .background(
                        Color.white.opacity(0.08),
                        in: RoundedRectangle(cornerRadius: 22, style: .continuous)
                    )
                    .overlay {
                        RoundedRectangle(cornerRadius: 22, style: .continuous)
                            .stroke(Color.white.opacity(0.10), lineWidth: 1)
                    }

                    if showInvalidCredentials {
                        Label(
                            language.text("patch.login_invalid"),
                            systemImage: "exclamationmark.circle.fill"
                        )
                        .font(.footnote.weight(.medium))
                        .foregroundStyle(Color.red.opacity(0.95))
                        .multilineTextAlignment(.center)
                    }

                    Button(action: authenticate) {
                        HStack(spacing: 10) {
                            if isLoading {
                                ProgressView()
                                    .tint(.white)
                            }
                            Text(language.text("patch.login_button"))
                                .font(.headline)
                        }
                        .frame(maxWidth: .infinity)
                        .frame(height: 52)
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.white)
                    .background(
                        AppTheme.accent,
                        in: RoundedRectangle(cornerRadius: 16, style: .continuous)
                    )
                    .disabled(username.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                        || password.isEmpty
                        || isLoading)
                    .opacity(username.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                        || password.isEmpty
                        || isLoading ? 0.55 : 1)
                    .accessibilityLabel(language.text("patch.login_button"))
                }
                .padding(.horizontal, 28)
                .padding(.bottom, 36)
                .frame(maxWidth: 460)
                .frame(maxWidth: .infinity)
            }
            .scrollIndicators(.hidden)
        }
        .preferredColorScheme(.dark)
    }

    @ViewBuilder
    private func loginField(
        title: String,
        systemImage: String,
        text: Binding<String>,
        isSecure: Bool
    ) -> some View {
        HStack(spacing: 12) {
            Image(systemName: systemImage)
                .foregroundStyle(AppTheme.accent)
                .frame(width: 22)
            if isSecure {
                SecureField(title, text: text)
                    .textContentType(.password)
            } else {
                TextField(title, text: text)
                    .textContentType(.username)
            }
        }
        .foregroundStyle(.white)
        .textInputAutocapitalization(.never)
        .autocorrectionDisabled()
        .padding(.horizontal, 14)
        .frame(height: 50)
        .background(
            Color.black.opacity(0.42),
            in: RoundedRectangle(cornerRadius: 14, style: .continuous)
        )
        .overlay {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(Color.white.opacity(0.10), lineWidth: 1)
        }
        .onChange(of: text.wrappedValue) { _ in
            showInvalidCredentials = false
        }
    }

    private func authenticate() {
        let submittedUsername = username.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !submittedUsername.isEmpty, !password.isEmpty, !isLoading else { return }
        isLoading = true
        showInvalidCredentials = false
        Task {
            let valid = await PatchRemoteAuthService.authenticate(
                username: submittedUsername,
                password: password
            )
            await MainActor.run {
                isLoading = false
                if valid {
                    isAuthenticated = true
                } else {
                    showInvalidCredentials = true
                }
            }
        }
    }
}

private enum PatchRemoteAuthService {
    private static let endpoint = URL(string: "https://pastebin.com/raw/8jX6KqDb")!

    static func authenticate(username: String, password: String) async -> Bool {
        var request = URLRequest(url: endpoint)
        request.cachePolicy = .reloadIgnoringLocalCacheData
        request.timeoutInterval = 15
        request.setValue("text/plain", forHTTPHeaderField: "Accept")

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let httpResponse = response as? HTTPURLResponse,
                  (200..<300).contains(httpResponse.statusCode),
                  let text = String(data: data, encoding: .utf8) else {
                return false
            }

            var expectedUsername: String?
            var expectedPassword: String?
            for line in text.split(whereSeparator: \.isNewline) {
                let parts = line.split(separator: ":", maxSplits: 1, omittingEmptySubsequences: false)
                guard parts.count == 2 else { continue }
                let key = String(parts[0]).trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
                let value = String(parts[1]).trimmingCharacters(in: .whitespacesAndNewlines)
                switch key {
                case "user": expectedUsername = value
                case "password": expectedPassword = value
                default: continue
                }
            }
            guard let expectedUsername, let expectedPassword else { return false }
            return username == expectedUsername && password == expectedPassword
        } catch {
            return false
        }
    }
}

private struct DashboardView: View {
    @Environment(\.appLanguage) private var language
    @EnvironmentObject private var appState: AppState
    @State private var showSettings = false
    @State private var showLogs = false

    var body: some View {
        NavigationStack {
            List {
                deviceSection
            }
            .navigationBarTitleDisplayMode(.inline)
            .tint(AppTheme.accent)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button { showLogs = true } label: {
                        Image(systemName: "apple.terminal")
                    }
                    .accessibilityLabel(language.text("accessibility.open_logs"))
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button { showSettings = true } label: {
                        Image(systemName: "gearshape")
                    }
                    .accessibilityLabel(language.text("accessibility.open_settings"))
                }
            }
            .sheet(isPresented: $showSettings) { SettingsView() }
            .sheet(isPresented: $showLogs) { LogView() }
        }
    }

    private var deviceSection: some View {
        Section {
            LabeledContent(language.text("dashboard.hardware_model")) {
                Text(AppInfo.displayMachineName)
                    .font(.body.monospaced())
            }
            LabeledContent(language.text("settings.ios_version")) {
                Text("\(AppInfo.osVersion) (\(AppInfo.osBuild))")
                    .font(.body.monospaced())
            }
            HStack {
                Text(language.text("settings.compatibility"))
                Spacer()
                Text(language.text(appState.isSupported ? "settings.supported" : "settings.unsupported"))
                    .foregroundStyle(appState.isSupported ? Color.green : Color.red)
            }

            if appState.kernelExploitApplicable && AppInfo.versionTuple.major < 26 {
                HStack {
                    Text(language.text("dashboard.kernel_status"))
                    Spacer()
                    if appState.kernelExploitRunning {
                        HStack(spacing: 6) {
                            ProgressView().controlSize(.small)
                            Text(language.text("dashboard.kernel_running"))
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                    } else {
                        Text(language.text(appState.exploitStatus.isSuccess ? "dashboard.kernel_active" : "dashboard.kernel_inactive"))
                            .foregroundStyle(appState.exploitStatus.isSuccess ? Color.green : Color.secondary)
                    }
                }
            }
        } header: {
            Text(language.text("common.device"))
        } footer: {
            Text(language.text("settings.supported_range_summary"))
        }
    }
}

private struct BundledExploitDefinition {
    let resourceName: String
    let fileExtension: String
    let titleKey: String
    let descriptionKey: String
    let targetKey: String
    let systemImage: String
}

private enum BundledExploitCatalog {
    static let cacheRes = BundledExploitDefinition(
        resourceName: "CacheResReplacement",
        fileExtension: "3105",
        titleKey: "exploits.cache_res_title",
        descriptionKey: "exploits.cache_res_description",
        targetKey: "exploits.cache_res_target",
        systemImage: "arrow.triangle.2.circlepath"
    )

    static func loadVariants(for definition: BundledExploitDefinition) throws -> [PatchProject] {
        guard let url = Bundle.main.url(
            forResource: definition.resourceName,
            withExtension: definition.fileExtension
        ) else {
            throw PatchPackageError.invalidProject
        }
        let data = try Data(contentsOf: url, options: .mappedIfSafe)
        let decoded = try PatchPackageCodec.decode(data, password: nil)
        if !decoded.variants.isEmpty {
            return decoded.variants
        }
        // Fallback for v1/v2 packages that might be bundled
        return [decoded.project]
    }
}

private enum ExploitCardStatus: Equatable {
    case ready
    case working
    case success
    case error

    var textKey: String {
        switch self {
        case .ready: return "exploits.status_ready"
        case .working: return "exploits.status_working"
        case .success: return "exploits.status_success"
        case .error: return "exploits.status_error"
        }
    }

    var color: Color {
        switch self {
        case .ready: return .secondary
        case .working: return AppTheme.accent
        case .success: return .green
        case .error: return .red
        }
    }
}

private struct ExploitsView: View {
    @Environment(\.appLanguage) private var language
    @State private var showInfo = true
    @State private var showSettings = false
    @State private var showLogs = false
    @State private var variants: [PatchProject] = []
    @State private var selectedVariantID: UUID?
    @State private var status: ExploitCardStatus = .ready
    @State private var isWorking = false
    @State private var hasReceipt = false

    private var selectedProject: PatchProject? {
        variants.first { $0.id == selectedVariantID }
    }

    private let definition = BundledExploitCatalog.cacheRes

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    hero
                    overviewStrip
                    infoCard
                    exploitCard
                }
                .padding(.horizontal, 16)
                .padding(.top, 10)
                .padding(.bottom, 28)
            }
            .background(AppTheme.pageBackground)
            .navigationTitle("")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    Text(language.text("tab.exploits"))
                        .font(.headline.weight(.semibold))
                }
            }
            .sheet(isPresented: $showSettings) { SettingsView() }
            .sheet(isPresented: $showLogs) { LogView() }
            .task {
                loadBundledProject()
            }
        }
    }

    private var hero: some View {
        HStack(spacing: 14) {
            AppLogo(size: 54)
                .shadow(color: AppTheme.accent.opacity(0.28), radius: 14, y: 6)
            VStack(alignment: .leading, spacing: 3) {
                Text("Zscript")
                    .font(.title2.weight(.bold))
                Text(language.text("exploits.brandline"))
                    .font(.caption.weight(.semibold))
                    .tracking(1.1)
                    .foregroundStyle(AppTheme.accent)
            }
            Spacer(minLength: 12)
            VStack(alignment: .trailing, spacing: 3) {
                Text(language.text("exploits.available"))
                    .font(.system(size: 9, weight: .bold, design: .rounded))
                    .tracking(0.7)
                    .foregroundStyle(AppTheme.accent)
                Text(AppInfo.marketingVersion)
                    .font(.caption.monospaced())
                    .foregroundStyle(.secondary)
            }
        }
        .padding(16)
        .background(
            LinearGradient(
                colors: [
                    AppTheme.accent.opacity(0.22),
                    AppTheme.consoleBackground,
                    AppTheme.consoleBackground
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            ),
            in: RoundedRectangle(cornerRadius: 22, style: .continuous)
        )
        .overlay {
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .stroke(AppTheme.accent.opacity(0.20), lineWidth: 1)
        }
        .shadow(color: AppTheme.accent.opacity(0.10), radius: 18, y: 8)
    }

    private var overviewStrip: some View {
        HStack(spacing: 10) {
            metricTile(
                title: language.text("exploits.active_target"),
                value: "Free Fire",
                systemImage: "scope"
            )
            metricTile(
                title: language.text("exploits.status_label"),
                value: language.text(status.textKey),
                systemImage: status == .success ? "checkmark.circle.fill" : "bolt.fill",
                tint: status.color
            )
        }
    }

    private var infoCard: some View {
        DisclosureGroup(isExpanded: $showInfo) {
            VStack(alignment: .leading, spacing: 10) {
                Divider()
                infoRow(
                    title: language.text("dashboard.hardware_model"),
                    value: AppInfo.displayMachineName,
                    systemImage: "iphone"
                )
                infoRow(
                    title: language.text("settings.ios_version"),
                    value: "\(AppInfo.osVersion) (\(AppInfo.osBuild))",
                    systemImage: "gearshape.2"
                )
                infoRow(
                    title: language.text("exploits.target"),
                    value: language.text("exploits.cache_res_target"),
                    systemImage: "scope"
                )
                HStack(spacing: 10) {
                    quickAction(
                        title: language.text("exploits.logs"),
                        systemImage: "apple.terminal"
                    ) {
                        showLogs = true
                    }
                    quickAction(
                        title: language.text("exploits.settings"),
                        systemImage: "gearshape"
                    ) {
                        showSettings = true
                    }
                }
            }
            .padding(.top, 8)
        } label: {
            HStack(spacing: 10) {
                Image(systemName: "info.circle.fill")
                    .foregroundStyle(AppTheme.accent)
                VStack(alignment: .leading, spacing: 2) {
                    Text(language.text("exploits.info"))
                        .font(.subheadline.weight(.semibold))
                    Text(language.text("exploits.info_footer"))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .tint(AppTheme.accent)
        .padding(14)
        .background(
            AppTheme.consoleBackground,
            in: RoundedRectangle(cornerRadius: 20, style: .continuous)
        )
        .overlay {
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .stroke(Color.white.opacity(0.06), lineWidth: 1)
        }
    }

    private var exploitCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top, spacing: 12) {
                ZStack {
                    RoundedRectangle(cornerRadius: 15, style: .continuous)
                        .fill(AppTheme.accent.opacity(0.16))
                    Image(systemName: definition.systemImage)
                        .font(.system(size: 21, weight: .bold))
                        .foregroundStyle(AppTheme.accent)
                }
                .frame(width: 48, height: 48)

                VStack(alignment: .leading, spacing: 3) {
                    Text(language.text(definition.titleKey))
                        .font(.title3.weight(.bold))
                    
                    if variants.count > 1 {
                        Menu {
                            ForEach(variants) { variant in
                                Button {
                                    selectedVariantID = variant.id
                                    hasReceipt = DevicePatchService.latestReceipt(projectID: variant.id) != nil
                                } label: {
                                    HStack {
                                        Text(variant.name)
                                        if selectedVariantID == variant.id {
                                            Image(systemName: "checkmark")
                                        }
                                    }
                                }
                            }
                        } label: {
                            HStack(spacing: 4) {
                                Text(selectedProject?.name ?? "...")
                                    .font(.subheadline.weight(.medium))
                                Image(systemName: "chevron.down")
                                    .font(.system(size: 10, weight: .bold))
                            }
                            .foregroundStyle(AppTheme.accent)
                            .padding(.vertical, 2)
                        }
                    }
                }
                Spacer(minLength: 8)
                statusBadge
            }

            HStack(spacing: 8) {
                Image(systemName: "scope")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(AppTheme.accent)
                Text(language.text(definition.targetKey))
                    .font(.caption.monospaced())
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                Spacer(minLength: 4)
                Image(systemName: "checkmark.shield.fill")
                    .font(.caption)
                    .foregroundStyle(.green)
            }
            .padding(.horizontal, 11)
            .frame(height: 34)
            .background(Color.white.opacity(0.05), in: Capsule())

            VStack(spacing: 9) {
                Button(action: inject) {
                    HStack(spacing: 10) {
                        if isWorking {
                            ProgressView()
                                .tint(.white)
                        }
                        Text(language.text("exploits.inject"))
                            .font(.headline.weight(.semibold))
                        Spacer()
                        Image(systemName: "bolt.fill")
                            .font(.body.weight(.bold))
                    }
                    .padding(.horizontal, 16)
                    .frame(maxWidth: .infinity)
                    .frame(height: 48)
                }
                .buttonStyle(.plain)
                .foregroundStyle(.white)
                .background(
                    LinearGradient(
                        colors: [AppTheme.accent, AppTheme.accent.opacity(0.72)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    in: RoundedRectangle(cornerRadius: 15, style: .continuous)
                )
                .shadow(color: AppTheme.accent.opacity(0.22), radius: 10, y: 5)
                .disabled(isWorking || selectedProject == nil)
                .opacity(isWorking || selectedProject == nil ? 0.55 : 1)

                if hasReceipt {
                    Button(action: restore) {
                        HStack(spacing: 10) {
                            Image(systemName: "arrow.uturn.backward.circle")
                            Text(language.text("exploits.restore"))
                                .font(.subheadline.weight(.semibold))
                            Spacer()
                        }
                        .padding(.horizontal, 16)
                        .frame(maxWidth: .infinity)
                        .frame(height: 42)
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(AppTheme.accent)
                    .background(
                        AppTheme.accent.opacity(0.10),
                        in: RoundedRectangle(cornerRadius: 14, style: .continuous)
                    )
                    .overlay {
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .stroke(AppTheme.accent.opacity(0.25), lineWidth: 1)
                    }
                    .disabled(isWorking)
                }
            }
        }
        .padding(17)
        .background(
            AppTheme.consoleBackground,
            in: RoundedRectangle(cornerRadius: 24, style: .continuous)
        )
        .overlay {
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .stroke(
                    LinearGradient(
                        colors: [AppTheme.accent.opacity(0.34), Color.white.opacity(0.05)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    lineWidth: 1
                )
        }
        .shadow(color: .black.opacity(0.24), radius: 18, y: 9)
    }

    private var statusBadge: some View {
        HStack(spacing: 5) {
            Circle()
                .fill(status.color)
                .frame(width: 6, height: 6)
            Text(language.text(status.textKey))
                .font(.system(size: 10, weight: .semibold, design: .monospaced))
                .foregroundStyle(status.color)
        }
        .padding(.horizontal, 8)
        .frame(height: 25)
        .background(status.color.opacity(0.10), in: Capsule())
    }

    private func metricTile(
        title: String,
        value: String,
        systemImage: String,
        tint: Color = AppTheme.accent
    ) -> some View {
        HStack(spacing: 9) {
            Image(systemName: systemImage)
                .font(.caption.weight(.bold))
                .foregroundStyle(tint)
                .frame(width: 22, height: 22)
                .background(tint.opacity(0.12), in: Circle())
            VStack(alignment: .leading, spacing: 1) {
                Text(title.uppercased())
                    .font(.system(size: 8, weight: .bold, design: .rounded))
                    .tracking(0.5)
                    .foregroundStyle(.secondary)
                Text(value)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 11)
        .frame(maxWidth: .infinity, minHeight: 48)
        .background(AppTheme.consoleBackground, in: RoundedRectangle(cornerRadius: 15, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 15, style: .continuous)
                .stroke(Color.white.opacity(0.05), lineWidth: 1)
        }
    }

    private func infoRow(title: String, value: String, systemImage: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: systemImage)
                .foregroundStyle(AppTheme.accent)
                .frame(width: 22)
            Text(title)
                .font(.subheadline)
            Spacer(minLength: 12)
            Text(value)
                .font(.caption.monospaced())
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.trailing)
        }
    }

    private func quickAction(title: String, systemImage: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Label(title, systemImage: systemImage)
                .font(.caption.weight(.semibold))
                .frame(maxWidth: .infinity)
                .frame(height: 38)
        }
        .buttonStyle(.bordered)
        .tint(AppTheme.accent)
    }

    private func loadBundledProject() {
        guard variants.isEmpty else { return }
        do {
            let loadedVariants = try BundledExploitCatalog.loadVariants(for: definition)
            variants = loadedVariants
            if let first = loadedVariants.first {
                selectedVariantID = first.id
                hasReceipt = DevicePatchService.latestReceipt(projectID: first.id) != nil
            }
        } catch {
            status = .error
        }
    }

    private func inject() {
        guard let project = selectedProject, !isWorking else { return }
        isWorking = true
        status = .working
        Task.detached(priority: .userInitiated) {
            do {
                _ = try DevicePatchService.apply(project: project)
                await MainActor.run {
                    isWorking = false
                    status = .success
                    hasReceipt = true
                }
            } catch {
                await MainActor.run {
                    isWorking = false
                    status = .error
                }
            }
        }
    }

    private func restore() {
        guard let project = selectedProject,
              let receipt = DevicePatchService.latestReceipt(projectID: project.id),
              !isWorking else { return }
        isWorking = true
        status = .working
        Task.detached(priority: .userInitiated) {
            do {
                try DevicePatchService.restore(receipt: receipt)
                await MainActor.run {
                    isWorking = false
                    status = .success
                    hasReceipt = false
                }
            } catch {
                await MainActor.run {
                    isWorking = false
                    status = .error
                }
            }
        }
    }
}
