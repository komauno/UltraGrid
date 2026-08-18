import AppKit
import Carbon.HIToolbox
import ServiceManagement

// MARK: - ホットキー

/// ショートカット定義（Carbon の仮想キーコード + 修飾フラグ）。
struct Hotkey: Codable, Equatable {
    var keyCode: UInt32
    var modifiers: UInt32   // cmdKey / optionKey / controlKey / shiftKey の合成

    /// 表示用文字列（例: "⌃⌥Space"）。
    var display: String {
        var s = ""
        if modifiers & UInt32(controlKey) != 0 { s += "⌃" }
        if modifiers & UInt32(optionKey)  != 0 { s += "⌥" }
        if modifiers & UInt32(shiftKey)   != 0 { s += "⇧" }
        if modifiers & UInt32(cmdKey)     != 0 { s += "⌘" }
        s += KeyName.string(for: keyCode)
        return s
    }

    /// ネイティブ NSMenuItem 用のキー等価文字（標準項目と同じ右揃え・半透明表示にするため）。
    var keyEquivalent: String {
        switch Int(keyCode) {
        case kVK_Space: return " "
        case kVK_Return, kVK_ANSI_KeypadEnter: return "\r"
        case kVK_LeftArrow:  return String(UnicodeScalar(NSLeftArrowFunctionKey)!)
        case kVK_RightArrow: return String(UnicodeScalar(NSRightArrowFunctionKey)!)
        case kVK_UpArrow:    return String(UnicodeScalar(NSUpArrowFunctionKey)!)
        case kVK_DownArrow:  return String(UnicodeScalar(NSDownArrowFunctionKey)!)
        default:
            let name = KeyName.string(for: keyCode)
            return name.count == 1 ? name.lowercased() : ""   // 1 文字キーのみ（数字・英字）
        }
    }

    /// ネイティブ NSMenuItem 用の修飾フラグ。
    var keyEquivalentModifierMask: NSEvent.ModifierFlags {
        var f: NSEvent.ModifierFlags = []
        if modifiers & UInt32(controlKey) != 0 { f.insert(.control) }
        if modifiers & UInt32(optionKey)  != 0 { f.insert(.option) }
        if modifiers & UInt32(shiftKey)   != 0 { f.insert(.shift) }
        if modifiers & UInt32(cmdKey)     != 0 { f.insert(.command) }
        return f
    }

    /// NSEvent から生成（設定画面のキーレコーダ用）。
    static func from(event: NSEvent) -> Hotkey {
        var m: UInt32 = 0
        let f = event.modifierFlags
        if f.contains(.command) { m |= UInt32(cmdKey) }
        if f.contains(.option)  { m |= UInt32(optionKey) }
        if f.contains(.control) { m |= UInt32(controlKey) }
        if f.contains(.shift)   { m |= UInt32(shiftKey) }
        return Hotkey(keyCode: UInt32(event.keyCode), modifiers: m)
    }
}

/// キーコード → 表示名の簡易対応表。
enum KeyName {
    static func string(for code: UInt32) -> String {
        switch Int(code) {
        case kVK_Space: return "Space"
        case kVK_Return, kVK_ANSI_KeypadEnter: return "↩"
        case kVK_LeftArrow: return "←"
        case kVK_RightArrow: return "→"
        case kVK_UpArrow: return "↑"
        case kVK_DownArrow: return "↓"
        case kVK_ANSI_1: return "1"
        case kVK_ANSI_2: return "2"
        case kVK_ANSI_3: return "3"
        case kVK_ANSI_4: return "4"
        case kVK_ANSI_5: return "5"
        case kVK_ANSI_6: return "6"
        case kVK_ANSI_7: return "7"
        case kVK_ANSI_8: return "8"
        case kVK_ANSI_9: return "9"
        case kVK_ANSI_0: return "0"
        default:
            if let s = letters[Int(code)] { return s }
            return "key\(code)"
        }
    }

    private static let letters: [Int: String] = [
        kVK_ANSI_A: "A", kVK_ANSI_B: "B", kVK_ANSI_C: "C", kVK_ANSI_D: "D",
        kVK_ANSI_E: "E", kVK_ANSI_F: "F", kVK_ANSI_G: "G", kVK_ANSI_H: "H",
        kVK_ANSI_I: "I", kVK_ANSI_J: "J", kVK_ANSI_K: "K", kVK_ANSI_L: "L",
        kVK_ANSI_M: "M", kVK_ANSI_N: "N", kVK_ANSI_O: "O", kVK_ANSI_P: "P",
        kVK_ANSI_Q: "Q", kVK_ANSI_R: "R", kVK_ANSI_S: "S", kVK_ANSI_T: "T",
        kVK_ANSI_U: "U", kVK_ANSI_V: "V", kVK_ANSI_W: "W", kVK_ANSI_X: "X",
        kVK_ANSI_Y: "Y", kVK_ANSI_Z: "Z"
    ]
}

// MARK: - アクション（クイック操作 / ショートカットの単位）

/// アクションの種類。
enum ActionKind: String, Codable {
    case placeZone   // グリッド領域へ配置
    case picker      // スナップピッカーを表示
}

/// メニュー / ショートカットから呼べる 1 操作。
/// 「クイック操作の選択肢」と「そのショートカット」を 1 つの型で表す。
struct GridAction: Codable, Equatable, Identifiable {
    var id: UUID = UUID()
    var name: String
    var kind: ActionKind = .placeZone
    var spec: GridSpec = .default
    var zone: GridZone = GridZone(col: 0, row: 0, colSpan: 3, rowSpan: 6)
    var showInMenu: Bool = true
    var hotkey: Hotkey?
}

// MARK: - 修飾キー（ドラッグスナップのカスタマイズ用）

/// ドラッグスナップで使う単一の修飾キー。
enum ModifierKey: String, Codable, CaseIterable, Identifiable {
    case control, option, shift, command
    var id: String { rawValue }

    /// 記号（⌃⌥⇧⌘）。
    var glyph: String {
        switch self {
        case .control: return "⌃"
        case .option:  return "⌥"
        case .shift:   return "⇧"
        case .command: return "⌘"
        }
    }

    /// 設定画面の選択肢表示。
    var label: String {
        switch self {
        case .control: return "Controlキー"
        case .option:  return "Optionキー"
        case .shift:   return "Shiftキー"
        case .command: return "Commandキー"
        }
    }

    /// NSEvent の修飾フラグ。
    var eventFlag: NSEvent.ModifierFlags {
        switch self {
        case .control: return .control
        case .option:  return .option
        case .shift:   return .shift
        case .command: return .command
        }
    }
}

// MARK: - 設定本体（永続化される値）

struct Settings: Codable, Equatable {
    // グリッド分割数（ピッカー / ドラッグスナップの内部セル）
    var gridCols: Int = 6
    var gridRows: Int = 6

    // 余白・隙間（px）
    var gap: Double = 6
    var outerMargin: Double = 6

    // ドラッグスナップ（既定は ⌃ を押しながらドラッグ、⌘ 追加で範囲選択）
    var dragSnapEnabled: Bool = true
    // OS 標準の Option ドラッグ（タイル表示）と競合しないよう既定は Control。
    var dragSnapModifier: ModifierKey = .control
    // 範囲選択（複数セル）に追加で押すキー。
    var dragRangeModifier: ModifierKey = .command

    // ログイン時に起動
    var launchAtLogin: Bool = false

    // モニタ（ディスプレイ）ごとのグリッド分割数。キーは NSScreen の安定した識別子。
    // 未登録のモニタは既定（gridCols/gridRows）を使う。
    var displayGrids: [String: GridSpec] = [:]

    // クイック操作 / ショートカット
    var actions: [GridAction] = Settings.defaultActions

    /// 既定のグリッド（モニタ別設定が無いときのフォールバック）。
    var gridSpec: GridSpec { GridSpec(cols: gridCols, rows: gridRows).clamped() }

    /// 指定モニタのグリッド分割数（未登録なら既定を返す）。
    func gridSpec(for screen: NSScreen?) -> GridSpec {
        if let screen, let s = displayGrids[screen.ultraGridKey] {
            return s.clamped()
        }
        return gridSpec
    }

    /// 既定のアクション一式。
    static var defaultActions: [GridAction] {
        func mod(_ m: Int...) -> UInt32 { m.reduce(UInt32(0)) { $0 | UInt32($1) } }
        let ctrlOpt = mod(controlKey, optionKey)
        // 各既定アクションは、その配置を表現できる最小限の分割数を使う。
        let halfH = GridSpec(cols: 2, rows: 1)   // 左右半分
        let halfV = GridSpec(cols: 1, rows: 2)   // 上下半分
        let whole = GridSpec(cols: 1, rows: 1)   // 最大化
        let thirds = GridSpec(cols: 3, rows: 1)  // 1/3 系
        return [
            GridAction(name: "スナップピッカー", kind: .picker,
                       hotkey: Hotkey(keyCode: UInt32(kVK_Space), modifiers: ctrlOpt)),
            GridAction(name: "左半分", spec: halfH, zone: GridZone(col: 0, row: 0, colSpan: 1, rowSpan: 1),
                       hotkey: Hotkey(keyCode: UInt32(kVK_LeftArrow), modifiers: ctrlOpt)),
            GridAction(name: "右半分", spec: halfH, zone: GridZone(col: 1, row: 0, colSpan: 1, rowSpan: 1),
                       hotkey: Hotkey(keyCode: UInt32(kVK_RightArrow), modifiers: ctrlOpt)),
            GridAction(name: "上半分", spec: halfV, zone: GridZone(col: 0, row: 0, colSpan: 1, rowSpan: 1),
                       hotkey: Hotkey(keyCode: UInt32(kVK_UpArrow), modifiers: ctrlOpt)),
            GridAction(name: "下半分", spec: halfV, zone: GridZone(col: 0, row: 1, colSpan: 1, rowSpan: 1),
                       hotkey: Hotkey(keyCode: UInt32(kVK_DownArrow), modifiers: ctrlOpt)),
            GridAction(name: "最大化", spec: whole, zone: GridZone(col: 0, row: 0, colSpan: 1, rowSpan: 1),
                       hotkey: Hotkey(keyCode: UInt32(kVK_Return), modifiers: ctrlOpt)),
            GridAction(name: "左 1/3", spec: thirds, zone: GridZone(col: 0, row: 0, colSpan: 1, rowSpan: 1),
                       showInMenu: true, hotkey: Hotkey(keyCode: UInt32(kVK_ANSI_1), modifiers: ctrlOpt)),
            GridAction(name: "中央 1/3", spec: thirds, zone: GridZone(col: 1, row: 0, colSpan: 1, rowSpan: 1),
                       showInMenu: true, hotkey: Hotkey(keyCode: UInt32(kVK_ANSI_2), modifiers: ctrlOpt)),
            GridAction(name: "右 1/3", spec: thirds, zone: GridZone(col: 2, row: 0, colSpan: 1, rowSpan: 1),
                       showInMenu: true, hotkey: Hotkey(keyCode: UInt32(kVK_ANSI_3), modifiers: ctrlOpt))
        ]
    }
}

// 旧バージョンで保存された JSON に新しいキーが無くても壊れないよう、
// 欠けている項目は既定値で補って読み込む。
extension Settings {
    enum CodingKeys: String, CodingKey {
        case gridCols, gridRows, gap, outerMargin
        case dragSnapEnabled, dragSnapModifier, dragRangeModifier
        case displayGrids, launchAtLogin, actions
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let def = Settings()
        gridCols          = try c.decodeIfPresent(Int.self,               forKey: .gridCols)          ?? def.gridCols
        gridRows          = try c.decodeIfPresent(Int.self,               forKey: .gridRows)          ?? def.gridRows
        gap               = try c.decodeIfPresent(Double.self,            forKey: .gap)               ?? def.gap
        outerMargin       = try c.decodeIfPresent(Double.self,            forKey: .outerMargin)       ?? def.outerMargin
        dragSnapEnabled   = try c.decodeIfPresent(Bool.self,             forKey: .dragSnapEnabled)   ?? def.dragSnapEnabled
        dragSnapModifier  = try c.decodeIfPresent(ModifierKey.self,      forKey: .dragSnapModifier)  ?? def.dragSnapModifier
        dragRangeModifier = try c.decodeIfPresent(ModifierKey.self,      forKey: .dragRangeModifier) ?? def.dragRangeModifier
        displayGrids      = try c.decodeIfPresent([String: GridSpec].self, forKey: .displayGrids)    ?? def.displayGrids
        launchAtLogin     = try c.decodeIfPresent(Bool.self,             forKey: .launchAtLogin)     ?? def.launchAtLogin
        actions           = try c.decodeIfPresent([GridAction].self,      forKey: .actions)           ?? def.actions
    }
}

// MARK: - ディスプレイ識別

extension NSScreen {
    /// 永続化に使う、ディスプレイの安定した識別子（再接続してもおおむね一致）。
    var ultraGridKey: String {
        if let num = (deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value,
           let cf = CGDisplayCreateUUIDFromDisplayID(num)?.takeRetainedValue() {
            return CFUUIDCreateString(nil, cf) as String
        }
        return localizedName
    }

    /// 設定画面のタブに出す表示名。
    var ultraGridLabel: String {
        let name = localizedName
        return name.isEmpty ? "ディスプレイ" : name
    }
}

// MARK: - ストア（SwiftUI 監視 + 永続化 + 変更通知）

final class SettingsStore: ObservableObject {

    static let shared = SettingsStore()

    /// 設定が変わったら通知（ホットキー再登録 / メニュー再構築に使用）。
    static let didChange = Notification.Name("UltraGridSettingsDidChange")

    @Published var settings: Settings {
        didSet {
            guard settings != oldValue else { return }
            save()
            if settings.launchAtLogin != oldValue.launchAtLogin {
                applyLaunchAtLogin(settings.launchAtLogin)
            }
            NotificationCenter.default.post(name: Self.didChange, object: nil)
        }
    }

    private var fileURL: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let dir = base.appendingPathComponent("UltraGrid", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("settings.json")
    }

    private init() {
        // 読み込み（無ければ既定値）。
        if let data = try? Data(contentsOf: FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("UltraGrid/settings.json")),
           let decoded = try? JSONDecoder().decode(Settings.self, from: data) {
            self.settings = decoded
        } else {
            self.settings = Settings()
        }
    }

    func save() {
        do {
            let enc = JSONEncoder()
            enc.outputFormatting = [.prettyPrinted, .sortedKeys]
            try enc.encode(settings).write(to: fileURL, options: .atomic)
        } catch {
            NSLog("UltraGrid: 設定保存に失敗 \(error)")
        }
    }

    /// 起動時に、設定値と実際のログイン項目の状態を突き合わせて揃える。
    /// （例: 設定が「起動する」なのにまだ未登録なら登録する）
    func reconcileLaunchAtLogin() {
        applyLaunchAtLogin(settings.launchAtLogin)
    }

    /// ログイン項目の登録/解除（macOS 13+ の SMAppService）。
    private func applyLaunchAtLogin(_ enabled: Bool) {
        do {
            if enabled {
                if SMAppService.mainApp.status != .enabled {
                    try SMAppService.mainApp.register()
                }
            } else {
                if SMAppService.mainApp.status == .enabled {
                    try SMAppService.mainApp.unregister()
                }
            }
        } catch {
            NSLog("UltraGrid: ログイン項目の変更に失敗 \(error)")
        }
    }
}
