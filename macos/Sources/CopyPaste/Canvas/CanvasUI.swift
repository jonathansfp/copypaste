import SwiftUI
import AppKit

/// UI-only state shared by the floating toolbars.
final class CanvasUIState: ObservableObject {
    @Published var showStyle = false
}

private let barBackground = Color(nsColor: NSColor(white: 0.13, alpha: 0.94))

struct BarBackground: ViewModifier {
    func body(content: Content) -> some View {
        content
            .background(barBackground, in: RoundedRectangle(cornerRadius: 11, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 11, style: .continuous).strokeBorder(Color.white.opacity(0.12)))
            .shadow(color: .black.opacity(0.35), radius: 10, y: 3)
            .environment(\.colorScheme, .dark)
    }
}

extension View {
    func floatingBar() -> some View { modifier(BarBackground()) }
}

struct IconButton: View {
    let symbol: String
    let help: String
    var active = false
    var tint: Color = .white
    var disabled = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(active ? Color.white : tint.opacity(disabled ? 0.35 : 0.92))
                .frame(width: 30, height: 30)
                .background(active ? Color.accentColor : Color.clear, in: RoundedRectangle(cornerRadius: 7, style: .continuous))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(disabled)
        .help(help)
    }
}

struct ToolButton: View {
    @ObservedObject var model: CanvasModel
    let tool: Tool

    var body: some View {
        IconButton(symbol: tool.symbol, help: tool.label + (tool.key.map { "  (\($0))" } ?? ""),
                   active: model.tool == tool) { model.tool = tool }
    }
}

struct ColorDot: View {
    let color: NSColor
    var size: CGFloat = 18
    var selected = false

    var body: some View {
        Circle()
            .fill(Color(nsColor: color))
            .frame(width: size, height: size)
            .overlay(Circle().strokeBorder(Color.white.opacity(0.35), lineWidth: 1))
            .padding(3)
            .overlay(Circle().strokeBorder(selected ? Color.white : .clear, lineWidth: 2))
    }
}

extension NSColor {
    func isSameColor(_ o: NSColor) -> Bool {
        guard let a = usingColorSpace(.sRGB), let b = o.usingColorSpace(.sRGB) else { return false }
        return abs(a.redComponent - b.redComponent) < 0.01 && abs(a.greenComponent - b.greenComponent) < 0.01
            && abs(a.blueComponent - b.blueComponent) < 0.01
    }
}

/// Button that shows the current color and opens the style panel.
struct StyleToggle: View {
    @ObservedObject var model: CanvasModel
    @ObservedObject var ui: CanvasUIState

    var body: some View {
        Button { ui.showStyle.toggle() } label: {
            ZStack {
                RoundedRectangle(cornerRadius: 7).fill(ui.showStyle ? Color.accentColor : .clear).frame(width: 30, height: 30)
                ColorDot(color: model.style.color, size: 18)
            }
        }
        .buttonStyle(.plain)
        .help("Cor, espessura, preenchimento e fonte")
    }
}

/// Colors, stroke width, fill, dash, hand-drawn style and font.
struct StylePanel: View {
    @ObservedObject var model: CanvasModel
    var columns = 6

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            let rows = stride(from: 0, to: CanvasModel.palette.count, by: columns).map {
                Array(CanvasModel.palette[$0..<min($0 + columns, CanvasModel.palette.count)])
            }
            VStack(spacing: 2) {
                ForEach(rows.indices, id: \.self) { r in
                    HStack(spacing: 2) {
                        ForEach(rows[r].indices, id: \.self) { c in
                            let color = rows[r][c]
                            Button { model.updateStyle { $0.color = color } } label: {
                                ColorDot(color: color, selected: model.style.color.isSameColor(color))
                            }
                            .buttonStyle(.plain)
                            .help("Atalho: \(r * columns + c + 1 <= 9 ? "\(r * columns + c + 1)" : "—")")
                        }
                    }
                }
            }

            row("Espessura") {
                ForEach([2.0, 4.0, 7.0, 11.0], id: \.self) { w in
                    choice(active: model.style.width == w, help: "\(Int(w)) pt") {
                        model.updateStyle { $0.width = w }
                    } label: {
                        Capsule().fill(Color.white).frame(width: 16, height: max(1.5, w * 0.8))
                    }
                }
            }

            row("Preenchimento") {
                choice(active: model.style.fill == .none, help: "Sem preenchimento") { model.updateStyle { $0.fill = .none } } label: {
                    RoundedRectangle(cornerRadius: 3).strokeBorder(Color.white, lineWidth: 1.5).frame(width: 16, height: 14)
                }
                choice(active: model.style.fill == .soft, help: "Preenchimento suave") { model.updateStyle { $0.fill = .soft } } label: {
                    RoundedRectangle(cornerRadius: 3).fill(Color(nsColor: model.style.color).opacity(0.35))
                        .overlay(RoundedRectangle(cornerRadius: 3).strokeBorder(Color.white, lineWidth: 1.5)).frame(width: 16, height: 14)
                }
                choice(active: model.style.fill == .solid, help: "Preenchimento sólido") { model.updateStyle { $0.fill = .solid } } label: {
                    RoundedRectangle(cornerRadius: 3).fill(Color(nsColor: model.style.color)).frame(width: 16, height: 14)
                }
            }

            row("Traço") {
                choice(active: !model.style.dashed, help: "Contínuo") { model.updateStyle { $0.dashed = false } } label: {
                    Rectangle().fill(Color.white).frame(width: 18, height: 2)
                }
                choice(active: model.style.dashed, help: "Tracejado") { model.updateStyle { $0.dashed = true } } label: {
                    HStack(spacing: 2) { ForEach(0..<3) { _ in Rectangle().fill(Color.white).frame(width: 4, height: 2) } }
                }
                choice(active: model.style.sketchy, help: "Estilo desenhado à mão (como Excalidraw)") {
                    model.updateStyle { $0.sketchy.toggle() }
                } label: {
                    Image(systemName: "scribble.variable").font(.system(size: 13))
                }
            }

            row("Texto") {
                Menu {
                    ForEach(FontChoice.allCases) { f in
                        Button(f.label) { model.updateStyle { $0.font = f } }
                    }
                } label: {
                    Text(model.style.font.label).font(.system(size: 11)).frame(width: 74, alignment: .leading)
                }
                .menuStyle(.borderlessButton)
                .fixedSize()
                choice(active: false, help: "Diminuir fonte") { model.updateStyle { $0.fontSize = max(10, $0.fontSize - 4) } } label: {
                    Image(systemName: "textformat.size.smaller").font(.system(size: 12))
                }
                Text("\(Int(model.style.fontSize))").font(.system(size: 11, design: .monospaced)).frame(width: 22)
                choice(active: false, help: "Aumentar fonte") { model.updateStyle { $0.fontSize = min(160, $0.fontSize + 4) } } label: {
                    Image(systemName: "textformat.size.larger").font(.system(size: 12))
                }
            }
        }
        .foregroundStyle(.white)
        .padding(10)
        .floatingBar()
    }

    private func row<C: View>(_ title: String, @ViewBuilder _ content: () -> C) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title).font(.system(size: 10, weight: .medium)).foregroundStyle(.white.opacity(0.55))
            HStack(spacing: 3) { content() }
        }
    }

    private func choice<L: View>(active: Bool, help: String, action: @escaping () -> Void, @ViewBuilder label: () -> L) -> some View {
        Button(action: action) {
            label()
                .frame(width: 28, height: 24)
                .background(active ? Color.accentColor : Color.white.opacity(0.07), in: RoundedRectangle(cornerRadius: 6))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(help)
    }
}

/// Menu with the Excalidraw-style component library.
struct LibraryMenu: View {
    @ObservedObject var model: CanvasModel

    var body: some View {
        Menu {
            ForEach(ShapeKind.library, id: \.self) { k in
                Button { model.tool = .draw(k) } label: { Label(k.label, systemImage: k.symbol) }
            }
        } label: {
            Image(systemName: "square.grid.2x2")
                .font(.system(size: 14, weight: .medium))
                .frame(width: 30, height: 30)
                .background(isLibraryTool ? Color.accentColor : .clear, in: RoundedRectangle(cornerRadius: 7))
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
        .help("Componentes: nota, banco de dados, pessoa, nuvem, balão, janela, celular…")
    }

    private var isLibraryTool: Bool {
        if case .draw(let k) = model.tool { return ShapeKind.library.contains(k) }
        return false
    }
}
