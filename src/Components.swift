import SwiftUI

// MARK: - 配色（参照国内安全软件的彩色图标语言）

enum Palette {
    static let blue = Color(red: 0.18, green: 0.49, blue: 0.96)
    static let cyan = Color(red: 0.07, green: 0.72, blue: 0.78)
    static let purple = Color(red: 0.48, green: 0.36, blue: 0.94)
    static let violet = Color(red: 0.69, green: 0.42, blue: 0.96)
    static let green = Color(red: 0.07, green: 0.65, blue: 0.48)
    static let mint = Color(red: 0.25, green: 0.80, blue: 0.60)
    static let orange = Color(red: 0.94, green: 0.55, blue: 0.12)
    static let amber = Color(red: 0.96, green: 0.71, blue: 0.25)
    static let red = Color(red: 0.90, green: 0.28, blue: 0.28)

    /// 每个模块一套渐变（图标底色）
    static func gradient(for item: NavItem) -> LinearGradient {
        switch item {
        case .home: return LinearGradient(colors: [blue, cyan], startPoint: .topLeading, endPoint: .bottomTrailing)
        case .speed: return LinearGradient(colors: [blue, Color(red: 0.29, green: 0.66, blue: 1.0)], startPoint: .topLeading, endPoint: .bottomTrailing)
        case .nodes: return LinearGradient(colors: [purple, violet], startPoint: .topLeading, endPoint: .bottomTrailing)
        case .lan: return LinearGradient(colors: [green, mint], startPoint: .topLeading, endPoint: .bottomTrailing)
        case .wifi: return LinearGradient(colors: [Color(red: 0.06, green: 0.54, blue: 0.88), Color(red: 0.19, green: 0.77, blue: 0.95)], startPoint: .topLeading, endPoint: .bottomTrailing)
        case .info: return LinearGradient(colors: [orange, amber], startPoint: .topLeading, endPoint: .bottomTrailing)
        }
    }

    static func color(for item: NavItem) -> Color {
        switch item {
        case .home: return blue
        case .speed: return blue
        case .nodes: return purple
        case .lan: return green
        case .wifi: return Color(red: 0.06, green: 0.54, blue: 0.88)
        case .info: return orange
        }
    }
}

// MARK: - 通用组件

/// 彩色圆角图标（安全软件工具箱那种）
struct TileIcon: View {
    var systemName: String
    var gradient: LinearGradient
    var size: CGFloat = 38

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: size * 0.28, style: .continuous)
                .fill(gradient)
                .frame(width: size, height: size)
                .shadow(color: .black.opacity(0.12), radius: 2, x: 0, y: 1)
            Image(systemName: systemName)
                .font(.system(size: size * 0.46, weight: .semibold))
                .foregroundStyle(.white)
        }
    }
}

/// 工具箱磁贴
struct ToolTile: View {
    var item: NavItem
    var subtitle: String
    @State private var hovering = false

    var body: some View {
        VStack(spacing: 8) {
            TileIcon(systemName: item.icon, gradient: Palette.gradient(for: item), size: 46)
            VStack(spacing: 2) {
                Text(item.title).font(.system(size: 12, weight: .medium)).lineLimit(1)
                Text(subtitle).font(.system(size: 10)).foregroundStyle(.secondary).lineLimit(1)
            }
        }
        .frame(width: 104, height: 92)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(hovering ? Color.primary.opacity(0.06) : Color(nsColor: .controlBackgroundColor))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(Color.primary.opacity(hovering ? 0.16 : 0.07))
        )
        .contentShape(Rectangle())
        .onHover { hovering = $0 }
        .animation(.easeOut(duration: 0.12), value: hovering)
    }
}

/// 体检评分环
struct ScoreRing: View {
    var score: Int
    var grade: String
    var color: Color
    var size: CGFloat = 148

    var body: some View {
        ZStack {
            Circle()
                .stroke(Color.primary.opacity(0.08), style: StrokeStyle(lineWidth: 13, lineCap: .round))
            Circle()
                .trim(from: 0, to: max(0.001, min(1, Double(score) / 100)))
                .stroke(
                    AngularGradient(colors: [color.opacity(0.65), color], center: .center),
                    style: StrokeStyle(lineWidth: 13, lineCap: .round)
                )
                .rotationEffect(.degrees(-90))
                .animation(.easeOut(duration: 0.6), value: score)
            VStack(spacing: 0) {
                Text(score > 0 ? "\(score)" : "—")
                    .font(.system(size: size * 0.30, weight: .bold, design: .rounded))
                    .monospacedDigit()
                Text(grade)
                    .font(.system(size: size * 0.10, weight: .medium))
                    .foregroundStyle(score > 0 ? color : .secondary)
            }
        }
        .frame(width: size, height: size)
    }
}

/// 首页状态卡
struct StatusCard: View {
    var title: String
    var value: String
    var unit: String = ""
    var caption: String
    var icon: String
    var color: Color
    var state: String = ""      // 正常 / 注意 / 未测

    private var stateColor: Color {
        switch state {
        case "正常": return .green
        case "注意": return .orange
        default: return .secondary
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                ZStack {
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(color.opacity(0.15))
                        .frame(width: 22, height: 22)
                    Image(systemName: icon).font(.system(size: 11, weight: .semibold)).foregroundStyle(color)
                }
                Text(title).font(.system(size: 12, weight: .medium)).foregroundStyle(.secondary)
                Spacer()
                if !state.isEmpty {
                    Text(state).font(.system(size: 10))
                        .padding(.horizontal, 6).padding(.vertical, 1)
                        .background(Capsule().fill(stateColor.opacity(0.15)))
                        .foregroundStyle(stateColor)
                }
            }
            HStack(alignment: .firstTextBaseline, spacing: 3) {
                Text(value).font(.system(size: 22, weight: .semibold, design: .rounded)).monospacedDigit()
                Text(unit).font(.system(size: 11)).foregroundStyle(.secondary)
            }
            Text(caption).font(.system(size: 10)).foregroundStyle(.tertiary).lineLimit(2)
        }
        .padding(11)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 11, style: .continuous).fill(Color(nsColor: .controlBackgroundColor)))
        .overlay(RoundedRectangle(cornerRadius: 11, style: .continuous).stroke(Color.primary.opacity(0.07)))
    }
}

struct MetricCard: View {
    var title: String
    var value: String
    var unit: String
    var icon: String
    var color: Color
    var subtitle: String = ""

    /// 值越长字号越小，避免 IP 这类长文本被挤到换行
    private var valueSize: CGFloat {
        switch value.count {
        case 0 ... 8: return 28
        case 9 ... 11: return 21
        default: return 17
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 5) {
                Image(systemName: icon).font(.caption).foregroundStyle(color)
                Text(title).font(.caption).foregroundStyle(.secondary)
                Spacer()
            }
            HStack(alignment: .firstTextBaseline, spacing: 3) {
                Text(value)
                    .font(.system(size: valueSize, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                Text(unit).font(.caption).foregroundStyle(.secondary)
            }
            if !subtitle.isEmpty {
                Text(subtitle).font(.caption2).foregroundStyle(.tertiary).lineLimit(2)
            }
            Spacer(minLength: 0)
        }
        .padding(12)
        .frame(maxWidth: .infinity, minHeight: 92, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 10).fill(Color(nsColor: .controlBackgroundColor)))
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.primary.opacity(0.07)))
    }
}

struct KV: View {
    var k: String
    var v: String
    var mono: Bool = false
    var width: CGFloat = 116

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Text(k)
                .font(.callout)
                .foregroundStyle(.secondary)
                .frame(width: width, alignment: .trailing)
            Text(v.isEmpty ? "—" : v)
                .font(mono ? .system(.callout, design: .monospaced) : .callout)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

struct CardBox<Content: View>: View {
    var title: String
    var icon: String = ""
    var accent: Color = .accentColor
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 6) {
                if !icon.isEmpty {
                    Image(systemName: icon).foregroundStyle(accent).font(.system(size: 12, weight: .semibold))
                }
                Text(title).font(.system(size: 13, weight: .semibold))
            }
            content
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Color(nsColor: .controlBackgroundColor)))
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(Color.primary.opacity(0.07)))
    }
}

struct SignalBars: View {
    var rssi: Int
    private var bars: Int {
        switch rssi {
        case let r where r >= -50: return 4
        case -60 ..< -50: return 3
        case -70 ..< -60: return 2
        case -80 ..< -70: return 1
        default: return 0
        }
    }
    private var color: Color {
        switch bars {
        case 4, 3: return .green
        case 2: return .yellow
        case 1: return .orange
        default: return .red
        }
    }

    var body: some View {
        HStack(alignment: .bottom, spacing: 2) {
            ForEach(0 ..< 4, id: \.self) { i in
                RoundedRectangle(cornerRadius: 1.5)
                    .fill(i < bars ? color : Color.secondary.opacity(0.25))
                    .frame(width: 4, height: CGFloat(6 + i * 5))
            }
        }
    }
}

struct Pill: View {
    var text: String
    var color: Color = .accentColor
    var body: some View {
        Text(text)
            .font(.caption2)
            .padding(.horizontal, 7)
            .padding(.vertical, 2)
            .background(Capsule().fill(color.opacity(0.15)))
            .foregroundStyle(color)
    }
}

func fmtMbps(_ v: Double) -> String {
    if v <= 0 { return "—" }
    if v >= 100 { return String(format: "%.0f", v) }
    return String(format: "%.2f", v)
}

func fmtMs(_ v: Double) -> String {
    if v <= 0 { return "—" }
    return String(format: "%.1f", v)
}
