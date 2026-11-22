import AppKit
import ApplicationServices

enum BrowserKind: String, CaseIterable {
    case chrome = "Chrome", safari = "Safari"
    var bundleIdentifier: String { self == .chrome ? "com.google.Chrome" : "com.apple.Safari" }
    var displayName: String { rawValue }
}
enum WindowMode: String { case half, full }
struct LaunchResult {
    let opened: Bool
    let notice: String?
}
struct BrowserSession { let pid: pid_t; let alreadyRunning: Bool }
enum BrowserFailure: Error { case missing, unableToLaunch, unavailable }
protocol BrowserDriver {
    func start(_ browser: BrowserKind) throws -> BrowserSession
    func countWindows(_ browser: BrowserKind) throws -> Int
    func newWindow(_ browser: BrowserKind) throws
    func setWindowMode(_ mode: WindowMode, session: BrowserSession, available: CGRect) -> Bool
    func wait(_ seconds: TimeInterval)
}

struct BrowserService {
    var driver: BrowserDriver
    func launch(_ browser: BrowserKind, mode: WindowMode, available: CGRect) -> LaunchResult {
        let session: BrowserSession
        do { session=try driver.start(browser) }
        catch BrowserFailure.missing { return LaunchResult(opened:false,notice:L("%@ is not installed. Choose another browser.",browser.displayName)) }
        catch { return LaunchResult(opened:false,notice:L("Could not open %@. Try again.",browser.displayName)) }
        var warnings: [String] = []
        do {
            var count=try driver.countWindows(browser)
            // Give an ordinary launch time to restore its own prior session.
            let retries=session.alreadyRunning ? 2 : 8
            for _ in 0..<retries where count==0 {
                driver.wait(0.45)
                count=try driver.countWindows(browser)
            }
            if count==0 {
                try driver.newWindow(browser)
                driver.wait(0.35)
            }
        } catch {
            warnings.append(L("If no window appears, press ⌘N."))
        }
        if !driver.setWindowMode(mode,session:session,available:available) {
            warnings.append(L("Use window controls to resize."))
        }
        return LaunchResult(opened:true,notice:warnings.isEmpty ? nil : warnings.joined(separator:"\n"))
    }
}

final class NativeBrowserDriver: BrowserDriver {
    private let lock=NSLock()
    private var didRequestAccessibility=false
    func start(_ browser: BrowserKind) throws -> BrowserSession {
        guard let url=NSWorkspace.shared.urlForApplication(withBundleIdentifier:browser.bundleIdentifier) else {
            throw BrowserFailure.missing
        }
        if let running=NSRunningApplication.runningApplications(withBundleIdentifier:browser.bundleIdentifier).first(where:{!$0.isTerminated}) {
            _=running.activate(options:[.activateAllWindows])
            return BrowserSession(pid:running.processIdentifier,alreadyRunning:true)
        }
        let config=NSWorkspace.OpenConfiguration()
        config.activates=true
        config.createsNewApplicationInstance=false
        let semaphore=DispatchSemaphore(value:0)
        var launched: NSRunningApplication?
        NSWorkspace.shared.openApplication(at:url, configuration:config) { running,_ in
            launched=running; semaphore.signal()
        }
        guard semaphore.wait(timeout:.now()+20) == .success, let launched else {throw BrowserFailure.unableToLaunch}
        return BrowserSession(pid:launched.processIdentifier,alreadyRunning:false)
    }

    private func appleScript(_ script: String) throws -> String {
        let process=Process()
        let output=Pipe()
        process.executableURL=URL(fileURLWithPath:"/usr/bin/osascript")
        process.arguments=["-e", "with timeout of 12 seconds\n"+script+"\nend timeout"]
        process.standardOutput=output
        process.standardError=output
        try process.run()
        let done=DispatchSemaphore(value:0)
        DispatchQueue.global().async {process.waitUntilExit();done.signal()}
        if done.wait(timeout:.now()+16) == .timedOut {
            if process.isRunning {process.terminate()}
            throw BrowserFailure.unavailable
        }
        let data=output.fileHandleForReading.readDataToEndOfFile()
        guard process.terminationStatus==0 else {throw BrowserFailure.unavailable}
        return String(decoding:data,as:UTF8.self).trimmingCharacters(in:.whitespacesAndNewlines)
    }
    func countWindows(_ browser: BrowserKind) throws -> Int {
        // Only query count; no URLs, history, cookies or browser profile files.
        let answer=try appleScript("tell application id \"\(browser.bundleIdentifier)\" to count windows")
        guard let n=Int(answer),n>=0 else {throw BrowserFailure.unavailable}
        return n
    }
    func newWindow(_ browser: BrowserKind) throws {
        // Recheck atomically inside the application to prevent duplicate windows.
        let command = browser == .chrome ? "make new window" : "make new document"
        _=try appleScript("tell application id \"\(browser.bundleIdentifier)\"\nif (count windows) = 0 then\n\(command)\nend if\nactivate\nend tell")
    }
    func wait(_ seconds: TimeInterval) { Thread.sleep(forTimeInterval:seconds) }
    private func windowFor(_ app: AXUIElement) -> AXUIElement? {
        for key in [kAXFocusedWindowAttribute,kAXMainWindowAttribute] {
            var value: CFTypeRef?
            if AXUIElementCopyAttributeValue(app,key as CFString,&value) == .success,
               let value, CFGetTypeID(value)==AXUIElementGetTypeID() {
                return unsafeBitCast(value,to:AXUIElement.self)
            }
        }
        var value: CFTypeRef?
        if AXUIElementCopyAttributeValue(app,kAXWindowsAttribute as CFString,&value) == .success,
           let windows=value as? [AXUIElement] {return windows.first}
        return nil
    }
    func setWindowMode(_ mode: WindowMode, session: BrowserSession, available: CGRect) -> Bool {
        if !AXIsProcessTrusted() {
            lock.lock()
            let prompt = !didRequestAccessibility
            didRequestAccessibility=true
            lock.unlock()
            if prompt {
                let options=[kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String:true] as CFDictionary
                _=AXIsProcessTrustedWithOptions(options)
            }
            return false
        }
        let running=AXUIElementCreateApplication(session.pid)
        var target=windowFor(running)
        for _ in 0..<6 where target==nil { wait(0.25);target=windowFor(running) }
        guard var window=target else {return false}
        _=AXUIElementSetAttributeValue(window,kAXMinimizedAttribute as CFString,kCFBooleanFalse)
        let fullscreen="AXFullScreen" as CFString
        var current: CFTypeRef?
        _=AXUIElementCopyAttributeValue(window,fullscreen,&current)
        let isFull=(current as? Bool) ?? false
        if mode == .full {
            return isFull || AXUIElementSetAttributeValue(window,fullscreen,kCFBooleanTrue) == .success
        }
        if isFull {
            guard AXUIElementSetAttributeValue(window,fullscreen,kCFBooleanFalse) == .success else {return false}
            wait(0.9)
            if let restored=windowFor(running) {window=restored}
        }
        // Available is already in global AX top-left coordinates.
        var position=CGPoint(x:available.midX,y:available.minY)
        var size=CGSize(width:available.width/2,height:available.height)
        guard let point=AXValueCreate(.cgPoint,&position),let dimensions=AXValueCreate(.cgSize,&size) else {return false}
        let moved=AXUIElementSetAttributeValue(window,kAXPositionAttribute as CFString,point)
        let resized=AXUIElementSetAttributeValue(window,kAXSizeAttribute as CFString,dimensions)
        // Move again because some window managers constrain the initial move.
        let corrected=AXUIElementSetAttributeValue(window,kAXPositionAttribute as CFString,point)
        return (moved == .success || corrected == .success) && resized == .success
    }
}

final class MockBrowserDriver: BrowserDriver {
    var counts:[Int]=[1]; var startError: BrowserFailure?; var countError=false
    var alreadyRunning=true; var modeSuccess=true; var created=0; var modes:[WindowMode]=[]
    func start(_ browser:BrowserKind) throws -> BrowserSession {
        if let startError {throw startError}
        return BrowserSession(pid:1,alreadyRunning:alreadyRunning)
    }
    func countWindows(_ browser:BrowserKind) throws -> Int {
        if countError {throw BrowserFailure.unavailable}
        if counts.count>1 {return counts.removeFirst()}
        return counts.first ?? 0
    }
    func newWindow(_ browser:BrowserKind) throws {created+=1}
    func setWindowMode(_ mode:WindowMode,session:BrowserSession,available:CGRect)->Bool {modes.append(mode);return modeSuccess}
    func wait(_ seconds:TimeInterval) {}
}
func testBrowserService() {
    let rect=CGRect(x:0,y:24,width:1440,height:870)
    let mock=MockBrowserDriver(),service=BrowserService(driver:mock)
    precondition(service.launch(.chrome,mode:.half,available:rect).opened && mock.created==0 && mock.modes==[.half])
    mock.counts=[0,0,0]; precondition(service.launch(.safari,mode:.full,available:rect).opened && mock.created==1 && mock.modes.last == .full)
    mock.counts=[0,0,2];mock.alreadyRunning=false
    precondition(service.launch(.chrome,mode:.half,available:rect).opened && mock.created==1)
    mock.countError=true;mock.modeSuccess=false
    let warning=service.launch(.safari,mode:.half,available:rect)
    precondition(warning.opened && warning.notice != nil && mock.created==1)
    mock.startError = .missing; precondition(!service.launch(.chrome,mode:.full,available:rect).opened)
    mock.startError = .unableToLaunch; precondition(!service.launch(.safari,mode:.half,available:rect).opened)
    print("浏览器适配测试通过：已有窗口复用、零窗口新开、延迟恢复、未安装、启动失败、权限退化和窗口模式。")
}
