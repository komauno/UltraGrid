import AppKit

// メニューバー常駐アプリのエントリポイント。
// SwiftUI ではなく AppKit を直接使うことで、ホットキー / Accessibility /
// オーバーレイなど低レベル制御を細かく扱える。
let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.run()
