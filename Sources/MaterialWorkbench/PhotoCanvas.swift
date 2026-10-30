import SwiftUI
struct PhotoCanvas: View {
 var image: NSImage; var module: Module; var options: Options
 var body: some View {
  GeometryReader { g in
   let source = image.size.width/max(1,image.size.height)
   let ratio: Double = module == .pdf ? (options.paper == "图片尺寸" ? source : options.paper == "Letter" ? 612.0/792 : 595.28/841.89) : (options.aspect ?? source)
   let w = min(g.size.width,g.size.height*ratio); let h = w/ratio
   ZStack {
    (options.background == "黑色" && module != .pdf ? Color.black : .white)
    Image(nsImage:image).resizable().aspectRatio(contentMode:module == .pdf && options.pdfFit ? .fit : .fill).frame(width:w,height:h).clipped()
   }.frame(width:w,height:h).shadow(color:.black.opacity(0.12),radius:8,y:3).position(x:g.size.width/2,y:g.size.height/2)
  }
 }
}
