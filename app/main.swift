import AppKit
import SwiftUI

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var window: NSWindow?
    private var keyMonitor: Any?
    private weak var room: RoomView?
    private var template: RoomLayout?
    private var artwork: RoomArtwork?
    private var library: [RoomComponent] = []
    private var versions = RoomVersions()
    private var storageError: Error?
    private let store = RoomProjectStore.local
    private var switchLayoutItem: NSMenuItem?

    func applicationDidFinishLaunching(_ notification: Notification) {
        do {
            let layout = try RoomResources.layout()
            template = layout
            artwork = RoomArtwork(layout: layout)
            library = RoomComponent.library(from: layout)
            do {
                versions = try store.load(using: library)
            } catch {
                storageError = error
                NSAlert(error: error).runModal()
            }
            let max = NSScreen.main?.visibleFrame.size ?? CGSize(width: 1440,height:900)
            let width=min(1180,max.width-80), height=min(width*0.66,max.height-80)
            let win=NSWindow(contentRect:CGRect(x:0,y:0,width:width,height:height),
                             styleMask:[.titled,.closable,.miniaturizable,.resizable],backing:.buffered,defer:false)
            win.title="Home Sweet Home"
            win.minSize=NSSize(width:870,height:580)
            win.collectionBehavior.insert(.fullScreenPrimary)
            window=win
            let menu=NSMenu()
            let appItem=NSMenuItem();menu.addItem(appItem)
            let appMenu=NSMenu(title:"Home Sweet Home");appItem.submenu=appMenu
            appMenu.addItem(withTitle:L("Quit Home Sweet Home"),action:#selector(NSApplication.terminate(_:)),keyEquivalent:"q")
            let windowItem=NSMenuItem();menu.addItem(windowItem)
            let windowMenu=NSMenu(title:L("Window"));windowItem.submenu=windowMenu
            let edit = windowMenu.addItem(withTitle: L("Edit Room"), action: #selector(editRoom), keyEquivalent: "e")
            edit.target = self
            let layouts = windowMenu.addItem(withTitle: L("Room Layouts"), action: nil, keyEquivalent: "")
            layouts.submenu = NSMenu(title: L("Room Layouts"))
            switchLayoutItem = layouts
            let fullscreen=windowMenu.addItem(withTitle:L("Toggle Full Screen"),action:#selector(NSWindow.toggleFullScreen(_:)),keyEquivalent:"f")
            fullscreen.keyEquivalentModifierMask=[.command,.control]
            NSApp.mainMenu=menu
            win.center()
            keyMonitor=NSEvent.addLocalMonitorForEvents(matching:.keyDown) { [weak self] event in
                let room = self?.room
                if event.keyCode==53 && room?.handleEscape()==true {return nil}
                if room?.chooser.handleKeyboard(event)==true {return nil}
                return event
            }
            if versions.active == nil { editRoom() } else { showRoom() }
            win.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps:true)
        } catch {
            NSAlert(error:error).runModal()
            NSApp.terminate(nil)
        }
    }

    @objc private func editRoom() {
        guard let template, let artwork, let window,
              !(window.contentView is NSHostingView<RoomEditor>) else { return }
        room = nil
        let editor = RoomEditor(template: template, artwork: artwork, library: library,
                                versions: versions, onCancel: { [weak self] in self?.showRoom() }) { [weak self] updated in
            try self?.saveVersions(updated)
        }
        window.contentView = NSHostingView(rootView: editor)
        window.makeFirstResponder(nil)
        refreshLayoutMenu()
    }

    private func showRoom() {
        guard let template, let artwork, let window else { return }
        let project = versions.active?.project
        let layout = project?.layout(from: template, library: library) ?? template
        let background = project?.backgroundPNG.flatMap(RoomArtwork.decode)
        let room = RoomView(layout: layout, artwork: artwork, background: background)
        window.contentView = room
        window.makeFirstResponder(nil)
        self.room = room
        refreshLayoutMenu()
    }

    private func saveVersions(_ updated: RoomVersions) throws {
        if let storageError { throw storageError }
        try store.save(updated, using: library)
        versions = updated
        refreshLayoutMenu()
    }

    private func refreshLayoutMenu() {
        guard let item = switchLayoutItem, let menu = item.submenu else { return }
        item.isHidden = room == nil || versions.layouts.isEmpty
        menu.removeAllItems()
        for version in versions.layouts {
            let choice = menu.addItem(withTitle: version.name, action: #selector(switchLayout(_:)), keyEquivalent: "")
            choice.target = self
            choice.representedObject = version.id
            choice.state = version.id == versions.activeID ? .on : .off
        }
    }

    @objc private func switchLayout(_ sender: NSMenuItem) {
        guard room != nil, let id = sender.representedObject as? UUID, id != versions.activeID else { return }
        do {
            var updated = versions
            try updated.select(id)
            try saveVersions(updated)
            showRoom()
        } catch {
            NSAlert(error: error).runModal()
        }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }
}

func captureRoom(to directory: URL) throws {
    let layout=try RoomResources.layout()
    let room=RoomView(layout:layout)
    let window=NSWindow(contentRect:CGRect(x:0,y:0,width:1180,height:765),styleMask:[.borderless],backing:.buffered,defer:false)
    window.contentView=room
    room.layoutSubtreeIfNeeded()
    func capture(_ name:String) throws {
        room.layoutSubtreeIfNeeded()
        guard let pixels=room.bitmapImageRepForCachingDisplay(in:room.bounds) else {throw CocoaError(.fileWriteUnknown)}
        room.cacheDisplay(in:room.bounds,to:pixels)
        guard let data=pixels.representation(using:.png,properties:[:]) else {throw CocoaError(.fileWriteUnknown)}
        try data.write(to:directory.appendingPathComponent(name))
    }
    room.testInteraction()
    room.testLaunchAndReturn()
    try capture("room-window.png")
    room.openChooser();try capture("monitor-picker.png");room.dismissChooser()
    window.setContentSize(CGSize(width:1557,height:1010))
    room.layoutSubtreeIfNeeded();room.testInteraction()
    room.openChooser();try capture("monitor-picker-full.png");room.dismissChooser()
    // Match the content area of the user's fullscreen screenshot (Retina 2x).
    window.setContentSize(CGSize(width:1710,height:1073))
    room.layoutSubtreeIfNeeded();room.testInteraction()
    try capture("room-fullscreen-mac.png")
    room.openChooser();try capture("monitor-picker-fullscreen-mac.png");room.dismissChooser()
    // Also exercise a taller window to verify top/bottom surface extension.
    window.setContentSize(CGSize(width:1000,height:1000))
    room.layoutSubtreeIfNeeded();room.testInteraction()
    try capture("room-tall.png")
    print("房间快照已保存：\(directory.path)")
}

func captureMonitorTypography(to directory:URL) throws {
    try FileManager.default.createDirectory(at:directory,withIntermediateDirectories:true)
    let locale=Bundle.main.preferredLocalizations.first ?? "en"
    let chooser=MonitorChooser()
    let window=NSWindow(contentRect:CGRect(origin:.zero,size:MonitorTypography.canvas),styleMask:[.borderless],backing:.buffered,defer:false)
    window.contentView=chooser
    func capture(_ filename:String) throws {
        chooser.layoutSubtreeIfNeeded()
        guard let pixels=chooser.bitmapImageRepForCachingDisplay(in:chooser.bounds) else {throw CocoaError(.fileWriteUnknown)}
        chooser.cacheDisplay(in:chooser.bounds,to:pixels)
        guard let png=pixels.representation(using:.png,properties:[:]) else {throw CocoaError(.fileWriteUnknown)}
        try png.write(to:directory.appendingPathComponent("\(locale)-\(filename).png"))
    }
    for (name,size) in [("full",CGSize(width:258,height:165)),("window",CGSize(width:145,height:93)),("miniature",CGSize(width:36,height:23))] {
        window.setContentSize(size)
        chooser.present();chooser.needsLayout=true;chooser.layoutSubtreeIfNeeded()
        chooser.testTypography()
        try capture("\(name)-chooser")
        chooser.showFailure(L("%@ is not installed. Choose another browser.","Safari"));try capture("\(name)-error")
        chooser.launchStarted(.chrome);try capture("\(name)-opening")
    }
    print("显示器排版测试通过：\(locale)，正常、最小窗口、缩小家具及本地化状态。")
}

if CommandLine.arguments.contains("--self-test") {
    do { try testLayout(); try testRoomProject(); testBrowserService(); exit(0) }
    catch { print(error); exit(1) }
}
if CommandLine.arguments.contains("--language-test") {
    print(Bundle.main.preferredLocalizations.joined(separator:","))
    print(L("Choose browser"),L("Half screen"),L("Full screen"),L("Cancel"),L("Opening %@…","Safari"),separator:" / ")
    exit(0)
}
let app=NSApplication.shared
if let index=CommandLine.arguments.firstIndex(of:"--type-test"),index+1<CommandLine.arguments.count {
    do {try captureMonitorTypography(to:URL(fileURLWithPath:CommandLine.arguments[index+1]));exit(0)}
    catch {print(error);exit(1)}
}
if let index=CommandLine.arguments.firstIndex(of:"--capture-test"),index+1<CommandLine.arguments.count {
    do {try captureRoom(to:URL(fileURLWithPath:CommandLine.arguments[index+1]));exit(0)}
    catch {print(error);exit(1)}
}
let delegate=AppDelegate()
app.delegate=delegate
app.setActivationPolicy(.regular)
app.run()
