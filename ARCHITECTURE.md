# Architecture

Voxtype Prism is an Omarchy `service` plugin. It runs inside the existing
`omarchy-shell` process and never launches a second Quickshell instance. This
release ships Signal as its first visual style.

```text
omarchy-shell
  └─ io.github.jonhenshaw.voxtype-prism / Service.qml
      ├─ VoxtypeConfig.qml   gates rendering until stock OSD is disabled
      ├─ StateReader.qml     watches idle/recording/transcribing state
      ├─ AudioBridge.qml     reads live peak/RMS frames
      ├─ OmarchyPalette.qml  follows the current theme
      └─ SignalSurface.qml   owns the click-through PanelWindow

voxtype.service
  ├─ writes $XDG_RUNTIME_DIR/voxtype/state
  └─ serves $XDG_RUNTIME_DIR/voxtype/audio.sock
```

## Why the built-in Voxtype OSD is disabled

Voxtype 0.7.5 starts its audio-level broadcaster regardless of whether the
built-in OSD child is enabled. Only spawning that child is gated by
`[osd] enabled`. Prism therefore sets the built-in OSD to disabled through an
explicit, reversible helper while retaining the same live audio feed.

The plugin itself never writes Voxtype configuration. `VoxtypeConfig.qml` reads
the file and fails closed: when the stock OSD is enabled or the config is
missing, Prism renders nothing and does not start its audio-bridge child.

## Lifecycle

Omarchy loads `Service.qml` once when the plugin is enabled. Disabling or
removing the plugin destroys the service, its PanelWindow, and the audio bridge.
Voxtype retains responsibility for speech capture, transcription, hotkeys, and
output. Prism is presentation-only in this release.

The helper under `scripts/` is user-invoked. It keeps a small state record under
`$XDG_STATE_HOME/voxtype-prism/` and uses an atomic replacement to change
only the scoped `[osd] enabled` key. Restore uses the recorded original value,
not a whole-file rollback, so later user changes survive.

The helper also recognizes the pre-release `voxtype-signal-osd` state path so
existing local setup state can be migrated without losing the original OSD
setting.

## Failure boundaries

- Missing Voxtype config: plugin remains dormant.
- Built-in OSD still enabled: plugin remains dormant, avoiding duplicates.
- Missing audio bridge or socket: the child retries without blocking the shell.
- QML load failure: Omarchy rejects or unloads the service through its plugin
  loader; Voxtype continues operating.
- Plugin removal without restore: Voxtype still works, but has no visualizer
  until the user runs the restore helper or re-enables its OSD.

## Distribution

The repository root is a complete Omarchy plugin and validates against manifest
schema version 1. It is intended for installation with `omarchy plugin add` and
listing through the independent omarchyplugins.com marketplace.
