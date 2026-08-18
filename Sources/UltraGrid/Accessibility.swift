import AppKit
import ApplicationServices

/// Accessibility（アクセシビリティ）権限の確認・要求を担当する。
/// ウィンドウ操作には「システム設定 > プライバシーとセキュリティ > アクセシビリティ」
/// での許可が必須。
enum Accessibility {

    /// 現在許可されているか。
    static var isTrusted: Bool {
        AXIsProcessTrusted()
    }

    /// 権限を確認し、未許可ならシステムのプロンプトを表示する。
    @discardableResult
    static func requestIfNeeded() -> Bool {
        let key = kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String
        let options = [key: true] as CFDictionary
        return AXIsProcessTrustedWithOptions(options)
    }

    /// システム設定のアクセシビリティ画面を直接開く。
    static func openSettings() {
        let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!
        NSWorkspace.shared.open(url)
    }
}
