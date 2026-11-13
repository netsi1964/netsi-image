Agent: lc-spec
Mode: Spec
Status: Ready
Confidence: Medium
Artifact mode: brief
Artifact folder: .lc/developer/netsi-image-openrouter-parameter-engine/

## TL;DR
<!-- lc-tldr -->

- Deliver the P0 slice of Netsi Image as one SwiftPM package: catalog store, schema-driven parameter form (13 control kinds), validation engine, `images` request builder, OpenRouter generation with SSE, file + sidecar library, API key in Keychain.
- The bundled catalog is the only source of truth: 68 models, 69 image endpoints, 1,154 `images` parameter entries (1,907 across all three surfaces); no parameter is hardcoded.
- 18 ordered work items (ITEM-001…ITEM-018) with 57 acceptance criteria; all are testable headlessly except the UI/accessibility ones, which get a written manual procedure.
- Two input conflicts are recorded: PRD AC-1.2 expects 17 parameters for the sunburst endpoint while the catalog lists 24, and PRD AC-4.1 references an example body that also carries `provider.options.openai.complexity`.
- Out of scope: PRD-FEAT-008…016 (pricing/budget, history, presets, batch queue, compare, skills, Shortcuts, export) and the `chatCompletions`/`responses` surfaces.

## Result and scope

Netsi Image must let one person run any OpenRouter image model on that model's own terms: every field the selected endpoint declares is settable, nothing is sent that the endpoint does not declare, and every result stays reproducible from a file next to the image. This delivery builds the P0 spine of that product — the catalog, the parameter engine, the `images` request path, one generation flow with streaming, the file/sidecar library and the Keychain-backed key — as a repository that builds and tests headlessly (`swift build`, `swift test`) with the SwiftUI macOS app as a compiling executable target.

**Release slice.** All seven P0 features (PRD-FEAT-001…007) restricted to the `images` surface. The slice is valuable on its own: a user can pick any of the 68 models, configure all its parameters with validation, inspect the exact request, generate, and find image + metadata later. Pricing estimates, budget, presets, history, queue, comparison and skills are deferred, so the run button carries no cost guard beyond showing the returned `usage.cost` after the fact.

**Repository layout assumed.** Greenfield directory, **no git repository yet** (so no history, branch or CI assumptions); toolchain Swift 6.4.2 / Xcode 27.2 / macOS 27.2 on Apple Silicon. Only two files exist today: `develop/PRD.md` and `openrouter-image-ui-catalog.json`.

```text
<repo root>/                          /Users/stenhougaard/Documents/GitHub/netsi-image
├── Package.swift                     SwiftPM manifest, platform macOS 27, Swift 6 language mode
├── develop/PRD.md                    approved PRD (input, never built)
├── openrouter-image-ui-catalog.json  canonical catalog snapshot, left unchanged
├── Sources/
│   ├── CatalogCore/                  catalog Codable model, JSONValue, lazy CatalogStore, refresh client
│   │   └── Resources/openrouter-image-ui-catalog.json   bundled copy, read via Bundle.module
│   ├── ParameterEngine/              ParameterDraft, control model, JSON Schema validator, activeWhen, valueConstraints, field constraints
│   ├── RequestKit/                   images request builder, JSON preview, SSE parser, response decoding
│   ├── GenerationKit/                OpenRouter client, job model + state, error mapping, coordinator
│   ├── LibraryKit/                   file + sidecar writer, index, rebuild, search, trash
│   ├── SettingsKit/                  settings model, Keychain store, read-only state
│   ├── NetsiImageUI/                 SwiftUI views, evidence badges, parameter inspector, design tokens
│   └── NetsiImageApp/                executable target: app entry, windows, commands (must compile headlessly)
└── Tests/
    ├── CatalogCoreTests/  ParameterEngineTests/  RequestKitTests/
    └── GenerationKitTests/  LibraryKitTests/  SettingsKitTests/
```

The plan may rename or split targets inside this layout, but must keep all non-UI logic in library targets with unit tests, keep the UI in the macOS SwiftUI executable target, and keep the bundled catalog byte-identical to the repo-root file.

**Facts measured directly on the catalog** (used by the acceptance criteria, not taken from the PRD): schemaVersion `1.0.0`, generatedAt `2026-11-11T10:48:18+00:00`, baseUrl `https://openrouter.ai`, language `da-DK`; 68 models, 121 endpoints (69 `images`, 26 `chatCompletions`, 26 `responses`), 1,907 parameter entries of which 1,154 are on `images` endpoints; image endpoint parameter counts 13–24, none empty; 10 endpoints declare `supportsStreaming`, all on `images`; 16 `activeWhen`, 13 `valueConstraints`, 5 `constraints`, 207 `suggestedValues`; 345 `routing` and 130 `provider_options` entries; 17 provider routes; `meta/muse-image` is the only model with an `images` surface but no endpoint; `openrouter/auto`, `openrouter/auto-code`, `openrouter/auto-beta` expose only `chatCompletions`/`responses`. Control-kind totals match the PRD exactly (select 357, text 283, json-editor 410, number 232, multi-select 190, checkbox 142, repeater 78, ordered-multi-select 69, textarea 69, image-list 68, size-input 6, image-input 2, constant 1).

**Out of scope for this run.**

- PRD-FEAT-008 (pricing/budget), 009 (history/diff), 010 (presets/favourites), 011 (input images beyond attaching local files to `image-list`/`image-input` fields), 012 (batch queue), 013 (compare), 014 (skills), 015 (Shortcuts), 016 (export/share/notifications).
- `chatCompletions` and `responses` request building, response decoding and their surface switch.
- Embedded metadata inside image containers (PNG `iTXt` / JPEG XMP / WebP EXIF), thumbnails, gallery UI polish, notifications, notarisation/signing, GitHub Actions CI, iOS.

**Non-functional constraints** (measurable, from PRD 4.5, 6.3 and 7.1–7.5; each is verified by an AC or a stated check).

| NFR | Constraint | Check |
|---|---|---|
| NFR-001 | Cold start to interactive model list ≤ 500 ms; one endpoint decode ≤ 50 ms; form re-render on model switch ≤ 150 ms; full validation of 200 fields ≤ 20 ms; preview update ≤ 50 ms; index search ≤ 300 ms at 10,000 items | Timed unit tests with generous CI slack, plus manual stopwatch run |
| NFR-002 | No third-party runtime dependency; URLSession, ImageIO, Security and SwiftData/SQLite only | Package dependency list review |
| NFR-003 | API key exists only in Keychain: never in UserDefaults, sidecars, logs, error text, dumps, fixtures or exports | AC-055, plus grep of the generated library folder and log output |
| NFR-004 | No telemetry by default; nothing leaves the machine except the request to `openrouter.ai`; no prompt content in default logs | Code review + offline test (AC-009) |
| NFR-005 | Atomic writes (temp + rename); index is derived and rebuildable; a failed refresh never destroys the last good catalog; unknown catalog/schema data degrades to a warning, never a crash | AC-010, AC-011, AC-017, AC-051 |
| NFR-006 | Every field exposes a label and a value description for VoiceOver; full keyboard operation; text contrast ≥ 4.5:1; evidence badges use shape + text, not colour alone; Reduce Motion respected | Manual procedure (AC-020, see Assumptions) |
| NFR-007 | Swift 6 strict concurrency: catalog is immutable after load and replaced atomically; services are actors or `Sendable`; UI never talks to HTTP or the filesystem directly (PRD 4.2 layer rules) | Build with strict concurrency + review |
| NFR-008 | Local debug log records ignored schema keywords, refresh failures and error mappings without key or prompt content | Log inspection in AC-024, AC-011 |
| NFR-009 | Danish UI; all user-facing strings via localisable keys so English can be added later; catalog labels are already `da-DK` | String catalogue review |
| NFR-010 | Network, Keychain, clock and filesystem access are injectable so the whole suite runs offline, deterministic, with no real spend and no Keychain prompts | Test run with network disabled |
| NFR-011 | macOS 27+, Apple Silicon; builds with the available Swift 6.4.2 toolchain and no Xcode project requirement | AC-001 |
| NFR-012 | No compliance claim is made. Provider data policy is shown before sending; the app stores everything locally; sandbox entitlements are declared but signing/notarisation is untested here | Review of entitlements and settings copy |

## Work items

Work items are in delivery order; each is independently testable and can ship alone behind the previous one.

### ITEM-001 (aliases: REQ-001, AC-001, AC-002, AC-003)
- Understanding: The repository must build and test headlessly on the available toolchain, with all real logic in libraries and a SwiftUI app that at least compiles.
- Done when:
  - AC-001 `swift build` and `swift test` succeed from a clean checkout of the repo root with network access disabled; no `.xcodeproj` is needed for either.
  - AC-002 The package exposes library targets for catalog, parameter engine, request building, generation, library and settings, plus a macOS SwiftUI executable target that compiles; every library target with logic has a test target.
  - AC-003 The bundled catalog resource is reachable at runtime through `Bundle.module` and its SHA-256 equals the SHA-256 of the repo-root `openrouter-image-ui-catalog.json`.
- Not included: GitHub Actions workflow, notarisation, hardened runtime, app icon.

### ITEM-002 (aliases: REQ-002, AC-004, AC-005, AC-006)
- Understanding: The whole app depends on a lossless, tolerant Swift model of the catalog JSON, including free-form JSON values.
- Done when:
  - AC-004 Decoding the bundled catalog yields `schemaVersion` "1.0.0", 68 models, 121 endpoints across three surfaces and 1,907 parameter entries; unknown top-level and unknown per-model/per-parameter keys decode without error.
  - AC-005 Decoding, re-encoding and decoding the full catalog yields an equal value for every declared field (round-trip), and every `$ref` reachable from model parameter schemas resolves inside the catalog's `$defs` (report: 0 dangling, 0 non-local refs).
  - AC-006 The parameter path of `provider.options.google-ai-studio/global.cachedContent` decodes to exactly 4 components, the third being the single key `google-ai-studio/global`.
- Not included: live-mapping code (ITEM-004).

### ITEM-003 (aliases: REQ-003, AC-007, AC-008, AC-009)
- Understanding: A 2.4 MB catalog must not slow startup, must be browsable offline, and must expose the provenance the UI shows in settings.
- Done when:
  - AC-007 Reading the catalog summary (generatedAt, model count, provider count) does not decode endpoint parameter lists, and first access to one model decodes only that model (asserted via an instrumented decode counter, not wall-clock alone).
  - AC-008 The summary reports generatedAt 2026-11-11T10:48:18Z, 68 models, 17 provider routes and 65 models with an `images` surface, matching `coverage`.
  - AC-009 With every outbound request failing, catalog browsing, parameter rendering, validation and JSON preview still succeed.
- Not included: refresh (ITEM-004).

### ITEM-004 (aliases: REQ-004, AC-010, AC-011, AC-012)
- Understanding: The catalog must be refreshable from its declared `sources` without ever leaving the app in a broken state.
- Done when:
  - AC-010 A refresh whose mapped result reports a `schemaVersion` other than the bundled one is rejected and the rejection is surfaced with the offending version; the active snapshot is unchanged.
  - AC-011 Any refresh failure (HTTP error, malformed JSON, schema break) leaves the active snapshot's `generatedAt` unchanged and produces an error message naming the failing source URL; the failure is also written to the local debug log.
  - AC-012 A successful refresh replaces the active snapshot atomically, shows the new `generatedAt` and counts, makes new models appear in the picker without restart, and is cached locally with per-section source URLs so the next launch uses it.
- Not included: scheduled background refresh; diffing two catalog versions.

### ITEM-005 (aliases: REQ-005, AC-013, AC-014, AC-015)
- Understanding: The user must find the right model and endpoint quickly, and always see what the model can actually do.
- Done when:
  - AC-013 The picker lists all 68 models; each row shows publisher, available surfaces, provider and a streaming badge when any endpoint declares `supportsStreaming`; `meta/muse-image` is shown with an explicit "no public image endpoint" state and `openrouter/auto*` are shown as not generatable in this release.
  - AC-014 Text, publisher, surface and provider filters compose and are stable across a refresh; a model that no longer matches a filter disappears without clearing the filter.
  - AC-015 Selecting `openai/gpt-image-2.6-sunburst` resolves exactly one `images` endpoint (`openai/gpt-image-2.6-sunburst@openai`) and its parameter list becomes the active form.
- Missing decisions: Q-002 (non-blocking: router models), Q-003 (non-blocking: default surface setting).

### ITEM-006 (aliases: REQ-006, AC-016, AC-017, AC-018, AC-019, AC-020)
- Understanding: Every declared parameter must appear exactly once, with the right widget, the right choices, the right limits and an honest evidence badge — driven only by catalog data.
- Done when:
  - AC-016 For all 69 `images` endpoints the rendered field set equals the endpoint's `parameters` list one-to-one by path (69/69 endpoints, 1,154/1,154 entries; sunburst renders 24 fields; no empty endpoint).
  - AC-017 All 13 `control` kinds map to their specified widget, and rendering the full catalog produces the catalog's own totals per kind (select 357, text 283, json-editor 410, number 232, multi-select 190, checkbox 142, repeater 78, ordered-multi-select 69, textarea 69, image-list 68, size-input 6, image-input 2, constant 1); an unknown `control` value renders as a JSON editor with a warning and never crashes.
  - AC-018 A `select` shows exactly `schema.enum` when present and `capability.values` otherwise; a `number` rejects non-numeric text and enforces the effective min/max; an `image-list` with `maxItems` 16 accepts 16 references and refuses the 17th with the reason (12 catalog fields use 16; the catalog range is 1–20).
  - AC-019 `routing` (345) and `provider_options` (130) fields live in separate collapsible sections titled "Routing" and "Provider-options" with field and changed counts; ungrouped fields come first with `required` first, then catalog order; every field shows its `evidence` badge and its `source` as tooltip with the badge buckets from the PRD table; search matches `key`, `label` and `path` and expands the section containing the hit.
  - AC-020 `suggestedValues` are offered as suggestions in `text`/`size-input`/matching controls and never restrict what can be entered; every field's accessibility label is generated from label + type + current value, and the keyboard/VoiceOver walkthrough in the manual procedure passes (NFR-006).
- Missing decisions: Q-004 (non-blocking: hiding uncertain fields by default).
- Not included: per-field favourites, per-field help authoring.

### ITEM-007 (aliases: REQ-007, AC-021, AC-022)
- Understanding: A field the user never touched must not be sent, so the provider default is never silently overridden.
- Done when:
  - AC-021 A never-touched optional field is `unset` and its key is absent from the preview body; setting a value and then resetting it returns the field to `unset` and removes the key again.
  - AC-022 Switching endpoints keeps values whose path exists on both endpoints with a compatible schema type; values whose path is missing or incompatible are listed as "not supported" and removed from the request only after explicit confirmation, which names each dropped path.
- Missing decisions: Q-005 (non-blocking: what counts as "compatible type").

### ITEM-008 (aliases: REQ-008, AC-023, AC-024, AC-025, AC-026)
- Understanding: Values must be checked against the endpoint's own schema, with the catalog as the `$ref` root, using a small validator we control.
- Done when:
  - AC-023 The validator supports `type` (including nullable arrays such as `["integer","null"]`), `enum`, `const`, `minimum`, `maximum`, `minLength`, `maxLength`, `pattern`, `minItems`, `maxItems`, `required`, `properties`, `items`, `anyOf`/`oneOf`/`allOf` and local `$ref` into `$defs`; unknown keywords are ignored and recorded in the debug log.
  - AC-024 A `$ref` to `ContentPartImage` accepts `{"type":"image_url","image_url":{"url":"…"}}` and rejects a value missing `image_url.url` or with a different `type`.
  - AC-025 `["integer","null"]` accepts an empty value as `null` and the field stays optional; a wrong type or a violated bound produces a blocking issue naming path, expected and actual.
  - AC-026 Where the endpoint declares `capability` bounds (`enum`, `range`) they override wider model-level schema bounds (e.g. `n` is limited 1–10 by `capability`, not by the OpenAPI schema).
- Not included: remote schema fetching; full JSON Schema 2020-12 support beyond the listed keywords.

### ITEM-009 (aliases: REQ-009, AC-027, AC-028, AC-029)
- Understanding: Conditionally relevant fields must be visibly unavailable and must never be sent when their condition fails.
- Done when:
  - AC-027 `equals`: `frame_count` on `openai/gpt-image-2.6-sunburst@openai` is inactive unless `output_format` is `gif`.
  - AC-028 `in` (10 entries) and `minItems` (2 entries, e.g. `markup` requires at least one `input_references` item) evaluate correctly against the draft; an unknown operator leaves the field active and records a warning.
  - AC-029 Inactive fields are hidden by default with a per-section count, the "show inactive fields" setting disables them instead of hiding, and an inactive field's value is excluded from the body and reported in the preview's "not sent" list.
- Not included: dependency-graph reordering of the form.

### ITEM-010 (aliases: REQ-010, AC-030, AC-031, AC-032)
- Understanding: Some values are only valid in combination with another field value, and some are only valid as file content; both must be caught before sending, with a concrete fix.
- Done when:
  - AC-030 `output_format: "jpeg"` with `background: "transparent"` is blocked with a message stating that transparent requires png or webp, plus a one-click fix that sets `output_format` to `png`.
  - AC-031 An option governed by a `valueConstraints` rule whose prerequisite is unmet is shown unavailable with the explanation in the picker (13 catalog entries).
  - AC-032 A `markup` mask that is not PNG, has no alpha, or has dimensions different from `input_references[0]` is rejected before sending with one explanation per violated rule (`mediaType`, `transparent`, `matchDimensionsOfReference`), and `size` enforces `pixelSize` step 16 and maxAspectRatio 3 (5 catalog `constraints` entries).
- Missing decisions: Q-006 (non-blocking: alpha detection for non-PNG sources).
- Not included: in-app mask painting or resizing.

### ITEM-011 (aliases: REQ-011, AC-033, AC-034, AC-035)
- Understanding: Errors must be located, prioritised and actionable, and they must gate the run button without blocking editing.
- Done when:
  - AC-033 Every issue carries path, severity (blocking/warning), message and optional fix suggestion; warnings never block generation.
  - AC-034 The run button is disabled while any blocking issue exists and shows the count ("3 felter mangler opmærksomhed"); activating it scrolls to the first issue; fixing one issue clears it and leaves all others untouched.
  - AC-035 Validating a synthesized 200-field endpoint completes within 20 ms on the development machine (measured in the test, reported as a value, no silent skip).
- Not included: fix suggestions that mutate more than one field.

### ITEM-012 (aliases: REQ-012, AC-036, AC-037, AC-038, AC-039)
- Understanding: The draft must become the exact `images` request body — nested paths preserved, unset fields omitted, provider routing and streaming handled per catalog rules.
- Done when:
  - AC-036 Only active, set parameter paths are applied, each path component becomes one key; the only keys added outside the endpoint's parameters are `model` and `stream`, and a parameter path with a slash in a component (e.g. `provider.options.google-ai-studio/global.cachedContent`) produces exactly that nesting.
  - AC-037 With an explicit provider, the endpoint's `providerPin` is merged as `{only:[slug], allow_fallbacks:false}` and selected provider-options land under `provider.options.<slug>`; `stream: true` is set only when streaming is enabled and the endpoint declares `supportsStreaming`; auto-routing sends only parameters valid for all candidate routes and warns when a selected parameter is not.
  - AC-038 Fixture 1 (prompt, `aspect_ratio` "3:2", `quality` "high", `output_format` "png", explicit provider openai, `provider.options.openai.complexity` "high") equals `requestExamples[0].body` order-insensitively; fixture 2 (google `gemini-3.1-flash-image`, `resolution` "2K", pin `google-vertex/global`) equals `requestExamples[1].body`.
  - AC-039 Requesting a surface other than `images` returns an explicit "unsupported in this release" error and never a partially built body; a request that still has blocking issues throws with those issues attached and sends nothing.
- Missing decisions: Q-007 (non-blocking: `model` source and the routing semantics for auto).
- Not included: `chatCompletions` and `responses` envelopes; auto-routing qualification analysis against live routes.

### ITEM-013 (aliases: REQ-013, AC-040, AC-041)
- Understanding: The user must be able to see exactly what will be sent, before sending it.
- Done when:
  - AC-040 The preview shows pretty-printed JSON of the exact bytes the client would send, updates within 50 ms of a field change, is copyable as-is, and can be limited to changed fields.
  - AC-041 Base64 image payloads appear in the preview as a redacted placeholder with file name and size while the body passed to the client contains the full base64 (asserted by comparing both).
- Not included: diff against the previous run; export as `.json`/`curl`.

### ITEM-014 (aliases: REQ-014, AC-042, AC-043, AC-044)
- Understanding: Generation must be a reliable, cancellable, idempotent call whose failures are understandable and whose cost is recorded.
- Done when:
  - AC-042 `POST /api/v1/images` with the bearer header, `HTTP-Referer` and `X-Title` set, on a 200 response with `data[*].b64_json` yields one result per image with media type from `data[*].media_type`, and `usage.cost` is stored on the job.
  - AC-043 Errors map to actionable states: 401 key problem, 402 credit, 429 with `retry-after` (shown as "try again in X s"), 5xx retryable, network failure offline; each message is human-readable, the raw provider body is available behind a details disclosure, and no message, log line or request dump contains the API key.
  - AC-044 Cancelling stops network traffic within 1 s and leaves the job `cancelled`; every job carries a UUID that is written into the sidecar, and submitting an already-active job id does not produce a second request.
- Missing decisions: Q-008 (non-blocking: automatic retry scope in this slice).
- Not included: queue, concurrency control, budget stop, offline queue.

### ITEM-015 (aliases: REQ-015, AC-045, AC-046, AC-047)
- Understanding: Streaming endpoints must show partial images as they arrive and finish deterministically.
- Done when:
  - AC-045 The SSE parser handles an event split across several chunks, several events in one chunk, CRLF and LF endings, comment/keep-alive lines and a terminal `[DONE]`, using synthetic fragments in unit tests.
  - AC-046 `image_generation.partial_image` is surfaced before the final image, `image_generation.completed` yields the final image plus cost, and `error` yields an issue carrying the provider's request id.
  - AC-047 `stream: true` is emitted only for the 10 catalog endpoints declaring `supportsStreaming`; for all others the non-streaming path is used and the elapsed time is shown without any invented duration estimate.
- Missing decisions: Q-009 (non-blocking: partial-image retention).
- Not included: historical timing statistics per endpoint.

### ITEM-016 (aliases: REQ-016, AC-048, AC-049, AC-050)
- Understanding: A result must outlive the app: an image you can open in Finder plus an authoritative sidecar that reproduces the request.
- Done when:
  - AC-048 A saved generation writes `Library/yyyy/MM/dd/yyyyMMdd-HHmmss-<model-slug>-<jobid-6>.<ext>` plus a `.json` sidecar beside it in the chosen root; name collisions get a deterministic suffix instead of overwriting.
  - AC-049 The sidecar (formatVersion 1) contains prompt raw and composed, model id/name/endpoint/provider/surface, every applied parameter in PathKey notation, the full request body, result file/sha256/bytes/mediaType/width/height/seed, usage cost and latency, app version and catalog version; re-reading and re-writing preserves unknown additional fields.
  - AC-050 Writes are atomic (temp file + rename), and any target path resolving outside the chosen root is refused before a byte is written (asserted with a traversal-style relative path).
- Missing decisions: Q-010 (non-blocking: embedded container metadata and thumbnails).
- Not included: PNG/JPEG/WebP embedded metadata, thumbnails, importer for foreign files, in-app trash UI beyond "move to Trash".

### ITEM-017 (aliases: REQ-017, AC-051, AC-052, AC-053)
- Understanding: The index is a cache over the files; losing it must cost nothing, and stale paths must be visible.
- Done when:
  - AC-051 Deleting the index, relaunching and running "Rebuild index" restores every item with model, prompt text, date, cost and hash matching the sidecars (fixture of ≥ 25 items).
  - AC-052 An item whose image was moved outside the app is reported as `missing` and can be relinked or removed without touching other items.
  - AC-053 A prompt-word search over a 10,000-item index fixture returns the matching items within 300 ms (measured value reported).
- Missing decisions: Q-001 (non-blocking: index storage engine).
- Not included: smart collections, tags UI, favourites, iCloud sync.

### ITEM-018 (aliases: REQ-018, AC-054, AC-055, AC-056, AC-057)
- Understanding: The key must be easy to set up, hard to leak, and its absence must degrade to a usable read-only app.
- Done when:
  - AC-054 Saving a key stores a generic-password item with service `dk.netsi.image.openrouter` and account `api-key`, accessible after first unlock, device-only; the key never appears in `UserDefaults`, sidecars, the library folder, or log output, and the UI shows only a masked suffix.
  - AC-055 "Test key" performs one cheap authorised request; a rejected key produces an understandable Danish error and is not stored.
  - AC-056 Deleting the key asks for confirmation and leaves catalog, form, preview, validation and library fully usable while generation is disabled with an explanation.
  - AC-057 A locked or denied Keychain produces guidance and no crash; injected Keychain failures are covered by unit tests.
- Missing decisions: Q-003 (non-blocking: settings list completeness), Q-005 rotated-key behaviour.
- Not included: onboarding wizard, per-provider overrides, budget settings, telemetry toggle wiring.

### Traceability
| AC | REQ |
|---|---|
| AC-001, AC-002, AC-003 | REQ-001 |
| AC-004, AC-005, AC-006 | REQ-002 |
| AC-007, AC-008, AC-009 | REQ-003 |
| AC-010, AC-011, AC-012 | REQ-004 |
| AC-013, AC-014, AC-015 | REQ-005 |
| AC-016, AC-017, AC-018, AC-019, AC-020 | REQ-006 |
| AC-021, AC-022 | REQ-007 |
| AC-023, AC-024, AC-025, AC-026 | REQ-008 |
| AC-027, AC-028, AC-029 | REQ-009 |
| AC-030, AC-031, AC-032 | REQ-010 |
| AC-033, AC-034, AC-035 | REQ-011 |
| AC-036, AC-037, AC-038, AC-039 | REQ-012 |
| AC-040, AC-041 | REQ-013 |
| AC-042, AC-043, AC-044 | REQ-014 |
| AC-045, AC-046, AC-047 | REQ-015 |
| AC-048, AC-049, AC-050 | REQ-016 |
| AC-051, AC-052, AC-053 | REQ-017 |
| AC-054, AC-055, AC-056, AC-057 | REQ-018 |

REQ-001…REQ-018 are carried by ITEM-001…ITEM-018 in the same order.

## Decisions before planning

1. Q-001 (non-blocking): Which index engine backs the library index — SwiftData as the PRD suggests, or a small own index file? Recommendation: start with SwiftData behind a protocol; if it cannot be exercised headlessly in `swift test` without an app container, switch to a JSON/SQLite index behind the same protocol in the plan's first task. Trade-off: SwiftData is PRD-aligned but adds test friction; an own index is trivially testable but is throwaway code if the 10,000-item benchmark fails.
2. Q-002 (non-blocking): How do the three `openrouter/auto*` router models appear in this slice? Recommendation: list them non-selectable with a "only chat/responses in this release" note, because they have no `images` surface. Trade-off: hiding them keeps the list at 65 generatable models but looks like missing data.
3. Q-003 (non-blocking): Which settings are in scope now? Recommendation: library root, default model, default surface (`images` fixed), streaming on/off, hide inactive fields, show uncertain fields, appearance — and nothing price- or telemetry-related until FEAT-008. Trade-off: a settings screen that later grows is cheap; a speculative one is wasted work.
4. Q-004 (non-blocking): Are `allowlist_only`/`inferred_type`/`surface_unverified` fields hidden by default (PRD D-5)? Recommendation: yes, hidden behind "Vis usikre felter", which changes the default rendered field count for some endpoints — so AC-016's parity test must run with all fields shown, and the counting rule must be stated in the test name. Trade-off: honesty versus a shorter default form.
5. Q-005 (non-blocking): What counts as "compatible type" when keeping values across endpoints (AC-022)? Recommendation: same effective JSON type after nullable-stripping, or both `string` where one is `string` with `enum` — anything narrower is "not supported". Trade-off: a stricter rule drops more values but never sends a wrong-typed value.
6. Q-006 (non-blocking): How is mask alpha detected? Recommendation: via ImageIO `CGImageAlphaInfo` for PNG/JPEG/HEIC; for JPEG always report "no alpha" so the explanation is concrete. Trade-off: an alpha check that reads pixels is slower but exact; metadata inspection is enough for PNG.
7. Q-007 (non-blocking): `model` value and auto-routing semantics. Recommendation: write `model` from `scope.modelId`, which equals the catalog's `model` parameter `const` in every inspected endpoint, and treat auto-routing in this slice as "explicit pin only, otherwise warn and send only declared parameters". Trade-off: auto-routing is not truly planned against live routes, which the PRD itself defers.
8. Q-008 (non-blocking): Is automatic retry part of this slice (PRD puts retries in FEAT-012)? Recommendation: no automatic retry; one manual "try again" action, so a 429/5xx is visible rather than hidden. Trade-off: fewer surprises, slightly more clicks.
9. Q-009 (non-blocking): Are received partial images kept after cancel (PRD "bevares i jobbet")? Recommendation: keep them in memory and in the job record, but do not write files for them in this slice. Trade-off: writing them would need a sidecar with a partial marker and would blur dedupe.
10. Q-010 (non-blocking): Are embedded container metadata and thumbnails in this slice? Recommendation: no — sidecar only (explicitly limited by the run's scope decision), revisit when FEAT-016 needs self-describing files. Trade-off: a moved image loses its metadata until the sidecar is found again.

- ASSUMPTION: Delivery scope is PRD-FEAT-001…007 only; FEAT-008…016 and the `chatCompletions`/`responses` surfaces are out of scope for this run (scope decision supplied with the request).
- ASSUMPTION: The repository layout above is the assumed layout; the plan may rename targets inside it but must keep core logic in library targets with tests and the UI in the macOS SwiftUI executable.
- ASSUMPTION: No git repository exists, so no branch, commit, history or CI requirement applies to this run; `git init` is optional and not an acceptance criterion.
- ASSUMPTION: The bundled catalog is a byte-identical copy of the repo-root `openrouter-image-ui-catalog.json`; `develop/PRD.md` is read as input and never modified.
- ASSUMPTION: All network tests use injected transports and synthetic SSE fragments; no test calls OpenRouter, needs a key, or spends money (PRD C-15).
- ASSUMPTION: Keychain behaviour is verified through an injected store in unit tests; the real `SecItem*` path is verified by the manual procedure, since a headless test runner cannot guarantee an unlocked login keychain.
- ASSUMPTION: UI-only criteria (keyboard/VoiceOver/contrast, panel layout) are satisfied by a written manual test procedure plus compilation of the app target; no snapshot-image tooling is introduced in this run.
- ASSUMPTION: SwiftUI `@Observable` state and Swift 6 strict concurrency are used as the PRD states; no third-party packages are added.
- ASSUMPTION: The PRD's Danish UI copy is followed, with catalog labels used verbatim; new app strings are Danish and go through localisable keys.
- ASSUMPTION: `usage.cost` is recorded whenever the provider returns it, and its absence is recorded as "unknown", never as 0 — even though budget enforcement itself is out of scope.
- ASSUMPTION: `meta/muse-image` and the three `openrouter/auto*` routers stay in the model list with explicit unavailable states, so the picker still shows all 68 models.
- ASSUMPTION: No solution baseline exists for this repository (UNKNOWN: no solution baseline); all repository and catalog facts above were measured directly from the working directory on 2026-11-11.

### Risks and conflicts
- RISK-001 The PRD's AC-1.2 expects exactly 17 parameters for the first `images` endpoint of `openai/gpt-image-2.6-sunburst`, while the catalog lists 24 (`model`, `prompt`, `user`, `session_id`, `trace`, `aspect_ratio`, `output_format`, `quality`, `background`, `n`, `input_references`, `output_compression`, `stream`, `frame_count`, `frame_duration_ms`, `markup`, `size`, `allow_fallbacks`, `ignore`, `only`, `order`, `sort`, `moderation`, `complexity`). Sources: `develop/PRD.md` AC-1.2 versus `openrouter-image-ui-catalog.json`. Resolution: catalog parity wins (PRD O-1); AC-016 asserts 24 and the PRD text needs correcting.
- RISK-002 The PRD's AC-4.1 expects a body identical to `requestExamples[0].body` for a fixture that does not set `provider.options.openai.complexity`, but that example body contains `provider.options.openai: {complexity: "high"}`. Sources: `develop/PRD.md` AC-4.1 versus `.requestExamples[0]`. Resolution: AC-038's fixture sets `complexity` to "high"; otherwise the comparison would be impossible without dropping a provider option.
- RISK-003 PRD-FEAT-004 says `model` is always set to `scope.modelId` while its own pseudocode uses the endpoint's model id, and the catalog also exposes `model` as a required parameter with a `const`. Sources: PRD-FEAT-004 text, Bilag B pseudocode, catalog `parameters[].key == "model"`. Resolution: all three agree in the inspected endpoints (`scope.modelId` == `const`); Q-007 fixes the rule and the builder asserts the two agree.
- RISK-004 AC-4.2 forbids keys not present in the endpoint's `parameters` "except `model` and `stream`", yet both are catalog parameters on the inspected endpoints, so the exception is unnecessary and could mask a bug. Resolution: AC-036 states the stricter rule (no synthetic keys at all) and treats `model`/`stream` as ordinary parameters that must exist in the catalog.
- RISK-005 Field-count parity (AC-016) depends on display settings: hiding inactive fields and hiding uncertain evidence changes rendered counts. Resolution: the parity test runs with all fields and all evidence levels visible, and the counting rule is part of the test name; Q-004 records the default-visibility choice.
- RISK-006 The index engine is unresolved (PRD D-1, Q-001); SwiftData may be awkward to exercise headlessly, which would make AC-051/AC-053 unimplementable as written. Resolution: keep the index behind a protocol and make the acceptance criteria storage-agnostic; the plan must resolve Q-001 before the library index task.
- RISK-007 App Sandbox, security-scoped bookmarks, ATS allowlisting and notarisation cannot be verified in this environment (no signing identity, no signed app). Resolution: declare entitlements in the app target, put all writes behind a root-confined store tested with plain paths, and record sandbox verification as manual and deferred; AC-050 covers only the root-confinement logic.
- RISK-008 The PRD assumes a live catalog refresh path whose upstream response shapes are not part of this repository, so mapping may drift. Resolution: refresh mapping is tested against recorded fixtures; a mapping or `schemaVersion` mismatch must surface an error and keep the bundled catalog (AC-010, AC-011).
- RISK-009 Performance criteria (NFR-001) may not be reproducible on CI hardware, producing flaky tests. Resolution: report measured values and use generous thresholds for pass/fail, with the PRD numbers validated manually on the development machine.
- RISK-010 Two delivered requirements compete for the same effort: full 13-control rendering plus the strict validator is the largest part of the slice, while the library and generation features are what make it usable. Sources: PRD phase 2 estimate (2.5 weeks) versus phase 3 (2.5 weeks). Resolution: the work-item order above front-loads the parameter engine and keeps generation/library as separable items, so a partial delivery still yields a correct request builder and preview.

## Next action

Run `/lc-plan .lc/developer/netsi-image-openrouter-parameter-engine/` now; the spec is Ready with no blocking questions. The plan should turn ITEM-001…ITEM-018 into ordered tasks mapped to REQ/AC ids, resolve Q-001 (index engine) before the library task, and keep the parity and fixture tests (AC-016, AC-038) as the regression spine that catches the RISK-001/RISK-002 disagreements.

Status: Ready
