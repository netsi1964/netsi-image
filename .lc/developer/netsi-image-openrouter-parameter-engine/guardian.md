# Netsi Image — sikkerhedsreview (P0-slice)

Agent: lc-security
Mode: Security
Status: Approved with Conditions
Confidence: High
Artifact mode: brief
Artifact folder: .lc/developer/netsi-image-openrouter-parameter-engine/

## TL;DR
<!-- lc-tldr -->

- No key material is stored, logged or exported outside the Keychain; no secret-shaped string appears in the tree.
- File writes are root-confined and atomic, and the library index is derived and rebuildable; no path traversal reaches the filesystem.
- The sidecar stores the full request body in plaintext, including any inline base64 input images — accepted with a documented condition.
- Sandbox entitlements and notarisation are not configured for this SwiftPM slice; that condition must be closed before any distribution.
- Refresh trusts a downloaded catalog after a `schemaVersion` check only; integrity beyond that is a residual risk.

Scope reviewed: `Sources/CoreSupport`, `CatalogCore`, `ParameterEngine`, `RequestKit`,
`GenerationKit`, `LibraryKit`, `SettingsKit`, `NetsiImageUI`, `Tests/`, `Package.swift`,
`docs/`, and the four upstream reports.

Evidence reviewed: `Package.swift` (no third-party dependency), `coder.md`, `tester.md`,
`reviewer.md`, a scan of the source tree for token-shaped strings and logging of headers, and the
Keychain/file-write code paths.

## Security Summary

The design keeps the interesting assets local: the API key lives only in the Keychain and is read
per call; prompts, parameters and images never leave the machine except in the OpenRouter request
itself. Error mapping includes the provider's response body but never the request headers, so the
bearer token cannot reach a log or an alert. The library writer checks confinement before the first
byte and writes through a temp file plus rename. The index is a derived cache, so corruption is
recoverable rather than destructive.

Weak points are operational, not architectural: there is no sandbox entitlement file or
notarisation in this slice, sidecars are plaintext, and a refreshed catalog is trusted after a
schema-version check only.

## Decision

Approved with Conditions.

Conditions: configure App Sandbox entitlements and notarisation before distribution; treat sidecars
as sensitive (they may contain input images); keep the "no third-party dependency" rule.

## Findings

| Id | Severity | Finding | Action |
|---|---|---|---|
| SEC-DEFECT-001 | Medium | No App Sandbox entitlement file, hardened-runtime flags or notarisation exist for the app target (`Package.swift`). The PRD requires sandboxing from day one. | Add entitlements (`com.apple.security.app-sandbox`, network client, user-selected read/write) and notarise before distribution. |
| SEC-DEFECT-002 | Low | Sidecars store the full request body in plaintext, including inline base64 input images (`Sources/LibraryKit/ImageWriter.swift`). | Document that the library holds prompt and image data; offer a "sidecar without body" setting if privacy requires it. |
| SEC-DEFECT-003 | Low | A refreshed catalog is written to Application Support and trusted on the next launch after a `schemaVersion` check only (`Sources/CatalogCore/Refresh/SnapshotCache.swift`). | Optionally record a source host allowlist and a checksum in the manifest. |

### Required Fixes

None blocking for this internal slice. SEC-DEFECT-001 is a condition for any distribution.

### Residual Risks

- The default library path (`~/Pictures/Netsi Image`) is outside the repository; writes are
  confined to it, but any future change that bypasses `ImageWriter` would not be.
- Provider-side retention and training policies are outside this app's control; the UI names the
  provider before a run.
- Real Keychain attribute verification is manual (M-8/M-15).

### Policy Gaps

Baseline principle (assumption): least privilege, no secret in logs, local-first data, and
no third-party runtime dependency (NFR-002). No formal security policy file exists in the
repository, so this principle is the reference.

## Handoff to Ship Agent

- Conditions to record in the release notes: sandbox/notarisation pending; sidecars are sensitive;
  no third-party dependency.
- No open High or Critical security defect.
- Manual security checks: Keychain attributes (M-15), key deletion and read-only mode (M-10).

Status: Approved with Conditions
