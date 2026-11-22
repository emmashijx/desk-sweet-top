import AppKit
import SwiftUI
import UniformTypeIdentifiers

struct RoomEditor: View {
    let template: RoomLayout
    let artwork: RoomArtwork
    let library: [RoomComponent]
    let onCancel: () -> Void
    let onSave: (RoomVersions) throws -> Void

    @State private var versions: RoomVersions
    @State private var versionID: UUID?
    @State private var project: RoomProject
    @State private var importedImage: CGImage?
    @State private var selectedID: UUID?
    @State private var error: String?
    @State private var pendingSelection: LayoutSelection?
    @State private var nameAction: NameAction?
    @State private var returnAfterNaming = false

    private let paper = Color(red: 0.98, green: 0.96, blue: 0.92)
    private let well = Color(red: 0.93, green: 0.90, blue: 0.84)
    private let olive = Color(red: 0.31, green: 0.36, blue: 0.25)
    private let thumbnails: [String: NSImage]

    init(template: RoomLayout, artwork: RoomArtwork, library: [RoomComponent], versions: RoomVersions,
         onCancel: @escaping () -> Void, onSave: @escaping (RoomVersions) throws -> Void) {
        self.template = template
        self.artwork = artwork
        self.library = library
        self.onCancel = onCancel
        self.onSave = onSave
        thumbnails = Dictionary(uniqueKeysWithValues: library.map { ($0.id, artwork.thumbnail(for: $0)) })
        let draft = versions.active?.project ?? RoomProject()
        _versions = State(initialValue: versions)
        _versionID = State(initialValue: versions.activeID)
        _project = State(initialValue: draft)
        _importedImage = State(initialValue: draft.backgroundPNG.flatMap(RoomArtwork.decode))
    }

    private enum LayoutSelection: Hashable, Identifiable {
        case blank, saved(UUID)
        var id: Self { self }
    }

    private enum NameAction: Hashable, Identifiable {
        case create, copy, rename(UUID)
        var id: Self { self }

        var title: String {
            switch self {
            case .create: return L("Name Your Layout")
            case .copy: return L("Save as New Layout…")
            case .rename: return L("Rename Layout…")
            }
        }
    }

    private var selected: RoomPlacement? { project.placements.first { $0.id == selectedID } }
    private var version: RoomVersion? { versions.layout(id: versionID) }
    private var canvasRatio: CGFloat { template.canvasWidth / template.canvasHeight }
    private var hasBackground: Bool { project.background != nil }

    var body: some View {
        VStack(spacing: 0) {
            toolbar
            Divider()
            HStack(spacing: 0) {
                libraryPanel
                Divider()
                VStack(spacing: 0) {
                    canvas
                    Divider()
                    inspector
                }
            }
        }
        .background(paper)
        .environment(\.colorScheme, .light)
        .tint(olive)
        .alert(Text(L("Room Editor")), isPresented: Binding(get: { error != nil }, set: { if !$0 { error = nil } })) {
            Button(L("OK")) { error = nil }
        } message: {
            Text(error ?? "")
        }
        .sheet(item: $nameAction, onDismiss: {
            if returnAfterNaming { onCancel() }
        }) { action in
            LayoutNameSheet(title: action.title, suggestion: nameSuggestion(for: action), onCancel: { nameAction = nil }) { name in
                try applyName(name, for: action)
            }
            .background(paper)
            .environment(\.colorScheme, .light)
            .tint(olive)
            .accentColor(olive)
        }
    }

    private var toolbar: some View {
        HStack(spacing: 10) {
            Text(L("Edit Room")).font(.system(size: 23, weight: .semibold, design: .serif))
                .accessibilityAddTraits(.isHeader)
            versionMenu
            Spacer()
            Button(L("Cancel"), action: onCancel).keyboardShortcut(.cancelAction)
            if versionID != nil {
                Button(L("Save as New Layout…")) { nameAction = .copy }.disabled(!hasBackground)
            }
            Button(L("Save Room"), action: saveAndClose)
                .buttonStyle(.borderedProminent)
                .keyboardShortcut("s", modifiers: .command)
                .disabled(!hasBackground)
        }
        .controlSize(.large)
        .padding(.horizontal, 20)
        .frame(height: 60)
    }

    private var versionMenu: some View {
        Menu {
            ForEach(versions.layouts) { saved in
                Button { requestLayout(.saved(saved.id)) } label: {
                    if saved.id == versionID {
                        Label(saved.name, systemImage: "checkmark")
                    } else {
                        Text(saved.name)
                    }
                }
            }
            if !versions.layouts.isEmpty { Divider() }
            Button(L("New Blank Layout")) { requestLayout(.blank) }
                .disabled(versionID == nil && project == RoomProject())
            if let versionID {
                Button(L("Rename Layout…")) { nameAction = .rename(versionID) }
            }
        } label: {
            Label(version?.name ?? L("New Layout"), systemImage: "square.on.square")
                .lineLimit(1)
        }
        .menuStyle(.borderedButton)
        .fixedSize(horizontal: false, vertical: true)
        .frame(maxWidth: 180)
        .accessibilityLabel(L("Room Layouts"))
        .accessibilityValue(version?.name ?? L("New Layout"))
        .help(L("Room Layouts"))
        .alert(item: $pendingSelection) { selection in
            Alert(title: Text(L("Unsaved Layout Changes")),
                  message: Text(L("Save this layout or save it as a new version before switching.")),
                  primaryButton: .cancel(Text(L("Keep Editing"))),
                  secondaryButton: .destructive(Text(L("Discard Changes"))) { openLayout(selection) })
        }
    }

    private func requestLayout(_ selection: LayoutSelection) {
        if case .saved(let id) = selection, id == versionID { return }
        if project == (version?.project ?? RoomProject()) {
            openLayout(selection)
        } else {
            pendingSelection = selection
        }
    }

    private func openLayout(_ selection: LayoutSelection) {
        switch selection {
        case .blank: versionID = nil
        case .saved(let id): versionID = id
        }
        project = version?.project ?? RoomProject()
        importedImage = project.backgroundPNG.flatMap(RoomArtwork.decode)
        selectedID = nil
    }

    private func saveAndClose() {
        guard let versionID else { nameAction = .create; return }
        attempt {
            var updated = versions
            try updated.update(versionID, project: project)
            try onSave(updated)
            onCancel()
        }
    }

    private func nameSuggestion(for action: NameAction) -> String {
        switch action {
        case .rename(let id): return versions.layout(id: id)?.name ?? ""
        case .copy:
            if let version {
                let copyName = L("%@ Copy", version.name)
                if copyName.count <= 64, versions.isNameAvailable(copyName) { return copyName }
            }
            return versions.nextName()
        case .create: return versions.nextName()
        }
    }

    private func applyName(_ name: String, for action: NameAction) throws {
        var updated = versions
        switch action {
        case .rename(let id): try updated.rename(id, to: name)
        case .create, .copy: try updated.add(named: name, project: project)
        }
        try onSave(updated)
        versions = updated
        returnAfterNaming = action == .create || action == .copy
        nameAction = nil
    }

    private var libraryPanel: some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 7) {
                Text(L("Background")).font(.headline).accessibilityAddTraits(.isHeader)
                if hasBackground {
                    Button { useBuiltInBackground() } label: {
                        Label(L("Generate Empty Room"), systemImage: "rectangle")
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    Button { importBackground() } label: {
                        Label(L("Import Image…"), systemImage: "photo")
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
                if project.placements.isEmpty {
                    Button(L("Open Original Layout")) {
                        project = .original(using: library)
                        importedImage = nil
                    }
                    .buttonStyle(.link)
                }
            }
            Divider()
            Text(L("Furniture")).font(.headline).accessibilityAddTraits(.isHeader)
            ScrollView {
                LazyVGrid(columns: [GridItem(.flexible(), spacing: 7), GridItem(.flexible(), spacing: 7)], spacing: 7) {
                    ForEach(library) { component in componentButton(component) }
                }
                .padding(.bottom, 4)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 15)
        .frame(width: 218)
    }

    private func componentButton(_ component: RoomComponent) -> some View {
        let monitorExists = component.id == "monitor" && project.placements.contains { $0.component == component.id }
        return Button { add(component) } label: {
            VStack(spacing: 3) {
                Image(nsImage: thumbnails[component.id]!)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(height: 48)
                    .accessibilityHidden(true)
                Text(L(component.title))
                    .font(.system(size: 11, weight: .medium))
                    .lineLimit(2)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: .infinity, minHeight: 25)
            }
            .padding(4)
            .background(.white.opacity(0.51), in: RoundedRectangle(cornerRadius: 6))
            .overlay { RoundedRectangle(cornerRadius: 6).strokeBorder(.black.opacity(0.09)) }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!hasBackground || monitorExists)
        .opacity(!hasBackground || monitorExists ? 0.45 : 1)
        .accessibilityLabel(L("Add %@", L(component.title)))
        .help(L("Add %@", L(component.title)))
    }

    private var canvas: some View {
        GeometryReader { geometry in
            let width = max(1, min(geometry.size.width - 36, (geometry.size.height - 36) * canvasRatio))
            let height = width / canvasRatio
            Group {
                if hasBackground {
                    RoomEditorCanvas(artwork: artwork, layout: project.layout(from: template, library: library),
                                     background: importedImage, placements: project.placements, selected: selected,
                                     onSelect: { selectedID = $0 }, onMove: move, onDelete: removeSelection)
                } else {
                    VStack(spacing: 13) {
                        Text(L("Start with a Background")).font(.system(size: 29, weight: .semibold, design: .serif))
                        HStack {
                            Button(L("Generate Empty Room"), action: useBuiltInBackground).buttonStyle(.borderedProminent)
                            Button(L("Import Image…"), action: importBackground)
                        }
                        .controlSize(.large)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(paper)
                }
            }
            .frame(width: width, height: height)
            .overlay { Rectangle().strokeBorder(.black.opacity(0.13), lineWidth: 1).allowsHitTesting(false) }
            .shadow(color: .black.opacity(0.10), radius: 9, y: 4)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .background(well)
    }

    private var inspector: some View {
        HStack(spacing: 9) {
            if let selected, let component = library.first(where: { $0.id == selected.component }) {
                Text(L(component.title)).font(.headline).lineLimit(1)
                Spacer(minLength: 0)
                Text(L("Size")).font(.callout)
                Slider(value: Binding(get: { selected.scale }, set: { resize(selected, to: $0) }), in: 0.25...1.75)
                    .frame(minWidth: 64, idealWidth: 104, maxWidth: 126)
                    .accessibilityLabel(L("Size"))
                Text(Double(selected.scale).formatted(.percent.precision(.fractionLength(0))))
                    .font(.callout.monospacedDigit())
                    .frame(minWidth: 43)
                orderButton("Send Backward", icon: "square.2.layers.3d.bottom.filled", step: -1)
                orderButton("Bring Forward", icon: "square.2.layers.3d.top.filled", step: 1)
                Button(role: .destructive, action: removeSelection) {
                    Label(L("Remove"), systemImage: "trash").labelStyle(.iconOnly)
                }
                .help(L("Remove"))
            } else {
                Text(L("Select a piece to move or resize it."))
                    .font(.callout).foregroundStyle(.secondary)
                    .opacity(hasBackground && !project.placements.isEmpty ? 1 : 0)
                Spacer()
            }
        }
        .padding(.horizontal, 17)
        .frame(height: 52)
    }

    private func orderButton(_ title: String, icon: String, step: Int) -> some View {
        let index = project.placements.firstIndex { $0.id == selectedID }
        return Button {
            guard let index, project.placements.indices.contains(index + step) else { return }
            project.placements.swapAt(index, index + step)
        } label: {
            Label(L(title), systemImage: icon).labelStyle(.iconOnly)
        }
        .disabled(index.map { !project.placements.indices.contains($0 + step) } ?? true)
        .help(L(title))
    }

    private func useBuiltInBackground() {
        project.background = .builtIn
        project.backgroundPNG = nil
        importedImage = nil
    }

    private func importBackground() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.image]
        guard panel.runModal() == .OK, let url = panel.url else { return }
        attempt {
            let data = try RoomProjectStore.importImage(url)
            guard let image = RoomArtwork.decode(data) else { throw RoomProjectError.invalidImage }
            project.background = .imported
            project.backgroundPNG = data
            importedImage = image
        }
    }

    private func add(_ component: RoomComponent) {
        let count = project.placements.filter { $0.component == component.id }.count
        guard hasBackground, component.id != "monitor" || count == 0 else { return }
        let offset = CGFloat((count % 8) * 20)
        let placement = constrained(RoomPlacement(component: component.id, x: offset, y: offset))
        project.placements.append(placement)
        selectedID = placement.id
    }

    private func move(_ original: RoomPlacement, _ offset: CGPoint) {
        var moved = original
        moved.x += offset.x
        moved.y += offset.y
        update(moved)
    }

    private func resize(_ original: RoomPlacement, to scale: CGFloat) {
        var resized = original
        resized.scale = scale
        update(resized)
    }

    private func constrained(_ placement: RoomPlacement) -> RoomPlacement {
        guard let component = library.first(where: { $0.id == placement.component }) else { return placement }
        let bounds = component.bounds
        let center = CGPoint(x: bounds.midX, y: bounds.midY)
        let rect = placement.destination(bounds, around: center)
        let visible = min(28, rect.width / 2, rect.height / 2)
        var adjusted = placement
        adjusted.x += min(max(rect.maxX, visible), template.canvasWidth + rect.width - visible) - rect.maxX
        adjusted.y += min(max(rect.maxY, visible), template.canvasHeight + rect.height - visible) - rect.maxY
        return adjusted
    }

    private func update(_ placement: RoomPlacement) {
        guard let index = project.placements.firstIndex(where: { $0.id == placement.id }) else { return }
        project.placements[index] = constrained(placement)
    }

    private func removeSelection() {
        project.placements.removeAll { $0.id == selectedID }
        selectedID = nil
    }

    private func attempt(_ action: () throws -> Void) {
        do { try action() }
        catch let failure { error = failure.localizedDescription }
    }
}

private struct LayoutNameSheet: View {
    let title: String
    let onCancel: () -> Void
    let onSave: (String) throws -> Void

    @State private var name: String
    @State private var error: String?
    @FocusState private var isNameFocused: Bool

    init(title: String, suggestion: String, onCancel: @escaping () -> Void, onSave: @escaping (String) throws -> Void) {
        self.title = title
        self.onCancel = onCancel
        self.onSave = onSave
        _name = State(initialValue: suggestion)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title).font(.headline).accessibilityAddTraits(.isHeader)
            TextField(L("Layout Name"), text: Binding(get: { name }, set: {
                name = $0
                error = nil
            }))
                .textFieldStyle(.roundedBorder)
                .focused($isNameFocused)
            if let error {
                Text(error).foregroundStyle(.red).font(.callout)
            }
            HStack {
                Spacer()
                Button(L("Cancel"), action: onCancel).keyboardShortcut(.cancelAction)
                Button(L("Save Layout Name")) {
                    do { try onSave(name) }
                    catch let failure { error = failure.localizedDescription }
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
                .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding(20)
        .frame(width: 350)
        .onAppear { isNameFocused = true }
    }
}

private struct RoomEditorCanvas: NSViewRepresentable {
    let artwork: RoomArtwork
    let layout: RoomLayout
    let background: CGImage?
    let placements: [RoomPlacement]
    let selected: RoomPlacement?
    let onSelect: (UUID?) -> Void
    let onMove: (RoomPlacement, CGPoint) -> Void
    let onDelete: () -> Void

    func makeNSView(context: Context) -> CanvasView { CanvasView(frame: .zero) }

    func updateNSView(_ view: CanvasView, context: Context) {
        view.editor = self
        view.needsDisplay = true
    }

    final class CanvasView: NSView {
        var editor: RoomEditorCanvas?
        private var dragStart: CGPoint?
        private var draggedPlacement: RoomPlacement?
        override var isFlipped: Bool { true }
        override var acceptsFirstResponder: Bool { true }
        override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

        private var transform: RoomTransform? {
            guard let layout = editor?.layout, bounds.width > 0, bounds.height > 0 else { return nil }
            return RoomTransform(canvas: CGSize(width: layout.canvasWidth, height: layout.canvasHeight), viewport: bounds)
        }

        override func draw(_ dirtyRect: NSRect) {
            guard let editor, let transform else { return }
            editor.artwork.draw(editor.layout, in: bounds, background: editor.background)
            guard let id = editor.selected?.id else { return }
            let outline = editor.layout.layers.filter { $0.placementID == id }.reduce(CGRect.null) { rect, layer in
                rect.union(editor.layout.viewportDestination(layer, transform: transform))
            }
            guard !outline.isNull else { return }
            let path = NSBezierPath(rect: outline.insetBy(dx: -2, dy: -2))
            NSColor.white.withAlphaComponent(0.9).setStroke()
            path.lineWidth = 3
            path.stroke()
            NSColor(srgbRed: 0.31, green: 0.36, blue: 0.25, alpha: 1).setStroke()
            path.lineWidth = 1.5
            path.stroke()
        }

        override func mouseDown(with event: NSEvent) {
            guard let editor, let transform else { return }
            window?.makeFirstResponder(self)
            let point = convert(event.locationInWindow, from: nil)
            let id = editor.artwork.hitTest(point, layout: editor.layout, transform: transform)
            dragStart = point
            draggedPlacement = editor.placements.first { $0.id == id }
            editor.onSelect(id)
        }

        override func mouseDragged(with event: NSEvent) {
            guard let editor, let transform, let dragStart, let draggedPlacement else { return }
            let point = convert(event.locationInWindow, from: nil)
            let offset = CGPoint(x: (point.x - dragStart.x) / transform.scale, y: (point.y - dragStart.y) / transform.scale)
            editor.onMove(draggedPlacement, offset)
        }

        override func mouseUp(with event: NSEvent) {
            dragStart = nil
            draggedPlacement = nil
        }

        override func keyDown(with event: NSEvent) {
            guard let editor, let selected = editor.selected else { super.keyDown(with: event); return }
            let step: CGFloat = event.modifierFlags.contains(.shift) ? 10 : 1
            switch event.keyCode {
            case 51, 117: editor.onDelete()
            case 123: editor.onMove(selected, CGPoint(x: -step, y: 0))
            case 124: editor.onMove(selected, CGPoint(x: step, y: 0))
            case 125: editor.onMove(selected, CGPoint(x: 0, y: step))
            case 126: editor.onMove(selected, CGPoint(x: 0, y: -step))
            default: super.keyDown(with: event)
            }
        }
    }
}
