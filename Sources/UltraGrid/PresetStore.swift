import AppKit

/// レイアウトプリセットを JSON でディスク保存し、復元する。
/// 保存先: ~/Library/Application Support/UltraGrid/presets.json
final class PresetStore {

    static let shared = PresetStore()

    private(set) var presets: [LayoutPreset] = []
    private let windowController = WindowController()

    private var fileURL: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let dir = base.appendingPathComponent("UltraGrid", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("presets.json")
    }

    private init() {
        load()
    }

    // MARK: - 現在の配置からプリセットを作る

    /// 現在開いている（可視の）全ウィンドウの配置を最も近いグリッドに丸めて保存する。
    /// spec は保存時の分割数。トレーディングのマルチウィンドウ配置を一括保存する用途。
    func capturePreset(named name: String, spec: GridSpec = .default) -> LayoutPreset {
        var placements: [WindowPlacement] = []

        for app in NSWorkspace.shared.runningApplications where app.activationPolicy == .regular {
            let appElement = AXUIElementCreateApplication(app.processIdentifier)
            var windowsRef: CFTypeRef?
            guard AXUIElementCopyAttributeValue(appElement, kAXWindowsAttribute as CFString, &windowsRef) == .success,
                  let windows = windowsRef as? [AXUIElement] else { continue }

            for window in windows {
                guard let appKit = frameOf(window) else { continue }
                guard let screen = NSScreen.screens.first(where: { $0.frame.intersects(appKit) }) else { continue }
                let zone = nearestZone(for: appKit, spec: spec, on: screen)
                placements.append(WindowPlacement(
                    appBundleID: app.bundleIdentifier,
                    appName: app.localizedName ?? "Unknown",
                    screenName: screen.localizedName,
                    spec: spec,
                    zone: zone
                ))
            }
        }

        let preset = LayoutPreset(name: name, placements: placements)
        presets.append(preset)
        save()
        return preset
    }

    // MARK: - 復元

    /// プリセットを適用する。含まれる各ウィンドウをグリッドへ配置する。
    func apply(_ preset: LayoutPreset) {
        for placement in preset.placements {
            windowController.apply(placement)
        }
    }

    func delete(_ preset: LayoutPreset) {
        presets.removeAll { $0.id == preset.id }
        save()
    }

    func rename(_ preset: LayoutPreset, to newName: String) {
        guard let idx = presets.firstIndex(where: { $0.id == preset.id }) else { return }
        presets[idx].name = newName
        save()
    }

    // MARK: - 永続化

    func save() {
        do {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            let data = try encoder.encode(presets)
            try data.write(to: fileURL, options: .atomic)
        } catch {
            NSLog("UltraGrid: プリセット保存に失敗 \(error)")
        }
    }

    func load() {
        guard let data = try? Data(contentsOf: fileURL) else { return }
        do {
            presets = try JSONDecoder().decode([LayoutPreset].self, from: data)
        } catch {
            NSLog("UltraGrid: プリセット読み込みに失敗 \(error)")
        }
    }

    // MARK: - グリッドへの丸め込み

    /// AppKit 座標の矩形を、最も面積の重なるグリッドセル範囲へ丸める。
    private func nearestZone(for rect: CGRect, spec: GridSpec, on screen: NSScreen) -> GridZone {
        let s = spec.clamped()
        let area = screen.visibleFrame
        let cellW = area.width / CGFloat(s.cols)
        let cellH = area.height / CGFloat(s.rows)

        // 左上原点でのセル範囲を求める。
        let minCol = Int(((rect.minX - area.minX) / cellW).rounded(.down))
        let maxCol = Int(((rect.maxX - area.minX) / cellW).rounded(.up)) - 1

        // AppKit は下端が原点なので row 変換に注意。
        let topFromTop = area.maxY - rect.maxY
        let bottomFromTop = area.maxY - rect.minY
        let minRow = Int((topFromTop / cellH).rounded(.down))
        let maxRow = Int((bottomFromTop / cellH).rounded(.up)) - 1

        let col = min(max(minCol, 0), s.cols - 1)
        let row = min(max(minRow, 0), s.rows - 1)
        let colSpan = min(max(maxCol - minCol + 1, 1), s.cols - col)
        let rowSpan = min(max(maxRow - minRow + 1, 1), s.rows - row)
        return GridZone(col: col, row: row, colSpan: colSpan, rowSpan: rowSpan)
    }

    private func frameOf(_ window: AXUIElement) -> CGRect? {
        var posRef: CFTypeRef?
        var sizeRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(window, kAXPositionAttribute as CFString, &posRef) == .success,
              AXUIElementCopyAttributeValue(window, kAXSizeAttribute as CFString, &sizeRef) == .success,
              let posRef, let sizeRef else { return nil }
        var point = CGPoint.zero
        var size = CGSize.zero
        AXValueGetValue(posRef as! AXValue, .cgPoint, &point)
        AXValueGetValue(sizeRef as! AXValue, .cgSize, &size)
        let axRect = CGRect(origin: point, size: size)
        // 極端に小さいウィンドウ（ツールパレット等）は無視。
        guard size.width > 80, size.height > 60 else { return nil }
        return Geometry.axToAppKit(axRect)
    }
}
