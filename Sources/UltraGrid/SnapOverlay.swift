import AppKit
import ApplicationServices

/// グリッドを画面に重ねて表示し、ドラッグでセル範囲を選ぶ「スナップピッカー」。
///
/// ホットキー（既定 ⌃⌥Space）で呼び出すと、カーソルのあるスクリーンに 6×6
/// グリッドが半透明で重なる。セルをドラッグで囲んで離すと、最前面ウィンドウが
/// その範囲に吸着（スナップ）する。ESC でキャンセル。
///
/// タイトルバーのドラッグを直接検知する完全なスナッピングは CGEventTap が必要で、
/// これはその土台となる明示起動版。
final class SnapOverlayController {

    static let shared = SnapOverlayController()

    private var overlayWindows: [SnapOverlayWindow] = []
    private let windowController = WindowController()
    private var targetWindow: AXUIElement?
    private var previousApp: NSRunningApplication?
    private var spec: GridSpec = .default

    /// スナップピッカーを表示する。spec 未指定なら設定のグリッド分割数を使う。
    func present(spec: GridSpec? = nil) {
        dismiss()

        // 重要: オーバーレイを出すと UltraGrid が最前面になるため、
        // アクティブ化する“前”に対象ウィンドウと元アプリを捕まえておく。
        self.targetWindow = windowController.currentFocusedWindow()
        self.previousApp = NSWorkspace.shared.frontmostApplication

        // カーソルのあるスクリーンを対象にする。
        let mouse = NSEvent.mouseLocation
        let targetScreen = NSScreen.screens.first { $0.frame.contains(mouse) } ?? NSScreen.main
        guard let targetScreen else { return }

        // そのモニタ向けのグリッド分割数を使う。
        self.spec = (spec ?? SettingsStore.shared.settings.gridSpec(for: targetScreen)).clamped()

        let window = SnapOverlayWindow(screen: targetScreen, spec: self.spec)
        window.onCommit = { [weak self] zone in
            guard let self else { return }
            if let target = self.targetWindow {
                self.windowController.place(zone: zone, spec: self.spec, on: targetScreen, window: target)
            }
            self.finish()
        }
        window.onCancel = { [weak self] in self?.finish() }

        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        overlayWindows = [window]
    }

    /// オーバーレイを閉じ、元のアプリを再びアクティブにする（3番の要望）。
    private func finish() {
        dismiss()
        // 配置直後は UltraGrid が最前面なので、元アプリのウィンドウにフォーカスを戻す。
        previousApp?.activate(options: [])
        previousApp = nil
    }

    func dismiss() {
        overlayWindows.forEach { $0.orderOut(nil) }
        overlayWindows.removeAll()
    }
}

/// オーバーレイ用の透明ウィンドウ。
final class SnapOverlayWindow: NSWindow {

    var onCommit: ((GridZone) -> Void)?
    var onCancel: (() -> Void)?

    init(screen: NSScreen, spec: GridSpec) {
        super.init(contentRect: screen.frame, styleMask: .borderless, backing: .buffered, defer: false)
        self.isOpaque = false
        self.backgroundColor = .clear
        self.level = .screenSaver
        self.ignoresMouseEvents = false
        self.hasShadow = false
        self.collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary]

        // グリッドは画面全体ではなく作業領域（メニューバー / Dock を除いた visibleFrame）に
        // 描く。GridModel の配置計算と一致させるため、ウィンドウ内ローカル座標へ変換する。
        let work = CGRect(
            x: screen.visibleFrame.minX - screen.frame.minX,
            y: screen.visibleFrame.minY - screen.frame.minY,
            width: screen.visibleFrame.width,
            height: screen.visibleFrame.height
        )
        let view = SnapGridView(frame: CGRect(origin: .zero, size: screen.frame.size), workArea: work, spec: spec)
        view.onCommit = { [weak self] zone in self?.onCommit?(zone) }
        view.onCancel = { [weak self] in self?.onCancel?() }
        self.contentView = view
        self.makeFirstResponder(view)
    }

    override var canBecomeKey: Bool { true }
}

/// グリッド線を描画し、ドラッグでセル範囲を選択するビュー。
final class SnapGridView: NSView {

    var onCommit: ((GridZone) -> Void)?
    var onCancel: (() -> Void)?

    private let spec: GridSpec
    private let workArea: CGRect
    private var startCell: (col: Int, row: Int)?
    private var currentCell: (col: Int, row: Int)?

    private var outerMargin: CGFloat { CGFloat(SettingsStore.shared.settings.outerMargin) }

    init(frame: CGRect, workArea: CGRect, spec: GridSpec) {
        self.spec = spec.clamped()
        self.workArea = workArea
        super.init(frame: frame)
    }

    required init?(coder: NSCoder) { fatalError() }

    override var acceptsFirstResponder: Bool { true }

    // MARK: - セル座標変換（ビュー座標は左下原点）

    // 作業領域（visibleFrame）から外周余白を引いたものがグリッド範囲。GridModel と一致。
    private var gridArea: CGRect { workArea.insetBy(dx: outerMargin, dy: outerMargin) }

    private func cell(at point: CGPoint) -> (col: Int, row: Int) {
        let area = gridArea
        let cellW = area.width / CGFloat(spec.cols)
        let cellH = area.height / CGFloat(spec.rows)
        let col = Int((point.x - area.minX) / cellW)
        let rowFromBottom = Int((point.y - area.minY) / cellH)
        let row = spec.rows - 1 - rowFromBottom // 上端が row 0
        return (min(max(col, 0), spec.cols - 1), min(max(row, 0), spec.rows - 1))
    }

    private func zone(from a: (col: Int, row: Int), to b: (col: Int, row: Int)) -> GridZone {
        let col = min(a.col, b.col)
        let row = min(a.row, b.row)
        let colSpan = abs(a.col - b.col) + 1
        let rowSpan = abs(a.row - b.row) + 1
        return GridZone(col: col, row: row, colSpan: colSpan, rowSpan: rowSpan)
    }

    /// グリッドセル範囲 → ビュー座標の矩形（ハイライト描画用）。
    private func rect(for zone: GridZone) -> CGRect {
        let area = gridArea
        let cellW = area.width / CGFloat(spec.cols)
        let cellH = area.height / CGFloat(spec.rows)
        let x = area.minX + CGFloat(zone.col) * cellW
        let w = cellW * CGFloat(zone.colSpan)
        let topOffset = CGFloat(zone.row) * cellH
        let y = area.maxY - topOffset - cellH * CGFloat(zone.rowSpan)
        return CGRect(x: x, y: y, width: w, height: h(cellH, zone))
    }

    private func h(_ cellH: CGFloat, _ zone: GridZone) -> CGFloat { cellH * CGFloat(zone.rowSpan) }

    // MARK: - マウス処理

    override func mouseDown(with event: NSEvent) {
        let p = convert(event.locationInWindow, from: nil)
        startCell = cell(at: p)
        currentCell = startCell
        needsDisplay = true
    }

    override func mouseDragged(with event: NSEvent) {
        let p = convert(event.locationInWindow, from: nil)
        currentCell = cell(at: p)
        needsDisplay = true
    }

    override func mouseUp(with event: NSEvent) {
        guard let start = startCell, let current = currentCell else { return }
        onCommit?(zone(from: start, to: current))
        startCell = nil
        currentCell = nil
    }

    override func keyDown(with event: NSEvent) {
        if event.keyCode == 53 { onCancel?() } // ESC
    }

    // MARK: - 描画

    override func draw(_ dirtyRect: CGRect) {
        let area = gridArea

        NSColor.black.withAlphaComponent(0.12).setFill()
        bounds.fill()

        // グリッド線。
        let cellW = area.width / CGFloat(spec.cols)
        let cellH = area.height / CGFloat(spec.rows)
        NSColor.white.withAlphaComponent(0.35).setStroke()
        let path = NSBezierPath()
        path.lineWidth = 1
        for c in 0...spec.cols {
            let x = area.minX + CGFloat(c) * cellW
            path.move(to: CGPoint(x: x, y: area.minY))
            path.line(to: CGPoint(x: x, y: area.maxY))
        }
        for r in 0...spec.rows {
            let y = area.minY + CGFloat(r) * cellH
            path.move(to: CGPoint(x: area.minX, y: y))
            path.line(to: CGPoint(x: area.maxX, y: y))
        }
        path.stroke()

        // 選択中のハイライト。
        if let start = startCell, let current = currentCell {
            let z = zone(from: start, to: current)
            let r = rect(for: z)
            NSColor.white.withAlphaComponent(0.35).setFill()
            r.fill()
            NSColor.white.withAlphaComponent(0.9).setStroke()
            let border = NSBezierPath(rect: r)
            border.lineWidth = 2
            border.stroke()
        }
    }
}
