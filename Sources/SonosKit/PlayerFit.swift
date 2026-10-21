import Foundation
#if canImport(CoreGraphics)
import CoreGraphics
public typealias LayoutLength = CGFloat
#else
public typealias LayoutLength = Double
#endif

public struct PlayerMetrics: Equatable, Sendable {
    public var column: LayoutLength
    public var artwork: LayoutLength
    public var transport: LayoutLength
    public var topInset: LayoutLength
    public var bottomInset: LayoutLength
    public var output: LayoutLength
    public var afterOutput: LayoutLength
    public var title: LayoutLength
    public var afterArt: LayoutLength
    public var progress: LayoutLength
    public var afterProgress: LayoutLength
    public var beforeTransport: LayoutLength
    public var beforeVolume: LayoutLength
    public var volume: LayoutLength
    public var modes: LayoutLength
    public var titleSize: LayoutLength
    public var artistSize: LayoutLength
    public var sourceSize: LayoutLength

    /// Vertical space used by everything except the artwork.
    public var chrome: LayoutLength {
        topInset + bottomInset + output + afterOutput + afterArt + title
            + afterProgress + progress + beforeTransport + transport + beforeVolume + volume + modes
    }
}

/// Sizes the now-playing column so the controls stay on screen and match the artwork.
public enum PlayerFit {
    public static func metrics(
        width: LayoutLength,
        height: LayoutLength,
        showsModes: Bool,
        topInset: LayoutLength = 58
    ) -> PlayerMetrics {
        let width = max(width, 0)
        let height = max(height, 0)
        let maxSide = min(LayoutLength(420), max(0, width - 72))
        let minSide = LayoutLength(132)
        var side = maxSide
        var fitted = layout(side: side, showsModes: showsModes, topInset: topInset)
        if side + fitted.chrome > height {
            side = clamp(height - fitted.chrome, min: minSide, max: maxSide)
            fitted = layout(side: side, showsModes: showsModes, topInset: topInset)
            let leftover = height - (side + fitted.chrome)
            if leftover > 1 {
                side = clamp(side + leftover, min: minSide, max: maxSide)
                fitted = layout(side: side, showsModes: showsModes, topInset: topInset)
            }
            if side + fitted.chrome > height {
                side = clamp(height - fitted.chrome, min: minSide, max: maxSide)
                fitted = layout(side: side, showsModes: showsModes, topInset: topInset)
            }
        }
        side = clamp(side, min: min(minSide, maxSide), max: maxSide)
        fitted = layout(side: side, showsModes: showsModes, topInset: topInset)
        fitted.artwork = side
        fitted.column = side
        return fitted
    }

    private static func layout(side: LayoutLength, showsModes: Bool, topInset: LayoutLength) -> PlayerMetrics {
        let t = clamp((side - 132) / (420 - 132), min: 0, max: 1)
        return PlayerMetrics(
            column: side,
            artwork: side,
            transport: lerp(46, 72, t),
            topInset: topInset,
            bottomInset: lerp(10, 18, t),
            output: lerp(30, 36, t),
            afterOutput: lerp(12, 16, t),
            title: lerp(50, 72, t),
            afterArt: lerp(10, 20, t),
            progress: lerp(36, 48, t),
            afterProgress: lerp(8, 12, t),
            beforeTransport: lerp(8, 14, t),
            beforeVolume: lerp(10, 16, t),
            volume: lerp(24, 30, t),
            modes: showsModes ? lerp(34, 44, t) : 0,
            titleSize: lerp(16, 22, t),
            artistSize: lerp(12, 16, t),
            sourceSize: lerp(11, 13, t)
        )
    }

    private static func lerp(_ a: LayoutLength, _ b: LayoutLength, _ t: LayoutLength) -> LayoutLength {
        a + (b - a) * t
    }

    private static func clamp(_ value: LayoutLength, min lower: LayoutLength, max upper: LayoutLength) -> LayoutLength {
        let upper = Swift.max(lower, upper)
        return Swift.min(upper, Swift.max(lower, value))
    }
}

/// Coalesces a burst of slider moves so only the latest sample is sent.
public struct DebounceLedger: Equatable, Sendable {
    public static let delayNanoseconds: UInt64 = 160_000_000
    public private(set) var generations: [String: Int]

    public init(generations: [String: Int] = [:]) {
        self.generations = generations
    }

    /// Returns the generation for this sample. Older generations of `key` are stale.
    public mutating func push(key: String) -> Int {
        let next = (generations[key] ?? 0) + 1
        generations[key] = next
        return next
    }

    public func isLatest(key: String, generation: Int) -> Bool {
        generations[key] == generation
    }
}
