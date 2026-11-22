import Foundation
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers

// Export the repaired master as an editable stack. The RGB artwork is sampled
// from the master, not repainted. ImageGen clean plates supply hidden pixels.
let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
let gradientVersion = CommandLine.arguments.contains("--gradient-v3-22")
let version = gradientVersion ? "3-22" : "3-21"
let out = root.appendingPathComponent("assets/design/v3/layers-v\(version)")
let originalSources = root.appendingPathComponent("assets/design/v3/layers-v3-21")
let masterURL = root.appendingPathComponent("assets/design/v3/room-day-v3-21.png")
let w = 1557, h = 1010, n = w*h
typealias Mask = [UInt8]

struct Raster {
    var bytes: [UInt8]
    init(_ url: URL) {
        guard let src = CGImageSourceCreateWithURL(url as CFURL, nil),
              let image = CGImageSourceCreateImageAtIndex(src, 0, nil) else {
            fatalError("Cannot read \(url.path)")
        }
        bytes = [UInt8](repeating: 0, count: n*4)
        bytes.withUnsafeMutableBytes { ptr in
            let cs = CGColorSpace(name: CGColorSpace.sRGB)!
            let ctx = CGContext(data: ptr.baseAddress, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w*4,
                space: cs, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue)!
            ctx.interpolationQuality = .high
            ctx.draw(image, in: CGRect(x: 0, y: 0, width: w, height: h))
        }
    }
    init(_ bytes: [UInt8]) { self.bytes = bytes }
}

func path(_ build: (CGMutablePath) -> Void) -> CGPath {
    let p = CGMutablePath(); build(p); return p
}
func pt(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x:x, y:y) }
func poly(_ pairs: [(CGFloat,CGFloat)]) -> CGPath {
    path { p in p.move(to:pt(pairs[0].0,pairs[0].1)); for (x,y) in pairs.dropFirst() { p.addLine(to:pt(x,y)) }; p.closeSubpath() }
}
func rect(_ x: CGFloat,_ y: CGFloat,_ width: CGFloat,_ height: CGFloat, radius: CGFloat = 0) -> CGPath {
    let r = CGRect(x:x,y:y,width:width,height:height)
    return radius == 0 ? CGPath(rect:r,transform:nil) : CGPath(roundedRect:r,cornerWidth:radius,cornerHeight:radius,transform:nil)
}
func oval(_ x: CGFloat,_ y: CGFloat,_ width: CGFloat,_ height: CGFloat) -> CGPath {
    CGPath(ellipseIn:CGRect(x:x,y:y,width:width,height:height),transform:nil)
}
func mask(_ paths: [CGPath]) -> Mask {
    var b = Mask(repeating:0,count:n)
    b.withUnsafeMutableBytes { ptr in
        let ctx = CGContext(data:ptr.baseAddress,width:w,height:h,bitsPerComponent:8,bytesPerRow:w,
            space:CGColorSpaceCreateDeviceGray(),bitmapInfo:CGImageAlphaInfo.none.rawValue)!
        ctx.translateBy(x:0,y:CGFloat(h)); ctx.scaleBy(x:1,y:-1)
        ctx.setFillColor(gray:1,alpha:1); ctx.setShouldAntialias(true)
        for p in paths { ctx.addPath(p); ctx.fillPath() }
    }
    // Keep mastered edge pixels wholly intact for pixel-consistent recomposition.
    // Subpixel shape coverage is already present in the source illustration.
    return b.map { $0 >= 90 ? 255 : 0 }
}
func union(_ masks: [Mask]) -> Mask {
    var out = Mask(repeating:0,count:n)
    for m in masks { for i in 0..<n where m[i] > 0 { out[i] = 255 } }
    return out
}
func minus(_ a: Mask,_ b: Mask) -> Mask {
    var r = a; for i in 0..<n where b[i] > 0 { r[i] = 0 }; return r
}
func intersect(_ a: Mask,_ b: Mask) -> Mask {
    var r = a; for i in 0..<n where b[i] == 0 { r[i] = 0 }; return r
}
func patched(_ base: Raster, _ under: Raster, at m: Mask) -> Raster {
    var result=base.bytes
    for i in 0..<n where m[i]>0 {
        let k=i*4
        result[k]=under.bytes[k]; result[k+1]=under.bytes[k+1]; result[k+2]=under.bytes[k+2]
    }
    return Raster(result)
}
let master=Raster(masterURL)
let clean=Raster(originalSources.appendingPathComponent("source-clean-background.png"))
let support=Raster(originalSources.appendingPathComponent("source-clean-desk-map.png"))
let emptyShelf=Raster(originalSources.appendingPathComponent("source-empty-bookcase.png"))

// Object silhouettes traced against the final 1557 x 1010 master.
let bookshelf = mask([path { p in
    p.move(to:pt(20,148)); p.addCurve(to:pt(199,99),control1:pt(102,159),control2:pt(128,98))
    p.addCurve(to:pt(381,148),control1:pt(273,98),control2:pt(304,158))
    p.addQuadCurve(to:pt(381,159),control:pt(386,150)); p.addLine(to:pt(375,165)); p.addLine(to:pt(375,778))
    p.addQuadCurve(to:pt(380,798),control:pt(384,782)); p.addLine(to:pt(375,814)); p.addQuadCurve(to:pt(379,843),control:pt(383,833))
    p.addLine(to:pt(350,844)); p.addQuadCurve(to:pt(335,825),control:pt(349,829))
    p.addCurve(to:pt(262,819),control1:pt(311,813),control2:pt(286,816))
    p.addQuadCurve(to:pt(202,834),control:pt(225,834)); p.addQuadCurve(to:pt(144,822),control:pt(178,834))
    p.addCurve(to:pt(65,826),control1:pt(109,809),control2:pt(85,817))
    p.addQuadCurve(to:pt(55,844),control:pt(58,832)); p.addLine(to:pt(30,844))
    p.addQuadCurve(to:pt(29,829),control:pt(25,839)); p.addLine(to:pt(32,799)); p.addQuadCurve(to:pt(27,781),control:pt(21,790))
    p.addLine(to:pt(29,164)); p.addLine(to:pt(20,158)); p.closeSubpath()
}])

// Four book groups, separate from the oak-backed empty furniture carcass.
let book1=mask([poly([(50,207),(82,207),(82,198),(111,198),(111,208),(138,208),(138,217),(160,217),(160,205),(210,205),(210,304),(50,304)]),
    poly([(229,279),(232,259),(244,259),(244,237),(331,237),(331,259),(340,259),(340,280),(348,280),(348,304),(229,304)])])
let book2=mask([poly([(49,348),(81,348),(81,337),(105,337),(105,353),(121,353),(121,356),(143,356),(143,345),(173,345),(173,356),(203,356),(203,359),(224,359),(224,458),(49,458)]),
    poly([(234,430),(240,430),(240,407),(254,407),(254,385),(336,385),(336,407),(344,407),(344,431),(350,431),(350,458),(234,458)])])
let book3=mask([poly([(49,493),(79,493),(79,505),(106,505),(106,510),(126,510),(126,497),(153,497),(153,503),(178,503),(178,492),(203,492),(203,505),(227,505),(227,609),(49,609)]),
    poly([(241,577),(249,577),(249,550),(345,550),(345,578),(350,578),(350,609),(241,609)])])
let book4=mask([poly([(49,650),(80,650),(80,658),(97,658),(97,651),(119,651),(119,645),(145,645),(145,652),(166,652),(166,661),(187,661),(187,642),(213,642),(213,655),(235,655),(235,650),(261,650),(261,773),(49,773)]),
    poly([(266,722),(276,722),(276,700),(347,700),(347,721),(351,721),(351,744),(355,744),(355,773),(266,773)])])
let allBooks = intersect(union([book1,book2,book3,book4]),bookshelf)

let windowOuter=mask([path { p in
    p.move(to:pt(391,403)); p.addLine(to:pt(391,246))
    p.addCurve(to:pt(406,191),control1:pt(391,218),control2:pt(394,204))
    p.addLine(to:pt(396,181)); p.addLine(to:pt(398,170)); p.addQuadCurve(to:pt(420,159),control:pt(403,159))
    p.addCurve(to:pt(662,76),control1:pt(468,108),control2:pt(567,80))
    p.addLine(to:pt(656,72)); p.addQuadCurve(to:pt(670,62),control:pt(658,63)); p.addQuadCurve(to:pt(680,58),control:pt(676,53))
    p.addQuadCurve(to:pt(691,64),control:pt(686,57)); p.addQuadCurve(to:pt(705,77),control:pt(701,63))
    p.addCurve(to:pt(939,158),control1:pt(806,80),control2:pt(890,106))
    p.addQuadCurve(to:pt(962,174),control:pt(964,157)); p.addLine(to:pt(951,191))
    p.addCurve(to:pt(968,252),control1:pt(961,207),control2:pt(968,222)); p.addLine(to:pt(968,403))
    p.addQuadCurve(to:pt(959,408),control:pt(966,408)); p.addLine(to:pt(398,408)); p.addQuadCurve(to:pt(391,403),control:pt(391,407)); p.closeSubpath()
}])
let panes=mask([
    path { p in p.move(to:pt(418,205)); p.addCurve(to:pt(499,153),control1:pt(436,175),control2:pt(470,151)); p.addCurve(to:pt(545,205),control1:pt(528,148),control2:pt(544,180)); p.closeSubpath() },
    path { p in p.move(to:pt(561,205)); p.addCurve(to:pt(682,110),control1:pt(560,142),control2:pt(610,107)); p.addCurve(to:pt(803,205),control1:pt(754,108),control2:pt(803,143)); p.closeSubpath() },
    path { p in p.move(to:pt(819,205)); p.addCurve(to:pt(860,152),control1:pt(820,172),control2:pt(836,151)); p.addCurve(to:pt(943,205),control1:pt(895,151),control2:pt(928,180)); p.closeSubpath() },
    rect(418,215,128,174,radius:7), rect(561,215,243,174), rect(819,215,123,174,radius:7)
])
let glass = intersect(windowOuter,panes)

let doorOuter=mask([path { p in
    p.move(to:pt(1257,452)); p.addLine(to:pt(1257,275))
    p.addCurve(to:pt(1378,117),control1:pt(1257,186),control2:pt(1310,134))
    p.addQuadCurve(to:pt(1396,101),control:pt(1380,105)); p.addQuadCurve(to:pt(1413,117),control:pt(1407,103))
    p.addCurve(to:pt(1540,275),control1:pt(1491,131),control2:pt(1539,186))
    p.addLine(to:pt(1540,449)); p.addLine(to:pt(1528,459)); p.addLine(to:pt(1528,834)); p.addLine(to:pt(1272,834))
    p.addLine(to:pt(1272,459)); p.addLine(to:pt(1257,459)); p.closeSubpath()
}])
let doorPanel=intersect(mask([path { p in
    p.move(to:pt(1288,828)); p.addLine(to:pt(1288,268)); p.addCurve(to:pt(1398,149),control1:pt(1288,201),control2:pt(1331,149))
    p.addCurve(to:pt(1511,268),control1:pt(1465,149),control2:pt(1511,201)); p.addLine(to:pt(1511,828)); p.closeSubpath()
},rect(1283,532,7,24,radius:2),rect(1502,247,12,44,radius:3),rect(1502,715,12,43,radius:3)]), doorOuter)

let windowFrame = minus(windowOuter,glass)
let doorSurround = minus(doorOuter,doorPanel)
// Sample the connected edited trim area from the ImageGen gradient reference.
// Preserve the original per-layer alpha and every other object layer; include
// grout and highlights together to avoid speckled seams on pale glazed tiles.
var gradientMaster=master
var ceramicMask=Mask(repeating:0,count:n)
if gradientVersion {
    let edited=Raster(out.appendingPathComponent("source-gradient.png"))
    let eligible=union([windowFrame,doorSurround])
    for i in 0..<n where eligible[i]>0 {
        let y=i/w, x=i%w
        if (x<970 && y>392) || (x>1250 && y>447) {continue}
        ceramicMask[i]=255
    }
    gradientMaster=patched(master,edited,at:ceramicMask)
    print("Ceramic pixels changed: \(ceramicMask.filter{$0>0}.count)")
}

let desk=mask([poly([(456,654),(483,630),(885,630),(912,654),(912,670),(456,670)]),
    rect(467,666,436,56,radius:3),
    poly([(488,716),(515,716),(492,858),(476,863),(473,856)]),
    poly([(518,716),(539,716),(529,837),(513,837)]),
    poly([(838,716),(858,716),(865,837),(845,837)]),
    poly([(858,716),(884,716),(901,858),(894,863),(882,859)])])
let monitor=mask([rect(568,425,270,186,radius:12),path { p in
    p.move(to:pt(676,609));p.addLine(to:pt(724,609));p.addQuadCurve(to:pt(728,629),control:pt(724,622))
    p.addQuadCurve(to:pt(747,640),control:pt(734,637));p.addQuadCurve(to:pt(748,648),control:pt(751,644))
    p.addLine(to:pt(652,648));p.addQuadCurve(to:pt(651,641),control:pt(648,645));p.addQuadCurve(to:pt(672,629),control:pt(665,636))
    p.addQuadCurve(to:pt(676,609),control:pt(676,620));p.closeSubpath()
}])
let screen=intersect(mask([rect(574,430,258,165,radius:6)]),monitor)

// Blossom silhouette including handle, stems and extended leaves.
let flower=mask([path { p in
    p.move(to:pt(435,576));p.addQuadCurve(to:pt(447,552),control:pt(434,562));p.addLine(to:pt(442,544))
    p.addQuadCurve(to:pt(448,528),control:pt(443,533));p.addQuadCurve(to:pt(457,516),control:pt(452,517))
    p.addLine(to:pt(467,518));p.addQuadCurve(to:pt(480,510),control:pt(472,509));p.addLine(to:pt(481,497))
    p.addQuadCurve(to:pt(496,488),control:pt(484,490));p.addQuadCurve(to:pt(509,506),control:pt(508,489));p.addLine(to:pt(504,518))
    p.addQuadCurve(to:pt(525,508),control:pt(514,507));p.addQuadCurve(to:pt(546,510),control:pt(534,503))
    p.addQuadCurve(to:pt(551,529),control:pt(551,516));p.addLine(to:pt(547,539));p.addLine(to:pt(558,548))
    p.addLine(to:pt(557,556));p.addLine(to:pt(545,558));p.addLine(to:pt(551,573));p.addLine(to:pt(559,578))
    p.addQuadCurve(to:pt(544,578),control:pt(551,581));p.addLine(to:pt(530,574))
    p.addQuadCurve(to:pt(547,590),control:pt(545,578));p.addQuadCurve(to:pt(533,614),control:pt(551,603))
    p.addQuadCurve(to:pt(531,640),control:pt(543,630));p.addQuadCurve(to:pt(480,647),control:pt(520,652))
    p.addQuadCurve(to:pt(480,606),control:pt(469,634));p.addLine(to:pt(484,583));p.addLine(to:pt(480,579))
    p.addLine(to:pt(462,584));p.addLine(to:pt(463,575));p.addLine(to:pt(446,575));p.addLine(to:pt(436,578));p.closeSubpath()
}])
let clockL=mask([oval(1011,130,112,113),rect(1020,251,95,34,radius:6)])
let clockR=mask([oval(1126,130,112,113),rect(1134,251,93,34,radius:6)])
let mapMask=mask([rect(974,305,212,161,radius:2)])
let plateMask=mask([oval(1016,493,130,131)])
let plateCenter=intersect(mask([oval(1035,512,92,93)]),plateMask)
let knifeMask=mask([path { p in
    p.move(to:pt(1006,492));p.addQuadCurve(to:pt(1013,502),control:pt(1013,491));p.addLine(to:pt(1011,556))
    p.addLine(to:pt(1008,568));p.addLine(to:pt(1011,605));p.addQuadCurve(to:pt(1008,625),control:pt(1017,620))
    p.addQuadCurve(to:pt(997,616),control:pt(998,626));p.addLine(to:pt(1000,570));p.addLine(to:pt(997,557))
    p.addLine(to:pt(998,516));p.addQuadCurve(to:pt(1006,492),control:pt(998,501));p.closeSubpath()
}])
let forkMask=mask([path { p in
    p.move(to:pt(1149,496));p.addLine(to:pt(1153,496));p.addLine(to:pt(1153,526));p.addLine(to:pt(1155,526))
    p.addLine(to:pt(1156,496));p.addLine(to:pt(1159,496));p.addLine(to:pt(1159,526));p.addLine(to:pt(1162,526))
    p.addLine(to:pt(1162,496));p.addLine(to:pt(1165,496));p.addLine(to:pt(1165,526));p.addLine(to:pt(1168,526))
    p.addLine(to:pt(1168,496));p.addLine(to:pt(1171,496));p.addLine(to:pt(1171,531))
    p.addQuadCurve(to:pt(1162,551),control:pt(1169,542));p.addLine(to:pt(1161,570));p.addLine(to:pt(1166,607))
    p.addQuadCurve(to:pt(1161,625),control:pt(1173,618));p.addQuadCurve(to:pt(1149,615),control:pt(1151,626))
    p.addLine(to:pt(1154,571));p.addLine(to:pt(1153,551));p.addQuadCurve(to:pt(1149,533),control:pt(1148,543));p.closeSubpath()
}])
let shade=path { p in
    p.move(to:pt(1198,395));p.addQuadCurve(to:pt(1213,402),control:pt(1210,394));p.addQuadCurve(to:pt(1219,422),control:pt(1216,411))
    p.addQuadCurve(to:pt(1233,448),control:pt(1224,440));p.addQuadCurve(to:pt(1224,457),control:pt(1234,457))
    p.addQuadCurve(to:pt(1215,453),control:pt(1218,459));p.addQuadCurve(to:pt(1204,458),control:pt(1210,460))
    p.addQuadCurve(to:pt(1192,452),control:pt(1197,457));p.addQuadCurve(to:pt(1182,455),control:pt(1185,458))
    p.addQuadCurve(to:pt(1176,445),control:pt(1176,452));p.addQuadCurve(to:pt(1167,451),control:pt(1168,453))
    p.addQuadCurve(to:pt(1158,444),control:pt(1159,451));p.addQuadCurve(to:pt(1146,443),control:pt(1147,451))
    p.addQuadCurve(to:pt(1163,418),control:pt(1156,436));p.addQuadCurve(to:pt(1180,403),control:pt(1172,402))
    p.addLine(to:pt(1189,398));p.addLine(to:pt(1192,385));p.addLine(to:pt(1203,385));p.addLine(to:pt(1207,398));p.closeSubpath()
}
let stem=path { p in
    p.move(to:pt(1206,808));p.addLine(to:pt(1206,575));p.addCurve(to:pt(1243,468),control1:pt(1206,532),control2:pt(1226,502))
    p.addCurve(to:pt(1261,393),control1:pt(1254,445),control2:pt(1264,418))
    p.addCurve(to:pt(1227,357),control1:pt(1259,369),control2:pt(1242,351));p.addCurve(to:pt(1197,392),control1:pt(1211,358),control2:pt(1204,377))
}
let lamp=mask([shade,stem.copy(strokingWithWidth:8,lineCap:.round,lineJoin:.round,miterLimit:2),path { p in
    p.move(to:pt(1201,797));p.addLine(to:pt(1211,797));p.addQuadCurve(to:pt(1227,818),control:pt(1210,809))
    p.addQuadCurve(to:pt(1250,830),control:pt(1237,821));p.addQuadCurve(to:pt(1244,844),control:pt(1256,838))
    p.addQuadCurve(to:pt(1171,844),control:pt(1208,857));p.addQuadCurve(to:pt(1163,833),control:pt(1160,842))
    p.addQuadCurve(to:pt(1189,818),control:pt(1171,823));p.addQuadCurve(to:pt(1201,797),control:pt(1202,810));p.closeSubpath()
}])
let bin=mask([path { p in
    p.move(to:pt(992,712));p.addCurve(to:pt(1051,699),control1:pt(992,703),control2:pt(1022,698))
    p.addCurve(to:pt(1111,712),control1:pt(1080,698),control2:pt(1111,704));p.addLine(to:pt(1105,839))
    p.addQuadCurve(to:pt(1099,851),control:pt(1106,848));p.addQuadCurve(to:pt(1005,851),control:pt(1053,861))
    p.addQuadCurve(to:pt(997,840),control:pt(995,847));p.closeSubpath()
}])
let rug=mask([path { p in
    p.move(to:pt(294,882));p.addLine(to:pt(1138,882));p.addQuadCurve(to:pt(1156,890),control:pt(1150,882))
    p.addLine(to:pt(1217,973));p.addQuadCurve(to:pt(1209,987),control:pt(1224,984))
    p.addLine(to:pt(239,987));p.addQuadCurve(to:pt(226,975),control:pt(221,987))
    p.addLine(to:pt(281,891));p.addQuadCurve(to:pt(294,882),control:pt(287,881));p.closeSubpath()
}])

struct Layer {
    let name: String
    let source: Raster
    let matte: Mask
    var bounds:(Int,Int,Int,Int) {
        var x0=w,y0=h,x1=0,y1=0
        for y in 0..<h { for x in 0..<w where matte[y*w+x] != 0 {
            x0=min(x0,x);x1=max(x1,x+1);y0=min(y0,y);y1=max(y1,y+1)
        }}
        return (x0,y0,x1,y1)
    }
}

// Use clean source surfaces in their entirety so hiding/moving a layer does
// not reveal silhouette-shaped seams, baked shadows or remnants of a book.
// The cut-out foreground artwork is still sampled from the locked master.
let base=clean
let bookshelfClean=emptyShelf
let deskClean=support
let mapClean=support
// A restrained, independently editable contact-shadow layer follows the
// traced foreground silhouettes. This avoids baking wallpaper/wood into the
// shadows and leaves the reconstructed background completely clean.
let fg=union([bookshelf,windowOuter,doorOuter,desk,monitor,flower,clockL,clockR,mapMask,plateMask,knifeMask,forkMask,lamp,bin,rug])
var distance=[Int16](repeating:1000,count:n)
for i in 0..<n where fg[i]>0 {distance[i]=0}
for y in 0..<h {for x in 0..<w {
    let i=y*w+x
    if x>0 {distance[i]=min(distance[i],distance[i-1]+1)}
    if y>0 {distance[i]=min(distance[i],distance[i-w]+1)}
}}
for y in (0..<h).reversed() {for x in (0..<w).reversed() {
    let i=y*w+x
    if x+1<w {distance[i]=min(distance[i],distance[i+1]+1)}
    if y+1<h {distance[i]=min(distance[i],distance[i+w]+1)}
}}
var shadowMask=Mask(repeating:0,count:n)
var shadowRGB=[UInt8](repeating:0,count:n*4)
for y in 4..<h { for x in 2..<w {
    let i=y*w+x, k=i*4
    guard fg[i]==0 else {continue}
    let d=Double(distance[(y-4)*w+x-2])
    guard d<13 else {continue}
    let alpha=0.17*exp(-(d*d)/35)
    shadowMask[i]=UInt8(max(0,min(255,Int(alpha*255))))
    shadowRGB[k]=38;shadowRGB[k+1]=28;shadowRGB[k+2]=22;shadowRGB[k+3]=255
}}
let layers:[Layer] = [
    Layer(name:"01 Wallpaper",source:base,matte:mask([rect(0,0,CGFloat(w),580)])),
    Layer(name:"02 Oak wainscot and trim",source:base,matte:mask([rect(0,580,CGFloat(w),249)])),
    Layer(name:"03 Parquet floor",source:base,matte:mask([rect(0,829,CGFloat(w),181)])),
    Layer(name:"03a Soft contact shadows",source:Raster(shadowRGB),matte:shadowMask),
    Layer(name:"04 Bookshelf",source:bookshelfClean,matte:bookshelf),
    Layer(name:"05 Books shelf 1",source:master,matte:intersect(book1,bookshelf)),
    Layer(name:"06 Books shelf 2",source:master,matte:intersect(book2,bookshelf)),
    Layer(name:"07 Books shelf 3",source:master,matte:intersect(book3,bookshelf)),
    Layer(name:"08 Books shelf 4",source:master,matte:intersect(book4,bookshelf)),
    Layer(name:"09 Window scenery",source:master,matte:glass),
    Layer(name:"10 Window frame and mosaic",source:gradientMaster,matte:windowFrame),
    Layer(name:"11 Door panel",source:master,matte:doorPanel),
    Layer(name:"12 Door surround",source:gradientMaster,matte:doorSurround),
    Layer(name:"13 Oak desk",source:deskClean,matte:desk),
    Layer(name:"14 Monitor body",source:master,matte:minus(monitor,screen)),
    Layer(name:"15 Monitor screen",source:master,matte:screen),
    Layer(name:"16 Seasonal flowers",source:master,matte:flower),
    Layer(name:"17 Clock left and label",source:master,matte:clockL),
    Layer(name:"18 Clock right and label",source:master,matte:clockR),
    Layer(name:"19 Travel map",source:mapClean,matte:mapMask),
    Layer(name:"20 Player knife",source:master,matte:knifeMask),
    Layer(name:"21 Player plate rim",source:master,matte:minus(plateMask,plateCenter)),
    Layer(name:"22 Plate idle center",source:master,matte:plateCenter),
    Layer(name:"23 Player fork",source:master,matte:forkMask),
    Layer(name:"24 Glass flower lamp",source:master,matte:lamp),
    Layer(name:"25 Enamel rubbish bin",source:master,matte:bin),
    Layer(name:"26 Woven rug",source:master,matte:rug)
]

func savePNG(_ rgba:[UInt8],_ url:URL) {
    let provider=CGDataProvider(data:Data(rgba) as CFData)!
    let img=CGImage(width:w,height:h,bitsPerComponent:8,bitsPerPixel:32,bytesPerRow:w*4,
        space:CGColorSpace(name:CGColorSpace.sRGB)!,bitmapInfo:CGBitmapInfo(rawValue:CGImageAlphaInfo.last.rawValue | CGBitmapInfo.byteOrder32Big.rawValue),
        provider:provider,decode:nil,shouldInterpolate:true,intent:.defaultIntent)!
    let dst=CGImageDestinationCreateWithURL(url as CFURL,UTType.png.identifier as CFString,1,nil)!
    CGImageDestinationAddImage(dst,img,nil); guard CGImageDestinationFinalize(dst) else { fatalError("PNG export failed") }
}
let pngDir=out.appendingPathComponent("png-layers")
try FileManager.default.createDirectory(at:pngDir,withIntermediateDirectories:true)
var composite=[UInt8](repeating:0,count:n*4)
for l in layers {
    var rgba=[UInt8](repeating:0,count:n*4)
    for i in 0..<n where l.matte[i]>0 {
        let k=i*4
        let a=Int(l.matte[i])
        rgba[k]=l.source.bytes[k];rgba[k+1]=l.source.bytes[k+1];rgba[k+2]=l.source.bytes[k+2];rgba[k+3]=UInt8(a)
        for c in 0..<3 { composite[k+c]=UInt8((Int(rgba[k+c])*a+Int(composite[k+c])*(255-a)+127)/255) }
        composite[k+3]=255
    }
    let name=l.name.lowercased().replacingOccurrences(of:" ",with:"-")+".png"
    savePNG(rgba,pngDir.appendingPathComponent(name))
}
savePNG(composite,out.appendingPathComponent("composited-preview.png"))
if gradientVersion {
    savePNG(gradientMaster.bytes,out.appendingPathComponent("master-preview.png"))
}
let diffCount=(0..<n).reduce(0) { total,i in
    let k=i*4; return total+(composite[k] != master.bytes[k] || composite[k+1] != master.bytes[k+1] || composite[k+2] != master.bytes[k+2] ? 1:0)
}

// PSD v1, 8-bit RGB, uncompressed layer channels. Layer records use true
// bounding rectangles; exported transparent PNGs retain full-canvas alignment.
extension Data {
    mutating func u16(_ n: Int) { let v=UInt16(truncatingIfNeeded:n).bigEndian; Swift.withUnsafeBytes(of:v){ append(contentsOf:$0) } }
    mutating func u32(_ n: Int) { let v=UInt32(truncatingIfNeeded:n).bigEndian; Swift.withUnsafeBytes(of:v){ append(contentsOf:$0) } }
    mutating func ascii(_ s:String) { append(contentsOf:s.utf8) }
}
var records=Data(), channelData=Data()
records.u16(layers.count)
var manifest:[[String:Any]]=[]
for l in layers.reversed() {
    let (x0,y0,x1,y1)=l.bounds, lw=x1-x0, lh=y1-y0, len=lw*lh
    precondition(len>0,"Empty layer: \(l.name)")
    records.u32(y0);records.u32(x0);records.u32(y1);records.u32(x1)
    records.u16(4)
    for id in [0,1,2,-1] { records.u16(id);records.u32(len+2) }
    records.ascii("8BIM");records.ascii("norm");records.append(contentsOf:[255,0,0,0])
    var extra=Data();extra.u32(0);extra.u32(0)
    let nameBytes=Array(l.name.utf8.prefix(255));var ps=Data([UInt8(nameBytes.count)]);ps.append(contentsOf:nameBytes)
    while ps.count%4 != 0 {ps.append(0)}
    extra.append(ps)
    records.u32(extra.count);records.append(extra)
    for c in 0..<4 {
        channelData.u16(0)
        var plane=[UInt8]();plane.reserveCapacity(len)
        for y in y0..<y1 { for x in x0..<x1 {
            let i=y*w+x
            plane.append(c==3 ? l.matte[i] : l.source.bytes[i*4+c])
        }}
        channelData.append(contentsOf:plane)
    }
    manifest.append(["name":l.name,"x":x0,"y":y0,"width":lw,"height":lh,
        "png":l.name.lowercased().replacingOccurrences(of:" ",with:"-")+".png"])
}
var layerInfo=records;layerInfo.append(channelData);if layerInfo.count%2 != 0 {layerInfo.append(0)}
var section=Data();section.u32(layerInfo.count);section.append(layerInfo);section.u32(0)
var psd=Data();psd.ascii("8BPS");psd.u16(1);psd.append(contentsOf:[0,0,0,0,0,0])
psd.u16(3);psd.u32(h);psd.u32(w);psd.u16(8);psd.u16(3)
psd.u32(0);psd.u32(0);psd.u32(section.count);psd.append(section)
psd.u16(0)
for c in 0..<3 { psd.append(contentsOf:(0..<n).map{composite[$0*4+c]}) }
try psd.write(to:out.appendingPathComponent("home-sweet-home-v\(version).psd"))
let json:[String:Any]=["canvasWidth":w,"canvasHeight":h,"layerOrder":"bottom-to-top",
    "layers":manifest.reversed() as [[String:Any]], "pixelDifferenceCount":diffCount]
try JSONSerialization.data(withJSONObject:json,options:[.prettyPrinted,.sortedKeys]).write(to:out.appendingPathComponent("layer-manifest.json"))
print("Exported \(layers.count) layers; master-composite differing pixels \(diffCount)/\(n)")
