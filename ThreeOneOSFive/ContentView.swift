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

    private let definition = BundledExploitCatalog.cacheRes
    private let electricBlue = Color(red: 0.26, green: 0.70, blue: 1.00)
    private let violet = Color(red: 0.53, green: 0.34, blue: 1.00)
    private let panel = Color(red: 0.075, green: 0.08, blue: 0.11)

    private var selectedProject: PatchProject? {
        variants.first { $0.id == selectedVariantID }
    }

    var body: some View {
        NavigationStack {
            ZStack {
                Color.black.ignoresSafeArea()
                ambientBackground

                ScrollView(showsIndicators: false) {
                    VStack(alignment: .leading, spacing: 20) {
                        topBar
                        identityHeader
                        primaryModule
                        telemetry
                        nodePanel
                    }
                    .padding(.horizontal, 18)
                    .padding(.top, 10)
                    .padding(.bottom, 34)
                }
            }
            .navigationBarHidden(true)
            .sheet(isPresented: $showSettings) { SettingsView() }
            .sheet(isPresented: $showLogs) { LogView() }
            .task {
                loadBundledProject()
            }
        }
        .preferredColorScheme(.dark)
    }

    private var ambientBackground: some View {
        VStack {
            RadialGradient(
                colors: [violet.opacity(0.18), .clear],
                center: .topTrailing,
                startRadius: 10,
                endRadius: 330
            )
            .frame(height: 420)
            Spacer()
        }
        .ignoresSafeArea()
        .allowsHitTesting(false)
    }

    private var topBar: some View {
        HStack {
            HStack(spacing: 10) {
                AppLogo(size: 38)
                    .shadow(color: electricBlue.opacity(0.34), radius: 12, y: 4)
                VStack(alignment: .leading, spacing: 1) {
                    Text("Zscript")
                        .font(.headline.weight(.bold))
                    Text(language.text("exploits.control_surface"))
                        .font(.system(size: 9, weight: .bold, design: .rounded))
                        .tracking(1.1)
                        .foregroundStyle(electricBlue)
                }
            }

            Spacer()

            HStack(spacing: 8) {
                Circle()
                    .fill(Color.green)
                    .frame(width: 7, height: 7)
                Text(language.text("exploits.available"))
                    .font(.system(size: 9, weight: .bold, design: .rounded))
                    .tracking(0.8)
            }
            .foregroundStyle(.secondary)
            .padding(.horizontal, 11)
            .frame(height: 30)
            .background(Color.white.opacity(0.06), in: Capsule())
            .overlay { Capsule().stroke(Color.white.opacity(0.09), lineWidth: 1) }

            Text("v\(AppInfo.marketingVersion)")
                .font(.system(size: 10, weight: .bold, design: .monospaced))
                .foregroundStyle(.secondary)

            Button { showSettings = true } label: {
                Image(systemName: "slider.horizontal.3")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(.primary)
                    .frame(width: 34, height: 34)
                    .background(Color.white.opacity(0.07), in: Circle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(language.text("accessibility.open_settings"))
        }
    }

    private var identityHeader: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(language.text("exploits.header").uppercased())
                .font(.system(size: 31, weight: .black, design: .rounded))
                .tracking(-0.8)
            HStack(spacing: 8) {
                Text(language.text("exploits.active_target").uppercased())
                    .font(.system(size: 10, weight: .bold, design: .rounded))
                    .tracking(1.1)
                    .foregroundStyle(.secondary)
                Text("/  FREE FIRE")
                    .font(.system(size: 10, weight: .bold, design: .monospaced))
                    .tracking(0.7)
                    .foregroundStyle(electricBlue)
            }
        }
    }

    private var primaryModule: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 12) {
                    HStack(spacing: 7) {
                        Image(systemName: "waveform.path.ecg")
                            .font(.system(size: 11, weight: .bold))
                        Text(language.text("exploits.primary_module"))
                            .font(.system(size: 10, weight: .bold, design: .rounded))
                            .tracking(1.2)
                    }
                    .foregroundStyle(Color.white.opacity(0.66))

                    Text(language.text(definition.titleKey))
                        .font(.system(size: 30, weight: .black, design: .rounded))
                        .tracking(-0.8)

                    HStack(spacing: 8) {
                        Image(systemName: "scope")
                            .font(.caption.weight(.bold))
                        Text(language.text(definition.targetKey))
                            .font(.caption.monospaced())
                            .lineLimit(1)
                    }
                    .foregroundStyle(Color.white.opacity(0.70))
                }

                Spacer(minLength: 12)

                ZStack {
                    Circle()
                        .fill(electricBlue.opacity(0.14))
                    Circle()
                        .stroke(electricBlue.opacity(0.38), lineWidth: 1)
                    Image(systemName: definition.systemImage)
                        .font(.system(size: 27, weight: .bold))
                        .foregroundStyle(electricBlue)
                }
                .frame(width: 64, height: 64)
            }

            Rectangle()
                .fill(Color.white.opacity(0.10))
                .frame(height: 1)
                .padding(.vertical, 20)

            HStack(spacing: 10) {
                Image(systemName: "rectangle.and.hand.point.up.left.fill")
                    .foregroundStyle(violet)
                VStack(alignment: .leading, spacing: 2) {
                    Text(language.text("exploits.variant_label").uppercased())
                        .font(.system(size: 9, weight: .bold, design: .rounded))
                        .tracking(0.9)
                        .foregroundStyle(.secondary)
                    Text(language.text("exploits.select_variant"))
                        .font(.caption)
                        .foregroundStyle(Color.white.opacity(0.58))
                }
                Spacer(minLength: 10)
                variantMenu
            }
            .padding(.horizontal, 12)
            .frame(minHeight: 58)
            .background(Color.white.opacity(0.055), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(Color.white.opacity(0.08), lineWidth: 1)
            }
            .padding(.bottom, 14)

            HStack(spacing: 10) {
                Button(action: inject) {
                    HStack(spacing: 9) {
                        if isWorking {
                            ProgressView().tint(.black)
                        } else {
                            Image(systemName: "bolt.fill")
                        }
                        Text(language.text("exploits.inject"))
                            .font(.headline.weight(.bold))
                        Spacer()
                        Image(systemName: "arrow.up.right")
                            .font(.caption.weight(.black))
                    }
                    .foregroundStyle(.black)
                    .padding(.horizontal, 16)
                    .frame(maxWidth: .infinity)
                    .frame(height: 54)
                }
                .buttonStyle(.plain)
                .background(
                    LinearGradient(
                        colors: [Color.white, electricBlue.opacity(0.78)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    in: RoundedRectangle(cornerRadius: 17, style: .continuous)
                )
                .shadow(color: electricBlue.opacity(0.25), radius: 16, y: 7)
                .disabled(isWorking || selectedProject == nil)
                .opacity(isWorking || selectedProject == nil ? 0.52 : 1)

                if hasReceipt {
                    Button(action: restore) {
                        Image(systemName: "arrow.uturn.backward")
                            .font(.headline.weight(.bold))
                            .foregroundStyle(.white)
                            .frame(width: 54, height: 54)
                    }
                    .buttonStyle(.plain)
                    .background(Color.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 17, style: .continuous))
                    .overlay {
                        RoundedRectangle(cornerRadius: 17, style: .continuous)
                            .stroke(Color.white.opacity(0.12), lineWidth: 1)
                    }
                    .disabled(isWorking)
                    .accessibilityLabel(language.text("exploits.restore"))
                }
            }
        }
        .padding(18)
        .background(
            LinearGradient(
                colors: [Color(red: 0.13, green: 0.15, blue: 0.22), panel, Color.black.opacity(0.88)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            ),
            in: RoundedRectangle(cornerRadius: 28, style: .continuous)
        )
        .overlay {
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .stroke(
                    LinearGradient(
                        colors: [electricBlue.opacity(0.60), violet.opacity(0.28), Color.white.opacity(0.07)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    lineWidth: 1
                )
        }
        .overlay(alignment: .topTrailing) {
            statusBadge
                .padding(17)
        }
        .shadow(color: violet.opacity(0.14), radius: 28, y: 14)
    }

    private var variantMenu: some View {
        Menu {
            ForEach(variants) { variant in
                Button {
                    withAnimation(.easeOut(duration: 0.2)) {
                        selectedVariantID = variant.id
                        hasReceipt = DevicePatchService.latestReceipt(projectID: variant.id) != nil
                        status = .ready
                    }
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
            HStack(spacing: 8) {
                Text(selectedProject?.name ?? language.text("exploits.no_variant"))
                    .font(.subheadline.weight(.bold))
                Image(systemName: "chevron.down")
                    .font(.system(size: 10, weight: .black))
            }
            .foregroundStyle(.white)
            .padding(.horizontal, 12)
            .frame(height: 36)
            .background(violet.opacity(0.28), in: Capsule())
            .overlay { Capsule().stroke(violet.opacity(0.65), lineWidth: 1) }
        }
        .disabled(variants.isEmpty)
    }

    private var telemetry: some View {
        HStack(spacing: 10) {
            telemetryCell(
                label: language.text("exploits.status_label"),
                value: language.text(status.textKey),
                systemImage: status == .success ? "checkmark" : "bolt.fill",
                tint: status.color
            )
            telemetryCell(
                label: language.text("exploits.target_locked"),
                value: "LOCKED",
                systemImage: "lock.fill",
                tint: electricBlue
            )
        }
    }

    private func telemetryCell(label: String, value: String, systemImage: String, tint: Color) -> some View {
        HStack(spacing: 10) {
            Image(systemName: systemImage)
                .font(.caption.weight(.bold))
                .foregroundStyle(tint)
                .frame(width: 27, height: 27)
                .background(tint.opacity(0.13), in: Circle())
            VStack(alignment: .leading, spacing: 2) {
                Text(label.uppercased())
                    .font(.system(size: 8, weight: .bold, design: .rounded))
                    .tracking(0.7)
                    .foregroundStyle(.secondary)
                Text(value)
                    .font(.caption.weight(.bold))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 12)
        .frame(maxWidth: .infinity, minHeight: 58)
        .background(panel, in: RoundedRectangle(cornerRadius: 17, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 17, style: .continuous)
                .stroke(Color.white.opacity(0.08), lineWidth: 1)
        }
    }

    private var nodePanel: some View {
        VStack(alignment: .leading, spacing: 0) {
            Button {
                withAnimation(.easeInOut(duration: 0.25)) {
                    showInfo.toggle()
                }
            } label: {
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(language.text("exploits.info").uppercased())
                            .font(.system(size: 10, weight: .bold, design: .rounded))
                            .tracking(1.1)
                            .foregroundStyle(electricBlue)
                        Text(language.text("exploits.info_footer"))
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.primary)
                    }
                    Spacer()
                    Image(systemName: showInfo ? "minus" : "plus")
                        .font(.caption.weight(.black))
                        .foregroundStyle(.secondary)
                        .frame(width: 30, height: 30)
                        .background(Color.white.opacity(0.07), in: Circle())
                }
            }
            .buttonStyle(.plain)

            if showInfo {
                VStack(alignment: .leading, spacing: 13) {
                    Rectangle()
                        .fill(Color.white.opacity(0.09))
                        .frame(height: 1)
                        .padding(.vertical, 14)
                    nodeRow(title: language.text("exploits.device_node"), value: AppInfo.displayMachineName, systemImage: "iphone")
                    nodeRow(title: language.text("exploits.runtime"), value: "iOS \(AppInfo.osVersion)", systemImage: "cpu")
                    nodeRow(title: language.text("exploits.secure"), value: language.text("exploits.target_locked"), systemImage: "checkmark.shield.fill", tint: .green)

                    HStack(spacing: 10) {
                        nodeAction(title: language.text("exploits.logs"), systemImage: "terminal.fill") {
                            showLogs = true
                        }
                        nodeAction(title: language.text("exploits.settings"), systemImage: "gearshape.fill") {
                            showSettings = true
                        }
                    }
                    .padding(.top, 5)
                }
            }
        }
        .padding(17)
        .background(panel, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .stroke(Color.white.opacity(0.08), lineWidth: 1)
        }
    }

    private func nodeRow(title: String, value: String, systemImage: String, tint: Color? = nil) -> some View {
        HStack(spacing: 11) {
            Image(systemName: systemImage)
                .font(.caption.weight(.bold))
                .foregroundStyle(tint ?? electricBlue)
                .frame(width: 24)
            Text(title.uppercased())
                .font(.system(size: 9, weight: .bold, design: .rounded))
                .tracking(0.7)
                .foregroundStyle(.secondary)
            Spacer(minLength: 8)
            Text(value)
                .font(.caption.monospaced())
                .foregroundStyle(.primary)
                .lineLimit(1)
        }
    }

    private func nodeAction(title: String, systemImage: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Label(title, systemImage: systemImage)
                .font(.caption.weight(.bold))
                .frame(maxWidth: .infinity)
                .frame(height: 40)
        }
        .buttonStyle(.plain)
        .foregroundStyle(.white)
        .background(Color.white.opacity(0.07), in: RoundedRectangle(cornerRadius: 13, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 13, style: .continuous)
                .stroke(Color.white.opacity(0.10), lineWidth: 1)
        }
    }

    private var statusBadge: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(status.color)
                .frame(width: 6, height: 6)
            Text(language.text(status.textKey))
                .font(.system(size: 10, weight: .bold, design: .monospaced))
                .foregroundStyle(status.color)
        }
        .padding(.horizontal, 10)
        .frame(height: 27)
        .background(status.color.opacity(0.12), in: Capsule())
        .overlay { Capsule().stroke(status.color.opacity(0.26), lineWidth: 1) }
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

