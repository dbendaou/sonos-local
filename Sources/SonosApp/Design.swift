import AppKit
import SwiftUI
import SonosKit

enum Palette {
    static func background(_ scheme: ColorScheme) -> Color {
        scheme == .dark ? .black : .white
    }

    static func card(_ scheme: ColorScheme) -> Color {
        scheme == .dark ? Color.white.opacity(0.08) : Color.black.opacity(0.045)
    }

    static func cardActive(_ scheme: ColorScheme) -> Color {
        scheme == .dark ? Color.white.opacity(0.14) : Color.black.opacity(0.075)
    }

    static func hairline(_ scheme: ColorScheme) -> Color {
        scheme == .dark ? Color.white.opacity(0.08) : Color.black.opacity(0.06)
    }

    static func fill(_ scheme: ColorScheme) -> Color {
        scheme == .dark ? .white : .black
    }

    static func inverse(_ scheme: ColorScheme) -> Color {
        scheme == .dark ? .black : .white
    }
}

struct ThinSlider: View {
    @Binding var value: Double
    var range: ClosedRange<Double> = 0...100
    var onEditingChanged: (Bool) -> Void = { _ in }
    var accessibilityTitle: String = "Value"

    var body: some View {
        GeometryReader { geo in
            let width = max(geo.size.width, 1)
            let span = range.upperBound - range.lowerBound
            let fraction = span == 0 ? 0 : CGFloat((value - range.lowerBound) / span)
            let knobX = min(max(0, width * fraction - 7), width - 14)
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(Color.primary.opacity(0.12))
                    .frame(height: 3)
                Capsule()
                    .fill(Color.primary)
                    .frame(width: max(3, width * fraction), height: 3)
                Circle()
                    .fill(Color.primary)
                    .frame(width: 14, height: 14)
                    .shadow(color: .black.opacity(0.12), radius: 2, y: 1)
                    .offset(x: knobX)
            }
            .frame(maxHeight: .infinity)
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { gesture in
                        let x = min(max(0, gesture.location.x), width)
                        value = range.lowerBound + Double(x / width) * span
                        onEditingChanged(true)
                    }
                    .onEnded { _ in
                        onEditingChanged(false)
                    }
            )
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(accessibilityTitle)
            .accessibilityValue("\(Int(value.rounded()))")
            .accessibilityAdjustableAction { direction in
                let step = max(span / 40, 1)
                switch direction {
                case .increment: value = min(range.upperBound, value + step)
                case .decrement: value = max(range.lowerBound, value - step)
                @unknown default: break
                }
                onEditingChanged(false)
            }
        }
        .frame(height: 22)
    }
}

struct ArtworkView: View {
    var url: URL?
    var cornerRadius: CGFloat = 12
    @State private var image: NSImage?
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .fill(scheme == .dark ? Color.white.opacity(0.06) : Color.black.opacity(0.05))
            if let image {
                Image(nsImage: image)
                    .resizable()
                    .scaledToFill()
            } else {
                Image(systemName: "music.note")
                    .font(.system(size: 28, weight: .light))
                    .foregroundStyle(.tertiary)
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
        .task(id: url) { await load() }
    }

    private func load() async {
        image = nil
        guard let url, NetworkPolicy.isAllowedURL(url) else { return }
        if let cached = ArtworkMemory.shared.image(for: url) {
            image = cached
            return
        }
        var request = URLRequest(url: url)
        request.timeoutInterval = 8
        guard let (data, response) = try? await URLSession.shared.data(for: request),
              let http = response as? HTTPURLResponse, http.statusCode == 200,
              let loaded = NSImage(data: data) else { return }
        ArtworkMemory.shared.store(loaded, for: url)
        image = loaded
    }
}

final class ArtworkMemory: @unchecked Sendable {
    static let shared = ArtworkMemory()
    private let cache = NSCache<NSURL, NSImage>()
    func image(for url: URL) -> NSImage? { cache.object(forKey: url as NSURL) }
    func store(_ image: NSImage, for url: URL) { cache.setObject(image, forKey: url as NSURL) }
}

struct QuietButton: View {
    var systemName: String
    var label: String
    var active: Bool = false
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(active ? Color.primary : Color.primary.opacity(0.42))
                .frame(width: 34, height: 34)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(label)
        .accessibilityLabel(label)
    }
}

struct TransportControls: View {
    var isPlaying: Bool
    var diameter: CGFloat = 72
    var onPrevious: () -> Void
    var onToggle: () -> Void
    var onNext: () -> Void
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        HStack(spacing: diameter > 60 ? 28 : 18) {
            skip("backward.fill", "Previous", onPrevious)
            Button(action: onToggle) {
                Image(systemName: isPlaying ? "pause.fill" : "play.fill")
                    .font(.system(size: diameter * 0.32, weight: .bold))
                    .foregroundStyle(Palette.inverse(scheme))
                    .offset(x: isPlaying ? 0 : diameter * 0.03)
                    .frame(width: diameter, height: diameter)
                    .background(Circle().fill(Palette.fill(scheme)))
            }
            .buttonStyle(.plain)
            .accessibilityLabel(isPlaying ? "Pause" : "Play")
            skip("forward.fill", "Next", onNext)
        }
    }

    private func skip(_ symbol: String, _ label: String, _ action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: diameter * 0.28, weight: .medium))
                .foregroundStyle(.primary)
                .frame(width: 44, height: 44)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
    }
}

struct WindowOpener: View {
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        Color.clear
            .frame(width: 0, height: 0)
            .onReceive(NotificationCenter.default.publisher(for: .sonosOpenMainWindow)) { _ in
                openWindow(id: "main")
                NSApp.activate(ignoringOtherApps: true)
            }
    }
}
