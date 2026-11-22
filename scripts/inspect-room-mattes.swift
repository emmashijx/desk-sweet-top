import Foundation
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers

let root=URL(fileURLWithPath:FileManager.default.currentDirectoryPath)
let art=root.appendingPathComponent("assets/design/v3")
func load(_ file:String)->CGImage {
    CGImageSourceCreateImageAtIndex(CGImageSourceCreateWithURL(art.appendingPathComponent(file) as CFURL,nil)!,0,nil)!
}
let sources=[load("layers-v3-22/composited-preview.png"),load("layers-v3-22-refined/composited-preview.png"),load("layers-v3-22/master-preview.png")]
let output=root.appendingPathComponent("output/local-test/matte-review")
try FileManager.default.createDirectory(at:output,withIntermediateDirectories:true)
let regions:[(String,CGRect)]=[("flowers",CGRect(x:421,y:474,width:149,height:190)),("clocks",CGRect(x:1001,y:117,width:238,height:181)),("lamp-and-utensils",CGRect(x:984,y:340,width:290,height:310)),("lamp-stem-base",CGRect(x:1150,y:630,width:131,height:231)),("desk-legs",CGRect(x:452,y:703,width:463,height:171)),("monitor-base",CGRect(x:561,y:591,width:283,height:66)),("bookcase-trim",CGRect(x:13,y:766,width:375,height:88)),("window-trim",CGRect(x:390,y:44,width:579,height:164)),("rug",CGRect(x:216,y:866,width:1016,height:132))]
for (name,rect) in regions {
    let scale=rect.width>400 ? 1 : 2
    let width=Int(rect.width)*scale,height=Int(rect.height)*scale
    let ctx=CGContext(data:nil,width:3*width,height:height,bitsPerComponent:8,bytesPerRow:3*width*4,space:CGColorSpace(name:CGColorSpace.sRGB)!,bitmapInfo:CGImageAlphaInfo.premultipliedLast.rawValue)!
    ctx.interpolationQuality = .none
    for (i,img) in sources.enumerated() {ctx.draw(img.cropping(to:rect)!,in:CGRect(x:i*width,y:0,width:width,height:height))}
    let dst=CGImageDestinationCreateWithURL(output.appendingPathComponent("\(name).png") as CFURL,UTType.png.identifier as CFString,1,nil)!
    CGImageDestinationAddImage(dst,ctx.makeImage()!,nil);CGImageDestinationFinalize(dst)
}
