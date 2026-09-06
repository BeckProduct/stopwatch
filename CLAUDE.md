# stopwatch — Flutter / iOS

A single-purpose stopwatch for iOS, presented as a mechanical chronograph. One screen, done to a
high finish. Design decisions live in the umbrella's `.orchestrator/stopwatch/design-notes.md` and
in the UI spec artifact attached to each ticket — **not** in this file.

Integration branch **`develop`**. Push, pull and fetch via the **`claude`** remote, never `origin`.

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
- Generated code (`*.g.dart`, `*.freezed.dart`) is built by `build_runner` and never hand-edited.

State management is **not yet decided**; propose it on the ticket that first needs it rather than
introducing one silently.

---

## iOS specifics

- **iOS only.** No Android, no web, no desktop. Do not add platform folders.
- The Live Activity / Dynamic Island is a **Swift widget extension** under `ios/`. It is the only
  non-Dart code in the project.
- Any change to `ios/Runner.xcodeproj`, signing, entitlements or `Info.plist` is broad-impact:
  say what it affects before making it.
- Simulator target: **iPhone 17 Pro**.

---

## Testing

- Timing and lap logic → unit tests, driven by an injectable clock. A test that needs `sleep` is
  the wrong test.
- Widget behaviour (pusher enablement, state transitions, lap stack) → widget tests.
- **Verify by falsification.** A test that still passes when you revert the change it covers is
  not a test. Say so if you could not falsify one.
- Painters are exempt from pixel assertions; test the geometry functions they call instead.

---

## Quality gates (run and report before going idle)

- `flutter analyze` — clean, not "clean except".
- `flutter test`
- `flutter run -d "iPhone 17 Pro"` builds and launches without exceptions.

**A screenshot is not verification of UI behaviour.** Justin drives the app by hand and is the only
source of a UI verdict. Report what you ran, and report animation and feel as *unverified*.

---

## Herdr orchestration (gated)

> **Only if `HERDR_ENV=1` AND you were launched with an implementation brief naming a ticket.**
> The `HERDR_ENV` check alone is not sufficient — the orchestrator satisfies it too, and the
> orchestrator guardrails forbid the orchestrator from implementing. No brief → this section is
> not for you.
>
> Ensure your runtime side pane exists (create it if missing, labeled `flutter-run`) and keep
> `flutter run -d "iPhone 17 Pro"` running there; watch it for compile errors and runtime
> exceptions and fix them locally. The orchestrator boots the Simulator before you launch. Cut
> your `feature/*` branch fresh from the latest `develop` (fetch first), push it to the `claude`
> remote with an explicit refspec, and open a PR with
> `gh pr create --repo BeckProduct/stopwatch --base develop --reviewer reviewbeck`. The
> orchestrator hands you a ticket ID — **you own it**: move it Todo → In Progress, add a brief
> update plus the PR link, and do **not** create a second ticket (the reviewer moves it to Done on
> merge). Run the Quality Gates above before going idle. Load `herdr-runtime` before waiting on
> any long-running command. **If `HERDR_ENV` is unset, ignore this entire section** — create no
> pane and start no process.
