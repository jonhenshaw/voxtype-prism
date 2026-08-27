# Voxtype Prism

An Omarchy-native enhancement layer for
[Voxtype](https://github.com/peteonrails/voxtype). The first release ships
**Signal**, a compact, theme-aware recording indicator.

![Voxtype Prism Signal recording indicator](preview.png)

- Compact 156 × 40 px pill with a tightly diffused micro-halo.
- Real microphone levels from Voxtype's audio bridge.
- Distinct listening, streaming, working, and ready states.
- Follows the focused Hyprland monitor.
- Uses an empty input region and never steals keyboard focus.
- Runs as an Omarchy `service` inside the existing `omarchy-shell` process.
- No network access, credentials, analytics, or privileged commands.
- Never loads watched config, runtime-state, or palette files into QML; a
  bounded, no-follow helper emits only normalized status tokens to
  `omarchy-shell`.

## Requirements

- Omarchy Quattro with shell-plugin support.
- Voxtype 0.7.5 or newer, running as `voxtype.service`.
- `/usr/bin/voxtype-audio-bridge` from the Voxtype package.
- Python 3 for the bundled bounded reader and reversible setup helper.
- `JetBrainsMono Nerd Font` for the state icons.

## Install

Add and enable the plugin:

```bash
omarchy plugin add https://github.com/jonhenshaw/voxtype-prism.git --enable
```

Then explicitly hand visualizer ownership from Voxtype to the plugin:

```bash
~/.config/omarchy/plugins/io.github.jonhenshaw.voxtype-prism/scripts/voxtype-prism-config setup
```

The setup helper:

1. Reads the existing Voxtype config without changing unrelated settings.
2. Records whether Voxtype's built-in OSD was enabled.
3. Creates a timestamped backup.
4. Changes only `[osd] enabled` to `false` using an atomic write.
5. Restarts and verifies `voxtype.service`.

Until setup is completed, Prism stays dormant so it never duplicates the
built-in Voxtype indicator.

Check setup state at any time:

```bash
~/.config/omarchy/plugins/io.github.jonhenshaw.voxtype-prism/scripts/voxtype-prism-config status
```

## Remove

Restore the exact OSD-enabled state recorded during setup, then remove the
plugin:

```bash
~/.config/omarchy/plugins/io.github.jonhenshaw.voxtype-prism/scripts/voxtype-prism-config restore
omarchy plugin remove io.github.jonhenshaw.voxtype-prism
```

The helper restores only `[osd] enabled`; it never rolls back or overwrites the
user's model, engine, hotkey, output, or other Voxtype settings.

## Security boundaries

- `VoxtypeConfig.qml`, `StateReader.qml`, and `OmarchyPalette.qml` consume only
  small normalized values from `scripts/voxtype-prism-read`. The helper opens sources with
  `O_NOFOLLOW`, requires regular files, enforces byte ceilings before emitting
  anything, and normalizes unexpected input to a fail-closed state.
- Setup state is read through a descriptor-validated, size-limited regular-file
  boundary, strictly typed, and bound to the requested VoxType config path.
  Writes use a private temporary file, `fsync`, and an atomic directory-relative
  replacement, so a planted symlink is replaced rather than followed.
- Config updates compare the latest bounded snapshot immediately before atomic
  replacement and retry when VoxType or its TUI concurrently replaces the file,
  preserving unrelated settings.

## Development

```bash
python3 -m unittest discover -s tests -v
omarchy plugin validate .
git diff --check
```

See [ARCHITECTURE.md](ARCHITECTURE.md) for lifecycle and failure boundaries and
[docs/design-qa.md](docs/design-qa.md) for the verified visual states.

## License and attribution

MIT. `AudioBridge.qml` and `StateReader.qml` are adapted from Voxtype 0.7.5,
copyright Peter Jackson, under Voxtype's MIT license.
