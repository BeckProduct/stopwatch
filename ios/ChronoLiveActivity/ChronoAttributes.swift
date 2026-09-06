import Foundation

#if canImport(ActivityKit)
  import ActivityKit

  /// The contract between the app and the Live Activity, compiled into both
  /// targets.
  ///
  /// `startDate` is a wall-clock *anchor*, not a second source of truth. It is
  /// recomputed from the engine's monotonic elapsed value on every push
  /// (`startDate = now - elapsed`), because `Text(timerInterval:)` is the only
  /// way to make iOS tick the digits without a push per second — and it takes a
  /// `Date` range. The engine remains the sole authority for elapsed time; this
  /// surface is a projection of it that the app does not render.
  @available(iOS 16.2, *)
  struct ChronoAttributes: ActivityAttributes {
    public struct ContentState: Codable, Hashable {
      /// Instant the run would have begun to reach the current elapsed value.
      var startDate: Date

      /// Set only while stopped, holding the frozen total. `nil` means running,
      /// and is what selects the self-ticking text over static text.
      var pausedElapsed: TimeInterval?

      /// Splits taken so far. The only other number the app has.
      var lapCount: Int

      var isRunning: Bool { pausedElapsed == nil }
    }

    /// ActivityKit requires at least one static attribute.
    var title: String
  }
#endif
