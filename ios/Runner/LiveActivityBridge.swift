import Flutter
import Foundation

#if canImport(ActivityKit)
  import ActivityKit
#endif

/// The app side of `MethodChannel('beck.stopwatch/liveactivity')`.
///
/// Owns the one in-flight `Activity` and nothing else. Every method answers
/// with a `Bool`: `false` means the activity is not showing — Live Activities
/// turned off in Settings, the system limit hit, or the OS too old — and the
/// app is expected to carry on silently rather than surface it.
final class LiveActivityBridge {
  static let channelName = "beck.stopwatch/liveactivity"

  private var currentActivityID: String?

  static func register(with messenger: FlutterBinaryMessenger) {
    let bridge = LiveActivityBridge()
    let channel = FlutterMethodChannel(name: channelName, binaryMessenger: messenger)
    channel.setMethodCallHandler { call, result in
      bridge.handle(call, result: result)
    }
    // The handler closure is the only strong reference the channel keeps, so
    // hold the channel for the process lifetime.
    Self.retained.append(channel)
  }

  private static var retained: [FlutterMethodChannel] = []

  private func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    let arguments = call.arguments as? [String: Any] ?? [:]
    switch call.method {
    case "start":
      result(start(arguments))
    case "update":
      result(update(arguments))
    case "end":
      end()
      result(true)
    case "isSupported":
      result(isSupported)
    default:
      result(FlutterMethodNotImplemented)
    }
  }

  private var isSupported: Bool {
    #if canImport(ActivityKit)
      if #available(iOS 16.2, *) {
        return ActivityAuthorizationInfo().areActivitiesEnabled
      }
    #endif
    return false
  }

  // MARK: - ActivityKit

  #if canImport(ActivityKit)
    /// `startDate` arrives as epoch seconds: the instant the run would have
    /// begun to reach the elapsed value the engine holds. Dart recomputes it on
    /// every push, so a resumed run re-anchors rather than drifting.
    @available(iOS 16.2, *)
    private func contentState(from arguments: [String: Any]) -> ChronoAttributes.ContentState {
      let startEpoch = arguments["startDate"] as? Double ?? Date().timeIntervalSince1970
      return ChronoAttributes.ContentState(
        startDate: Date(timeIntervalSince1970: startEpoch),
        pausedElapsed: arguments["pausedElapsed"] as? Double,
        lapCount: arguments["lapCount"] as? Int ?? 0
      )
    }
  #endif

  private func start(_ arguments: [String: Any]) -> Bool {
    #if canImport(ActivityKit)
      if #available(iOS 16.2, *) {
        guard ActivityAuthorizationInfo().areActivitiesEnabled else { return false }
        // A second start with one already showing is a restart, not a stack.
        end()
        do {
          let activity = try Activity.request(
            attributes: ChronoAttributes(title: "Stopwatch"),
            content: ActivityContent(state: contentState(from: arguments), staleDate: nil)
          )
          currentActivityID = activity.id
          return true
        } catch {
          NSLog("LiveActivityBridge: start failed — \(error.localizedDescription)")
          return false
        }
      }
    #endif
    return false
  }

  private func update(_ arguments: [String: Any]) -> Bool {
    #if canImport(ActivityKit)
      if #available(iOS 16.2, *) {
        guard let id = currentActivityID,
          let activity = Activity<ChronoAttributes>.activities.first(where: { $0.id == id })
        else { return false }
        let content = ActivityContent(state: contentState(from: arguments), staleDate: nil)
        Task { await activity.update(content) }
        return true
      }
    #endif
    return false
  }

  private func end() {
    #if canImport(ActivityKit)
      if #available(iOS 16.2, *) {
        // Ends every activity this app owns, not just the tracked one: a
        // force-quit can leave one showing that this process never requested.
        for activity in Activity<ChronoAttributes>.activities {
          Task { await activity.end(nil, dismissalPolicy: .immediate) }
        }
      }
    #endif
    currentActivityID = nil
  }
}
