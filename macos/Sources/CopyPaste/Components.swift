import SwiftUI
import AppKit

struct VisualEffect: NSViewRepresentable {
    var material: NSVisualEffectView.Material = .popover
    var blending: NSVisualEffectView.BlendingMode = .behindWindow

    func makeNSView(context: Context) -> NSVisualEffectView {
        let v = NSVisualEffectView()
        v.material = material
        v.blendingMode = blending
        v.state = .active
        return v
    }

    func updateNSView(_ v: NSVisualEffectView, context: Context) {
        v.material = material
        v.blendingMode = blending
    }
}

/// Leading thumbnail: image preview, color swatch, file icon or type symbol.
struct ClipThumb: View {
    let item: ClipItem
    var size: CGFloat = 36

    var body: some View {
        Group {
            switch item.kind {
            case .image:
                if let img = ImageCache.shared.thumbnail(for: item, maxPixel: Int(size * 3)) {
                    Image(nsImage: img).resizable().aspectRatio(contentMode: .fill)
                } else {
                    symbolTile
                }
            case .color:
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color(nsColor: ColorParser.parse(item.text ?? "") ?? .clear))
            case .file:
                if let path = item.fileURLs.first?.path {
                    Image(nsImage: NSWorkspace.shared.icon(forFile: path)).resizable().aspectRatio(contentMode: .fit)
                } else {
                    symbolTile
                }
            default:
                symbolTile
            }
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(Color.primary.opacity(0.08), lineWidth: 1))
    }

    private var symbolTile: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 8).fill(tint.opacity(0.14))
            Image(systemName: item.kind.symbol)
                .font(.system(size: size * 0.4, weight: .medium))
                .foregroundStyle(tint)
        }
    }

    private var tint: Color {
        switch item.kind {
        case .link: return .teal
        case .code: return .purple
        case .image: return .orange
        default: return .blue
        }
    }
}

/// Large preview used by the panel (Space) and the library detail.
struct ClipPreview: View {
    let item: ClipItem

    var body: some View {
        switch item.kind {
        case .image:
            if let img = ImageCache.shared.fullImage(for: item) {
                Image(nsImage: img)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                Text(L("Imagem não encontrada")).foregroundStyle(.secondary)
            }
        case .color:
            VStack(spacing: 12) {
                RoundedRectangle(cornerRadius: 14)
                    .fill(Color(nsColor: ColorParser.parse(item.text ?? "") ?? .clear))
                    .frame(height: 140)
                    .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(Color.primary.opacity(0.1)))
                Text(item.text ?? "").font(.system(.title3, design: .monospaced)).textSelection(.enabled)
            }
            .padding()
        case .file:
            ScrollView {
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(item.fileURLs, id: \.self) { url in
                        HStack {
                            Image(nsImage: NSWorkspace.shared.icon(forFile: url.path))
                                .resizable().frame(width: 28, height: 28)
                            VStack(alignment: .leading) {
                                Text(url.lastPathComponent)
                                Text(url.deletingLastPathComponent().path).font(.caption).foregroundStyle(.secondary)
                            }
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding()
            }
        default:
            ScrollView {
                Text(item.text ?? "")
                    .font(item.kind == .code ? .system(size: 12, design: .monospaced) : .system(size: 13))
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding()
            }
        }
    }
}

struct AppSourceLabel: View {
    let item: ClipItem
    var now: Date = Date()
    var showDetail = true

    var body: some View {
        HStack(spacing: 4) {
            if let icon = ImageCache.shared.appIcon(bundleID: item.sourceBundleID) {
                Image(nsImage: icon).resizable().frame(width: 13, height: 13)
            }
            Text(metaText).lineLimit(1)
        }
        .font(.system(size: 11))
        .foregroundStyle(.secondary)
    }

    private var metaText: String {
        var parts: [String] = []
        if let app = item.sourceAppName { parts.append(app) }
        parts.append(TimeText.relative(item.date, now: now))
        if showDetail, let d = item.detail { parts.append(d) }
        return parts.joined(separator: " · ")
    }
}
