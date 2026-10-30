import AppKit
import ImageIO
import UniformTypeIdentifiers
import CoreImage
import PDFKit

enum ImageService {
 static func thumbnail(_ url: URL, edge: Int = 400) -> NSImage? {
  guard let s = CGImageSourceCreateWithURL(url as CFURL,nil), let image = CGImageSourceCreateThumbnailAtIndex(s,0,[kCGImageSourceCreateThumbnailFromImageIfAbsent:true,kCGImageSourceCreateThumbnailWithTransform:true,kCGImageSourceThumbnailMaxPixelSize:edge,kCGImageSourceShouldCacheImmediately:true] as CFDictionary) else { return nil }
  return NSImage(cgImage:image,size:.zero)
 }
 static func rendered(_ url: URL, options o: Options, maxEdge: Double? = nil) throws -> CGImage {
  guard o.imageMax.isFinite, o.percent.isFinite, o.imageMB.isFinite, o.imageQuality.isFinite, o.imageMax >= 0, o.imageMax <= 100000, o.percent > 0, o.percent <= 100 else { throw WorkError("请输入有效尺寸；百分比范围为 1–100%。") }
  guard let source = CGImageSourceCreateWithURL(url as CFURL,nil), let props = CGImageSourceCopyPropertiesAtIndex(source,0,nil) as? [CFString:Any], let width = props[kCGImagePropertyPixelWidth] as? Double, let height = props[kCGImagePropertyPixelHeight] as? Double else { throw WorkError("系统无法解码此图片或 RAW 格式：\(url.lastPathComponent)") }
  let orientation = props[kCGImagePropertyOrientation] as? Int ?? 1
  let displayWidth = orientation >= 5 ? height : width; let displayHeight = orientation >= 5 ? width : height
  let reference = o.imageDimension == "最大宽度" ? displayWidth : o.imageDimension == "最大高度" ? displayHeight : max(width,height)
  let scale = o.imageMax > 0 ? min(1,o.imageMax/reference) : 1
  let edge = maxEdge ?? max(width,height)*scale
  let target = max(1,Int(edge*min(100,max(1,o.percent))/100))
  guard let decoded = CGImageSourceCreateThumbnailAtIndex(source,0,[kCGImageSourceCreateThumbnailFromImageAlways:true,kCGImageSourceCreateThumbnailWithTransform:true,kCGImageSourceThumbnailMaxPixelSize:target] as CFDictionary) else { throw WorkError("无法解码此图片；当前系统可能不支持该相机 RAW。") }
  var image = decoded
  if let aspect = o.aspect {
   let w = Double(image.width), h = Double(image.height)
   let cw = min(w,h*aspect), ch = min(h,w/aspect)
   guard let cropped = image.cropping(to:CGRect(x:(w-cw)*o.x,y:(h-ch)*o.y,width:cw,height:ch)) else { throw WorkError("图片裁切失败。") }; image = cropped
  }
  guard let cs = CGColorSpace(name:CGColorSpace.sRGB), let context = CGContext(data:nil,width:image.width,height:image.height,bitsPerComponent:8,bytesPerRow:0,space:cs,bitmapInfo:CGImageAlphaInfo.noneSkipLast.rawValue) else { throw WorkError("无法分配图片内存。") }
  context.setFillColor((o.background == "黑色" ? NSColor.black : NSColor.white).cgColor); context.fill(CGRect(x:0,y:0,width:image.width,height:image.height)); context.draw(image,in:CGRect(x:0,y:0,width:image.width,height:image.height))
  guard let result = context.makeImage() else { throw WorkError("无法生成图片。") }; return result
 }
 static func jpeg(_ image: CGImage, quality: Double) throws -> Data {
  let data = NSMutableData(); guard let d = CGImageDestinationCreateWithData(data,UTType.jpeg.identifier as CFString,1,nil) else { throw WorkError("无法创建 JPEG。") }
  CGImageDestinationAddImage(d,image,[kCGImageDestinationLossyCompressionQuality:quality] as CFDictionary)
  guard CGImageDestinationFinalize(d) else { throw WorkError("JPEG 写入失败。") }; return data as Data
 }
 static func convert(_ input: URL, directory: URL, options o: Options, cancelled: ()->Bool = { false }, outputName: String? = nil) throws -> (URL,String) {
  let image = try rendered(input,options:o)
  var data = try jpeg(image,quality:o.imageQuality)
  if o.imageMB > 0 {
   let limit = Int(o.imageMB*1_000_000); var lo = 0.08; var hi = o.imageQuality; var best: Data?
   for _ in 0..<9 { if cancelled() { throw CancellationError() }; let q = (lo+hi)/2; let candidate = try jpeg(image,quality:q); if candidate.count <= limit { best = candidate; lo = q } else { hi = q } }
   guard let best else { throw WorkError("仅降低 JPEG 质量无法达到体积上限。请在尺寸设置中明确选择缩小后重试。") }; data = best
  }
  let dest = try OutputNaming.destination(directory:directory,automatic:OutputNaming.image(input,options:o,outputSize:CGSize(width:image.width,height:image.height)),custom:outputName,extension:"jpg")
  if cancelled() { throw CancellationError() }
  let temp = directory.appendingPathComponent(".material-\(UUID().uuidString).jpg")
  defer { try? FileManager.default.removeItem(at:temp) }
  try data.write(to:temp,options:.withoutOverwriting)
  guard let verified = CGImageSourceCreateWithURL(temp as CFURL,nil), CGImageSourceGetStatus(verified) == .statusComplete else { throw WorkError("JPEG 完整性校验失败，未交付文件。") }
  if cancelled() { throw CancellationError() }
  try FileManager.default.moveItem(at:temp,to:dest)
  OutputNaming.record(dest,input:input,custom:outputName)
  return (dest,"\(image.width)×\(image.height) · sRGB · \(sizeText(Int64(data.count)))")
 }
}
enum PDFService {
 static func merge(_ urls: [URL], directory: URL, options o: Options, cancelled: ()->Bool, progress: (Double)->Void, outputName: String? = nil) throws -> URL {
  let dest = try OutputNaming.destination(directory:directory,automatic:OutputNaming.pdf(urls),custom:outputName,extension:"pdf"); let temp = directory.appendingPathComponent(".material-\(UUID().uuidString).pdf")
  defer { try? FileManager.default.removeItem(at:temp) }
  guard let context = CGContext(temp as CFURL,mediaBox:nil,nil) else { throw WorkError("无法创建 PDF。") }
  for (index,url) in urls.enumerated() {
   if cancelled() { context.closePDF(); throw CancellationError() }
   var imageOptions = Options(); imageOptions.background = o.background
   var image = try ImageService.rendered(url,options:imageOptions,maxEdge:o.lightPDF ? 1800 : nil)
   if o.lightPDF { let data = try ImageService.jpeg(image,quality:0.72); if let s = CGImageSourceCreateWithData(data as CFData,nil), let compressed = CGImageSourceCreateImageAtIndex(s,0,nil) { image = compressed } }
   let page: CGSize
   switch o.paper { case "图片尺寸": page = CGSize(width:image.width,height:image.height); case "Letter": page = CGSize(width:612,height:792); default: page = CGSize(width:595.28,height:841.89) }
   var box = CGRect(origin:.zero,size:page); context.beginPDFPage([kCGPDFContextMediaBox as String:NSData(bytes:&box,length:MemoryLayout<CGRect>.size)] as CFDictionary)
   context.setFillColor(NSColor.white.cgColor); context.fill(box)
   let sx = page.width/CGFloat(image.width), sy = page.height/CGFloat(image.height); let scale = o.fit ? min(sx,sy) : max(sx,sy)
   let rect = CGRect(x:(page.width-CGFloat(image.width)*scale)/2,y:(page.height-CGFloat(image.height)*scale)/2,width:CGFloat(image.width)*scale,height:CGFloat(image.height)*scale)
   context.saveGState(); context.clip(to:box); context.draw(image,in:rect); context.restoreGState(); context.endPDFPage(); progress(Double(index+1)/Double(urls.count))
  }
  context.closePDF()
  guard let pdf = PDFDocument(url:temp), pdf.pageCount == urls.count else { throw WorkError("PDF 页数验证失败。") }
  if cancelled() { throw CancellationError() }
  try FileManager.default.moveItem(at:temp,to:dest); return dest
 }
}
