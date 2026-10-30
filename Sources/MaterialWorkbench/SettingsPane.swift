import SwiftUI

struct SettingsPane: View {
    @EnvironmentObject private var m: WorkbenchModel
    let module: Module
    @State private var more = false
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                HStack { Text(module == .rename ? "命名规则" : "输出设置").font(.headline); Spacer(); if module != .rename { Text("应用到全部").font(.caption).foregroundStyle(.secondary) } }
                switch module {
                case .video: video
                case .image: image
                case .pdf: pdf
                case .rename: rename
                }
            }.padding(20)
        }.background(Color(nsColor: .controlBackgroundColor)).disabled(m.running)
    }
    private func field(_ title: String, value: Binding<Double>, unit: String, hint: String? = nil) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack { Text(title); Spacer(); TextField("", value: value, format: .number).textFieldStyle(.roundedBorder).frame(width: 85).multilineTextAlignment(.trailing); Text(unit).foregroundStyle(.secondary) }
            if let hint { Text(hint).font(.callout).foregroundStyle(.secondary) }
        }
    }
    private var ratio: some View {
        Picker("比例", selection: $m.options.ratio) { ForEach(["原始比例","16:9","9:16","1:1","4:5","4:3"], id: \.self) { Text($0) } }
    }
    private var video: some View {
        Group {
            SettingGroup("目标体积", subtitle: "每个视频独立计算，输出不超过此上限") {
                HStack(spacing: 6) {
                    ForEach([50.0,100,200,500], id: \.self) { value in
                        Button("\(Int(value))") { m.options.targetMB = value }
                            .buttonStyle(.bordered).tint(m.options.targetMB == value ? .accentColor : .secondary)
                            .frame(maxWidth: .infinity)
                    }
                }
                field("自定义", value: $m.options.targetMB, unit: "MB")
            }
            SettingGroup("画面与播放") {
                ratio
                Picker("输出最长边", selection: $m.options.resolution) {
                    Text("原始尺寸").tag("原始")
                    ForEach(["720","1080","1920","3840"], id: \.self) { Text($0 + " px").tag($0) }
                }
                Picker("帧率", selection: $m.options.fps) {
                    ForEach(["自动","保留时间节奏","23.976","24","25","29.97","30","50","59.94","60"], id: \.self) { Text($0) }
                }
            }
            if m.options.ratio != "原始比例" || m.options.zoom > 1 {
                SettingGroup("构图") {
                    Picker("适应方式", selection: $m.options.fit) { Text("裁切填满").tag(false); Text("完整保留").tag(true) }
                    if m.options.fit {
                        Picker("背景", selection: $m.options.blur) { Text("黑色").tag(false); Text("模糊画面").tag(true) }
                    } else { composition }
                }
            }
            DisclosureGroup("更多设置", isExpanded: $more) {
                VStack(alignment: .leading, spacing: 16) {
                    Picker("编码策略", selection: $m.options.codec) { ForEach(["自动推荐","通用兼容","高效压缩"], id: \.self) { Text($0) } }
                    if m.options.ratio == "原始比例" && m.options.zoom <= 1 {
                        Picker("适应方式", selection: $m.options.fit) { Text("裁切填满").tag(false); Text("完整保留").tag(true) }
                        if m.options.fit { Toggle("模糊背景", isOn: $m.options.blur) } else { composition }
                    }
                    Text("自动帧率会检查 VFR。保持原始尺寸时不降低分辨率；HDR 暂不转换。").font(.callout).foregroundStyle(.secondary)
                }.padding(.top, 14)
            }
        }
    }
    private var composition: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("拖动画面调整当前视频，也可使用滑块。").font(.callout).foregroundStyle(.secondary)
            HStack { Text("水平").font(.callout); Slider(value: $m.options.x, in: 0...1).onChange(of: m.options.x) { _,_ in m.saveComposition() } }
            HStack { Text("垂直").font(.callout); Slider(value: $m.options.y, in: 0...1).onChange(of: m.options.y) { _,_ in m.saveComposition() } }
            HStack { Text("缩放").font(.callout); Slider(value: $m.options.zoom, in: 1...3).onChange(of: m.options.zoom) { _,_ in m.saveComposition() }; Text("\(m.options.zoom, format: .number.precision(.fractionLength(1)))×").font(.callout).monospacedDigit() }
        }
    }
    private var image: some View {
        Group {
            SettingGroup("格式与画质") {
                LabeledContent("输出格式", value: "JPEG · sRGB")
                Picker("画质", selection: Binding(get: { [0.94,0.82,0.65].contains(m.options.imageQuality) ? m.options.imageQuality : -1 }, set: { if $0 > 0 { m.options.imageQuality = $0 } })) {
                    Text("高画质").tag(0.94); Text("适合分享").tag(0.82); Text("较小体积").tag(0.65); Text("自定义").tag(-1.0)
                }
                field("体积上限", value: $m.options.imageMB, unit: "MB", hint: "0 表示不限制，不会为达标自动缩小尺寸。")
            }
            SettingGroup("图片尺寸") {
                Picker("限制方式", selection: $m.options.imageDimension) { ForEach(["最长边","最大宽度","最大高度"], id: \.self) { Text($0) } }
                field("最大像素", value: $m.options.imageMax, unit: "px", hint: "0 保持原尺寸，不放大原片。")
            }
            DisclosureGroup("更多设置", isExpanded: $more) {
                VStack(alignment: .leading, spacing: 16) {
                    HStack { Text("JPEG 质量"); Spacer(); Text("\(Int(m.options.imageQuality*100))%").monospacedDigit() }
                    Slider(value: $m.options.imageQuality, in: 0.1...1)
                    field("缩放比例", value: $m.options.percent, unit: "%")
                    ratio
                    Picker("透明区域填充", selection: $m.options.background) { Text("白色").tag("白色"); Text("黑色").tag("黑色") }
                    Text("RAW 解码支持取决于 macOS 和相机型号。").font(.callout).foregroundStyle(.secondary)
                }.padding(.top, 14)
            }
        }
    }
    private var pdf: some View {
        Group {
            SettingGroup("页面") {
                Picker("尺寸", selection: $m.options.paper) { ForEach(["A4","Letter","图片尺寸"], id: \.self) { Text($0) } }
                Picker("布局", selection: $m.options.pdfFit) { Text("完整适应").tag(true); Text("铺满裁切").tag(false) }
            }
            SettingGroup("输出画质") {
                Picker("策略", selection: $m.options.lightPDF) { Text("标准画质").tag(false); Text("轻量分享").tag(true) }.pickerStyle(.radioGroup)
                Text(m.options.lightPDF ? "最长边 1800px，适合发送与分享。" : "保留图片像素，适合查看细节。").font(.callout).foregroundStyle(.secondary)
            }
            Label("左侧顺序即最终页序，可直接拖动调整。", systemImage: "arrow.up.arrow.down").font(.callout).foregroundStyle(.secondary)
        }
    }
    private var rename: some View {
        Group {
            SettingGroup("名称") {
                TextField("统一名称，留空保留原名", text: $m.options.base).textFieldStyle(.roundedBorder)
                TextField("前缀", text: $m.options.prefix).textFieldStyle(.roundedBorder)
                TextField("后缀", text: $m.options.suffix).textFieldStyle(.roundedBorder)
            }
            SettingGroup("连续编号") {
                Stepper("起点：\(m.options.start)", value: $m.options.start, in: 0...999999)
                Stepper("位数：\(m.options.digits)", value: $m.options.digits, in: 1...12)
            }
            SettingGroup("查找替换") {
                TextField("查找内容", text: $m.options.find).textFieldStyle(.roundedBorder)
                TextField("替换为", text: $m.options.replace).textFieldStyle(.roundedBorder)
            }
            Text("扩展名保持不变。清空统一名称，可只添加前后缀或查找替换。").font(.callout).foregroundStyle(.secondary)
            if !m.items.isEmpty {
                if let problem = m.renameProblem { Label(problem, systemImage: "exclamationmark.triangle").foregroundStyle(.red) }
                else { Label("未发现名称冲突", systemImage: "checkmark.circle").foregroundStyle(.green) }
            }
        }
    }
}

struct SettingGroup<Content: View>: View {
    let title: String
    let subtitle: String?
    @ViewBuilder var content: Content
    init(_ title: String, subtitle: String? = nil, @ViewBuilder content: () -> Content) {
        self.title = title; self.subtitle = subtitle; self.content = content()
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 5) { Text(title).font(.subheadline.weight(.semibold)); if let subtitle { Text(subtitle).font(.callout).foregroundStyle(.secondary) } }
            content
        }
    }
}
