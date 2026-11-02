import SwiftUI
import AppKit
import Combine

@MainActor
final class AgentBubbleModel: ObservableObject {
    @Published var draft = ""
    @Published var selection: UUID?
    @Published var above = true
    @Published var tailX: CGFloat = 150
    @Published var bodyHeight: CGFloat = 48
}

/// Keep the existing task entry points, but present them as a pet-anchored speech bubble.
@MainActor
final class AgentTaskWindowController: NSObject {
    static let shared = AgentTaskWindowController()
    let model = AgentBubbleModel()
    private var panel: AgentBubblePanel?
    private var observation: AnyCancellable?
    private(set) var isVisible = false

    func open() {
        PetController.shared.show()
        if panel == nil {
            let hosting = NSHostingView(rootView: AgentBubbleView(model: model))
            hosting.sizingOptions = []
            let panel = AgentBubblePanel(contentRect: .zero, styleMask: [.borderless],
                                         backing: .buffered, defer: false)
            panel.contentView = hosting
            panel.isOpaque = false
            panel.backgroundColor = .clear
            panel.hasShadow = true
            panel.level = .floating
            panel.isFloatingPanel = true
            panel.becomesKeyOnlyIfNeeded = false
            panel.hidesOnDeactivate = false
            panel.isReleasedWhenClosed = false
            panel.isExcludedFromWindowsMenu = true
            panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle]
            self.panel = panel
            // Window movement also covers dragging while the animation loop is suspended.
            NotificationCenter.default.addObserver(self, selector: #selector(petWindowMoved(_:)),
                                                   name: NSWindow.didMoveNotification, object: nil)
            NotificationCenter.default.addObserver(self, selector: #selector(petWindowMoved(_:)),
                                                   name: NSWindow.didResizeNotification, object: nil)
            observation = AgentTaskStore.shared.objectWillChange.sink { [weak self] _ in
                DispatchQueue.main.async { self?.followPet() }
            }
        }
        if let active = AgentTaskStore.shared.activeID { model.selection = active }
        isVisible = true
        followPet()
        NSApp.activate(ignoringOtherApps: true)
        panel?.makeKeyAndOrderFront(nil)
        AgentTaskStore.shared.checkRuntime()
    }

    func hide() {
        isVisible = false
        panel?.orderOut(nil)
    }

    @objc private func petWindowMoved(_ notification: Notification) {
        guard notification.object as? NSWindow !== panel else { return }
        followPet()
    }

    func followPet() {
        guard isVisible, let panel, let anchor = PetController.shared.taskBubbleAnchor else { return }
        let store = AgentTaskStore.shared
        let selected = store.jobs.first { $0.id == model.selection }
        let height: CGFloat = (selected == nil ? 176 :
            80 + model.bodyHeight + (selected?.result.isEmpty == false ? 24 : 0)) + (store.error == nil ? 0 : 42)
        let placement = AgentBubbleGeometry.place(near: anchor.frame,
            visible: anchor.screen?.visibleFrame ?? anchor.frame.insetBy(dx: -400, dy: -400), desiredHeight: height)
        if model.above != placement.above { model.above = placement.above }
        if abs(model.tailX - placement.tailX) > 0.5 { model.tailX = placement.tailX }
        if panel.frame != placement.frame { panel.setFrame(placement.frame, display: true) }
    }

    func updateBodyHeight(_ height: CGFloat) {
        let job = AgentTaskStore.shared.jobs.first { $0.id == model.selection }
        let bounded = min(max(32, ceil(height)), job?.status == "approval" ? 210 : 160)
        guard abs(model.bodyHeight - bounded) > 1 else { return }
        model.bodyHeight = bounded
        followPet()
    }

    func select(_ id: UUID?) {
        if model.selection != id { model.bodyHeight = 48 }
        model.selection = id
        followPet()
    }
}

private final class AgentBubblePanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
    override func cancelOperation(_ sender: Any?) { AgentTaskWindowController.shared.hide() }
}

struct AgentBubbleView: View {
    @ObservedObject var model: AgentBubbleModel
    @ObservedObject private var store = AgentTaskStore.shared
    @ObservedObject private var locale = LocalizationManager.shared
    @State private var composing = false
    @State private var showingHistory = false
    @State private var showingDetails = false
    @State private var pendingDelete: AgentJob?
    private var selected: AgentJob? { store.jobs.first { $0.id == model.selection } }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            header
            if let job = selected {
                taskContent(job)
            } else {
                composer
            }
            if let error = store.error {
                HStack(alignment: .top, spacing: 6) {
                    Text(error).font(.caption).foregroundStyle(.red).lineLimit(3).help(error)
                    Spacer(minLength: 0)
                    Button { store.error = nil } label: { Image(systemName: "xmark.circle") }
                        .buttonStyle(.plain).help(ChatText.pick("关闭提示", "Dismiss error"))
                }
            }
        }
        .padding(10)
        .padding(.bottom, model.above ? 12 : 0)
        .padding(.top, model.above ? 0 : 12)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background {
            BubbleOutline(above: model.above, tailX: model.tailX).fill(.regularMaterial)
                .overlay {
                    BubbleOutline(above: model.above, tailX: model.tailX)
                        .fill(Color(nsColor: .windowBackgroundColor).opacity(0.72))
                }
        }
        .overlay(BubbleOutline(above: model.above, tailX: model.tailX).stroke(Color.primary.opacity(0.12), lineWidth: 0.7))
        .confirmationDialog(ChatText.pick("删除这个任务及执行记录？", "Delete this task and its history?"),
                            isPresented: Binding(get: { pendingDelete != nil }, set: { if !$0 { pendingDelete = nil } }), titleVisibility: .visible) {
            Button(ChatText.pick("删除任务", "Delete task"), role: .destructive) {
                if let job = pendingDelete {
                    store.delete(job)
                    if model.selection == job.id { AgentTaskWindowController.shared.select(nil) }
                }
                pendingDelete = nil
            }
        }
        .onChange(of: store.activeID) { _, id in
            if let id { AgentTaskWindowController.shared.select(id) }
        }
    }

    private var header: some View {
        HStack(spacing: 9) {
            Image(systemName: "sparkles").foregroundStyle(Color.accentColor)
            Text(ChatText.pick("交给大肥鱼", "Leave it to DaFeiYu")).font(.callout.weight(.semibold)).foregroundStyle(.primary)
            Spacer()
            if !store.jobs.isEmpty {
                Button { showingHistory.toggle() } label: { Image(systemName: "clock.arrow.circlepath") }
                    .help(ChatText.pick("最近的任务", "Recent tasks"))
                    .popover(isPresented: $showingHistory) {
                        ScrollView {
                            VStack(alignment: .leading, spacing: 4) {
                                ForEach(store.jobs) { job in
                                    Button {
                                        AgentTaskWindowController.shared.select(job.id)
                                        showingHistory = false
                                    } label: {
                                        VStack(alignment: .leading, spacing: 3) {
                                            Text(job.prompt).lineLimit(2)
                                            Text(AgentTaskStore.statusText(job.status)).font(.caption).foregroundStyle(.secondary)
                                        }.frame(maxWidth: .infinity, alignment: .leading).padding(7)
                                    }.buttonStyle(.plain)
                                        .contextMenu {
                                            Button(ChatText.pick("删除任务", "Delete task"), role: .destructive) {
                                                showingHistory = false
                                                pendingDelete = job
                                            }.disabled(store.activeID == job.id)
                                        }
                                }
                            }.padding(8)
                        }.frame(width: 280, height: 220)
                    }
            }
            if selected != nil {
                Button { AgentTaskWindowController.shared.select(nil) } label: { Image(systemName: "plus.bubble") }
                    .help(ChatText.pick("新任务", "New task"))
            }
            Button { AgentTaskWindowController.shared.hide() } label: { Image(systemName: "xmark") }
                .help(ChatText.pick("收起气泡，任务继续", "Hide bubble; task continues"))
        }.buttonStyle(.plain).foregroundStyle(.secondary)
    }

    private var composer: some View {
        VStack(alignment: .leading, spacing: 9) {
            Text(ChatText.pick("想让我帮你做点什么？", "What can I help you with?"))
                .font(.callout).foregroundStyle(.secondary)
            ChatInput(text: $model.draft, onSend: submit, transparentBackground: true, onCompositionChange: { composing = $0 })
                .frame(height: 48)
                .background(Color.primary.opacity(0.045), in: RoundedRectangle(cornerRadius: 9))
                .clipShape(RoundedRectangle(cornerRadius: 9))
                .overlay(alignment: .topLeading) {
                    if model.draft.isEmpty && !composing {
                        Text(ChatText.pick("比如：检查项目，修复一个问题…", "For example: inspect and fix this project…"))
                            .font(.callout).foregroundStyle(.tertiary).padding(.horizontal, 10).padding(.top, 8)
                            .allowsHitTesting(false)
                    }
                }
            HStack {
                Button { store.chooseWorkspace() } label: {
                    Label(store.workspace.isEmpty ? ChatText.pick("选择工作文件夹", "Choose a folder") : URL(fileURLWithPath: store.workspace).lastPathComponent,
                          systemImage: "folder")
                        .lineLimit(1).truncationMode(.middle)
                }.buttonStyle(.plain).font(.caption).foregroundStyle(.secondary)
                    .help(store.workspace.isEmpty ? ChatText.pick("选择工作文件夹", "Choose a folder") : store.workspace)
                Spacer(minLength: 4)
                Button(action: submit) { Image(systemName: "arrow.up.circle.fill").font(.system(size: 25)) }
                    .buttonStyle(.plain).foregroundStyle(Color.accentColor)
                    .help(ChatText.pick("派发任务", "Start task"))
                    .disabled(composing || !store.runtimeReady || store.isBusy || model.draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
            if store.checking || store.installing {
                HStack(spacing: 7) {
                    ProgressView().controlSize(.mini)
                    Text(store.setupStatus ?? ChatText.pick("正在准备工作能力…", "Getting ready…")).font(.caption).foregroundStyle(.secondary)
                    if store.installing {
                        Spacer(minLength: 0)
                        Button(ChatText.pick("取消", "Cancel")) { store.cancelRuntimeInstallation() }.font(.caption).buttonStyle(.plain)
                    }
                }
            } else if !store.runtimeReady {
                Button(ChatText.pick("启用工作能力", "Enable tasks")) { store.installRuntime() }.font(.caption)
                    .help(ChatText.pick("首次联网下载配套后台，之后使用本机缓存，无需安装 Python、Node 或其他应用。", "Download the matching runtime once; reuse it locally without installing Python, Node or another app."))
            } else if store.isBusy {
                Button(ChatText.pick("查看正在进行的任务", "View active task")) {
                    AgentTaskWindowController.shared.select(store.activeID)
                }.font(.caption)
            }
        }
    }

    private func taskContent(_ job: AgentJob) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 7) {
                if job.status == "running" { ProgressView().controlSize(.mini) }
                Text(AgentTaskStore.statusText(job.status)).font(.caption.weight(.medium)).foregroundStyle(.secondary)
                Spacer()
                if store.activeID == job.id {
                    Button(ChatText.pick("停止", "Stop")) { store.stop() }.font(.caption)
                }
            }
            ScrollView {
                VStack(alignment: .leading, spacing: 10) {
                    Text(job.prompt).font(.caption).foregroundStyle(.secondary).lineLimit(2).help(job.prompt)
                    if let plan = job.plan, !plan.isEmpty {
                        VStack(alignment: .leading, spacing: 5) {
                            ForEach(Array(plan.prefix(5).enumerated()), id: \.offset) { _, step in
                                Label(step.content, systemImage: step.status == "completed" ? "checkmark.circle.fill" :
                                      (step.status == "in_progress" ? "circle.dotted" : "circle"))
                                    .font(.caption).lineLimit(2).foregroundStyle(step.status == "in_progress" ? .primary : .secondary)
                            }
                        }
                    }
                    if job.status == "running" {
                        Text(job.activity?.last ?? ChatText.pick("正在整理思路…", "Working on your request…"))
                            .font(.callout).foregroundStyle(.secondary)
                        if let reply = job.reply, !reply.isEmpty { Text(reply).font(.callout).textSelection(.enabled) }
                    }
                    if job.status == "approval", store.activeID == job.id {
                        approvalContent
                    } else if job.status == "approval", !store.isBusy {
                        Text(ChatText.pick("还有一步需要你确认。", "One more step needs your review.")).font(.callout)
                        Button(ChatText.pick("继续", "Continue")) { store.resume(job) }.disabled(!store.runtimeReady)
                    }
                    if !job.result.isEmpty { Text(job.displayResult).font(.callout).textSelection(.enabled) }
                    if job.status == "cancelled" {
                        Text(ChatText.pick("已停下，已完成的改动会保留。", "Stopped. Completed changes are kept.")).font(.callout)
                    }
                    if job.status == "interrupted" {
                        Text(ChatText.pick("上次工作中断了，请检查已有改动后再派新任务。", "The last run was interrupted. Check existing changes before starting again.")).font(.callout)
                    }
                    if !job.logs.isEmpty {
                        DisclosureGroup(ChatText.pick("执行详情", "Details"), isExpanded: $showingDetails) {
                            Text(job.logs.joined(separator: "\n\n")).font(.system(.caption2, design: .monospaced)).textSelection(.enabled)
                        }.font(.caption).foregroundStyle(.secondary)
                    }
                }.frame(maxWidth: .infinity, alignment: .leading).padding(.trailing, 4)
                    .fixedSize(horizontal: false, vertical: true)
                    .background(GeometryReader { geometry in
                        Color.clear
                            .onAppear {
                                DispatchQueue.main.async { AgentTaskWindowController.shared.updateBodyHeight(geometry.size.height) }
                            }
                            .onChange(of: geometry.size.height) { _, height in
                                DispatchQueue.main.async { AgentTaskWindowController.shared.updateBodyHeight(height) }
                            }
                    })
            }
            .frame(height: model.bodyHeight)
            if !job.result.isEmpty {
                HStack {
                    Button(ChatText.pick("复制回复", "Copy reply")) {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(job.displayResult, forType: .string)
                    }
                    Spacer()
                    Button(ChatText.pick("再交给我一件事", "Another task")) { AgentTaskWindowController.shared.select(nil) }
                }.font(.caption).buttonStyle(.plain).foregroundStyle(.secondary)
            }
        }
    }

    private var approvalContent: some View {
        VStack(alignment: .leading, spacing: 9) {
            Text(ChatText.pick("这一步需要你点头", "May I do this step?")).font(.callout.weight(.semibold))
            ForEach(store.approvals) { approval in
                Text(["run_command", "bash", "workflow"].contains(approval.name) ? ChatText.pick("运行命令", "Run command") : (["workspace_write", "write", "edit"].contains(approval.name) ? ChatText.pick("修改文件", "Change file") : ChatText.pick("执行操作：", "Operation: ") + approval.name))
                    .font(.caption.weight(.medium))
                Text(approval.arguments).font(.system(.caption, design: .monospaced)).textSelection(.enabled)
            }
            if store.approvals.contains(where: { ["run_command", "bash", "workflow"].contains($0.name) }) {
                Text(ChatText.pick("命令以你的用户权限在本机执行。", "Commands run locally with your user permissions."))
                    .font(.caption2).foregroundStyle(.secondary)
            }
            HStack {
                Button(ChatText.pick("先别做", "Reject")) { store.decide(approve: false) }
                Button(ChatText.pick("可以，继续", "Allow")) { store.decide(approve: true) }.buttonStyle(.borderedProminent)
            }
        }
    }

    private func submit() {
        guard !composing else { return }
        if store.workspace.isEmpty { store.chooseWorkspace() }
        if store.submit(model.draft) {
            model.draft = ""
            AgentTaskWindowController.shared.select(store.activeID)
        }
    }
}

private struct BubbleOutline: Shape {
    var above: Bool
    var tailX: CGFloat
    func path(in rect: CGRect) -> Path {
        let r: CGFloat = 17
        let body = CGRect(x: rect.minX + 1, y: rect.minY + 1 + (above ? 0 : 12),
                          width: rect.width - 2, height: rect.height - 14)
        let tip = min(max(tailX, body.minX + r + 11), body.maxX - r - 11)
        var path = Path()
        path.move(to: CGPoint(x: body.minX + r, y: body.minY))
        if !above {
            path.addLine(to: CGPoint(x: tip - 10, y: body.minY))
            path.addLine(to: CGPoint(x: tip, y: rect.minY + 1))
            path.addLine(to: CGPoint(x: tip + 10, y: body.minY))
        }
        path.addLine(to: CGPoint(x: body.maxX - r, y: body.minY))
        path.addQuadCurve(to: CGPoint(x: body.maxX, y: body.minY + r), control: CGPoint(x: body.maxX, y: body.minY))
        path.addLine(to: CGPoint(x: body.maxX, y: body.maxY - r))
        path.addQuadCurve(to: CGPoint(x: body.maxX - r, y: body.maxY), control: CGPoint(x: body.maxX, y: body.maxY))
        if above {
            path.addLine(to: CGPoint(x: tip + 10, y: body.maxY))
            path.addLine(to: CGPoint(x: tip, y: rect.maxY - 1))
            path.addLine(to: CGPoint(x: tip - 10, y: body.maxY))
        }
        path.addLine(to: CGPoint(x: body.minX + r, y: body.maxY))
        path.addQuadCurve(to: CGPoint(x: body.minX, y: body.maxY - r), control: CGPoint(x: body.minX, y: body.maxY))
        path.addLine(to: CGPoint(x: body.minX, y: body.minY + r))
        path.addQuadCurve(to: CGPoint(x: body.minX + r, y: body.minY), control: CGPoint(x: body.minX, y: body.minY))
        path.closeSubpath()
        return path
    }
}
