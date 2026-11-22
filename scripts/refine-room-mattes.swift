import Foundation
import CoreGraphics
import ImageIO
import Vision
import CoreVideo
import UniformTypeIdentifiers

// Refine the existing editable mattes without repainting the approved artwork.
// Output is a new version; original PNGs and PSD are never changed.
let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
let design = root.appendingPathComponent("assets/design/v3")
let original = design.appendingPathComponent("layers-v3-22")
let clean = design.appendingPathComponent("layers-v3-21")
let output = design.appendingPathComponent("layers-v3-22-refined")
let pngDir = output.appendingPathComponent("png-layers")
try FileManager.default.createDirectory(at:pngDir,withIntermediateDirectories:true)
let w=1557,h=1010,n=w*h

struct Raster {
    let image:CGImage
    let bytes:[UInt8]
    init(_ url:URL) {
        let decoded=CGImageSourceCreateImageAtIndex(CGImageSourceCreateWithURL(url as CFURL,nil)!,0,nil)!
        precondition(decoded.width==w && decoded.height==h)
        var b=[UInt8](repeating:0,count:n*4)
        b.withUnsafeMutableBytes { p in
            let ctx=CGContext(data:p.baseAddress,width:w,height:h,bitsPerComponent:8,bytesPerRow:w*4,space:CGColorSpace(name:CGColorSpace.sRGB)!,bitmapInfo:CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue)!
            ctx.draw(decoded,in:CGRect(x:0,y:0,width:w,height:h))
        }
        image=decoded
        bytes=b
    }
    @inline(__always) func alpha(_ i:Int)->UInt8 {bytes[i*4+3]}
    @inline(__always) func rgb(_ i:Int)->SIMD3<Float> {
        let k=i*4;return SIMD3(Float(bytes[k]),Float(bytes[k+1]),Float(bytes[k+2]))
    }
}
struct Layer:Decodable {
    var name:String;var png:String;var x:Int;var y:Int;var width:Int;var height:Int
    var rect:CGRect {CGRect(x:x,y:y,width:width,height:height)}
}
struct Layout:Decodable {var layers:[Layer]}
let layout=try JSONDecoder().decode(Layout.self,from:Data(contentsOf:root.appendingPathComponent("app/layout.json")))
let old=layout.layers.map{Raster(original.appendingPathComponent("png-layers/"+$0.png))}
let master=Raster(original.appendingPathComponent("master-preview.png"))
let shelf=Raster(clean.appendingPathComponent("source-empty-bookcase.png"))
let support=Raster(clean.appendingPathComponent("source-clean-desk-map.png"))
let base=Raster(clean.appendingPathComponent("source-clean-background.png"))

func write(_ bytes:[UInt8],_ url:URL) {
    let image=CGImage(width:w,height:h,bitsPerComponent:8,bitsPerPixel:32,bytesPerRow:w*4,space:CGColorSpace(name:CGColorSpace.sRGB)!,bitmapInfo:CGBitmapInfo(rawValue:CGImageAlphaInfo.last.rawValue | CGBitmapInfo.byteOrder32Big.rawValue),provider:CGDataProvider(data:Data(bytes) as CFData)!,decode:nil,shouldInterpolate:true,intent:.defaultIntent)!
    let dst=CGImageDestinationCreateWithURL(url as CFURL,UTType.png.identifier as CFString,1,nil)!
    CGImageDestinationAddImage(dst,image,nil);precondition(CGImageDestinationFinalize(dst))
}

struct Region {
    let x:Int,y:Int,width:Int,height:Int
    var count:Int {width*height}
    init(_ rect:CGRect) {
        let r=rect.integral.intersection(CGRect(x:0,y:0,width:w,height:h))
        x=Int(r.minX);y=Int(r.minY);width=Int(r.width);height=Int(r.height)
    }
    var rect:CGRect {CGRect(x:x,y:y,width:width,height:height)}
    @inline(__always) func index(_ p:Int)->Int {(y+p/width)*w+x+p%width}
    @inline(__always) func local(_ gx:Int,_ gy:Int)->Int? {
        guard gx>=x,gx<x+width,gy>=y,gy<y+height else{return nil}
        return (gy-y)*width+gx-x
    }
    // Eight-neighbour chamfer distance, with subpixel-equivalent diagonal costs.
    func distances(to target:[Bool])->[Float] {
        var d=target.map{$0 ? Float(0):Float(10000)}
        for yy in 0..<height {for xx in 0..<width {
            let p=yy*width+xx
            if xx>0 {d[p]=min(d[p],d[p-1]+1)}
            if yy>0 {d[p]=min(d[p],d[p-width]+1);if xx>0 {d[p]=min(d[p],d[p-width-1]+1.4142)};if xx+1<width {d[p]=min(d[p],d[p-width+1]+1.4142)}}
        }}
        for yy in (0..<height).reversed() {for xx in (0..<width).reversed() {
            let p=yy*width+xx
            if xx+1<width {d[p]=min(d[p],d[p+1]+1)}
            if yy+1<height {d[p]=min(d[p],d[p+width]+1);if xx>0 {d[p]=min(d[p],d[p+width-1]+1.4142)};if xx+1<width {d[p]=min(d[p],d[p+width+1]+1.4142)}}
        }}
        return d
    }
}

func visionMask(_ source:Raster,_ region:Region)->[Float]? {
    guard let crop=source.image.cropping(to:region.rect) else{return nil}
    let handler=VNImageRequestHandler(cgImage:crop,options:[:])
    let request=VNGenerateForegroundInstanceMaskRequest()
    do {
        try handler.perform([request])
        guard let observation=request.results?.first,!observation.allInstances.isEmpty else{return nil}
        let buffer=try observation.generateScaledMaskForImage(forInstances:observation.allInstances,from:handler)
        CVPixelBufferLockBaseAddress(buffer,.readOnly);defer{CVPixelBufferUnlockBaseAddress(buffer,.readOnly)}
        guard CVPixelBufferGetWidth(buffer)==region.width,CVPixelBufferGetHeight(buffer)==region.height,let address=CVPixelBufferGetBaseAddress(buffer) else{return nil}
        let p=address.assumingMemoryBound(to:Float32.self), stride=CVPixelBufferGetBytesPerRow(buffer)/4
        return (0..<region.count).map{max(0,min(1,p[($0/region.width)*stride+$0%region.width]))}
    } catch { print("Vision matte unavailable:",error.localizedDescription);return nil }
}

@inline(__always) func dot(_ a:SIMD3<Float>,_ b:SIMD3<Float>)->Float {a.x*b.x+a.y*b.y+a.z*b.z}
@inline(__always) func clamp(_ a:Float)->Float {max(0,min(1,a))}
@inline(__always) func byte(_ a:Float)->UInt8 {UInt8(max(0,min(255,a.rounded())))}
func luminance(_ c:SIMD3<Float>)->Float {c.x*0.2126+c.y*0.7152+c.z*0.0722}

// Follow the locked artwork where the old arch includes up to nine pixels
// of wallpaper, and where the shade mask overruns its slender glass lip.
func smoothContour(_ coordinates: [Int: Float]) -> [Int: Float] {
    coordinates.reduce(into: [:]) { result, sample in
        let (position, center) = sample
        var sum = center * 3
        var weight: Float = 3
        for offset in [-2, -1, 1, 2] {
            guard let neighbor = coordinates[position + offset], abs(neighbor - center) <= 3 else { continue }
            let contribution: Float = abs(offset) == 1 ? 2 : 1
            sum += neighbor * contribution
            weight += contribution
        }
        result[position] = sum / weight
    }
}

var archRows: [Int: Float] = [:]
for x in 409...957 {
    guard let traced = (56..<201).first(where: { old[10].alpha($0*w+x)>127 }) else { continue }
    func contrast(at y: Int) -> Float {
        let i = y*w+x
        let delta = master.rgb(i)-base.rgb(i)
        return dot(delta,delta)
    }
    if let edge = (max(56,traced-2)..<(traced+15)).first(where: { y in
        contrast(at:y)>625 && (y..<(y+5)).filter { contrast(at:$0)>361 }.count>=4
    }) {
        archRows[x] = Float(edge)
    }
}
let archContour = smoothContour(archRows)
var shadeColumns: [Int: Float] = [:]
for y in 405..<456 {
    func peachContrast(at x: Int) -> Float {
        let i = y*w+x
        return base.rgb(i).z-master.rgb(i).z
    }
    if let edge = (1203...1235).reversed().first(where: { x in
        peachContrast(at:x)>22 && ((x-3)...x).filter { peachContrast(at:$0)>18 }.count>=3
    }) {
        shadeColumns[y] = Float(edge)
    }
}
let shadeContour = smoothContour(shadeColumns)

func removeWallpaper(from color: SIMD3<Float>, using backdrop: SIMD3<Float>, opacity: Float) -> SIMD3<Float> {
    let recovered = (color-backdrop*(1-opacity))/max(0.2,opacity)
    let limit: Float = 35
    return SIMD3(max(color.x-limit,min(color.x+limit,recovered.x)),
                 max(color.y-limit,min(color.y+limit,recovered.y)),
                 max(color.z-limit,min(color.z+limit,recovered.z)))
}

// Each group owns an exterior silhouette. Inner component boundaries remain
// pixel-aligned (screen/bezel, glass/frame, panel/door frame, plate/rim).
struct Group {
    var name:String;var ids:[Int];var source:Raster;var useVision:Bool=true
    var protectDepth:Float=5;var expand:Float=1.45
}
let groups:[Group]=[
    Group(name:"bookshelf",ids:[4],source:shelf),
    Group(name:"books 1",ids:[5],source:master,protectDepth:4),
    Group(name:"books 2",ids:[6],source:master,protectDepth:4),
    Group(name:"books 3",ids:[7],source:master,protectDepth:4),
    Group(name:"books 4",ids:[8],source:master,protectDepth:4),
    Group(name:"window",ids:[10,9],source:master,useVision:false,protectDepth:3),
    Group(name:"door",ids:[12,11],source:master,protectDepth:4),
    Group(name:"desk",ids:[13],source:support,protectDepth:4),
    Group(name:"monitor",ids:[14,15],source:master,protectDepth:5),
    Group(name:"flowers",ids:[16],source:master,protectDepth:1000,expand:15),
    Group(name:"clock left",ids:[17],source:master,protectDepth:6),
    Group(name:"clock right",ids:[18],source:master,protectDepth:6),
    Group(name:"map",ids:[19],source:support,useVision:false,protectDepth:4),
    Group(name:"knife",ids:[20],source:master,protectDepth:4),
    Group(name:"plate",ids:[21,22],source:master,protectDepth:3),
    Group(name:"fork",ids:[23],source:master,useVision:false,protectDepth:3),
    Group(name:"lamp",ids:[24],source:master,useVision:false,protectDepth:5),
    Group(name:"bin",ids:[25],source:master,protectDepth:5),
    Group(name:"rug",ids:[26],source:master,protectDepth:5)
]

var finalLayers=[[UInt8]](repeating:[],count:27)
var fg=[Float](repeating:0,count:n)
var logs:[String]=[]

for g in groups {
    let bounds=g.ids.map{layout.layers[$0].rect}.reduce(CGRect.null){$0.union($1)}
    let r=Region(bounds.insetBy(dx:-14,dy:-14))
    let global=(0..<r.count).map{r.index($0)}
    let originalMask=global.map{i in g.ids.contains{old[$0].alpha(i)>127}}
    let oldIn=r.distances(to:originalMask.map{!$0}),oldOut=r.distances(to:originalMask)
    var model=g.useVision ? visionMask(g.source,r):nil
    // Vision handles the intricate blossom/handle and round objects well;
    // thin lamp stem and fork teeth must retain their traced topology.
    if g.name=="lamp" {
        model=originalMask.map{$0 ? 1:0}
        for (part,below,above) in [(Region(CGRect(x:1135,y:336,width:143,height:143)),0,464),(Region(CGRect(x:1148,y:782,width:122,height:90)),795,h)] {
            if let m=visionMask(g.source,part) {
                for p in 0..<r.count {
                    let i=global[p],x=i%w,y=i/w
                    if y>=below,y<above,let q=part.local(x,y) {model![p]=m[q]}
                }
            }
        }
    }
    var core=originalMask
    if let model {
        for p in 0..<r.count {
            let i=global[p],x=i%w,y=i/w
            let insideBounds=bounds.contains(CGPoint(x:CGFloat(x)+0.5,y:CGFloat(y)+0.5))
            core[p]=insideBounds && ((model[p]>=0.5 && oldOut[p]<=g.expand) || (originalMask[p] && oldIn[p]>=g.protectDepth))
            // Never fill the narrow traced holes between fork/lamp details.
            if g.name=="lamp" && y>=464 && y<795 {core[p]=originalMask[p]}
            if g.name=="lamp" && y>=464 && y<580 && oldOut[p]<=1.5 {
                let c=g.source.rgb(i);core[p]=(c.x-c.z>65 || c.y<154) && oldOut[p]<=1.5
            }
            // Desk legs blend into the oak behind them, so automatic object
            // detection is not authoritative for these hand-traced supports.
            if g.name=="desk" && y>=715 {core[p]=originalMask[p]}
            if g.name=="monitor" && y>=610 {core[p]=originalMask[p]}
            if g.name=="plate" {core[p]=originalMask[p] && (model[p]>0.12 || oldIn[p]>=2)}
        }
    }
    // The previous fork outline used the wrong tine spacing. The actual
    // locked source has four distinct gold tines against cream wallpaper.
    // Isolate by their red/blue chroma, not a polygon or simulated tine.
    if g.name=="fork" {
        for p in 0..<r.count {
            let i=global[p],x=i%w,y=i/w
            if y>=496 && y<531 && x>=1149 && x<=1167 {
                let c=g.source.rgb(i),cut:Float=y<506 ? 66:80
                core[p]=c.x-c.z>=cut
            } else if y<531 {core[p]=false}
        }
    }
    let insideCount=core.filter{$0}.count,oldCount=originalMask.filter{$0}.count
    if insideCount < oldCount/2 { print("Fallback to legacy contour for",g.name);core=originalMask;model=nil }
    let toFG=r.distances(to:core),toBG=r.distances(to:core.map{!$0})
    // Each final alpha is estimated in an edge-only trimap. The source's
    // colour gradient separates the actual object from its surrounding wall.
    // Interior RGB is copied exactly, not regenerated or blurred.
    var outputPixels:[Int:[UInt8]]=[:]
    for id in g.ids {outputPixels[id]=[UInt8](repeating:0,count:n*4)}
    var partial=0,removed=0,opaque=0
    for p in 0..<r.count {
        let i=global[p],x=i%w,y=i/w
        guard bounds.contains(CGPoint(x:CGFloat(x)+0.5,y:CGFloat(y)+0.5)),toFG[p]<2.1 else{continue}
        let px=p%r.width,py=p/r.width
        // The existing interior partition wins ownership. New edge pixels
        // belong to the outermost layer (first in each group).
        let owner=g.ids.first(where:{old[$0].alpha(i)>127}) ?? g.ids[0]
        guard layout.layers[owner].rect.contains(CGPoint(x:CGFloat(x)+0.5,y:CGFloat(y)+0.5)) else{continue}
        var color=g.source.rgb(i),alpha:Float=1
        if toBG[p]<2.5 {
            let c=color
            var bestF:Float=Float.greatestFiniteMagnitude,bestB:Float=Float.greatestFiniteMagnitude
            var f=c,b=c
            // Prefer nearby reliable inner/outer samples; source similarity
            // breaks ties without pulling an adjacent object's colour in.
            for dy in -6...6 {for dx in -6...6 {
                let xx=px+dx,yy=py+dy
                guard xx>=0,xx<r.width,yy>=0,yy<r.height else{continue}
                let q=yy*r.width+xx,spatial=Float(dx*dx+dy*dy)
                let sample=g.source.rgb(global[q]),diff=sample-c
                let score=spatial+dot(diff,diff)/10000
                if core[q] && toBG[q]>=1.8 && score<bestF {bestF=score;f=sample}
                if !core[q] && toFG[q]>=1.8 && score<bestB {bestB=score;b=sample}
            }}
            // Very thin metal details may have no two-pixel core. Use their
            // original centerline as foreground instead of eroding them away.
            if bestF == Float.greatestFiniteMagnitude {
                for dy in -3...3 {for dx in -3...3 {
                    let xx=px+dx,yy=py+dy
                    guard xx>=0,xx<r.width,yy>=0,yy<r.height else{continue}
                    let q=yy*r.width+xx
                    if core[q] {
                        let score=Float(dx*dx+dy*dy)-toBG[q]*2
                        if score<bestF{bestF=score;f=g.source.rgb(global[q])}
                    }
                }}
            }
            // Continuous subpixel coverage from the refined binary contour.
            // A weighted 3x3 neighbourhood softens stair-steps on diagonals
            // without applying blur to the object's artwork.
            var covered:Float=0,weights:Float=0
            for dy in -1...1 {for dx in -1...1 {
                let xx=px+dx,yy=py+dy
                if xx<0 || xx>=r.width || yy<0 || yy>=r.height {continue}
                let weight:Float=(dx==0 ? 2:1)*(dy==0 ? 2:1)
                weights+=weight;if core[yy*r.width+xx]{covered+=weight}
            }}
            var geometric=clamp((covered/max(weights,1)-0.06)/0.88)
            if core[p] && toBG[p]>=1.8 {geometric=1}
            if !core[p] {geometric=min(geometric,0.32)}
            let delta=f-b,den=dot(delta,delta)
            // Use a strong image-guided correction on organic silhouettes;
            // for structural and thin elements, trust connected geometry to
            // avoid holes when their wood/metal matches a background tone.
            let organic=(g.name=="flowers" && y<632) || g.name.hasPrefix("clock") || (g.name=="lamp" && y<464)
            alpha=geometric
            if bestF < Float.greatestFiniteMagnitude && bestB < Float.greatestFiniteMagnitude && den>350 {
                let projected=clamp(dot(c-b,delta)/den)
                let residual=c-(b+delta*projected)
                let unreliable=dot(residual,residual)>max(900,den*0.45)
                if !unreliable {
                    alpha=organic ? clamp(projected*0.55+geometric*0.45) : clamp(projected*0.18+geometric*0.82)
                }
                // Remove fully background-coloured fringe pixels rather than
                // leaving a pale semi-opaque ghost around the object.
                if organic && dot(c-b,c-b)<max(90,den*0.035) && projected<0.26 {alpha*=0.2}
                if !organic && core[p] {alpha=max(alpha,geometric*0.85)}
                if projected>0.97 && core[p] && geometric>0.92 {alpha=1}
                if g.name=="fork" && y<531 {
                    let threshold:Float=y<506 ? 48:67
                    alpha=clamp((c.x-c.z-threshold)/32)
                    if c.x-c.z<55 {alpha=0}
                }
                if alpha>0.025 && alpha<0.98 {
                    let unmixed=(c-b*(1-alpha))/max(0.18,alpha)
                    // Constrain unmixing to the trusted foreground colour;
                    // low-alpha numeric noise must never become black specks.
                    let safe=SIMD3(max(f.x-28,min(f.x+28,unmixed.x)),max(f.y-28,min(f.y+28,unmixed.y)),max(f.z-28,min(f.z+28,unmixed.z)))
                    color=safe*0.72+c*0.28
                }
            } else {
                alpha=geometric
            }
            if !core[p] {alpha=min(alpha,0.38)}
            if alpha<0.10 {alpha=0}
            if alpha>0.975 {alpha=1;color=c}
        }
        // Avoid adding a foreground sample across an old internal seam. For
        // opaque legacy pixels, preserve the approved per-layer artwork RGB.
        if alpha==1,old[owner].alpha(i)==255 {color=old[owner].rgb(i)}
        let edgeCoverage: Float?
        if g.name=="window", let top=archContour[x] {
            edgeCoverage=clamp(Float(y)-top+0.88)
        } else if g.name=="lamp", let right=shadeContour[y], x>=1200, x<=1235 {
            edgeCoverage=clamp(right-Float(x)+0.85)
        } else {
            edgeCoverage=nil
        }
        if let coverage=edgeCoverage, coverage<1 {
            alpha=min(alpha,coverage)
            color=removeWallpaper(from:master.rgb(i),using:base.rgb(i),opacity:alpha)
        }
        if alpha==0 {if originalMask[p]{removed+=1};continue}
        if alpha<1 {partial+=1}else{opaque+=1}
        let k=i*4
        outputPixels[owner]![k]=byte(color.x);outputPixels[owner]![k+1]=byte(color.y);outputPixels[owner]![k+2]=byte(color.z);outputPixels[owner]![k+3]=byte(alpha*255)
        // Books and inner layers share the exterior of their parent; avoid
        // adding internal cast shadows behind books on the shelf.
        if !(5...8).contains(owner) {fg[i]=max(fg[i],alpha)}
    }
    for id in g.ids {finalLayers[id]=outputPixels[id]!}
    let report="\(g.name): legacy \(oldCount), refined core \(insideCount), opaque \(opaque), partial \(partial), removed fringe \(removed)"
    print(report);logs.append(report)
}

// Smooth the edges of nested components too, without revealing a seam.
// The lower layer overlaps by one pixel underneath the opaque upper layer;
// both share the locked source colour at that coordinate.
for (lower,upper) in [(9,10),(11,12),(14,15),(21,22)] {
    let intersection=layout.layers[lower].rect.intersection(layout.layers[upper].rect)
    let r=Region(intersection.insetBy(dx:-3,dy:-3))
    let indices=(0..<r.count).map{r.index($0)}
    let lowerMask=indices.map{old[lower].alpha($0)>127},upperMask=indices.map{old[upper].alpha($0)>127}
    let outerDistance=r.distances(to:(0..<r.count).map{!lowerMask[$0] && !upperMask[$0]})
    let dl=r.distances(to:lowerMask),du=r.distances(to:upperMask)
    for p in 0..<r.count where outerDistance[p]>=2.5 && dl[p]<2.1 && du[p]<2.1 {
        let i=indices[p],x=i%w,y=i/w,k=i*4
        let point=CGPoint(x:CGFloat(x)+0.5,y:CGFloat(y)+0.5)
        guard intersection.contains(point),max(finalLayers[lower][k+3],finalLayers[upper][k+3])==255 else{continue}
        let c=lowerMask[p] ? old[lower].rgb(i):old[upper].rgb(i)
        let a:UInt8=upperMask[p] ? (dl[p]<=1.5 ? 224:255):(du[p]<=1.5 ? 32:0)
        if a>0 {
            finalLayers[upper][k]=byte(c.x);finalLayers[upper][k+1]=byte(c.y);finalLayers[upper][k+2]=byte(c.z);finalLayers[upper][k+3]=a
        }
        if a<255 {
            finalLayers[lower][k]=byte(c.x);finalLayers[lower][k+1]=byte(c.y);finalLayers[lower][k+2]=byte(c.z);finalLayers[lower][k+3]=255
        } else if dl[p]<=2.1 {
            finalLayers[lower][k]=byte(c.x);finalLayers[lower][k+1]=byte(c.y);finalLayers[lower][k+2]=byte(c.z);finalLayers[lower][k+3]=48
        }
    }
}

// Original contact shadows on the desk belong with their object, not with
// the background shadow layer (which is below the desk in z-order).
for (id,contact) in [(14,CGRect(x:649,y:645,width:102,height:6)),(16,CGRect(x:475,y:645,width:61,height:7))] {
    let area=Region(contact.intersection(layout.layers[id].rect))
    for p in 0..<area.count {
        let i=area.index(p),k=i*4
        let objectAlpha=Float(finalLayers[id][k+3])/255
        guard objectAlpha<0.97 else{continue}
        let cleanL=luminance(support.rgb(i)),actualL=luminance(master.rgb(i))
        let a=clamp((cleanL-actualL)/max(1,cleanL-32))*0.55
        guard a>0.025 else{continue}
        let under=a*(1-objectAlpha),combined=objectAlpha+under
        for (c,tint) in [Float(38),28,22].enumerated() {finalLayers[id][k+c]=byte((Float(finalLayers[id][k+c])*objectAlpha+tint*under)/combined)}
        finalLayers[id][k+3]=byte(combined*255)
    }
}

// Maintain the original direction, strength and feathered contact shadow.
// It now follows the refined silhouette and can show through transparent
// edge pixels. Opaque furniture naturally covers it in the composite.
let entire=Region(CGRect(x:0,y:0,width:w,height:h))
let dist=entire.distances(to:fg.map{$0>0.5})
var shadow=[UInt8](repeating:0,count:n*4)
let sb=layout.layers[3].rect
for y in 4..<h {for x in 2..<w {
    guard sb.contains(CGPoint(x:CGFloat(x)+0.5,y:CGFloat(y)+0.5)) else{continue}
    let i=y*w+x,k=i*4,d=dist[(y-4)*w+x-2]
    guard d<13,fg[i]<0.999 else{continue}
    var a=0.17*exp(-(d*d)/35)
    let archWeight = archContour[x].map {
        clamp((17-abs(Float(y)-$0))/5) * clamp(Float(min(x-408,958-x))/8)
    } ?? 0
    let shadeWeight = clamp(Float(x-1182)/23) * clamp(Float(1256-x)/10)
        * clamp(Float(y-384)/12) * clamp(Float(481-y)/12)
    let repairWeight = max(archWeight, shadeWeight)
    if repairWeight>0 {
        // Recover the artwork's soft shadow without darkening the wall
        // around the old, oversized cutout and outlining it in pale cream.
        let backgroundL=luminance(base.rgb(i))
        let sourceL=luminance(master.rgb(i))
        let recovered = clamp((backgroundL-sourceL-4)/max(1,backgroundL-32))
        a -= (a-min(a,recovered))*repairWeight
    }
    // Match the original darker contact area beneath the bookcase's curved
    // plinth instead of exposing an artificial bright strip of baseboard.
    if x>53 && x<354 && y>=813 && y<844 {
        let cleanL=luminance(base.rgb(i)),actualL=luminance(master.rgb(i))
        let originalShade=clamp((cleanL-actualL)/max(1,cleanL-32))*0.75
        a=max(a,min(0.43,originalShade))
    }
    shadow[k]=38;shadow[k+1]=28;shadow[k+2]=22;shadow[k+3]=byte(a*255)
}}
finalLayers[3]=shadow
for id in 0...2 {
    // Architectural surfaces contain no cutout edges; copy bit-for-bit.
    let src=original.appendingPathComponent("png-layers/"+layout.layers[id].png)
    try Data(contentsOf:src).write(to:pngDir.appendingPathComponent(layout.layers[id].png))
    finalLayers[id]=old[id].bytes
}
var composite=base.bytes
for id in 3..<27 {
    let pixels=finalLayers[id]
    precondition(pixels.count==n*4 && stride(from:3,to:pixels.count,by:4).contains{pixels[$0]>0})
    write(pixels,pngDir.appendingPathComponent(layout.layers[id].png))
    for i in 0..<n where pixels[i*4+3]>0 {
        let k=i*4,a=Int(pixels[k+3])
        for c in 0..<3 {composite[k+c]=UInt8((Int(pixels[k+c])*a+Int(composite[k+c])*(255-a)+127)/255)}
        composite[k+3]=255
    }
}
write(composite,output.appendingPathComponent("composited-preview.png"))
try logs.joined(separator:"\n").write(to:output.appendingPathComponent("matte-report.txt"),atomically:true,encoding:.utf8)
let manifest:[[String:Any]]=layout.layers.map{["name":$0.name,"png":$0.png,"x":$0.x,"y":$0.y,"width":$0.width,"height":$0.height]}
try JSONSerialization.data(withJSONObject:["canvasWidth":w,"canvasHeight":h,"layerOrder":"bottom-to-top","layers":manifest],options:[.prettyPrinted,.sortedKeys]).write(to:output.appendingPathComponent("layer-manifest.json"))

// Editable PSD v1, with the exact same straight RGBA channels as the PNGs.
extension Data {
    mutating func u16(_ n:Int){let v=UInt16(truncatingIfNeeded:n).bigEndian;Swift.withUnsafeBytes(of:v){append(contentsOf:$0)}}
    mutating func u32(_ n:Int){let v=UInt32(truncatingIfNeeded:n).bigEndian;Swift.withUnsafeBytes(of:v){append(contentsOf:$0)}}
    mutating func ascii(_ s:String){append(contentsOf:s.utf8)}
}
var records=Data(),channels=Data();records.u16(27)
for id in (0..<27).reversed() {
    let l=layout.layers[id],len=l.width*l.height,pixels=finalLayers[id]
    records.u32(l.y);records.u32(l.x);records.u32(l.y+l.height);records.u32(l.x+l.width);records.u16(4)
    for c in [0,1,2,-1]{records.u16(c);records.u32(len+2)}
    records.ascii("8BIM");records.ascii("norm");records.append(contentsOf:[255,0,0,0])
    var extra=Data();extra.u32(0);extra.u32(0)
    let name=Array(l.name.utf8.prefix(255));var ps=Data([UInt8(name.count)]);ps.append(contentsOf:name)
    while ps.count%4 != 0{ps.append(0)};extra.append(ps);records.u32(extra.count);records.append(extra)
    for c in 0..<4 {
        channels.u16(0);var plane=[UInt8]();plane.reserveCapacity(len)
        for y in l.y..<(l.y+l.height){for x in l.x..<(l.x+l.width){plane.append(pixels[(y*w+x)*4+c])}}
        channels.append(contentsOf:plane)
    }
}
var layerInfo=records;layerInfo.append(channels);if layerInfo.count%2 != 0{layerInfo.append(0)}
var section=Data();section.u32(layerInfo.count);section.append(layerInfo);section.u32(0)
var psd=Data();psd.ascii("8BPS");psd.u16(1);psd.append(contentsOf:[0,0,0,0,0,0]);psd.u16(3);psd.u32(h);psd.u32(w);psd.u16(8);psd.u16(3);psd.u32(0);psd.u32(0);psd.u32(section.count);psd.append(section);psd.u16(0)
for c in 0..<3{psd.append(contentsOf:(0..<n).map{composite[$0*4+c]})}
try psd.write(to:output.appendingPathComponent("home-sweet-home-v3-22-refined.psd"))
print("Refined 27 layers at",output.path)
