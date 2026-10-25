import SwiftUI

enum TaoTheme {
    static let paper = Color(red: 0.965, green: 0.959, blue: 0.941)
    static let ink = Color(red: 0.065, green: 0.068, blue: 0.070)
    static let muted = Color(red: 0.43, green: 0.43, blue: 0.41)
    static let line = Color.black.opacity(0.12)
    static let calendar: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(secondsFromGMT: 28_800)!
        return c
    }()
    static let timeZone = TimeZone(secondsFromGMT: 28_800)!

    static func format(_ date: Date, pattern: String = "yyyy.MM.dd  HH:mm") -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.calendar = calendar
        f.timeZone = timeZone
        f.dateFormat = pattern
        return f.string(from: date)
    }

    static func parse(_ string: String) -> Date? {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.calendar = calendar
        f.timeZone = timeZone
        f.dateFormat = "yyyy-MM-dd'T'HH:mm:ss"
        return f.date(from: string)
    }
}

struct TaijiMark: View {
    var size: CGFloat = 30
    var body: some View {
        Canvas { context, bounds in
            let diameter = min(bounds.width, bounds.height)
            let r = diameter / 2
            let center = CGPoint(x: r, y: r)
            context.fill(Path(ellipseIn: CGRect(x: 0, y: 0, width: diameter, height: diameter)), with: .color(TaoTheme.ink))
            var light = Path()
            light.addArc(center: center, radius: r, startAngle: .degrees(-90), endAngle: .degrees(90), clockwise: false)
            light.addArc(center: CGPoint(x: r, y: r * 1.5), radius: r / 2, startAngle: .degrees(90), endAngle: .degrees(-90), clockwise: false)
            light.addArc(center: CGPoint(x: r, y: r / 2), radius: r / 2, startAngle: .degrees(90), endAngle: .degrees(-90), clockwise: true)
            light.closeSubpath()
            context.fill(light, with: .color(TaoTheme.paper))
            let eye = diameter * 0.085
            context.fill(Path(ellipseIn: CGRect(x: r - eye / 2, y: r / 2 - eye / 2, width: eye, height: eye)), with: .color(TaoTheme.paper))
            context.fill(Path(ellipseIn: CGRect(x: r - eye / 2, y: r * 1.5 - eye / 2, width: eye, height: eye)), with: .color(TaoTheme.ink))
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }
}
