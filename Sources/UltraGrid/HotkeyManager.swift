import AppKit
import Carbon.HIToolbox

/// グローバルホットキーを Carbon の RegisterEventHotKey で登録・管理する。
/// アプリが最前面でなくてもキー入力を受け取れる。
final class HotkeyManager {

    /// 登録済みホットキーの内部表現。
    private struct Registered {
        let ref: EventHotKeyRef
        let handler: () -> Void
    }

    private var registered: [UInt32: Registered] = [:]
    private var nextID: UInt32 = 1
    private var eventHandler: EventHandlerRef?

    static let shared = HotkeyManager()

    private init() {
        installHandler()
    }

    // MARK: - 登録

    /// ホットキーを登録する。keyCode / modifiers は Carbon 定義（例: cmdKey, optionKey）。
    @discardableResult
    func register(keyCode: UInt32, modifiers: UInt32, handler: @escaping () -> Void) -> UInt32 {
        let id = nextID
        nextID += 1

        var hotKeyRef: EventHotKeyRef?
        let hotKeyID = EventHotKeyID(signature: Self.signature, id: id)
        let status = RegisterEventHotKey(
            keyCode, modifiers, hotKeyID,
            GetApplicationEventTarget(), 0, &hotKeyRef
        )
        guard status == noErr, let hotKeyRef else {
            NSLog("UltraGrid: ホットキー登録に失敗 (keyCode=\(keyCode), status=\(status))")
            return 0
        }
        registered[id] = Registered(ref: hotKeyRef, handler: handler)
        return id
    }

    /// 登録済みホットキーをすべて解除する（設定変更時の再登録などに使用）。
    func unregisterAll() {
        for (_, entry) in registered {
            UnregisterEventHotKey(entry.ref)
        }
        registered.removeAll()
    }

    // MARK: - イベントハンドラ

    private static let signature: OSType = {
        // 'UGRD' を OSType(FourCharCode) にした識別子。
        let chars = Array("UGRD".utf8)
        return chars.reduce(OSType(0)) { ($0 << 8) + OSType($1) }
    }()

    private func installHandler() {
        var eventType = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: UInt32(kEventHotKeyPressed)
        )
        let selfPtr = Unmanaged.passUnretained(self).toOpaque()
        InstallEventHandler(
            GetApplicationEventTarget(),
            { _, event, userData -> OSStatus in
                guard let event, let userData else { return OSStatus(eventNotHandledErr) }
                let manager = Unmanaged<HotkeyManager>.fromOpaque(userData).takeUnretainedValue()
                var hotKeyID = EventHotKeyID()
                let status = GetEventParameter(
                    event, EventParamName(kEventParamDirectObject),
                    EventParamType(typeEventHotKeyID), nil,
                    MemoryLayout<EventHotKeyID>.size, nil, &hotKeyID
                )
                guard status == noErr else { return status }
                manager.registered[hotKeyID.id]?.handler()
                return noErr
            },
            1, &eventType, selfPtr, &eventHandler
        )
    }
}

/// よく使うキーコードのショートハンド（Carbon.HIToolbox の kVK_* をラップ）。
enum Key {
    static let one = UInt32(kVK_ANSI_1)
    static let two = UInt32(kVK_ANSI_2)
    static let three = UInt32(kVK_ANSI_3)
    static let four = UInt32(kVK_ANSI_4)
    static let five = UInt32(kVK_ANSI_5)
    static let six = UInt32(kVK_ANSI_6)
    static let leftArrow = UInt32(kVK_LeftArrow)
    static let rightArrow = UInt32(kVK_RightArrow)
    static let upArrow = UInt32(kVK_UpArrow)
    static let downArrow = UInt32(kVK_DownArrow)
    static let ret = UInt32(kVK_Return)
}

/// 修飾キーのショートハンド。
enum Mod {
    static let cmd = UInt32(cmdKey)
    static let opt = UInt32(optionKey)
    static let ctrl = UInt32(controlKey)
    static let shift = UInt32(shiftKey)
    /// トレーディング用途で衝突しにくい ⌃⌥（Control+Option）を既定の接頭修飾に採用。
    static let ctrlOpt = UInt32(controlKey) | UInt32(optionKey)
    static let ctrlOptShift = UInt32(controlKey) | UInt32(optionKey) | UInt32(shiftKey)
}
