import AppKit

/// 座標系ヘルパー。
///
/// AppKit（NSScreen / NSWindow）は左下原点・Y上向き、Accessibility API は
/// 主ディスプレイ左上原点・Y下向きで座標を扱う。ウルトラワイド + 複数モニタ
/// 環境ではこの変換を誤ると配置が大きくズレるため、ここに集約する。
enum Geometry {

    /// 主ディスプレイ（メニューバーのある screens[0]）の高さ。
    static var primaryHeight: CGFloat {
        NSScreen.screens.first?.frame.height ?? 0
    }

    /// AppKit グローバル座標の矩形を Accessibility 座標（左上原点）へ変換する。
    static func appKitToAX(_ rect: CGRect) -> CGRect {
        let axY = primaryHeight - rect.maxY
        return CGRect(x: rect.minX, y: axY, width: rect.width, height: rect.height)
    }

    /// Accessibility 座標（左上原点）の矩形を AppKit グローバル座標へ変換する。
    static func axToAppKit(_ rect: CGRect) -> CGRect {
        let appKitY = primaryHeight - rect.maxY
        return CGRect(x: rect.minX, y: appKitY, width: rect.width, height: rect.height)
    }
}
