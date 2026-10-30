import Foundation
import AppKit

@MainActor enum V11Checks {
    static func run(root: URL, images: [URL]) throws {
        func check(_ valid: Bool, _ title: String) throws {
            guard valid else { throw WorkError("V1.1 验证失败：" + title) }; print("PASS " + title)
        }
        let source = root.appendingPathComponent("A3_Demo.mp4")
        try Data("source".utf8).write(to: source)
        let info = VideoInfo(codec: "h264", duration: 10, width: 1920, height: 1080, fps: 60, cadenceFPS: 60, vfr: false, audio: true, hdr: false)
        var o = Options()
        try check(OutputNaming.video(source, options: o, info: info) == "A3_Demo_100MB", "100MB 命名")
        o.targetMB = 10
        try check(OutputNaming.video(source, options: o, info: info) == "A3_Demo_10MB", "10MB 命名")
        o.targetMB = 100; o.ratio = "9:16"; o.resolution = "1920"; o.fps = "30"
        try check(OutputNaming.video(source, options: o, info: info) == "A3_Demo_100MB_9x16_1080P_30fps", "组合操作命名及分辨率准确")
        o.ratio = "16:9"; o.resolution = "原始"; o.fps = "60"
        try check(OutputNaming.video(source, options: o, info: info) == "A3_Demo_100MB", "未变化的比例与帧率不附加")
        let manual = try OutputNaming.destination(directory: root, automatic: "A3_Demo_100MB", custom: "我的交付.mp4", extension: "mp4")
        try check(manual.lastPathComponent == "我的交付.mp4", "手动名称优先")
        try Data("existing".utf8).write(to: manual)
        OutputNaming.record(manual,input:source,custom:"我的交付.mp4")
        try check(OutputNaming.base(manual) == "我的交付", "再次处理仍保留手动基础名称")
        let next = try OutputNaming.destination(directory: root, automatic: "unused", custom: "我的交付", extension: "mp4")
        try check(next.lastPathComponent == "我的交付_2.mp4" && (try Data(contentsOf: manual)) == Data("existing".utf8), "命名冲突不覆盖")
        do { _ = try OutputNaming.destination(directory: root, automatic: "safe", custom: "../bad", extension: "jpg"); throw WorkError("路径穿越未阻止") } catch let e as WorkError { try check(e.message != "路径穿越未阻止", "非法输出名称阻止") }
        let previous = root.appendingPathComponent("A3_Demo_100MB.mp4")
        try Data("output".utf8).write(to: previous); OutputNaming.record(previous, input: source)
        o = Options(); o.targetMB = 10
        try check(OutputNaming.video(previous, options: o, info: info) == "A3_Demo_10MB", "依据输出来源替换旧后缀")
        let userFile = root.appendingPathComponent("用户原名_100MB.mp4")
        try Data().write(to: userFile)
        try check(OutputNaming.base(userFile) == "用户原名_100MB", "用户原有参数式名称保留")
        o = Options()
        try check(OutputNaming.image(images[0], options: o) == "图片0", "仅图片格式转换不添加后缀")
        o.imageMB = 10; o.imageMax = 300
        try check(OutputNaming.image(images[0], options: o) == "图片0_10MB_300px", "图片体积和尺寸统一命名")
        o.imageMax = 2000; o.ratio = "原始比例"
        try check(OutputNaming.image(images[0], options: o) == "图片0_10MB", "没有缩小的图片不标尺寸")

        let defaults = UserDefaults.standard
        let keys = ["options.v1", "targetMB", "codec"]
        let saved = keys.map { defaults.object(forKey: $0) }
        defer { for (key, value) in zip(keys, saved) { if let value { defaults.set(value, forKey: key) } else { defaults.removeObject(forKey: key) } } }
        var legacy = try JSONSerialization.jsonObject(with: JSONEncoder().encode(Options())) as! [String:Any]
        legacy.removeValue(forKey:"pdfFit"); legacy["targetMB"] = 200.0
        defaults.set(try JSONSerialization.data(withJSONObject:legacy),forKey:"options.v1")
        let m = WorkbenchModel(); m.module = .image
        try check(m.options.targetMB == 200 && m.options.pdfFit, "旧版选项兼容且不重置体积设置")
        m.options.fit = false
        m.items = [Item(url: images[0]), Item(url: images[1]), Item(url: images[2])]
        m.items[0].status = "已完成"; m.items[0].output = images[0]
        m.items[1].status = "失败"
        m.items[2].status = "已完成"; m.items[2].output = images[2]
        m.batch = BatchResult(module: .image, items: m.items, directory: root)
        m.imagesToPDF()
        try check(!m.options.fit, "PDF 布局不改变原视频构图选项")
        try check(m.module == .pdf && m.items.map(\.url) == [images[0],images[2]], "图片接 PDF 仅包含本批成功输出并保序")
        m.move(m.items[1].id, to: m.items[0].id)
        try check(m.items.map(\.url) == [images[2],images[0]], "传入 PDF 后仍可排序")
        m.returnToImages()
        try check(m.module == .image && m.items.count == 3 && m.batch?.successful.count == 2, "返回图片保留输出结果和失败信息")
        m.running = true
        let delegate = WorkbenchDelegate(); delegate.model = m
        let window = NSWindow(contentRect: NSRect(x:0,y:0,width:600,height:400), styleMask: [.titled,.closable,.miniaturizable], backing: .buffered, defer: false)
        delegate.register(window)
        try check(!delegate.windowShouldClose(window), "关闭主窗口保留窗口与任务")
        _ = delegate.applicationShouldHandleReopen(NSApplication.shared, hasVisibleWindows: false)
        try check(window.isVisible && m.running && m.items.count == 3 && delegate.mainWindow === window, "Dock 重新打开沿用同一窗口与队列")
        window.orderOut(nil); window.delegate = nil
        m.running = false
    }
}
