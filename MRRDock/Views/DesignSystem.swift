import SwiftUI
import AppKit

/// Design tokens. One sober green for growth, one muted red for decline, warm
/// neutrals for everything else — the popover is read at a glance from a menu
/// bar, so colour carries meaning and nothing else.
enum DS {
    static let ground = dynamic(light: NSColor(red: 0.988, green: 0.984, blue: 0.976, alpha: 1),
                                dark: NSColor(white: 0.10, alpha: 1))
    static let card = dynamic(light: .white, dark: NSColor(white: 0.145, alpha: 1))
    static let cardAlt = dynamic(light: NSColor(red: 0.965, green: 0.957, blue: 0.941, alpha: 1),
                                 dark: NSColor(white: 0.19, alpha: 1))
    static let hairline = dynamic(light: NSColor(white: 0.1, alpha: 0.08),
                                  dark: NSColor(white: 1, alpha: 0.10))

    static let ink = dynamic(light: NSColor(red: 0.098, green: 0.094, blue: 0.086, alpha: 1),
                             dark: NSColor(white: 0.95, alpha: 1))
    static let inkSecondary = dynamic(light: NSColor(white: 0.42, alpha: 1),
                                      dark: NSColor(white: 0.66, alpha: 1))
    static let inkTertiary = dynamic(light: NSColor(white: 0.60, alpha: 1),
                                     dark: NSColor(white: 0.50, alpha: 1))

    static let brand = Color(red: 0.114, green: 0.478, blue: 0.365)
    static let up = Color(red: 0.129, green: 0.522, blue: 0.400)
    static let down = Color(red: 0.761, green: 0.290, blue: 0.267)
    static let warn = Color(red: 0.784, green: 0.573, blue: 0.204)

    static func trend(_ value: Double) -> Color { value >= 0 ? up : down }

    static let display = Font.system(size: 38, weight: .bold, design: .rounded).monospacedDigit()
    static let figureLG = Font.system(size: 19, weight: .semibold, design: .rounded).monospacedDigit()
    static let figure = Font.system(size: 13, weight: .medium).monospacedDigit()
    static let title = Font.system(size: 14, weight: .semibold)
    static let body = Font.system(size: 12.5)
    static let caption = Font.system(size: 11)
    static let label = Font.system(size: 10, weight: .semibold)

    private static func dynamic(light: NSColor, dark: NSColor) -> Color {
        Color(nsColor: .init(name: nil) { $0.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua ? dark : light })
    }
}

struct CardBackground: ViewModifier {
    var padding: CGFloat = 14
    func body(content: Content) -> some View {
        content
            .padding(padding)
            .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(DS.card))
            .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(DS.hairline, lineWidth: 1))
    }
}

extension View {
    func card(padding: CGFloat = 14) -> some View { modifier(CardBackground(padding: padding)) }

    /// Uppercase section label used above every block in the popover.
    func sectionLabel() -> some View {
        font(DS.label).tracking(0.8).foregroundStyle(DS.inkTertiary).textCase(.uppercase)
    }
}

/// A pill carrying a signed percentage — the only place the trend colours appear
/// as a fill.
struct TrendPill: View {
    let value: Double
    var body: some View {
        Text(Format.percent(value))
            .font(DS.caption.weight(.semibold)).monospacedDigit()
            .padding(.horizontal, 7).padding(.vertical, 2.5)
            .background(Capsule().fill(DS.trend(value).opacity(0.12)))
            .foregroundStyle(DS.trend(value))
    }
}

/// The MRR trend line. Deliberately axis-less: with two weeks of daily points
/// the shape is the message, and gridlines would only add ink to a 60pt strip.
struct Sparkline: View {
    let points: [Double]
    var color: Color = DS.brand

    var body: some View {
        GeometryReader { geo in
            let path = linePath(in: geo.size)
            ZStack {
                path.fill(LinearGradient(colors: [color.opacity(0.18), color.opacity(0.01)],
                                         startPoint: .top, endPoint: .bottom))
                    .mask(areaMask(in: geo.size))
                path.stroke(color, style: StrokeStyle(lineWidth: 1.8, lineCap: .round, lineJoin: .round))
            }
        }
    }

    private func coordinates(in size: CGSize) -> [CGPoint] {
        guard points.count > 1 else { return [] }
        let minimum = points.min() ?? 0
        let maximum = points.max() ?? 1
        // A flat line would divide by zero; drawing it through the middle is
        // more honest than snapping it to the top or the bottom of the box.
        let span = maximum - minimum
        return points.enumerated().map { index, value in
            let x = size.width * CGFloat(index) / CGFloat(points.count - 1)
            let ratio = span > 0 ? (value - minimum) / span : 0.5
            return CGPoint(x: x, y: size.height * (1 - CGFloat(ratio)) * 0.9 + size.height * 0.05)
        }
    }

    private func linePath(in size: CGSize) -> Path {
        var path = Path()
        let coords = coordinates(in: size)
        guard let first = coords.first else { return path }
        path.move(to: first)
        for point in coords.dropFirst() { path.addLine(to: point) }
        return path
    }

    private func areaMask(in size: CGSize) -> Path {
        var path = linePath(in: size)
        let coords = coordinates(in: size)
        guard let first = coords.first, let last = coords.last else { return path }
        path.addLine(to: CGPoint(x: last.x, y: size.height))
        path.addLine(to: CGPoint(x: first.x, y: size.height))
        path.closeSubpath()
        return path
    }
}
