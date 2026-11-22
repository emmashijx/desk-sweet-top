import AppKit

// A quiet porcelain palette derived from the room's blue ceramic and ivory trim.
private enum MonitorPalette {
    private static func rgb(_ r:CGFloat,_ g:CGFloat,_ b:CGFloat)->NSColor {NSColor(srgbRed:r/255,green:g/255,blue:b/255,alpha:1)}
    static let canvas=rgb(220,231,237)
    static let porcelain=rgb(250,245,235)
    static let ink=rgb(43,65,83)
    static let secondary=rgb(70,92,107)
    static let accent=rgb(66,107,135)
    static let divider=rgb(161,179,190)
    static let pressed=rgb(199,218,229)
    static let error=rgb(132,68,58)
    static let idlePaper=rgb(247,235,214)
}

// One native type family, with a small intentional scale for a physical screen.
enum MonitorTextRole {
    case heading, browser, mode, secondary, feedback
    var size: CGFloat {
        switch self {
        case .heading: return 17
        case .browser: return 15.5
        case .mode: return 12
        case .secondary: return 11.5
        case .feedback: return 11.5
        }
    }
    var weight: NSFont.Weight {
        switch self {
        case .heading, .browser: return .semibold
        case .mode: return .medium
        case .secondary, .feedback: return .regular
        }
    }
    var tracking: CGFloat {
        switch self {
        case .heading: return -0.012
        case .browser: return 0
        case .mode, .secondary, .feedback: return 0.012
        }
    }
}

enum MonitorTypography {
    static let canvas=CGSize(width:258,height:165)
    static func scale(for size:CGSize)->CGFloat {
        max(0,min(size.width/canvas.width,size.height/canvas.height))
    }
    static func preferredSize(_ role:MonitorTextRole, scale:CGFloat)->CGFloat {
        // At normal window sizes retain a readable floor. An editor-resized
        // miniature still fits its screen rather than spilling over its edges.
        let floor:CGFloat = scale >= 0.5 ? (role == .browser || role == .heading ? 10 : 8.5) : 0.5
        return max(floor,role.size*scale)
    }
    static func text(_ value:String,role:MonitorTextRole,pointSize:CGFloat,color:NSColor,alignment:NSTextAlignment = .center,wrapping:Bool=false,underlined:Bool=false)->NSAttributedString {
        let paragraph=NSMutableParagraphStyle()
        paragraph.alignment=alignment
        paragraph.lineBreakMode=wrapping ? .byWordWrapping : .byClipping
        paragraph.lineSpacing=wrapping ? pointSize*0.10 : 0
        var attributes:[NSAttributedString.Key:Any]=[.font:NSFont.systemFont(ofSize:pointSize,weight:role.weight),.foregroundColor:color,.kern:pointSize*role.tracking,.paragraphStyle:paragraph]
        if underlined { attributes[.underlineStyle]=NSUnderlineStyle.single.rawValue }
        return NSAttributedString(string:value,attributes:attributes)
    }
    static func measured(_ text:NSAttributedString,width:CGFloat,wrapping:Bool)->CGSize {
        if !wrapping {return text.size()}
        return text.boundingRect(with:CGSize(width:max(0.1,width),height:10000),options:[.usesLineFragmentOrigin,.usesFontLeading]).size
    }
    static func fitted(_ value:String,role:MonitorTextRole,scale:CGFloat,color:NSColor,available:CGSize,alignment:NSTextAlignment = .center,wrapping:Bool=false,underlined:Bool=false)->NSAttributedString {
        let preferred=preferredSize(role,scale:scale)
        let limit=CGSize(width:max(0.1,available.width),height:max(0.1,available.height))
        var low:CGFloat=0.1,high=preferred
        func make(_ size:CGFloat)->NSAttributedString {text(value,role:role,pointSize:size,color:color,alignment:alignment,wrapping:wrapping,underlined:underlined)}
        func fits(_ value:NSAttributedString)->Bool {
            let actual=measured(value,width:limit.width,wrapping:wrapping)
            return actual.width<=limit.width+0.05 && actual.height<=limit.height+0.05
        }
        let ideal=make(preferred)
        if fits(ideal) {return ideal}
        for _ in 0..<12 {let mid=(low+high)/2;if fits(make(mid)){low=mid}else{high=mid}}
        return make(low)
    }
    static func applyFeedback(_ label:MonitorFeedbackLabel,value:String,scale:CGFloat,color:NSColor) {
        label.padding=scale
        label.attributedStringValue=fitted(value,role:.feedback,scale:scale,color:color,available:CGSize(width:max(0.1,label.bounds.width-2*scale),height:max(0.1,label.bounds.height-2*scale)),wrapping:true)
    }
}

// Draw with the same text rectangle used for fit measurements. AppKit's
// standard field cell adds insets and can truncate CJK at tiny dimensions.
final class MonitorFeedbackLabel:NSView {
    override var isFlipped:Bool {true}
    var padding:CGFloat=0
    var textColor:NSColor=MonitorPalette.idlePaper
    var attributedStringValue=NSAttributedString(string:"") {
        didSet {needsDisplay=true;setAccessibilityLabel(attributedStringValue.string)}
    }
    var stringValue:String {attributedStringValue.string}
    init(){super.init(frame:.zero);setAccessibilityElement(true);setAccessibilityRole(.staticText)}
    required init?(coder:NSCoder){fatalError("init(coder:)")}
    override func draw(_ dirtyRect:NSRect) {
        guard !stringValue.isEmpty else{return}
        attributedStringValue.draw(with:bounds.insetBy(dx:padding,dy:padding),options:[.usesLineFragmentOrigin,.usesFontLeading])
    }
    override func hitTest(_ point:NSPoint)->NSView? {nil}
}

final class RoomButton: NSButton {
    var fill: NSColor = .clear
    var foreground: NSColor = MonitorPalette.ink
    var label: String
    var role: MonitorTextRole = .mode
    var typeScale: CGFloat=1
    var icon: NSImage?
    var leftAligned=false
    var selectionState:Bool? {didSet{needsDisplay=true}}
    var keyboardFocused=false { didSet { needsDisplay=true } }
    var onMouseDown: (() -> Void)?
    init(_ label: String,target:AnyObject?,action:Selector?) {
        self.label=label
        super.init(frame:.zero)
        self.target=target;self.action=action
        isBordered=false;bezelStyle = .regularSquare
        setButtonType(.momentaryChange)
        focusRingType = .none
        setAccessibilityLabel(label)
        wantsLayer=true
        layer?.cornerRadius=5
    }
    required init?(coder:NSCoder) {fatalError("init(coder:)")}
    override func mouseDown(with event:NSEvent) {
        onMouseDown?()
        super.mouseDown(with:event)
    }
    override func draw(_ dirtyRect:NSRect) {
        let bg = isHighlighted ? MonitorPalette.pressed : fill
        bg.setFill()
        NSBezierPath(roundedRect:bounds,xRadius:4*typeScale,yRadius:4*typeScale).fill()
        let (str,imageSize,iconSpace)=labelComposition()
        let s=str.size()
        let start = leftAligned ? 13*typeScale : (bounds.width-s.width-iconSpace)/2
        if let icon {icon.draw(in:CGRect(x:start,y:(bounds.height-imageSize)/2,width:imageSize,height:imageSize),from:.zero,operation:.sourceOver,fraction:isEnabled ? 1 : 0.4)}
        if let selected=selectionState {
            let marker=CGRect(x:start,y:(bounds.height-imageSize)/2,width:imageSize,height:imageSize).insetBy(dx:0.6*typeScale,dy:0.6*typeScale)
            MonitorPalette.accent.setStroke()
            let ring=NSBezierPath(ovalIn:marker);ring.lineWidth=1.15*typeScale;ring.stroke()
            if selected {
                MonitorPalette.accent.setFill()
                NSBezierPath(ovalIn:marker.insetBy(dx:2.6*typeScale,dy:2.6*typeScale)).fill()
            }
        }
        str.draw(at:CGPoint(x:start+iconSpace,y:(bounds.height-s.height)/2))
    }
    func labelComposition()->(NSAttributedString,CGFloat,CGFloat) {
        let imageSize=min((selectionState == nil ? 18:11)*typeScale,bounds.height*0.62,bounds.width*0.22)
        let iconSpace=(icon != nil || selectionState != nil) ? imageSize+6*typeScale : 0
        let padding=leftAligned ? 13*typeScale : 4*typeScale
        let str=MonitorTypography.fitted(label,role:role,scale:typeScale,color:foreground,available:CGSize(width:max(0.1,bounds.width-iconSpace-2*padding),height:max(0.1,bounds.height-4*typeScale)),underlined:keyboardFocused)
        return (str,imageSize,iconSpace)
    }
}

private func browserGlyph(_ browser:BrowserKind)->NSImage {
    NSImage(size:NSSize(width:24,height:24),flipped:false) { rect in
        let c=MonitorPalette.accent
        c.setStroke();c.setFill()
        let circle=NSBezierPath(ovalIn:rect.insetBy(dx:2,dy:2));circle.lineWidth=1.9;circle.stroke()
        if browser == .chrome {
            let inner=NSBezierPath(ovalIn:rect.insetBy(dx:8,dy:8));inner.lineWidth=1.7;inner.stroke()
            for angle in [0.0,120.0,240.0] {
                let a=angle*Double.pi/180, b=(angle+27)*Double.pi/180
                let line=NSBezierPath()
                line.move(to:CGPoint(x:12+4*cos(b),y:12+4*sin(b)))
                line.line(to:CGPoint(x:12+10*cos(a),y:12+10*sin(a)))
                line.lineWidth=1.5;line.stroke()
            }
        } else {
            let needle=NSBezierPath()
            needle.move(to:CGPoint(x:17,y:18));needle.line(to:CGPoint(x:10,y:10));needle.line(to:CGPoint(x:7,y:6));needle.line(to:CGPoint(x:14,y:13));needle.close()
            needle.fill()
        }
        return true
    }
}

final class MonitorChooser: NSView {
    var onChoose: ((BrowserKind,WindowMode)->Void)?
    var onCancel: (()->Void)?
    var mode: WindowMode = .half
    var busy=false
    private let title=NSTextField(labelWithString:L("Choose browser"))
    private let status=MonitorFeedbackLabel()
    private var chrome:RoomButton!
    private var safari:RoomButton!
    private var half:RoomButton!
    private var full:RoomButton!
    private var close:RoomButton!
    private var statusText=""
    private var statusIsError=false
    private var browserPanel=CGRect.zero
    private var typeScale:CGFloat {MonitorTypography.scale(for:bounds.size)}
    private var keyboardIndex: Int?
    private var controls: [RoomButton] { [half,full,chrome,safari,close] }
    override var isFlipped: Bool {true}
    override var acceptsFirstResponder: Bool {true}
    init() {
        super.init(frame:.zero)
        wantsLayer=true
        layer?.backgroundColor=MonitorPalette.canvas.cgColor
        layer?.cornerRadius=5
        layer?.masksToBounds=true
        title.textColor=MonitorPalette.ink;title.alignment = .left
        title.maximumNumberOfLines=1
        status.textColor=MonitorPalette.secondary
        chrome=RoomButton("Chrome",target:self,action:#selector(pickChrome))
        safari=RoomButton("Safari",target:self,action:#selector(pickSafari))
        chrome.icon=browserGlyph(.chrome);safari.icon=browserGlyph(.safari)
        for button in [chrome!,safari!] {button.foreground=MonitorPalette.ink;button.role = .browser;button.leftAligned=true}
        half=RoomButton(L("Half screen"),target:self,action:#selector(pickHalf))
        full=RoomButton(L("Full screen"),target:self,action:#selector(pickFull))
        close=RoomButton(L("Cancel"),target:self,action:#selector(cancel))
        close.role = .secondary;close.foreground=MonitorPalette.secondary
        for button in [half!,full!] {button.selectionState=false;button.setAccessibilityRole(.radioButton)}
        let views: [NSView] = [title,status,chrome,safari,half,full,close]
        for view in views {addSubview(view)}
        half.nextKeyView=full; full.nextKeyView=chrome; chrome.nextKeyView=safari
        safari.nextKeyView=close; close.nextKeyView=half
        for control in controls {control.onMouseDown={[weak self] in self?.clearKeyboardFocus()}}
        isHidden=true
        updateMode()
    }
    required init?(coder:NSCoder) {fatalError("init(coder:)")}
    override func draw(_ dirtyRect:NSRect) {
        super.draw(dirtyRect)
        guard !browserPanel.isEmpty else{return}
        let s=typeScale
        let panel=NSBezierPath(roundedRect:browserPanel,xRadius:5*s,yRadius:5*s)
        MonitorPalette.porcelain.setFill();panel.fill()
        MonitorPalette.divider.setStroke();panel.lineWidth=0.75*s;panel.stroke()
        let rule=NSBezierPath()
        rule.move(to:CGPoint(x:browserPanel.minX+10*s,y:browserPanel.midY))
        rule.line(to:CGPoint(x:browserPanel.maxX-10*s,y:browserPanel.midY))
        rule.lineWidth=0.65*s;rule.stroke()
    }
    override func layout() {
        super.layout()
        let s=typeScale
        let origin=CGPoint(x:(bounds.width-258*s)/2,y:(bounds.height-165*s)/2)
        func box(_ x:CGFloat,_ y:CGFloat,_ w:CGFloat,_ h:CGFloat)->CGRect {
            CGRect(x:origin.x+x*s,y:origin.y+y*s,width:w*s,height:h*s)
        }
        title.frame=box(13,8,176,24)
        title.attributedStringValue=MonitorTypography.fitted(L("Choose browser"),role:.heading,scale:s,color:MonitorPalette.ink,available:CGSize(width:title.bounds.width-2*s,height:title.bounds.height-2*s),alignment:.left)
        close.frame=box(189,7,56,25)
        // Mode first, then two full-width actions in one grouped list.
        half.frame=box(13,33,114,22)
        full.frame=box(131,33,114,22)
        browserPanel=box(13,58,232,66)
        chrome.frame=box(14,59,230,32)
        safari.frame=box(14,92,230,31)
        status.frame=box(12,128,234,33)
        layer?.cornerRadius=5*s
        for b in controls {b.typeScale=s;b.layer?.cornerRadius=4*s;b.needsDisplay=true}
        needsDisplay=true
        updateStatus()
    }
    func present(notice:String?=nil) {
        busy=false;isHidden=false;statusText=notice ?? "";statusIsError=false;updateStatus();updateEnabled()
        clearKeyboardFocus()
        window?.makeFirstResponder(self)
    }
    func hide() {clearKeyboardFocus();isHidden=true;busy=false}
    private func clearKeyboardFocus() {
        keyboardIndex=nil
        controls.forEach{$0.keyboardFocused=false}
    }
    func handleKeyboard(_ event:NSEvent) -> Bool {
        guard !isHidden,!busy else {return false}
        if event.keyCode==48 {
            let backwards=event.modifierFlags.contains(.shift)
            let index=keyboardIndex.map{($0+(backwards ? -1 : 1)+controls.count)%controls.count} ?? (backwards ? controls.count-1 : 0)
            clearKeyboardFocus();keyboardIndex=index
            controls[index].keyboardFocused=true
            window?.makeFirstResponder(controls[index])
            return true
        }
        if (event.keyCode==36 || event.keyCode==49),let index=keyboardIndex {
            controls[index].performClick(nil);return true
        }
        return false
    }
    func launchStarted(_ browser:BrowserKind) {
        busy=true;clearKeyboardFocus();statusText=L("Opening %@…",browser.displayName);statusIsError=false;updateStatus();updateEnabled()
    }
    func showFailure(_ text:String) {
        busy=false;statusText=text;statusIsError=true;updateStatus();updateEnabled()
    }
    private func updateStatus() {MonitorTypography.applyFeedback(status,value:statusText,scale:typeScale,color:statusIsError ? MonitorPalette.error : MonitorPalette.secondary)}
    func updateMode() {
        half.selectionState=mode == .half
        full.selectionState=mode == .full
        half.foreground=mode == .half ? MonitorPalette.ink : MonitorPalette.secondary
        full.foreground=mode == .full ? MonitorPalette.ink : MonitorPalette.secondary
        half.setAccessibilityValue(mode == .half ? 1 : 0)
        full.setAccessibilityValue(mode == .full ? 1 : 0)
        half.needsDisplay=true;full.needsDisplay=true
    }
    private func updateEnabled() {
        [chrome!,safari!,half!,full!,close!].forEach{$0.isEnabled = !busy; $0.needsDisplay=true}
    }
    @objc private func pickChrome() {choose(.chrome)}
    @objc private func pickSafari() {choose(.safari)}
    @objc private func pickHalf() {if !busy {mode = .half;updateMode()}}
    @objc private func pickFull() {if !busy {mode = .full;updateMode()}}
    @objc func cancel() {if !busy {onCancel?()}}
    private func choose(_ browser:BrowserKind) {if !busy {onChoose?(browser,mode)}}
    func testControls() {
        let previous=onChoose
        var picked: [(BrowserKind,WindowMode)]=[]
        onChoose={picked.append(($0,$1))}
        precondition(controls.allSatisfy{ $0.focusRingType == .none && !$0.keyboardFocused })
        if let tab=NSEvent.keyEvent(with:.keyDown,location:.zero,modifierFlags:[],timestamp:0,windowNumber:0,context:nil,characters:"\t",charactersIgnoringModifiers:"\t",isARepeat:false,keyCode:48) {
            precondition(handleKeyboard(tab) && half.keyboardFocused && !chrome.keyboardFocused)
            precondition(handleKeyboard(tab) && full.keyboardFocused && !half.keyboardFocused)
            precondition(handleKeyboard(tab) && chrome.keyboardFocused)
            precondition(handleKeyboard(tab) && safari.keyboardFocused)
            precondition(handleKeyboard(tab) && close.keyboardFocused)
            clearKeyboardFocus()
        }
        full.performClick(nil); chrome.performClick(nil)
        half.performClick(nil); safari.performClick(nil)
        precondition(picked.count==2 && picked[0].0 == .chrome && picked[0].1 == .full && picked[1].0 == .safari && picked[1].1 == .half)
        launchStarted(.chrome)
        precondition(busy && !chrome.isEnabled && !safari.isEnabled)
        showFailure("测试启动失败")
        precondition(!busy && chrome.isEnabled && safari.isEnabled)
        present();onChoose=previous
    }
    func testTypography() {
        layoutSubtreeIfNeeded()
        precondition(chrome.frame.maxY<=safari.frame.minY && safari.frame.maxY<=status.frame.minY)
        precondition(half.frame.maxX<=full.frame.minX && half.frame.maxY<=browserPanel.minY)
        precondition(controls.allSatisfy{bounds.insetBy(dx:-0.1,dy:-0.1).contains($0.frame)})
        let values=[L("Opening %@…","Chrome"),L("%@ is not installed. Choose another browser.","Safari"),L("Could not open %@. Try again.","Chrome"),L("If no window appears, press ⌘N.")+"\n"+L("Use window controls to resize.")]
        for control in controls {
            let (text,_,space)=control.labelComposition()
            precondition(text.size().width+space <= control.bounds.width+0.1 && text.size().height <= control.bounds.height+0.1)
        }
        precondition(title.attributedStringValue.size().width<=title.bounds.width+0.1 && title.attributedStringValue.size().height<=title.bounds.height+0.1)
        for value in values {
            showFailure(value)
            let size=MonitorTypography.measured(status.attributedStringValue,width:status.bounds.width,wrapping:true)
            precondition(size.width<=status.bounds.width+0.1 && size.height<=status.bounds.height+0.1)
        }
        present()
    }
}
