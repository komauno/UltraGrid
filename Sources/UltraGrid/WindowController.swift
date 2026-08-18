import AppKit
import ApplicationServices

/// Accessibility API を使ってウィンドウを移動・リサイズする。
final class WindowController {

    /// 設定の余白・隙間を反映したグリッド計算機。
    var grid: GridModel {
        var g = GridModel()
        g.gap = CGFloat(SettingsStore.shared.settings.gap)
        g.outerMargin = CGFloat(SettingsStore.shared.settings.outerMargin)
        return g
    }

    // MARK: - 公開 API

    /// 最前面ウィンドウを、指定スクリーン上のグリッド領域へ配置する。
    /// screen が nil の場合はウィンドウが今いるスクリーンを使う。
    @discardableResult
    func place(zone: GridZone, spec: GridSpec, on screen: NSScreen? = nil) -> Bool {
        guard Accessibility.isTrusted else {
            Accessibility.requestIfNeeded()
            return false
        }
        guard let window = focusedWindowElement() else { return false }

        let targetScreen = screen ?? screenOfWindow(window) ?? NSScreen.main
        guard let targetScreen else { return false }

        let frame = grid.frame(for: zone, spec: spec, on: targetScreen)
        return setFrame(frame, for: window)
    }

    /// 事前に捕まえた特定ウィンドウを配置する（スナップピッカー用）。
    /// ピッカー表示中は UltraGrid が最前面になるため、最前面判定に頼らずこちらを使う。
    @discardableResult
    func place(zone: GridZone, spec: GridSpec, on screen: NSScreen, window: AXUIElement) -> Bool {
        guard Accessibility.isTrusted else { return false }
        let frame = grid.frame(for: zone, spec: spec, on: screen)
        return setFrame(frame, for: window)
    }

    /// 現在フォーカスされているウィンドウ要素を返す。
    /// 重要: アプリをアクティブ化する“前”に呼ぶこと（呼んだ時点の最前面ウィンドウを返す）。
    func currentFocusedWindow() -> AXUIElement? {
        focusedWindowElement()
    }

    /// 保存済みプレースメントを適用する（プリセット復元で使用）。
    @discardableResult
    func apply(_ placement: WindowPlacement) -> Bool {
        guard Accessibility.isTrusted else { return false }
        let screen = placement.screenName.flatMap { name in
            NSScreen.screens.first { $0.localizedName == name }
        } ?? NSScreen.main
        guard let screen,
              let window = frontWindow(ofAppNamed: placement.appName, bundleID: placement.appBundleID)
        else { return false }

        let frame = grid.frame(for: placement.zone, spec: placement.spec, on: screen)
        return setFrame(frame, for: window)
    }

    // MARK: - 現在の最前面ウィンドウ情報（プリセット保存で使用）

    struct WindowSnapshot {
        var appName: String
        var appBundleID: String?
        var screenName: String?
        var frame: CGRect // AppKit 座標
    }

    /// 最前面ウィンドウの現在状態を取得する。
    func snapshotFrontWindow() -> WindowSnapshot? {
        guard let app = NSWorkspace.shared.frontmostApplication,
              let window = focusedWindowElement(),
              let axFrame = frameOf(window) else { return nil }

        let appKit = Geometry.axToAppKit(axFrame)
        let screen = NSScreen.screens.first { $0.frame.intersects(appKit) }
        return WindowSnapshot(
            appName: app.localizedName ?? "Unknown",
            appBundleID: app.bundleIdentifier,
            screenName: screen?.localizedName,
            frame: appKit
        )
    }

    // MARK: - AXUIElement ヘルパー

    private func focusedWindowElement() -> AXUIElement? {
        guard let app = NSWorkspace.shared.frontmostApplication else { return nil }
        let appElement = AXUIElementCreateApplication(app.processIdentifier)

        var windowRef: CFTypeRef?
        let result = AXUIElementCopyAttributeValue(
            appElement, kAXFocusedWindowAttribute as CFString, &windowRef
        )
        if result == .success, let windowRef {
            return (windowRef as! AXUIElement)
        }
        // フォールバック: アプリの最前面ウィンドウ。
        var windowsRef: CFTypeRef?
        if AXUIElementCopyAttributeValue(appElement, kAXWindowsAttribute as CFString, &windowsRef) == .success,
           let windows = windowsRef as? [AXUIElement], let first = windows.first {
            return first
        }
        return nil
    }

    private func frontWindow(ofAppNamed name: String, bundleID: String?) -> AXUIElement? {
        let running = NSWorkspace.shared.runningApplications
        let match = running.first { app in
            if let bundleID, let appBundle = app.bundleIdentifier { return appBundle == bundleID }
            return app.localizedName == name
        }
        guard let match else { return nil }
        let appElement = AXUIElementCreateApplication(match.processIdentifier)
        var windowsRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(appElement, kAXWindowsAttribute as CFString, &windowsRef) == .success,
              let windows = windowsRef as? [AXUIElement] else { return nil }
        return windows.first
    }

    private func frameOf(_ window: AXUIElement) -> CGRect? {
        guard let position = axPoint(window, kAXPositionAttribute),
              let size = axSize(window, kAXSizeAttribute) else { return nil }
        return CGRect(origin: position, size: size)
    }

    /// AppKit 座標の矩形を AX 座標へ変換してウィンドウへ適用する。
    @discardableResult
    private func setFrame(_ appKitRect: CGRect, for window: AXUIElement) -> Bool {
        let ax = Geometry.appKitToAX(appKitRect)
        var pos = ax.origin
        var size = ax.size

        // 先に位置、次にサイズの順で設定すると多くのアプリで安定する。
        if let posValue = AXValueCreate(.cgPoint, &pos) {
            AXUIElementSetAttributeValue(window, kAXPositionAttribute as CFString, posValue)
        }
        if let sizeValue = AXValueCreate(.cgSize, &size) {
            AXUIElementSetAttributeValue(window, kAXSizeAttribute as CFString, sizeValue)
        }
        // サイズ制約でズレるアプリ向けにもう一度位置を合わせる。
        if let posValue = AXValueCreate(.cgPoint, &pos) {
            AXUIElementSetAttributeValue(window, kAXPositionAttribute as CFString, posValue)
        }
        return true
    }

    private func screenOfWindow(_ window: AXUIElement) -> NSScreen? {
        guard let axFrame = frameOf(window) else { return nil }
        let appKit = Geometry.axToAppKit(axFrame)
        return NSScreen.screens.first { $0.frame.intersects(appKit) }
    }

    // MARK: - AXValue 取り出しヘルパー

    private func axPoint(_ element: AXUIElement, _ attribute: String) -> CGPoint? {
        guard let value = axValue(element, attribute) else { return nil }
        var point = CGPoint.zero
        return AXValueGetValue(value, .cgPoint, &point) ? point : nil
    }

    private func axSize(_ element: AXUIElement, _ attribute: String) -> CGSize? {
        guard let value = axValue(element, attribute) else { return nil }
        var size = CGSize.zero
        return AXValueGetValue(value, .cgSize, &size) ? size : nil
    }

    private func axValue(_ element: AXUIElement, _ attribute: String) -> AXValue? {
        var ref: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute as CFString, &ref) == .success,
              let ref else { return nil }
        return (ref as! AXValue)
    }
}
