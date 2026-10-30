import SwiftUI
import AVKit
import CoreImage
final class CanvasView: NSView {
 let backgroundVideo = AVPlayerLayer(); let video = AVPlayerLayer(); var options = Options(); var sourceSize = CGSize(width:16,height:9)
 override init(frame:NSRect) { super.init(frame:frame); wantsLayer = true; layer?.backgroundColor = NSColor.black.cgColor; layer?.masksToBounds = true; layer?.addSublayer(backgroundVideo); layer?.addSublayer(video); video.videoGravity = .resize; backgroundVideo.videoGravity = .resizeAspectFill }
 required init?(coder:NSCoder) { fatalError() }
 override func layout() {
  super.layout(); let w = bounds.width, h = bounds.height; let sw = sourceSize.width, sh = sourceSize.height; guard w > 0, h > 0, sw > 0, sh > 0 else { return }
  CATransaction.begin(); CATransaction.setDisableActions(true)
  backgroundVideo.frame = bounds; backgroundVideo.isHidden = !options.fit || !options.blur
  if let filter = CIFilter(name:"CIGaussianBlur") { filter.setValue(22,forKey:kCIInputRadiusKey); backgroundVideo.filters = [filter] }
  if options.fit { let scale = min(w/sw,h/sh); video.frame = CGRect(x:(w-sw*scale)/2,y:(h-sh*scale)/2,width:sw*scale,height:sh*scale) }
  else {
   let geometry = VideoGeometry(source:sourceSize,options:options)
   let cw = geometry.cropWidth, ch = geometry.cropHeight
   let scale = w/CGFloat(cw)
   // NSView layer coordinates are bottom-left; source crop coordinates start at top-left.
   let left = (sw-CGFloat(cw))*options.x; let top = (sh-CGFloat(ch))*options.y
   video.frame = CGRect(x:-left*scale,y:-(sh-CGFloat(ch)-top)*scale,width:sw*scale,height:sh*scale)
  }
  CATransaction.commit()
 }
}
struct VideoCanvas: NSViewRepresentable {
 var player: AVPlayer?; var options: Options; var sourceSize: CGSize
 func makeNSView(context:Context) -> CanvasView { CanvasView(frame:.zero) }
 func updateNSView(_ view:CanvasView,context:Context) { view.video.player = player; view.backgroundVideo.player = player; view.options = options; view.sourceSize = sourceSize; view.needsLayout = true }
}
