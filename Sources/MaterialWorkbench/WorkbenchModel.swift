import SwiftUI
import UniformTypeIdentifiers
import AVFoundation
@MainActor final class WorkbenchModel: ObservableObject {
 @Published var module: Module?; @Published var items: [Item] = []; @Published var selection: UUID?; @Published var options = Options() { didSet { if let data = try? JSONEncoder().encode(options) { UserDefaults.standard.set(data,forKey:"options.v1") } } }; @Published var running = false; @Published var error: String?; @Published var outputDirectory: URL?; @Published var undoPlan: [RenamePair] = []
 @Published var batch: BatchResult?
 @Published var pdfName = ""
 private var imageWorkspace: (items: [Item], options: Options, batch: BatchResult?)?
 let runner = ProcessRunner(); let thumbnails = ThumbnailLoader()
 init() { if let data = UserDefaults.standard.data(forKey:"options.v1"), let stored = try? JSONSerialization.jsonObject(with:data) as? [String:Any], let defaultData = try? JSONEncoder().encode(Options()), var merged = try? JSONSerialization.jsonObject(with:defaultData) as? [String:Any] { merged.merge(stored) { _,saved in saved }; if let compatible = try? JSONSerialization.data(withJSONObject:merged), let saved = try? JSONDecoder().decode(Options.self,from:compatible) { options = saved; return } }; options.targetMB = UserDefaults.standard.double(forKey:"targetMB"); if options.targetMB <= 0 { options.targetMB = 100 }; options.codec = UserDefaults.standard.string(forKey:"codec") ?? "自动推荐" }
 var selected: Item? { items.first { $0.id == selection } }
 func switchModule(_ value: Module) { guard !running else { return }; module = value; items = []; selection = nil; batch = nil; pdfName = ""; imageWorkspace = nil }
 func chooseFiles() {
  let p = NSOpenPanel(); p.canChooseDirectories = true; p.canChooseFiles = true; p.allowsMultipleSelection = true; p.prompt = "添加素材"
  if p.runModal() == .OK { importURLs(p.urls) }
 }
 func importURLs(_ urls: [URL]) {
  guard !running else { return }
  let currentModule = module
  Task {
   let expanded = await Task.detached { () -> [URL] in
    urls.flatMap { u -> [URL] in
     var dir: ObjCBool = false
     if FileManager.default.fileExists(atPath:u.path,isDirectory:&dir), dir.boolValue {
      return (FileManager.default.enumerator(at:u,includingPropertiesForKeys:[.isRegularFileKey],options:[.skipsHiddenFiles,.skipsPackageDescendants])?.allObjects as? [URL] ?? []).filter { (try? $0.resourceValues(forKeys:[.isRegularFileKey]).isRegularFile) == true }.sorted { $0.path.localizedStandardCompare($1.path) == .orderedAscending }
     }; return [u]
    }
   }.value
   if module == nil, let first = expanded.first { let type = UTType(filenameExtension:first.pathExtension); module = type?.conforms(to:.movie) == true ? .video : type?.conforms(to:.image) == true ? .image : .rename }
   guard currentModule == nil || module == currentModule else { return }
   for u in expanded {
    let type = UTType(filenameExtension:u.pathExtension)
    if module == .video && type?.conforms(to:.movie) != true { continue }
    if (module == .image || module == .pdf) && type?.conforms(to:.image) != true { continue }
    if !items.contains(where:{$0.url == u}) { batch = nil; let item = Item(url:u); items.append(item); if selection == nil { selection = item.id }; let id = item.id
     Task { let image = await thumbnails.load(u); if let index = items.firstIndex(where:{$0.id == id}) { items[index].thumbnail = image } }
    }
   }
  }
 }
 func chooseOutput() -> URL? {
  let p = NSOpenPanel(); p.canChooseFiles = false; p.canChooseDirectories = true; p.canCreateDirectories = true; p.prompt = "选择输出位置"
  guard p.runModal() == .OK else { return nil }; outputDirectory = p.url; return p.url
 }
 func update(_ id: UUID, progress: Double? = nil, status: String? = nil, output: URL? = nil, details: String? = nil) {
  guard let i = items.firstIndex(where:{$0.id == id}) else { return }
  if let progress { items[i].progress = progress }; if let status { items[i].status = status }; if let output { items[i].output = output }; if let details { items[i].details = details }
 }
 func move(_ id: UUID, to target: UUID) { guard !running, let from = items.firstIndex(where:{$0.id == id}), let to = items.firstIndex(where:{$0.id == target}), from != to else { return }; let item = items.remove(at:from); items.insert(item,at:min(to,items.count)) }
 func saveComposition() { guard let i = items.firstIndex(where:{$0.id == selection}) else { return }; items[i].x = options.x; items[i].y = options.y; items[i].zoom = options.zoom }
 func loadComposition() { guard let item = selected else { return }; options.x = item.x; options.y = item.y; options.zoom = item.zoom }
 func start() {
  guard !running, !items.isEmpty, let module else { return }
  if module == .rename { rename(); return }
  guard let directory = outputDirectory ?? chooseOutput() else { return }
  UserDefaults.standard.set(options.targetMB,forKey:"targetMB"); UserDefaults.standard.set(options.codec,forKey:"codec")
  saveComposition();
  for i in items.indices { items[i].output = nil; items[i].details = ""; items[i].status = "等待处理"; items[i].progress = 0 }
  let snapshot = items; var settings = options; if module == .pdf { settings.fit = options.pdfFit }; let pdfOutputName = pdfName; runner.reset(); batch = nil; running = true
  Task {
   if module == .pdf {
    do { let result = try await Task.detached { try PDFService.merge(snapshot.map(\.url),directory:directory,options:settings,cancelled:{self.runner.isCancelled},progress:{ value in Task { @MainActor in for item in snapshot { if self.items.first(where:{$0.id == item.id})?.status != "已完成" { self.update(item.id,progress:value,status:"正在合并") } } } },outputName:pdfOutputName) }.value
     for item in snapshot { update(item.id,progress:1,status:"已完成",output:result,details:"\(snapshot.count) 页 · \(sizeText(bytes(result)))") }
    } catch { for item in snapshot { update(item.id,status:error is CancellationError ? "已取消" : "失败",details:error.localizedDescription) }; self.error = error is CancellationError ? "已取消，未交付不完整文件。" : error.localizedDescription }
   } else {
    for item in snapshot {
     if runner.isCancelled { break }; update(item.id,progress:0,status:"正在处理")
     var o = settings; o.x = item.x; o.y = item.y; o.zoom = item.zoom
     do {
      let result = try await Task.detached { () throws -> (URL,String) in
       if module == .video { return try VideoService(self.runner).process(item.url,directory:directory,options:o,progress: { p in Task { @MainActor in self.update(item.id,progress:p) } },outputName:item.customName) }
       if self.runner.isCancelled { throw CancellationError() }; return try ImageService.convert(item.url,directory:directory,options:o,cancelled:{self.runner.isCancelled},outputName:item.customName)
      }.value
      update(item.id,progress:1,status:"已完成",output:result.0,details:result.1)
      if module == .image { let thumbnail = await thumbnails.load(result.0); if let index = items.firstIndex(where:{$0.id == item.id}) { items[index].thumbnail = thumbnail } }
     } catch { update(item.id,status:error is CancellationError ? "已取消" : "失败",details:error.localizedDescription) }
    }
   }
   for i in items.indices where items[i].status == "等待处理" { items[i].status = "已取消" }
   batch = BatchResult(module:module,items:items,directory:directory)
   running = false
  }
 }
 var renamePlan: [RenamePair] { (try? RenameService.plan(items.map(\.url),options:options)) ?? [] }
 var renameProblem: String? { guard !items.isEmpty else { return nil }; do { _ = try RenameService.plan(items.map(\.url),options:options); return nil } catch { return error.localizedDescription } }
 func rename() {
  do { let plan = try RenameService.plan(items.map(\.url),options:options); let alert = NSAlert(); alert.messageText = "重命名 \(plan.count) 个文件？"; alert.informativeText = "这会直接修改原文件名。请核对列表中的预览；完成后可撤销最近一次操作。"; alert.addButton(withTitle:"重命名"); alert.addButton(withTitle:"取消"); guard alert.runModal() == .alertFirstButtonReturn else { return }; running = true
   Task { do { try await Task.detached { try RenameService.apply(plan) }.value; undoPlan = plan.map { RenamePair(original:$0.renamed,renamed:$0.original) }; for i in items.indices { items[i].url = plan[i].renamed; items[i].status = "已重命名" }; batch = BatchResult(module:.rename,items:items,directory:nil) } catch { self.error = error.localizedDescription }; running = false }
  } catch { self.error = error.localizedDescription }
 }
 func undo() { guard !running, !undoPlan.isEmpty else { return }; let plan = undoPlan; running = true; Task { do { try await Task.detached { try RenameService.apply(plan) }.value; for i in items.indices { if let pair = plan.first(where:{$0.original == items[i].url}) { items[i].url = pair.renamed; items[i].status = "已撤销" } }; undoPlan = []; batch = BatchResult(module:.rename,items:items,directory:nil) } catch { self.error = error.localizedDescription }; running = false } }
 func setCustomName(_ name:String, id:UUID) { if let i = items.firstIndex(where:{$0.id == id}) { items[i].customName = name } }
 func setVideoInfo(_ info:VideoInfo, id:UUID) { if let i = items.firstIndex(where:{$0.id == id}) { items[i].videoInfo = info } }
 func outputStem(_ item:Item) -> String {
  if !item.customName.trimmingCharacters(in:.whitespacesAndNewlines).isEmpty { return item.customName }
  switch module {
  case .video: return OutputNaming.video(item.url,options:options,info:item.videoInfo)
  case .image: return OutputNaming.image(item.url,options:options)
  case .pdf: return pdfName.isEmpty ? OutputNaming.pdf(items.map(\.url)) : pdfName
  default: return item.url.deletingPathExtension().lastPathComponent
  }
 }
 func outputExtension(_ item:Item) -> String {
  if module == .image { return "jpg" }; if module == .pdf { return "pdf" }
  if module == .video, let info = item.videoInfo, bytes(item.url) <= Int64(max(0,min(1_000_000,options.targetMB.isFinite ? options.targetMB : 0))*1_000_000), options.ratio == "原始比例", options.zoom == 1, options.resolution == "原始", options.codec == "自动推荐", options.fps == "保留时间节奏" || (options.fps == "自动" && !info.vfr) { return item.url.pathExtension }
  return "mp4"
 }
 func previewFilename(_ item:Item) -> String {
  let ext = outputExtension(item), stem = outputStem(item)
  if let directory = outputDirectory, let url = try? OutputNaming.destination(directory:directory,automatic:stem,custom:nil,extension:ext) { return url.lastPathComponent }
  let clean = stem.lowercased().hasSuffix("."+ext.lowercased()) ? String(stem.dropLast(ext.count+1)) : stem
  return clean+"."+ext
 }
 func imagesToPDF() {
  guard !running, module == .image, let result = batch, result.module == .image, !result.successful.isEmpty else { return }
  imageWorkspace = (items, options, batch)
  items = result.successful.compactMap { item in item.output.map { Item(url:$0,thumbnail:item.thumbnail) } }
  module = .pdf; selection = items.first?.id; batch = nil; pdfName = ""
 }
 var canReturnToImages: Bool { imageWorkspace != nil && module == .pdf }
 func returnToImages() {
  guard !running, let saved = imageWorkspace else { return }
  var restored = saved.options; restored.paper = options.paper; restored.pdfFit = options.pdfFit; restored.lightPDF = options.lightPDF
  module = .image; items = saved.items; options = restored; batch = saved.batch; selection = items.first?.id; imageWorkspace = nil
 }

}

actor ThumbnailLoader {
 func load(_ u:URL) -> NSImage? {
  if UTType(filenameExtension:u.pathExtension)?.conforms(to:.movie) == true {
   let generator = AVAssetImageGenerator(asset:AVURLAsset(url:u)); generator.appliesPreferredTrackTransform = true; generator.maximumSize = CGSize(width:400,height:400)
   if let cg = try? generator.copyCGImage(at:.zero,actualTime:nil) { return NSImage(cgImage:cg,size:.zero) }; return nil
  }; return ImageService.thumbnail(u)
 }
}
