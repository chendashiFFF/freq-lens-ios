import SwiftUI

struct ConnectionView: View {
    @Environment(LensStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var address = ""
    @State private var username = ""
    @State private var password = ""
    @FocusState private var focus: Field?
    private enum Field { case name, address, username, password }
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    if !store.profiles.isEmpty {
                        LensCard {
                            VStack(spacing: 15) {
                                SectionHeading(title: "已保存的服务器")
                                ForEach(store.profiles) { profile in
                                    HStack {
                                        Button {
                                            Task { await store.select(profile); dismiss() }
                                        } label: {
                                            HStack(spacing: 10) {
                                                Image(systemName: "server.rack").foregroundStyle(LensTheme.tint)
                                                VStack(alignment: .leading, spacing: 4) {
                                                    Text(profile.name).font(.subheadline.weight(.medium))
                                                    Text(profile.address.host() ?? "").font(.caption).foregroundStyle(LensTheme.muted)
                                                }
                                                Spacer()
                                                if store.activeID == profile.id { Image(systemName: "checkmark.circle.fill").foregroundStyle(LensTheme.tint) }
                                            }
                                        }.buttonStyle(.plain)
                                        Button {
                                            name = profile.name; address = profile.address.absoluteString; username = profile.username
                                            password = ""; focus = .password
                                        } label: { Image(systemName: "key").font(.system(size: 13)).padding(8) }
                                            .accessibilityLabel("重新连接 \(profile.name)")
                                    }
                                }
                            }
                        }
                    }
                    LensCard {
                        VStack(alignment: .leading, spacing: 20) {
                            SectionHeading(title: "服务器连接")
                            input("名称（可选）") {
                                TextField("我的 Freqtrade", text: $name).focused($focus, equals: .name).accessibilityIdentifier("serverName")
                            }
                            input("API 地址") {
                                TextField("https://your-server:8080", text: $address)
                                    .keyboardType(.URL).textContentType(.URL).textInputAutocapitalization(.never)
                                    .focused($focus, equals: .address).accessibilityIdentifier("serverAddress")
                            }
                            input("用户名") {
                                TextField("API 用户名", text: $username).textContentType(.username)
                                    .textInputAutocapitalization(.never).focused($focus, equals: .username).accessibilityIdentifier("serverUsername")
                            }
                            input("密码") {
                                SecureField("API 密码", text: $password).textContentType(.password)
                                    .focused($focus, equals: .password).accessibilityIdentifier("serverPassword")
                            }
                            if let error = store.connectionError {
                                Label(error, systemImage: "exclamationmark.circle").font(.caption).foregroundStyle(LensTheme.loss)
                                    .accessibilityIdentifier("connectionError")
                            }
                            Button {
                                focus = nil
                                Task {
                                    if await store.connect(name: name, address: address, username: username, password: password) {
                                        password = ""
                                        dismiss()
                                    }
                                }
                            } label: {
                                HStack(spacing: 8) {
                                    if store.isConnecting { ProgressView().tint(.white) }
                                    Text(store.isConnecting ? "连接并读取数据…" : "连接服务器")
                                    if !store.isConnecting { Image(systemName: "arrow.right") }
                                }.font(.system(size: 15, weight: .semibold)).frame(maxWidth: .infinity).padding(.vertical, 9)
                            }.buttonStyle(.glassProminent).tint(LensTheme.tint)
                                .disabled(address.isEmpty || username.isEmpty || password.isEmpty || store.isConnecting)
                                .accessibilityIdentifier("connectButton")
                        }
                    }
                    HStack(alignment: .top, spacing: 9) {
                        Image(systemName: "lock.shield").foregroundStyle(LensTheme.tint)
                        VStack(alignment: .leading, spacing: 5) {
                            Text("数据连接").font(.system(size: 12, weight: .medium))
                            Text("登录凭证保存在设备钥匙串。历史记录删除需再次确认，不提供开仓或平仓操作。")
                                .font(.system(size: 11)).foregroundStyle(LensTheme.muted).lineSpacing(3)
                        }
                    }.padding(.horizontal, 4)
                    Button {
                        Task { await store.select(nil); dismiss() }
                    } label: {
                        Label("浏览演示数据", systemImage: "sparkles").font(.subheadline).frame(maxWidth: .infinity)
                    }.padding(.vertical, 8)
                }.padding(24)
            }.background(LensTheme.background).scrollDismissesKeyboard(.interactively)
                .navigationTitle("数据连接").navigationBarTitleDisplayMode(.inline)
                .toolbar { ToolbarItem(placement: .topBarTrailing) { Button("完成", systemImage: "xmark") { dismiss() }.labelStyle(.iconOnly).disabled(store.isConnecting) } }
                .interactiveDismissDisabled(store.isConnecting)
                .autocorrectionDisabled()
        }
    }
    private func input<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title).font(.system(size: 11, weight: .medium)).foregroundStyle(LensTheme.muted)
            content().font(.system(size: 15)).padding(13).background(LensTheme.background, in: RoundedRectangle(cornerRadius: 12))
        }
    }
}
