# Signal OSD design QA

Date: 2026-08-25

## Visual target

- Selected direction: Option 2, Signal.
- Source: the selected Signal concept preserved in `images/reference-signal.png`.
- Target card: 156 × 40 logical pixels, Tokyo Night panel, rounded state border, microphone icon, seven level bars, and uppercase state label.

## Compared evidence

- Reference capture: `images/reference-signal.png`.
- Installed recording capture: `images/installed-recording-signal.png`.
- Side-by-side comparison: `images/reference-vs-installed.png`.
- Installed transcribing capture: `images/installed-transcribing-signal.png`.
- Final micro-halo recording capture: `images/installed-micro-halo.png`.

The reference and installed recording states were compared at equivalent logical scale. The installed card preserves the selected 156 × 40 footprint, 14 px radius, dark translucent panel, red state treatment, microphone icon, seven-bar region, and right-aligned `LISTENING` label. The initial long outer glow was replaced after user review with a tightly bounded 6 px, 8%-opacity micro-halo.

## Findings

- P0: none.
- P1: none.
- P2: none.
- P3: the click-through carrier is 168 × 48 logical pixels to retain the micro-halo without clipping; the card remains exactly 156 × 40.

## Functional checks

- Production `shell.qml` loads under Quickshell 0.3.1 with no QML/runtime errors.
- Focused-monitor mapping placed the layer on DP-5 during the live cycle.
- Final layer geometry is `168 × 48`; centering the 156 × 40 card inside it with a 20 px layer margin preserves the card's original 24 px bottom position.
- The live state probe reported `recording`, `surfaceWanted: true`, `presence: 1`, and an attached audio bridge.
- The recording-and-cancel test returned the daemon and state file to `idle` without transcribing or pasting text.
- The transcribing preview matches the selected yellow working treatment.
- The microphone and ready checkmark both reset to zero rotation after the working spinner stops.
- The final deployed micro-halo is tightly bounded to 6 px at 8% opacity; no long solid capsule remains.
- Final process tree contains one Voxtype daemon, one custom Quickshell OSD, and one audio bridge; no GTK OSD or duplicate preview instance remains.

final result: passed
