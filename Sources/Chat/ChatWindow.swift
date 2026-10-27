import SwiftUI
import AppKit

@MainActor
final class ChatWindowController: NSObject, NSWindowDelegate {
    static let shared = ChatWindowController()
    private var window: NSWindow?
    func open() {
        if let window {
            window.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }
        let controller = NSHostingController(rootView: ChatView().environmentObject(LocalizationManager.shared))
        let win = NSWindow(contentViewController: controller)
        win.title = ChatText.title
        win.styleMask = [.titled, .closable, .miniaturizable, .resizable]
        win.setContentSize(NSSize(width: 480, height: 620))
        win.minSize = NSSize(width: 400, height: 480)
        win.center()
        win.isReleasedWhenClosed = false
        win.delegate = self
        window = win
        win.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
    func windowWillClose(_ notification: Notification) {
        ChatStore.shared.stop()
        window = nil
    }
}

struct ChatView: View {
    @EnvironmentObject private var locale: LocalizationManager
    @ObservedObject private var chat = ChatStore.shared
    @State private var draft = ""
    @State private var configuring = false
    @State private var deleting = false
    @State private var showingHistory = false
    @State private var drafts: [UUID: String] = [:]

    private var conversationTitle: String {
        let title = chat.conversations.first(where: { $0.id == chat.activeID })?.title ?? ""
        return title.isEmpty ? ChatText.pick("新会话", "New conversation") : title
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                if let image = BundledImage.menuBarIcon {
                    Image(nsImage: image).resizable().scaledToFit().frame(width: 38, height: 38)
                }
                VStack(alignment: .leading) {
                    Text(ChatText.title).font(.headline)
                    Text(chat.model.isEmpty ? ChatText.pick("先设置模型连接", "Set up a model to begin") : chat.model)
                        .font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                Button { configuring = true } label: { Image(systemName: "gearshape") }
                    .help(ChatText.pick("连接设置", "Connection settings"))
                    .disabled(chat.isSending)
                Button { chat.newConversation() } label: { Image(systemName: "plus.bubble") }
                    .help(ChatText.pick("新建会话", "New conversation"))
                    .disabled(chat.isSending)
                Button { showingHistory = true } label: { Image(systemName: "clock.arrow.circlepath") }
                    .help(ChatText.pick("历史会话", "Conversations"))
                    .disabled(chat.isSending)
                Button { deleting = true } label: { Image(systemName: "trash") }
                    .help(ChatText.pick("删除当前会话", "Delete current conversation"))
                    .disabled(chat.isSending || chat.messages.isEmpty)
            }.padding()
            HStack {
                Text(conversationTitle)
                    .lineLimit(1)
                Spacer()
                Text(ChatText.pick("\(chat.messages.count) 条消息", "\(chat.messages.count) messages"))
            }.font(.caption).foregroundStyle(.secondary).padding(.horizontal).padding(.bottom, 8)
            Divider()
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 14) {
                        if chat.messages.isEmpty {
                            VStack(alignment: .leading, spacing: 12) {
                                Text(ChatText.pick("我在这里，今天想聊点什么？", "I'm here. What's on your mind?"))
                                    .font(.title3)
                                Text(ChatText.pick("在连接设置中填写完整聊天接口地址、模型名称和 API Key。兼容 Chat Completions 流式接口，也可连接本机服务。", "Enter your full chat endpoint, model and API key in Connection settings. Supports streaming Chat Completions and local services."))
                                    .foregroundStyle(.secondary)
                                Button(ChatText.pick("连接设置", "Connection settings")) { configuring = true }
                            }.padding(20)
                        }
                        ForEach(chat.messages) { message in
                            VStack(alignment: .leading, spacing: 5) {
                                Text(message.role == "user" ? ChatText.pick("你", "You") : locale[.appName])
                                    .font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                                if message.content.isEmpty {
                                    HStack { ProgressView().controlSize(.small); Text(ChatText.pick("正在想…", "Thinking…")) }
                                } else {
                                    Text(message.content).textSelection(.enabled)
                                }
                            }
                            .padding(12)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(message.role == "user" ? Color.accentColor.opacity(0.10) : Color.secondary.opacity(0.07))
                            .clipShape(RoundedRectangle(cornerRadius: 12))
                            .id(message.id)
                        }
                        Color.clear.frame(height: 1).id("bottom")
                    }.padding()
                }
                .onChange(of: chat.messages.last?.content) { _, _ in proxy.scrollTo("bottom", anchor: .bottom) }
                .onChange(of: chat.messages.count) { _, _ in proxy.scrollTo("bottom", anchor: .bottom) }
                .onChange(of: chat.activeID) { _, _ in proxy.scrollTo("bottom", anchor: .bottom) }
            }
            if chat.isCompacting {
                HStack {
                    ProgressView().controlSize(.small)
                    Text(ChatText.pick("正在整理较早对话的记忆…", "Summarizing older conversation…"))
                    Spacer()
                }.font(.caption).padding(.horizontal).padding(.bottom, 8)
            }
            if let notice = chat.contextNotice {
                Text(notice).font(.caption).foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading).padding(.horizontal).padding(.bottom, 6)
            }
            if let error = chat.error {
                HStack(alignment: .top) {
                    Image(systemName: "exclamationmark.circle")
                    Text(error).textSelection(.enabled)
                    Spacer()
                    Button { chat.error = nil } label: { Image(systemName: "xmark") }.buttonStyle(.plain)
                }.font(.caption).foregroundStyle(.red).padding(.horizontal).padding(.bottom, 8)
            }
            Divider()
            VStack(alignment: .leading, spacing: 8) {
                HStack(alignment: .bottom) {
                    ChatInput(text: $draft, onSend: send)
                        .frame(height: 60)
                        .overlay(alignment: .topLeading) {
                            if draft.isEmpty {
                                Text(ChatText.pick("和我说句话…", "Say something…"))
                                    .foregroundStyle(.tertiary).padding(.leading, 11).padding(.top, 7)
                                    .allowsHitTesting(false)
                            }
                        }
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                    if chat.isSending {
                        Button(ChatText.pick("停止", "Stop")) { chat.stop() }
                    } else {
                        Button(ChatText.pick("发送", "Send")) { send() }
                            .buttonStyle(.borderedProminent)
                            .disabled(draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    }
                }
                contextDetails
                Text(ChatText.pick("回车发送，Shift＋回车换行 · 长对话按需生成摘要，会额外调用当前模型；完整原文保存在本机。", "Return to send, Shift+Return for a new line · Long chats trigger an extra summary request to your model. Full history stays on this Mac."))
                    .font(.caption2).foregroundStyle(.secondary)
            }.padding()
        }
        .background(Color(nsColor: .windowBackgroundColor))
        .sheet(isPresented: $configuring) { ChatConnectionView() }
        .sheet(isPresented: $showingHistory) { ChatHistoryView() }
        .confirmationDialog(ChatText.pick("永久删除当前会话？无法恢复。", "Permanently delete this conversation? This cannot be undone."), isPresented: $deleting, titleVisibility: .visible) {
            Button(ChatText.pick("删除会话", "Delete conversation"), role: .destructive) { chat.deleteConversation(chat.activeID) }
        }
        .onChange(of: chat.activeID) { oldID, newID in
            drafts[oldID] = draft
            draft = drafts[newID] ?? ""
        }
    }
    private var contextDetails: some View {
        DisclosureGroup(ChatText.pick("上下文与用量", "Context and usage")) {
            VStack(alignment: .leading, spacing: 4) {
                Text(ChatText.pick("约 4,000 估算 tokens 触发压缩；较早内容变为摘要，保留最近原文。估算不等于服务商精确计数。", "Compaction triggers around 4,000 estimated tokens. Older turns become a summary; recent text stays verbatim. Estimates differ from provider counts."))
                if chat.lastEstimatedInputTokens > 0 {
                    Text(ChatText.pick("本次聊天输入估算：约 \(chat.lastEstimatedInputTokens) tokens", "Estimated chat input: ~\(chat.lastEstimatedInputTokens) tokens"))
                }
                if let usage = chat.lastUsage {
                    usageLine(usage, label: ChatText.pick("聊天实际用量", "Reported chat usage"))
                } else {
                    Text(ChatText.pick("聊天实际用量：服务商未返回或尚未完成。", "Reported chat usage: unavailable or not completed."))
                }
                if let usage = chat.lastSummaryUsage {
                    usageLine(usage, label: ChatText.pick("额外摘要用量", "Additional summary usage"))
                }
                if let summary = chat.conversations.first(where: { $0.id == chat.activeID })?.summary {
                    Text(ChatText.pick("此会话已保存摘要（\(summary.text.count) 字符）。", "This conversation has a saved summary (\(summary.text.count) characters)."))
                }
            }.frame(maxWidth: .infinity, alignment: .leading).textSelection(.enabled)
        }.font(.caption).foregroundStyle(.secondary)
    }
    private func usageLine(_ usage: ChatUsage, label: String) -> some View {
        let input = usage.prompt_tokens.map(String.init) ?? "—"
        let output = usage.completion_tokens.map(String.init) ?? "—"
        let cache = usage.prompt_cache_hit_tokens.map(String.init) ?? "—"
        return Text(ChatText.pick("\(label)：输入 \(input) / 输出 \(output) / 缓存命中 \(cache) tokens", "\(label): input \(input) / output \(output) / cache hit \(cache) tokens"))
    }
    private func send() {
        chat.send(draft)
        if chat.isSending { draft = "" }
    }
}

struct ChatConnectionView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var locale: LocalizationManager
    @State private var endpoint = ChatStore.shared.endpoint
    @State private var model = ChatStore.shared.model
    @State private var key = ""
    @State private var error: String?
    @State private var credentialLoaded = false
    @State private var requestUsage = ChatStore.shared.requestUsage
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(ChatText.pick("模型连接", "Model connection")).font(.title2.bold())
            Text(ChatText.pick("发送后，角色设定、会话摘要和近期原文会交给此服务。长对话会额外请求模型生成摘要，可能产生 API 费用。桌宠其他功能离线运行。", "Sending shares the character prompt, saved summary and recent turns with this endpoint. Long chats make an additional summarization request, which may incur API fees. Other pet features work offline."))
                .font(.callout).foregroundStyle(.secondary)
            TextField(ChatText.pick("完整聊天接口地址", "Full chat endpoint URL"), text: $endpoint)
                .onChange(of: endpoint) { _, _ in loadKey() }
            Text("https://api.deepseek.com/chat/completions\nhttp://localhost:11434/v1/chat/completions")
                .font(.caption).foregroundStyle(.secondary).textSelection(.enabled)
            TextField(ChatText.pick("模型名称（按服务商提供的填写）", "Model ID supplied by your provider"), text: $model)
            SecureField("API Key", text: $key)
            Text(ChatText.pick("密钥保存在 macOS 钥匙串，按接口地址分别保存。本机免密服务可留空；清空后保存可删除对应密钥。", "Keys are stored in macOS Keychain separately for each endpoint. Leave blank for local services without authentication; saving an empty key deletes that endpoint's key."))
                .font(.caption).foregroundStyle(.secondary)
            Toggle(ChatText.pick("请求服务商返回 token 用量", "Request token usage from provider"), isOn: $requestUsage)
                .font(.callout)
            Text(ChatText.pick("如服务商不支持 stream_options 并返回 400，可关闭此选项。未返回用量时仅显示估算，不代表实际账单。", "Disable this if your provider rejects stream_options with HTTP 400. Estimates are not billing figures."))
                .font(.caption).foregroundStyle(.secondary)
            if let error { Text(error).foregroundStyle(.red).font(.caption).textSelection(.enabled) }
            HStack {
                Spacer()
                Button(ChatText.pick("取消", "Cancel")) { dismiss() }.keyboardShortcut(.cancelAction)
                Button(ChatText.pick("保存", "Save")) {
                    do {
                        try ChatStore.shared.configure(endpoint: endpoint, model: model, key: key)
                        ChatStore.shared.requestUsage = requestUsage
                        dismiss()
                    } catch { self.error = error.localizedDescription }
                }.buttonStyle(.borderedProminent).disabled(!credentialLoaded)
            }
        }
        .textFieldStyle(.roundedBorder)
        .padding(24).frame(width: 460)
        .onAppear { loadKey() }
    }
    private func loadKey() {
        do {
            let normalized = endpoint.trimmingCharacters(in: .whitespacesAndNewlines)
            key = try ChatKeychain.read(endpoint: normalized)
            credentialLoaded = true
            error = nil
        } catch {
            credentialLoaded = false
            self.error = error.localizedDescription
        }
    }
}


struct ChatHistoryView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var locale: LocalizationManager
    @ObservedObject private var chat = ChatStore.shared
    @State private var pendingDelete: ChatConversation?
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(ChatText.pick("历史会话", "Conversations")).font(.title2.bold())
                Spacer()
                Button(ChatText.pick("完成", "Done")) { dismiss() }
            }
            Text(ChatText.pick("各会话独立记忆。新建会话不会携带其他会话的聊天内容。", "Each conversation has its own context. New conversations do not include other chats."))
                .font(.caption).foregroundStyle(.secondary)
            List {
                ForEach(chat.conversations.sorted(by: { $0.updatedAt > $1.updatedAt })) { conversation in
                    HStack {
                        Button {
                            chat.selectConversation(conversation.id)
                            dismiss()
                        } label: {
                            HStack {
                                Image(systemName: conversation.id == chat.activeID ? "checkmark.bubble" : "bubble.left")
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(conversation.title.isEmpty ? ChatText.pick("新会话", "New conversation") : conversation.title)
                                        .lineLimit(1)
                                    Text(conversation.updatedAt, style: .date)
                                        .font(.caption).foregroundStyle(.secondary)
                                }
                                Spacer()
                                Text("\(conversation.messages.count)").foregroundStyle(.secondary)
                            }.contentShape(Rectangle())
                        }.buttonStyle(.plain)
                        Button { pendingDelete = conversation } label: { Image(systemName: "trash") }
                            .buttonStyle(.borderless)
                            .help(ChatText.pick("删除会话", "Delete conversation"))
                    }.padding(.vertical, 5)
                }
            }.listStyle(.inset)
            Button(ChatText.pick("新建会话", "New conversation")) {
                chat.newConversation()
                dismiss()
            }.buttonStyle(.borderedProminent)
        }
        .padding(20).frame(width: 440, height: 440)
        .disabled(chat.isSending)
        .confirmationDialog(ChatText.pick("永久删除此会话？无法恢复。", "Permanently delete this conversation? This cannot be undone."), isPresented: Binding(
            get: { pendingDelete != nil }, set: { if !$0 { pendingDelete = nil } }
        ), titleVisibility: .visible) {
            Button(ChatText.pick("删除会话", "Delete conversation"), role: .destructive) {
                if let conversation = pendingDelete { chat.deleteConversation(conversation.id) }
                pendingDelete = nil
            }
        }
    }
}
