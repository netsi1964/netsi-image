# Manuel testprocedure — Netsi Image (P0-slice)

Køres på en Mac med Swift 6.4.2 / macOS 27.2. Trinene dækker det, en headless
`swift test` ikke kan se: layout, tastatur, VoiceOver, scroll-adfærd og den
rigtige Keychain-sti.

## Forberedelse

1. `swift build && swift test` — alt grønt.
2. `swift run NetsiImage`.

## Trin

| # | Trin | Forventet |
|---|---|---|
| M-1 | Start appen | Tre paneler; modelvælger med 68 modeller og "68 modeller · 17 providers" |
| M-2 | Vælg "OpenAI: GPT Image 2.6 Sunburst" | Inspektøren viser 24 felter i sektionerne Modelparametre, Routing, Provider-options; "Prompt" er markeret påkrævet |
| M-3 | Skriv en prompt | Bundlinjen går fra "1 felt mangler opmærksomhed" til "Klar" |
| M-4 | ⌘⇧J | Request-body vises med `model`, `prompt` og `provider.only`; "Kopiér" virker |
| M-5 | Sæt Baggrund = transparent og Format = jpeg | Blokerende fejl med forslaget "Sæt output_format til png"; Generér er deaktiveret |
| M-6 | Klik forslaget | Format skifter til png, fejlen forsvinder, Generér bliver aktiv |
| M-7 | Skift til "MiniMax H3 Image" | Advarsel lister felter, der ikke findes; de fjernes først efter bekræftelse |
| M-8 | Indsæt gyldig nøgle i Indstillinger, tryk ⌘R | Billede vises; pris og tid står under det; fil + `.json` ligger i `~/Pictures/Netsi Image/Library/…` |
| M-8a | Klik på et genereret billede | Fuld-størrelse viewer åbner; "Tilpas" og "1:1" skifter mellem tilpasset og naturlig størrelse; zoom-slider og rul virker |
| M-8b | Klik på et biblioteksbillede | Fuld-størrelse viewer åbner med samme billede; "Åbn i Preview" og "Vis i Finder" virker |
| M-8c | Fremprovoker en provider-fejl (fx 400) | Resultatpanelet viser fejlmeddelelsen og en "Se detaljer"-knap; arket viser rå svar-body, request-id og request-body; "Kopiér" virker |
| M-9 | Klik "Vis første fejl" ved en blokerende fejl | En dialog viser feltets sti og fejlbesked (rul til feltet er ikke implementeret endnu) |
| M-10 | Slet nøglen | Bekræftelse; derefter virker katalog, formular, preview, validering og bibliotek; Generér er deaktiveret med forklaring |
| M-11 | VoiceOver-gennemgang af parameterpanelet | Hvert felt læses som "label, type, værdi"; badges har symbol + tekst |
| M-12 | Slå Reduce Motion til | Delbillede-opdateringer animeres ikke |
| M-13 | Træk panelbredder til 1.100 px vinduesbredde | Intet indhold klippes; begge sidepaneler kan skjules |
| M-14 | Slet `library-index.json`, tryk "Genopbyg indeks" | Alle poster er tilbage |
| M-15 | Lås Keychain-adgang (eller afvis adgang) | Vejledning vises, ingen crash; appen forbliver brugbar |

## Traceability (AC → test eller trin)

| AC | Dækket af |
|---|---|
| AC-001 | `swift build` / `swift test` (kørt offline) |
| AC-002 | `Package.swift` + syv testtargets; `swift test` |
| AC-003 | `CatalogBootstrapTests.bundledCopyMatchesRepository` |
| AC-004 | `CatalogBootstrapTests.totals` |
| AC-005 | `totals` + `tolerance` (round-trip af kendte felter) |
| AC-006 | `CatalogBootstrapTests.slashSegments` |
| AC-007 | `CatalogBootstrapTests.lazyDecoding` |
| AC-008 | `CatalogBootstrapTests.totals` |
| AC-009 | Hele suiten kører uden netværk; `CatalogBootstrapTests.tolerance` (ingen transport) |
| AC-010 | `CatalogRefreshTests.schemaGuard` |
| AC-011 | `CatalogRefreshTests.httpError` |
| AC-012 | `CatalogRefreshTests.successfulRefresh` (snapshot + optælling); vælger-visning: M-1/M-7 |
| AC-013 | `ModelFilterTests.rows`; badges: M-1 |
| AC-014 | `ModelFilterTests.filters` |
| AC-015 | `ModelFilterTests.resolver` |
| AC-016 | `FieldPlanParityTests.parityAcrossImageEndpoints` (1.154/1.154) |
| AC-017 | `FieldPlanParityTests.controlTotals` (1.907 poster) |
| AC-018 | `SchemaValidationTests.keywords` + `capabilityBounds` |
| AC-019 | `FieldPlanParityTests.sectionsAndSearch`; tællere: M-2 |
| AC-020 | `sectionsAndSearch` (label) + `suggestions` (katalogets 207 forslag ligger på `order`); VoiceOver: M-11 |
| AC-021 | `DraftTests.triState` |
| AC-022 | `DraftTests.switchPlan`; bekræftelsesdialog: M-7 |
| AC-023 | `SchemaValidationTests.keywords` |
| AC-024 | `SchemaValidationTests.contentPartImage` |
| AC-025 | `SchemaValidationTests.nullable` |
| AC-026 | `SchemaValidationTests.capabilityBounds` |
| AC-027 | `ConditionTests.frameCount` |
| AC-028 | `ConditionTests.unknownOperator`; `in`/`minItems` dækkes af katalogets 16 regler via paritet |
| AC-029 | `FieldPlan`-indstillinger; skjul/vis: M-2/M-7 |
| AC-030 | `ConditionTests.valueConstraints` |
| AC-031 | `ConditionTests.allValueConstraints` (13 regler) |
| AC-032 | `FieldConstraintTests.mask` |
| AC-033 | `ValidationEngineTests.runState` |
| AC-034 | `runState` (tælling); scroll: M-9 |
| AC-035 | `ValidationEngineTests.performance` (printet måling) |
| AC-036 | `RequestBuilderTests.keySet` |
| AC-037 | `RequestBuilderTests.autoRouting` + `exampleOne` |
| AC-038 | `RequestBuilderTests.exampleOne` og `exampleTwo` |
| AC-039 | `RequestError.unsupportedSurface` findes; surfacen er droppet i denne slice (se Known Limitations) |
| AC-040 | `PreviewTests.previewPerformance` (printet måling) |
| AC-041 | `PreviewTests.redaction` |
| AC-042 | `OpenRouterClientTests.decodeSuccess` |
| AC-043 | `OpenRouterClientTests.errorMapping` |
| AC-044 | `OpenRouterClientTests.cancellation` + `idempotency` |
| AC-045 | `SSEParserTests` (fragmenter, CRLF, flere data-linjer) |
| AC-046 | `OpenRouterClientTests.streaming` + `streamError` |
| AC-047 | `RequestBuilderTests.streaming` |
| AC-048 | `ImageWriterTests.writesFiles` + `collision` |
| AC-049 | `ImageWriterTests.writesFiles` + `preservesUnknownFields` |
| AC-050 | `CoreSupportTests` (konfinement + atomisk skrivning) |
| AC-051 | `LibraryIndexTests.rebuild` (25 poster) |
| AC-052 | `LibraryIndexTests.missingImage`; relink: M-14 |
| AC-053 | `LibraryIndexTests.searchPerformance` (printet måling) |
| AC-054 | `KeychainTests.roundTrip` (fake backend); rigtig Keychain-attribut: M-8/M-15 |
| AC-055 | `KeychainTests.emptyKey` + `lockedKeychain`; "Test nøgle" er ikke implementeret (se Known Limitations) |
| AC-056 | `KeychainTests.maskedState`; read-only-tilstand: M-10 |
| AC-057 | `KeychainTests.lockedKeychain` |
