import AppKit
import ScreenCaptureKit
import Combine

/// Owns selection and floating panels independently of Topit's whole-window overlays.
final class RegionPinManager: ObservableObject {
    static let shared = RegionPinManager()
    private var selection: RegionSelectionController?
    private var selectionRequest: UUID?
    private var panels = [UUID: RegionPanelController]()
    @Published private(set) var autoHideEnabled = false
    private var autoHideGesture = RegionAutoHideGesture()
    private var localEvents: Any?
    private var globalEvents: Any?
    private var proximityTimer: Timer?

    func startMonitoring() {
        guard localEvents == nil else { return }
        let mask: NSEvent.EventTypeMask = [.flagsChanged, .keyDown, .leftMouseDown, .rightMouseDown, .otherMouseDown, .scrollWheel]
        localEvents = NSEvent.addLocalMonitorForEvents(matching: mask) { [weak self] event in
            self?.handleAutoHideGesture(event)
            return event
        }
        globalEvents = NSEvent.addGlobalMonitorForEvents(matching: mask) { [weak self] event in
            self?.handleAutoHideGesture(event)
        }
    }

    private func handleAutoHideGesture(_ event: NSEvent) {
        guard event.type == .flagsChanged else { autoHideGesture.cancel(); return }
        let flags = event.modifierFlags
        let otherModifiers: NSEvent.ModifierFlags = [.shift, .option, .command, .function]
        if autoHideGesture.modifiersChanged(control: flags.contains(.control),
                                            otherModifiers: !flags.intersection(otherModifiers).isEmpty,
                                            timestamp: event.timestamp) {
            setAutoHideEnabled(!autoHideEnabled)
        }
    }

    func setAutoHideEnabled(_ enabled: Bool) {
        guard enabled != autoHideEnabled else { return }
        autoHideGesture.reset()
        autoHideEnabled = enabled
        for controller in panels.values { controller.setAutoHideEnabled(enabled) }
        updateProximityTimer()
    }

    private func updateProximityTimer() {
        proximityTimer?.invalidate()
        proximityTimer = nil
        guard autoHideEnabled, !panels.isEmpty else { return }
        let timer = Timer(timeInterval: 0.05, repeats: true) { [weak self] _ in
            guard let self else { return }
            let pointer = NSEvent.mouseLocation
            for controller in self.panels.values { controller.updateAutoHide(pointer: pointer) }
        }
        RunLoop.main.add(timer, forMode: .common)
        proximityTimer = timer
    }

    func selectRegion(in window: SCWindow) {
        selectRegion(windowID: window.windowID)
    }

    func selectRegion(windowID: CGWindowID) {
        selection?.close()
        closeMainWindow()
        let request = UUID()
        selectionRequest = request
        // Thumbnail entries can be stale after a source window moves or resizes.
        SCShareableContent.getExcludingDesktopWindows(false, onScreenWindowsOnly: true) { content, error in
            DispatchQueue.main.async { [weak self] in
                guard let self, self.selectionRequest == request else { return }
                self.selectionRequest = nil
                guard let source = content?.windows.first(where: { $0.windowID == windowID }) else {
                    createAlert(title: "Region Capture", message: error?.localizedDescription ?? "This window is not available!".local, button1: "OK").runModal()
                    return
                }
                let controller = RegionSelectionController(source: source)
                self.selection = controller
                controller.onFinish = { [weak self, weak controller] region in
                    guard let self, self.selection === controller else { return }
                    self.selection = nil
                    if let region { self.pin(window: source, region: region) }
                }
                controller.show()
            }
        }
    }

    private func pin(window: SCWindow, region: CGRect) {
        let id = UUID()
        let controller = RegionPanelController(source: window, region: region)
        panels[id] = controller
        controller.onClose = { [weak self] in
            self?.panels.removeValue(forKey: id)
            self?.updateProximityTimer()
        }
        controller.setAutoHideEnabled(autoHideEnabled)
        controller.show()
        updateProximityTimer()
    }

    func cancelSelection() {
        selectionRequest = nil
        selection?.close()
        selection = nil
    }

    func closeAll() {
        cancelSelection()
        for panel in Array(panels.values) { panel.close() }
    }
}

final class RegionSelectionController: NSObject, NSWindowDelegate {
    let source: SCWindow
    var onFinish: ((CGRect?) -> Void)?
    private let panel: RegionPanel
    private let selectionView = RegionSelectionView()
    private let session = RegionCaptureSession()
    private var finished = false
    private var timeout: Timer?

    init(source: SCWindow) {
        self.source = source
        panel = RegionPanel(contentRect: CGRectTransform(cgRect: source.frame),
                            styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        super.init()
        panel.title = "Topit Region Selection"
        panel.allowsKeyboardFocus = true
        panel.level = .screenSaver
        panel.isReleasedWhenClosed = false
        panel.backgroundColor = .black
        panel.hasShadow = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.contentView = selectionView
        panel.delegate = self
        panel.onCancel = { [weak self] in self?.close() }
        selectionView.onSelection = { [weak self] region in self?.finish(region) }
        session.onImage = { [weak self] image in
            guard let self, !self.finished else { return }
            self.timeout?.invalidate()
            self.selectionView.image = NSImage(cgImage: image, size: self.source.frame.size)
            self.selectionView.needsDisplay = true
            self.session.stop()
        }
        session.onError = { [weak self] error in self?.fail(error.localizedDescription) }
    }

    func show() {
        panel.makeKeyAndOrderFront(nil)
        panel.makeFirstResponder(selectionView)
        timeout = Timer.scheduledTimer(withTimeInterval: 10, repeats: false) { [weak self] _ in
            self?.fail("Could not capture this window. Check Screen Recording permission and try again.".local)
        }
        Task { await session.start(window: source) }
    }

    func close() { panel.close() }

    private func finish(_ region: CGRect?) {
        guard !finished else { return }
        finished = true
        timeout?.invalidate()
        session.stop()
        panel.close()
        onFinish?(region)
    }

    private func fail(_ message: String) {
        guard !finished else { return }
        finish(nil)
        createAlert(title: "Region Capture", message: message, button1: "OK").runModal()
    }

    func windowWillClose(_ notification: Notification) { finish(nil) }
}

final class RegionSelectionView: NSView {
    var image: NSImage?
    var onSelection: ((CGRect) -> Void)?
    private var start: CGPoint?
    private var selection: CGRect = .zero
    override var isFlipped: Bool { true }
    override var acceptsFirstResponder: Bool { true }

    override func resetCursorRects() { addCursorRect(bounds, cursor: .crosshair) }

    override func draw(_ dirtyRect: NSRect) {
        NSColor.black.setFill()
        bounds.fill()
        image?.draw(in: bounds, from: .zero, operation: .sourceOver, fraction: 1, respectFlipped: true, hints: nil)
        let shade = NSBezierPath(rect: bounds)
        if !selection.isEmpty { shade.appendRect(selection) }
        shade.windingRule = .evenOdd
        NSColor.black.withAlphaComponent(0.42).setFill()
        shade.fill()
        if !selection.isEmpty {
            NSColor.white.setStroke()
            let border = NSBezierPath(rect: selection.insetBy(dx: 0.5, dy: 0.5))
            border.lineWidth = 1
            border.stroke()
        }
        let text = image == nil ? "Preparing window capture…".local :
            ("Drag to select a region • Release to pin • Esc to cancel".local +
             (selection.isEmpty ? "" : "  \(Int(selection.width)) × \(Int(selection.height))"))
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 14, weight: .medium), .foregroundColor: NSColor.white
        ]
        let size = (text as NSString).size(withAttributes: attributes)
        let width = min(bounds.width - 16, size.width + 24)
        let box = CGRect(x: max(8, (bounds.width - width) / 2), y: 12, width: width, height: size.height + 16)
        NSColor.black.withAlphaComponent(0.8).setFill()
        NSBezierPath(roundedRect: box, xRadius: 8, yRadius: 8).fill()
        (text as NSString).draw(in: box.insetBy(dx: 12, dy: 8), withAttributes: attributes)
    }

    override func mouseDown(with event: NSEvent) {
        guard image != nil else { return }
        start = convert(event.locationInWindow, from: nil)
        selection = .zero
        needsDisplay = true
    }

    override func mouseDragged(with event: NSEvent) {
        guard let start else { return }
        selection = RegionGeometry.selection(from: start, to: convert(event.locationInWindow, from: nil), in: bounds)
        needsDisplay = true
    }

    override func mouseUp(with event: NSEvent) {
        guard let start else { return }
        selection = RegionGeometry.selection(from: start, to: convert(event.locationInWindow, from: nil), in: bounds)
        self.start = nil
        if let region = RegionGeometry.normalized(selection, in: bounds.size) { onSelection?(region) }
        needsDisplay = true
    }
}

final class RegionPanelController: NSObject, NSWindowDelegate {
    var onClose: (() -> Void)?
    private let source: SCWindow
    private let region: CGRect
    private let panel: RegionPanel
    private let preview = RegionPreviewView()
    private var session: RegionCaptureSession?
    private var frozen = false
    private var closed = false
    private var sourceTimer: Timer?
    private let input: RegionInputRouter
    private var localModifiers: Any?
    private var globalModifiers: Any?
    private var autoHideEnabled = false
    private var proximityHidden = false
    private var visibleOpacity: CGFloat = 1

    init(source: SCWindow, region: CGRect) {
        self.source = source
        self.region = region
        input = RegionInputRouter(windowID: source.windowID, processID: source.owningApplication?.processID ?? 0, region: region)
        let sourceRect = CGRect(x: source.frame.minX + source.frame.width * region.minX,
                                y: source.frame.minY + source.frame.height * region.minY,
                                width: source.frame.width * region.width, height: source.frame.height * region.height)
        panel = RegionPanel(contentRect: CGRectTransform(cgRect: sourceRect),
                            styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        super.init()
        panel.title = "Topit Layer Region \(UUID().uuidString)"
        panel.level = .floating
        panel.isReleasedWhenClosed = false
        panel.backgroundColor = .black
        panel.hasShadow = true
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.contentAspectRatio = sourceRect.size
        let factor = max(64 / sourceRect.width, 40 / sourceRect.height)
        panel.contentMinSize = CGSize(width: sourceRect.width * min(factor, 1), height: sourceRect.height * min(factor, 1))
        panel.contentView = preview
        panel.becomesKeyOnlyIfNeeded = true
        panel.hidesOnDeactivate = false
        panel.isExcludedFromWindowsMenu = false
        panel.acceptsMouseMovedEvents = true
        panel.delegate = self
        panel.onCancel = { [weak self] in self?.close() }
        preview.onClose = { [weak self] in self?.close() }
        preview.onFreeze = { [weak self] in self?.toggleFreeze() }
        preview.onFocus = { [weak self] in self?.focusSource() }
        preview.onMouse = { [weak self] event, point, size in self?.input.mouse(event, point: point, viewSize: size) }
        preview.onBeginInteraction = { [weak self] in self?.updateEditMode(false) }
        preview.onReleaseInput = { [weak self] in self?.input.releaseInput() }
        input.onFocusFailure = { [weak self] in
            self?.preview.message = "Could not focus the source window without raising it.".local
        }
    }

    func show() {
        NSApp.addWindowsItem(panel, title: "Region Capture".local + " — " + (source.title ?? ""), filename: false)
        panel.orderFrontRegardless()
        updateEditMode(NSEvent.modifierFlags.contains(.shift))
        localModifiers = NSEvent.addLocalMonitorForEvents(matching: .flagsChanged) { [weak self] event in
            self?.updateEditMode(event.modifierFlags.contains(.shift))
            return event
        }
        globalModifiers = NSEvent.addGlobalMonitorForEvents(matching: .flagsChanged) { [weak self] event in
            self?.updateEditMode(event.modifierFlags.contains(.shift))
        }
        startStream()
        sourceTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            guard let self, getCGWindowFrameWithID(self.source.windowID) == nil else { return }
            self.input.endNativeInput()
            self.session?.stop()
            self.session = nil
            self.sourceTimer?.invalidate()
            self.preview.message = "Source window closed • Last frame kept".local
            self.frozen = true
            self.preview.isFrozen = true
        }
    }

    private func updateEditMode(_ editing: Bool) {
        let editing = editing && !autoHideEnabled
        panel.allowsKeyboardFocus = editing
        if editing && !preview.isEditing { input.releaseInput() }
        preview.isEditing = editing
        // Native edge resizing must never intercept a source click in interaction mode.
        if editing { panel.styleMask.insert(.resizable) }
        else { panel.styleMask.remove(.resizable) }
        if !editing && panel.isKeyWindow { panel.resignKey() }
        panel.invalidateCursorRects(for: preview)
    }

    func setAutoHideEnabled(_ enabled: Bool) {
        guard enabled != autoHideEnabled else { return }
        autoHideEnabled = enabled
        input.releaseInput()
        preview.isAutoHiding = enabled
        panel.allowsInteraction = !enabled
        panel.ignoresMouseEvents = enabled
        if enabled {
            input.endNativeInput()
            visibleOpacity = panel.alphaValue
            panel.makeFirstResponder(nil)
            if panel.isKeyWindow { panel.resignKey() }
            updateEditMode(false)
            updateAutoHide(pointer: NSEvent.mouseLocation)
        } else {
            proximityHidden = false
            setAutoHideOpacity(visibleOpacity)
            updateEditMode(NSEvent.modifierFlags.contains(.shift))
        }
    }

    func updateAutoHide(pointer: CGPoint) {
        guard autoHideEnabled else { return }
        let hidden = RegionAutoHideVisibility.shouldHide(pointer: pointer, frame: panel.frame, currentlyHidden: proximityHidden)
        guard hidden != proximityHidden else { return }
        proximityHidden = hidden
        setAutoHideOpacity(hidden ? 0 : visibleOpacity)
    }

    private func setAutoHideOpacity(_ opacity: CGFloat) {
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.12
            panel.animator().alphaValue = opacity
        }
    }

    private func startStream() {
        let session = RegionCaptureSession(region: region)
        self.session = session
        preview.message = nil
        session.onImage = { [weak self] image in
            guard let self else { return }
            self.preview.image = NSImage(cgImage: image, size: CGSize(width: image.width, height: image.height))
        }
        session.onError = { [weak self] _ in
            self?.input.endNativeInput()
            self?.preview.message = "Capture stopped • Click Resume to retry".local
            self?.frozen = true
            self?.preview.isFrozen = true
            self?.session?.stop()
            self?.session = nil
        }
        Task { await session.start(window: source) }
    }

    private func toggleFreeze() {
        guard !autoHideEnabled else { return }
        frozen.toggle()
        input.releaseInput()
        preview.isFrozen = frozen
        if frozen {
            input.endNativeInput()
            session?.stop()
            session = nil
        } else {
            startStream()
        }
    }

    private func focusSource() {
        guard !autoHideEnabled else { return }
        guard let app = source.owningApplication else { return }
        if let axWindow = getAXWindow(windowID: source.windowID) {
            AXUIElementPerformAction(axWindow, kAXRaiseAction as CFString)
        }
        NSRunningApplication(processIdentifier: app.processID)?.activate(options: .activateIgnoringOtherApps)
    }

    func close() { panel.close() }

    func windowDidResignKey(_ notification: Notification) {
        if preview.isEditing { input.releaseInput() }
    }

    func windowWillClose(_ notification: Notification) {
        guard !closed else { return }
        closed = true
        NSApp.removeWindowsItem(panel)
        input.endNativeInput()
        if let localModifiers { NSEvent.removeMonitor(localModifiers) }
        if let globalModifiers { NSEvent.removeMonitor(globalModifiers) }
        sourceTimer?.invalidate()
        session?.stop()
        session = nil
        onClose?()
    }
}

final class RegionPreviewView: NSView {
    var image: NSImage? { didSet { needsDisplay = true } }
    var message: String? { didSet { needsDisplay = true } }
    var isFrozen = false {
        didSet {
            freezeButton.title = (isFrozen ? "Resume" : "Freeze").local
            if isFrozen {
                onReleaseInput?()
                forwardingGesture = false
                forwardingRightGesture = false
                forwardingOtherGesture = false
            }
            updateControls()
        }
    }
    var isEditing = false { didSet { updateControls(); needsDisplay = true } }
    var isAutoHiding = false {
        didSet {
            if isAutoHiding {
                forwardingGesture = false
                forwardingRightGesture = false
                forwardingOtherGesture = false
                onReleaseInput?()
            }
            updateControls()
        }
    }
    var onMouse: ((NSEvent, CGPoint, CGSize) -> Void)?
    var onBeginInteraction: (() -> Void)?
    var onReleaseInput: (() -> Void)?
    private var hovering = false
    private var forwardingGesture = false
    private var forwardingRightGesture = false
    private var forwardingOtherGesture = false
    override var acceptsFirstResponder: Bool { isEditing && !isAutoHiding }
    override var needsPanelToBecomeKey: Bool { isEditing && !isAutoHiding }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { !isAutoHiding }
    override func hitTest(_ point: NSPoint) -> NSView? { isAutoHiding ? nil : super.hitTest(point) }
    var onClose: (() -> Void)?
    var onFreeze: (() -> Void)?
    var onFocus: (() -> Void)?
    private let controls = NSStackView()
    private let freezeButton = NSButton(title: "Freeze".local, target: nil, action: nil)
    private var tracking: NSTrackingArea?
    override var isFlipped: Bool { true }

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        layer?.masksToBounds = true
        controls.orientation = .horizontal
        controls.spacing = 4
        controls.wantsLayer = true
        controls.layer?.backgroundColor = NSColor.windowBackgroundColor.withAlphaComponent(0.94).cgColor
        controls.layer?.cornerRadius = 6
        controls.edgeInsets = NSEdgeInsets(top: 3, left: 3, bottom: 3, right: 3)
        controls.translatesAutoresizingMaskIntoConstraints = false
        let close = NSButton(image: NSImage(systemSymbolName: "xmark", accessibilityDescription: "Unpin Region".local)!, target: self, action: #selector(closeRegion))
        close.toolTip = "Unpin Region".local
        freezeButton.target = self
        freezeButton.action = #selector(freeze)
        let copy = NSButton(image: NSImage(systemSymbolName: "doc.on.doc", accessibilityDescription: "Copy Snapshot".local)!, target: self, action: #selector(copySnapshot))
        copy.toolTip = "Copy Snapshot".local
        for button in [close, freezeButton, copy] {
            button.bezelStyle = .inline
            button.setButtonType(.momentaryPushIn)
            controls.addArrangedSubview(button)
        }
        addSubview(controls)
        NSLayoutConstraint.activate([
            controls.topAnchor.constraint(equalTo: topAnchor, constant: 4),
            controls.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 4)
        ])
        controls.isHidden = true
        toolTip = "Interact with the source • Hold Shift to move, resize, or open panel controls".local
    }

    convenience init() { self.init(frame: .zero) }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func draw(_ dirtyRect: NSRect) {
        NSColor.black.setFill()
        bounds.fill()
        image?.draw(in: bounds, from: .zero, operation: .sourceOver, fraction: 1, respectFlipped: true, hints: nil)
        if isEditing {
            NSColor.controlAccentColor.setStroke()
            let border = NSBezierPath(rect: bounds.insetBy(dx: 1.5, dy: 1.5))
            border.lineWidth = 3
            border.stroke()
            let label = "Shift: Move / Resize".local
            (label as NSString).draw(at: CGPoint(x: 8, y: bounds.height - 23), withAttributes: [
                .foregroundColor: NSColor.white, .backgroundColor: NSColor.black.withAlphaComponent(0.8),
                .font: NSFont.systemFont(ofSize: 12, weight: .medium)
            ])
        }
        if let message {
            NSColor.black.withAlphaComponent(0.7).setFill()
            CGRect(x: 0, y: bounds.height - 42, width: bounds.width, height: 42).fill()
            (message as NSString).draw(in: CGRect(x: 8, y: bounds.height - 36, width: bounds.width - 16, height: 34),
                                      withAttributes: [.foregroundColor: NSColor.white, .font: NSFont.systemFont(ofSize: 12)])
        }
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let tracking { removeTrackingArea(tracking) }
        let area = NSTrackingArea(rect: .zero, options: [.activeAlways, .mouseEnteredAndExited, .mouseMoved, .inVisibleRect], owner: self)
        addTrackingArea(area)
        tracking = area
    }

    private func updateControls() {
        controls.isHidden = isAutoHiding || !(hovering && (isEditing || isFrozen))
    }

    override func resetCursorRects() {
        if isEditing { addCursorRect(bounds, cursor: .openHand) }
    }

    override func mouseEntered(with event: NSEvent) { hovering = true; updateControls() }
    override func mouseExited(with event: NSEvent) { hovering = false; updateControls() }
    override func mouseMoved(with event: NSEvent) {
        if !isEditing && !isFrozen { forwardMouse(event) }
    }

    override func mouseDown(with event: NSEvent) {
        guard !isAutoHiding else { return }
        if event.modifierFlags.contains(.shift) {
            window?.makeKey()
            window?.performDrag(with: event)
            return
        }
        guard !isFrozen else { return }
        onBeginInteraction?()
        message = nil
        forwardingGesture = true
        forwardMouse(event)
    }

    override func mouseDragged(with event: NSEvent) {
        if forwardingGesture { forwardMouse(event) }
    }
    override func mouseUp(with event: NSEvent) {
        if forwardingGesture { forwardMouse(event) }
        forwardingGesture = false
    }
    override func rightMouseDown(with event: NSEvent) {
        guard !isAutoHiding else { return }
        if event.modifierFlags.contains(.shift) || isFrozen {
            if let menu = menu(for: event) { NSMenu.popUpContextMenu(menu, with: event, for: self) }
        } else {
            forwardingRightGesture = true
            forwardMouse(event)
        }
    }
    override func rightMouseDragged(with event: NSEvent) { if forwardingRightGesture { forwardMouse(event) } }
    override func rightMouseUp(with event: NSEvent) {
        if forwardingRightGesture { forwardMouse(event) }
        forwardingRightGesture = false
    }
    override func otherMouseDown(with event: NSEvent) {
        if !isAutoHiding && !isEditing && !isFrozen { forwardingOtherGesture = true; forwardMouse(event) }
    }
    override func otherMouseDragged(with event: NSEvent) { if forwardingOtherGesture { forwardMouse(event) } }
    override func otherMouseUp(with event: NSEvent) {
        if forwardingOtherGesture { forwardMouse(event) }
        forwardingOtherGesture = false
    }
    override func scrollWheel(with event: NSEvent) { if !isEditing && !isFrozen { forwardMouse(event) } }
    override func resignFirstResponder() -> Bool {
        onReleaseInput?()
        return super.resignFirstResponder()
    }

    private func forwardMouse(_ event: NSEvent) {
        guard !isAutoHiding else { return }
        onMouse?(event, convert(event.locationInWindow, from: nil), bounds.size)
    }

    override func menu(for event: NSEvent) -> NSMenu? {
        guard !isAutoHiding else { return nil }
        let menu = NSMenu()
        for (title, action) in [(isFrozen ? "Resume" : "Freeze", #selector(freeze)),
                                ("Copy Snapshot", #selector(copySnapshot)),
                                ("Focus Source Window", #selector(focus)),
                                ("Unpin Region", #selector(closeRegion))] {
            let item = menu.addItem(withTitle: title.local, action: action, keyEquivalent: "")
            item.target = self
        }
        let opacity = NSMenuItem(title: "Opacity".local, action: nil, keyEquivalent: "")
        let submenu = NSMenu()
        for percent in [100, 80, 60, 40, 20] {
            let item = submenu.addItem(withTitle: "\(percent)%", action: #selector(setOpacity(_:)), keyEquivalent: "")
            item.tag = percent
            item.target = self
            item.state = Int((window?.alphaValue ?? 1) * 100) == percent ? .on : .off
        }
        opacity.submenu = submenu
        menu.addItem(opacity)
        return menu
    }

    @objc private func closeRegion() { if !isAutoHiding { onClose?() } }
    @objc private func freeze() { if !isAutoHiding { onFreeze?() } }
    @objc private func focus() { if !isAutoHiding { onFocus?() } }
    @objc private func setOpacity(_ sender: NSMenuItem) {
        if !isAutoHiding { window?.alphaValue = CGFloat(sender.tag) / 100 }
    }
    @objc private func copySnapshot() {
        guard !isAutoHiding, let image else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.writeObjects([image])
    }
}
