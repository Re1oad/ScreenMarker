import Cocoa
import Carbon.HIToolbox

// MARK: - Drawing

struct Stroke {
    var points: [NSPoint]
    var color: NSColor
    var width: CGFloat
}

final class CanvasView: NSView {
    var strokes: [Stroke] = []
    var current: Stroke?
    var color: NSColor = .systemRed
    var lineWidth: CGFloat = 4
    var onEscape: (() -> Void)?

    override var acceptsFirstResponder: Bool { true }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func resetCursorRects() {
        addCursorRect(bounds, cursor: .crosshair)
    }

    override func mouseDown(with event: NSEvent) {
        let p = convert(event.locationInWindow, from: nil)
        current = Stroke(points: [p], color: color, width: lineWidth)
        needsDisplay = true
    }

    override func mouseDragged(with event: NSEvent) {
        current?.points.append(convert(event.locationInWindow, from: nil))
        needsDisplay = true
    }

    override func mouseUp(with event: NSEvent) {
        if let s = current { strokes.append(s) }
        current = nil
        needsDisplay = true
    }

    override func keyDown(with event: NSEvent) {
        if event.keyCode == UInt16(kVK_Escape) {
            onEscape?()
        } else if event.modifierFlags.contains(.command), event.charactersIgnoringModifiers == "z" {
            undo()
        } else {
            super.keyDown(with: event)
        }
    }

    override func draw(_ dirtyRect: NSRect) {
        NSColor.clear.set()
        dirtyRect.fill()
        for s in strokes + (current.map { [$0] } ?? []) {
            s.color.set()
            if s.points.count == 1 {
                let p = s.points[0], r = s.width / 2
                NSBezierPath(ovalIn: NSRect(x: p.x - r, y: p.y - r, width: s.width, height: s.width)).fill()
                continue
            }
            let path = NSBezierPath()
            path.lineWidth = s.width
            path.lineCapStyle = .round
            path.lineJoinStyle = .round
            path.move(to: s.points[0])
            for p in s.points.dropFirst() { path.line(to: p) }
            path.stroke()
        }
    }

    func clear() {
        strokes.removeAll()
        current = nil
        needsDisplay = true
    }

    func undo() {
        _ = strokes.popLast()
        needsDisplay = true
    }
}

final class OverlayWindow: NSWindow {
    let canvas: CanvasView

    init(screen: NSScreen) {
        canvas = CanvasView(frame: NSRect(origin: .zero, size: screen.frame.size))
        super.init(contentRect: screen.frame, styleMask: .borderless, backing: .buffered, defer: false)
        setFrame(screen.frame, display: false)
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        // Just below the menu bar so the ScreenMarker menu stays clickable while drawing.
        level = NSWindow.Level(rawValue: NSWindow.Level.mainMenu.rawValue - 1)
        ignoresMouseEvents = true
        isReleasedWhenClosed = false
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        contentView = canvas
    }

    override var canBecomeKey: Bool { true }
}

// MARK: - Global hotkeys (Carbon; no Accessibility permission needed)

var hotKeyHandlers: [UInt32: () -> Void] = [:]

func installHotKeyHandler() {
    var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
    InstallEventHandler(GetApplicationEventTarget(), { _, event, _ in
        var hk = EventHotKeyID()
        GetEventParameter(event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID),
                          nil, MemoryLayout<EventHotKeyID>.size, nil, &hk)
        DispatchQueue.main.async { hotKeyHandlers[hk.id]?() }
        return noErr
    }, 1, &spec, nil, nil)
}

func registerHotKey(id: UInt32, keyCode: Int, handler: @escaping () -> Void) {
    var ref: EventHotKeyRef?
    let hkID = EventHotKeyID(signature: OSType(0x534D_4B52), id: id) // 'SMKR'
    RegisterEventHotKey(UInt32(keyCode), UInt32(controlKey | optionKey), hkID, GetApplicationEventTarget(), 0, &ref)
    hotKeyHandlers[id] = handler
}

// MARK: - App

final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    var overlays: [OverlayWindow] = []
    var statusItem: NSStatusItem!
    var menu: NSMenu!
    var drawItem: NSMenuItem!
    var colorItems: [NSMenuItem] = []
    var widthItems: [NSMenuItem] = []
    var drawing = false
    var color: NSColor = .systemRed
    var lineWidth: CGFloat = 4

    let palette: [(String, NSColor)] = [("Red", .systemRed), ("Orange", .systemOrange), ("Yellow", .systemYellow),
                                        ("Green", .systemGreen), ("Blue", .systemBlue), ("White", .white), ("Black", .black)]
    let widths: [(String, CGFloat)] = [("Small", 2), ("Medium", 4), ("Large", 8)]

    func applicationDidFinishLaunching(_ notification: Notification) {
        buildStatusItem()
        buildOverlays()
        NotificationCenter.default.addObserver(self, selector: #selector(screensChanged),
                                               name: NSApplication.didChangeScreenParametersNotification, object: nil)
        installHotKeyHandler()
        registerHotKey(id: 1, keyCode: kVK_ANSI_D) { [weak self] in self?.togglePen() }
        registerHotKey(id: 2, keyCode: kVK_ANSI_X) { [weak self] in self?.clearAll() }
        registerHotKey(id: 3, keyCode: kVK_ANSI_Z) { [weak self] in self?.undo() }
        registerHotKey(id: 4, keyCode: kVK_ANSI_M) { [weak self] in self?.showMenuAtMouse() }
    }

    func buildOverlays() {
        overlays.forEach { $0.orderOut(nil) }
        overlays = NSScreen.screens.map { screen in
            let w = OverlayWindow(screen: screen)
            w.canvas.color = color
            w.canvas.lineWidth = lineWidth
            w.canvas.onEscape = { [weak self] in self?.setDrawing(false) }
            w.canvas.menu = menu // right-click while drawing
            w.ignoresMouseEvents = !drawing
            w.orderFrontRegardless()
            return w
        }
    }

    @objc func screensChanged() { buildOverlays() }

    func buildStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        updateStatusIcon()

        menu = NSMenu()
        menu.delegate = self
        drawItem = item("Draw", #selector(togglePen), key: "d")
        menu.addItem(drawItem)
        menu.addItem(.separator())

        colorItems = palette.enumerated().map { i, entry in
            let mi = item(entry.0, #selector(pickColor(_:)))
            mi.tag = i
            mi.image = swatch(entry.1)
            return mi
        }
        colorItems.forEach(menu.addItem)
        menu.addItem(.separator())

        widthItems = widths.enumerated().map { i, entry in
            let mi = item(entry.0, #selector(pickWidth(_:)))
            mi.tag = i
            return mi
        }
        widthItems.forEach(menu.addItem)
        menu.addItem(.separator())

        menu.addItem(item("Undo", #selector(undo), key: "z"))
        menu.addItem(item("Erase All", #selector(clearAll), key: "x"))
        menu.addItem(.separator())
        menu.addItem(item("Show This Menu", #selector(showMenuAtMouse), key: "m"))
        let hint = NSMenuItem(title: "Or right-click while drawing", action: nil, keyEquivalent: "")
        hint.isEnabled = false
        menu.addItem(hint)
        menu.addItem(.separator())
        let quit = NSMenuItem(title: "Quit ScreenMarker", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        menu.addItem(quit)

        statusItem.menu = menu
    }

    /// Menu item whose shortcut label shows the global ⌃⌥ hotkey.
    func item(_ title: String, _ action: Selector, key: String = "") -> NSMenuItem {
        let mi = NSMenuItem(title: title, action: action, keyEquivalent: key)
        mi.target = self
        if !key.isEmpty { mi.keyEquivalentModifierMask = [.control, .option] }
        return mi
    }

    func swatch(_ c: NSColor) -> NSImage {
        NSImage(size: NSSize(width: 14, height: 14), flipped: false) { rect in
            let dot = NSBezierPath(ovalIn: rect.insetBy(dx: 1, dy: 1))
            c.setFill()
            dot.fill()
            NSColor.gray.withAlphaComponent(0.7).setStroke()
            dot.lineWidth = 1
            dot.stroke()
            return true
        }
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        drawItem.state = drawing ? .on : .off
        for (i, mi) in colorItems.enumerated() { mi.state = palette[i].1 == color ? .on : .off }
        for (i, mi) in widthItems.enumerated() { mi.state = widths[i].1 == lineWidth ? .on : .off }
    }

    func updateStatusIcon() {
        guard let button = statusItem?.button else { return }
        let name = drawing ? "pencil.tip.crop.circle.fill" : "pencil.tip.crop.circle"
        button.image = NSImage(systemSymbolName: name, accessibilityDescription: "ScreenMarker")
        button.contentTintColor = drawing ? color : nil
        button.toolTip = drawing ? "ScreenMarker: drawing (Esc or ⌃⌥D to stop)" : "ScreenMarker"
    }

    func setDrawing(_ on: Bool) {
        drawing = on
        overlays.forEach { $0.ignoresMouseEvents = !on }
        if on {
            NSApp.activate(ignoringOtherApps: true)
            let mouse = NSEvent.mouseLocation
            let target = overlays.first { $0.frame.contains(mouse) } ?? overlays.first
            target?.makeKeyAndOrderFront(nil)
            target?.makeFirstResponder(target?.canvas)
            overlays.forEach { $0.invalidateCursorRects(for: $0.canvas) }
        } else {
            NSApp.deactivate()
            NSCursor.arrow.set()
        }
        updateStatusIcon()
    }

    @objc func togglePen() { setDrawing(!drawing) }

    /// Pops the menu up at the pointer, for when the menu bar is hidden (full-screen slide shows).
    @objc func showMenuAtMouse() {
        NSApp.activate(ignoringOtherApps: true)
        menu.popUp(positioning: nil, at: NSEvent.mouseLocation, in: nil)
        if !drawing { NSApp.deactivate() }
    }

    @objc func pickColor(_ sender: NSMenuItem) {
        color = palette[sender.tag].1
        overlays.forEach { $0.canvas.color = color }
        if !drawing { setDrawing(true) } else { updateStatusIcon() }
    }

    @objc func pickWidth(_ sender: NSMenuItem) {
        lineWidth = widths[sender.tag].1
        overlays.forEach { $0.canvas.lineWidth = lineWidth }
    }

    @objc func undo() {
        // Undo on the screen the mouse is on.
        let mouse = NSEvent.mouseLocation
        (overlays.first { $0.frame.contains(mouse) } ?? overlays.first)?.canvas.undo()
    }

    @objc func clearAll() { overlays.forEach { $0.canvas.clear() } }
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.accessory)
app.run()
