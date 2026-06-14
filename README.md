# Pulse

A beautiful, featherweight system monitor that lives in your Mac's menu bar.

See CPU, memory, and disk at a glance — and the apps eating them — then quit a
runaway app in one click. Built so you catch the next *"Your system has run out
of application memory"* **before** it happens.

![Pulse panel](docs/panel.png)

## Why

Activity Monitor is heavy and buried. Pulse is the opposite: a single live line
in your menu bar (CPU) plus the one number that actually predicts trouble (memory
%). Click it for three ring gauges and the top memory-hungry apps, each with its
real icon. Spot the culprit, hit ⏏, done.

## Design principles

- **Light by default.** No subprocesses, no background daemons. Pulse reads CPU,
  RAM, and disk straight from the kernel (Mach `host_statistics`, `libproc`
  `proc_pid_rusage`). Idle memory footprint is ~14 MB; the menu bar samples every
  2 s and the process list only samples while the panel is open.
- **Quiet until it matters.** The menu bar stays monochrome and calm; the memory
  number warms to orange, then red, only as pressure climbs.
- **Native, not generic.** AppKit + SwiftUI, real app icons, SF typography,
  system materials. It looks like it shipped with macOS.

## Install

Requires macOS 14+ and a Swift toolchain (Xcode or Command Line Tools).

```bash
git clone https://github.com/sonpiaz/pulse.git
cd pulse
./scripts/build-app.sh release
open dist/Pulse.app
```

To launch at login: System Settings → General → Login Items → add `Pulse.app`.

## Usage

- **Menu bar**: live CPU sparkline + memory %. Click to open the panel.
- **Panel**: CPU / Memory / Disk ring gauges, then the top apps by memory.
- **Quit an app**: click the ⏏ button on its row (sends `SIGTERM`).
- **Force quit**: ⌥-click the ⏏ button (sends `SIGKILL`).

## How the numbers are derived

| Metric | Source |
|---|---|
| CPU % | `host_processor_info` tick deltas, normalized across all cores |
| Memory used | App (internal − purgeable) + wired + compressed pages — matches Activity Monitor's "Memory Used" |
| Disk | `volumeAvailableCapacityForImportantUsage` on the data volume |
| Per-app memory | `proc_pid_rusage` physical footprint, with Electron-style helpers grouped under their parent `.app` |
| Per-app CPU | `proc_pid_rusage` user+system time deltas |

## Verify the math yourself

```bash
.build/release/Pulse --selftest      # prints one live sample to compare with `top` / `vm_stat`
```

## License

MIT © 2026 Son Nguyen
