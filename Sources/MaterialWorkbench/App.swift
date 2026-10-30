import SwiftUI
import AVKit
import UniformTypeIdentifiers

@main struct MaterialWorkbenchApp: App {
    @NSApplicationDelegateAdaptor(WorkbenchDelegate.self) private var appDelegate
    @StateObject private var model = WorkbenchModel()
    @AppStorage("appearance.v1") private var appearance = "system"
    init() {
        if CommandLine.arguments.contains("--self-test") {
            do { try SelfTest.run(); exit(0) } catch { print(error.localizedDescription); exit(1) }
        }
    }
    var body: some Scene {
        WindowGroup("素材工作台", id: "main") {
            MainWindowContent(delegate:appDelegate,model:model)
                .frame(minWidth: 1060, minHeight: 680)
                .preferredColorScheme(appearance == "dark" ? .dark : appearance == "light" ? .light : nil)
                .onAppear { NSApp.setActivationPolicy(.regular) }
        }
        .defaultSize(width: 1280, height: 820)
        .commands {
            CommandGroup(replacing: .newItem) {
                Button("添加文件…") { model.chooseFiles() }.keyboardShortcut("o").disabled(model.running)
                Button("开始处理") { model.start() }.keyboardShortcut(.return, modifiers: .command).disabled(model.running || model.items.isEmpty)
            }
            CommandGroup(after: .toolbar) {
                Menu("外观") {
                    Picker("外观", selection: $appearance) { Text("跟随系统").tag("system"); Text("浅色").tag("light"); Text("深色").tag("dark") }
                }
            }
            CommandGroup(replacing: .undoRedo) {
                Button("撤销批量重命名") { model.undo() }.keyboardShortcut("z").disabled(model.undoPlan.isEmpty || model.running)
            }
        }
    }
}

struct MainWindowContent: View {
    let delegate: WorkbenchDelegate
    @ObservedObject var model: WorkbenchModel
    @Environment(\.openWindow) private var openWindow
    var body: some View {
        ContentView().environmentObject(model)
            .background(MainWindowProbe { window in delegate.model = model; delegate.register(window) })
            .onAppear { delegate.openMainWindow = { openWindow(id:"main") } }
    }
}

struct ContentView: View {
    @EnvironmentObject private var m: WorkbenchModel
    @State private var dropTarget = false
    var body: some View {
        VStack(spacing: 0) {
            if let module = m.module {
                if m.items.isEmpty {
                    ImportLanding(module: module)
                } else {
                    if let result = m.batch, result.module == module { ResultBanner(result: result) }
                    workspace(module)
                    ActionBar()
                }
            } else { HomeView() }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(nsColor: .windowBackgroundColor))
        .toolbar {
            ToolbarItem(placement: .navigation) {
                Button { if !m.running { m.module = nil } } label: { Image(systemName: "square.grid.2x2") }.help("所有工具").disabled(m.running)
            }
            ToolbarItem(placement: .principal) {
                VStack(spacing: 2) {
                    Text(m.module?.rawValue ?? "素材工作台").font(.headline)
                    if m.running { Text("正在本地处理，原文件保留").font(.caption).foregroundStyle(.secondary) }
                }
            }
            ToolbarItemGroup(placement: .primaryAction) {
                if m.canReturnToImages { Button("返回图片结果") { m.returnToImages() }.disabled(m.running) }
                if m.running && m.module != .rename { Button("取消", role: .cancel) { m.runner.cancel() } }
                Button { m.chooseFiles() } label: { Label("添加文件", systemImage: "plus") }.disabled(m.running)
            }
        }
        .onOpenURL { m.importURLs([$0]) }
        .onDrop(of: [UTType.fileURL], isTargeted: $dropTarget) { providers in
            for provider in providers {
                _ = provider.loadObject(ofClass: URL.self) { url, _ in
                    if let url { Task { @MainActor in m.importURLs([url]) } }
                }
            }
            return !m.running
        }
        .overlay { if dropTarget && !m.running { Rectangle().stroke(Color.accentColor, lineWidth: 3).padding(3).allowsHitTesting(false) } }
        .alert("操作提示", isPresented: Binding(get: { m.error != nil }, set: { if !$0 { m.error = nil } })) {
            Button("好") { m.error = nil }
        } message: { Text(m.error ?? "") }
    }

    @ViewBuilder private func workspace(_ module: Module) -> some View {
        if module == .rename {
            HSplitView {
                RenameComparison().frame(minWidth: 600, maxWidth: .infinity)
                SettingsPane(module: module).frame(minWidth: 290, idealWidth: 310, maxWidth: 350)
            }
        } else {
            HSplitView {
                FileQueue(module: module).frame(minWidth: module == .image ? 220 : 190, idealWidth: module == .image ? 270 : 230, maxWidth: 300)
                VStack(spacing: 0) {
                    PreviewPane().frame(maxWidth: .infinity, maxHeight: .infinity)
                    if m.batch == nil { OutputNameEditor() }
                }.frame(minWidth: 380, maxWidth: .infinity)
                SettingsPane(module: module).frame(minWidth: 290, idealWidth: 310, maxWidth: 350)
            }
        }
    }
}

struct HomeView: View {
    @EnvironmentObject private var m: WorkbenchModel
    private let columns = [GridItem(.flexible(), spacing: 16), GridItem(.flexible(), spacing: 16)]
    var body: some View {
        VStack(alignment: .leading, spacing: 28) {
            VStack(alignment: .leading, spacing: 8) {
                Text("素材工作台").font(.system(size: 30, weight: .semibold))
                Text("处理好素材，继续下一步。").font(.title3).foregroundStyle(.secondary)
            }
            LazyVGrid(columns: columns, spacing: 16) {
                ForEach(Module.allCases) { module in
                    Button { m.switchModule(module) } label: {
                        HStack(alignment: .top, spacing: 18) {
                            Image(systemName: module.icon).font(.system(size: 26, weight: .regular)).foregroundStyle(module.tint).frame(width: 42, height: 44)
                            VStack(alignment: .leading, spacing: 8) {
                                Text(module.rawValue).font(.title3.weight(.semibold)).foregroundStyle(.primary)
                                Text(module.description).font(.body).foregroundStyle(.secondary).multilineTextAlignment(.leading)
                            }
                            Spacer(minLength: 0)
                            Image(systemName: "arrow.up.right").foregroundStyle(.tertiary)
                        }
                        .padding(24).frame(maxWidth: .infinity, minHeight: 112, alignment: .leading)
                        .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 12))
                        .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(.primary.opacity(0.07)))
                        .contentShape(Rectangle())
                    }.buttonStyle(.plain)
                }
            }
            HStack(spacing: 12) {
                Image(systemName: "square.and.arrow.down").font(.title2)
                Text("拖入文件或文件夹，自动推荐处理工具")
                Spacer()
                Button("选择文件…") { m.chooseFiles() }.keyboardShortcut("o")
            }.foregroundStyle(.secondary).padding(.top, 4)
            Label("所有处理都在本机完成", systemImage: "lock.shield").font(.callout).foregroundStyle(.secondary)
        }.frame(maxWidth: 860).padding(40).frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

struct ImportLanding: View {
    @EnvironmentObject private var m: WorkbenchModel
    let module: Module
    var body: some View {
        VStack(spacing: 22) {
            Image(systemName: module.icon).font(.system(size: 44, weight: .light)).foregroundStyle(module.tint)
            VStack(spacing: 10) {
                Text(module.rawValue).font(.largeTitle.weight(.semibold))
                Text(module.description).font(.title3).foregroundStyle(.secondary)
            }
            VStack(spacing: 16) {
                Image(systemName: "arrow.down.document").font(.system(size: 32, weight: .light)).foregroundStyle(.secondary)
                Text(module == .rename ? "拖入需要整理的文件" : module == .video ? "拖入视频或视频文件夹" : "拖入图片或图片文件夹").font(.headline)
                Button("选择文件…") { m.chooseFiles() }.buttonStyle(.borderedProminent).controlSize(.large)
                Text("支持批量添加 · ⌘O").font(.callout).foregroundStyle(.secondary)
            }.frame(width: 520, height: 230)
                .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 12))
                .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(.secondary.opacity(0.3), style: StrokeStyle(lineWidth: 1, dash: [6, 5])))
            if module == .video { Text("当前预设：每个视频上限 \(OutputNaming.number(m.options.targetMB)) MB").foregroundStyle(.secondary) }
            if module == .image { Text("输出 JPEG · sRGB · 保留原素材").foregroundStyle(.secondary) }
            if module == .pdf { Text("导入后拖动图片即可调整页面顺序").foregroundStyle(.secondary) }
        }.padding(40).frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

extension Module {
    var tint: Color { switch self { case .video: .orange; case .image: .teal; case .pdf: .indigo; case .rename: .brown } }
    var description: String {
        switch self {
        case .video: "压到需要的体积，调整比例与帧率"
        case .image: "批量转换、缩放，轻松分享原片"
        case .pdf: "排好图片顺序，整理成一份 PDF"
        case .rename: "对照新旧名称，批量整理文件"
        }
    }
}
