import AppKit

final class RoomView: NSView {
    let layoutSpec: RoomLayout
    private let artwork: RoomArtwork
    private let background: CGImage?
    private let monitorButton=NSButton()
    private let message=MonitorFeedbackLabel()
    let chooser=MonitorChooser()
    var browserService=BrowserService(driver:NativeBrowserDriver())
    var transform: RoomTransform {
        RoomTransform(canvas: CGSize(width: layoutSpec.canvasWidth, height: layoutSpec.canvasHeight), viewport: bounds)
    }
    override var isFlipped: Bool { true }
    init(layout: RoomLayout, artwork: RoomArtwork? = nil, background: CGImage? = nil) {
        layoutSpec = layout
        self.artwork = artwork ?? RoomArtwork(layout: layout)
        self.background = background
        super.init(frame: .zero)
        monitorButton.isBordered=false
        monitorButton.isTransparent=true
        monitorButton.title=""
        monitorButton.keyEquivalent="\r"
        monitorButton.keyEquivalentModifierMask=[]
        monitorButton.target=self
        monitorButton.action=#selector(openChooser)
        monitorButton.toolTip=L("Open Chrome or Safari")
        monitorButton.setAccessibilityLabel(L("Choose a browser"))
        monitorButton.focusRingType = .none
        message.textColor=NSColor(calibratedRed:0.96,green:0.91,blue:0.83,alpha:1)
        message.isHidden=true
        addSubview(message)
        addSubview(monitorButton)
        addSubview(chooser)
        chooser.onCancel={ [weak self] in self?.dismissChooser() }
        chooser.onChoose={ [weak self] kind,mode in self?.launch(kind,mode:mode) }
    }
    required init?(coder: NSCoder) { fatalError("init(coder:)") }
    override func draw(_ dirtyRect: NSRect) {
        artwork.draw(layoutSpec, in: bounds, background: background)
    }
    var monitorRect: CGRect {
        guard let screen=layoutSpec.screen, screen.visible != false else {return .zero}
        return layoutSpec.viewportDestination(screen,transform:transform)
    }
    override func setFrameSize(_ newSize: NSSize) {
        super.setFrameSize(newSize); needsDisplay=true;needsLayout=true
    }
    override func layout() {
        super.layout()
        monitorButton.frame=monitorRect
        monitorButton.isHidden=monitorRect.isEmpty || !chooser.isHidden
        chooser.frame=monitorRect
        let screenScale=MonitorTypography.scale(for:monitorRect.size)
        message.frame=monitorRect.insetBy(dx:10*screenScale,dy:12*screenScale)
        MonitorTypography.applyFeedback(message,value:message.stringValue,scale:screenScale,color:message.textColor)
        chooser.needsLayout=true
    }
    @objc func openChooser() {
        guard !monitorRect.isEmpty,chooser.isHidden else{return}
        message.isHidden=true; monitorButton.isHidden=true
        chooser.present()
    }
    func dismissChooser() {
        chooser.hide();monitorButton.isHidden=monitorRect.isEmpty
        window?.makeFirstResponder(monitorButton)
    }
    @discardableResult func handleEscape() -> Bool {
        guard !chooser.isHidden && !chooser.busy else {return false}
        dismissChooser();return true
    }
    private func launch(_ browser:BrowserKind,mode:WindowMode) {
        chooser.launchStarted(browser)
        let screen=window?.screen ?? NSScreen.main
        let visible=screen?.visibleFrame ?? CGRect(x:0,y:0,width:1440,height:900)
        let globalY=NSScreen.screens.first?.frame.maxY ?? visible.maxY
        let available=CGRect(x:visible.minX,y:globalY-visible.maxY,width:visible.width,height:visible.height)
        let service=browserService
        DispatchQueue.global(qos:.userInitiated).async { [weak self] in
            let result=service.launch(browser,mode:mode,available:available)
            DispatchQueue.main.async {
                guard let self else{return}
                if result.opened {
                    self.dismissChooser()
                    if let notice=result.notice {
                        self.message.isHidden=false
                        MonitorTypography.applyFeedback(self.message,value:notice,scale:MonitorTypography.scale(for:self.monitorRect.size),color:self.message.textColor)
                    }
                } else {self.chooser.showFailure(result.notice ?? L("Could not open browser. Try again."))}
            }
        }
    }
    func checkAssets() -> Bool { artwork.hasAssets(for: layoutSpec) }
    func testInteraction() {
        layoutSubtreeIfNeeded()
        precondition(checkAssets() && monitorButton.frame==monitorRect && chooser.frame==monitorRect)
        let inside=CGPoint(x:monitorRect.midX,y:monitorRect.midY)
        // hitTest receives a point in the superview's coordinate system.
        precondition(hitTest(convert(inside,to:superview)) === monitorButton)
        precondition(hitTest(convert(CGPoint(x:5,y:5),to:superview)) !== monitorButton)
        monitorButton.performClick(nil)
        precondition(!chooser.isHidden && monitorButton.isHidden)
        chooser.testControls()
        precondition(handleEscape() && chooser.isHidden && !monitorButton.isHidden)
        print("屏幕交互测试通过：命中区域、选择器、半屏/全屏、启动中、失败、取消。")
    }
    func testLaunchAndReturn() {
        let saved=browserService
        let mock=MockBrowserDriver()
        browserService=BrowserService(driver:mock)
        openChooser();launch(.chrome,mode:.half)
        let deadline=Date().addingTimeInterval(3)
        while !chooser.isHidden && Date()<deadline { RunLoop.current.run(until:Date().addingTimeInterval(0.02)) }
        precondition(chooser.isHidden && !monitorButton.isHidden && message.isHidden && mock.created==0)
        browserService=saved
        print("启动返回测试通过：成功启动后恢复待机状态。")
    }
}
