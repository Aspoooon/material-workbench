import Foundation
import CoreGraphics
struct VideoGeometry {
 let width: Int; let height: Int; let cropWidth: Int; let cropHeight: Int
 init(source:CGSize,options o:Options) {
  let sw = Double(source.width), sh = Double(source.height)
  var w = sw, h = sh
  if let aspect = o.aspect { if w/h > aspect { w = h*aspect } else { h = w/aspect } }
  if let edge = Double(o.resolution), edge > 0 { let scale = edge/max(w,h); w *= scale; h *= scale }
  width = max(2,Int(w/2)*2); height = max(2,Int(h/2)*2)
  cropWidth = max(2,Int(min(sw,sh*Double(width)/Double(height))/o.zoom/2)*2)
  cropHeight = max(2,Int(Double(cropWidth)*Double(height)/Double(width)/2)*2)
 }
 var aspect: Double { Double(width)/Double(height) }
}
