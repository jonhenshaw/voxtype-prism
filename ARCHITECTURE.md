# Architecture

Voxtype Prism is an Omarchy `service` plugin. It runs inside the existing
`omarchy-shell` process and never launches a second Quickshell instance. This
release ships Signal as its first visual style.

```text
omarchy-shell
  └─ io.github.jonhenshaw.voxtype-prism / Service.qml
      ├─ VoxtypeConfig.qml   gates rendering until stock OSD is disabled
      ├─ StateReader.qml     watches idle/recording/transcribing state
      ├─ BoundedValueReader.qml consumes normalized helper status tokens
      ├─ AudioBridge.qml     reads live peak/RMS frames
      ├─ OmarchyPalette.qml  follows the current theme
      ├─ PrismActivation.qml owns explicit first-run activation
      └─ SignalSurface.qml   owns the click-through PanelWindow

voxtype.service
  ├─ writes $XDG_RUNTIME_DIR/voxtype/state
  └─ serves $XDG_RUNTIME_DIR/voxtype/audio.sock

scripts/voxtype-prism-read
  ├─ opens config/runtime/palette sources with O_NOFOLLOW
  ├─ accepts only regular files below mode-specific byte ceilings
  └─ emits small normalized status tokens, never source content

scripts/voxtype-refine
  ├─ Voxtype post-process child (stdin → stdout)
  ├─ reads ~/.config/voxtype/refine.toml for grok|anthropic|openai|local
  ├─ reads ~/.config/voxtype/refine-prompt.md
  ├─ appends ~/.config/voxtype/refine-dictionary.md to the system prompt
  └─ uses OhMyPi ~/.omp/agent/agent.db; never enters QML


```

## Why the built-in Voxtype OSD is disabled

Voxtype 0.7.5 starts its audio-level broadcaster regardless of whether the
built-in OSD child is enabled. Only spawning that child is gated by
`[osd] enabled`. Prism therefore sets the built-in OSD to disabled through an
explicit, reversible helper while retaining the same live audio feed.

The plugin itself never writes Voxtype configuration. `VoxtypeConfig.qml`
receives only a normalized status token from the bounded reader and fails
closed: when the stock OSD is enabled or the config is missing, unsafe, or
oversized, Prism renders nothing and does not start its audio-bridge child.

## Lifecycle

Omarchy loads `Service.qml` once when the plugin is enabled. Disabling or
removing the plugin destroys the service, its PanelWindow, and the audio bridge.
Voxtype retains responsibility for speech capture, transcription, hotkeys, and
output. Prism is presentation-only in this release. Optional LLM refine is a
Voxtype post-process hook (`scripts/voxtype-refine`), not a Quickshell child.

When the stock OSD is still enabled, Prism displays an interactive activation
card instead of Signal. Only its explicit **Activate** action runs the audited
setup helper. Normal plugin reloads leave configuration untouched. Removal uses
the same explicit, config-bound restore helper documented in the README.

The helper under `scripts/` is user-invoked. It keeps a small state record under
`$XDG_STATE_HOME/voxtype-prism/` and uses an atomic replacement to change
only the scoped `[osd] enabled` key. Restore uses the recorded original value,
not a whole-file rollback, so later user changes survive.

Setup-state reads require a descriptor-validated regular file, reject symlinks
and oversized content, and validate a strictly typed, config-bound schema only
after the byte ceiling is enforced. Writes create a mode-0600 temporary file
through a directory descriptor, flush it, and atomically replace the destination
without following a planted link. Scoped VoxType config updates compare the
latest snapshot immediately before replacement and retry a concurrent atomic
change instead of overwriting unrelated settings.

The helper also recognizes the pre-release `voxtype-signal-osd` state path so
existing local setup state can be migrated without losing the original OSD
setting.

## Failure boundaries

- Missing Voxtype config: plugin remains dormant.
- Unsafe or oversized config: plugin remains dormant without collecting its
  content into `omarchy-shell`.
- Unsafe, oversized, or invalid runtime state: state normalizes to `idle`.
- Unsafe or oversized palette: the last safe/default palette remains active.
- Built-in OSD still enabled: plugin remains dormant, avoiding duplicates.
- First-run activation failure: the card remains visible with a bounded error;
  the stock Voxtype indicator stays active.
- Missing audio bridge or socket: the child retries without blocking the shell.
- QML load failure: Omarchy rejects or unloads the service through its plugin
  loader; Voxtype continues operating.
- Plugin removal without restore: Voxtype still works, but has no visualizer
  until the user runs the restore helper or re-enables its OSD.

## Distribution

The repository root is a complete Omarchy plugin and validates against manifest
schema version 1. It is intended for installation with `omarchy plugin add` and
listing through the independent omarchyplugins.com marketplace.
