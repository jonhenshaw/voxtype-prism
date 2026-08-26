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

## Requirements

- Omarchy Quattro with shell-plugin support.
- Voxtype 0.7.5 or newer, running as `voxtype.service`.
- `/usr/bin/voxtype-audio-bridge` from the Voxtype package.
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
