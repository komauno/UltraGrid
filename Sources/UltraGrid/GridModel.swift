import AppKit

/// 画面をグリッドに分割し、セル領域から実際の矩形を計算する。
///
/// - グリッド原点は「左上」（row 0 が画面上端）。人間の直感に合わせている。
/// - `visibleFrame` を使うことでメニューバー / Dock を避けて配置する。
/// - ウルトラワイド用に縦横それぞれ最大6分割まで対応。
struct GridModel {

    /// ウィンドウ間の隙間（px）。0 でぴったり敷き詰め。
    var gap: CGFloat = 6
    /// 画面端の余白（px）。
    var outerMargin: CGFloat = 6

    /// グリッド上のセル領域を AppKit グローバル座標の矩形へ変換する。
    ///
    /// - Parameters:
    ///   - zone: 占有するセル領域（左上原点）。
    ///   - spec: 分割数。
    ///   - screen: 対象スクリーン。
    /// - Returns: AppKit 座標（左下原点）の矩形。
    func frame(for zone: GridZone, spec: GridSpec, on screen: NSScreen) -> CGRect {
        let s = spec.clamped()
        let z = zone.clamped(to: s)

        // 配置に使える領域（メニューバー / Dock を除いた領域から外周余白を引く）。
        let area = screen.visibleFrame.insetBy(dx: outerMargin, dy: outerMargin)

        // セル1つあたりのサイズ（隙間を差し引いて算出）。
        let totalGapX = gap * CGFloat(s.cols - 1)
        let totalGapY = gap * CGFloat(s.rows - 1)
        let cellW = (area.width - totalGapX) / CGFloat(s.cols)
        let cellH = (area.height - totalGapY) / CGFloat(s.rows)

        // 左上原点でオフセットを計算し、AppKit 用に上下反転する。
        let x = area.minX + CGFloat(z.col) * (cellW + gap)
        let w = cellW * CGFloat(z.colSpan) + gap * CGFloat(z.colSpan - 1)
        let h = cellH * CGFloat(z.rowSpan) + gap * CGFloat(z.rowSpan - 1)

        // row は上端が 0。AppKit は下端が原点なので、上からのオフセットを下からに変換。
        let topOffset = CGFloat(z.row) * (cellH + gap)
        let y = area.maxY - topOffset - h

        return CGRect(x: x.rounded(), y: y.rounded(), width: w.rounded(), height: h.rounded())
    }

    /// スクリーン上の1点（AppKit 座標）が属するセルを返す。ドラッグ中のスナップ判定に使う。
    func cell(at point: CGPoint, spec: GridSpec, on screen: NSScreen) -> (col: Int, row: Int)? {
        let s = spec.clamped()
        let area = screen.visibleFrame.insetBy(dx: outerMargin, dy: outerMargin)
        guard area.contains(point) else { return nil }

        let cellW = area.width / CGFloat(s.cols)
        let cellH = area.height / CGFloat(s.rows)

        let col = Int((point.x - area.minX) / cellW)
        // 上端が row 0 になるよう反転。
        let rowFromBottom = Int((point.y - area.minY) / cellH)
        let row = s.rows - 1 - rowFromBottom

        return (min(max(col, 0), s.cols - 1), min(max(row, 0), s.rows - 1))
    }
}
