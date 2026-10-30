import SwiftUI
import AVKit
struct PreviewPane: View {
 @EnvironmentObject var m: WorkbenchModel
 @State private var player: AVPlayer?
 @State private var sourceSize = CGSize(width:16,height:9)
 @State private var enlarged: NSImage?
 @State private var showEnlarged = false
 @State private var grid = false
 @State private var sourceInfo: VideoInfo?
 @State private var inspector: ProcessRunner?
 var body: some View {
  VStack(spacing:18) {
   if let item = m.selected {
    HStack { if m.module == .image { Button { grid.toggle() } label: { Image(systemName:grid ? "rectangle" : "square.grid.2x2") }.help("切换缩略图网格") }; Text(item.url.lastPathComponent).font(.headline).lineLimit(1); Spacer(); if m.module == .video { Text("构图预览").font(.caption).foregroundStyle(.secondary) } }.padding(.horizontal,24).padding(.top,24)
    GeometryReader { proxy in
     ZStack {
      (m.module == .video ? Color.black : Color(nsColor:.windowBackgroundColor))
      if m.module == .image && grid {
       ScrollView { LazyVGrid(columns:[GridItem(.adaptive(minimum:110))],spacing:14) { ForEach(m.items) { entry in Button { m.selection = entry.id; grid = false } label: { VStack { if let thumb = entry.thumbnail { Image(nsImage:thumb).resizable().scaledToFit().frame(height:100) } else { ProgressView().frame(height:100) }; Text(entry.url.lastPathComponent).font(.caption).lineLimit(1) }.padding(8) }.buttonStyle(.plain) } }.padding(18) }
      } else if m.module == .video {
       let aspect = VideoGeometry(source:sourceSize,options:m.options).aspect
       let width = min(proxy.size.width-36,(proxy.size.height-36)*aspect)
       VideoCanvas(player:player,options:m.options,sourceSize:sourceSize).frame(width:width,height:width/aspect)
      } else if let image = item.thumbnail { PhotoCanvas(image:image,module:m.module ?? .image,options:m.options).padding(30).onTapGesture { let url = item.url; Task { enlarged = await Task.detached { ImageService.thumbnail(url,edge:4000) }.value; showEnlarged = true } } }
      else { Image(systemName:"doc").font(.system(size:70,weight:.ultraLight)).foregroundStyle(.secondary) }
     }.clipShape(RoundedRectangle(cornerRadius:10))
     .gesture(DragGesture().onChanged { value in if m.module == .video && !m.options.fit { m.options.x = min(1,max(0,value.location.x/proxy.size.width)); m.options.y = min(1,max(0,value.location.y/proxy.size.height)); m.saveComposition() } })
    }.padding(.horizontal,24)
    VStack(alignment:.leading,spacing:10) {
     if m.module == .video { HStack { Button { player?.rate == 0 ? player?.play() : player?.pause() } label: { Label("播放 / 暂停",systemImage:"playpause") }; Button("回到开头") { player?.seek(to:.zero) } } }
     if m.module == .video, let info = sourceInfo {
      Text("源素材：\(info.width)×\(info.height) · \(String(format:"%.3f",info.fps)) fps · \(info.vfr ? "VFR" : "CFR") · \(info.codec.uppercased()) · \(String(format:"%.1f",info.duration)) 秒").font(.caption).foregroundStyle(.secondary)
      if m.options.targetMB*8_000_000/max(1,info.duration)/Double(info.width*info.height)/max(1,info.fps) < 0.04 { Label("目标体积偏小，画质可能明显下降。尺寸和帧率仍会保留。",systemImage:"exclamationmark.triangle").font(.caption).foregroundStyle(.orange) }
     }
     Text(item.details.isEmpty ? "选择右侧设置，然后开始处理。" : item.details).font(.callout).foregroundStyle(item.status == "失败" ? .red : .secondary).textSelection(.enabled)
     if let output = item.output {
      Text(output.lastPathComponent).font(.callout.weight(.medium)).textSelection(.enabled)
      HStack { Button("在 Finder 中显示") { NSWorkspace.shared.activateFileViewerSelecting([output]) }; Text("拖出结果").padding(7).background(.quaternary,in:RoundedRectangle(cornerRadius:6)).onDrag { NSItemProvider(contentsOf:output) ?? NSItemProvider() } }
     }
    }.frame(maxWidth:.infinity,alignment:.leading).padding(24)
   } else { ContentUnavailableView("添加素材，开始处理",systemImage:m.module?.icon ?? "tray.and.arrow.down",description:Text("拖入文件，或按 ⌘O 添加。")) }
  }
  .onChange(of:m.selection) { _,_ in loadSelection() }
  .onAppear { loadSelection() }
  .sheet(isPresented:$showEnlarged) { VStack { if let image = enlarged { Image(nsImage:image).resizable().scaledToFit() }; Button("关闭") { showEnlarged = false }.keyboardShortcut(.cancelAction) }.padding().frame(minWidth:700,minHeight:600) }
  .onDisappear { player?.pause(); inspector?.cancel() }
 }
 func loadSelection() {
  player?.pause(); inspector?.cancel(); sourceInfo = nil; m.loadComposition()
  guard let item = m.selected, m.module == .video else { player = nil; return }
  player = AVPlayer(url:item.url); let runner = ProcessRunner(); inspector = runner
  Task {
   let asset = AVURLAsset(url:item.url)
   if let track = try? await asset.loadTracks(withMediaType:.video).first, let size = try? await track.load(.naturalSize), let transform = try? await track.load(.preferredTransform), m.selection == item.id { let transformed = size.applying(transform); sourceSize = CGSize(width:abs(transformed.width),height:abs(transformed.height)) }
   let info: VideoInfo?
   if let cached = item.videoInfo { info = cached } else { info = try? await Task.detached { try VideoService(runner).inspect(item.url) }.value }
   if m.selection == item.id { sourceInfo = info; if let info { m.setVideoInfo(info,id:item.id) } }
  }
 }
}
