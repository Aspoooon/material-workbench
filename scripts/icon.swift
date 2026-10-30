import AppKit
import CoreGraphics
let directory = CommandLine.arguments[1]
try FileManager.default.createDirectory(atPath:directory,withIntermediateDirectories:true)
for size in [16,32,64,128,256,512,1024] {
 let image = NSImage(size:NSSize(width:size,height:size))
 image.lockFocus()
 let s = CGFloat(size)
 NSColor(calibratedRed:0.14,green:0.19,blue:0.22,alpha:1).setFill()
 NSBezierPath(roundedRect:NSRect(x:s*0.04,y:s*0.04,width:s*0.92,height:s*0.92),xRadius:s*0.22,yRadius:s*0.22).fill()
 NSColor(calibratedRed:0.96,green:0.66,blue:0.30,alpha:1).setFill()
 let back = NSBezierPath(roundedRect:NSRect(x:s*0.22,y:s*0.31,width:s*0.51,height:s*0.46),xRadius:s*0.07,yRadius:s*0.07); back.fill()
 NSColor(calibratedRed:0.95,green:0.94,blue:0.88,alpha:1).setFill()
 NSBezierPath(roundedRect:NSRect(x:s*0.31,y:s*0.23,width:s*0.47,height:s*0.39),xRadius:s*0.06,yRadius:s*0.06).fill()
 NSColor(calibratedRed:0.14,green:0.19,blue:0.22,alpha:1).setFill()
 let play = NSBezierPath(); play.move(to:NSPoint(x:s*0.48,y:s*0.32));play.line(to:NSPoint(x:s*0.48,y:s*0.53));play.line(to:NSPoint(x:s*0.64,y:s*0.425));play.close();play.fill()
 image.unlockFocus()
 let rep = NSBitmapImageRep(data:image.tiffRepresentation!)!
 let data = rep.representation(using:.png,properties:[:])!
 try data.write(to:URL(fileURLWithPath:directory).appendingPathComponent("size\(size).png"))
}
