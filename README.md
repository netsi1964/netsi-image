# Netsi Image

Native macOS-app til billedgenerering via [OpenRouter](https://openrouter.ai). Skrevet i SwiftUI, uden tredjepartsafhængigheder, med et mørkt "Sequoia Dark Studio"-layout.

Appen læser et bundlet katalog over 68 OpenRouter-billedmodeller (17 providers) og viser **alle** de parametre, hver model understøtter — med skema, validering, betingede felter og provider-routing. Hver generering gemmes som billedfil + JSON-metadata, og JSON'en er **indlejret i selve billedfilen**, så den ikke kan skilles fra billedet.

---

## Indhold

- [Funktioner](#funktioner)
- [Installation](#installation)
- [Anvendelse](#anvendelse)
- [Sikkerhed](#sikkerhed)
- [Tid og penge brugt](#tid-og-penge-brugt)
- [Arkitektur](#arkitektur)
- [Test](#test)
- [Bibliotek og filer](#bibliotek-og-filer)

---

## Funktioner

### Modelkatalog
- Bundlet snapshot af OpenRouter's billedmodeller (68 modeller, 17 providers), med automatisk gruppering i produktfamilier (fx "Google: Nano Banana", "ByteDance Seed: Seedream").
- Live-opdatering fra OpenRouter, med validering af URL-segmenter, svarstørrelse og JSON-dybde.
- Per-token pris på modelrækker og familier.

### Parameterformular
- Skema-drevet formular med 13 kontroltyper (select, tekst, tal, slider, checkbox, multi-select, repeater, image-list, image-input, size-input, JSON-editor, konstant, ukendt).
- Validerings- og betingelsesmotor: `activeWhen`, `valueConstraints`, `required`, blokerende fejl og advarsler, forslag til rettelser.
- Automatisk udledning af sektioner, "N felter", søgning i felter og Nulstil.
- Design-tilpassede kontroltyper: `Billedformat` som 4 aspect-chips, `Sampling Steps` og `Guidance` som sliders, `Seed` med terning, `Referencebilleder` som dropzone.
- Request-body kan inspiceres som JSON (⌘⇧J) og kopieres.

### Generering
- Understøtter de tre API-flader, OpenRouter tilbyder til billedgenerering, med korrekt provider-routing.
- Streaming med live preview, når modellen understøtter det; automatisk fallback til en almindelig request, hvis streamen slutter uden billede.
- En plain request sender aldrig `stream: true`; en streaming-request sender det altid.
- Billeder valideres på magic bytes (PNG/JPEG/WebP/GIF); SVG og ukendte formater afvises med dansk fejl.
- Størrelsesgrænse på svar (64 MiB; 16 MiB for katalog-opdatering).

### Billedbibliotek
- Hver generering gemmes som `billede.png` + `billede.json` (sidecar) i `~/Pictures/Netsi Image/Library/ÅÅÅÅ/MM/DD/`.
- JSON-metadata er indlejret i billedet: PNG `iTXt`-chunk med nøgle `NetsiImage`, JPEG `COM`-segment med `NetsiImage:{json}`. `sha256` og `bytes` opdateres i sidecar'en bagefter.
- Bibliotek med søgning, filtre og "Genopbyg indeks"; indekset er afledt og kan slettes og genskabes.
- Fuld-størrelse viewer med "Tilpas" / "1:1", zoom, "Åbn i Preview" og "Vis i Finder".

### UI
- Tre-panels studio-layout: topbar med brand, version, navigation, handlinger og avatar; 264 pt sidebar med familie-accordions; canvas med prompt-felt, hero-preview og biblioteksgrid; 320 pt inspector; statuslinje.
- Fanerne Canvas, Bibliotek, History, Batch Queue og Models.
- Dark studio-tema, `StudioTheme`/`StudioFont`/`StudioMoney`, chips, søgefelt, sektionsoverskrifter, pills og status-prikker.
- Forbrug vises fra OpenRouter: `/api/v1/key` parses til `usageUSD` / `limitUSD` / `remainingUSD`, vist i topbar, sidebar-kort og Indstillinger, med "Opdater forbrug".

### Nøgle og indstillinger
- OpenRouter-nøgle gemmes i Keychain (`dk.netsi.image.openrouter` / `api-key`).
- Indstillinger: gem, slet, test nøgle, opdater forbrug, vælg biblioteksmappe.
- Dansk fejl- og statusprog i hele appen.

### Sikkerhed
- `ImageFormatSniffer` verifierer serverens `media_type` mod faktiske magic bytes.
- Størrelsesgrænse, JSON-dybdegrænse (64) og URL-segmentvalidering i katalog-opdateringen.
- `LibraryItem.isOpenable` og `openInPreview` åbner kun kendte billedformater.
- `endpointURL` kræver `https` og samme host som skabelonen, og percent-encoder `author`/`slug`.

---

## Installation

### Krav
- macOS 27 (Apple Silicon)
- Swift 6.4 / Xcode 27
- Ingen tredjepartsafhængigheder

### Byg og test
```sh
swift build
swift test
```

### Byg og installer som app
```sh
./scripts/build-app.sh              # release-build + installer i /Applications
./scripts/build-app.sh --no-install # kun build til build/Netsi Image.app
```

Scriptet:
1. Bygger release.
2. Samler `Netsi Image.app` med `Info.plist` (bundle-id `dk.netsi.image`, version `1.3.0`, build `4`).
3. Lægger SwiftPM-ressourcebundlen i `Contents/Resources`.
4. Signerer med den lokale identitet **"Netsi Image Local"** (se nedenfor), ellers ad-hoc.
5. Kopierer appen til `/Applications` og afregistrerer staging-bundlen, så kun `/Applications` er registreret.

### Stabil signeringsidentitet
`scripts/signing-identity.sh` opretter én gang et selvsigneret kode-signeringscertifikat i en separat nøglering (`~/Library/Keychains/netsi-image-signing.keychain-db`). Fordi signaturen er stabil, husker macOS appens adgang til OpenRouter-nøglen i Keychain, og nye builds udløser ikke nye "Netsi Image ønsker at…"-dialoger.

```sh
./scripts/signing-identity.sh          # opret identiteten, hvis den mangler
./scripts/signing-identity.sh --print  # print identitetens navn
```

Appen er ikke notariseret og må kun distribueres lokalt. På en anden Mac skal den signeres og notariseres først.

### Første start
1. Appen vælger en genererbar model, opretter biblioteket i `~/Pictures/Netsi Image` og viser parameterinspektøren.
2. Åbn **Indstillinger…** og indsæt din OpenRouter-nøgle.
3. Tryk **Gem nøgle** og **Test nøgle**.

---

## Anvendelse

### 1. Vælg model
I venstre sidebar: vælg en produktfamilie og en modelversion. Hver række viser modelnavn og per-token pris. "Opdater" henter kataloget fra OpenRouter.

### 2. Skriv prompt
Skriv i prompt-feltet på canvas. Når prompten er sat, skifter statuslinjen fra "1 felt mangler opmærksomhed" til "Klar".

### 3. Justér parametre
Højre inspector viser alle modellens felter, grupperet i sektioner. Brug søgefeltet til at finde et felt. Felter med `påkrævet` skal udfyldes; blokerende fejl vises med et forslag til rettelse.

### 4. Generér
Tryk **Generér** (⌘R) eller play-knappen. Ved streaming vises billedet løbende; ellers vises det, når svaret er klar. Pris og tid står under billedet.

### 5. Find resultatet
Billedet ligger i `~/Pictures/Netsi Image/Library/...` og i biblioteket. Klik på et billede for fuld-størrelse viewer; "Åbn i Preview" og "Vis i Finder" virker derfra.

### 6. Inspicér request
⌘⇧J viser den præcise request-body, som appen sender. "Kopiér" lægger den på udklipsholderen.

### 7. Forbrug
Forbrug hentes fra OpenRouter og vises i topbar, sidebar og Indstillinger. **Opdater forbrug** henter de nyeste tal.

### 8. Indstillinger
- **Gem nøgle** / **Slet nøgle** / **Test nøgle**.
- **Vælg mappe…** for bibliotekets placering.
- **Opdater forbrug** for at hente `usage`, `limit` og `remaining`.

---

## Sikkerhed

Koden er blevet sikkerhedsscannet af **Claude** (Anthropic) i en separat gennemgang. Scanningen fokuserede på:

- **A. Billedvalidering:** serverens `media_type` verificeres mod faktiske magic bytes; SVG, ukendte og tomme svar afvises.
- **B. Ressourcegrænser:** svarstørrelse (64 MiB / 16 MiB), JSON-dybde (64) og URL-segmentvalidering i katalog-opdateringen.
- **C. Nøglehåndtering:** nøglen ligger i Keychain, ikke i filer eller logs; `LibraryItem.isOpenable` og `openInPreview` begrænser åbning til kendte formater.
- **D. Netværk:** `endpointURL` kræver `https` og samme host som skabelonen, og percent-encoder `author`/`slug`.

Rapporten er ikke en garanti; den er et øjebliksbillede af koden på det tidspunkt, scanningen blev kørt. Kør `swift test` og en ny scanning, før du ændrer sikkerhedsrelevante dele.

---

## Tid og penge brugt

### Tid
- **Aktiv udvikling:** ca. **8 timer** fordelt over 11.–13. november 2026 (målt som samtaletid med maks. 10 minutters idle pr. gap).
- **Wall-clock:** ca. **42 timer** fra første til sidste aktivitet.

### Penge
| Post | Beløb |
|---|---|
| OpenRouter — udviklingssamtalen (DeepSeek V4.1 Flash) | **$3.93** |
| OpenRouter — nøglens samlede forbrug (inkl. appens egne billedgenereringer) | **$13.63** |
| OpenRouter — nøglens grænse | $20.00 |
| OpenRouter — nøglens resterende | $19.40 |
| OpenRouter — månedligt forbrug | $12.53 |
| OpenRouter — ugentligt forbrug | $11.76 |
| Claude (Anthropic) — sikkerhedsscanning | Brugerens eget abonnement |

Tallene er hentet fra OpenRouter's `/api/v1/key` og fra de lokale OpenCode-samtalelogfiler. De er øjebliksbilleder og ikke en faktura.

### Omkostningsdetaljer
- **OpenRouter** er den eneste betalte API-afhængighed. Modellen `deepseek/deepseek-v4.1-flash-1017` blev brugt til hele udviklingssamtalen (957 assistant-svar, ca. 3.6M input-tokens, 358K output-tokens, 350M cache-læste tokens).
- **Claude** blev brugt til sikkerhedsscanningen, ikke til selve kodeudviklingen.
- **DeepSeek** kører via OpenRouter, så det er inkluderet i OpenRouter-beløbet.

---

## Arkitektur

```
Sources/
├── CoreSupport/        ← fælles typer: JSON, netværk, billedformat, metadata
├── CatalogCore/        ← katalog, modeller, refresh, filtrering
├── ParameterEngine/    ← skema, validering, betingelser, field plan
├── RequestKit/         ← request-builder for de tre API-flader
├── GenerationKit/      ← OpenRouter-klient, decode/stream, key spend
├── LibraryKit/         ← filer, sidecars, indeks, billedskrivning
├── SettingsKit/        ← Keychain, indstillinger
├── NetsiImageUI/       ← SwiftUI: tema, shell, views, preview
└── NetsiImageApp/      ← appens entry point
```

- **SwiftPM**, `swift-tools-version: 6.4`, macOS 27, strict concurrency.
- Ingen tredjepartsafhængigheder.
- Kataloget ligger i `Sources/CatalogCore/Resources/` og er byte-identisk med `openrouter-image-ui-catalog.json` i roden (testet).

---

## Test

```sh
swift test
```

**108 tests i 7 suites** — CoreSupport, CatalogCore, ParameterEngine, RequestKit, GenerationKit, LibraryKit, SettingsKit. Testene kører offline; ingen netværksadgang nødvendig.

---

## Bibliotek og filer

```
~/Pictures/Netsi Image/
├── Library/2026/11/11/20261111-142233-openai-gpt-image-2-a1b2c3.png
├── Library/2026/11/11/20261111-142233-openai-gpt-image-2-a1b2c3.json
└── library-index.json        ← afledt; kan slettes og genopbygges
```

Slet `library-index.json` og tryk **Genopbyg indeks** i appen for at genskabe alle poster fra sidecars.

### Katalog-cache
`~/Library/Application Support/dk.netsi.image/catalog/`

### Keychain
- Service: `dk.netsi.image.openrouter`
- Account: `api-key`

### Signeringsidentitet
- Nøglering: `~/Library/Keychains/netsi-image-signing.keychain-db`
- Certifikat: `~/Library/Application Support/dk.netsi.image/signing/cert.pem`

---

## Dokumentation

- `develop/PRD.md` — produktkrav (1466 linjer, dansk).
- `docs/runbook.md` — byg, test og kør.
- `docs/manual-test-procedure.md` — manuel testprocedure (M-1 … M-15).
- `.lc/developer/...` — lc-flowets artefakter (spec, plan, kode, test, review, sikkerhed).
