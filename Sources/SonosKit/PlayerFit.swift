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

    /// Vertical space used by everything except the artwork.
    public var chrome: LayoutLength {
        topInset + bottomInset + output + afterOutput + afterArt + title
            + afterProgress + progress + beforeTransport + transport + beforeVolume + volume + modes
    }
}

/// Sizes the now-playing column so the controls stay on screen.
public enum PlayerFit {
    public static func metrics(width: LayoutLength, height: LayoutLength, showsModes: Bool) -> PlayerMetrics {
        let width = max(width, 0)
        let height = max(height, 0)
        let transport: LayoutLength = height < 620 ? 52 : 64
        var metrics = PlayerMetrics(
            column: min(400, max(180, width - 56)),
            artwork: 0,
            transport: transport,
            topInset: 58,
            bottomInset: 16,
            output: 34,
            afterOutput: 12,
            title: 64,
            afterArt: 16,
            progress: 44,
            afterProgress: 10,
            beforeTransport: 12,
            beforeVolume: 14,
            volume: 28,
            modes: showsModes ? 42 : 0
        )
        metrics.artwork = min(metrics.column, max(64, height - metrics.chrome))
        return metrics
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
