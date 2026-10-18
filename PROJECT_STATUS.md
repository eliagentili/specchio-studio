# Stato del progetto

Aggiornato il **18 ottobre 2026**. Versione **1.3.1, build 7**, arm64, target macOS 14. Prima **[pre-release sperimentale gratuita v1.3.1-preview.1](https://github.com/eliagentili/specchio-studio/releases/tag/v1.3.1-preview.1)**, pubblicata su scelta esplicita del titolare con le incertezze dichiarate. La pubblicazione non chiude la revisione dei diritti, i collaudi hardware o la notarizzazione.

## Funzionalità

Acquisizione USB, wireless dedicato e finestra/schermo; registrazione MOV H.264/HEVC con audio della sorgente quando disponibile; screenshot, composizione, annotazioni, OCR locale ed esportazione video H.264 con audio e taglio temporale.

Icona e immagine demo correnti sono riproducibili dal codice incluso: `scripts/generate_icon.swift` e il rendering di `Tests/StudioTests.swift`. Questo non sostituisce la revisione della provenienza dei contributi iniziali.

Sono disponibili formati Automatico, Verticale 9:16, Quadrato 1:1 e Orizzontale 16:9 condivisi da screenshot e video. I preset video esportano 1080×1920, 1080×1080 e 1920×1080 pixel. Per gli screenshot la scala di esportazione moltiplica queste dimensioni.

## Punti di ingresso

- `Sources/App.swift`: avvio e comandi dell’app.
- `Sources/StudioView.swift`: interfaccia e flussi dello Studio.
- `Sources/Canvas.swift`: composizione e formati di uscita.
- `Sources/CaptureEngine.swift`: acquisizione, snapshot e registrazioni.
- `Sources/WirelessSource.swift` e `Native/WirelessBridge.m`: ricevitore, abbinamento, decoder e ciclo di vita del flusso.
- `Sources/ScreenSource.swift`: acquisizione tramite selettore nativo macOS.
- `Sources/VideoExporter.swift`: esportazione dei video con composizione.
- `scripts/generate_icon.swift`: icona geometrica riproducibile, senza immagini o font esterni.
- `scripts/bundle_licenses.py`: testi delle licenze nel bundle.
- `scripts/release.py`: pacchetti locali di sorgenti e binario, informazioni sui sorgenti e checksum.

## Verifiche

`VALIDAZIONE.txt` distingue le prove attuali dai risultati storici. La suite completa della 1.3 è passata, compresi oscuramento, report, pacchetti creator e invalidazione OCR. Le verifiche precedenti della 1.2 sono conservate nel resoconto; build ottimizzata, firma e percorsi UI per privacy, report, pacchetti e taglio decimale sono verificati. Le prove USB e wireless con iPhone fisico riportate nei documenti risalgono al **17 ottobre 2026** e non sono state ripetute sulla build 7.

Le verifiche manuali ancora aperte comprendono nuovo collaudo iPhone, iPad, sessioni prolungate, cambi di orientamento, più dispositivi e primo avvio su un altro Mac. Restano assenti controllo remoto e ascolto audio dal vivo.

## Preparazione della distribuzione

`python3 scripts/release.py` esegue test e build e prepara in `.build/releases/1.3.1/` archivio sorgenti senza cronologia Git, ZIP dell’app, `SOURCE-INFO.txt` e checksum. L’opzione `--source-only` prepara solo i sorgenti nella sottocartella `source-only/` e non valida il programma. Nessuna delle due modalità pubblica file o cambia lo stato del repository remoto.

La pre-release usa una firma ad hoc, senza Developer ID o notarizzazione. L’integrità della firma è verificata; la valutazione locale `spctl --assess` la rifiuta con uscita 3. Un download può quindi essere bloccato da macOS. Restano aperti i punti di `RELEASE_CHECKLIST.txt`: provenienza dei contributi e delle risorse, disponibilità del nome, revisione della dipendenza FairPlay e conformità delle licenze. L’autorizzazione alla pubblicazione sperimentale non certifica questi aspetti.

La pagina della pre-release distribuisce ZIP dell’app, sorgenti corrispondenti senza `.git`, `SOURCE-INFO.txt` e checksum. I pacchetti derivano dal commit `d6e0bd84f334d3064c0e5e4af163254a08611cf4`, prima degli aggiornamenti documentali che ne annunciano la pubblicazione. La nuova preparazione isolata ha ricompilato le dipendenze ed eseguito 23 gruppi di test e build ottimizzata; i 653 hash del manifest sorgenti, i checksum e l’integrità della firma ad hoc sono verificati. Queste prove non sono un nuovo collaudo fisico né una verifica dei diritti.

`PROMO.txt` e `marketing/LAUNCH.md` contengono testi promozionali e bozze social; nessun post social è stato inviato. Il sito pubblico ora collega il download sperimentale e ne espone i limiti.

Le chiavi di abbinamento risiedono nei dati locali dell’app. Build, registrazioni personali e dati di abbinamento devono rimanere esclusi dai sorgenti distribuiti.

## Funzioni 1.3

`Sources/Privacy.swift`: maschere raster, suggerimenti OCR locali, editor.
`Sources/BugReport.swift`: report locali con allegati e OCR sanitizzato, originale opt-in.
`Sources/CreatorExport.swift`: pacchetti immagini/video atomici con tre formati e copertina.
`Sources/StudioTools.swift`: flussi UI, stili persistenti e proiezione delle annotazioni.
Le maschere immagine e video sono separate; gli stili non persistono dati della sorgente.

## Patch 1.3.1 e upstream

Aggiornati libplist 2.8.0 e OpenSSL 3.6.5; controlli sulle dimensioni e sullo stato dell’abbinamento PIN, con regressioni AddressSanitizer e scambio autenticato sintetico completo. Il confronto dei sorgenti ufficiali è ripetibile con `scripts/verify_upstream.py`; pin e impronte sono in `ThirdParty/upstream.json`.

`UPSTREAM_AUDIT.txt` registra ambito e limiti del controllo storico. Su autorizzazione del titolare, main è stato inizialmente sostituito con un solo commit radice della versione revisionata; sono poi seguiti commit per marketing e documentazione della pre-release. Backup e materiali di analisi sono conservati privatamente fuori dal progetto. La riscrittura non elimina cache del servizio o cloni precedenti e non cambia la provenienza del codice. Il ramo OpenSSL 3.6 termina il supporto il 1° novembre 2026, quindi va pianificata una migrazione. La pubblicazione sperimentale successiva non modifica l’ambito o i limiti dell’audit precedente.

## Presentazione pubblica

Landing bilingue: https://eliagentili.github.io/specchio-studio-site/ (italiano in `/it/`). Il repository pubblico `eliagentili/specchio-studio-site` contiene soltanto sito, immagini originali e licenza del sito, con una cronologia autonoma. Il repository dell’app `eliagentili/specchio-studio` è pubblico e ospita la pre-release sperimentale, i sorgenti e le note sulle verifiche ancora aperte.

`docs/` è la sorgente statica del sito; `scripts/build_site.py` rigenera le pagine EN/IT, `scripts/check_site.py` verifica collegamenti, metadati e integrità degli asset, `scripts/package_site.py` prepara una cartella isolata tramite elenco esplicito dei file ammessi. `marketing/SITE.md` descrive la manutenzione; `marketing/LAUNCH.md` raccoglie posizionamento, storyboard e bozze LinkedIn.
