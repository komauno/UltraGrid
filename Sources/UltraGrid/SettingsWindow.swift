import AppKit
import SwiftUI

/// 設定ウィンドウの表示を管理する（メニュー「設定…」から呼ぶ）。
/// アイコン付きタブ（現代的な macOS の設定風）にするため NSTabViewController を使う。
final class SettingsWindowController: NSObject, NSWindowDelegate {

    static let shared = SettingsWindowController()
    private var window: NSWindow?

    private let contentWidth: CGFloat = 600
    private let contentHeight: CGFloat = 480

    func show() {
        if window == nil {
            let tabVC = NSTabViewController()
            tabVC.tabStyle = .toolbar

            tabVC.addTabViewItem(makeTab("一般", "gearshape", GeneralSettingsView()))
            tabVC.addTabViewItem(makeTab("スナップ", "square.grid.3x3", GridSettingsView()))
            tabVC.addTabViewItem(makeTab("ショートカット", "command", ShortcutSettingsView()))

            tabVC.title = "UltraGrid 設定"          // NSTabViewController が持つタイトルにも設定
            let win = NSWindow(contentViewController: tabVC)
            win.styleMask = [.titled, .closable, .miniaturizable]   // サイズ固定（リサイズ不可）
            win.titleVisibility = .visible
            win.isReleasedWhenClosed = false
            win.delegate = self
            win.setContentSize(NSSize(width: contentWidth, height: contentHeight))
            win.center()
            window = win
        }
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
        window?.title = "UltraGrid 設定"            // contentViewController バインドに上書きされないよう最後に設定
    }

    private func makeTab<V: View>(_ title: String, _ symbol: String, _ view: V) -> NSTabViewItem {
        // 固定サイズを与えてウィンドウ幅が content まで広がるようにする。
        let host = NSHostingController(rootView: view.frame(width: contentWidth, height: contentHeight))
        let item = NSTabViewItem(viewController: host)
        item.label = title
        item.image = NSImage(systemSymbolName: symbol, accessibilityDescription: title)
        return item
    }

    func windowWillClose(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
    }
}

// MARK: - 一般

struct GeneralSettingsView: View {
    @ObservedObject private var store = SettingsStore.shared

    var body: some View {
        Form {
            Section("ドラッグスナップ") {
                Toggle("修飾キーを押しながらドラッグでスナップ", isOn: $store.settings.dragSnapEnabled)
                Picker("ドラッグスナップの修飾キー", selection: $store.settings.dragSnapModifier) {
                    // 範囲選択キーと重複しないよう、そのキーは選択肢から除外する。
                    ForEach(ModifierKey.allCases.filter { $0 != store.settings.dragRangeModifier }) {
                        Text($0.label).tag($0)
                    }
                }
                .disabled(!store.settings.dragSnapEnabled)
                Picker("範囲選択の追加キー", selection: $store.settings.dragRangeModifier) {
                    ForEach(ModifierKey.allCases.filter { $0 != store.settings.dragSnapModifier }) {
                        Text($0.label).tag($0)
                    }
                }
                .disabled(!store.settings.dragSnapEnabled)
                Text("ドラッグスナップの修飾キーを押しながらウィンドウをドラッグすると、離した位置のグリッドにスナップします。さらに範囲選択の追加キーを押している間は、スナップするグリッドの範囲を選択できます。")
                    .font(.caption).foregroundColor(.secondary).fixedSize(horizontal: false, vertical: true)
            }
            Section {
                Toggle("ログイン時に UltraGrid を起動する", isOn: $store.settings.launchAtLogin)
            }
            Section("隙間と余白") {
                PxRow(title: "ウィンドウ間の隙間", value: $store.settings.gap)
                PxRow(title: "画面端の余白", value: $store.settings.outerMargin)
            }
        }
        .formStyle(.grouped)
    }
}

/// px 値の行（ラベル幅を固定してスライダ長を揃え、値はテキストフィールドで直接入力可）。
struct PxRow: View {
    let title: String
    @Binding var value: Double
    var range: ClosedRange<Double> = 0...20

    var body: some View {
        HStack(spacing: 7) {
            Text(title).frame(width: 130, alignment: .leading)
            Slider(value: $value, in: range)
            TextField("", value: $value, format: .number.precision(.fractionLength(0)))
                .textFieldStyle(.roundedBorder)
                .multilineTextAlignment(.trailing)
                .font(.body.monospacedDigit())        // 桁数で幅がぶれないように
                .frame(width: 64)                      // 高さは自然サイズ（フォーカス枠が収まる）
                .fixedSize(horizontal: false, vertical: true)
            Text("px").foregroundColor(.secondary).frame(width: 20, alignment: .leading)
        }
        .onChange(of: value) { newValue in
            let clamped = min(max(newValue.rounded(), range.lowerBound), range.upperBound)
            if clamped != value { value = clamped }
        }
    }
}

// MARK: - グリッド

/// 全幅に等分割されるセグメントコントロール（macOS 標準のサウンド設定と同じ見た目）。
/// SwiftUI の segmented Picker は内容幅に縮むため、NSSegmentedControl を全幅で使う。
struct FullWidthSegmented: NSViewRepresentable {
    let items: [(id: String, label: String)]
    @Binding var selection: String

    func makeNSView(context: Context) -> NSSegmentedControl {
        let seg = NSSegmentedControl()
        seg.trackingMode = .selectOne
        seg.segmentDistribution = .fillEqually
        seg.target = context.coordinator
        seg.action = #selector(Coordinator.changed(_:))
        seg.setContentHuggingPriority(.defaultLow, for: .horizontal)
        seg.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        return seg
    }

    func updateNSView(_ seg: NSSegmentedControl, context: Context) {
        context.coordinator.parent = self
        if seg.segmentCount != items.count { seg.segmentCount = items.count }
        for (i, it) in items.enumerated() {
            if seg.label(forSegment: i) != it.label { seg.setLabel(it.label, forSegment: i) }
            seg.setWidth(0, forSegment: i)   // 0 = fillEqually に委ねる
        }
        if let idx = items.firstIndex(where: { $0.id == selection }), seg.selectedSegment != idx {
            seg.selectedSegment = idx
        }
    }

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    final class Coordinator: NSObject {
        var parent: FullWidthSegmented
        init(_ parent: FullWidthSegmented) { self.parent = parent }
        @objc func changed(_ sender: NSSegmentedControl) {
            let i = sender.selectedSegment
            guard i >= 0, i < parent.items.count else { return }
            parent.selection = parent.items[i].id
        }
    }
}

struct GridSettingsView: View {
    @ObservedObject private var store = SettingsStore.shared
    @State private var selectedKey: String = ""

    private struct DisplayItem: Identifiable { let id: String; let label: String }

    /// 接続中のディスプレイ一覧（同名は連番で区別）。
    private var displays: [DisplayItem] {
        var seen: [String: Int] = [:]
        return NSScreen.screens.map { sc in
            let base = sc.ultraGridLabel
            seen[base, default: 0] += 1
            let label = seen[base]! > 1 ? "\(base) (\(seen[base]!))" : base
            return DisplayItem(id: sc.ultraGridKey, label: label)
        }
    }

    /// 有効な選択キー（無効なら先頭のディスプレイ）。
    private var activeKey: String {
        displays.contains(where: { $0.id == selectedKey }) ? selectedKey : (displays.first?.id ?? "")
    }

    private var activeSpec: GridSpec {
        (activeKey.isEmpty ? nil : store.settings.displayGrids[activeKey])?.clamped() ?? store.settings.gridSpec
    }

    /// 選択中ディスプレイの画面比率（縦 / 横）。
    private var activeAspect: CGFloat? {
        guard let sc = NSScreen.screens.first(where: { $0.ultraGridKey == activeKey }) else { return nil }
        let f = sc.frame.size
        return f.width > 0 ? f.height / f.width : nil
    }

    var body: some View {
        VStack(spacing: 0) {
            // モニタ切り替えのセグメントバーは最上部・全幅に配置する。
            if displays.count > 1 {
                FullWidthSegmented(items: displays.map { ($0.id, $0.label) },
                                   selection: Binding(get: { activeKey }, set: { selectedKey = $0 }))
                    .frame(maxWidth: .infinity)
                    .padding(.horizontal, 20)
                    .padding(.top, 16)
                    .padding(.bottom, 6)
            }

            Form {
                Section("スナップに使用するグリッド") {
                    IntRow(title: "横方向", value: gridBinding(\.cols), range: 1...6)
                    IntRow(title: "縦方向", value: gridBinding(\.rows), range: 1...6)
                    Text(displays.count > 1
                         ? "このディスプレイにおける、スナップピッカーとドラッグスナップで使うグリッドの分割数を設定します。"
                         : "スナップピッカーとドラッグスナップで使うグリッドの分割数を設定します。")
                        .font(.caption).foregroundColor(.secondary).fixedSize(horizontal: false, vertical: true)
                }
                Section("プレビュー") {
                    HStack {
                        Spacer()
                        BlueGridView(spec: activeSpec, aspect: activeAspect)
                        Spacer()
                    }
                    .padding(.vertical, 12)
                }
            }
            .formStyle(.grouped)
        }
        .onAppear {
            if !displays.contains(where: { $0.id == selectedKey }) {
                selectedKey = displays.first?.id ?? ""
            }
        }
    }

    /// 選択中モニタの cols / rows への Binding（未登録なら既定値をシードして作成）。
    private func gridBinding(_ key: WritableKeyPath<GridSpec, Int>) -> Binding<Int> {
        Binding(
            get: { activeSpec[keyPath: key] },
            set: { newValue in
                let target = activeKey
                var s = (target.isEmpty ? nil : store.settings.displayGrids[target]) ?? store.settings.gridSpec
                s[keyPath: key] = newValue
                if target.isEmpty {
                    // ディスプレイを識別できない場合は既定グリッドに書き込む。
                    store.settings.gridCols = s.clamped().cols
                    store.settings.gridRows = s.clamped().rows
                } else {
                    store.settings.displayGrids[target] = s.clamped()
                }
            }
        )
    }
}

/// 分割数と画面比率を反映した青色グリッド。
/// `selection` を渡すと表示のみ、`interactive` を渡すとドラッグで範囲選択できる。
struct BlueGridView: View {
    let spec: GridSpec
    var selection: GridZone? = nil
    var interactive: Binding<GridZone>? = nil
    var width: CGFloat = 200
    /// 画面比率（縦 / 横）。nil ならメインスクリーンの比率を使う。
    var aspect: CGFloat? = nil

    @State private var dragStart: (col: Int, row: Int)? = nil

    private var size: CGSize {
        let ratio: CGFloat
        if let aspect, aspect > 0 {
            ratio = aspect
        } else {
            let screen = NSScreen.main?.frame.size ?? CGSize(width: 16, height: 9)
            ratio = screen.width > 0 ? screen.height / screen.width : 0.5
        }
        let h = min(max(width * ratio, 40), 240)   // 極端な比率でも収まるようクランプ
        return CGSize(width: width, height: h)
    }

    var body: some View {
        let s = size
        let shown = interactive?.wrappedValue ?? selection
        let canvas = Canvas { context, canvasSize in
            draw(context, canvasSize, zone: shown)
        }
        .frame(width: s.width, height: s.height)
        .contentShape(Rectangle())

        if let interactive {
            canvas.gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { v in handleDrag(v.location, size: s, binding: interactive) }
                    .onEnded { _ in dragStart = nil }
            )
        } else {
            canvas
        }
    }

    private func handleDrag(_ location: CGPoint, size: CGSize, binding: Binding<GridZone>) {
        let s = spec.clamped()
        let cw = size.width / CGFloat(s.cols)
        let ch = size.height / CGFloat(s.rows)
        let col = min(max(Int(location.x / cw), 0), s.cols - 1)
        let row = min(max(Int(location.y / ch), 0), s.rows - 1)  // Canvas は上原点なので row0 が上
        if dragStart == nil { dragStart = (col, row) }
        let a = dragStart!
        binding.wrappedValue = GridZone(
            col: min(a.col, col), row: min(a.row, row),
            colSpan: abs(a.col - col) + 1, rowSpan: abs(a.row - row) + 1
        )
    }

    private func draw(_ context: GraphicsContext, _ canvasSize: CGSize, zone: GridZone?) {
        let s = spec.clamped()
        let rect = CGRect(origin: .zero, size: canvasSize)
        let accent = Color.accentColor
        let cw = canvasSize.width / CGFloat(s.cols)
        let ch = canvasSize.height / CGFloat(s.rows)

        // 全体の薄い塗り。
        context.fill(Path(roundedRect: rect, cornerRadius: 6), with: .color(accent.opacity(0.12)))

        // 選択範囲の塗り。地の塗りと同じ角丸でクリップして隅からはみ出さないようにする。
        if let zone {
            let z = zone.clamped(to: s)
            let sel = CGRect(x: cw * CGFloat(z.col), y: ch * CGFloat(z.row),
                             width: cw * CGFloat(z.colSpan), height: ch * CGFloat(z.rowSpan))
            var clipped = context
            clipped.clip(to: Path(roundedRect: rect, cornerRadius: 6))
            clipped.fill(Path(sel), with: .color(accent.opacity(0.38)))
        }

        // 内側のグリッド線。
        var lines = Path()
        for i in 1..<s.cols {
            let x = cw * CGFloat(i)
            lines.move(to: CGPoint(x: x, y: 0)); lines.addLine(to: CGPoint(x: x, y: canvasSize.height))
        }
        for j in 1..<s.rows {
            let y = ch * CGFloat(j)
            lines.move(to: CGPoint(x: 0, y: y)); lines.addLine(to: CGPoint(x: canvasSize.width, y: y))
        }
        context.stroke(lines, with: .color(accent.opacity(0.55)), lineWidth: 1)

        // 外枠。
        context.stroke(Path(roundedRect: rect.insetBy(dx: 0.5, dy: 0.5), cornerRadius: 6),
                       with: .color(accent), lineWidth: 1.5)
    }
}

/// 整数値の行（テキストフィールド + ステッパー、キーボード入力可）。
struct IntRow: View {
    let title: String
    @Binding var value: Int
    let range: ClosedRange<Int>

    var body: some View {
        HStack(spacing: 8) {
            Text(title).frame(width: 130, alignment: .leading)
            Spacer()                                   // 入力欄を右寄せにする
            TextField("", value: $value, format: .number)
                .textFieldStyle(.roundedBorder)
                .multilineTextAlignment(.trailing)
                .font(.body.monospacedDigit())
                .frame(width: 48)
                .fixedSize(horizontal: false, vertical: true)
            Stepper("", value: $value, in: range).labelsHidden()
        }
        .onChange(of: value) { newValue in
            let clamped = min(max(newValue, range.lowerBound), range.upperBound)
            if clamped != value { value = clamped }
        }
    }
}

// MARK: - ショートカット / クイック操作

struct ShortcutSettingsView: View {
    @ObservedObject private var store = SettingsStore.shared

    /// スナップピッカー系（配置ではない）。
    private var pickerActions: [GridAction] { store.settings.actions.filter { $0.kind != .placeZone } }
    /// 並べ替え対象のクイック操作（グリッド配置）。
    private var quickActions: [GridAction] { store.settings.actions.filter { $0.kind == .placeZone } }

    var body: some View {
        VStack(spacing: 0) {
            List {
                Section {
                    Text("操作にショートカットを割り当てられます。ドラッグすると並び順を変更できます。")
                        .font(.caption).foregroundColor(.secondary)
                }

                // スナップピッカーは他のクイック操作とは独立したグループにする。
                Section("スナップピッカーを開く") {
                    ForEach(pickerActions) { action in
                        ShortcutListRow(action: action) {
                            ActionEditWindowController.shared.open(action.id)
                        }
                    }
                }

                Section("クイック操作") {
                    ForEach(quickActions) { action in
                        ShortcutListRow(action: action) {
                            ActionEditWindowController.shared.open(action.id)
                        }
                    }
                    .onMove(perform: moveQuick)
                }
            }
            .listStyle(.inset)
            .scrollIndicators(.visible)     // 縦幅を超えたらスクロールバーを常時表示
            .frame(maxHeight: .infinity)

            // 追加 / 既定に戻す（グルーピングせず、下部のバーに配置）。
            HStack {
                Button {
                    let new = GridAction(name: "新しい操作", spec: store.settings.gridSpec,
                                         zone: GridZone(col: 0, row: 0, colSpan: 1, rowSpan: 1))
                    store.settings.actions.append(new)
                    ActionEditWindowController.shared.open(new.id)   // 追加後すぐ編集
                } label: { Label("操作を追加", systemImage: "plus") }
                Spacer()
                Button("既定に戻す") { confirmResetToDefaults() }
                    .foregroundColor(.red)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 12)
        }
    }

    /// 「既定に戻す」前に確認アラートを表示する。
    private func confirmResetToDefaults() {
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = "クイック操作を既定に戻しますか？"
        alert.informativeText = "現在のクイック操作はすべて破棄されます。"
        alert.addButton(withTitle: "既定に戻す")   // 先頭が既定ボタン
        alert.addButton(withTitle: "キャンセル")
        if let cancel = alert.buttons.last { cancel.keyEquivalent = "\u{1b}" }  // Esc で取消
        if alert.runModal() == .alertFirstButtonReturn {
            store.settings.actions = Settings.defaultActions
        }
    }

    /// クイック操作だけを並べ替え、ピッカー系は先頭に据え置く。
    /// store.settings.actions の順序がそのままメニューバーの順序になる。
    private func moveQuick(from source: IndexSet, to destination: Int) {
        var quick = quickActions
        quick.move(fromOffsets: source, toOffset: destination)
        store.settings.actions = pickerActions + quick
    }
}

/// ショートカット一覧の 1 行（表示のみ + 編集ボタン）。
struct ShortcutListRow: View {
    let action: GridAction
    var onEdit: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Text(action.name).lineLimit(1)
            Spacer()
            Text(action.hotkey?.display ?? "未設定")
                .font(.system(.body, design: .rounded))
                .foregroundColor(action.hotkey == nil ? .secondary : .primary)
            Button("編集", action: onEdit)
        }
        .padding(.vertical, 8)          // 行間（横区切り線の間隔）を広げてモダンに
    }
}

// MARK: - ショートカット編集ウィンドウ

/// 「編集」で開く別ウィンドウを管理する。
final class ActionEditWindowController: NSObject, NSWindowDelegate {
    static let shared = ActionEditWindowController()
    private var windows: [UUID: NSWindow] = [:]

    func open(_ id: UUID) {
        if let win = windows[id] {
            win.makeKeyAndOrderFront(nil)
            return
        }
        let host = NSHostingController(rootView: ActionEditView(actionID: id) { [weak self] in self?.close(id) })
        let win = NSWindow(contentViewController: host)
        win.title = "ショートカットを編集"
        win.styleMask = [.titled, .closable]
        win.isReleasedWhenClosed = false
        win.delegate = self
        win.setContentSize(NSSize(width: 380, height: 464))
        win.center()
        windows[id] = win
        NSApp.activate(ignoringOtherApps: true)
        win.makeKeyAndOrderFront(nil)
    }

    func close(_ id: UUID) {
        windows[id]?.close()
        windows[id] = nil
    }

    func windowWillClose(_ notification: Notification) {
        guard let win = notification.object as? NSWindow else { return }
        windows = windows.filter { $0.value != win }
    }
}

/// ショートカット 1 件の編集ビュー（別ウィンドウの中身）。
struct ActionEditView: View {
    let actionID: UUID
    var onClose: () -> Void
    @ObservedObject private var store = SettingsStore.shared

    var body: some View {
        if store.settings.actions.contains(where: { $0.id == actionID }) {
            let action = binding()
            VStack(alignment: .leading, spacing: 18) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("名称").font(.caption).foregroundColor(.secondary)
                    TextField("", text: action.name).textFieldStyle(.roundedBorder)
                }

                if action.wrappedValue.kind == .placeZone {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("クイック操作に使用するグリッド").font(.caption).foregroundColor(.secondary)
                        IntRow(title: "横方向", value: action.spec.cols, range: 1...6)
                        IntRow(title: "縦方向", value: action.spec.rows, range: 1...6)
                    }

                    VStack(spacing: 8) {
                        Text("配置").font(.caption).foregroundColor(.secondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                        HStack {
                            Spacer()
                            BlueGridView(spec: action.wrappedValue.spec, interactive: action.zone, width: 240)
                            Spacer()
                        }
                        Text("グリッド上をドラッグして範囲を選択")
                            .font(.caption2).foregroundColor(.secondary)
                            .frame(maxWidth: .infinity, alignment: .center)
                    }
                    // 分割数を変えたら選択ゾーンを新しい分割数に丸め込む。
                    .onChange(of: action.wrappedValue.spec) { newSpec in
                        let z = action.wrappedValue.zone.clamped(to: newSpec)
                        if z != action.wrappedValue.zone { action.wrappedValue.zone = z }
                    }
                } else {
                    Text("スナップピッカーを開くと、現在使用しているウィンドウを配置するグリッドの範囲を選択できます。")
                        .font(.caption).foregroundColor(.secondary).fixedSize(horizontal: false, vertical: true)
                }

                VStack(alignment: .leading, spacing: 4) {
                    Text("ショートカットキー").font(.caption).foregroundColor(.secondary)
                    KeyRecorderField(hotkey: action.hotkey)
                }

                Spacer()

                HStack {
                    // スナップピッカーは削除できないため、削除ボタンは配置操作にのみ表示する。
                    if action.wrappedValue.kind == .placeZone {
                        Button(role: .destructive) {
                            store.settings.actions.removeAll { $0.id == actionID }
                            onClose()
                        } label: { Label("削除", systemImage: "trash") }
                    }
                    Spacer()
                    Button("完了") { onClose() }.keyboardShortcut(.defaultAction)
                }
            }
            .padding(20)
            .frame(width: 380)
        } else {
            Color.clear.frame(width: 380, height: 1).onAppear { onClose() }
        }
    }

    /// ストア内の該当アクションへの Binding を作る（id で常に引き直す）。
    private func binding() -> Binding<GridAction> {
        Binding(
            get: { store.settings.actions.first(where: { $0.id == actionID }) ?? GridAction(name: "") },
            set: { newValue in
                if let i = store.settings.actions.firstIndex(where: { $0.id == actionID }) {
                    store.settings.actions[i] = newValue
                }
            }
        )
    }
}

// MARK: - キーレコーダ

/// クリックすると次のキー入力を記録してショートカットに設定するフィールド。
struct KeyRecorderField: View {
    @Binding var hotkey: Hotkey?
    @State private var recording = false
    @State private var monitor: Any?

    var body: some View {
        HStack(spacing: 6) {
            Button(action: toggle) {
                Text(recording ? "キーを入力…" : (hotkey?.display ?? "未設定"))
                    .frame(width: 96)
                    .foregroundColor(recording ? .accentColor : .primary)
            }
            .buttonStyle(.bordered)

            Button { hotkey = nil } label: { Image(systemName: "xmark.circle.fill") }
                .buttonStyle(.borderless)
                .foregroundColor(.secondary)
                .opacity(hotkey == nil ? 0.25 : 1)
                .disabled(hotkey == nil)
                .help("ショートカットを解除")
        }
        .onDisappear { stop() }
    }

    private func toggle() { recording ? stop() : startRecording() }

    private func startRecording() {
        recording = true
        monitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown]) { event in
            if event.keyCode == 53 { stop(); return nil }   // ESC で取消
            hotkey = Hotkey.from(event: event)
            stop()
            return nil
        }
    }

    private func stop() {
        recording = false
        if let m = monitor { NSEvent.removeMonitor(m); monitor = nil }
    }
}
