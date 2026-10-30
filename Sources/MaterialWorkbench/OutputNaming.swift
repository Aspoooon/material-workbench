import Foundation
import ImageIO
import CoreGraphics
import Darwin

/// Only strip suffixes when our own output carries matching provenance.
/// An arbitrary user's filename that happens to end in _100MB is never stripped.
enum OutputNaming {
    private struct Provenance: Codable { let base: String; let stem: String }
    private static let key = "local.spencer.MaterialWorkbench.naming"

    static func base(_ input: URL) -> String {
        let stem = input.deletingPathExtension().lastPathComponent
        let length = getxattr(input.path, key, nil, 0, 0, 0)
        guard length > 0, length < 8192 else { return stem }
        var data = Data(count: length)
        let read = data.withUnsafeMutableBytes { getxattr(input.path, key, $0.baseAddress, length, 0, 0) }
        guard read == length, let record = try? JSONDecoder().decode(Provenance.self, from: data), record.stem == stem else { return stem }
        return record.base
    }

    static func record(_ output: URL, input: URL, custom: String? = nil) {
        var manual = custom?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let ext = output.pathExtension
        if manual.lowercased().hasSuffix("." + ext.lowercased()) { manual = String(manual.dropLast(ext.count + 1)) }
        guard let data = try? JSONEncoder().encode(Provenance(base: manual.isEmpty ? base(input) : manual, stem: output.deletingPathExtension().lastPathComponent)) else { return }
        _ = data.withUnsafeBytes { setxattr(output.path, key, $0.baseAddress, data.count, 0, 0) }
    }

    static func number(_ n: Double) -> String {
        guard n.isFinite else { return "0" }
        return String(format: "%.3f", locale: Locale(identifier: "en_US_POSIX"), n).replacingOccurrences(of: #"\.?0+$"#, with: "", options: .regularExpression)
    }

    static func compose(_ input: URL, tokens: [String]) -> String {
        var used = Set<String>()
        let suffix = tokens.filter { !$0.isEmpty && used.insert($0).inserted }.joined(separator: "_")
        let stem = base(input)
        // APFS limits each component to 255 bytes. Leave space for extension and collision number.
        var trimmed = stem
        let allowance = max(32, 230 - suffix.utf8.count)
        while trimmed.utf8.count > allowance { trimmed.removeLast() }
        return trimmed + (suffix.isEmpty ? "" : "_" + suffix)
    }

    static func video(_ input: URL, options o: Options, info: VideoInfo?) -> String {
        var tokens = [number(o.targetMB) + "MB"]
        if let info {
            let geometry = VideoGeometry(source: CGSize(width: info.width, height: info.height), options: o)
            if let ratio = o.aspect, abs(ratio - Double(info.width) / Double(info.height)) > 0.002 { tokens.append(o.ratio.replacingOccurrences(of: ":", with: "x")) }
            if !o.fit && o.zoom > 1.001 { tokens.append("裁切" + number(o.zoom) + "x") }
            if o.resolution != "原始", geometry.width != info.width || geometry.height != info.height {
                let short = min(geometry.width, geometry.height)
                let isWide = abs(geometry.aspect - 16.0/9) < 0.005 || abs(geometry.aspect - 9.0/16) < 0.005
                tokens.append(isWide && [720,1080,2160].contains(short) ? "\(short)P" : "\(geometry.width)x\(geometry.height)")
            }
            var rate = Double(o.fps)
            if o.fps == "自动" && info.vfr {
                rate = [23.976,24,25,29.97,30,50,59.94,60].min { abs($0-info.cadenceFPS) < abs($1-info.cadenceFPS) }
            }
            if let rate, info.vfr || abs(rate-info.fps) > 0.01 { tokens.append(number(rate) + "fps") }
        } else {
            // Source metadata is being loaded; do not invent changes before it is available.
        }
        return compose(input, tokens: tokens)
    }

    static func imageSize(_ input: URL) -> CGSize? {
        guard let source = CGImageSourceCreateWithURL(input as CFURL, nil), let props = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any], let w = props[kCGImagePropertyPixelWidth] as? Double, let h = props[kCGImagePropertyPixelHeight] as? Double else { return nil }
        let orientation = props[kCGImagePropertyOrientation] as? Int ?? 1
        return orientation >= 5 ? CGSize(width:h,height:w) : CGSize(width:w,height:h)
    }

    static func image(_ input: URL, options o: Options, outputSize: CGSize? = nil) -> String {
        var tokens: [String] = []
        if o.imageMB > 0 { tokens.append(number(o.imageMB) + "MB") }
        if let size = imageSize(input) {
            if let ratio = o.aspect, abs(ratio - size.width/size.height) > 0.002 { tokens.append(o.ratio.replacingOccurrences(of: ":", with: "x")) }
            let reference = o.imageDimension == "最大宽度" ? size.width : o.imageDimension == "最大高度" ? size.height : max(size.width,size.height)
            if o.imageMax > 0 && o.imageMax < reference {
                tokens.append((o.imageDimension == "最大宽度" ? "宽" : o.imageDimension == "最大高度" ? "高" : "") + number(o.imageMax) + "px")
            }
        }
        if o.percent < 100 { tokens.append(number(o.percent) + "pct") }
        return compose(input, tokens: tokens)
    }

    static func pdf(_ inputs: [URL]) -> String {
        guard let first = inputs.first else { return "图片_合集" }
        let names = inputs.map { base($0) }
        var common = base(first)
        for name in names.dropFirst() { while !name.hasPrefix(common) && !common.isEmpty { common.removeLast() } }
        common = common.trimmingCharacters(in: CharacterSet(charactersIn: "_- .0123456789"))
        return (common.count >= 2 ? String(common.prefix(60)) : "图片") + "_合集"
    }

    static func destination(directory: URL, automatic: String, custom: String?, extension ext: String) throws -> URL {
        var stem = custom?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if stem.isEmpty { stem = automatic }
        if stem.lowercased().hasSuffix("." + ext.lowercased()) { stem = String(stem.dropLast(ext.count + 1)) }
        guard !stem.isEmpty, stem != ".", stem != "..", !stem.contains("/"), !stem.contains(":"), !stem.contains("\0"), stem.utf8.count <= 230 else { throw WorkError("输出名称无效或过长，请使用不含 / 和 : 的简短文件名。") }
        return availableURL(directory, stem, ext)
    }
}
