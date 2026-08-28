# Refinement Workbench design QA

Date: 2026-08-27

## Audit scope

Combined UX, visual, keyboard, resize, and accessibility-risk review of the
Refinement, Prompt, Dictionary, and Indicator destinations. The prior Option 1
mock is historical context, not a fidelity target; live user screenshots showed
that reproducing it preserved hierarchy and alignment failures.

## User goal and accessibility target

Configure Prism's enhancement layer without learning four different page
layouts. Every destination must remain readable and operable at the normal
1120 x 760 window, the 900 x 620 minimum, and larger Omarchy text. Normal-size
supporting copy targets at least the usual 4.5:1 contrast threshold.

## Before

The supplied live screenshots established the starting defects:

- Refinement placed a full labeled toggle between the title and an unrelated,
  hard-coded Signal preview.
- Hand-sized rows, percentage widths, and x/y spacer arithmetic produced
  inconsistent field widths and baselines.
- Prompt over-emphasized advice; Dictionary stretched a short tutorial to full
  editor height; Indicator used a large stage for a 156 x 40 visual.
- The footer scattered actions across the page and used misleading Reset and
  Test this prompt labels.
- Omarchy's default window opacity exposed browser and terminal content through
  the application.
- Common 1.4 to 1.55 foreground darkening produced roughly 4.28:1 to 3.60:1
  contrast on the active Tokyo Night surface.

## Implemented design system

- PrismPageHeader.qml gives every page one title/subtitle rhythm.
- PrismFormField.qml aligns labels, metadata, controls, and helper text.
- PrismSection.qml provides opaque, theme-native grouping.
- Page composition uses ColumnLayout, RowLayout, and GridLayout; manual x/y
  spacer calculations were removed from the four page bodies.
- Every page has a clipped vertical scrolling fallback for minimum-window and
  larger-text combinations.
- PrismTextArea.qml uses an opaque editor surface, a 2px accent focus border,
  readable placeholder/count copy, and conditional byte counts.
- Navigation keeps shortcut labels stable; the footer groups status, Advanced,
  Revert, and Save, then collapses safely at narrow effective widths.
- Dialog icon buttons center the glyph's tight painted bounds inside the native
  control-height target, avoiding Nerd Font advance-box drift.
- The launcher removes the default-opacity tag and applies opacity 1 1.

## Flow steps and health

1. **Refinement - healthy.** Enablement is a full-width setting row. Provider
   and model fields share a two-column grid. Test is in the section header,
   raw/output editors are equal, and privacy copy stays attached to the test.
2. **Prompt - healthy.** One editor owns the page. Guidance is a short helper,
   byte counts appear only near the limit, and Try in Refinement accurately
   names the navigation action.
3. **Dictionary - healthy.** The editor and intrinsic-height format guide align
   at normal width. At narrow effective widths or larger text, the guide
   collapses into wrapping inline help rather than overflowing.
4. **Indicator - healthy.** Preview state lives with the preview and includes
   Listening, Streaming, Processing, and Done. Style/position, scale/glow, and
   motion stay top-aligned; overflow scrolls instead of crossing the footer.

## Accepted evidence

Normal 1120 x 760:

- docs/images/refinement-workbench-implementation.png
- docs/images/refinement-workbench-prompt.png
- docs/images/refinement-workbench-dictionary.png
- docs/images/refinement-workbench-indicator-signal.png
- docs/images/refinement-workbench-indicator-halo.png
- docs/images/refinement-workbench-indicator-bar-pulse.png
- docs/images/refinement-workbench-indicator-streaming.png
- docs/images/refinement-workbench-shortcuts.png

Responsive checks:

- docs/images/refinement-workbench-dictionary-min-large-text.png
  (900 x 620, 15px Omarchy base font)
- docs/images/refinement-workbench-indicator-large-text.png
  (1120 x 760, 15px Omarchy base font)
- docs/images/refinement-workbench-refinement-min-font18.png
- docs/images/refinement-workbench-prompt-min-font18.png
- docs/images/refinement-workbench-dictionary-min-font18.png
- docs/images/refinement-workbench-indicator-min-font18.png
  (all 900 x 620 with an 18px Omarchy base font)

Each saved PNG was opened individually at original detail before acceptance.

## Behavioral evidence

- 119 Python unit tests pass.
- tests/workbench-smoke.sh passes backend draft/save/revert/conflict/close
  contracts. It is a property-level smoke test, not user-input simulation.
- omarchy plugin validate ., tests/qml-lint.sh, and git diff --check pass.
  QML lint retains the repository's known incomplete external-singleton type
  warnings and reports no fatal error.
- Independent visual-system and DHH-inspired adversarial reviewers report no
  remaining P0/P1/P2 blocker after the narrow and larger-text fixes.
- Live Hyprland inspection reports opacity 1 and no default-opacity tag; a fresh
  compositor capture shows no browser or terminal bleed.
- A QtTest mouse-wheel event against the 900 x 620, 18px Indicator page moved
  its Flickable contentY from zero, proving clipped lower controls are reachable.
- A live focused-window regression sends Alt+4, F1, Escape, and Alt+1 through
  Wayland virtual-keyboard input. OCR verifies the Indicator page, keyboard
  shortcuts overlay, overlay dismissal, and return to Refinement in order.

## Evidence limits

- Static screenshots do not prove assistive-technology announcements or full
  WCAG conformance.
- Live key evidence covers page shortcuts, the shortcuts overlay, and Escape.
  Tab traversal, dropdown selection, and dirty-dialog keyboard flows remain
  covered structurally or by property smoke rather than an exhaustive live-key
  sequence.
- Provider network success depends on the selected provider and is outside a
  no-credential UI regression.

final result: passed
