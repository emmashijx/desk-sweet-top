import AppKit
import ImageIO
import UniformTypeIdentifiers

struct RoomComponent: Identifiable {
    let id: String
    let title: String
    let layers: [RoomLayer]

    var bounds: CGRect { layers.reduce(.null) { $0.union(($1.target ?? $1.source).rect) } }

    static func library(from layout: RoomLayout) -> [RoomComponent] {
        let definitions: [(String, String, ClosedRange<Int>)] = [
            ("window", "Arched Window", 9...10),
            ("door", "Pink Door", 11...12),
            ("bookcase", "Bookcase", 4...8),
            ("desk", "Oak Desk", 13...13),
            ("monitor", "Monitor", 14...15),
            ("flowers", "Flower Vase", 16...16),
            ("left-clock", "Left Clock", 17...17),
            ("right-clock", "Right Clock", 18...18),
            ("map", "Travel Map", 19...19),
            ("tableware", "Plate and Cutlery", 20...23),
            ("lamp", "Glass Lamp", 24...24),
            ("bin", "Enamel Bin", 25...25),
            ("rug", "Woven Rug", 26...26)
        ]
        return definitions.compactMap { id, title, range in
            let layers = layout.ordered.filter { layer in Int(layer.png.prefix(2)).map(range.contains) ?? false }.map { original in
                var layer = original
                let rect = layout.destination(original)
                layer.target = RoomRect(x: rect.minX, y: rect.minY, width: rect.width, height: rect.height)
                return layer
            }
            guard layers.count == range.count else { return nil }
            return RoomComponent(id: id, title: title, layers: layers)
        }
    }
}

struct RoomPlacement: Codable, Equatable, Identifiable {
    var id = UUID()
    var component: String
    var x: CGFloat = 0
    var y: CGFloat = 0
    var scale: CGFloat = 1

    func destination(_ rect: CGRect, around center: CGPoint) -> CGRect {
        CGRect(x: center.x + (rect.minX - center.x) * scale + x,
               y: center.y + (rect.minY - center.y) * scale + y,
               width: rect.width * scale, height: rect.height * scale)
    }
}

struct RoomProject: Codable, Equatable {
    enum Background: String, Codable { case builtIn, imported }

    var background: Background?
    var backgroundPNG: Data?
    var placements: [RoomPlacement] = []

    static func original(using library: [RoomComponent]) -> RoomProject {
        let ordered = library.sorted { ($0.layers.first?.z ?? 0) < ($1.layers.first?.z ?? 0) }
        return RoomProject(background: .builtIn, placements: ordered.map { RoomPlacement(component: $0.id) })
    }

    func layout(from template: RoomLayout, library: [RoomComponent]) -> RoomLayout {
        var layers = background == .builtIn ? template.ordered.filter { $0.surface != nil } : []
        let components = Dictionary(uniqueKeysWithValues: library.map { ($0.id, $0) })
        for placement in placements {
            guard let component = components[placement.component] else { continue }
            let center = CGPoint(x: component.bounds.midX, y: component.bounds.midY)
            for var layer in component.layers {
                let rect = placement.destination((layer.target ?? layer.source).rect, around: center)
                layer.target = RoomRect(x: rect.minX, y: rect.minY, width: rect.width, height: rect.height)
                layer.z = layers.count
                layer.placementID = placement.id
                layers.append(layer)
            }
        }
        return RoomLayout(canvasWidth: template.canvasWidth, canvasHeight: template.canvasHeight, layers: layers)
    }

    func validated(using library: [RoomComponent]) throws {
        let componentIDs = Set(library.map(\.id))
        guard background != nil,
              background != .imported || backgroundPNG.flatMap(RoomArtwork.decode) != nil,
              Set(placements.map(\.id)).count == placements.count,
              placements.filter({ $0.component == "monitor" }).count <= 1,
              placements.allSatisfy({
                  componentIDs.contains($0.component) && $0.x.isFinite && $0.y.isFinite &&
                  (0.25...1.75).contains($0.scale)
              }) else { throw RoomProjectError.invalidProject }
    }
}

struct RoomVersion: Codable, Equatable, Identifiable {
    var id = UUID()
    var name: String
    var project: RoomProject
}

struct RoomVersions: Codable, Equatable {
    private(set) var layouts: [RoomVersion] = []
    private(set) var activeID: UUID?

    var active: RoomVersion? { layout(id: activeID) }

    func layout(id: UUID?) -> RoomVersion? {
        layouts.first { $0.id == id }
    }

    func nextName() -> String {
        var number = layouts.count + 1
        while !isNameAvailable(L("Layout %ld", number)) { number += 1 }
        return L("Layout %ld", number)
    }

    @discardableResult
    mutating func add(named requestedName: String, project: RoomProject) throws -> UUID {
        let name = try validatedName(requestedName)
        let version = RoomVersion(name: name, project: project)
        layouts.append(version)
        activeID = version.id
        return version.id
    }

    mutating func update(_ id: UUID, project: RoomProject) throws {
        guard let index = layouts.firstIndex(where: { $0.id == id }) else { throw RoomProjectError.invalidProject }
        layouts[index].project = project
        activeID = id
    }

    mutating func rename(_ id: UUID, to requestedName: String) throws {
        guard let index = layouts.firstIndex(where: { $0.id == id }) else { throw RoomProjectError.invalidProject }
        let name = try validatedName(requestedName, excluding: id)
        layouts[index].name = name
    }

    mutating func select(_ id: UUID) throws {
        guard layout(id: id) != nil else { throw RoomProjectError.invalidProject }
        activeID = id
    }

    func isNameAvailable(_ name: String, excluding id: UUID? = nil) -> Bool {
        let key = Self.nameKey(name)
        return !layouts.contains { $0.id != id && Self.nameKey($0.name) == key }
    }

    func validated(using library: [RoomComponent]) throws {
        guard Set(layouts.map(\.id)).count == layouts.count,
              layouts.isEmpty ? activeID == nil : active != nil else { throw RoomProjectError.invalidProject }
        for version in layouts {
            guard try validatedName(version.name, excluding: version.id) == version.name else {
                throw RoomProjectError.invalidProject
            }
            try version.project.validated(using: library)
        }
    }

    private func validatedName(_ requestedName: String, excluding id: UUID? = nil) throws -> String {
        let name = requestedName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty, name.count <= 64, name.rangeOfCharacter(from: .newlines) == nil else {
            throw RoomProjectError.invalidName
        }
        guard isNameAvailable(name, excluding: id) else { throw RoomProjectError.duplicateName }
        return name
    }

    private static func nameKey(_ name: String) -> String {
        name.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: Locale(identifier: "en_US_POSIX"))
    }
}

enum RoomProjectError: LocalizedError {
    case invalidImage, invalidProject
    case invalidName, duplicateName

    var errorDescription: String? {
        switch self {
        case .invalidImage: return L("This image could not be opened.")
        case .invalidProject: return L("This room layout could not be opened.")
        case .invalidName: return L("Enter a name between 1 and 64 characters.")
        case .duplicateName: return L("A layout already uses this name.")
        }
    }
}

struct RoomProjectStore {
    let directory: URL

    var file: URL { directory.appendingPathComponent("room-versions.json") }
    var legacyFile: URL { directory.appendingPathComponent("room.json") }

    static var local: RoomProjectStore {
        if let directory = ProcessInfo.processInfo.environment["SWEET_HOME_PROJECT_DIRECTORY"], !directory.isEmpty {
            return RoomProjectStore(directory: URL(fileURLWithPath: directory, isDirectory: true))
        }
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return RoomProjectStore(directory: support.appendingPathComponent("Home Sweet Home", isDirectory: true))
    }

    func load(using library: [RoomComponent]) throws -> RoomVersions {
        if let data = try read(file) {
            let versions = try JSONDecoder().decode(RoomVersions.self, from: data)
            try versions.validated(using: library)
            return versions
        }
        var versions = RoomVersions()
        if let data = try read(legacyFile) {
            let project = try JSONDecoder().decode(RoomProject.self, from: data)
            try versions.add(named: L("First Layout"), project: project)
            try save(versions, using: library)
        }
        return versions
    }

    func save(_ versions: RoomVersions, using library: [RoomComponent]) throws {
        try versions.validated(using: library)
        let encoded = try JSONEncoder().encode(versions)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try encoded.write(to: file, options: .atomic)
    }

    private func read(_ url: URL) throws -> Data? {
        do { return try Data(contentsOf: url) }
        catch let error as CocoaError where error.code == .fileReadNoSuchFile { return nil }
    }

    static func importImage(_ file: URL) throws -> Data {
        let options = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: 3072
        ] as CFDictionary
        guard let source = CGImageSourceCreateWithURL(file as CFURL, nil),
              let image = CGImageSourceCreateThumbnailAtIndex(source, 0, options) else {
            throw RoomProjectError.invalidImage
        }
        let data = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(data, UTType.png.identifier as CFString, 1, nil) else {
            throw RoomProjectError.invalidImage
        }
        CGImageDestinationAddImage(destination, image, nil)
        guard CGImageDestinationFinalize(destination) else { throw RoomProjectError.invalidImage }
        return data as Data
    }
}

func testRoomProject() throws {
    let template = try RoomResources.layout()
    let library = RoomComponent.library(from: template)
    precondition(library.count == 13)
    var project = RoomProject(background: .builtIn)
    precondition(project.layout(from: template, library: library).layers.count == 3)
    let monitor = RoomPlacement(component: "monitor", x: 60, y: -25, scale: 0.75)
    let lamp = RoomPlacement(component: "lamp")
    let secondLamp = RoomPlacement(component: "lamp", x: -30)
    project.placements = [lamp, monitor, secondLamp]
    let composed = project.layout(from: template, library: library)
    let movedScreen = composed.screen!
    precondition(movedScreen.placementID == monitor.id)
    precondition(abs(composed.destination(movedScreen).width - template.screen!.width * 0.75) < 0.01)
    precondition(composed.ordered.last?.placementID == secondLamp.id)
    precondition(RoomProject.original(using: library).layout(from: template, library: library).layers.count == 26)

    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: directory) }
    let store = RoomProjectStore(directory: directory)
    let missing = try store.load(using: library)
    precondition(missing.layouts.isEmpty && missing.active == nil)
    let image = RoomResources.root().appendingPathComponent("layers/01-wallpaper.png")
    project.background = .imported
    project.backgroundPNG = try RoomProjectStore.importImage(image)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    let legacyBytes = try JSONEncoder().encode(project)
    try legacyBytes.write(to: store.legacyFile)

    var versions = try store.load(using: library)
    let firstID = versions.active!.id
    precondition(versions.layouts.count == 1 && versions.active?.name == L("First Layout"))
    precondition(versions.active?.project == project)
    precondition(versions.active?.project.layout(from: template, library: library).layers.allSatisfy { $0.surface == nil } == true)
    let migrated = try store.load(using: library)
    precondition(migrated == versions)

    let blankRoom = RoomProject(background: .builtIn)
    let otherID = try versions.add(named: "  Weekend  ", project: blankRoom)
    precondition(versions.active?.id == otherID && versions.active?.name == "Weekend")
    do {
        try versions.add(named: "weekend", project: blankRoom)
        preconditionFailure("Duplicate layout name was accepted")
    } catch RoomProjectError.duplicateName {}
    try versions.rename(firstID, to: "Original room")
    try versions.update(otherID, project: RoomProject(background: .builtIn, placements: [lamp]))
    try versions.select(firstID)
    try store.save(versions, using: library)

    let loaded = try store.load(using: library)
    precondition(loaded == versions && loaded.active?.project == project)
    precondition(loaded.layout(id: otherID)?.project.placements == [lamp])
    let preservedLegacy = try Data(contentsOf: store.legacyFile)
    precondition(preservedLegacy == legacyBytes)
    print("房间编辑测试通过：空房间、组件分组、背景导入、旧布局迁移、版本另存、改名、更新和切换重载。")
}
