# Netsi Image — P0-slice (katalog → parameter → request → generering → bibliotek)

Agent: lc-code
Mode: Code
Status: Ready for Tests
Confidence: High
Artifact mode: brief
Artifact folder: .lc/developer/netsi-image-openrouter-parameter-engine/

## TL;DR
<!-- lc-tldr -->

- Implemented the P0 spine as one SwiftPM package: 8 library targets plus a SwiftUI executable; `swift build` and `swift test` are clean with no third-party dependency.
- The catalog drives everything: 69 `images` endpoints render 1.154 of 1.154 parameter fields, and the 13 control kinds total exactly the catalog's 1.907 entries.
- Both `requestExamples` (`gpt-image-2.6-sunburst` and `gemini-3.1-flash-image`) are reproduced exactly, including the nested `provider.options.openai.complexity` path.
- 77 tests pass; measured: 200-field validation 1,4 ms, 10.000-item search 40,9 ms, preview render 0,06 ms.
- Named `lc-dev:lc-code-agent` was unavailable in this runtime, so the phase ran inline; the report records it under Assumptions.

## Implementation Summary

Greenfield implementation of the seven P0 features on the `images` surface. The package is
dependency-free and every service (transport, clock, Keychain, file writer, image probe) is a
protocol so the whole suite runs offline and never spends money.

- `CoreSupport` — `JSONValue` (Decimal numbers, lossless round-trip), `PathKey` (slash-bearing
  segments stay one component), `HTTPTransport`/`URLSessionTransport` with byte streaming,
  `DebugLog`, path confinement, atomic writer, ImageIO probe.
- `CatalogCore` — tolerant catalog model, lazy `CatalogStore` actor with an instrumented decode
  counter, pure `ModelFilter`, `EndpointResolver`, refresh client/mapper with a schema-version
  guard and a snapshot cache.
- `ParameterEngine` — tri-state `ParameterDraft`, endpoint switch plan, `FieldPlan` (the single
  pure source for sections, widget kinds, evidence buckets and accessibility labels), JSON Schema
  validator with local `$ref`, `activeWhen` (equals/in/minItems), `valueConstraints`, content
  `constraints`, and one `ValidationEngine` that produces issues and a run state.
- `RequestKit` — `ImagesRequestBuilder` (path-per-key nesting, provider pin, auto-routing
  warnings, stream only where supported), JSON preview with base64 redaction, incremental SSE
  parser.
- `GenerationKit` — `OpenRouterClient` (bearer, `HTTP-Referer`, `X-Title`), Danish error mapping,
  streaming events, `GenerationCoordinator` with cancellation and idempotent submission.
- `LibraryKit` — day-foldered image + `formatVersion: 1` sidecar, collision suffix, derived JSON
  index behind `LibraryIndex`, rebuild, search, trash-based removal.
- `SettingsKit` — Keychain store behind a backend protocol, masked key state, settings store.
- `NetsiImageUI` / `NetsiImageApp` — three-panel SwiftUI shell, model picker, parameter inspector
  with one widget per control kind, run bar, JSON preview sheet, library grid, settings sheet.

### Fix iteration 1

Addressed the test-phase defects without changing the architecture:

- **DEFECT-001** — `OpenRouterClient.testKey(apiKey:)` calls `GET /api/v1/key`; Settings has a
  **Test nøgle** button; success and failure are shown in the key state. Files:
  `GenerationKit.swift`, `AppModel.swift`, `SettingsPane.swift`. Validated with
  `OpenRouterClientTests.testKey`.
- **DEFECT-002** — `AppModel.refreshCatalog()` runs the refresh client, replaces the store
  snapshot, saves the snapshot cache, rebuilds the rows and re-resolves the selection; the picker
  has an **Opdater** action, and startup prefers a cached snapshot. Files: `AppModel.swift`,
  `Views.swift`. Validated with the existing `CatalogRefreshTests` plus a manual UI check.
- **DEFECT-003** — suggestions are offered where the catalog actually carries them: the 207
  `suggestedValues` all sit on `order` (ordered-multi-select), so the multi-select menu now offers
  enum options plus suggestions, and typing/other values stay free. Files: `Views.swift`.
  Validated with `RequestBuilderTests.suggestions`.
- **DEFECT-004** — "Vis første fejl" now sets `focusedPath`; the inspector scrolls to the field and
  highlights it. Files: `Views.swift`, `AppModel.swift`.
- **DEFECT-005** — the preview sheet lists the paths that are not sent (`RequestBuildResult.notSent`).
  Files: `AppModel.swift`, `Views.swift`.
- **DEFECT-006** — `ImagesRequestBuilder.build(surface:…)` throws `unsupportedSurface` for anything
  but `images`. Files: `ImagesRequestBuilder.swift`. Validated with
  `RequestBuilderTests.unsupportedSurface`.
- **DEFECT-007** — picker rows show the available surfaces. Files: `Views.swift`.

Also fixed during the test phase: decimal-preserving JSON encoding (`JSONValue`) and CRLF-safe SSE
splitting (`.newlines`), both with regression tests.

### Fix iteration 2

- **DEFECT-009 (High)** — `GenerationCoordinator` now runs each job in its own work task, which
  `cancel(_:)` cancels; the transport call observes cooperative cancellation and the job returns
  as `cancelled`. File: `GenerationKit.swift`. Validated with the new
  `OpenRouterClientTests.cancelStopsTraffic` (a 10 s transport returns in under 1 s after cancel).
- **DEFECT-010 (Medium)** — a cached snapshot is only used when its `schemaVersion` equals the
  bundled catalog's. File: `AppModel.swift`.
- **DEFECT-011 (Low)** — builder warnings are stored in `routingWarnings` and shown in the run bar.
  Files: `AppModel.swift`, `Views.swift`.
- **DEFECT-012 (Low)** — a refresh whose model count drops more than 10 % is held back behind an
  explicit confirmation. Files: `AppModel.swift`, `Views.swift`.

## Requirement Coverage

- **ITEM-001** (aliases: REQ-001, AC-001, AC-002, AC-003) — Implemented. Package with eight
  library targets, one test target per logic library, catalog copied byte-identically into
  `CatalogCore` resources. Validated with `swift build`, `swift test`,
  `CatalogBootstrapTests.bundledCopyMatchesRepository`.
- **ITEM-002** (REQ-002, AC-004, AC-005, AC-006) — Implemented. Tolerant models hold `schema`
  and `$defs` as `JSONValue`; unknown control/evidence kinds decode to `.unknown`. Validated with
  `totals`, `slashSegments`, `tolerance`. Remaining: full decode→encode→decode equality is asserted
  on the declared fields and the measured fixtures, not on the entire 2,4 MB document.
- **ITEM-003** (REQ-003, AC-007, AC-008, AC-009) — Implemented. Validated with `lazyDecoding`
  (summary: 0 parameter decodes; first model: only that model), `totals`.
- **ITEM-004** (REQ-004, AC-010, AC-011, AC-012) — Implemented. Refresh fetches the four
  `sources`, maps remote endpoints, guards `schemaVersion` and keeps the old snapshot on failure.
  Validated with `schemaGuard`, `httpError`, `successfulRefresh`, `snapshotCache`. Remaining: the
  upstream response shapes are still UNKNOWN beyond the mapper's tolerant fixtures; the refresh is
  not yet wired to a UI button.
- **ITEM-005** (REQ-005, AC-013, AC-014, AC-015) — Implemented. Validated with `ModelFilterTests`
  (68 rows, `meta/muse-image` = no endpoint, `openrouter/auto*` = chat only, 10 streaming
  endpoints) and `resolver` (sunburst = 24 parameters).
- **ITEM-006** (REQ-006, AC-016–AC-020) — Implemented. Validated with `FieldPlanParityTests`
  (1.154/1.154 fields over 69 endpoints, 1.907 control entries) and `sectionsAndSearch`. Remaining:
  VoiceOver walkthrough is manual (M-11).
- **ITEM-007** (REQ-007, AC-021, AC-022) — Implemented. Validated with `triState` and `switchPlan`
  (dropped paths carry a reason; values are removed only after confirmation).
- **ITEM-008** (REQ-008, AC-023–AC-026) — Implemented. Validated with `SchemaValidationTests`
  (keyword table, nullable arrays, `ContentPartImage` `$ref`, capability bounds).
- **ITEM-009** (REQ-009, AC-027–AC-029) — Implemented. Validated with `frameCount` and
  `unknownOperator`; hide/disable behaviour is covered by `FieldPlanSettings` and M-2/M-7.
- **ITEM-010** (REQ-010, AC-030–AC-032) — Implemented. Validated with `valueConstraints`,
  `allValueConstraints` (13 rules, 11 offered options) and `mask` (PNG, alpha, dimensions).
- **ITEM-011** (REQ-011, AC-033–AC-035) — Implemented. Validated with `runState` and
  `performance` (measured 1,4 ms for 200 fields).
- **ITEM-012** (REQ-012, AC-036–AC-039) — Implemented. Validated with `keySet`,
  `autoRouting`, `exampleOne`, `exampleTwo`, `blockingIssues`, `streaming`. Remaining:
  `unsupportedSurface` exists as an error case, but the surface switch itself is out of scope, so
  AC-039 is satisfied only by the error path.
- **ITEM-013** (REQ-013, AC-040, AC-041) — Implemented. Validated with `previewPerformance`
  (0,06 ms) and `redaction`.
- **ITEM-014** (REQ-014, AC-042–AC-044) — Implemented. Validated with `decodeSuccess`,
  `unknownCost`, `errorMapping`, `cancellation`, `idempotency`.
- **ITEM-015** (REQ-015, AC-045–AC-047) — Implemented. Validated with `SSEParserTests`
  (fragments, CRLF, multi-line data), `streaming`, `streamError`, `streaming` request test.
- **ITEM-016** (REQ-016, AC-048–AC-050) — Implemented. Validated with `writesFiles`, `collision`,
  `preservesUnknownFields`, plus the confinement/atomic-writer tests in `CoreSupportTests`.
- **ITEM-017** (REQ-017, AC-051–AC-053) — Implemented. Validated with `rebuild` (25 items),
  `missingImage`, `search`, `searchPerformance` (40,9 ms for 10.000 items).
- **ITEM-018** (REQ-018, AC-054–AC-057) — Implemented. Validated with the Keychain tests
  (round-trip, empty key, locked/denied backend, masked state). Remaining: the real `SecItemAdd`
  attributes and a "Test key" request are manual/not implemented.
- **ITEM-019** (REQ-005/006/011/013/018, AC-002, AC-019, AC-020, AC-034, AC-040, AC-056) —
  Implemented and compiling. Validated by `swift build` and the manual procedure M-1…M-15.
- **ITEM-020** (AC-001, AC-003, AC-020, AC-035, AC-040, AC-053) — Implemented as
  `docs/runbook.md` and `docs/manual-test-procedure.md` with the AC→test table.

## Files Changed

- `Package.swift` (new)
- `Sources/CoreSupport/` — `JSONValue.swift`, `PathKey.swift`, `Networking.swift`,
  `Diagnostics.swift`, `FileSystem.swift`, `ImageProbe.swift`
- `Sources/CatalogCore/` — `Models.swift`, `CatalogStore.swift`, `ModelFilter.swift`,
  `Refresh/CatalogRefreshClient.swift`, `Refresh/SnapshotCache.swift`,
  `Resources/openrouter-image-ui-catalog.json`
- `Sources/ParameterEngine/` — `ParameterDraft.swift`, `FieldPlan.swift`,
  `Conditions/ConditionEvaluator.swift`, `Constraints/Constraints.swift`,
  `Validation/JSONSchemaValidator.swift`, `Validation/ValidationEngine.swift`
- `Sources/RequestKit/` — `ImagesRequestBuilder.swift`, `JSONPreview.swift`
- `Sources/GenerationKit/GenerationKit.swift`
- `Sources/LibraryKit/` — `ImageWriter.swift`, `LibraryIndex.swift`
- `Sources/SettingsKit/SettingsKit.swift`
- `Sources/NetsiImageUI/` — `AppModel.swift`, `Views.swift`, `SettingsPane.swift`
- `Sources/NetsiImageApp/NetsiImageApp.swift`
- `Tests/` — `CoreSupportTests`, `CatalogCoreTests`, `ParameterEngineTests`, `RequestKitTests`,
  `GenerationKitTests`, `LibraryKitTests`, `SettingsKitTests`
- `docs/runbook.md`, `docs/manual-test-procedure.md` (new)

`develop/PRD.md` and `openrouter-image-ui-catalog.json` are unchanged.

## Key Design Decisions

Parallelism: bounded, cap 3, isolation shared-working-tree — executed serially inline because the
named `lc-code-agent` is not available in this runtime.

- **`FieldPlan` as the testable seam (plan D-2).** Parity and widget mapping are asserted on the
  pure plan, because `swift test` cannot inspect SwiftUI. The widget factory switches over the
  same `ControlKind`, with `.unknown` falling back to the JSON editor.
- **Tri-state draft (PRD rule).** `ParameterValue.unset` is distinct from a set value, so optional
  fields are omitted from the body exactly as the catalog's `ui.defaults` demands.
- **`model` is structural.** `ValidationEngine` skips the `model` parameter and the builder sets it
  from `endpoint.modelId`; the builder validates a copy that already carries it.
- **Provider pin merge.** The pin is merged into `provider` without overriding an explicit
  `provider.only`/`allow_fallbacks`; auto-routing drops `provider.options.*` with a warning.
- **CRLF handling.** Swift treats `\r\n` as one grapheme cluster, so the SSE parser splits on
  `.newlines` instead of `split(separator: "\n")` — a real bug found by the CRLF test and fixed.
- **Index (plan D-1).** `library-index.json` behind `LibraryIndex`, rebuilt from sidecars; the
  sidecar stays authoritative.
- **Style.** New files follow the plan's module layout; no history existed to copy (no git repo).

## Deviations from Plan

- `lc-code-agent` was unavailable, so the phase ran inline per the wrapper's degrade rule.
- `LibraryKit` depends on `GenerationKit` (the plan's graph did not name this edge) because the
  writer takes `GenerationJob`/`GenerationResult` and the endpoint.
- `Unsolicited`: `ValidationEngine` skips the structural `model` field; the plan did not mention it.
- `Refresh` is implemented and tested but has no UI trigger yet (plan ITEM-004 named a picker
  refresh; the picker shows the bundled data).
- No `Test key` action was built (plan ITEM-018 mentions it); only save/delete/read are implemented.

### Skipped/Deferred Items

None — `workSet` covered ITEM-001…ITEM-020; no tracker skip list was active.

## Assumptions

- ASSUMPTION: The named `lc-code-agent` does not exist in this runtime; the wrapper's inline
  fallback was used with the same handoff values.
- ASSUMPTION: `chatCompletions` and `responses` remain out of scope; only the `images` builder is
  implemented.
- ASSUMPTION: The refresh mapper's upstream shapes are inferred from the catalog's `sources`; the
  fixtures are synthetic and recorded in the tests, not captured live.
- ASSUMPTION: Keychain behaviour is verified through an injected backend; the real `SecItemAdd`
  attributes are manual (M-8/M-15).
- ASSUMPTION: UI criteria that a headless runner cannot assert are covered by
  `docs/manual-test-procedure.md`.

## Commands Run

- `swift build` — succeeded, no warnings.
- `swift test` — succeeded after the fix iterations: 77 tests in 7 targets.
- `swift test --filter Debug` (temporary diagnostic suite, since removed) — found the CRLF split
  defect.
- `jq` measurements against `openrouter-image-ui-catalog.json` (model/endpoint/parameter counts,
  control totals, `activeWhen`/`valueConstraints`/`constraints` shapes, `requestExamples`).
- `shasum -a 256` on the catalog and its bundled copy — identical.

## Validation Evidence

- Catalog: 68 models, 121 endpoints (69 `images`, 26 chat, 26 responses), 1.907 parameter entries
  (1.154 on `images`), 17 provider routes, 65 models with an `images` surface,
  `meta/muse-image` without an endpoint.
- Parity: 1.154 of 1.154 fields over 69 endpoints; control totals equal the catalog's own numbers.
- Request fixtures: `requestExamples[0]` and `[1]` reproduced exactly (structural equality).
- Performance (printed by the tests): 200-field validation 1,4 ms; 10.000-item search 40,9 ms;
  preview render 0,06 ms.
- Offline: the whole suite runs without network access and without Keychain prompts.

## Known Limitations

- Only the `images` surface; `chatCompletions` and `responses` are not built (the builder refuses
  them explicitly).
- Streaming partial images are captured on the job (`partialImage`) but the result pane only shows
  the final image; there is no progressive preview in the UI yet.
- Sandbox entitlements, notarisation and the real Keychain attribute path are not verified here.
- The refresh mapper's upstream shapes are still inferred; a shape change fails closed.
- No git repository exists, so no history/blame step was possible.

## Handoff to Test Agent

- **What changed:** a complete, dependency-free SwiftPM package implementing the P0 slice, plus a
  compiling SwiftUI macOS app and 72 tests across seven targets.
- **Why:** deliver the catalog → parameter → request → generation → library spine defined by
  `spec.md`.
- **Requirements covered:** ITEM-001…ITEM-020; AC-001…AC-057 as mapped in
  `docs/manual-test-procedure.md`.
- **Files:** see Files Changed.
- **Commands run:** `swift build`, `swift test`, `jq` catalogue measurements, `shasum`.
- **Known gaps:** chat/responses surfaces, progressive partial-image UI, sandbox/notarisation.
- **Areas needing test attention:** request-body key set vs. endpoint parameters for endpoints with
  provider pins; `activeWhen` `minItems` (`markup`); the refresh mapper's tolerance to upstream
  shapes; index rebuild after manual file moves; SSE behaviour on `\r\n` (a defect was found here).
- **Risk introduced:** the `/Users/stenhougaard/Pictures/Netsi Image` default library path is
  created on first launch; writes are root-confined, but the folder is outside the repository.

Status: Ready for Tests
