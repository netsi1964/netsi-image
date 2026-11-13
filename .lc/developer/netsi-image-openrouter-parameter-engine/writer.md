# Netsi Image — release forberedelse (P0-slice)

Agent: lc-ship
Mode: Ship
Status: Ready for Release Preparation
Confidence: High
Artifact mode: brief
Artifact folder: .lc/developer/netsi-image-openrouter-parameter-engine/

## TL;DR
<!-- lc-tldr -->

- Netsi Image P0 er klar som en dependency-fri SwiftPM-pakke med en kompilerende SwiftUI-macOS-app: katalog, parametermotor, request-bygger, generering med SSE og et filbaseret bibliotek med sidecars.
- 77 tests er grønne offline; paritet er 1.154/1.154 felter over 69 endpoints, og begge katalogets request-eksempler genskabes præcist.
- To fix-iterationer lukkede 11 defekter, inkl. en High om afbrydelse og en High om CRLF i SSE-parseren.
- Sikkerhed er godkendt med betingelser: sandbox/notarisering mangler, og sidecars er almindelig tekst.
- Intet er committet eller udgivet; næste skridt er manuel test efter `docs/manual-test-procedure.md` og en beslutning om P1-omfang.

## Release Summary

Denne leverance er den første fungerende kerne af Netsi Image: man kan vælge en af de 68
OpenRouter-billedmodeller, se og justere **alle** de parametre, endpointet melder (1.154 felter på
`images`-fladen), få valideret requesten mod katalogets skemaer og betingelser, se den præcise
body, generere med streaming hvor det understøttes, og finde billedet igen som en selvstændig fil
med en JSON-sidecar.

Indhold: 8 biblioteks-targets, 1 SwiftUI-executable, 77 tests i 7 target, 2 dokumentationsfiler.
Ingen tredjepartsafhængigheder. `develop/PRD.md` og `openrouter-image-ui-catalog.json` er uændrede.

## Release Notes

**Nyt**
- Katalog med bundlet snapshot, lazy dekodning og live-opdatering med `schemaVersion`-vagt og
  cache (AC-001…AC-012).
- Schema-drevet parameterformular med 13 kontroltyper, tri-state værdier, søgning, bevis-badges og
  sektionerne Modelparametre/Routing/Provider-options (AC-016…AC-022).
- Validering: JSON Schema-delængde med `$ref`, `activeWhen` (`equals`/`in`/`minItems`),
  `valueConstraints` og providerspecifikke `constraints` (AC-023…AC-035).
- Request-bygger for `images` med provider-pin, auto-routing-advarsler, streaming kun hvor
  endpointet melder støtte, samt JSON-forhåndsvisning med base64-redaktion (AC-036…AC-041).
- Generering via OpenRouter med dansk fejlmapping, idempotente jobs, reel afbrydelse og
  SSE-begivenheder (AC-042…AC-047).
- Bibliotek: `Library/yyyy/MM/dd/…` + sidecar, kollisionssuffiks, atomisk skrivning,
  rodkonfinement, afledt indeks med genopbygning og søgning (AC-048…AC-053).
- Nøgle i Keychain med test-handling, maskeret visning og read-only-tilstand (AC-054…AC-057).
- SwiftUI-skal med tre paneler, modelvælger, inspektør, kør-linje, preview, galleri og indstillinger.

**Rettet undervejs**
- Decimal-tab i JSON-kodning (kataloget er nu tabsfrit ved round-trip).
- CRLF i SSE: Swift behandler `\r\n` som ét tegn, så parseren delte aldrig linjer; nu splittes på
  `.newlines`.
- Afbrydelse stopper nu det kørende transport-kald (work-task pr. job).

**Ikke med**
- `chatCompletions`/`responses`, prisestimat/budget, historik, presets, batch-kø, sammenligning,
  skills, Shortcuts og eksport (P1/P2 i PRD'en).

## Known Limitations

- Kun `images`-fladen; andre flader afvises eksplicit.
- Delbilleder gemmes på jobbet, men vises ikke progressivt i resultatpanelet.
- Sandbox-entitlements, hardened runtime og notarisering er ikke konfigureret.
- Katalogets upstream-svarformer er stadig antagne; opdatering fejler lukket ved skemabrud.
- VoiceOver, rigtige Keychain-attributter og panellayout er manuelle testpunkter (M-1…M-16).

## Recommended Next Action

1. Kør `docs/manual-test-procedure.md` (M-1…M-16) på en ren brugerkonto.
2. Beslut P1-omfang (prisestimat/budget og presets er de mest værdifulde næste).
3. Tilføj sandbox/notarisering før nogen form for distribution.
4. Opret git-repo og commit den grønne tilstand, før næste iteration.

Status: Ready for Release Preparation
