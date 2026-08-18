import AppKit
import ApplicationServices

/// ⌃⌘ を押しながらウィンドウをドラッグしたときに、離した位置のゾーンへ吸着させる。
///
/// グローバルイベント監視（他アプリのマウス操作も観測できる）で実現する。
/// マウスイベントは奪わない（クリックスルー）ので、ドラッグ自体は通常どおり行われ、
/// 指を離した瞬間にウィンドウをグリッドへ配置し直す。
///
/// 画面の端・隅は「半分 / 四分割 / 最大化」に、内側はポインタ直下のセルに解決する。
final class DragSnapMonitor {

    static let shared = DragSnapMonitor()

    private var dragMonitor: Any?
    private var upMonitor: Any?
    private var flagsMonitor: Any?

    private var active = false
    private var draggedWindow: AXUIElement?
    private var currentScreen: NSScreen?
    private var overlay: DragOverlayWindow?
    private var highlight: GridZone?
    /// 範囲選択の追加キーを押した瞬間のセル（ここから現在セルまでを範囲選択する）。
    private var anchorCell: (col: Int, row: Int)?
    /// 範囲選択モード中か（スナップ修飾キーに加えて追加キーを押している間だけ true）。
    private var selecting = false

    private let windowController = WindowController()

    private init() {}

    /// 監視を開始する。
    func start() {
        guard dragMonitor == nil else { return }
        dragMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDragged]) { [weak self] e in
            self?.handleDrag(e)
        }
        upMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseUp]) { [weak self] _ in
            self?.handleUp()
        }
        flagsMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.flagsChanged]) { [weak self] e in
            guard let self, self.active else { return }
            // ⌃⌘ を離したらキャンセル。
            guard Self.modifierHeld(e.modifierFlags) else { self.cancel(); return }
            // ドラッグせずに ⌥ を押下/解放しただけでも選択状態を更新する。
            let mouse = NSEvent.mouseLocation
            guard let screen = self.currentScreen ?? NSScreen.screens.first(where: { $0.frame.contains(mouse) }) else { return }
            self.updateSelection(flags: e.modifierFlags, mouse: mouse, screen: screen,
                                 spec: SettingsStore.shared.settings.gridSpec(for: screen))
        }
    }

    // MARK: - イベント処理

    private static func modifierHeld(_ flags: NSEvent.ModifierFlags) -> Bool {
        // スナップ開始の修飾キー（既定は Control。OS 標準の Option ドラッグと競合しない）。
        flags.contains(SettingsStore.shared.settings.dragSnapModifier.eventFlag)
    }

    /// 範囲選択の追加キーが押されているか（既定は Command）。
    private static func rangeHeld(_ flags: NSEvent.ModifierFlags) -> Bool {
        flags.contains(SettingsStore.shared.settings.dragRangeModifier.eventFlag)
    }

    private func handleDrag(_ event: NSEvent) {
        guard SettingsStore.shared.settings.dragSnapEnabled else { return }

        // 修飾キーが押されていなければ、進行中のセッションを閉じる。
        guard Self.modifierHeld(event.modifierFlags) else {
            if active { cancel() }
            return
        }

        let mouse = NSEvent.mouseLocation
        guard let screen = NSScreen.screens.first(where: { $0.frame.contains(mouse) }) ?? NSScreen.main else { return }
        let spec = SettingsStore.shared.settings.gridSpec(for: screen)

        if !active {
            // セッション開始: ポインタ直下のウィンドウを捕まえる（単一セルから開始）。
            draggedWindow = windowElement(atAppKit: mouse)
            guard draggedWindow != nil else { return }
            active = true
            selecting = false
            anchorCell = nil
            currentScreen = screen
            showOverlay(on: screen)
        } else if screen != currentScreen {
            // 別スクリーンへ移ったらオーバーレイと選択状態を取り直す。
            currentScreen = screen
            selecting = false
            anchorCell = nil
            showOverlay(on: screen)
        }

        updateSelection(flags: event.modifierFlags, mouse: mouse, screen: screen, spec: spec)
    }

    /// ハイライトを更新する。
    /// ⌥ を押している間だけ範囲選択（⌥ を押した瞬間のセルを基準）、
    /// それ以外はポインタ直下の単一セル。
    private func updateSelection(flags: NSEvent.ModifierFlags, mouse: CGPoint, screen: NSScreen, spec: GridSpec) {
        let current = cell(at: mouse, on: screen, spec: spec)
        if Self.rangeHeld(flags) {
            if !selecting {
                selecting = true
                anchorCell = current   // 追加キーを押した位置を範囲の基準にする
            }
            highlight = zone(from: anchorCell ?? current, to: current)
        } else {
            selecting = false
            anchorCell = nil
            highlight = zone(from: current, to: current)  // 単一セル
        }
        overlay?.gridView?.setHighlight(highlight)
    }

    private func handleUp() {
        guard active else { return }
        defer { teardown() }
        guard let window = draggedWindow, let screen = currentScreen, let zone = highlight else { return }
        let spec = SettingsStore.shared.settings.gridSpec(for: screen)
        windowController.place(zone: zone, spec: spec, on: screen, window: window)
    }

    private func cancel() { teardown() }

    private func teardown() {
        active = false
        draggedWindow = nil
        currentScreen = nil
        highlight = nil
        anchorCell = nil
        selecting = false
        overlay?.orderOut(nil)
        overlay = nil
    }

    private func showOverlay(on screen: NSScreen) {
        overlay?.orderOut(nil)
        let ov = DragOverlayWindow(screen: screen, spec: SettingsStore.shared.settings.gridSpec(for: screen))
        ov.orderFrontRegardless()
        overlay = ov
    }

    // MARK: - セル座標・範囲

    /// ポインタ位置（AppKit グローバル座標）が属するグリッドセルを返す。
    private func cell(at mouse: CGPoint, on screen: NSScreen, spec: GridSpec) -> (col: Int, row: Int) {
        let s = spec.clamped()
        let work = screen.visibleFrame
        let cellW = work.width / CGFloat(s.cols)
        let cellH = work.height / CGFloat(s.rows)
        let col = Int((mouse.x - work.minX) / cellW)
        let rowFromBottom = Int((mouse.y - work.minY) / cellH)
        let row = s.rows - 1 - rowFromBottom  // 上端が row 0
        return (min(max(col, 0), s.cols - 1), min(max(row, 0), s.rows - 1))
    }

    /// 2 つのセルを対角とする矩形ゾーンを返す。
    private func zone(from a: (col: Int, row: Int), to b: (col: Int, row: Int)) -> GridZone {
        let col = min(a.col, b.col)
        let row = min(a.row, b.row)
        let colSpan = abs(a.col - b.col) + 1
        let rowSpan = abs(a.row - b.row) + 1
        return GridZone(col: col, row: row, colSpan: colSpan, rowSpan: rowSpan)
    }

    // MARK: - ポインタ直下のウィンドウ取得

    private func windowElement(atAppKit point: CGPoint) -> AXUIElement? {
        let systemWide = AXUIElementCreateSystemWide()
        // AX 座標（主ディスプレイ左上原点）へ変換。
        let axY = Geometry.primaryHeight - point.y
        var element: AXUIElement?
        let result = AXUIElementCopyElementAtPosition(systemWide, Float(point.x), Float(axY), &element)
        guard result == .success, let element else { return nil }
        return topLevelWindow(from: element)
    }

    private func topLevelWindow(from element: AXUIElement) -> AXUIElement? {
        if role(of: element) == (kAXWindowRole as String) { return element }
        var ref: CFTypeRef?
        if AXUIElementCopyAttributeValue(element, kAXWindowAttribute as CFString, &ref) == .success, let ref {
            return (ref as! AXUIElement)
        }
        if AXUIElementCopyAttributeValue(element, kAXTopLevelUIElementAttribute as CFString, &ref) == .success, let ref {
            return (ref as! AXUIElement)
        }
        return nil
    }

    private func role(of element: AXUIElement) -> String? {
        var ref: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXRoleAttribute as CFString, &ref) == .success else { return nil }
        return ref as? String
    }
}

// MARK: - クリックスルーのオーバーレイ

/// マウスを奪わずグリッドとハイライトだけ描く透明ウィンドウ。
final class DragOverlayWindow: NSWindow {

    private(set) var gridView: DragOverlayView?

    init(screen: NSScreen, spec: GridSpec) {
        super.init(contentRect: screen.frame, styleMask: .borderless, backing: .buffered, defer: false)
        isOpaque = false
        backgroundColor = .clear
        level = .screenSaver
        ignoresMouseEvents = true      // ← ドラッグを邪魔しない
        hasShadow = false
        collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary]

        let work = CGRect(
            x: screen.visibleFrame.minX - screen.frame.minX,
            y: screen.visibleFrame.minY - screen.frame.minY,
            width: screen.visibleFrame.width,
            height: screen.visibleFrame.height
        )
        let view = DragOverlayView(frame: CGRect(origin: .zero, size: screen.frame.size), workArea: work, spec: spec)
        contentView = view
        gridView = view
    }

    override var canBecomeKey: Bool { false }
}

/// ドラッグスナップ用の描画ビュー（ハイライトは外部から設定）。
final class DragOverlayView: NSView {

    private let spec: GridSpec
    private let workArea: CGRect
    private var highlight: GridZone?

    init(frame: CGRect, workArea: CGRect, spec: GridSpec) {
        self.spec = spec.clamped()
        self.workArea = workArea
        super.init(frame: frame)
    }

    required init?(coder: NSCoder) { fatalError() }

    func setHighlight(_ zone: GridZone?) {
        highlight = zone
        needsDisplay = true
    }

    private var gridArea: CGRect {
        workArea.insetBy(dx: CGFloat(SettingsStore.shared.settings.outerMargin),
                         dy: CGFloat(SettingsStore.shared.settings.outerMargin))
    }

    private func rect(for zone: GridZone) -> CGRect {
        let area = gridArea
        let cellW = area.width / CGFloat(spec.cols)
        let cellH = area.height / CGFloat(spec.rows)
        let x = area.minX + CGFloat(zone.col) * cellW
        let w = cellW * CGFloat(zone.colSpan)
        let topOffset = CGFloat(zone.row) * cellH
        let h = cellH * CGFloat(zone.rowSpan)
        let y = area.maxY - topOffset - h
        return CGRect(x: x, y: y, width: w, height: h)
    }

    override func draw(_ dirtyRect: CGRect) {
        let area = gridArea

        // 薄い枠。
        NSColor.white.withAlphaComponent(0.25).setStroke()
        let grid = NSBezierPath()
        grid.lineWidth = 1
        let cellW = area.width / CGFloat(spec.cols)
        let cellH = area.height / CGFloat(spec.rows)
        for c in 0...spec.cols {
            let x = area.minX + CGFloat(c) * cellW
            grid.move(to: CGPoint(x: x, y: area.minY)); grid.line(to: CGPoint(x: x, y: area.maxY))
        }
        for r in 0...spec.rows {
            let y = area.minY + CGFloat(r) * cellH
            grid.move(to: CGPoint(x: area.minX, y: y)); grid.line(to: CGPoint(x: area.maxX, y: y))
        }
        grid.stroke()

        // ハイライト（半透明の白）。
        if let zone = highlight {
            let r = rect(for: zone)
            NSColor.white.withAlphaComponent(0.35).setFill()
            r.fill()
            NSColor.white.withAlphaComponent(0.9).setStroke()
            let border = NSBezierPath(rect: r)
            border.lineWidth = 2
            border.stroke()
        }
    }
}
