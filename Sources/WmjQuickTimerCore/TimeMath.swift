import Foundation

public enum TimeMath {
    /// Round elapsed seconds *up* to the next quarter hour, minimum 0.25
    /// (16 minutes bills 0.5; a 3-minute timer submits 0.25, never 0).
    public static func quarterHours(fromSeconds seconds: TimeInterval) -> Double {
        max(0.25, (seconds / 900).rounded(.up) * 0.25)
    }

    /// Quick Log hours: 0.25–8.0 in exact quarter-hour steps.
    public static func isValidQuickLogHours(_ hours: Double) -> Bool {
        hours >= 0.25 && hours <= 8 && (hours * 4).truncatingRemainder(dividingBy: 1) == 0
    }
}
