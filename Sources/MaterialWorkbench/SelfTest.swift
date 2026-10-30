import Foundation
import CoreGraphics
import PDFKit
import ImageIO
import AppKit
enum SelfTest {
 static func run() throws {
  let root = FileManager.default.temporaryDirectory.appendingPathComponent("material-check-\(UUID().uuidString)"); try FileManager.default.createDirectory(at:root,withIntermediateDirectories:true)
  defer { try? FileManager.default.removeItem(at:root) }
  func check(_ ok: Bool,_ message: String) throws { guard ok else { throw WorkError("验收失败："+message) }; print("PASS "+message) }
  let runner = ProcessRunner(); let video = VideoService(runner)
  let src = root.appendingPathComponent("测试视频.mp4")
  _ = try runner.run("ffmpeg",["-v","error","-f","lavfi","-i","testsrc2=size=640x360:rate=30:duration=4","-f","lavfi","-i","sine=frequency=440:duration=4","-c:v","h264_videotoolbox","-b:v","4000000","-c:a","aac","-y",src.path])
  let before = bytes(src); var o = Options(); o.targetMB = 0.35; o.codec = "通用兼容"; o.fps = "24"; o.ratio = "1:1"; o.x = 0.8
  let result = try video.process(src,directory:root,options:o,progress:{_ in}); let info = try video.inspect(result.0)
  try check(bytes(result.0) <= 350000,"视频体积上限")
  try check(info.width == 360 && info.height == 360 && abs(info.fps-24)<0.01,"组合裁切和 CFR 帧率")
  try check(abs(info.duration-4)<0.1 && info.audio,"视频时长和音轨保留")
  try check(bytes(src) == before,"视频原文件保留")
  let expectedPixels = try runner.run("ffmpeg",["-v","error","-i",src.path,"-vf","crop=360:360:224:0","-frames:v","1","-f","rawvideo","-pix_fmt","rgb24","pipe:1"])
  let actualPixels = try runner.run("ffmpeg",["-v","error","-i",result.0.path,"-frames:v","1","-f","rawvideo","-pix_fmt","rgb24","pipe:1"])
  let difference = zip(expectedPixels,actualPixels).reduce(0.0) { $0+abs(Double($1.0)-Double($1.1)) } / Double(max(1,expectedPixels.count))
  try check(expectedPixels.count == actualPixels.count && difference < 22,"裁切坐标与期望画面一致")
  func streamTimes(_ url:URL) throws -> [(Double,Double)] {
   let data = try runner.run("ffprobe",["-v","error","-show_streams","-of","json",url.path]); let json = try JSONSerialization.jsonObject(with:data) as! [String:Any]
   return (json["streams"] as! [[String:Any]]).filter { ["audio","video"].contains($0["codec_type"] as? String ?? "") }.map { (Double($0["start_time"] as? String ?? "0") ?? 0,Double($0["duration"] as? String ?? "0") ?? 0) }
  }
  let times = try streamTimes(result.0)
  try check(times.count == 2 && abs(times[0].0-times[1].0)<0.06 && abs(times[0].1-times[1].1)<0.12,"音视频轨道起止时间同步")
  var copyOptions = Options(); copyOptions.targetMB = 10
  let mov = root.appendingPathComponent("无需转换.mov")
  _ = try runner.run("ffmpeg",["-v","error","-i",src.path,"-c","copy","-y",mov.path])
  let copied = try video.process(mov,directory:root,options:copyOptions,progress:{_ in})
  try check(copied.0.pathExtension == "mov" && (try Data(contentsOf:mov)) == (try Data(contentsOf:copied.0)),"符合上限时保留容器并原样复制")
  let vfr = root.appendingPathComponent("vfr.mp4")
  _ = try runner.run("ffmpeg",["-v","error","-i",src.path,"-vf","select='if(lt(t,2),1,not(mod(n,2)))'","-fps_mode","vfr","-c:v","h264_videotoolbox","-an","-y",vfr.path])
  try check(try video.inspect(vfr).vfr,"根据逐帧时间戳识别 VFR")
  o.fps = "自动"; o.ratio = "原始比例"; o.targetMB = 1
  let stable = try video.process(vfr,directory:root,options:o,progress:{_ in}); try check(try !video.inspect(stable.0).vfr,"VFR 自动转换为 CFR")
  var images: [URL] = []
  for i in 0..<3 {
   let cs = CGColorSpace(name:CGColorSpace.sRGB)!; let c = CGContext(data:nil,width:600,height:400,bitsPerComponent:8,bytesPerRow:0,space:cs,bitmapInfo:CGImageAlphaInfo.premultipliedLast.rawValue)!
   c.setFillColor(CGColor(red:CGFloat(i)/2,green:0.3,blue:0.5,alpha:1)); c.fill(CGRect(x:0,y:0,width:600,height:400)); let image = c.makeImage()!
   let u = root.appendingPathComponent("图片\(i).png"); let d = CGImageDestinationCreateWithURL(u as CFURL,"public.png" as CFString,1,nil)!; CGImageDestinationAddImage(d,image,nil); CGImageDestinationFinalize(d); images.append(u)
  }
  var io = Options(); io.imageMax = 300; io.imageMB = 0.03
  let jpg = try ImageService.convert(images[0],directory:root,options:io)
  try check(bytes(jpg.0)<=30000,"图片尺寸和体积转换")
  let pdf = try PDFService.merge(images.reversed(),directory:root,options:io,cancelled:{false},progress:{_ in})
  try check(PDFDocument(url:pdf)?.pageCount == 3,"PDF 页面数量")
  let document = PDFDocument(url:pdf)!
  let first = document.page(at:0)!.thumbnail(of:CGSize(width:100,height:140),for:.mediaBox)
  let last = document.page(at:2)!.thumbnail(of:CGSize(width:100,height:140),for:.mediaBox)
  let firstRep = NSBitmapImageRep(data:first.tiffRepresentation!)!; let lastRep = NSBitmapImageRep(data:last.tiffRepresentation!)!
  let firstColor = firstRep.colorAt(x:firstRep.pixelsWide/2,y:firstRep.pixelsHigh/2)!.usingColorSpace(.deviceRGB)!
  let lastColor = lastRep.colorAt(x:lastRep.pixelsWide/2,y:lastRep.pixelsHigh/2)!.usingColorSpace(.deviceRGB)!
  try check(firstColor.redComponent > lastColor.redComponent+0.5,"PDF 逆序合并页面内容正确")
  var ro = Options(); ro.base = "A3_产品图"; ro.start = 1
  let plan = try RenameService.plan(images,options:ro); try RenameService.apply(plan)
  try check(plan[0].renamed.lastPathComponent == "A3_产品图_001.png" && FileManager.default.fileExists(atPath:plan[2].renamed.path),"批量重命名和编号")
  try RenameService.apply(plan.map { RenamePair(original:$0.renamed,renamed:$0.original) })
  try check(images.allSatisfy { FileManager.default.fileExists(atPath:$0.path) },"撤销重命名")
  let cycle = [RenamePair(original:images[0],renamed:images[1]),RenamePair(original:images[1],renamed:images[0])]; try RenameService.apply(cycle); try check(images.allSatisfy { FileManager.default.fileExists(atPath:$0.path) },"循环名称安全暂存")
  ro.base = ""; ro.prefix = ""; ro.find = "图片1"; ro.replace = "图片0"
  do { _ = try RenameService.plan(images,options:ro); throw WorkError("冲突未被检测") } catch let e as WorkError { try check(e.message != "冲突未被检测","同名冲突阻止执行") }
  runner.cancel(); do { _ = try runner.run("ffprobe",[src.path]); throw WorkError("取消未生效") } catch is CancellationError { print("PASS 取消任务") }
  let active = ProcessRunner(); let done = DispatchSemaphore(value:0); var wasCancelled = false
  DispatchQueue.global().async {
   do { _ = try active.run("ffmpeg",["-v","error","-re","-f","lavfi","-i","testsrc2=size=64x64:rate=30","-t","30","-f","null","-"]) } catch is CancellationError { wasCancelled = true } catch { print(error.localizedDescription) }; done.signal()
  }
  Thread.sleep(forTimeInterval:0.4); active.cancel()
  try check(done.wait(timeout:.now()+5) == .success && wasCancelled,"运行中取消并回收进程")
  try MainActor.assumeIsolated { try V11Checks.run(root:root,images:images) }
  print("ALL CHECKS PASSED")
 }
}
