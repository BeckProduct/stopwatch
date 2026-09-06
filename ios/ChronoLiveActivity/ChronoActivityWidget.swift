import SwiftUI
import WidgetKit

#if canImport(ActivityKit)
  import ActivityKit

  private enum Chrono {
    /// accent1 from the dial palette. The only colour this surface borrows.
    static let accent = Color(red: 0xC8 / 255, green: 0x10 / 255, blue: 0x2E / 255)
    static let ink = Color(red: 0x11 / 255, green: 0x12 / 255, blue: 0x14 / 255)
  }

  /// Elapsed digits, ticked by iOS rather than by a push per second.
  ///
  /// While running this is `Text(timerInterval:)`, which the system advances on
  /// its own — pushing once a second would be rate-limited and would cost real
  /// battery. While stopped there is nothing to tick, so the frozen total is
  /// drawn as static text.
  @available(iOS 16.2, *)
  private struct ElapsedText: View {
    let state: ChronoAttributes.ContentState
    let size: CGFloat

    var body: some View {
      Group {
        if let paused = state.pausedElapsed {
          Text(Self.formatted(paused))
        } else {
          Text(timerInterval: state.startDate...Date.distantFuture, countsDown: false)
        }
      }
      .font(.system(size: size, weight: .medium, design: .monospaced))
      .monospacedDigit()
    }

    /// Matches what `Text(timerInterval:)` shows, so stopping does not reformat
    /// the numerals under the user.
    static func formatted(_ interval: TimeInterval) -> String {
      let total = Int(interval)
      let hours = total / 3600
      let minutes = (total % 3600) / 60
      let seconds = total % 60
      return hours > 0
        ? String(format: "%d:%02d:%02d", hours, minutes, seconds)
        : String(format: "%02d:%02d", minutes, seconds)
    }
  }

  /// The motion cue: a hairline that fills across one minute.
  ///
  /// Driven by `timerInterval` so iOS animates it without a push. It fills the
  /// minute in progress and then holds — it cannot restart itself, because a
  /// Live Activity only re-renders when state is pushed to it.
  @available(iOS 16.2, *)
  private struct MinuteCue: View {
    let state: ChronoAttributes.ContentState

    var body: some View {
      Group {
        if state.isRunning {
          let secondsIn = max(0, Date().timeIntervalSince(state.startDate))
          let minuteStart = state.startDate.addingTimeInterval((secondsIn / 60).rounded(.down) * 60)
          ProgressView(
            timerInterval: minuteStart...minuteStart.addingTimeInterval(60),
            countsDown: false,
            label: { EmptyView() },
            currentValueLabel: { EmptyView() }
          )
          .progressViewStyle(.linear)
        } else {
          Capsule().fill(Color.white.opacity(0.12))
        }
      }
      .tint(Chrono.accent)
      .frame(height: 3)
    }
  }

  @available(iOS 16.2, *)
  private struct LockScreenView: View {
    let state: ChronoAttributes.ContentState

    var body: some View {
      VStack(alignment: .leading, spacing: 12) {
        HStack(alignment: .firstTextBaseline) {
          VStack(alignment: .leading, spacing: 2) {
            Text("STOPWATCH")
              .font(.system(size: 10, weight: .bold))
              .tracking(1.8)
              .foregroundStyle(.white.opacity(0.45))
            ElapsedText(state: state, size: 30)
              .foregroundStyle(.white)
          }
          Spacer()
          VStack(alignment: .trailing, spacing: 2) {
            Text("LAP")
              .font(.system(size: 10, weight: .bold))
              .tracking(1.8)
              .foregroundStyle(.white.opacity(0.45))
            Text("\(state.lapCount)")
              .font(.system(size: 30, weight: .medium, design: .monospaced))
              .foregroundStyle(.white)
          }
        }
        MinuteCue(state: state)
      }
      .padding(16)
      .activityBackgroundTint(Chrono.ink)
      .activitySystemActionForegroundColor(.white)
    }
  }

  @available(iOS 16.2, *)
  struct ChronoActivityWidget: Widget {
    var body: some WidgetConfiguration {
      ActivityConfiguration(for: ChronoAttributes.self) { context in
        LockScreenView(state: context.state)
      } dynamicIsland: { context in
        DynamicIsland {
          DynamicIslandExpandedRegion(.leading) {
            ElapsedText(state: context.state, size: 22)
              .foregroundStyle(.white)
              .padding(.leading, 4)
          }
          DynamicIslandExpandedRegion(.trailing) {
            Text("LAP \(context.state.lapCount)")
              .font(.system(size: 12, weight: .bold))
              .tracking(1.6)
              .foregroundStyle(.white.opacity(0.55))
              .padding(.trailing, 4)
          }
          DynamicIslandExpandedRegion(.bottom) {
            MinuteCue(state: context.state)
          }
        } compactLeading: {
          Circle()
            .fill(Chrono.accent)
            .frame(width: 8, height: 8)
            .opacity(context.state.isRunning ? 1 : 0.4)
        } compactTrailing: {
          // ~50 pt of room. Numerals only; the dial does not fit here and is
          // not attempted.
          ElapsedText(state: context.state, size: 13)
            .foregroundStyle(.white)
            .frame(maxWidth: 52)
        } minimal: {
          Circle()
            .fill(Chrono.accent)
            .frame(width: 8, height: 8)
            .opacity(context.state.isRunning ? 1 : 0.4)
        }
        .keylineTint(Chrono.accent)
      }
    }
  }

  @main
  struct ChronoLiveActivityBundle: WidgetBundle {
    var body: some Widget {
      if #available(iOS 16.2, *) {
        ChronoActivityWidget()
      }
    }
  }
#endif
