Agent: lc-plan
Mode: Plan
Status: Ready
Confidence: Medium
Artifact mode: brief
Artifact folder: .lc/developer/netsi-image-openrouter-parameter-engine/

## TL;DR
<!-- lc-tldr -->

- One SwiftPM package (tools 6.4, `.macOS(.v27)`): 8 library targets plus a thin SwiftUI executable, all logic headless-testable; a throwaway probe package on this machine built and tested the same shape in 6.5 s.
- 20 work items and 21 ordered tasks: scaffold → catalog (tolerant model, lazy store, guarded refresh, filters) → parameter engine (tri-state draft, `FieldPlan`, 13 widgets, validator, conditions, constraints, run state) → request builder and preview → generation with SSE → library files and index → Keychain → UI shell → verification pass.
- The catalog is the only source of truth: tests walk all 69 `images` endpoints (1,154 entries) for field parity and all 1,907 entries for the 13 control-kind totals; `requestExamples[0]`/`[1]` are the request-body regression spine.
- Q-001 (index engine) is resolved in-plan: a derived JSON index behind a `LibraryIndex` protocol instead of SwiftData, because the sidecar is authoritative and a headless test cannot rely on an app container; AC-051/AC-053 stay satisfied.
- Two conflicts remain open with the PRD text (AC-1.2's 17 vs 24 fields; AC-4.1's example body) and are resolved in favour of the catalog, as the spec records; verification of sandbox, signing and VoiceOver stays manual.

## Approach and delivery order

**Chosen approach.** One SwiftPM package with a strict dependency direction and no third-party packages (NFR-002):

```text
CoreSupport  →  CatalogCore  →  ParameterEngine  →  RequestKit  →  GenerationKit
    ↑                ↑                                    ↓            ↓
SettingsKit ────────┴────────  LibraryKit ───────────────┴────────────┘
                                   ↓
                        NetsiImageUI (SwiftUI)  →  NetsiImageApp (executable)
```

`CoreSupport` holds the shared, dependency-free primitives the rest depends on: `JSONValue`, `PathKey`, an injectable `HTTPTransport`/`Clock`/`DebugLog`, atomic file writes and path confinement, and an `ImageProbe` (ImageIO) that `ParameterEngine` can use for AC-032 without importing library code. This is one target more than the spec's layout; it removes the alternative — putting the transport in `CatalogCore` and making the request layer depend on the catalog for networking reasons. Trade-off recorded under Decisions.

**Why.** The spec's order already front-loads the risky, high-value part (the parameter engine) and leaves generation and library as separable items, so a partial delivery still yields a correct request builder and JSON preview. The plan adds one structural refinement: `FieldPlan` — a pure, headless function from `(Endpoint, AppSettings)` to the ordered field list, widget kind, section, evidence bucket and accessibility label. SwiftUI renders that plan and nothing else, so AC-016 and AC-017 are asserted on data instead of on rendered pixels, which a headless `swift test` cannot inspect.

**Execution order.** T-01 scaffold → T-02 catalog model → T-03 store → T-04 refresh → T-05 picker and filters → T-06 tri-state draft → T-07 `FieldPlan` and the 13 widgets → T-08 validator → T-09 conditions → T-10 value/field constraints → T-11 run state → T-12 builder → T-13 preview → T-14 client and jobs → T-15 SSE → T-16 library files → T-17 index → T-18 settings and Keychain → T-19 UI shell → T-20 verification. T-06 (ITEM-007) is pulled ahead of T-07 (ITEM-006) because the plan's "changed" counts, inactive evaluation and dropped-value confirmation all read the draft.

**Parallel lanes after T-02** (bounded to 2–3 lanes, `coderParallelism: bounded`):

| Lane | Tasks | Starts after |
|---|---|---|
| A catalog | T-03 → T-04 → T-05 | T-02 |
| B engine | T-06 → T-07 → T-08/T-09/T-10 → T-11 | T-02 |
| C request and generation | T-12 → T-13 → T-14 → T-15 | T-11 |
| D library | T-16 → T-17 | T-02 (needs `CoreSupport` only) |
| E settings | T-18 | T-02 |
| F UI | T-19 | T-12, T-14, T-18 |

Lane D and E are independent of the engine and can run alongside B; T-19 and T-20 are the only serial join points.

## Decisions and trade-offs

**D-1 Index engine (resolves Q-001).** Options: (a) SwiftData behind a protocol, PRD-aligned but needs a container the test runner may not provide; (b) own JSON index file, rebuilt from sidecars; (c) SQLite via the system `libsqlite3`, fast but C interop plus a schema to migrate. **Chosen: (b)** — `Library/../index.json` at the library root, loaded into memory, rebuilt from sidecars, searched in process. AC-051 ("delete the index, rebuild, everything returns") and AC-053 (300 ms at 10,000 items) are met by construction, the sidecar stays authoritative (PRD 5.3) and the whole path is deterministic offline. Cost: a full rewrite on each save, acceptable at 10k items and reversible if the benchmark fails, because everything sits behind `LibraryIndex`.

**D-2 Parity is asserted on `FieldPlan`, not on views.** The 13 control kinds map through one pure `ControlMapping` table consumed by both the parity test and the SwiftUI widget factory. Trade-off: the factory's switch must stay exhaustive (compiler-enforced with an `unknown` case that falls back to the JSON editor), and "the right widget is on screen" remains a manual check.

**D-3 Control-kind totals span all surfaces.** Measured directly: the 69 `images` endpoints carry 1,154 entries (select 240, text 165, json-editor 167, number 128, multi-select 138, checkbox 87, repeater 14, the rest as in the spec), while the spec's AC-017 totals (select 357, json-editor 410, …) cover all 1,907 entries across three surfaces. AC-016 therefore walks `images` only and AC-017 walks every surface, and the test names state that scope.

**D-4 Lazy catalog.** Parse the 2.4 MB file once into a `JSONValue` tree, expose the summary from `coverage` plus model ids, and convert one model to typed `CatalogModel`/`ParameterSpec` on first access, counting conversions. AC-007 is asserted on that counter (summary access ⇒ 0 parameter decodes; first model access ⇒ that model only), not on wall-clock alone. Cost: the JSON tree costs more memory than typed structs; the alternative — slicing raw bytes per model — saves memory but adds a hand-rolled scanner.

**D-5 Platform.** `// swift-tools-version: 6.4` with `platforms: [.macOS(.v27)]`, verified to compile here; `.v27` needs the 6.4 manifest, so a lower tools version would force the string form `.macOS("27.0")`.

**D-6 Non-blocking spec decisions Q-002…Q-010** are adopted as the spec recommended them, each with its consequence recorded: routers listed but non-selectable (Q-002); settings limited to root, default model, streaming, hide-inactive, show-uncertain, appearance (Q-003); uncertain evidence hidden by default behind "Vis usikre felter", with parity tests running all-visible (Q-004); type compatibility = equal nullable-stripped type, with `string` and `string`+`enum` compatible (Q-005); alpha via `CGImageAlphaInfo`, JPEG always "no alpha" (Q-006); `model` from `scope.modelId` with a builder assertion against the endpoint's `const` (Q-007); no automatic retry, one manual retry (Q-008); partial images kept in memory only (Q-009); no embedded container metadata (Q-010).

## Work items

### ITEM-001 (aliases: REQ-001, AC-001, AC-002, AC-003, T-01)
- Affected areas: `Package.swift`; `Sources/CoreSupport/`, `Sources/CatalogCore/` (+ `Resources/openrouter-image-ui-catalog.json`), `Sources/ParameterEngine/`, `Sources/RequestKit/`, `Sources/GenerationKit/`, `Sources/LibraryKit/`, `Sources/SettingsKit/`, `Sources/NetsiImageUI/`, `Sources/NetsiImageApp/NetsiImageApp.swift`; `Tests/*`; repo root `openrouter-image-ui-catalog.json` (read-only).
- Implementation: create the manifest (tools 6.4, `.macOS(.v27)`, Swift 6 language mode) with the 8 library targets, the executable and one test target per logic library; `cp` the repo-root catalog into `CatalogCore`'s resources with `.copy` so `Bundle.module` serves it; add a minimal `@main` app in `NetsiImageApp.swift` (not `main.swift`, which conflicts with top-level code) and a placeholder SwiftUI root view.
- Validation: `swift build` and `swift test` succeed from a clean state with network disabled (AC-001); a test enumerates the target list and asserts every logic library has a test target (AC-002); a SHA-256 test compares `Bundle.module`'s bytes with the repo-root file, located from `#filePath` with a `NETSI_CATALOG_ROOT` override (AC-003). A throwaway probe on this machine confirmed this exact shape builds headlessly, renders SwiftUI in an executable target and resolves `Bundle.module` resources under `swift test`.

### ITEM-002 (aliases: REQ-002, AC-004, AC-005, AC-006, T-02)
- Affected areas: `CoreSupport/JSONValue.swift` (`null`/`bool`/`number(Decimal)`/`string`/`array`/`object`, `Sendable`, lossless `Codable`), `CoreSupport/PathKey.swift`; `CatalogCore/Catalog.swift`, `Model.swift`, `Endpoint.swift`, `ParameterSpec.swift`, `ControlKind.swift`, `EvidenceKind.swift`.
- Implementation: tolerant models. `schema` and `$defs` are held as `JSONValue` so free-form schema keywords survive; every declared field decodes from measured shapes (top-level `schemaVersion`, `generatedAt`, `baseUrl`, `language`, `coverage`, `sources`, `ui`, `apiSurfaces`, `requestExamples`, `models`, `$defs`; endpoint `providerPin`, `supportsStreaming`, `pricing`, `parameters`; parameter `key`, `label`, `path`, `scope`, `schema`, `control`, `required`, `evidence`, `source`, `capability`, `activeWhen`, `valueConstraints`, `constraints`, `suggestedValues`, `group`, `note`, `allowedBy`). `ControlKind` and `EvidenceKind` decode unknown raw values into `.unknown(…)` instead of throwing.
- Validation: decode counts 68 models, 121 endpoints, 1,907 entries and the schema version, with unknown keys present in fixtures decoding cleanly (AC-004); decode → encode → decode equality per declared field, plus a `$ref` walk from every model schema into `$defs` reporting 0 dangling and 0 non-local refs (AC-005); the path `["provider","options","google-ai-studio/global","cachedContent"]` decodes to exactly 4 components with the third kept whole (AC-006) — measured: 16 image-endpoint paths contain a slash-bearing segment.

### ITEM-003 (aliases: REQ-003, AC-007, AC-008, AC-009, T-03)
- Affected areas: `CatalogCore/CatalogStore.swift` (actor over D-4), `CatalogCore/CatalogSummary.swift`, `CatalogCore/LazyModelDecoder.swift`.
- Implementation: single parse into `JSONValue`, summary computed without touching parameters, per-model typed conversion cached behind the actor with a counter injected for tests; the store is immutable after load and replaced atomically.
- Validation: counter assertions that summary access performs 0 parameter decodes and first model access decodes one model (AC-007); summary equals generatedAt `2026-11-11T10:48:18Z`, 68 models, 17 provider routes, 65 models with an `images` surface, cross-checked against `coverage` (AC-008); with a transport that always throws, browsing, `FieldPlan` construction, validation and preview all still succeed (AC-009).

### ITEM-004 (aliases: REQ-004, AC-010, AC-011, AC-012, T-04)
- Affected areas: `CatalogCore/Refresh/CatalogRefreshClient.swift`, `RefreshMapper.swift`, `SchemaVersionGuard.swift`, `SnapshotCache.swift`; `Tests/CatalogCoreTests/Fixtures/refresh/*.json`.
- Implementation: fetch the four catalog `sources` through `HTTPTransport`, map to the catalog shape in one place, reject any `schemaVersion` other than the bundled one, and swap the store's snapshot atomically; cache under `~/Library/Application Support/dk.netsi.image/catalog/` with a per-section source manifest; every failure is written to `DebugLog` with the failing URL and keeps the old snapshot.
- Validation: a mapped result with a different schema version is rejected and named, snapshot unchanged (AC-010); HTTP error, malformed JSON and schema break each keep `generatedAt` and produce a message naming the source URL plus a debug-log entry (AC-011); a successful refresh replaces the snapshot, changes counts, appears in the picker without restart and is reused on the next launch (AC-012). Fixtures are recorded from one manual public capture of the `sources` URLs (no key needed) and committed, so the suite stays offline.

### ITEM-005 (aliases: REQ-005, AC-013, AC-014, AC-015, T-05)
- Affected areas: `CatalogCore/ModelFilter.swift`, `CatalogCore/EndpointResolver.swift`; picker rows in `NetsiImageUI/ModelPicker.swift`.
- Implementation: pure filter composition (text over id/name, publisher, surface, provider), a row DTO carrying publisher, surfaces, provider, streaming badge and an availability state (`generatable`, `noImageEndpoint`, `chatOnly`), and an endpoint resolver that returns exactly one `images` endpoint or an explicit choice when several share a provider.
- Validation: 68 rows with the measured states — `meta/muse-image` as "no public image endpoint", `openrouter/auto*` as not generatable (AC-013); filters compose and survive a snapshot swap, a non-matching model disappears without clearing filters (AC-014); sunburst resolves to `openai/gpt-image-2.6-sunburst@openai` and its 24 parameters become the active form (AC-015).

### ITEM-006 (aliases: REQ-006, AC-016, AC-017, AC-018, AC-019, AC-020, T-07)
- Affected areas: `ParameterEngine/FieldPlan.swift`, `ControlMapping.swift`, `EvidenceBucket.swift`, `FieldAccessibilityLabel.swift`; `NetsiImageUI/ParameterPanel.swift`, `Widgets/*.swift` (13 widgets + factory), `EvidenceBadge.swift`.
- Implementation: `FieldPlan.make(endpoint:settings:)` produces ordered sections (ungrouped first, `required` first then catalog order; "Routing" 345 and "Provider-options" 130 with field and changed counts), each field carrying widget kind, evidence bucket, suggested values, note and a generated a11y label; search matches `key`, `label` and `path` and expands the hit's section; the widget factory renders one widget per `WidgetKind` with an exhaustive switch and an `unknown` fallback to the JSON editor plus a warning.
- Validation: parity over all 69 `images` endpoints — 1,154/1,154 by path, 24 for sunburst, no endpoint empty, run with all evidence levels visible (AC-016); kind totals over all 1,907 entries equal the catalog's own numbers, and an injected unknown `control` renders as a JSON editor (AC-017); enum-vs-capability source, numeric rejection with effective min/max, and the 16/17-item `image-list` refusal (AC-018); section counts, badge buckets and search-driven expansion (AC-019); suggestions never restrict input and labels read label + type + value (AC-020, with the VoiceOver walkthrough in ITEM-020's procedure).

### ITEM-007 (aliases: REQ-007, AC-021, AC-022, T-06)
- Affected areas: `ParameterEngine/ParameterDraft.swift`, `TypeCompatibility.swift`, `EndpointSwitchPlan.swift`.
- Implementation: `PathKey`-keyed draft with tri-state `ParameterValue.unset`/`.value(JSONValue)`, `set`/`reset`/`value(for:)`, and an applied-parameters accessor returning only set, active paths; switching endpoints produces a plan listing kept values and dropped paths with reasons, which the UI surfaces for explicit confirmation.
- Validation: untouched field is `unset` and absent from the preview body; set then reset returns to `unset` and removes the key (AC-021); switching keeps same-or-compatible-type paths, lists each dropped path with the Q-005 reason, and removes them only after confirmation (AC-022).

### ITEM-008 (aliases: REQ-008, AC-023, AC-024, AC-025, AC-026, T-08)
- Affected areas: `ParameterEngine/Validation/JSONSchemaValidator.swift`, `SchemaRegistry.swift`, `Issue.swift` (`path`, `severity`, `message`, `expected`, `actual`, `fixSuggestion`).
- Implementation: a small validator over `JSONValue` supporting `type` (incl. nullable arrays), `enum`, `const`, `minimum`/`maximum`, `minLength`/`maxLength`, `pattern`, `minItems`/`maxItems`, `required`, `properties`, `items`, `anyOf`/`oneOf`/`allOf` and local `$ref` into `$defs`; unknown keywords ignored and recorded in `DebugLog`; endpoint `capability` bounds override schema bounds before validation runs.
- Validation: keyword coverage table with one passing and one failing value each (AC-023); `ContentPartImage` accepts `{"type":"image_url","image_url":{"url":…}}` and rejects a missing `image_url.url` or a different `type` (AC-024); `["integer","null"]` accepts empty as null and stays optional, wrong type or bound reports path/expected/actual (AC-025); `n` is bounded 1–10 by `capability` (AC-026).

### ITEM-009 (aliases: REQ-009, AC-027, AC-028, AC-029, T-09)
- Affected areas: `ParameterEngine/Conditions/ConditionEvaluator.swift`; inactive handling in `FieldPlan` and `RequestKit`'s not-sent list.
- Implementation: evaluate `equals`, `in`, `minItems` against the draft with `PathKey` lookup; unknown operator ⇒ field active plus a logged warning; inactive fields hidden by default with a per-section count, or disabled when "show inactive fields" is on, and always excluded from the body and reported in the preview's "not sent" list.
- Validation: `frame_count` inactive unless `output_format` is `gif` on sunburst (AC-027); all 10 `in` and 2 `minItems` entries behave, unknown operator stays active with a warning (AC-028); hide/disable switch and the "not sent" list (AC-029).

### ITEM-010 (aliases: REQ-010, AC-030, AC-031, AC-032, T-10)
- Affected areas: `ParameterEngine/Constraints/ValueConstraintEvaluator.swift`, `FieldConstraintEvaluator.swift`; `CoreSupport/ImageProbe.swift` (ImageIO: dimensions, alpha, media type).
- Implementation: option-level unavailability from `valueConstraints` with the explanation shown in the picker; field-level rules `mediaType`, `transparent`, `matchDimensionsOfReference`, `pixelSize` (`step` 16, `maxAspectRatio` 3) evaluated against probed input files; each violated rule yields its own explanation and, where possible, a one-field fix.
- Validation: jpeg + transparent blocked with "transparent requires png or webp" and a one-click switch to png (AC-030); all 13 `valueConstraints` entries mark the governed option unavailable with a reason (AC-031); mask media type, alpha and dimension mismatches produce one issue per rule and `size` enforces step and aspect ratio (AC-032).

### ITEM-011 (aliases: REQ-011, AC-033, AC-034, AC-035, T-11)
- Affected areas: `ParameterEngine/ValidationEngine.swift`, `RunState.swift`; run bar in `NetsiImageUI/RunBar.swift`.
- Implementation: one engine that runs schema, capability, `activeWhen`, `valueConstraints` and `constraints` in a fixed order over a draft and returns `[Issue]` plus a derived `RunState` (`canRun`, blocking count, first issue); warnings never block; the UI binds the button title to the count and scrolls to the first issue.
- Validation: every issue carries path, severity, message and optional fix (AC-033); run is disabled with "3 felter mangler opmærksomhed", fixes one issue and leaves others untouched (AC-034, engine part automated, scroll part manual); a synthesized 200-field validation reports a measured value under 20 ms with the number printed into the test output and no silent skip (AC-035).

### ITEM-012 (aliases: REQ-012, AC-036, AC-037, AC-038, AC-039, T-12)
- Affected areas: `RequestKit/ImagesRequestBuilder.swift`, `ProviderRoutingPlanner.swift`, `RequestError.swift`.
- Implementation: apply each active, set `path` one component per key; merge `providerPin` as `{only:[slug], allow_fallbacks:false}` and place provider options under `provider.options.<slug>`; set `stream: true` only when enabled and declared; throw `unsupportedSurface` for anything but `images` and `blockingIssues` carrying the issues — never a partial body.
- Validation: key set equals endpoint parameters, with the 4-component path nesting exactly (AC-036); routing/pin/options/stream rules, including the auto-routing warning (AC-037); order-insensitive equality with `requestExamples[0]` and `[1]` using the fixtures the spec fixes (AC-038); unsupported surface and blocking-issue refusal (AC-039). A test asserts `scope.modelId` equals the endpoint's `model` `const` for all 69 endpoints.

### ITEM-013 (aliases: REQ-013, AC-040, AC-041, T-13)
- Affected areas: `RequestKit/JSONPreview.swift`, `Redaction.swift`; preview panel in `NetsiImageUI/JSONPreviewPanel.swift`.
- Implementation: deterministic pretty-printed JSON of the exact bytes handed to the client, a changed-fields-only mode, copy-as-is, and base64 redaction to `"<fil: navn, 1,2 MB>"` applied to the preview only.
- Validation: preview equals the sent body and updates within 50 ms of a field change (measured, reported) (AC-040); redacted placeholder carries file name and size while the client payload still contains the full base64, asserted by comparing both (AC-041).

### ITEM-014 (aliases: REQ-014, AC-042, AC-043, AC-044, T-14)
- Affected areas: `GenerationKit/OpenRouterClient.swift`, `GenerationJob.swift`, `JobError.swift`, `GenerationCoordinator.swift`.
- Implementation: `POST /api/v1/images` through `HTTPTransport` with bearer, `HTTP-Referer` and `X-Title`; decode `data[*].b64_json`/`media_type` and store `usage.cost` (absent ⇒ "unknown", never 0); map 401/402/429(+`retry-after`)/5xx/network to actionable Danish states with the raw body behind a details disclosure; a UUID per job, idempotent submission, cancellation that stops traffic within 1 s.
- Validation: 200 response yields one result per image with the right media type and stored cost (AC-042); a table-driven error test per status with `retry-after` formatting, plus a scan asserting no message or dump contains the key (AC-043); cancel leaves `cancelled` and resubmitting an active id makes no second request (AC-044).

### ITEM-015 (aliases: REQ-015, AC-045, AC-046, AC-047, T-15)
- Affected areas: `RequestKit/SSEParser.swift` (incremental, byte-level), `GenerationKit/GenerationEvent.swift`, streaming branch in the coordinator.
- Implementation: an incremental parser fed arbitrary chunks, emitting events plus a terminal `[DONE]`; map `image_generation.partial_image`, `image_generation.completed` (final image + cost) and `error` (with request id).
- Validation: synthetic fragments covering split events, several events per chunk, CRLF/LF, comments and `[DONE]` (AC-045); partial before final, completed yields final + cost, error yields the provider request id (AC-046); `stream: true` only for the 10 measured streaming endpoints and elapsed time shown without invented estimates (AC-047).

### ITEM-016 (aliases: REQ-016, AC-048, AC-049, AC-050, T-16)
- Affected areas: `LibraryKit/ImageWriter.swift`, `Sidecar.swift`, `LibraryPaths.swift`; confinement in `CoreSupport/PathConfinement.swift`.
- Implementation: write `Library/yyyy/MM/dd/yyyyMMdd-HHmmss-<model-slug>-<jobid-6>.<ext>` plus a `formatVersion: 1` `.json` sidecar with the measured field set, atomic temp+rename, deterministic collision suffix, and root confinement checked before any byte is written.
- Validation: file and sidecar names and locations, collision suffix instead of overwrite (AC-048); every declared sidecar field present with `PathKey`-notated parameters and full request body, and re-read/re-write preserves unknown extra fields (AC-049); atomicity via an injected failing write, plus a traversal-style relative path refused before writing (AC-050).

### ITEM-017 (aliases: REQ-017, AC-051, AC-052, AC-053, T-17)
- Affected areas: `LibraryKit/LibraryIndex.swift` (protocol), `JSONIndex.swift` (D-1), `IndexRebuilder.swift`, `LibrarySearch.swift`.
- Implementation: index entries derived from sidecars (model, prompt text, date, cost, hash, file path), rebuilt by walking the root, searchable by prompt words across name and content, with `missing` state and relink/remove per item.
- Validation: delete the index, relaunch, rebuild restores every item of a ≥25-item fixture with matching fields (AC-051); a moved image is reported `missing`, relink or removal leaves others intact (AC-052); a 10,000-item fixture returns prompt-word matches with a reported measured duration under 300 ms (AC-053).

### ITEM-018 (aliases: REQ-018, AC-054, AC-055, AC-056, AC-057, T-18)
- Affected areas: `SettingsKit/KeychainStore.swift`, `KeyState.swift`, `AppSettings.swift`.
- Implementation: generic-password item, service `dk.netsi.image.openrouter`, account `api-key`, `kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly`; masked suffix in the model; "Test key" as one cheap authorised request; deleting requires confirmation and leaves everything but generation usable; locked/denied Keychain degrades to guidance.
- Validation: stored item's attributes read back and a scan of `UserDefaults`, sidecars, library folder and log output finds no key (AC-054); a rejected key gives a Danish error and is not stored (AC-055); deletion confirmation keeps catalog/form/preview/validation/library usable and disables generation with an explanation (AC-056); injected Keychain failures (`errSecInteractionNotAllowed`, `errSecAuthFailed`) are covered by unit tests (AC-057).

### ITEM-019 (aliases: REQ-005, REQ-006, REQ-011, REQ-013, REQ-018, AC-002, AC-019, AC-020, AC-034, AC-040, AC-056, T-19)
- Affected areas: `NetsiImageUI/AppShell.swift`, `PromptPane.swift`, `ResultPane.swift`, `LibraryList.swift`, `SettingsPane.swift`, `Commands.swift`, `GenerationViewModel.swift` (`@Observable`, `@MainActor`); `NetsiImageApp/NetsiImageApp.swift`.
- Implementation: the three-panel layout with collapsible side panels, bottom run bar, model picker, parameter inspector, preview sheet (⌘⇧J), generation result with partial-image display, library list, settings pane and keyboard commands (⌘R, ⌘⇧J, ⌘F, ⌥↑/⌥↓). The UI talks only to view models over service protocols — no HTTP and no filesystem calls in views (NFR-007, PRD 4.2).
- Validation: the app compiles and launches; a written manual procedure covers the parts a headless runner cannot assert — keyboard walkthrough, VoiceOver labels, the run-button scroll-to-first-issue, panel collapse and the read-only state after key deletion (AC-020, AC-034, AC-056).

### ITEM-020 (aliases: REQ-001, AC-001, AC-003, AC-020, AC-035, AC-040, AC-053, T-20)
- Affected areas: `docs/manual-test-procedure.md`, `docs/runbook.md`, `Tests/IntegrationTests/` (parity and perf report), `.gitignore` only if a git repository is created.
- Implementation: one verification pass that runs the full suite offline, records the measured performance values (200-field validation, 10k search, preview latency, decode timings), regenerates the catalog SHA, greps the library fixture folder and log output for key-shaped strings, and documents the manual procedures and how to run everything.
- Validation: `swift build`/`swift test` clean with network disabled; the parity and fixture tests pass; every AC in the spec's Traceability table has at least one automated test or one numbered manual step, listed in the runbook (AC-001, AC-003, AC-020, AC-035, AC-040, AC-053).

## Test strategy and quality gates

- **Parity spine.** Two catalog walkers: `images`-only (AC-016) and all-surface control-kind totals (AC-017). Both read the bundled catalog, so a wrong bundle SHA is caught first by AC-003.
- **Fixture spine.** `requestExamples[0]` and `[1]` compared order-insensitively against `JSONValue` equality; the spec's RISK-001/RISK-002 corrections (24 sunburst fields, `complexity: "high"` in fixture 1) are asserted, not commented.
- **Injection everywhere** (NFR-010): transport, clock, Keychain, file writer and image probe are protocols; the whole suite runs with the network off and never prompts.
- **Measured, not skipped.** Performance tests print the measured duration into the test output and fail on the threshold in the same test; no `XCTSkip`-style escape.
- **Offline acceptance.** AC-009, AC-011 and the whole suite run under a transport that throws.
- **Manual procedure** for VoiceOver, contrast, Reduce Motion, run-bar scroll behaviour, panel layout and the real `SecItem*` path.
- **Gates before code is called done:** `swift build` and `swift test` clean, no new warnings, no third-party dependency added, no key-shaped string in the tree, every AC mapped.

## Risks and open questions

- **High — AC-007 is a design constraint, not just a test.** A naive `Codable` decode of `models: [CatalogModel]` would decode every parameter list at load and fail AC-007. Mitigation: the lazy design in D-4 with an instrumented counter, implemented in T-03 before anything reads the catalog.
- **High — refresh mapping has no known upstream shape.** `.sources` names four URLs but not their response bodies. Mitigation: one manual public capture becomes a committed fixture, the mapper is the only place that knows upstream shapes, and the `schemaVersion` guard plus "keep the last good snapshot" behaviour is tested first (T-04).
- **High — two surface scopes for counts.** AC-016 (1,154 entries) and AC-017 (1,907 entries) count different populations; a single walker would fail one of them. Mitigation: D-3 and explicit test names.
- **Medium — Q-001 deviates from the PRD's SwiftData suggestion.** Recorded as D-1; everything sits behind a protocol so the decision is reversible if AC-053 fails.
- **Medium — performance thresholds may flake on slower hardware** (NFR-001). Mitigation: generous pass/fail thresholds on measured values, with the PRD numbers validated manually on this machine and reported.
- **Medium — sandbox, security-scoped bookmarks and notarisation cannot be verified here.** Mitigation: entitlements declared, all writes behind root-confined code with plain-path tests, sandbox behaviour recorded as manual and deferred.
- **Medium — UI criteria are only partly automatable.** Mitigation: pure `FieldPlan` carries the testable parts (labels, ordering, counts); the rest is a numbered manual procedure.
- **Low — PRD text still contradicts the catalog** (RISK-001, RISK-002, RISK-003, RISK-004). Mitigation: tests assert catalog truth; correcting `develop/PRD.md` is out of scope and not done by this run.

## Assumptions

- ASSUMPTION: The feature folder is `.lc/developer/netsi-image-openrouter-parameter-engine/` as given by the invocation; no other candidate folder exists.
- ASSUMPTION: No solution baseline exists for this repository (UNKNOWN: no solution baseline), so all repository facts come from direct measurement of the working directory on 2026-11-11 and from `spec.md`.
- ASSUMPTION: Q-001 is resolved in-plan with a derived JSON index behind a `LibraryIndex` protocol (D-1), because a subagent run cannot ask the user and the sidecar-as-truth design makes the storage choice reversible.
- ASSUMPTION: Q-002…Q-010 are resolved exactly as the spec recommended them (D-6); none of them blocks a safe plan.
- ASSUMPTION: Upstream refresh response shapes are treated as UNKNOWN until one manual public capture is recorded as a fixture in T-04; until then the mapper is exercised only by that fixture.
- ASSUMPTION: Toolchain facts verified here rather than assumed — Swift 6.4.2 on macOS 27.2, `swift-tools-version: 6.4` with `.macOS(.v27)` compiles, a SwiftUI executable target builds and runs under `swift build`, `Bundle.module` resources resolve under `swift test`, and Swift Testing is available.
- ASSUMPTION: A `CoreSupport` target is added to the spec's layout to hold shared primitives, keeping the dependency direction one-way; the spec explicitly allows splitting targets inside its layout.
- ASSUMPTION: `usage.cost` is `Decimal` and an absent cost is stored as "unknown", never as 0, even though budget enforcement is out of scope.
- ASSUMPTION: The 69 `images` endpoints, 1,154 entries, 10 streaming endpoints, 12 `maxItems: 16` fields and 16 slash-bearing paths measured here are the numbers the parity and constraint tests assert.
- ASSUMPTION: UI-only criteria are satisfied by a documented manual procedure plus compilation; no snapshot-image tooling or UI test runner is introduced in this run.
- ASSUMPTION: No git repository, branch, CI workflow, signing identity or notarisation is required by this run; `git init` stays optional.

## Definition of Done

- `swift build` and `swift test` succeed from a clean checkout with network disabled; no third-party dependency; no new compiler warnings.
- All 57 acceptance criteria in `spec.md` are covered by at least one automated test or one numbered manual step, with the mapping listed in the runbook (ITEM-020).
- Parity holds over all 69 `images` endpoints (1,154/1,154 by path) and the 13 control-kind totals equal the catalog's own numbers across all 1,907 entries, with the population named in each test.
- `requestExamples[0]` and `[1]` are reproduced exactly (order-insensitively) by the builder using the spec's corrected fixtures.
- Performance values are measured and printed: 200-field validation < 20 ms, 10k-item search < 300 ms, preview update < 50 ms, one-model decode < 50 ms.
- No API key appears in `UserDefaults`, sidecars, the library folder, logs or error text; verified by test and by a grep of a generated library folder.
- Every service is injectable and every test runs offline, deterministically, without spending money or prompting for Keychain access.
- The bundled catalog is byte-identical to the repo-root file, and `develop/PRD.md` and `openrouter-image-ui-catalog.json` are unmodified.
- Danish UI strings go through localisable keys; catalog labels are used verbatim.
- The app target compiles and launches; the manual procedure for VoiceOver, keyboard, run-bar behaviour and read-only degradation is written and its steps are executable.

## Next handoff

Run `/lc-code .lc/developer/netsi-image-openrouter-parameter-engine/` and start with T-01 (ITEM-001), which must land and test green before any lane opens. Then run lanes A, B, D and E against T-02; wire T-12→T-13→T-14→T-15 before T-19; finish with T-20. Keep the parity and fixture tests in every lane's definition of done — they are the only cheap defence against RISK-001 and RISK-002.

Mindmap: skipped — install the external mindmap skill to enable it
Status: Ready
