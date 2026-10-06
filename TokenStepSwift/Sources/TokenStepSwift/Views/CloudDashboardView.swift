import SwiftUI

struct CloudDashboardView: View {
    @StateObject private var store = SupabaseCloudStore()
    @State private var selectedDevice = "全部"
    @State private var selectedAgent = "全部"
    @State private var selectedProject = "全部"
    @State private var selectedOS = "全部"
    @State private var selectedDay = "全部"

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            if store.isAuthenticated {
                dashboard
            } else {
                loginCard
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var loginCard: some View {
        VStack(alignment: .leading, spacing: 16) {
            Label(L("连接 Supabase"), systemImage: "cloud.fill")
                .font(.title2.weight(.heavy))
                .foregroundStyle(Color.tokenInk)
            Text(L("这里只保存项目 URL、Publishable Key 和邮箱；密码与登录 Token 仅保留在当前进程内。"))
                .font(.callout)
                .foregroundStyle(.secondary)
            TextField("https://xxxxx.supabase.co", text: $store.projectURL)
                .textFieldStyle(.roundedBorder)
            SecureField(L("Publishable Key"), text: $store.publishableKey)
                .textFieldStyle(.roundedBorder)
            TextField(L("邮箱"), text: $store.email)
                .textFieldStyle(.roundedBorder)
            SecureField(L("密码"), text: $store.password)
                .textFieldStyle(.roundedBorder)
            if let error = store.errorMessage {
                Text(error).font(.caption.weight(.semibold)).foregroundStyle(.red)
            }
            Button(store.isLoading ? L("连接中…") : L("登录并读取云端数据")) { store.signIn() }
                .buttonStyle(.borderedProminent)
                .tint(Color.tokenGreen)
                .disabled(store.isLoading || store.projectURL.isEmpty || store.publishableKey.isEmpty || store.email.isEmpty || store.password.isEmpty)
        }
        .padding(22)
        .background(Color.tokenSurface, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 22, style: .continuous).stroke(Color.black.opacity(0.06)))
    }

    private var dashboard: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack {
                Label(L("Supabase 已连接"), systemImage: "checkmark.icloud.fill")
                    .font(.headline.weight(.bold)).foregroundStyle(Color.tokenGreenDark)
                Spacer()
                Button(L("刷新")) { store.refresh() }.disabled(store.isLoading)
                Button(L("退出")) { store.signOut() }
            }
            filters
            HStack(spacing: 14) {
                metric(L("Token 合计"), TokenStepFormat.tokens(filteredRows.reduce(0) { $0 + $1.totalTokens }, compact: true))
                metric(L("机器"), "\(Set(filteredRows.map(\.deviceID)).count)")
                metric(L("Agent"), "\(Set(filteredRows.map(\.agentKey)).count)")
                metric(L("项目"), "\(Set(filteredRows.map(\.projectKey)).count)")
            }
            cloudRows
            if let error = store.errorMessage {
                Text(error).font(.caption.weight(.semibold)).foregroundStyle(.red)
            }
        }
    }

    private var filters: some View {
        HStack(spacing: 12) {
            filterPicker(L("机器"), selection: $selectedDevice, values: Set(store.rows.map(\.deviceName)))
            filterPicker("Agent", selection: $selectedAgent, values: Set(store.rows.map(\.agentName)))
            filterPicker(L("项目"), selection: $selectedProject, values: Set(store.rows.map(\.projectName)))
            filterPicker(L("系统"), selection: $selectedOS, values: Set(store.rows.map(\.osFamily)))
            filterPicker(L("日期"), selection: $selectedDay, values: Set(store.rows.map(\.localDate)))
            Spacer()
        }
    }

    private func filterPicker(_ title: String, selection: Binding<String>, values: Set<String>) -> some View {
        Picker(title, selection: selection) {
            Text(L("全部")).tag("全部")
            ForEach(values.sorted(), id: \.self) { Text($0).tag($0) }
        }
        .frame(maxWidth: 250)
    }

    private func metric(_ title: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(title).font(.caption.weight(.bold)).foregroundStyle(.secondary)
            Text(value).font(.title2.weight(.heavy)).foregroundStyle(Color.tokenInk)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(Color.tokenSurface, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private var cloudRows: some View {
        LazyVStack(spacing: 8) {
            ForEach(filteredRows) { row in
                HStack(spacing: 12) {
                    Image(systemName: row.osFamily == "windows" ? "desktopcomputer" : "laptopcomputer")
                        .foregroundStyle(Color.tokenGreen)
                    VStack(alignment: .leading, spacing: 3) {
                        Text("\(row.deviceName) · \(row.agentName)").font(.callout.weight(.bold))
                        Text("\(row.localDate) · \(row.osFamily) \(row.osVersion) · \(row.projectName) · \(row.model)")
                            .font(.caption).foregroundStyle(.secondary).lineLimit(1)
                    }
                    Spacer()
                    Text(TokenStepFormat.tokens(row.totalTokens, compact: true))
                        .font(.headline.monospacedDigit().weight(.heavy))
                }
                .padding(13)
                .background(Color.tokenSurface.opacity(0.8), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            }
        }
    }

    private var filteredRows: [CloudUsageRow] {
        store.rows.filter { row in
            (selectedDevice == "全部" || row.deviceName == selectedDevice)
                && (selectedAgent == "全部" || row.agentName == selectedAgent)
                && (selectedProject == "全部" || row.projectName == selectedProject)
                && (selectedOS == "全部" || row.osFamily == selectedOS)
                && (selectedDay == "全部" || row.localDate == selectedDay)
        }
    }
}
