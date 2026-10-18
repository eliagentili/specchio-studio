# Stato del progetto

Aggiornato il **18 ottobre 2026**. Versione **1.3.1, build 7**, arm64, target macOS 14. Preparazione locale per revisione; pubblicazione ancora da approvare dopo la chiusura dei punti aperti.

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

La build locale è firmata ad hoc e non notarizzata. Per il rilascio devono essere chiusi i punti di `RELEASE_CHECKLIST.txt`: provenienza dei contributi e delle risorse, disponibilità del nome, revisione della dipendenza FairPlay, conformità delle licenze e distribuzione dei sorgenti corrispondenti.

L’archivio senza `.git` può essere valutato per una futura distribuzione pubblica solo dopo la revisione dei diritti. La sua preparazione non modifica il repository. `PROMO.txt` è una bozza non pubblicata.

Le chiavi di abbinamento risiedono nei dati locali dell’app. Build, registrazioni personali e dati di abbinamento devono rimanere esclusi dai sorgenti distribuiti.

## Funzioni 1.3

`Sources/Privacy.swift`: maschere raster, suggerimenti OCR locali, editor.
`Sources/BugReport.swift`: report locali con allegati e OCR sanitizzato, originale opt-in.
`Sources/CreatorExport.swift`: pacchetti immagini/video atomici con tre formati e copertina.
`Sources/StudioTools.swift`: flussi UI, stili persistenti e proiezione delle annotazioni.
Le maschere immagine e video sono separate; gli stili non persistono dati della sorgente.

## Patch 1.3.1 e upstream

Aggiornati libplist 2.8.0 e OpenSSL 3.6.5; controlli sulle dimensioni e sullo stato dell’abbinamento PIN, con regressioni AddressSanitizer e scambio autenticato sintetico completo. Il confronto dei sorgenti ufficiali è ripetibile con `scripts/verify_upstream.py`; pin e impronte sono in `ThirdParty/upstream.json`.

`UPSTREAM_AUDIT.txt` registra ambito e limiti del controllo. Su autorizzazione del titolare, main è stato sostituito con un solo commit radice della versione revisionata. Backup e materiali di analisi sono conservati privatamente fuori dal progetto. La riscrittura non elimina cache del servizio o cloni precedenti e non cambia la provenienza del codice. Il ramo OpenSSL 3.6 termina il supporto il 1° novembre 2026, quindi va pianificata una migrazione. Non è stata pubblicata una release o modificata la visibilità del repository.
