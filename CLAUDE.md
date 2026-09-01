# chessfen

## Agent skills

### Issue tracker

GitHub Issues on `sunfmin/chessfen`, via the `gh` CLI. See `docs/agents/issue-tracker.md`.

### Triage labels

The five canonical roles, each label string equal to its name. See `docs/agents/triage-labels.md`.

### Domain docs

Single-context: `CONTEXT.md` and `docs/adr/` at the repo root. See `docs/agents/domain.md`.

## Deploy to the phone after every change

改完就装到手机上，不用等我开口 — a change nobody can hold in their hand is not finished.
Same trigger as the auto-commit rule: one meaningful step done, tests green, then deploy.

```bash
./ios/App/deploy.sh          # build Release, install on the connected iPhone, launch it
```

- **Only when the app changed** — anything under `ios/App/` or `ios/Sources/`. Docs, ADRs,
  `CONTEXT.md`, README: no deploy.
- **Run it in the background.** It is a Release build of Stockfish at `-O3`; a cold one is
  minutes, a warm one under one. Never sit in the foreground waiting for it.
- **Tests first, deploy after** — `swift test -c release`, and the screen tests when a screen
  changed. A build that fails on the phone after a green test run is a signing or a device
  problem, and worth saying so plainly.
- **No phone, no problem.** The script exits with `no connected iPhone found` when nothing is
  plugged in and unlocked. Say that one line and carry on; it is not a failed task.
- The script takes an optional udid (`./ios/App/deploy.sh <udid>`) and otherwise takes the first
  available iPhone from `xcrun devicectl list devices`. Bundle id is `com.sunfmin.chessfen`, and
  it launches with `--terminate-existing`, so what is on screen is always the build just made.
