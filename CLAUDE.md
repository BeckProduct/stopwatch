# stopwatch — Flutter / iOS

A single-purpose stopwatch for iOS, presented as a mechanical chronograph. One screen, done to a
high finish.

**The code is the current design.** The UI spec artifact `stopwatch-spec.html`, in the umbrella's
`.orchestrator/stopwatch/` and cited by path in the early tickets, is **historical**: it still draws
the cased face with a lap register, which PAT-214 replaced with an uncased dial, the controls below
it and a tenths register. Read it for intent, never for what the screen looks like. `design-notes.md`
sits alongside it and is likewise a record, not a spec.

---

## The correctness rule

**Elapsed time comes from a monotonic clock. Never from frame counts, never from `DateTime.now()`
deltas alone.**

- `Stopwatch` / `Ticker` elapsed duration is the source of truth for the running total.
- A wall-clock anchor (`DateTime`) exists *only* to reconcile time passed while suspended, and is
  written at suspend and read at resume.
- Every rendered angle and every digit derives from that one elapsed value in the same frame.

Two clocks means the hand and the numerals disagree, and the disagreement grows with the run.
Violating this is an auto-FAIL, not a code-review preference.

---

## Flutter conventions

- Respect the reactive, declarative model. Explicit state ownership; keep it as local as the
  problem allows.
- This is a one-screen app. **Do not** import a layered architecture it does not need — no
  repository layer, no service layer, no feature-directory tree for a single feature.
- Widgets stay dumb; timing and transition logic lives behind them in something testable without
  a widget tree.
- Custom painting is the bulk of this app. Keep painters pure functions of their inputs, give them
  real `shouldRepaint`, and keep per-frame allocation out of `paint`.
- `dart format`. Idiomatic Dart. `const` wherever it holds. Avoid needless nullability.
- **State management is plain Flutter, no package**: `ChronoScreen` is the only `StatefulWidget`
  and holds the screen's state with `setState`, over plain injected classes — `RunSession`
  composing `TimingEngine`, the clocks and the `RunStore`, plus `RattrapanteController`, a
  `ChangeNotifier` for the split hand. Introducing a package needs a ticket and a reason this
  cannot carry the case.

---

## iOS specifics

- **iOS only.** No Android, no web, no desktop. Do not add platform folders.
- The Live Activity / Dynamic Island is a **Swift widget extension**, `ios/ChronoLiveActivity/`.
  It talks to Dart through `ios/Runner/LiveActivityBridge.swift`, which compiles into the Runner
  target alongside the usual `AppDelegate`/`SceneDelegate` and the bridging header.
- Any change to `ios/Runner.xcodeproj`, signing, entitlements or `Info.plist` is broad-impact:
  say what it affects before making it.
- Simulator target: **iPhone 17 Pro**.

---

## Testing

- Timing and lap logic → unit tests, driven by an injectable clock. A test that needs `sleep` is
  the wrong test.
- Widget behaviour (pusher enablement, state transitions, lap stack) → widget tests.
- Painters are exempt from pixel assertions; test the geometry functions they call instead.

---

## Quality gates (run and report before going idle)

- `flutter analyze` — clean, not "clean except".
- `flutter test`

Those two are the gates. `flutter run -d "iPhone 17 Pro"` is **optional** — reach for it when you
need the simulator to diagnose something, not to prove the branch builds.

**The UI verdict is Justin's.** He drives the app by hand and is the only source of one; a
screenshot is not verification of animation, feel or gesture behaviour. Report what you ran and
report those as *unverified*. An agent spending a build to report that the app launched has told
nobody anything.

---

## Herdr orchestration (gated)

> **Only if `HERDR_ENV=1` AND you hold an implementation brief naming a ticket.** The orchestrator
> satisfies `HERDR_ENV` too and is forbidden from implementing. No brief → not for you.
>
> Branching, pushing and opening the PR are `git-conventions`' — load it and follow it.
>
> Work that needs the simulator: ensure your runtime side pane exists (create it if missing,
> labeled `flutter-run`) and keep `flutter run -d "iPhone 17 Pro"` running there, watching for
> compile errors and runtime exceptions and fixing them locally. The orchestrator boots the
> Simulator before you launch. A change that cannot reach the screen needs no pane.
>
> Load `herdr-runtime` before waiting on any long-running command. **If `HERDR_ENV` is unset,
> ignore this entire section** — create no pane and start no process.
