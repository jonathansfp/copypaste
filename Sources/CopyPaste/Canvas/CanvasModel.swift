import AppKit
import Combine

/// Shared state for the capture editor and the presentation board.
final class CanvasModel: ObservableObject {
    @Published var shapes: [Shape] = [] { didSet { changed.send() } }
    @Published var tool: Tool = .draw(.arrow)
    @Published var style = ShapeStyle()
    @Published var selection: Set<UUID> = [] { didSet { changed.send() } }
    @Published private(set) var canUndo = false
    @Published private(set) var canRedo = false

    /// Fires on anything that needs a redraw (cheaper than observing every published property).
    let changed = PassthroughSubject<Void, Never>()

    private var undoStack: [[Shape]] = []
    private var redoStack: [[Shape]] = []

    static let palette: [NSColor] = [
        .systemRed, .systemOrange, .systemYellow, .systemGreen, .systemTeal, .systemBlue,
        .systemIndigo, .systemPurple, .systemPink, .white, NSColor(white: 0.55, alpha: 1), NSColor(white: 0.08, alpha: 1),
    ]

    /// Call before every user mutation.
    func checkpoint() {
        undoStack.append(shapes)
        if undoStack.count > 300 { undoStack.removeFirst() }
        redoStack.removeAll()
        refreshFlags()
    }

    func undo() {
        guard let prev = undoStack.popLast() else { return }
        redoStack.append(shapes)
        shapes = prev
        selection = selection.filter { id in shapes.contains { $0.id == id } }
        refreshFlags()
    }

    func redo() {
        guard let next = redoStack.popLast() else { return }
        undoStack.append(shapes)
        shapes = next
        refreshFlags()
    }

    private func refreshFlags() {
        canUndo = !undoStack.isEmpty
        canRedo = !redoStack.isEmpty
    }

    var nextStepNumber: Int { (shapes.filter { $0.kind == .step }.map(\.number).max() ?? 0) + 1 }

    var selectedShapes: [Shape] { shapes.filter { selection.contains($0.id) } }

    /// Changes the current style and applies it to the selected shapes.
    func updateStyle(_ change: (inout ShapeStyle) -> Void) {
        change(&style)
        guard !selection.isEmpty else { return }
        checkpoint()
        for i in shapes.indices where selection.contains(shapes[i].id) {
            change(&shapes[i].style)
        }
    }

    func deleteSelection() {
        guard !selection.isEmpty else { return }
        checkpoint()
        shapes.removeAll { selection.contains($0.id) }
        selection = []
    }

    func duplicateSelection() {
        guard !selection.isEmpty else { return }
        checkpoint()
        var newIDs: Set<UUID> = []
        for s in selectedShapes {
            var c = s
            c.id = UUID()
            c.seed = .random(in: 1...UInt64.max)
            c.offset(dx: 20, dy: 20)
            if c.kind == .step { c.number = nextStepNumber }
            shapes.append(c)
            newIDs.insert(c.id)
        }
        selection = newIDs
    }

    func bringToFront() {
        guard !selection.isEmpty else { return }
        checkpoint()
        let sel = shapes.filter { selection.contains($0.id) }
        shapes.removeAll { selection.contains($0.id) }
        shapes.append(contentsOf: sel)
    }

    func sendToBack() {
        guard !selection.isEmpty else { return }
        checkpoint()
        let sel = shapes.filter { selection.contains($0.id) }
        shapes.removeAll { selection.contains($0.id) }
        shapes.insert(contentsOf: sel, at: 0)
    }

    func clear() {
        guard !shapes.isEmpty else { return }
        checkpoint()
        shapes = []
        selection = []
    }
}
