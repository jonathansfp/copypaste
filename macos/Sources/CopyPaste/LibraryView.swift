import SwiftUI
import AppKit

enum LibrarySection: Hashable {
    case all, pinned, mostUsed
    case kind(ClipKind)

    var title: String {
        switch self {
        case .all: return L("Todos os itens")
        case .pinned: return L("Fixados")
        case .mostUsed: return L("Mais usados")
        case .kind(let k): return k.label
        }
    }

    var symbol: String {
        switch self {
        case .all: return "tray.full"
        case .pinned: return "pin"
        case .mostUsed: return "flame"
        case .kind(let k): return k.symbol
        }
    }
}

struct LibraryView: View {
    @ObservedObject var store = ClipboardStore.shared
    @State private var section: LibrarySection = .all
    @State private var selection: UUID?
    @State private var search = ""
    @State private var grid = false

    private var sections: [LibrarySection] {
        [.all, .pinned, .mostUsed] + ClipKind.allCases.map { .kind($0) }
    }

    private func items(for s: LibrarySection) -> [ClipItem] {
        switch s {
        case .all: return store.items
        case .pinned: return store.items.filter(\.pinned)
        case .mostUsed: return Array(store.items.filter { $0.useCount > 1 }.sorted { $0.useCount > $1.useCount }.prefix(100))
        case .kind(let k): return store.items.filter { $0.kind == k }
        }
    }

    private var visible: [ClipItem] {
        items(for: section).filter { $0.matches(search) }
    }

    var body: some View {
        HStack(spacing: 0) {
            sidebar
                .frame(width: 220)
            Divider()
            middle
                .frame(minWidth: 360, maxWidth: .infinity)
            Divider()
            detail
                .frame(width: 320)
        }
        .frame(minWidth: 960, minHeight: 560)
    }

    // MARK: Sidebar

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                TextField(L("Buscar no histórico"), text: $search).textFieldStyle(.plain)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .background(RoundedRectangle(cornerRadius: 8).fill(Color.primary.opacity(0.06)))
            .padding(.horizontal, 12)
            .padding(.top, 44)
            .padding(.bottom, 12)

            Text(L("Biblioteca")).font(.system(size: 11, weight: .semibold)).foregroundStyle(.secondary)
                .padding(.horizontal, 18).padding(.bottom, 4)

            ForEach(sections, id: \.self) { s in
                sidebarRow(s)
            }

            Divider().padding(.vertical, 8).padding(.horizontal, 12)

            Button { WindowManager.shared.showSettings() } label: {
                HStack(spacing: 10) {
                    Image(systemName: "gearshape").frame(width: 20).foregroundStyle(Color.accentColor)
                    Text(L("Configurações"))
                    Spacer()
                }
                .padding(.horizontal, 10).padding(.vertical, 6)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 8)

            Spacer()
        }
        .background(VisualEffect(material: .sidebar).ignoresSafeArea())
    }

    private func sidebarRow(_ s: LibrarySection) -> some View {
        let on = section == s
        let count = items(for: s).count
        return Button {
            section = s
            selection = nil
        } label: {
            HStack(spacing: 10) {
                Image(systemName: s.symbol).frame(width: 20).foregroundStyle(Color.accentColor)
                Text(s.title).fontWeight(on ? .semibold : .regular)
                Spacer()
                if count > 0 && s != .mostUsed {
                    Text("\(count)").font(.system(size: 11)).foregroundStyle(.secondary)
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(RoundedRectangle(cornerRadius: 7).fill(on ? Color.primary.opacity(0.1) : .clear))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 8)
    }

    // MARK: Middle

    private var middle: some View {
        let list = visible
        return VStack(spacing: 0) {
            HStack {
                Text(section.title).font(.system(size: 17, weight: .semibold))
                Spacer()
                Picker("", selection: $grid) {
                    Image(systemName: "list.bullet").tag(false)
                    Image(systemName: "square.grid.2x2").tag(true)
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .frame(width: 80)
            }
            .padding(.horizontal, 16)
            .padding(.top, 14)
            .padding(.bottom, 10)
            Divider()

            if list.isEmpty {
                VStack(spacing: 8) {
                    Spacer()
                    Image(systemName: "clipboard").font(.system(size: 32)).foregroundStyle(.tertiary)
                    Text(L("Nenhum item")).foregroundStyle(.secondary)
                    Spacer()
                }
                .frame(maxWidth: .infinity)
            } else if grid {
                ScrollView {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 150), spacing: 12)], spacing: 12) {
                        ForEach(list) { item in
                            gridTile(item)
                        }
                    }
                    .padding(14)
                }
            } else {
                List(selection: $selection) {
                    ForEach(list) { item in
                        HStack(spacing: 12) {
                            ClipThumb(item: item, size: 34)
                            VStack(alignment: .leading, spacing: 3) {
                                HStack(spacing: 4) {
                                    if item.pinned { Image(systemName: "pin.fill").font(.system(size: 9)).foregroundStyle(.orange) }
                                    Text(item.title).lineLimit(1)
                                }
                                AppSourceLabel(item: item, showDetail: false)
                            }
                        }
                        .padding(.vertical, 3)
                        .tag(item.id)
                    }
                }
                .listStyle(.inset)
                .contextMenu(forSelectionType: UUID.self) { ids in
                    if let id = ids.first, let item = store.items.first(where: { $0.id == id }) {
                        itemMenu(item)
                    }
                } primaryAction: { ids in
                    if let id = ids.first, let item = store.items.first(where: { $0.id == id }) {
                        ClipboardStore.shared.copy(item)
                    }
                }
            }

            Divider()
            Text(L("%d itens · clique para detalhes · duplo clique ou ↩ para copiar", list.count))
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 16)
                .padding(.vertical, 7)
        }
    }

    @ViewBuilder
    private func itemMenu(_ item: ClipItem) -> some View {
        Button(L("Copiar")) { ClipboardStore.shared.copy(item) }
        Button(item.pinned ? L("Desafixar") : L("Fixar")) { ClipboardStore.shared.togglePin(item) }
        Divider()
        Button(L("Excluir"), role: .destructive) {
            if selection == item.id { selection = nil }
            ClipboardStore.shared.delete(item)
        }
    }

    private func gridTile(_ item: ClipItem) -> some View {
        let on = selection == item.id
        return VStack(alignment: .leading, spacing: 6) {
            ZStack {
                RoundedRectangle(cornerRadius: 10).fill(Color.primary.opacity(0.04))
                if item.kind == .image, let img = ImageCache.shared.thumbnail(for: item, maxPixel: 400) {
                    Image(nsImage: img).resizable().aspectRatio(contentMode: .fill)
                } else if item.kind == .text || item.kind == .code || item.kind == .link {
                    Text(item.text ?? "")
                        .font(.system(size: 10, design: item.kind == .code ? .monospaced : .default))
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                        .padding(8)
                } else {
                    ClipThumb(item: item, size: 56)
                }
            }
            .frame(height: 100)
            .clipShape(RoundedRectangle(cornerRadius: 10))
            Text(item.title).font(.system(size: 12, weight: .medium)).lineLimit(1)
            AppSourceLabel(item: item, showDetail: false)
        }
        .padding(8)
        .background(RoundedRectangle(cornerRadius: 12).fill(on ? Color.accentColor.opacity(0.15) : Color.clear))
        .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(on ? Color.accentColor.opacity(0.6) : Color.primary.opacity(0.08)))
        .contentShape(Rectangle())
        .onTapGesture(count: 2) { ClipboardStore.shared.copy(item) }
        .simultaneousGesture(TapGesture().onEnded { selection = item.id })
        .contextMenu { itemMenu(item) }
    }

    // MARK: Detail

    @ViewBuilder
    private var detail: some View {
        if let id = selection, let item = store.items.first(where: { $0.id == id }) {
            VStack(alignment: .leading, spacing: 0) {
                HStack(spacing: 10) {
                    ClipThumb(item: item, size: 30)
                    Text(item.title).font(.headline).lineLimit(2)
                }
                .padding(.horizontal, 16)
                .padding(.top, 44)
                .padding(.bottom, 12)

                ClipPreview(item: item)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(RoundedRectangle(cornerRadius: 10).fill(Color.primary.opacity(0.04)))
                    .padding(.horizontal, 12)

                Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 6) {
                    info(L("Tipo"), item.kind.label)
                    info(L("Origem"), item.sourceAppName ?? "—")
                    info(L("Copiado"), item.date.formatted(date: .abbreviated, time: .shortened))
                    info(L("Primeira vez"), item.firstCopied.formatted(date: .abbreviated, time: .shortened))
                    info(L("Usos"), "\(item.useCount)")
                    if let d = item.detail { info(L("Detalhe"), d) }
                }
                .font(.system(size: 12))
                .padding(16)

                HStack {
                    Button { ClipboardStore.shared.copy(item) } label: {
                        Label(L("Copiar"), systemImage: "doc.on.doc")
                    }
                    .keyboardShortcut(.return, modifiers: [])
                    .buttonStyle(.borderedProminent)
                    Button { ClipboardStore.shared.togglePin(item) } label: {
                        Label(item.pinned ? L("Desafixar") : L("Fixar"), systemImage: item.pinned ? "pin.slash" : "pin")
                    }
                    Spacer()
                    Button(role: .destructive) {
                        selection = nil
                        ClipboardStore.shared.delete(item)
                    } label: {
                        Image(systemName: "trash")
                    }
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 16)
            }
        } else {
            VStack(spacing: 10) {
                Image(systemName: "sidebar.right").font(.system(size: 34)).foregroundStyle(.tertiary)
                Text(L("Clique em um item para ver os detalhes")).foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private func info(_ k: String, _ v: String) -> some View {
        GridRow {
            Text(k).foregroundStyle(.secondary)
            Text(v).lineLimit(1).textSelection(.enabled)
        }
    }
}
