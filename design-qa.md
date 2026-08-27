# Refinement Workbench design QA

**Source visual truth**

- `docs/images/refinement-workbench-reference.png`
- Selected Option 1, Refinement Workbench.

**Rendered implementation**

- `docs/images/refinement-workbench-implementation.png`
- Production `SettingsPanel.qml` rendered with the installed Omarchy `Ui` and
  `Commons` modules, live redacted settings, and the software Qt Quick backend
  through `tests/capture-workbench.sh`.

**Viewport and normalization**

- Production window: 1120 x 760 logical QML pixels.
- Live monitor: 1.6 device scale; the compositor reports the deployed window at
  exactly 1120 x 760 logical pixels, floating and centered.
- Source pixels: 1487 x 1058, treated as the source's native 1x design canvas.
- Implementation pixels: 1120 x 760 at `QT_SCALE_FACTOR=1`.
- Full comparison normalization: implementation scaled uniformly to
  1487 x 1009 (1.3277x), then centered on a 1487 x 1058 black canvas. No
  non-uniform stretching was used.
- Side-by-side evidence:
  `docs/images/refinement-workbench-comparison.png`.

**State**

- Refinement tab, enabled, Grok ready, no model override, live effective-model
  label, listening indicator, populated raw and refined text, successful test
  status, and a dirty draft so Reset and Save are enabled.
- The success output and 418 ms duration are capture-only presentation data.
  No provider request was made and no credential entered QML.
- Supporting production captures also cover Prompt, Dictionary, and Indicator,
  plus Signal, Halo, and Bar Pulse indicator presets.

## Findings

- No actionable P0, P1, or P2 mismatch remains.
- The implementation preserves the source's information architecture and
  hierarchy: 18% navigation rail, refinement-first header, provider/model/
  readiness row, paired raw/output work area, centered explicit test action,
  privacy disclosure, and persistent Reset/Save/Advanced footer.
- Intentional deviation: production uses live Omarchy font, fill, border,
  focus, accent, and spacing tokens instead of reproducing the mock's pink
  gradient skin or drawing a fake title bar. This is required by the product
  spec and keeps Prism native across themes.
- Intentional addition: the model control distinguishes an optional override
  from the effective provider model. This is useful state, fits without
  collision, and does not change the hierarchy.
- P3 fixed during QA: the first implementation capture repeated the long model
  name in the success status and elided the duration. The status now reads
  `Refinement completed · 418 ms`; the model remains visible in its dedicated
  field.

## Required fidelity surfaces

- **Fonts and typography:** both designs use a monospace UI voice. Production
  uses `Style.font.family` and the native display/heading/subtitle/body/caption
  scale. Labels remain legible at the machine's 1.6 display scale, hierarchy is
  clear, long model text elides safely, and body copy wraps without clipping.
- **Spacing and layout rhythm:** the normalized full view shows matching major
  regions and ordering. At 1120 x 760, navigation, provider controls, editors,
  privacy copy, and footer actions do not overlap or leave controls off-screen.
  Prompt, Dictionary, and Indicator captures show the same margins and footer
  alignment.
- **Colors and visual tokens:** source intent is a dark, focused workbench with
  one expressive signal color. Production maps this to `Color.background`,
  `Color.popups.background`, `Color.foreground`, `Color.muted`, `Color.accent`,
  and `Color.urgent`; semantic readiness, error, focus, and disabled states keep
  sufficient visual separation.
- **Image quality and asset fidelity:** this settings surface requires no
  photographic or branded raster assets. Icons use Omarchy's installed icon
  font and indicator visuals reuse the real runtime QML renderer. Captures are
  lossless PNGs with no scaling artifacts in the implementation truth image.
- **Copy and content:** provider privacy is explicit, tests disclose that they
  do not save changes, local prompt/dictionary paths are named, model override
  behavior is clear, and Advanced Voxtype settings remains an escape hatch.
- **Controls and accessibility:** native buttons, dropdowns, text fields,
  sliders, and toggle components expose accessible names; focusable actions and
  documented shortcuts are present; reduced motion is injectable; dirty close,
  modal focus restoration, validation, conflict, loading, success, failure,
  and stale-output states are implemented.

## Focused comparison evidence

- Header/provider/readiness:
  `docs/images/refinement-workbench-comparison-header.png`.
- Raw/refined workspace:
  `docs/images/refinement-workbench-comparison-test.png`.
- These crops were required because typography, model labeling, editor borders,
  and status copy are too small to judge reliably in the full 3046 px montage.

## Interaction and runtime evidence

- `tests/workbench-smoke.sh` opens the real panel, edits provider/prompt/
  dictionary/indicator settings, cycles all presets, saves through the JSON
  backend, verifies round-trip state, tests dirty re-summon, reset, UTF-8 byte
  limits, tab navigation, dirty-close interception, and clean close.
- The fake-provider unit test exercises raw-to-refined output without writing
  the candidate settings or using the network.
- Direct shell summon and the user-scoped `voxtype-configure.desktop` path both
  opened the deployed panel. Hyprland reported title `Voxtype Prism`, floating
  1120 x 760, centered at 640,308; no stock configuration window appeared.
- Live shell logs were checked after the launcher fixes. There were no panel
  load errors or desktop-entry escape warnings. Offscreen capture emits only
  the expected platform warning and unsupported-window-mask warning.

## Comparison history

1. First side-by-side pass: no P0/P1/P2 mismatch. One P3 status truncation was
   found; the redundant model repetition was removed.
2. Post-fix pass: full and focused comparisons show the duration in full and no
   new P0/P1/P2 issue. Prompt, Dictionary, Indicator, Signal, Halo, and Bar Pulse
   supporting captures were also reviewed for clipping and alignment.

## Implementation checklist

- [x] Match selected workbench structure and hierarchy.
- [x] Use native Omarchy theme and control primitives.
- [x] Preserve same-state success, dirty, and listening evidence.
- [x] Verify all supporting tabs and three indicator presets.
- [x] Fix status truncation and recapture.
- [x] Check live launcher geometry and shell errors.

## Follow-up polish

- No blocking polish remains. A future Omarchy theme token for a stronger
  always-primary action fill could make Test refinement more prominent without
  introducing a Prism-only button style.

final result: passed
