# Agents

QML is presentation-only. LLM refine is `scripts/voxtype-refine`, a Voxtype
post-process child, not an `omarchy-shell` path.

User-owned files (not in this repo):

- `~/.config/voxtype/refine.toml` — provider (`grok` default, `anthropic`, `openai`, `local`)
- `~/.config/voxtype/refine-prompt.md` — system prompt; edit in place or `scripts/voxtype-refine edit-prompt`
- `~/.config/voxtype/refine-dictionary.md` — terms appended to the system prompt; `scripts/voxtype-refine edit-dictionary`


Credentials stay in `~/.omp/agent/agent.db`. `scripts/voxtype-prism-config` only
toggles `[osd] enabled`. Human-facing commands: README.md § LLM refine.
