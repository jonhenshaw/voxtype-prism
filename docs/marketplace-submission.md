# Marketplace submission

## Issue title

```text
[Plugin]: Voxtype Prism
```

## Issue body

```markdown
### Repository URL

https://github.com/jonhenshaw/voxtype-prism

### Category

Productivity

### Tags

ai, quickshell, system

### Suggest a missing tag

_No response_

### Maintainer notes

Voxtype Prism is an Omarchy-native refinement workbench and curated indicator studio for the Voxtype dictation daemon. It ships Signal, Halo, and Bar Pulse plus an on-demand native panel for provider selection, raw-versus-refined testing, prompt editing, dictionary editing, and appearance controls. Standard installation displays an in-shell activation card, and only the user's explicit click changes `[osd] enabled`; no second terminal setup command is required. Its service installs an ownership-marked user desktop entry so Quick Shell opens Prism, while preserving the packaged Voxtype TUI as fallback. QML receives only normalized runtime values or bounded settings responses and never receives credentials. The optional `scripts/voxtype-refine` child is the only network path; it reads one bounded row from a stable, non-symlink OhMyPi database for Grok, Anthropic, or OpenAI, or talks to a loopback local model. Provider tests are explicit, remote providers receive dictated text, responses are bounded, and Voxtype falls back to raw text on post-process failure. Setup and settings writes use size-limited, symlink-safe, private atomic operations, opaque revisions, concurrent-change checks, and a private write-ahead journal for crash recovery. Foreign post-process hooks and foreign desktop entries are refused rather than overwritten. Removal instructions disable refinement, remove the owned launcher, and restore the recorded OSD value before deletion.

### Submission checklist

- [x] The repository is public and contains installation and removal instructions.
- [x] I have documented the plugin license and any external dependencies.
- [x] I confirm that I own or have permission to submit this plugin and its preview assets.
- [x] The plugin does not overwrite user configuration without explicit consent.
- [x] I understand that approval is for listing and is not a security review.
```
