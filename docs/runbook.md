# Kørebog — Netsi Image (P0-slice)

Denne fil beskriver, hvordan pakken bygges, testes og køres, og hvordan hver
acceptance-kriterium i `spec.md` verificeres.

## Forudsætninger

- macOS 27.2 eller nyere (Apple Silicon)
- Swift 6.4.2 / Xcode 27.2
- Ingen tredjepartsafhængigheder; ingen netværksadgang nødvendig for test

## Byg og test

```sh
swift build
swift test
```

Begge kører offline. Kataloget ligger i `Sources/CatalogCore/Resources/` og er
byte-identisk med `openrouter-image-ui-catalog.json` i roden (testet).

## Kør appen

```sh
swift run NetsiImage
```

## Byg og installer som macOS-app

```sh
./scripts/build-app.sh              # release-build + installer i /Applications
./scripts/build-app.sh --no-install # kun build til build/Netsi Image.app
```

Scriptet samler `Netsi Image.app` med `Info.plist` (bundle-id `dk.netsi.image`),
lægger SwiftPM-ressourcebundlen i `Contents/Resources`, ad-hoc-signerer og kopierer
appen til `/Applications`. Appen er ikke notariseret, så den må kun distribueres
lokalt; på en anden Mac skal den signeres og notariseres først.

Første start: appen vælger `openai/gpt-image-2` (eller første genererbare
model), opretter biblioteket i `~/Pictures/Netsi Image` og viser
parameterinspektøren. En OpenRouter-nøgle indtastes under **Indstillinger…**;
den gemmes i Keychain (`dk.netsi.image.openrouter` / `api-key`).

## Bibliotekslayout

```
~/Pictures/Netsi Image/
├── Library/2026/11/11/20261111-142233-openai-gpt-image-2-a1b2c3.png
├── Library/2026/11/11/20261111-142233-openai-gpt-image-2-a1b2c3.json
└── library-index.json        ← afledt; kan slettes og genopbygges
```

Slet `library-index.json` og tryk **Genopbyg indeks** i appen (eller kør
`LibraryService.rebuild()`) for at genskabe alle poster fra sidecars.

## Målte værdier (CI-logg)

Testene printer deres egne målinger:

| Måling | Grænse | Hvor |
|---|---|---|
| Validering af 200 felter | < 20 ms | `Tests/ParameterEngineTests` (printes) |
| Søgning i 10.000 poster | < 300 ms | `Tests/LibraryKitTests` (printes) |
| Paritet over 69 images-endpoints | 1.154/1.154 felter | `Tests/ParameterEngineTests` |

## Manuel procedure (det en headless kørsel ikke kan se)

1. **Start** appen. Modelvælgeren viser 68 modeller og "68 modeller · 17 providers".
2. Vælg `OpenAI: GPT Image 2.6 Sunburst`. Inspektøren viser **24 felter**, fordelt på
   Modelparametre, Routing og Provider-options. `Prompt` er markeret som påkrævet.
3. Skriv en prompt. Bundlinjen skifter fra "1 felt mangler opmærksomhed" til "Klar".
4. Tryk **⌘⇧J**: request-body vises med `model`, `prompt` og `provider.only`.
5. Sæt `Baggrund` = `transparent` og `Format` = `jpeg`. Der vises en blokerende fejl
   med forslaget "Sæt output_format til png"; **Generér** er deaktiveret.
6. Skift til `MiniMax H3 Image`. En advarsel lister felter, der ikke findes på den
   nye model, og de fjernes først efter bekræftelse.
7. Med en gyldig nøgle: tryk **⌘R**. Billedet vises, og pris/tid står under det.
   Filen og `.json`-sidecaren ligger i dagens mappe i biblioteket.
8. Slet nøglen i Indstillinger. Katalog, formular, preview og bibliotek virker
   fortsat; **Generér** er deaktiveret med en forklaring.
9. VoiceOver: hvert felt læses som "label, type, værdi" (fx "Baggrund, valgmulighed,
   transparent"). Bevis-badges har både symbol og tekst.
10. Reduce Motion: delbillede-opdateringer animeres ikke.
11. Panelbredder kan trækkes; indholdet ombrydes uden klip ved 1.100 px bredde.

## Kendte begrænsninger

- Kun `images`-fladen; `chatCompletions` og `responses` er udskudt.
- Ingen prisestimat/budget, historik, presets, kø, sammenligning eller skills (P1).
- Sandbox, notarisering og App Store er ikke konfigureret i denne slice.
