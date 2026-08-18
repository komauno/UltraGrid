import Foundation

/// グリッドの分割数（縦横それぞれ最大6）。
struct GridSpec: Codable, Equatable {
    var cols: Int
    var rows: Int

    static let `default` = GridSpec(cols: 6, rows: 6)

    /// 分割数を1...6にクランプする。
    func clamped() -> GridSpec {
        GridSpec(cols: min(max(cols, 1), 6), rows: min(max(rows, 1), 6))
    }
}

/// グリッド上の占有領域。原点は左上（col=0, row=0 が左上のセル）。
/// col/row はセルインデックス、colSpan/rowSpan は占有するセル数。
struct GridZone: Codable, Equatable {
    var col: Int
    var row: Int
    var colSpan: Int
    var rowSpan: Int

    init(col: Int, row: Int, colSpan: Int = 1, rowSpan: Int = 1) {
        self.col = col
        self.row = row
        self.colSpan = colSpan
        self.rowSpan = rowSpan
    }

    /// 指定したグリッド仕様に収まるように領域を丸める。
    func clamped(to spec: GridSpec) -> GridZone {
        let s = spec.clamped()
        let c = min(max(col, 0), s.cols - 1)
        let r = min(max(row, 0), s.rows - 1)
        let cs = min(max(colSpan, 1), s.cols - c)
        let rs = min(max(rowSpan, 1), s.rows - r)
        return GridZone(col: c, row: r, colSpan: cs, rowSpan: rs)
    }
}

/// 1枚のウィンドウの配置指定。アプリはバンドルID（無ければ名前）で識別する。
struct WindowPlacement: Codable, Equatable, Identifiable {
    var id: UUID = UUID()
    var appBundleID: String?
    var appName: String
    /// 対象スクリーン（NSScreen.localizedName）。nil なら現在のメインスクリーン。
    var screenName: String?
    var spec: GridSpec
    var zone: GridZone
}

/// 複数ウィンドウをまとめた保存レイアウト（例: 「監視用」「寄り付き用」）。
struct LayoutPreset: Codable, Equatable, Identifiable {
    var id: UUID = UUID()
    var name: String
    var placements: [WindowPlacement]
    var createdAt: Date = Date()
}

/// 1つのグリッド配置に割り当てるショートカット定義。
struct HotkeyBinding: Codable, Equatable, Identifiable {
    var id: UUID = UUID()
    var name: String
    var spec: GridSpec
    var zone: GridZone
    /// Carbon の仮想キーコード。
    var keyCode: UInt32
    /// Carbon の修飾フラグ（cmdKey / optionKey / controlKey / shiftKey の合成）。
    var modifiers: UInt32
}
