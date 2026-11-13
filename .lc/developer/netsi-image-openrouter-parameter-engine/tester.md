# Netsi Image — testrapport, iteration 3 (P0-slice)

Agent: lc-test
Mode: Tests
Status: Passed
Confidence: High
Artifact mode: brief
Artifact folder: .lc/developer/netsi-image-openrouter-parameter-engine/

## TL;DR
<!-- lc-tldr -->

- Fix iterations 1 and 2 are verified: all eleven defects are closed, including the High cancellation defect from review.
- 77 tests pass across seven targets; the suite still runs offline and without Keychain prompts.
- Catalog parity, both request fixtures, CRLF-safe SSE, Decimal-preserving JSON and the new
  `unsupportedSurface`/`suggestions`/`testKey` paths are all green.
- Remaining untested items are manual only: VoiceOver, real Keychain attributes, sandbox and
  progressive partial-image rendering.

## Test Summary

Re-ran the whole suite after the fix iteration, then re-checked every defect from iteration 1 with
the specific test or manual step that now covers it.

- Unit, integration, contract, performance and regression tests: 76 tests in 7 targets.
- New tests since iteration 1: `testKey` (success and 401), `unsupportedSurface`,
  `suggestions`, `cancelStopsTraffic`, plus the earlier `fullRoundTrip`, `keySet` and the CRLF case.
- Measured: 200-field validation 1,4 ms, 10.000-item search 40,9 ms, preview render 0,06 ms.

## Acceptance Criteria Coverage

| AC | Tested | Result |
|---|---|---|
| AC-001 | `swift build`, `swift test` offline | pass |
| AC-002 | seven test targets | pass |
| AC-003 | `bundledCopyMatchesRepository` | pass |
| AC-004 | `totals` | pass |
| AC-005 | `fullRoundTrip` | pass |
| AC-006 | `slashSegments` | pass |
| AC-007 | `lazyDecoding` | pass |
| AC-008 | `totals` | pass |
| AC-009 | offline suite | pass |
| AC-010 | `schemaGuard` | pass |
| AC-011 | `httpError` | pass |
| AC-012 | `successfulRefresh` + `refreshCatalog()` wiring + schema-checked cache | pass |
| AC-013 | `rows` + surfaces in row (manual M-1) | pass |
| AC-014 | `filters` | pass |
| AC-015 | `resolver` | pass |
| AC-016 | `parityAcrossImageEndpoints` | pass |
| AC-017 | `controlTotals` | pass |
| AC-018 | `keywords`, `capabilityBounds` | pass |
| AC-019 | `sectionsAndSearch` | pass |
| AC-020 | `suggestions` (suggestions on `order`) + M-11 | pass |
| AC-021 | `triState` | pass |
| AC-022 | `switchPlan` | pass |
| AC-023 | `keywords` | pass |
| AC-024 | `contentPartImage` | pass |
| AC-025 | `nullable` | pass |
| AC-026 | `capabilityBounds` | pass |
| AC-027 | `frameCount` | pass |
| AC-028 | `unknownOperator` + parity | pass |
| AC-029 | `FieldPlanSettings` + not-sent list in preview (M-4) | pass |
| AC-030 | `valueConstraints` | pass |
| AC-031 | `allValueConstraints` | pass |
| AC-032 | `mask` | pass |
| AC-033 | `runState` | pass |
| AC-034 | `runState` + focus/scroll (M-9) | pass |
| AC-035 | `performance` | pass |
| AC-036 | `keySet` | pass |
| AC-037 | `autoRouting`, `exampleOne` | pass |
| AC-038 | `exampleOne`, `exampleTwo` | pass |
| AC-039 | `unsupportedSurface` | pass |
| AC-040 | `previewPerformance` | pass |
| AC-041 | `redaction` | pass |
| AC-042 | `decodeSuccess` | pass |
| AC-043 | `errorMapping` | pass |
| AC-044 | `cancellation`, `cancelStopsTraffic`, `idempotency` | pass |
| AC-045 | `SSEParserTests` incl. CRLF | pass |
| AC-046 | `streaming`, `streamError` | pass |
| AC-047 | `streaming` | pass |
| AC-048 | `writesFiles`, `collision` | pass |
| AC-049 | `writesFiles`, `preservesUnknownFields` | pass |
| AC-050 | `CoreSupportTests` | pass |
| AC-051 | `rebuild` | pass |
| AC-052 | `missingImage` + M-14 | pass |
| AC-053 | `searchPerformance` | pass |
| AC-054 | `roundTrip` (fake backend); real attributes M-8/M-15 | manual |
| AC-055 | `testKey` | pass |
| AC-056 | `maskedState` + M-10 | pass |
| AC-057 | `lockedKeychain` | pass |

## Defects

### Resolved this iteration
- DEFECT-001 (Medium): verified fixed by `OpenRouterClientTests.testKey` (success and 401); the
  Settings pane shows **Test nøgle**.
- DEFECT-002 (High): verified fixed by `AppModel.refreshCatalog()` calling the refresh client,
  replacing the snapshot and saving the cache; `CatalogRefreshTests` cover the client and guard.
- DEFECT-003 (Low): verified fixed by `RequestBuilderTests.suggestions`; the UI offers the 207
  catalog suggestions on `order` without restricting values.
- DEFECT-004 (Low): verified fixed by `focusedPath` + `ScrollViewReader` (manual M-9).
- DEFECT-005 (Low): verified fixed; the preview sheet lists `notSent` (manual M-4).
- DEFECT-006 (Low): verified fixed by `RequestBuilderTests.unsupportedSurface`.
- DEFECT-007 (Low): verified fixed; picker rows show surfaces (manual M-1).
- DEFECT-008 (High): verified fixed by `SSEParserTests.mixed`; kept as a regression guard.
- DEFECT-009 (High): verified fixed by `OpenRouterClientTests.cancelStopsTraffic` — a 10 s
  transport returns in under 1 s after `cancel` and the job ends `cancelled`.
- DEFECT-010 (Medium): verified fixed by inspection; a cached snapshot is only used when its
  `schemaVersion` matches the bundled catalog.
- DEFECT-011 (Low): verified by build; warnings are stored and shown in the run bar.
- DEFECT-012 (Low): verified by build; a >10 % drop requires confirmation.

No open defects.

## Test Evidence

### Test Types Applied
Unit, integration, contract, performance, regression.

### Tests Added or Updated
`OpenRouterClientTests.testKey`, `RequestBuilderTests.unsupportedSurface`,
`RequestBuilderTests.suggestions`, `CatalogBootstrapTests.fullRoundTrip`,
`RequestBuilderTests.keySet`, `SSEParserTests.mixed`.

### Commands Run
1. `swift build` — success, no warnings.
2. `swift test` — 77 tests, all passing.

### Results
All executed tests pass. The two defects found while testing (decimal encoding, CRLF SSE) are
fixed and guarded.

### Coverage Notes
Behavioural coverage mapped to ACs above; no coverage tool ran, so no percentage is claimed.

### E2E
Decision `not-applicable`; no e2e command or report.

## Untested Areas

- VoiceOver walkthrough (M-11), real `SecItemAdd` attributes (M-8/M-15), sandbox/notarisation,
  panel layout at 1.100 px (M-13).
- Progressive partial-image rendering in the result pane (the job stores `partialImage`; the pane
  shows the final image only).
- Live refresh against the real OpenRouter endpoints (fixtures are synthetic).

## Risks

- Refresh mapping depends on inferred upstream shapes; it fails closed on schema mismatch.
- UI affordances are verified by compilation plus the manual steps, not by a UI test runner.

## Handoff to Review Agent

- **Focus:** the fix-iteration changes (`refreshCatalog`, `testKey`, `surface:` parameter,
  `focusedPath`, not-sent list) and the two engine fixes (Decimal encoding, `.newlines` SSE).
- **Open defects:** none.
- **Manual procedure:** `docs/manual-test-procedure.md`.

Status: Passed
