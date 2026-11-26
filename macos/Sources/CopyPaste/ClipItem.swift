import AppKit

enum ClipKind: String, Codable, CaseIterable, Identifiable {
    case text, link, image, color, code, file
    var id: String { rawValue }

    var label: String {
        switch self {
        case .text: return L("Texto")
        case .link: return L("Links")
        case .image: return L("Imagens")
        case .color: return L("Cores")
        case .code: return L("Código")
        case .file: return L("Arquivos")
        }
    }

    var symbol: String {
        switch self {
        case .text: return "text.alignleft"
        case .link: return "link"
        case .image: return "photo"
        case .color: return "paintpalette"
        case .code: return "chevron.left.forwardslash.chevron.right"
        case .file: return "doc"
        }
    }
}

struct ClipItem: Identifiable, Codable, Equatable {
    var id = UUID()
    var kind: ClipKind
    /// Text content (text/link/color/code) or file paths separated by "\n" (file).
    var text: String?
    var imageFile: String?
    var imageWidth: Int?
    var imageHeight: Int?
    var sourceAppName: String?
    var sourceBundleID: String?
    var firstCopied: Date
    /// Last time it was copied / used. History is ordered by this.
    var date: Date
    var useCount: Int = 1
    var pinned: Bool = false
    var contentHash: String

    var fileURLs: [URL] {
        (text ?? "").split(separator: "\n").map { URL(fileURLWithPath: String($0)) }
    }

    var title: String {
        switch kind {
        case .image:
            return L("Imagem")
        case .file:
            let urls = fileURLs
            if urls.count == 1 { return urls[0].lastPathComponent }
            return L("%d arquivos", urls.count)
        default:
            let t = (text ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            let lines = t.components(separatedBy: .newlines).map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
            let joined = lines.prefix(3).joined(separator: " ")
            return String(joined.prefix(300))
        }
    }

    var detail: String? {
        switch kind {
        case .image:
            if let w = imageWidth, let h = imageHeight { return "\(w) × \(h)" }
            return nil
        case .link:
            let t = (text ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            let url = URL(string: t.contains("://") ? t : "https://" + t)
            return url?.host
        case .file:
            return fileURLs.first?.deletingLastPathComponent().path.replacingOccurrences(of: NSHomeDirectory(), with: "~")
        case .color:
            return nil
        default:
            return L("%d caracteres", (text ?? "").count)
        }
    }

    func matches(_ query: String) -> Bool {
        if query.isEmpty { return true }
        let q = query.lowercased()
        if (text ?? "").lowercased().contains(q) { return true }
        if (sourceAppName ?? "").lowercased().contains(q) { return true }
        if kind == .image && ("imagem".contains(q) || "image".contains(q) || "imagen".contains(q)) { return true }
        return false
    }
}

enum Classifier {
    private static let editorBundles = [
        "com.microsoft.VSCode", "com.apple.dt.Xcode", "com.sublimetext", "dev.zed.Zed",
        "com.todesktop.230313mzl4w4u92", "com.jetbrains", "com.googlecode.iterm2",
        "com.apple.Terminal", "com.github.wez.wezterm", "dev.warp.Warp", "com.mitchellh.ghostty",
        "com.exafunction.windsurf", "com.panic.Nova",
    ]

    static func kind(for s: String, bundleID: String?) -> ClipKind {
        let t = s.trimmingCharacters(in: .whitespacesAndNewlines)
        if ColorParser.parse(t) != nil { return .color }
        if isLink(t) { return .link }
        if looksLikeCode(s, bundleID: bundleID) { return .code }
        return .text
    }

    static func isLink(_ t: String) -> Bool {
        guard !t.isEmpty, t.rangeOfCharacter(from: .whitespacesAndNewlines) == nil else { return false }
        let lower = t.lowercased()
        for p in ["http://", "https://", "ftp://", "mailto:", "file://"] where lower.hasPrefix(p) { return true }
        let pattern = #"^(www\.)?([a-z0-9-]+\.)+[a-z]{2,}(:\d+)?(/\S*)?$"#
        return lower.range(of: pattern, options: .regularExpression) != nil
    }

    static func looksLikeCode(_ s: String, bundleID: String?) -> Bool {
        var score = 0
        if let b = bundleID, editorBundles.contains(where: { b.hasPrefix($0) }) { score += 1 }
        let markers = ["{", "}", ";\n", "=>", "->", "()", "</", "/>", "==", "!=", "&&", "||", "::",
                       "import ", "func ", "def ", "const ", "let ", "var ", "return ", "class ",
                       "function ", "#include", "SELECT ", " FROM ", "npm ", "git ", "sudo ", "$(", "};"]
        score += min(markers.filter { s.contains($0) }.count, 3)
        let lines = s.components(separatedBy: .newlines)
        if lines.count > 1 && lines.contains(where: { $0.hasPrefix("    ") || $0.hasPrefix("\t") }) { score += 1 }
        return score >= 3
    }
}

enum ColorParser {
    static func parse(_ raw: String) -> NSColor? {
        let s = raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if s.hasPrefix("#") {
            let hex = String(s.dropFirst())
            guard [3, 6, 8].contains(hex.count), let v = UInt64(hex, radix: 16) else { return nil }
            var r, g, b, a: CGFloat
            switch hex.count {
            case 3:
                r = CGFloat((v >> 8) & 0xF) / 15; g = CGFloat((v >> 4) & 0xF) / 15; b = CGFloat(v & 0xF) / 15; a = 1
            case 6:
                r = CGFloat((v >> 16) & 0xFF) / 255; g = CGFloat((v >> 8) & 0xFF) / 255; b = CGFloat(v & 0xFF) / 255; a = 1
            default:
                r = CGFloat((v >> 24) & 0xFF) / 255; g = CGFloat((v >> 16) & 0xFF) / 255; b = CGFloat((v >> 8) & 0xFF) / 255; a = CGFloat(v & 0xFF) / 255
            }
            return NSColor(srgbRed: r, green: g, blue: b, alpha: a)
        }
        let pattern = #"^rgba?\(\s*(\d{1,3})\s*,\s*(\d{1,3})\s*,\s*(\d{1,3})\s*(,\s*([0-9.]+)\s*)?\)$"#
        guard let re = try? NSRegularExpression(pattern: pattern),
              let m = re.firstMatch(in: s, range: NSRange(s.startIndex..., in: s)) else { return nil }
        func group(_ i: Int) -> Double? {
            guard let r = Range(m.range(at: i), in: s) else { return nil }
            return Double(s[r])
        }
        guard let r = group(1), let g = group(2), let b = group(3), r <= 255, g <= 255, b <= 255 else { return nil }
        let a = group(5) ?? 1
        return NSColor(srgbRed: r / 255, green: g / 255, blue: b / 255, alpha: a)
    }
}

enum TimeText {
    nonisolated(unsafe) private static var cached: (AppLanguage, RelativeDateTimeFormatter)?

    /// Rebuilt when the interface language changes.
    private static var formatter: RelativeDateTimeFormatter {
        let lang = AppLanguage.current
        if let c = cached, c.0 == lang { return c.1 }
        let f = RelativeDateTimeFormatter()
        f.locale = Locale(identifier: lang.localeTag)
        f.unitsStyle = .abbreviated
        cached = (lang, f)
        return f
    }

    static func relative(_ date: Date, now: Date = Date()) -> String {
        if now.timeIntervalSince(date) < 60 { return L("agora") }
        return formatter.localizedString(for: date, relativeTo: now)
    }
}
