import SwiftUI
import UniformTypeIdentifiers

struct FileQueue: View {
    @EnvironmentObject private var m: WorkbenchModel
    let module: Module
    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text(module == .pdf ? "页面顺序" : "素材").font(.headline)
                Text("\(m.items.count)").foregroundStyle(.secondary)
                Spacer()
                Button { m.items = []; m.selection = nil; m.batch = nil } label: { Image(systemName: "trash") }.buttonStyle(.plain).help("清空当前列表").disabled(m.running)
            }.padding(16)
            if module == .image { imageGrid } else { orderedList }
            if module == .pdf { Text("拖动排序 · 右键移除页面").font(.callout).foregroundStyle(.secondary).padding(12) }
        }.background(Color(nsColor: .underPageBackgroundColor).opacity(0.25))
    }
    private var imageGrid: some View {
        ScrollView {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 92), spacing: 10)], spacing: 14) {
                ForEach(m.items) { item in
                    Button { m.selection = item.id } label: {
                        VStack(spacing: 7) {
                            Thumbnail(item: item).frame(height: 82).frame(maxWidth: .infinity)
                            Text(item.url.lastPathComponent).font(.caption).lineLimit(2).foregroundStyle(.primary)
                            if item.status != "等待处理" { Text(item.status).font(.caption).foregroundStyle(item.status == "失败" ? .red : .secondary) }
                        }.padding(8)
                            .background(m.selection == item.id ? Color.accentColor.opacity(0.12) : .clear, in: RoundedRectangle(cornerRadius: 8))
                            .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(m.selection == item.id ? Color.accentColor : .clear, lineWidth: 2))
                    }.buttonStyle(.plain).contextMenu { itemMenu(item) }
                }
            }.padding(12)
        }
    }
    private var orderedList: some View {
        List(selection: $m.selection) {
            ForEach(Array(m.items.enumerated()), id: \.element.id) { index, item in
                HStack(spacing: 10) {
                    if module == .pdf { Text("\(index + 1)").monospacedDigit().foregroundStyle(.secondary).frame(width: 22) }
                    Thumbnail(item: item).frame(width: module == .pdf ? 50 : 44, height: module == .pdf ? 68 : 44)
                    VStack(alignment: .leading, spacing: 5) {
                        Text(item.url.lastPathComponent).lineLimit(2).font(.body)
                        Text(item.status == "等待处理" ? sizeText(bytes(item.url)) : item.status).font(.callout).foregroundStyle(item.status == "失败" ? .red : .secondary)
                        if item.status == "正在处理" || item.status == "正在合并" { ProgressView(value: item.progress).controlSize(.small) }
                    }
                }.padding(.vertical, 7).tag(item.id)
                    .onDrag { NSItemProvider(object: item.id.uuidString as NSString) }
                    .onDrop(of: [UTType.text], isTargeted: nil) { providers in
                        guard module == .pdf, !m.running, let provider = providers.first else { return false }
                        _ = provider.loadObject(ofClass: NSString.self) { value, _ in
                            if let text = value as? String, let id = UUID(uuidString: text) { Task { @MainActor in m.move(id, to: item.id) } }
                        }
                        return true
                    }
                    .contextMenu { itemMenu(item) }
            }
            .onMove { from, to in if !m.running { m.items.move(fromOffsets: from, toOffset: to) } }
        }.listStyle(.sidebar)
    }
    @ViewBuilder private func itemMenu(_ item: Item) -> some View {
        Button("移除") { m.items.removeAll { $0.id == item.id }; if m.selection == item.id { m.selection = m.items.first?.id } }.disabled(m.running)
        Button("在 Finder 中显示") { NSWorkspace.shared.activateFileViewerSelecting([item.output ?? item.url]) }
    }
}

struct Thumbnail: View {
    let item: Item
    var body: some View {
        Group {
            if let image = item.thumbnail { Image(nsImage: image).resizable().scaledToFit() }
            else { Image(systemName: "doc").font(.title2).foregroundStyle(.secondary).frame(maxWidth: .infinity, maxHeight: .infinity) }
        }
    }
}

struct OutputNameEditor: View {
    @EnvironmentObject private var m: WorkbenchModel
    var body: some View {
        if let item = m.selected {
            let automatic = m.module == .pdf ? OutputNaming.pdf(m.items.map(\.url)) : m.module == .video ? OutputNaming.video(item.url, options: m.options, info: item.videoInfo) : OutputNaming.image(item.url, options: m.options)
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("输出名称").font(.callout.weight(.medium))
                    if m.module != .pdf && m.items.count > 1 { Text("当前文件").font(.caption).foregroundStyle(.secondary) }
                    Spacer()
                    if !(m.module == .pdf ? m.pdfName : item.customName).isEmpty {
                        Button("恢复自动命名") { if m.module == .pdf { m.pdfName = "" } else { m.setCustomName("", id: item.id) } }.font(.caption)
                    }
                }
                HStack {
                    TextField(automatic, text: Binding(get: { m.module == .pdf ? m.pdfName : m.items.first(where: { $0.id == item.id })?.customName ?? "" }, set: { if m.module == .pdf { m.pdfName = $0 } else { m.setCustomName($0, id: item.id) } }))
                        .textFieldStyle(.roundedBorder).accessibilityIdentifier("outputName")
                    Text("." + m.outputExtension(item)).foregroundStyle(.secondary)
                }
                Text("预计：" + m.previewFilename(item)).font(.caption).foregroundStyle(.secondary).lineLimit(2).textSelection(.enabled)
            }.padding(.horizontal, 22).padding(.vertical, 14).background(.bar).disabled(m.running)
        }
    }
}

struct ActionBar: View {
    @EnvironmentObject private var m: WorkbenchModel
    var body: some View {
        VStack(spacing: 0) {
            Divider()
            HStack(spacing: 16) {
                if m.running {
                    ProgressView(value: m.items.map(\.progress).reduce(0,+) / Double(max(1,m.items.count))).frame(width: 130)
                    Text("正在处理 \(m.items.filter { $0.status == "已完成" }.count) / \(m.items.count)").font(.callout).monospacedDigit()
                } else if m.module != .rename {
                    Button { _ = m.chooseOutput() } label: { Label(m.outputDirectory?.lastPathComponent ?? "选择输出文件夹", systemImage: "folder") }.help(m.outputDirectory?.path ?? "原文件保持不变")
                } else {
                    Label("直接修改文件名，可撤销最近一次", systemImage: "arrow.uturn.backward").font(.callout).foregroundStyle(.secondary)
                }
                Spacer()
                if m.module == .rename { Button("撤销上一次") { m.undo() }.disabled(m.undoPlan.isEmpty || m.running) }
                Button(m.running ? (m.module == .rename ? "正在重命名…" : "取消处理") : m.module == .rename ? "执行重命名" : m.module == .pdf ? "导出 PDF" : m.batch == nil ? "开始处理" : "再次处理") {
                    if m.running { m.runner.cancel() } else { m.start() }
                }.buttonStyle(.borderedProminent).controlSize(.large)
                    .disabled(m.items.isEmpty || (m.module == .rename && (m.renameProblem != nil || m.running)))
            }.padding(.horizontal, 20).padding(.vertical, 14)
        }.background(.bar)
    }
}

struct ResultBanner: View {
    @EnvironmentObject private var m: WorkbenchModel
    let result: BatchResult
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .center, spacing: 14) {
                Image(systemName: result.failures > 0 ? "exclamationmark.circle.fill" : "checkmark.circle.fill").font(.title2).foregroundStyle(result.failures > 0 ? .orange : .green)
                VStack(alignment: .leading, spacing: 4) {
                    Text(result.module == .rename ? (result.items.contains { $0.status == "已撤销" } ? "已撤销 \(result.items.filter { $0.status == "已撤销" }.count) 个文件的重命名" : "已重命名 \(result.items.filter { $0.status == "已重命名" }.count) 个文件") : "已完成 \(result.module == .pdf ? "PDF 合并" : "\(result.successful.count) 个文件")").font(.headline)
                    HStack(spacing: 10) {
                        if result.failures > 0 { Text("\(result.failures) 个失败").foregroundStyle(.red) }
                        if result.cancelled > 0 { Text("\(result.cancelled) 个未完成") }
                        if let first = result.successful.first?.output {
                            Text(result.module == .pdf ? "\(result.items.count) 页 · \(sizeText(bytes(first)))" : result.directory?.lastPathComponent ?? "").lineLimit(1).help(result.directory?.path ?? "")
                        }
                    }.font(.callout).foregroundStyle(.secondary)
                }
                Spacer(minLength: 12)
                if result.module != .rename { Button("调整设置") { m.batch = nil } }
                if result.module == .image && !result.successful.isEmpty {
                    Button { m.imagesToPDF() } label: { Label("合并为 PDF", systemImage: "doc.richtext") }.buttonStyle(.borderedProminent).controlSize(.large)
                }
                if result.module == .pdf, let url = result.successful.first?.output { Button("打开 PDF") { NSWorkspace.shared.open(url) } }
                if let url = result.successful.first?.output { Button("在 Finder 中显示") { NSWorkspace.shared.activateFileViewerSelecting([url]) } }
                if result.module == .rename { Button("撤销重命名") { m.undo() }.disabled(m.undoPlan.isEmpty) }
            }
            if result.module == .image {
                HStack(spacing: 8) {
                    ForEach(Array(result.successful.prefix(7))) { item in
                        Thumbnail(item: item).frame(width: 42, height: 42).onDrag { NSItemProvider(contentsOf: item.output!) ?? NSItemProvider() }
                    }
                    if result.successful.count > 7 { Text("+\(result.successful.count - 7)").foregroundStyle(.secondary) }
                }
            }
        }.padding(.horizontal, 22).padding(.vertical, 16).background(Color(nsColor: .controlBackgroundColor))
        Divider()
    }
}

struct RenameComparison: View {
    @EnvironmentObject private var m: WorkbenchModel
    var body: some View {
        let plans = m.renamePlan
        let names = Dictionary(uniqueKeysWithValues: zip(m.items,plans).map { ($0.0.id,$0.1.renamed.lastPathComponent) })
        VStack(alignment: .leading, spacing: 0) {
            HStack { Text("名称对照").font(.headline); Spacer(); Text("\(m.items.count) 个文件").foregroundStyle(.secondary) }.padding(20)
            Table(m.items, selection: $m.selection) {
                TableColumn("原文件名") { item in Text(item.url.lastPathComponent).lineLimit(2).foregroundStyle(.secondary).textSelection(.enabled).padding(.vertical, 8) }
                TableColumn("新文件名") { item in Text(names[item.id] ?? "名称冲突，请调整规则").foregroundStyle(names[item.id] == nil ? Color.red : Color.primary).fontWeight(.medium).lineLimit(2).textSelection(.enabled) }
                TableColumn("状态") { item in Text(item.status).foregroundStyle(.secondary) }.width(90)
            }.tableStyle(.inset).alternatingRowBackgrounds(.disabled).contextMenu { if let id = m.selection { Button("移除所选文件") { m.items.removeAll { $0.id == id } }.disabled(m.running) } }
            if let problem = m.renameProblem { Label(problem, systemImage: "exclamationmark.triangle").foregroundStyle(.red).padding(16) }
        }
    }
}
