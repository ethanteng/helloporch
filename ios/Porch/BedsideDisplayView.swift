import UIKit
import PorchCore

/// Decorative artwork stays behind the real clock. No flashing, parallax, or
/// perpetual animation: the sky follows local time at the clock's minute tick.
final class BedsideSceneView: UIView {
    var scene = BedsideScene(date: Date(), preferences: .init()) { didSet { setNeedsDisplay() } }
    override init(frame: CGRect) { super.init(frame: frame); isUserInteractionEnabled = false; isAccessibilityElement = false; isOpaque = true }
    required init?(coder: NSCoder) { fatalError("Use init(frame:)") }
    override func draw(_ rect: CGRect) {
        guard let ctx = UIGraphicsGetCurrentContext() else { return }
        let w = bounds.width, h = bounds.height
        func color(_ r: CGFloat, _ g: CGFloat, _ b: CGFloat) -> UIColor { UIColor(red: r, green: g, blue: b, alpha: 1) }
        func blend(_ a: UIColor, _ b: UIColor, _ amount: Double) -> UIColor {
            var ar: CGFloat = 0, ag: CGFloat = 0, ab: CGFloat = 0, aa: CGFloat = 0
            var br: CGFloat = 0, bg: CGFloat = 0, bb: CGFloat = 0, ba: CGFloat = 0
            a.getRed(&ar, green: &ag, blue: &ab, alpha: &aa); b.getRed(&br, green: &bg, blue: &bb, alpha: &ba)
            let t = CGFloat(max(0, min(1, amount)))
            return color(ar + (br - ar) * t, ag + (bg - ag) * t, ab + (bb - ab) * t)
        }
        let twilightTop = color(0.27, 0.18, 0.27), twilightBottom = color(0.39, 0.24, 0.20)
        let midnightTop = color(0.025, 0.045, 0.11), midnightBottom = color(0.07, 0.12, 0.19)
        let daylight = sin(.pi * scene.progress)
        let top = scene.isDay ? blend(twilightTop, color(0.08, 0.23, 0.34), daylight) : blend(twilightTop, midnightTop, min(1, daylight * 3))
        let bottom = scene.isDay ? blend(twilightBottom, color(0.18, 0.32, 0.35), daylight) : blend(twilightBottom, midnightBottom, min(1, daylight * 3))
        let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: [top.cgColor, bottom.cgColor] as CFArray, locations: [0, 1])!
        ctx.drawLinearGradient(gradient, start: .zero, end: CGPoint(x: 0, y: h), options: [])
        func ellipse(_ rect: CGRect, _ c: UIColor) { c.setFill(); UIBezierPath(ovalIn: rect).fill() }
        if !scene.isDay {
            for i in 0..<24 {
                let x = CGFloat((i * 157 + 37) % 997) / 997 * w
                let y = CGFloat((i * 73 + 11) % 211) / 1000 * h
                ellipse(CGRect(x: x, y: y, width: i % 3 == 0 ? 3 : 2, height: i % 3 == 0 ? 3 : 2), UIColor(white: 0.85, alpha: 0.45))
            }
        }
        let radius = min(w, h) * 0.047
        let point = CGPoint(x: w * (0.09 + 0.82 * scene.progress), y: h * (0.87 - 0.77 * sin(.pi * scene.progress)))
        if scene.isDay {
            ellipse(CGRect(x: point.x - radius * 1.4, y: point.y - radius * 1.4, width: radius * 2.8, height: radius * 2.8), UIColor(red: 1, green: 0.79, blue: 0.39, alpha: 0.08))
            ellipse(CGRect(x: point.x - radius, y: point.y - radius, width: radius * 2, height: radius * 2), color(1, 0.83, 0.48))
        } else {
            // A crescent cut out with the local sky color; a symbolic moon,
            // rather than a forecast of the astronomical lunar phase.
            ctx.saveGState()
            let outer = CGRect(x: point.x - radius, y: point.y - radius, width: radius * 2, height: radius * 2)
            UIBezierPath(ovalIn: outer).addClip()
            let moon = UIBezierPath(ovalIn: outer)
            moon.append(UIBezierPath(ovalIn: CGRect(x: point.x - radius * 0.25, y: point.y - radius * 1.2, width: radius * 1.7, height: radius * 1.7)))
            moon.usesEvenOddFillRule = true; moon.addClip()
            color(0.91, 0.89, 0.73).setFill(); UIRectFill(CGRect(x: point.x - radius, y: point.y - radius, width: radius * 2, height: radius * 2)); ctx.restoreGState()
        }
        // Quiet rolling hills frame the clock, with a seasonal tree at the edge.
        func hill(_ base: CGFloat, _ c: UIColor, _ offset: CGFloat) {
            let path = UIBezierPath(); path.move(to: CGPoint(x: 0, y: h * base))
            path.addCurve(to: CGPoint(x: w, y: h * (base + offset)), controlPoint1: CGPoint(x: w * 0.36, y: h * (base - 0.09)), controlPoint2: CGPoint(x: w * 0.65, y: h * (base + 0.05)))
            path.addLine(to: CGPoint(x: w, y: h)); path.addLine(to: CGPoint(x: 0, y: h)); path.close(); c.setFill(); path.fill()
        }
        let snow = scene.season == .winter
        hill(0.86, snow ? color(0.24, 0.31, 0.36) : color(0.10, 0.23, 0.22), -0.01)
        hill(0.94, snow ? color(0.33, 0.39, 0.41) : color(0.065, 0.17, 0.16), -0.025)
        ctx.saveGState(); ctx.translateBy(x: w * 0.87, y: h * 0.92)
        let unit = min(w, h) * 0.18
        let branches = UIBezierPath(); branches.move(to: .zero); branches.addLine(to: CGPoint(x: -unit * 0.04, y: -unit))
        for (x,y) in [(-0.35,-0.85),(0.3,-0.72),(-0.27,-0.54),(0.26,-1.03)] {
            branches.move(to: CGPoint(x: -unit * 0.02, y: unit * y * 0.7)); branches.addLine(to: CGPoint(x: unit * x, y: unit * y))
        }
        color(0.33, 0.28, 0.23).setStroke(); branches.lineWidth = max(3, unit * 0.04); branches.lineCapStyle = .round; branches.stroke()
        if !snow {
            let foliage: UIColor = scene.season == .fall ? color(0.65, 0.34, 0.18) : scene.season == .spring ? color(0.46, 0.55, 0.37) : color(0.23, 0.41, 0.28)
            for (x,y,r) in [(-0.24,-0.83,0.26),(0.19,-0.85,0.27),(0.0,-1.07,0.28),(-0.15,-0.58,0.23),(0.23,-0.62,0.21)] {
                ellipse(CGRect(x: unit * (x-r), y: unit * (y-r), width: unit * r * 2, height: unit * r * 2), foliage)
            }
            if scene.season == .spring {
                for (x,y) in [(-0.24,-0.9),(0.19,-0.9),(-0.02,-1.15),(0.22,-0.64)] { ellipse(CGRect(x: unit*x, y: unit*y, width: unit*0.07, height: unit*0.07), color(0.85,0.66,0.63)) }
            }
        } else {
            color(0.75, 0.79, 0.79).setStroke(); branches.lineWidth = max(1, unit * 0.014); branches.stroke()
        }
        ctx.restoreGState()
        // Keeps cream clock lettering readable over every sky and season.
        let shade = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: [UIColor.clear.cgColor, UIColor.black.withAlphaComponent(0.76).cgColor, UIColor.black.withAlphaComponent(0.76).cgColor, UIColor.clear.cgColor] as CFArray, locations: [0, 0.28, 0.74, 1])!
        ctx.drawLinearGradient(shade, start: .zero, end: CGPoint(x: 0, y: h), options: [])
    }
}

final class BedsideDisplaySettingsViewController: CaregiverFormViewController {
    private var preferences = BedsidePreferences.load()
    private let appearance = UISegmentedControl(items: ["Default", "Dynamic"])
    private let hemisphere = UISegmentedControl(items: ["Northern", "Southern"])
    private let day = UIStepper(), night = UIStepper()
    private let dayLabel = PorchStyle.label("", size: 19, color: PorchStyle.ink)
    private let nightLabel = PorchStyle.label("", size: 19, color: PorchStyle.ink)
    private let example = BedsideSceneView()
    override func viewDidLoad() {
        super.viewDidLoad(); title = "Bedside display"
        navigationItem.rightBarButtonItem = UIBarButtonItem(title: "Save", style: .done, target: self, action: #selector(save))
        appearance.selectedSegmentIndex = preferences.appearance == .dynamic ? 1 : 0
        appearance.accessibilityLabel = "Bedside view"
        hemisphere.selectedSegmentIndex = preferences.hemisphere == .northern ? 0 : 1
        hemisphere.accessibilityLabel = "Season hemisphere"
        for control in [appearance, hemisphere] {
            control.selectedSegmentTintColor = PorchStyle.accent; control.backgroundColor = PorchStyle.page
            control.setTitleTextAttributes([.foregroundColor: PorchStyle.ink], for: .normal)
            control.setTitleTextAttributes([.foregroundColor: UIColor.white], for: .selected)
            control.heightAnchor.constraint(greaterThanOrEqualToConstant: 48).isActive = true
            control.addTarget(self, action: #selector(update), for: .valueChanged)
        }
        form.addArrangedSubview(section("Clock view", detail: "Both views always show the current date and time in large, clear text. Default keeps the screen dark. Dynamic adds a quiet sky, a sun or moon, and a seasonal landscape.", views: [appearance]))
        example.heightAnchor.constraint(equalToConstant: 210).isActive = true
        example.layer.cornerRadius = 20; example.clipsToBounds = true
        let previewClock = PorchStyle.label(DateFormatter.localizedString(from: Date(), dateStyle: .medium, timeStyle: .short), size: 24, color: PorchStyle.nightText, weight: .semibold)
        previewClock.textAlignment = .center; previewClock.translatesAutoresizingMaskIntoConstraints = false
        example.addSubview(previewClock)
        NSLayoutConstraint.activate([previewClock.centerYAnchor.constraint(equalTo: example.centerYAnchor), previewClock.leadingAnchor.constraint(equalTo: example.leadingAnchor, constant: 20), previewClock.trailingAnchor.constraint(equalTo: example.trailingAnchor, constant: -20)])
        form.addArrangedSubview(example)
        day.minimumValue = 0; day.maximumValue = 11; day.value = Double(preferences.dayStart)
        night.minimumValue = 12; night.maximumValue = 23; night.value = Double(preferences.nightStart)
        day.accessibilityLabel = "Day begins"; night.accessibilityLabel = "Night begins"
        func row(_ label: UILabel, _ stepper: UIStepper) -> UIView {
            stepper.addTarget(self, action: #selector(update), for: .valueChanged)
            let row = UIStackView(arrangedSubviews: [label, UIView(), stepper]); row.alignment = .center; row.spacing = 16; return row
        }
        form.addArrangedSubview(section("Day & night schedule", detail: "The sun and moon follow these times and the iPad's local clock. They represent your daily routine, rather than local sunrise, sunset, or moon phase. The scene updates gently each minute and respects Reduce Motion.", views: [row(dayLabel, day), row(nightLabel, night)]))
        form.addArrangedSubview(section("Seasons", detail: "Choose your hemisphere. Seasons follow the local calendar: March–May is spring in the north and fall in the south.", views: [hemisphere]))
        hideKeyboardControl(); update()
    }
    @objc private func update() {
        preferences.appearance = appearance.selectedSegmentIndex == 0 ? .default : .dynamic
        preferences.hemisphere = hemisphere.selectedSegmentIndex == 0 ? .northern : .southern
        preferences.dayStart = Int(day.value); preferences.nightStart = Int(night.value)
        func hour(_ value: Int) -> String {
            let date = Calendar.current.date(from: DateComponents(year: 2026, month: 1, day: 1, hour: value))!
            let formatter = DateFormatter(); formatter.setLocalizedDateFormatFromTemplate("j"); return formatter.string(from: date)
        }
        dayLabel.text = "Day begins · \(hour(preferences.dayStart))"; nightLabel.text = "Night begins · \(hour(preferences.nightStart))"
        day.accessibilityValue = hour(preferences.dayStart); night.accessibilityValue = hour(preferences.nightStart)
        example.isHidden = preferences.appearance != .dynamic
        example.scene = BedsideScene(date: Date(), preferences: preferences)
    }
    @objc private func save() {
        preferences.save()
        NotificationCenter.default.post(name: .porchBedsideDisplayChanged, object: nil)
        navigationController?.popViewController(animated: true)
    }
}
extension Notification.Name { static let porchBedsideDisplayChanged = Notification.Name("porchBedsideDisplayChanged") }
