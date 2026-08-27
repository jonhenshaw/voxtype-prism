# Voxtype Prism: Signal style design QA

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

- The standard-install activation card loaded in Quickshell at `336 × 112`
  logical pixels, bottom-centred with a 24 px margin, under the dedicated
  `voxtype-prism-activation` namespace. It accepts pointer input only across
  that small surface and requests no keyboard focus.
- Activation remains explicit: only the card's **Activate** button starts the
  audited setup helper. While the card is visible, Signal and its audio bridge
  remain dormant and VoxType's stock indicator stays active.
- `Service.qml` loads as an enabled Omarchy `service` under Quickshell 0.3.1 with no plugin QML/runtime errors.
- Before setup, the service reported `configured: false`, stayed hidden, and did not start its audio bridge while Voxtype's stock OSD remained enabled.
- After explicit setup, the service reported `configured: true` and Voxtype ran without an OSD child.
- Focused-monitor mapping placed the live plugin layer on DP-2.
- Final layer geometry is `168 × 48`; centering the 156 × 40 card inside it with a 20 px layer margin preserves the card's original 24 px bottom position.
- The live state probe reported `recording`, `surfaceWanted: true`, `presence: 1`, and an attached audio bridge; Hyprland attributed the layer to the Omarchy shell process.
- The recording-and-cancel test returned the daemon and state file to `idle` without transcribing or pasting text.
- The transcribing preview matches the selected yellow working treatment.
- The microphone and ready checkmark both reset to zero rotation after the working spinner stops.
- The final deployed micro-halo is tightly bounded to 6 px at 8% opacity; no long solid capsule remains.
- Disable/re-enable unloaded and recreated the service and audio bridge cleanly.
- The explicit restore helper returned Voxtype to its original OSD state; official plugin removal and atomic `omarchy plugin add` installation both completed successfully.
- The bounded-reader and config-helper regression suites pass, including scoped edits, exact enabled-state restoration, oversized-file rejection, non-regular-file rejection, and planted-symlink read/write cases.
- Final process tree contains one Voxtype daemon and the existing Omarchy shell only; there is no standalone Signal Quickshell process or Voxtype OSD child.
- Two shell crashes during locked-session lifecycle testing were traced to Omarchy's lock recovery fatal (`Tried to show lockscreen surfaces without active lock`) before Signal's service was loaded. No Signal QML frame or runtime error appeared in either crash timeline.

final result: passed
