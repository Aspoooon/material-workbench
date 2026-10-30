# 素材工作台 · Material Workbench

轻量的原生 macOS 素材处理工具。视频压缩、图片转换、图片合并 PDF、文件批量重命名，在本机完成，无登录、云服务或遥测。

A native, local-first macOS utility for video compression, image conversion, image-to-PDF and safe batch renaming. Chinese interface.

## 功能

- **视频**：指定体积上限；H.264 / HEVC VideoToolbox；CFR / VFR 识别与帧率转换；可视化比例、位置和缩放；批量队列、取消、体积校验。
- **图片**：系统支持的 RAW / JPEG / PNG / HEIF / TIFF 等转换为 JPEG；质量、尺寸、比例、体积控制；缩略图与放大预览。
- **PDF**：图片拖动排序；A4 / Letter / 图片尺寸；适应 / 铺满；标准与轻量输出。图片转换后可直接将成功结果带入 PDF。
- **重命名**：新旧名称实时对照；编号、前后缀、查找替换；冲突检测、失败回滚与当前会话内撤销。
- 按实际操作生成输出名称，支持手动修改；默认保留原素材。同名输出安全编号。
- 原生工具栏、深浅色模式、Finder 拖入、快捷键；关窗后保留队列并支持重新打开。

## 安装

从本仓库 **Releases** 下载 DMG，打开后把「素材工作台」拖入 Applications。更新时先退出旧版，再替换 App。

当前二进制适用于 **Apple Silicon / macOS 27+**。运行不需要 Xcode、终端或 Homebrew。Intel 和较早 macOS 尚未验证；源码的 SwiftUI 部署目标与附带运行时的最低版本不同，不代表旧系统已受支持。

发行版使用 ad-hoc 签名，没有 Developer ID 签名或 Apple 公证。macOS 可能拦截从网络下载的应用；仅对确认来源的文件，通过「系统设置 → 隐私与安全性」允许打开。不需要关闭系统安全保护。

## 从源码构建

需要 Apple Silicon Mac、macOS 27、Xcode 27 / Swift 6、系统 `make`。无需 Homebrew 或第三方 Swift 包。

```sh
# 在克隆后的仓库根目录执行
shasum -a 256 -c Runtime/SOURCE.sha256
./scripts/build-runtime.sh
./scripts/build.sh
./scripts/package-dmg.sh
```

源码仓库包含官方 FFmpeg 8.0 源码归档；运行时脚本在临时目录构建 arm64 FFmpeg / FFprobe，然后写入 `Runtime/`。首次编译需要几分钟。源码归档已包含在仓库内，构建无需额外下载媒体依赖。

输出为 `dist/素材工作台.app` 和 `dist/素材工作台.dmg`。应用标识保持 `local.spencer.MaterialWorkbench`，不要改成第二套 App 标识，否则已有设置不会自动沿用。

构建脚本默认缓存于项目 `.build/`，可通过 `MATERIAL_BUILD_DIR` 指定独立目录。打开 `Package.swift` 可在 Xcode 查看源码；独立运行的完整 App 请使用上述打包脚本生成。

## 使用

首页选择工具，或直接拖入文件 / 文件夹。⌘O 添加素材，⌘Return 开始处理。选择输出目录后执行，完成区可定位 Finder 或继续合并 PDF。⌘Z 撤销当前会话最近一次重命名。

文件名里的 `100MB` 表示用户指定的输出上限，并非实际大小。实际体积在结果区显示。目标过低可能明显损失画质；程序不会为满足上限暗中降低视频分辨率。

## 项目结构

- `Sources/MaterialWorkbench/`：SwiftUI / AppKit 界面、窗口生命周期、队列、命名与处理服务。
- `Runtime/`：FFmpeg 源码、许可证和构建后的工具。
- `Resources/`：应用图标。
- `scripts/`：运行时构建、App 打包、DMG 打包。

AVFoundation / VideoToolbox / FFmpeg 负责视频，Image I/O / Core Graphics / PDFKit 负责图片与 PDF；Swift 通过安全的参数数组调用独立进程，不拼接媒体文件 Shell 命令。

## 必要验证

```sh
"dist/素材工作台.app/Contents/MacOS/MaterialWorkbench" --self-test
```

测试在临时目录生成少量媒体，检查体积、裁切、帧率、音视频时间轴、图片转换、PDF 页序、重命名安全、命名规则与图片接 PDF。V1.1 在开发 Mac 上通过 38 项检查；这不等于覆盖所有相机、手机和系统版本。窗口恢复另做了关窗、最小化及系统重新激活的人工验证。

## 已知限制

- HDR / Dolby Vision 暂不转换；只处理第一条视频与第一条音频，不承诺保留字幕、多音轨、章节或复杂元数据。
- RAW 解码取决于 macOS 与相机型号，不保证所有 RAW 格式均可用。
- 软件编码回退为 MPEG-4；硬件编码不保证在同体积下始终获得最高画质。
- 取消图片任务需要等待当前系统解码返回。重命名撤销仅在当前运行会话有效；强制结束、断电和外部同时修改文件不在事务恢复保证内。
- 自动命名的来源标记依赖文件扩展属性。传输后属性丢失时保留完整原名，不猜测删除用户原名。
- 模糊背景预览与导出使用不同模糊实现，视觉可能略有差异。

欢迎用 GitHub Issues 报告可复现问题。请提供 App / 系统版本、操作步骤和必要的媒体规格；不要上传含隐私的素材、完整个人路径或凭据。

## 许可证

应用原创 Swift 代码、构建脚本与原创图标以 **MIT** 发布，见 `LICENSE`。FFmpeg / FFprobe 及其源码不受本项目 MIT 重新许可，按其自身许可证分发。详见 `THIRD_PARTY_NOTICES.md` 和 `Runtime/COPYING.LGPLv2.1`。
