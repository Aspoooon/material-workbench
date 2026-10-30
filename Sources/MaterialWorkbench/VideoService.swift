import Foundation
import CoreGraphics
struct VideoInfo {
 var codec: String; var duration: Double; var width: Int; var height: Int; var fps: Double; var cadenceFPS: Double; var vfr: Bool; var audio: Bool; var hdr: Bool
}
final class VideoService {
 let runner: ProcessRunner
 init(_ runner: ProcessRunner) { self.runner = runner }
 func inspect(_ url: URL) throws -> VideoInfo {
  let data = try runner.run("ffprobe", ["-v","error","-show_streams","-show_format","-of","json",url.path])
  let json = try JSONSerialization.jsonObject(with: data) as? [String:Any] ?? [:]
  let streams = json["streams"] as? [[String:Any]] ?? []
  guard let v = streams.first(where: { $0["codec_type"] as? String == "video" }) else { throw WorkError("文件没有可读取的视频轨道。") }
  func rate(_ s: String) -> Double { let a = s.split(separator:"/").compactMap { Double($0) }; return a.count == 2 && a[1] != 0 ? a[0]/a[1] : 0 }
  let duration = Double((json["format"] as? [String:Any])?["duration"] as? String ?? "0") ?? 0
  guard duration > 0 else { throw WorkError("无法读取视频时长。") }
  // Read every presentation timestamp, using a file to avoid retaining frame data in memory.
  var previous: Double?; var histogram: [Int:Int] = [:]; var count = 0
  _ = try runner.run("ffprobe", ["-v","error","-select_streams","v:0","-show_entries","frame=best_effort_timestamp_time","-of","csv=p=0",url.path],lineHandler: { line in
   guard let time = Double(line.split(separator:",").first ?? "") else { return }
   if let previous { let interval = time-previous; if interval > 0.00001 { histogram[Int((interval*10000).rounded()),default:0] += 1; count += 1 } }; previous = time
  })
  let nominal = rate(v["avg_frame_rate"] as? String ?? "0/1")
  var cumulative = 0; var median = nominal > 0 ? 1/nominal : 1/30.0
  for key in histogram.keys.sorted() { cumulative += histogram[key] ?? 0; if cumulative > count/2 { median = Double(key)/10000; break } }
  let vfr = histogram.contains { abs(Double($0.key)/10000-median) > max(0.001,median*0.06) }
  var w = v["width"] as? Int ?? 0; var h = v["height"] as? Int ?? 0
  if let sides = v["side_data_list"] as? [[String:Any]], let rotation = sides.compactMap({ $0["rotation"] as? Int }).first, abs(rotation)%180 == 90 { swap(&w,&h) }
  guard w > 0, h > 0, w <= 32768, h <= 32768, duration.isFinite else { throw WorkError("视频尺寸或时长无效。") }
  return VideoInfo(codec:v["codec_name"] as? String ?? "未知",duration:duration,width:w,height:h,fps:nominal > 0 ? nominal : 1/median,cadenceFPS:1/median,vfr:vfr,audio:streams.contains { $0["codec_type"] as? String == "audio" },hdr:["smpte2084","arib-std-b67"].contains(v["color_transfer"] as? String ?? ""))
 }
 func process(_ input: URL, directory: URL, options o: Options, progress: @escaping(Double)->Void, outputName: String? = nil) throws -> (URL,String) {
  guard o.targetMB.isFinite, o.targetMB >= 0.1, o.targetMB <= 1_000_000 else { throw WorkError("请输入 0.1 至 1,000,000 MB 的有效体积。") }
  let info = try inspect(input)
  guard !info.hdr else { throw WorkError("此视频为 HDR。当前版本暂不转换 HDR，以避免未验证的色彩变化。") }
  let limit = Int64(o.targetMB*1_000_000)
  guard limit > 100_000 else { throw WorkError("目标体积过小。") }
  let automaticName = OutputNaming.video(input,options:o,info:info)
  let dest = try OutputNaming.destination(directory:directory,automatic:automaticName,custom:outputName,extension:"mp4")
  let temp = directory.appendingPathComponent(".material-\(UUID().uuidString).mp4")
  defer { try? FileManager.default.removeItem(at:temp) }
  if bytes(input) <= limit && o.ratio == "原始比例" && o.zoom == 1 && o.resolution == "原始" && (o.fps == "保留时间节奏" || (o.fps == "自动" && !info.vfr)) && o.codec == "自动推荐" {
   let copyDest = try OutputNaming.destination(directory:directory,automatic:automaticName,custom:outputName,extension:input.pathExtension)
   try FileManager.default.copyItem(at:input,to:temp); if runner.isCancelled { throw CancellationError() }; try FileManager.default.moveItem(at:temp,to:copyDest); OutputNaming.record(copyDest,input:input,custom:outputName); return (copyDest,"原文件已符合上限，直接复制 · \(info.width)×\(info.height) · \(String(format:"%.3f",info.fps)) fps · \(sizeText(bytes(copyDest)))")
  }
  let geometry = VideoGeometry(source:CGSize(width:info.width,height:info.height),options:o)
  let ow = geometry.width, oh = geometry.height
  var filters: [String] = []
  if o.fit {
   if o.blur { filters.append("split=2[bg][fg];[bg]scale=\(ow):\(oh):force_original_aspect_ratio=increase,crop=\(ow):\(oh),boxblur=20:2[b];[fg]scale=\(ow):\(oh):force_original_aspect_ratio=decrease[f];[b][f]overlay=(W-w)/2:(H-h)/2,setsar=1") }
   else { filters.append("scale=\(ow):\(oh):force_original_aspect_ratio=decrease,pad=\(ow):\(oh):(ow-iw)/2:(oh-ih)/2:black,setsar=1") }
  } else {
   let cw = geometry.cropWidth, ch = geometry.cropHeight
   filters.append("crop=\(cw):\(ch):(iw-ow)*\(o.x):(ih-oh)*\(o.y),scale=\(ow):\(oh),setsar=1")
  }
  var fps: Double? = Double(o.fps)
  if o.fps == "自动" && info.vfr { let common = [23.976,24,25,29.97,30,50,59.94,60]; fps = common.min(by:{abs($0-info.cadenceFPS)<abs($1-info.cadenceFPS)}) }
  let fpsExpression: String? = fps.map { value in [23.976:"24000/1001",29.97:"30000/1001",59.94:"60000/1001"][value] ?? String(value) }
  if let fpsExpression { filters.append("fps=\(fpsExpression)") }
  let audio = info.audio ? min(128000.0,max(32000.0,Double(limit)*8/info.duration*0.10)) : 0
  var bitrate = Double(limit)*8*0.94/info.duration-audio
  guard bitrate >= 24000 else { throw WorkError("体积不足以容纳此时长的视频和音频，请提高目标。") }
  var hardware = true; var hardwareDecode = true
  for attempt in 0..<4 {
   try? FileManager.default.removeItem(at:temp)
   let codec = o.codec == "通用兼容" || (o.codec == "自动推荐" && bitrate / Double(ow*oh) / max(1,info.fps) > 0.16) ? "h264" : "hevc"
   var args = ["-hide_banner","-nostdin","-v","error"] + (hardwareDecode ? ["-hwaccel","videotoolbox"] : []) + ["-i",input.path,"-map","0:v:0","-map","0:a:0?","-vf",filters.joined(separator:","),"-c:v",hardware ? codec+"_videotoolbox" : "mpeg4","-b:v",String(Int(bitrate)),"-pix_fmt","yuv420p"]
   if hardware { args += ["-allow_sw","1"] }
   if fps == nil { args += ["-enc_time_base","demux"] }
   if codec == "hevc" && hardware { args += ["-tag:v","hvc1"] }
   args += ["-fps_mode",fps == nil ? "passthrough" : "cfr","-c:a","aac","-b:a",String(Int(audio)),"-movflags","+faststart","-progress","pipe:1","-y",temp.path]
   do { _ = try runner.run("ffmpeg",args,progress:progress,duration:info.duration) }
   catch { if runner.isCancelled { throw error }; if hardwareDecode { hardwareDecode = false; continue }; if hardware { hardware = false; continue }; throw error }
   let actual = bytes(temp)
   if actual <= limit && actual > 0 {
    let outputInfo = try inspect(temp)
    guard abs(outputInfo.duration-info.duration) < max(0.3,2/info.fps) else { throw WorkError("导出时长校验失败，未交付文件。") }
    if runner.isCancelled { throw CancellationError() }
    try FileManager.default.moveItem(at:temp,to:dest)
    OutputNaming.record(dest,input:input,custom:outputName)
    return (dest,"\(info.width)×\(info.height) · \(info.vfr ? "VFR" : "CFR") → \(ow)×\(oh) · \(String(format:"%.3f",outputInfo.fps)) fps · \(hardware ? (codec == "hevc" ? "HEVC" : "H.264") : "MPEG-4 软件回退")\n\(sizeText(bytes(input))) → \(sizeText(actual)) · 减少 \(Int((1-Double(actual)/Double(max(1,bytes(input))))*100))%\(bitrate/Double(ow*oh)/max(1,outputInfo.fps) < 0.04 ? " · 低码率，画质可能明显下降" : "")")
   }
   bitrate *= min(0.85,Double(limit)/Double(max(1,actual))*0.90)
   if attempt == 3 { throw WorkError("多次调整后仍超过体积上限，请提高目标。未交付超限文件。") }
  }
  throw WorkError("无法完成编码。")
 }
}
