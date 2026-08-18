import AppKit

/// メニューバー（NSStatusItem）の UI とアクションを担当する。
final class MenuBarController: NSObject, NSMenuDelegate {

    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    private let windowController = WindowController()
    private let presetStore = PresetStore.shared

    override init() {
        super.init()
        if let button = statusItem.button {
            button.image = NSImage(systemSymbolName: "square.grid.3x3.fill", accessibilityDescription: "UltraGrid")
        }
        let menu = NSMenu()
        menu.delegate = self
        statusItem.menu = menu
        rebuildMenu()
    }

    // メニューを開くたびに最新のプリセット / 権限状態を反映する。
    func menuNeedsUpdate(_ menu: NSMenu) {
        rebuildMenu()
    }

    func rebuildMenu() {
        guard let menu = statusItem.menu else { return }
        menu.removeAllItems()

        // 権限案内。
        if !Accessibility.isTrusted {
            let warn = NSMenuItem(title: "⚠︎ アクセシビリティ権限が必要です", action: #selector(openAccessibility), keyEquivalent: "")
            warn.target = self
            menu.addItem(warn)
            menu.addItem(.separator())
        }

        // クイック操作 / ショートカット（設定の actions から生成）。
        let header = NSMenuItem(title: "クイック操作", action: nil, keyEquivalent: "")
        header.isEnabled = false
        menu.addItem(header)

        for action in SettingsStore.shared.settings.actions {
            let item = NSMenuItem(title: action.name, action: #selector(runAction(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = action.id
            // 標準項目（設定 / 終了）と同じく、キーは右揃え・半透明でネイティブ表示する。
            if let hk = action.hotkey {
                item.keyEquivalent = hk.keyEquivalent
                item.keyEquivalentModifierMask = hk.keyEquivalentModifierMask
            }
            menu.addItem(item)
        }

        // プリセット。
        menu.addItem(.separator())
        let presetHeader = NSMenuItem(title: "レイアウトプリセット", action: nil, keyEquivalent: "")
        presetHeader.isEnabled = false
        menu.addItem(presetHeader)

        if presetStore.presets.isEmpty {
            let empty = NSMenuItem(title: "（未保存）", action: nil, keyEquivalent: "")
            empty.isEnabled = false
            menu.addItem(empty)
        } else {
            for preset in presetStore.presets {
                let item = NSMenuItem(title: "▸ \(preset.name)", action: #selector(applyPreset(_:)), keyEquivalent: "")
                item.target = self
                item.representedObject = preset.id
                menu.addItem(item)
            }
        }

        let capture = NSMenuItem(title: "現在の配置を保存…", action: #selector(capturePreset), keyEquivalent: "s")
        capture.target = self
        menu.addItem(capture)

        let manage = NSMenuItem(title: "プリセットを削除…", action: #selector(managePresets), keyEquivalent: "")
        manage.target = self
        menu.addItem(manage)

        // 設定・終了。
        menu.addItem(.separator())
        let settings = NSMenuItem(title: "設定…", action: #selector(openSettings), keyEquivalent: ",")
        settings.target = self
        menu.addItem(settings)

        let quit = NSMenuItem(title: "UltraGrid を終了", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        menu.addItem(quit)
    }

    // MARK: - アクション

    @objc private func runAction(_ sender: NSMenuItem) {
        guard let id = sender.representedObject as? UUID,
              let action = SettingsStore.shared.settings.actions.first(where: { $0.id == id }) else { return }
        switch action.kind {
        case .picker:
            SnapOverlayController.shared.present()
        case .placeZone:
            windowController.place(zone: action.zone, spec: action.spec)
        }
    }

    @objc private func applyPreset(_ sender: NSMenuItem) {
        guard let id = sender.representedObject as? UUID,
              let preset = presetStore.presets.first(where: { $0.id == id }) else { return }
        presetStore.apply(preset)
    }

    @objc private func capturePreset() {
        let alert = NSAlert()
        alert.messageText = "現在のウィンドウ配置を保存"
        alert.informativeText = "プリセット名を入力してください。"
        let field = NSTextField(frame: NSRect(x: 0, y: 0, width: 240, height: 24))
        field.placeholderString = "レイアウト名"
        alert.accessoryView = field
        alert.addButton(withTitle: "保存")
        alert.addButton(withTitle: "キャンセル")
        NSApp.activate(ignoringOtherApps: true)
        if alert.runModal() == .alertFirstButtonReturn {
            let name = field.stringValue.isEmpty ? "無題レイアウト" : field.stringValue
            _ = presetStore.capturePreset(named: name)
        }
    }

    @objc private func managePresets() {
        guard !presetStore.presets.isEmpty else { return }
        let alert = NSAlert()
        alert.messageText = "削除するプリセットを選択"
        let popup = NSPopUpButton(frame: NSRect(x: 0, y: 0, width: 240, height: 24))
        popup.addItems(withTitles: presetStore.presets.map { $0.name })
        alert.accessoryView = popup
        alert.addButton(withTitle: "削除")
        alert.addButton(withTitle: "キャンセル")
        NSApp.activate(ignoringOtherApps: true)
        if alert.runModal() == .alertFirstButtonReturn {
            let preset = presetStore.presets[popup.indexOfSelectedItem]
            presetStore.delete(preset)
        }
    }

    @objc private func openSettings() {
        SettingsWindowController.shared.show()
    }

    @objc private func openAccessibility() {
        Accessibility.openSettings()
    }
}
