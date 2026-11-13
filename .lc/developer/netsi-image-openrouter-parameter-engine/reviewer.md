# Netsi Image — review, iteration 2 (P0-slice)

Agent: lc-review
Mode: Review
Status: Approved
Confidence: High
Artifact mode: brief
Artifact folder: .lc/developer/netsi-image-openrouter-parameter-engine/

## TL;DR
<!-- lc-tldr -->

- The High cancellation defect is fixed properly: each job runs in its own work task, `cancel` cancels it, and a 10-second transport returns in under 1 second.
- The cached-snapshot path now compares `schemaVersion` with the bundled catalog before use; the refresh confirmation guards an implausible shrink.
- No open findings remain; the architecture and the catalog-as-only-source-of-truth design hold up under review.
- Remaining gaps are explicitly out of scope (chat/responses surfaces, progressive partial preview, sandbox/notarisation).

## Review Summary

Re-reviewed the iteration-2 diff only: `GenerationKit` (work-task cancellation), `AppModel`
(cached-snapshot schema check, refresh confirmation, routing warnings) and `Views` (run-bar warning,
confirmation UI). The new `cancelStopsTraffic` test closes the gap that the previous review found.

The change itself stays inside the planned scope, keeps the one-way dependency direction and adds
no dependency. Error handling remains explicit, and the cancellation path now sets `cancelled` for
both `CancellationError` and a cooperative transport abort.

## Decision

Approved.

Proceed to security: yes.

## Findings

### Requirement Coverage Assessment
AC-044 is now met: cancellation stops the transport call and the job ends `cancelled`. AC-012 is
met with a schema-checked cache and a confirmation for implausible refreshes.

### Code Quality
`GenerationCoordinator` is easier to reason about: `submit` owns task lifecycle, `run` owns the
state machine, `finished` stamps time and stores the job. No force unwraps; no key material in
paths that log.

### Architecture & Maintainability
No new coupling. `AppModel` still talks only to services; the UI stays free of HTTP and filesystem
calls.

### Test Coverage
The cancellation timing is now asserted (elapsed < 1 s against a 10 s stub). The cached-snapshot
path has no automated UI test; it is small and reviewed by inspection.

### Resolved this iteration
- DEFECT-009 (High): fixed in `GenerationKit.swift`; verified by `cancelStopsTraffic`.
- DEFECT-010 (Medium): fixed in `AppModel.swift`; verified by inspection.
- DEFECT-011 (Low): fixed in `AppModel.swift` and `Views.swift`.
- DEFECT-012 (Low): fixed in `AppModel.swift` and `Views.swift`.

## Blocking Issues

None.

## Non-Blocking Suggestions

None open. (A future iteration could add a UI test runner for the panel behaviours that are manual
today.)

## Security Handoff

- Key lifecycle: read per call, never persisted outside Keychain, never logged — confirm.
- Sidecars embed the full request body, including any inline base64 input images; confirm that is
  intended and that redaction only affects the preview.
- Sandbox entitlements and notarisation remain unconfigured for this SwiftPM slice.

## Recommended Next Action

Proceed to the security phase.

Status: Approved
