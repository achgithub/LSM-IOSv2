import SwiftUI
import Lottie
import UIKit

/// Isolated visual-direction prototype for the V2 in-app experience.
///
/// This file is intentionally not linked from app navigation and does not use
/// `V2Theme`. It is a disposable showroom for agreeing atmosphere, colour and
/// motion before any production design-system work begins.
struct V2ExperienceThemePOC: View {
    fileprivate enum Scene: String, CaseIterable, Identifiable {
        case games = "Games"
        case matchday = "Matchday"
        case loading = "Loading"
        case winner = "Winner"

        var id: Self { self }
    }

    @State private var scene = Scene.games
    @State private var appearance: ColorScheme

    init(initialAppearance: ColorScheme = .dark) {
        _appearance = State(initialValue: initialAppearance)
    }

    var body: some View {
        ZStack {
            POCStadiumBackground(accent: scene.accent)

            VStack(spacing: 0) {
                HStack(spacing: 10) {
                    Picker("POC scene", selection: $scene) {
                        ForEach(Scene.allCases) { scene in
                            Text(scene.rawValue).tag(scene)
                        }
                    }
                    .pickerStyle(.segmented)

                    Button {
                        withAnimation(.easeInOut(duration: 0.28)) {
                            appearance = appearance == .dark ? .light : .dark
                        }
                    } label: {
                        Image(systemName: appearance == .dark ? "sun.max.fill" : "moon.stars.fill")
                            .font(.body.weight(.bold))
                            .foregroundStyle(POCTheme.chrome)
                            .frame(width: 38, height: 32)
                            .background(POCTheme.panel, in: RoundedRectangle(cornerRadius: 9, style: .continuous))
                            .overlay(RoundedRectangle(cornerRadius: 9).stroke(POCTheme.line))
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(appearance == .dark ? "Show light mode" : "Show dark mode")
                }
                .padding(.horizontal, 16)
                .padding(.top, 10)
                .padding(.bottom, 14)

                Group {
                    switch scene {
                    case .games: POCGamesScreen()
                    case .matchday: POCMatchdayScreen()
                    case .loading: POCLoadingScreen()
                    case .winner: POCWinnerScreen()
                    }
                }
                .id(scene)
                .transition(.opacity.combined(with: .scale(scale: 0.985)))
            }
        }
        .preferredColorScheme(appearance)
        .animation(.easeInOut(duration: 0.24), value: scene)
    }
}

private extension V2ExperienceThemePOC.Scene {
    var accent: Color {
        switch self {
        case .games, .loading: POCTheme.chrome
        case .matchday: POCTheme.predictor
        case .winner: POCTheme.gold
        }
    }
}

private enum POCTheme {
    static let ink = adaptive(light: 0xEEF4FA, dark: 0x07101F)
    static let navy = adaptive(light: 0xE3EDF7, dark: 0x0B1628)
    static let panel = adaptive(light: 0xFFFFFF, dark: 0x111E32)
    static let panelRaised = adaptive(light: 0xE5EDF6, dark: 0x17263D)
    static let line = Color(UIColor { traits in
        traits.userInterfaceStyle == .dark
            ? UIColor.white.withAlphaComponent(0.09)
            : UIColor(red: 0.67, green: 0.73, blue: 0.81, alpha: 0.38)
    })
    static let text = adaptive(light: 0x132033, dark: 0xF8FAFC)
    static let muted = adaptive(light: 0x52667F, dark: 0x96A5BA)
    static let chrome = adaptive(light: 0x1975BA, dark: 0x3DA8FF)
    static let lms = adaptive(light: 0xC95608, dark: 0xF97316)
    static let predictor = adaptive(light: 0x087BAE, dark: 0x38BDF8)
    static let killer = adaptive(light: 0xCF2447, dark: 0xF43F5E)
    static let success = adaptive(light: 0x16875F, dark: 0x34D399)
    static let gold = adaptive(light: 0xA96D00, dark: 0xFBBF24)
    static let onAccent = Color(hex: 0x07101F)

    private static func adaptive(light: UInt32, dark: UInt32) -> Color {
        Color(UIColor { traits in
            UIColor(hex: traits.userInterfaceStyle == .dark ? dark : light)
        })
    }
}

private struct POCStadiumBackground: View {
    let accent: Color
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        GeometryReader { proxy in
          ZStack {
            // One fixed composition in both appearances. Keeping the source
            // geometry identical means the stadium does not jump when the
            // user changes appearance; only its grade and lighting animate.
            if let url = Bundle.main.url(forResource: "V2POCStadiumDay", withExtension: "png"),
               let stadium = UIImage(contentsOfFile: url.path) {
                Image(uiImage: stadium)
                    .resizable()
                    .scaledToFit()
                    .frame(width: proxy.size.width, height: proxy.size.height)
                    .clipped()
                    .saturation(colorScheme == .dark ? 0.62 : 0.94)
                    .contrast(colorScheme == .dark ? 1.10 : 0.98)
                    .brightness(colorScheme == .dark ? -0.26 : 0)
            }

            if colorScheme == .dark {
                Color(hex: 0x071426).opacity(0.54)
                    .blendMode(.multiply)
                POCNightLighting()
                    .transition(.opacity)
            } else {
                Color.white.opacity(0.035)
                .transition(.opacity)
            }

            LinearGradient(
                colors: colorScheme == .dark
                    ? [POCTheme.ink.opacity(0.04), POCTheme.ink.opacity(0.16), POCTheme.ink.opacity(0.34)]
                    : [Color.white.opacity(0.02), Color.white.opacity(0.08), Color(hex: 0xF7FAF5).opacity(0.12)],
                startPoint: .top,
                endPoint: .bottom
            )

            accent.opacity(colorScheme == .dark ? 0.08 : 0.035)
                .blendMode(.plusLighter)

            TimelineView(.animation(minimumInterval: reduceMotion ? 60 : 1 / 20)) { timeline in
                let phase = reduceMotion ? 0.0 : timeline.date.timeIntervalSinceReferenceDate
                Canvas { context, size in
                    for index in 0..<18 {
                        let lane = Double((index * 47) % 101) / 101
                        let travel = (phase * (7 + Double(index % 5)) + Double(index * 31))
                            .truncatingRemainder(dividingBy: size.height + 80)
                        let point = CGPoint(x: lane * size.width, y: travel - 40)
                        context.fill(
                            Path(ellipseIn: CGRect(x: point.x, y: point.y, width: 2, height: 2)),
                            with: .color(index.isMultiple(of: 4) ? accent.opacity(0.45) : .white.opacity(0.16))
                        )
                    }
                }
            }
          }
          .frame(width: proxy.size.width, height: proxy.size.height)
          .clipped()
          .overlay(alignment: .bottom) {
              LinearGradient(
                  colors: [.clear, colorScheme == .dark ? POCTheme.ink.opacity(0.48) : Color.white.opacity(0.22)],
                  startPoint: .top,
                  endPoint: .bottom
              )
                .frame(height: 260)
                .allowsHitTesting(false)
          }
        }
        .ignoresSafeArea()
    }
}

private struct POCNightLighting: View {
    var body: some View {
        GeometryReader { proxy in
          ZStack {
            RadialGradient(
                colors: [.white.opacity(0.96), POCTheme.chrome.opacity(0.34), .clear],
                center: .topLeading,
                startRadius: 2,
                endRadius: 230
            )
            RadialGradient(
                colors: [.white.opacity(0.96), POCTheme.chrome.opacity(0.34), .clear],
                center: .topTrailing,
                startRadius: 2,
                endRadius: 230
            )

            // Light the individual lamp housings in the source artwork. The
            // banks follow the roof trusses, so the glow now has a visible
            // origin instead of reading as ambient haze from off-screen.
            ForEach(0..<9, id: \.self) { index in
                let progress = CGFloat(index) / 8
                let y = proxy.size.height * (0.132 + progress * 0.142)
                let inset = proxy.size.width * (0.018 + progress * 0.078)

                POCLiveFloodlight(angle: -14)
                    .position(x: inset, y: y)
                POCLiveFloodlight(angle: 14)
                    .position(x: proxy.size.width - inset, y: y)
            }

            Canvas { context, size in
                var leftBeam = Path()
                leftBeam.move(to: CGPoint(x: 0, y: 120))
                leftBeam.addLine(to: CGPoint(x: size.width * 0.47, y: size.height * 0.72))
                leftBeam.addLine(to: CGPoint(x: size.width * 0.28, y: size.height * 0.72))
                leftBeam.closeSubpath()

                var rightBeam = Path()
                rightBeam.move(to: CGPoint(x: size.width, y: 120))
                rightBeam.addLine(to: CGPoint(x: size.width * 0.72, y: size.height * 0.72))
                rightBeam.addLine(to: CGPoint(x: size.width * 0.53, y: size.height * 0.72))
                rightBeam.closeSubpath()

                context.fill(leftBeam, with: .linearGradient(
                    Gradient(colors: [POCTheme.chrome.opacity(0.20), .clear]),
                    startPoint: CGPoint(x: 0, y: 120),
                    endPoint: CGPoint(x: size.width * 0.40, y: size.height * 0.65)
                ))
                context.fill(rightBeam, with: .linearGradient(
                    Gradient(colors: [POCTheme.chrome.opacity(0.20), .clear]),
                    startPoint: CGPoint(x: size.width, y: 120),
                    endPoint: CGPoint(x: size.width * 0.60, y: size.height * 0.65)
                ))
            }
          }
        }
        .blendMode(.screen)
        .allowsHitTesting(false)
    }
}

private struct POCLiveFloodlight: View {
    let angle: Double

    var body: some View {
        ZStack {
            Circle()
                .fill(POCTheme.chrome.opacity(0.42))
                .frame(width: 42, height: 42)
                .blur(radius: 11)

            Circle()
                .fill(Color.white.opacity(0.72))
                .frame(width: 22, height: 22)
                .blur(radius: 5)

            RoundedRectangle(cornerRadius: 2.5, style: .continuous)
                .fill(Color.white)
                .frame(width: 9, height: 14)
                .overlay {
                    RoundedRectangle(cornerRadius: 2.5, style: .continuous)
                        .stroke(POCTheme.chrome.opacity(0.9), lineWidth: 1)
                }
                .shadow(color: .white.opacity(0.95), radius: 5)
        }
        .rotationEffect(.degrees(angle))
    }
}

private struct POCGamesScreen: View {
    var body: some View {
        ScrollView {
            LazyVStack(spacing: 18) {
                POCPageHeader(eyebrow: "LAST STAND MANAGER", title: "Your games", detail: "Three ways to play. One matchday hub.")

                HStack(spacing: 10) {
                    POCMetric(value: "3", label: "ACTIVE", color: POCTheme.chrome)
                    POCMetric(value: "12", label: "DUE", color: POCTheme.gold)
                    POCMetric(value: "48", label: "PLAYERS", color: POCTheme.success)
                }

                POCGameCard(mode: "LAST MAN STANDING", name: "Saturday Survivors", detail: "Round 8 · 14 still standing", symbol: "shield.lefthalf.filled", color: POCTheme.lms, progress: 0.68)
                POCGameCard(mode: "PREDICTOR", name: "Office League", detail: "Matchday 24 · 6 predictions due", symbol: "chart.line.uptrend.xyaxis", color: POCTheme.predictor, progress: 0.42)
                POCGameCard(mode: "KILLER", name: "The Knockout", detail: "Kill phase · 9 players remain", symbol: "scope", color: POCTheme.killer, progress: 0.81)
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 32)
        }
    }
}

private struct POCMatchdayScreen: View {
    var body: some View {
        ScrollView {
            LazyVStack(spacing: 18) {
                POCPageHeader(eyebrow: "PREDICTOR · MATCHDAY 24", title: "Make it count", detail: "Six fixtures close Saturday at 14:45")

                POCPanel {
                    HStack(spacing: 12) {
                        Image(systemName: "timer")
                            .font(.title2.weight(.bold))
                            .foregroundStyle(POCTheme.gold)
                        VStack(alignment: .leading, spacing: 3) {
                            Text("PREDICTIONS CLOSE IN").pocMicroLabel(color: POCTheme.muted)
                            Text("1d  04h  18m").font(.system(.title3, design: .monospaced).weight(.heavy))
                        }
                        Spacer()
                        Text("4/6").font(.headline.monospacedDigit()).foregroundStyle(POCTheme.predictor)
                    }
                }

                POCFixture(home: "Arsenal", away: "Chelsea", score: "2  –  1", selected: true)
                POCFixture(home: "Everton", away: "Fulham", score: "–  –  –", selected: false)
                POCFixture(home: "Liverpool", away: "Newcastle", score: "3  –  1", selected: true)

                Button(action: {}) {
                    Label("Confirm predictions", systemImage: "checkmark.circle.fill")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 15)
                        .foregroundStyle(POCTheme.onAccent)
                        .background(POCTheme.predictor, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 32)
        }
    }
}

private struct POCLoadingScreen: View {
    var body: some View {
        VStack(spacing: 22) {
            Spacer()
            ZStack {
                Circle().fill(POCTheme.chrome.opacity(0.10)).frame(width: 150, height: 150)
                Circle().stroke(POCTheme.chrome.opacity(0.22), lineWidth: 1).frame(width: 126, height: 126)
                LottieView(animation: .named("DribblingSoccer"))
                    .playing(loopMode: .loop)
                    .resizable()
                    .frame(width: 104, height: 104)
            }
            VStack(spacing: 7) {
                Text("Getting matchday ready").font(.title3.bold()).foregroundStyle(POCTheme.text)
                Text("Refreshing fixtures, scores and submissions")
                    .font(.subheadline).foregroundStyle(POCTheme.muted)
            }
            HStack(spacing: 6) {
                ForEach(0..<3) { index in
                    Circle().fill(index == 0 ? POCTheme.chrome : POCTheme.chrome.opacity(0.25)).frame(width: 7, height: 7)
                }
            }
            Spacer()
            Text("Football motion is reserved for football work")
                .pocMicroLabel(color: POCTheme.muted)
                .padding(.bottom, 30)
        }
        .padding(.horizontal, 24)
    }
}

private struct POCWinnerScreen: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var celebrate = false

    var body: some View {
        ZStack {
            VStack(spacing: 22) {
                Spacer()
                ZStack {
                    Circle().fill(POCTheme.gold.opacity(0.12)).frame(width: 188, height: 188)
                    Circle().stroke(POCTheme.gold.opacity(0.3), lineWidth: 1).frame(width: 154, height: 154)
                    LottieView(animation: .named("CupCelebration"))
                        .playing(loopMode: .playOnce)
                        .resizable()
                        .frame(width: 150, height: 150)
                }
                .scaleEffect(celebrate ? 1 : 0.72)
                .opacity(celebrate ? 1 : 0)

                VStack(spacing: 8) {
                    Text("CHAMPION").pocMicroLabel(color: POCTheme.gold)
                    Text("Jamie Carter").font(.system(.largeTitle, design: .rounded).weight(.black))
                    Text("Saturday Survivors").font(.headline).foregroundStyle(POCTheme.muted)
                }

                POCPanel {
                    HStack {
                        POCWinnerStat(value: "8", label: "ROUNDS")
                        Divider().overlay(POCTheme.line)
                        POCWinnerStat(value: "7", label: "WINS")
                        Divider().overlay(POCTheme.line)
                        POCWinnerStat(value: "24", label: "PLAYERS")
                    }
                    .frame(height: 48)
                }
                .padding(.horizontal, 16)
                Spacer()
                Text("Celebrate once, then settle into the result")
                    .pocMicroLabel(color: POCTheme.muted)
                    .padding(.bottom, 30)
            }

            if celebrate && !reduceMotion { POCConfetti() }
        }
        .onAppear {
            withAnimation(.spring(response: 0.62, dampingFraction: 0.72)) { celebrate = true }
        }
    }
}

private struct POCPageHeader: View {
    let eyebrow: String
    let title: String
    let detail: String

    var body: some View {
        VStack(alignment: .center, spacing: 7) {
            Text(eyebrow).pocMicroLabel(color: POCTheme.chrome)
            Text(title)
                .font(.custom("MontserratThin-Black", size: 34))
                .foregroundStyle(POCTheme.text)
                .multilineTextAlignment(.center)
            Text(detail)
                .font(.subheadline)
                .foregroundStyle(POCTheme.muted)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, alignment: .center)
        .padding(.top, 8)
    }
}

private struct POCPanel<Content: View>: View {
    @ViewBuilder let content: () -> Content

    var body: some View {
        content()
            .padding(17)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(POCTheme.panel.opacity(0.84), in: RoundedRectangle(cornerRadius: 20, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous).stroke(POCTheme.line))
            .shadow(color: .black.opacity(0.2), radius: 18, y: 10)
    }
}

private struct POCMetric: View {
    let value: String
    let label: String
    let color: Color

    var body: some View {
        VStack(spacing: 3) {
            Text(value).font(.title2.bold()).foregroundStyle(color)
            Text(label).pocMicroLabel(color: POCTheme.muted)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 13)
        .background(POCTheme.panel.opacity(0.88), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 16).stroke(POCTheme.line))
    }
}

private struct POCGameCard: View {
    let mode: String
    let name: String
    let detail: String
    let symbol: String
    let color: Color
    let progress: Double

    var body: some View {
        POCPanel {
            HStack(spacing: 14) {
                Image(systemName: symbol)
                    .font(.title2.weight(.bold))
                    .foregroundStyle(color)
                    .frame(width: 48, height: 48)
                    .background(color.opacity(0.13), in: RoundedRectangle(cornerRadius: 15, style: .continuous))
                VStack(alignment: .leading, spacing: 5) {
                    Text(mode).pocMicroLabel(color: color)
                    Text(name).font(.headline).foregroundStyle(POCTheme.text)
                    Text(detail).font(.caption).foregroundStyle(POCTheme.muted)
                }
                Spacer()
                Image(systemName: "chevron.right").foregroundStyle(POCTheme.muted)
            }
            ProgressView(value: progress)
                .tint(color)
                .padding(.top, 13)
        }
    }
}

private struct POCFixture: View {
    let home: String
    let away: String
    let score: String
    let selected: Bool

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 5) {
                Text(home).font(.subheadline.weight(.semibold))
                Text(away).font(.subheadline.weight(.semibold))
            }
            Spacer()
            Text(score)
                .font(.system(.headline, design: .monospaced).weight(.heavy))
                .foregroundStyle(selected ? POCTheme.text : POCTheme.muted)
                .padding(.horizontal, 13).padding(.vertical, 10)
                .background(selected ? POCTheme.predictor.opacity(0.14) : POCTheme.panelRaised, in: RoundedRectangle(cornerRadius: 12))
        }
        .padding(15)
        .background(POCTheme.panel.opacity(0.92), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 18).stroke(selected ? POCTheme.predictor.opacity(0.55) : POCTheme.line))
    }
}

private struct POCWinnerStat: View {
    let value: String
    let label: String

    var body: some View {
        VStack(spacing: 2) {
            Text(value).font(.headline.monospacedDigit()).foregroundStyle(POCTheme.text)
            Text(label).pocMicroLabel(color: POCTheme.muted)
        }
        .frame(maxWidth: .infinity)
    }
}

private struct POCConfetti: View {
    private let colors = [POCTheme.gold, POCTheme.chrome, POCTheme.lms, POCTheme.success, POCTheme.killer]

    var body: some View {
        TimelineView(.animation) { timeline in
            let time = timeline.date.timeIntervalSinceReferenceDate
            Canvas { context, size in
                for index in 0..<42 {
                    let seed = Double((index * 71) % 103) / 103
                    let fall = (time * (52 + Double(index % 6) * 9) + Double(index * 43))
                        .truncatingRemainder(dividingBy: size.height + 60)
                    let sway = sin(time * 1.8 + Double(index)) * 18
                    let x = seed * size.width + sway
                    let rect = CGRect(x: x, y: fall - 30, width: index.isMultiple(of: 3) ? 4 : 7, height: 10)
                    context.fill(Path(roundedRect: rect, cornerRadius: 2), with: .color(colors[index % colors.count].opacity(0.88)))
                }
            }
        }
        .allowsHitTesting(false)
        .ignoresSafeArea()
        .mask(LinearGradient(colors: [.white, .white, .clear], startPoint: .top, endPoint: .bottom))
    }
}

private extension Text {
    func pocMicroLabel(color: Color) -> some View {
        font(.system(size: 10, weight: .black, design: .rounded))
            .tracking(1.25)
            .foregroundStyle(color)
    }
}

private extension Color {
    init(hex: UInt32) {
        self.init(
            .sRGB,
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255,
            opacity: 1
        )
    }
}

private extension UIColor {
    convenience init(hex: UInt32) {
        self.init(
            red: CGFloat((hex >> 16) & 0xFF) / 255,
            green: CGFloat((hex >> 8) & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255,
            alpha: 1
        )
    }
}

#Preview("V2 experience theme POC") {
    V2ExperienceThemePOC()
}
