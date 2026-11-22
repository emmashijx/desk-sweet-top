import AppKit

struct RoomRect: Codable, Equatable {
    var x: CGFloat
    var y: CGFloat
    var width: CGFloat
    var height: CGFloat
    var rect: CGRect { CGRect(x: x, y: y, width: width, height: height) }
}

// Structural surfaces can extend to the viewport; movable objects never do.
enum RoomSurface: String, Codable { case wallpaper, wainscot, floor }

struct RoomLayer: Codable {
    var name: String
    var png: String
    var x: CGFloat
    var y: CGFloat
    var width: CGFloat
    var height: CGFloat
    var target: RoomRect?
    var z: Int?
    var visible: Bool?
    var surface: RoomSurface?
    var placementID: UUID?
    var source: RoomRect { RoomRect(x: x, y: y, width: width, height: height) }
}

struct RoomGroup: Codable {
    var originX: CGFloat
    var originY: CGFloat
    var offsetX: CGFloat
    var offsetY: CGFloat
    var scale: CGFloat
    var members: [String]
}

struct RoomLayout: Codable {
    var canvasWidth: CGFloat
    var canvasHeight: CGFloat
    var layers: [RoomLayer]
    var groups: [RoomGroup]?
    var screen: RoomLayer? { layers.first { $0.png == "15-monitor-screen.png" } }
    func destination(_ l: RoomLayer) -> CGRect {
        let r = (l.target ?? l.source).rect
        guard let g = groups?.first(where: { $0.members.contains(l.png) }) else { return r }
        let scale = max(0.05, g.scale)
        return CGRect(x: g.originX + (r.minX-g.originX)*scale + g.offsetX,
                      y: g.originY + (r.minY-g.originY)*scale + g.offsetY,
                      width: r.width*scale, height: r.height*scale)
    }
    func viewportDestination(_ l: RoomLayer, transform: RoomTransform) -> CGRect {
        let fitted = transform.rect(destination(l))
        guard let surface = l.surface else { return fitted }
        return transform.surfaceRect(fitted, surface: surface)
    }
    var ordered: [RoomLayer] {
        layers.enumerated().sorted { a, b in
            let z1 = a.element.z ?? a.offset, z2 = b.element.z ?? b.offset
            return z1 == z2 ? a.offset < b.offset : z1 < z2
        }.map(\.element)
    }
}

struct RoomTransform {
    var canvas: CGSize
    var viewport: CGRect
    var scale: CGFloat { min(viewport.width/canvas.width, viewport.height/canvas.height) }
    var origin: CGPoint { CGPoint(x: viewport.midX - canvas.width*scale/2, y: viewport.midY - canvas.height*scale/2) }
    func rect(_ source: CGRect) -> CGRect {
        CGRect(x: origin.x + source.minX*scale, y: origin.y + source.minY*scale,
               width: source.width*scale, height: source.height*scale)
    }
    func surfaceRect(_ fitted: CGRect, surface: RoomSurface) -> CGRect {
        // Keep both wall/floor seams at their original fitted heights, so
        // furniture, floor contact shadows and the baseboard remain aligned.
        let top = surface == .wallpaper ? viewport.minY : fitted.minY
        let bottom = surface == .floor ? viewport.maxY : fitted.maxY
        return CGRect(x: viewport.minX, y: top, width: viewport.width, height: max(0,bottom-top))
    }
}

enum RoomResources {
    static func root() -> URL {
        if let explicit = ProcessInfo.processInfo.environment["SWEET_HOME_RESOURCES"] {
            return URL(fileURLWithPath: explicit)
        }
        return Bundle.main.resourceURL!
    }
    static func layout() throws -> RoomLayout {
        try JSONDecoder().decode(RoomLayout.self, from: Data(contentsOf: root().appendingPathComponent("layout.json")))
    }
}

func testLayout() throws {
    var layout = try RoomResources.layout()
    precondition(layout.layers.count == 27 && layout.canvasWidth == 1557 && layout.canvasHeight == 1010)
    let screen = layout.screen!
    let t = RoomTransform(canvas: CGSize(width: 1557, height: 1010), viewport: CGRect(x: 0, y: 0, width: 1200, height: 800))
    let initial = t.rect(layout.destination(screen))
    precondition(initial.width > 190 && initial.width < 210)
    precondition(abs(initial.minX - screen.x*t.scale) < 0.1)
    let old = layout.destination(screen)
    layout.groups = [RoomGroup(originX: old.minX, originY: old.minY, offsetX: 40, offsetY: -20, scale: 0.8, members: ["14-monitor-body.png", "15-monitor-screen.png"])]
    let moved = layout.destination(screen)
    precondition(abs(moved.minX-old.minX-40)<0.1 && abs(moved.width-old.width*0.8)<0.1)
    let body=layout.layers.first{$0.png=="14-monitor-body.png"}!
    precondition(abs(layout.destination(body).width-body.width*0.8)<0.1)
    let other=layout.layers.first{$0.png=="01-wallpaper.png"}!
    precondition(layout.destination(other)==other.source.rect)
    let wide = RoomTransform(canvas: CGSize(width: 1557, height: 1010), viewport: CGRect(x:0,y:0,width:1800,height:900))
    precondition(wide.origin.x > 0 && abs(wide.origin.y)<0.1)
    let surfaces=layout.ordered.filter{$0.surface != nil}
    precondition(surfaces.map(\.surface)==[.wallpaper,.wainscot,.floor])
    for size in [CGSize(width:1557,height:1010),CGSize(width:1710,height:1073),CGSize(width:1800,height:900),CGSize(width:840,height:570),CGSize(width:1000,height:1000)] {
        let viewport=CGRect(origin:.zero,size:size)
        let transform=RoomTransform(canvas:CGSize(width:layout.canvasWidth,height:layout.canvasHeight),viewport:viewport)
        let r=surfaces.map{layout.viewportDestination($0,transform:transform)}
        precondition(r.allSatisfy{abs($0.minX-viewport.minX)<0.001 && abs($0.maxX-viewport.maxX)<0.001})
        precondition(abs(r[0].minY-viewport.minY)<0.001 && abs(r[0].maxY-r[1].minY)<0.001 && abs(r[1].maxY-r[2].minY)<0.001 && abs(r[2].maxY-viewport.maxY)<0.001)
        for layer in layout.layers where layer.surface == nil {
            let original=layout.destination(layer)
            let mapped=layout.viewportDestination(layer,transform:transform)
            precondition(mapped==transform.rect(original))
            precondition(abs(mapped.width*original.height-mapped.height*original.width)<0.001)
        }
    }
    print("布局测试通过：27 层、背景无留白、家具等比映射、显示器组移动和缩放。")
}
