import SwiftUI
import UniformTypeIdentifiers
import AVKit

enum Module: String, CaseIterable, Identifiable {
 case video = "视频处理", image = "图片处理", pdf = "合并 PDF", rename = "批量重命名"
 var id: String { rawValue }
 var icon: String { switch self { case .video: "film"; case .image: "photo"; case .pdf: "doc.richtext"; case .rename: "textformat.abc" } }
 var hint: String { switch self { case .video: "让成片轻装出发"; case .image: "从原片到随手分享"; case .pdf: "把图片整理成一份文档"; case .rename: "让文件名井然有序" } }
}
struct Item: Identifiable {
 let id = UUID(); var url: URL; var thumbnail: NSImage?; var status = "等待处理"; var progress = 0.0; var output: URL?; var details = ""; var x = 0.5; var y = 0.5; var zoom = 1.0; var customName = ""; var videoInfo: VideoInfo?
}
struct Options: Codable {
 var targetMB = 100.0; var codec = "自动推荐"; var fps = "自动"; var ratio = "原始比例"; var fit = false; var blur = false; var resolution = "原始"; var x = 0.5; var y = 0.5; var zoom = 1.0
 var imageDimension = "最长边"; var imageQuality = 0.9; var imageMax = 0.0; var percent = 100.0; var imageMB = 0.0; var background = "白色"
 var pdfFit = true; var paper = "A4"; var lightPDF = false
 var base = "素材"; var prefix = ""; var suffix = ""; var find = ""; var replace = ""; var start = 1; var digits = 3
 var aspect: Double? { ["16:9":16.0/9,"9:16":9.0/16,"1:1":1,"4:5":4.0/5,"4:3":4.0/3][ratio] }
}
struct WorkError: LocalizedError { let message: String; var errorDescription: String? { message }; init(_ text: String) { message = text } }
func bytes(_ url: URL) -> Int64 { (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize).map(Int64.init) ?? 0 }
func sizeText(_ n: Int64) -> String { ByteCountFormatter.string(fromByteCount: n, countStyle: .file) }
func availableURL(_ directory: URL, _ name: String, _ ext: String) -> URL {
 var u = directory.appendingPathComponent(name).appendingPathExtension(ext); var n = 2
 while FileManager.default.fileExists(atPath: u.path) { u = directory.appendingPathComponent("\(name)_\(n)").appendingPathExtension(ext); n += 1 }; return u
}

struct BatchResult {
 var module: Module
 var items: [Item]
 var directory: URL?
 var successful: [Item] { items.filter { $0.status == "已完成" && $0.output != nil } }
 var failures: Int { items.filter { $0.status == "失败" }.count }
 var cancelled: Int { items.filter { $0.status == "已取消" || $0.status == "等待处理" }.count }
}
