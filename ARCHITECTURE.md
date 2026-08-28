# Architecture

Voxtype Prism is an Omarchy `service` + on-demand `panel` plugin. Both run
inside the existing `omarchy-shell` process; Prism never launches a second
Quickshell instance. The service owns runtime presentation and activation. The
panel is a normal `FloatingWindow` that owns no configuration logic.

```text
omarchy-shell
  └─ io.github.jonhenshaw.voxtype-prism / Service.qml
      ├─ VoxtypeConfig.qml   gates rendering until stock OSD is disabled
      ├─ StateReader.qml     watches idle/recording/transcribing state
      ├─ BoundedValueReader.qml consumes normalized helper status tokens
      ├─ AudioBridge.qml     reads live peak/RMS frames
      ├─ OmarchyPalette.qml  follows the current theme
      ├─ PrismActivation.qml owns explicit first-run activation
      ├─ IndicatorRuntimeConfig.qml reads normalized Prism preferences
      ├─ IndicatorController.qml owns state/timing/audio history
      ├─ IndicatorVisual.qml renders Signal|Halo|Bar Pulse
      ├─ SignalSurface.qml   owns the click-through PanelWindow
      └─ LauncherManager.qml installs the separate guarded Quick Shell entry

omarchy-shell (only while summoned)
  └─ SettingsPanel.qml / FloatingWindow
      ├─ SettingsBackend.qml sends bounded JSON over Process stdin
      ├─ PrismTextArea.qml owns native multiline editing
      └─ IndicatorVisual.qml supplies the exact live preview renderer

voxtype.service
  ├─ writes $XDG_RUNTIME_DIR/voxtype/state
  └─ serves $XDG_RUNTIME_DIR/voxtype/audio.sock

scripts/voxtype-prism-read
  ├─ opens config/runtime/palette/indicator sources with O_NOFOLLOW
  ├─ accepts only regular files below mode-specific byte ceilings
  └─ emits small normalized status tokens, never source content

scripts/voxtype-prism-settings
  ├─ snapshot → normalized, credential-free JSON + opaque revision
  ├─ apply ← expected revision + partial patch on stdin
  ├─ test-refine ← explicit sample + unsaved candidate on stdin
  ├─ owns safe prompt/dictionary/provider/indicator persistence
  └─ owns narrow, reversible Voxtype post-process integration

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

The long-lived QML service never writes Voxtype configuration.
`VoxtypeConfig.qml` receives only a normalized status token from the bounded
reader and fails closed: when the stock OSD is enabled or the config is missing,
unsafe, or oversized, Prism renders nothing and does not start its audio-bridge
child. Writes occur only after an explicit activation or workbench save through
the Python helpers.

## Lifecycle

Omarchy loads `Service.qml` once when the plugin is enabled. It keeps the light
`SettingsPanel.qml` object mounted so a host toggle cannot destroy a dirty
draft, but the FloatingWindow stays hidden and the backend does no work until
the panel is summoned. Disabling or removing the plugin destroys the service,
indicator PanelWindow, settings FloatingWindow, and audio bridge.
Voxtype retains responsibility for speech capture, transcription, hotkeys, and
output. QML remains presentation-only; optional LLM refinement executes as a
Voxtype post-process child (`scripts/voxtype-refine`), not as a Quickshell
network path.

When the stock OSD is still enabled, Prism displays an interactive activation
card instead of Signal. Only its explicit **Activate** action runs the audited
setup helper. Normal plugin reloads leave configuration untouched. Removal uses
the same explicit, config-bound restore helper documented in the README.

The activation helper keeps a small state record under
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

The settings backend computes a composite hash across every managed input.
Mutations require that opaque revision, validate the full partial patch before
writing, and persist a private write-ahead journal before the first replacement.
An interrupted prepared transaction restores candidate-valued files only when
readback proves ownership; a committed journal is finalized without rolling the
save back. Unknown or concurrently changed values stop recovery rather than
being overwritten. A service restart failure is reported as committed rather
than pretending disk state was rolled back. Foreign post-process commands are
never overwritten. The earlier exact Prism trampoline is recognized through a
bounded AST check and migrated on explicit save.

Provider readiness is a redacted label. The OhMyPi database must be a bounded,
stable, non-symlink regular file; only one size-capped provider row is parsed.
Credential contents and HTTP authorization never cross the settings interface.
`test-refine` is the only settings action allowed to contact a provider; normal
snapshots and saves are local operations.

## Failure boundaries

- Missing Voxtype config: plugin remains dormant.
- Unsafe or oversized config: plugin remains dormant without collecting its
  content into `omarchy-shell`.
- Unsafe, oversized, or invalid runtime state: state normalizes to `idle`.
- Unsafe or oversized palette: the last safe/default palette remains active.
- Unsafe, oversized, or unknown indicator preferences: Signal defaults are
  used without loading the document into QML.
- Built-in OSD still enabled: plugin remains dormant, avoiding duplicates.
- First-run activation failure: the card remains visible with a bounded error;
  the stock Voxtype indicator stays active.
- Missing audio bridge or socket: the child retries without blocking the shell.
- Concurrent settings edit: save fails with a fresh conflict instead of
  overwriting the other writer.
- Foreign post-process hook: refinement enablement is refused and the command
  remains unchanged.
- Provider or test failure: the explicit test reports a redacted error; normal
  Voxtype post-processing retains upstream raw-transcript fallback behavior.
- Launcher conflict: a foreign `voxtype-prism.desktop` is preserved. Migration
  removes only an older Prism-marked configuration override, so Voxtype's
  packaged settings launcher remains independently available.
- QML load failure: Omarchy rejects or unloads the service through its plugin
  loader; Voxtype continues operating.
- Plugin removal without restore: Voxtype still works, but has no visualizer
  until the user runs the restore helper or re-enables its OSD.

## Distribution

The repository root is a complete Omarchy plugin and validates against manifest
schema version 1. It is intended for installation with `omarchy plugin add` and
listing through the independent omarchyplugins.com marketplace.
