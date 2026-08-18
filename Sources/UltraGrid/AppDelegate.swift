import AppKit
import Carbon.HIToolbox

/// アプリのライフサイクルと、設定に基づくホットキー登録を担当する。
final class AppDelegate: NSObject, NSApplicationDelegate {

    private var menuBar: MenuBarController?
    private let windowController = WindowController()

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Dock アイコンを出さないメニューバー常駐アプリ。
        NSApp.setActivationPolicy(.accessory)

        // 権限確認（未許可ならシステムのプロンプト）。
        Accessibility.requestIfNeeded()

        menuBar = MenuBarController()
        registerHotkeys()

        // 設定に応じてログイン項目の登録状態を揃える（自動起動の反映）。
        SettingsStore.shared.reconcileLaunchAtLogin()

        // ⌃⌘ を押しながらのドラッグスナップ監視を開始。
        DragSnapMonitor.shared.start()

        // 設定変更に追従してホットキー / メニューを再構築。
        NotificationCenter.default.addObserver(
            self, selector: #selector(settingsChanged),
            name: SettingsStore.didChange, object: nil
        )
    }

    @objc private func settingsChanged() {
        registerHotkeys()
        menuBar?.rebuildMenu()
    }

    // MARK: - ホットキー登録（設定のアクションから生成）

    private func registerHotkeys() {
        let hk = HotkeyManager.shared
        hk.unregisterAll()

        // 各アクションに割り当てられたショートカット。
        for action in SettingsStore.shared.settings.actions {
            guard let key = action.hotkey else { continue }
            let captured = action
            hk.register(keyCode: key.keyCode, modifiers: key.modifiers) { [weak self] in
                self?.perform(captured)
            }
        }

        // ⌃⌥⇧1..6  保存済みプリセットの1〜6番目を適用（固定）。
        let presetKeys = [Key.one, Key.two, Key.three, Key.four, Key.five, Key.six]
        for (index, key) in presetKeys.enumerated() {
            hk.register(keyCode: key, modifiers: Mod.ctrlOptShift) {
                let presets = PresetStore.shared.presets
                guard index < presets.count else { return }
                PresetStore.shared.apply(presets[index])
            }
        }
    }

    /// アクションを実行する（メニュー / ショートカット共通）。
    func perform(_ action: GridAction) {
        switch action.kind {
        case .picker:
            SnapOverlayController.shared.present()
        case .placeZone:
            windowController.place(zone: action.zone, spec: action.spec)
        }
    }
}
