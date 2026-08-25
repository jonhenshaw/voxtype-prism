# Architecture

Signal is a user-owned replacement for Voxtype's Quickshell OSD frontend. It is
not loaded into the Omarchy shell process and it does not modify packaged files.

```text
graphical-session.target
  └─ voxtype.service
      └─ voxtype daemon
          └─ voxtype-osd-quickshell --no-daemonize
              └─ qs -p $VOXTYPE_OSD_QML_PATH
                  └─ shell.qml
                      ├─ StateReader.qml
                      ├─ AudioBridge.qml
                      ├─ OmarchyPalette.qml
                      └─ SignalSurface.qml
```

## Inputs

- State: `$XDG_RUNTIME_DIR/voxtype/state`.
- Audio levels: `/usr/bin/voxtype-audio-bridge`, which reads Voxtype's audio
  socket and emits peak/RMS frames as NDJSON.
- Theme: `$XDG_STATE_HOME/omarchy/current/theme/colors.toml`, with Tokyo Night
  fallbacks when Omarchy theme data is unavailable.
- Output placement: `Hyprland.focusedMonitor`, mapped to `Quickshell.screens`.

## Lifecycle and persistence

The Voxtype daemon owns the OSD child. The Quickshell launcher stays attached
to the daemon, so service restart, logout, and reboot replace the complete
process tree together. A systemd user-service drop-in supplies
`VOXTYPE_OSD_QML_PATH`; Voxtype's config selects `frontend = "quickshell"`.

The deployed QML and drop-in live under user-owned XDG directories. Omarchy and
Voxtype package upgrades therefore do not overwrite them. Compatibility still
depends on Voxtype's state/audio contracts and Quickshell APIs remaining stable.

## Packaging direction

The current tree is suitable for a personal Git repository. A shareable release
should add idempotent install/uninstall scripts that discover XDG paths, preserve
the user's existing Voxtype configuration, write the absolute OSD path into a
service drop-in, and verify the process tree after restart. It must not ship or
rewrite a user's transcription-model settings.

`AudioBridge.qml` and `StateReader.qml` are adapted from Voxtype 0.7.5, which is
MIT licensed. The remaining QML composes the Signal indicator and Omarchy
integration around those interfaces.
