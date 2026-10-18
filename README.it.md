# Specchio Studio

### Il tuo dispositivo. Pronto da condividere.

Trasforma le acquisizioni di iPhone e iPad in **demo di prodotto, contenuti e segnalazioni bug più chiare**, dal Mac.

Creato da [**Elia Gentili**](https://github.com/eliagentili) · App nativa macOS · Elaborazione dei media locale

[Scopri il prodotto](https://eliagentili.github.io/specchio-studio-site/it/) · [English](README.md) · [Guida all’uso](LEGGIMI.txt) · [Verifiche](VALIDAZIONE.txt)

<p align="center">
  <img src="docs/assets/github-banner.png" alt="Specchio Studio — Il tuo dispositivo. Pronto da condividere. Creato da Elia Gentili." width="900">
</p>

**Anteprima · 1.3.1, build 7 · Apple Silicon · macOS 14 o successivo.** Il rilascio previsto è gratuito. L’app è in revisione e non è ancora disponibile un download pubblico.

## Un’acquisizione. Tre risultati utili.

Acquisire lo schermo è il primo passo. Specchio Studio riunisce il lavoro successivo: comporre il risultato, coprire dettagli selezionati, spiegare un problema e generare i file che servono.

| Quando vuoi… | Con Specchio Studio puoi… | Ottieni… |
| --- | --- | --- |
| Mostrare ciò che hai sviluppato | Registrare, tagliare, scegliere uno sfondo e una cornice generica | Una demo video composta, con audio della sorgente quando disponibile |
| Preparare contenuti per più formati | Esportare un pacchetto creator da un’immagine o un video | Verticale **9:16**, quadrato **1:1**, orizzontale **16:9**, copertina e riepilogo dei file |
| Spiegare un bug con chiarezza | Annotare uno screenshot e aggiungere passaggi, risultato atteso e osservato | Una cartella locale con immagini, testo OCR e report **Markdown e JSON** |

<p align="center">
  <img src="docs/assets/formats-proof.webp" alt="Composizioni reali del canvas demo nei formati 9:16, 1:1 e 16:9; grafica sintetica, senza un dispositivo fisico collegato" width="900">
</p>

## Acquisisci, prepara, esporta

- **Porta uno schermo nello Studio.** Collega iPhone o iPad via USB o tramite il ricevitore wireless dedicato, acquisisci una finestra o uno schermo del Mac, oppure importa un’immagine o un video locale.
- **Cura la presentazione.** Scegli sfondo, cornice generica, rotazione, specchio e formato. Annota le immagini. Salva l’aspetto come stile riutilizzabile.
- **Copri i dettagli selezionati.** Disegna rettangoli opachi oppure controlla i suggerimenti OCR locali per email, telefoni e possibili chiavi. Le maschere confermate si applicano alle immagini esportate, ai video composti e all’OCR dei report.
- **Elabora i media sul Mac.** Registrazione, composizione e OCR usano framework nativi. Non servono un account nell’app o un servizio cloud di elaborazione.
- **Scegli l’uscita adatta.** Registra la sorgente in MOV H.264 o HEVC; esporta video H.264 composti con taglio e audio quando presente. Salva immagini singole o genera insieme i tre formati creator.

I preset video creator sono **1080 × 1920**, **1080 × 1080** e **1920 × 1080**. Le immagini usano le stesse dimensioni di base, con scala di esportazione disponibile. Con lo zoom Adatta, la sorgente viene adattata alla composizione. La registrazione mantiene il formato della sorgente; cornice e maschere privacy si applicano nella fase separata di composizione/esportazione.

### Controlli privacy da verificare sul risultato

Le maschere sostituiscono i pixel con aree opache negli export interessati. L’OCR dei report legge lo screenshot oscurato. L’originale senza maschere è **escluso dalla cartella del report per impostazione iniziale** e richiede una scelta esplicita.

Controlla i file prima di condividerli: i suggerimenti OCR possono non rilevare tutti i dati sensibili. Nei video le maschere sono **rettangoli fissi per l’intera clip selezionata**, senza inseguimento del movimento. Registrazioni originali, audio e testo scritto manualmente nei report non vengono oscurati automaticamente. Annotazioni e zoom si applicano agli export delle immagini, non ai video. Gli stili salvati contengono l’aspetto, senza acquisizioni, maschere o testo riconosciuto.

## Compila e prova in locale

Servono un **Mac Apple Silicon con macOS 14+**, gli Apple Command Line Tools (`swiftc`, `clang`) e Python 3 disponibile come `python3`. Le dipendenze native sono incluse; non serve Homebrew. L’interfaccia attuale è in italiano.

```sh
./build.sh
open "Specchio Studio.app"
```

La build locale usa una **firma ad hoc e non è notarizzata**. Per ricompilare OpenSSL dai sorgenti inclusi esegui `./Native/build_crypto.sh` prima di `./build.sh`; servono anche Perl e make.

Per USB, sblocca il dispositivo, autorizza il Mac e scegli **Rileva USB → Connetti**. Per il wireless, attiva **Wireless**, scegli **Specchio Studio** in Duplica schermo sul dispositivo e inserisci il codice mostrato quando richiesto. Parti dalla stessa rete Wi-Fi. I permessi macOS dipendono dalla sorgente scelta.

La [guida completa](LEGGIMI.txt) descrive permessi, registrazione, composizione ed export. Una sola finestra per processo può attivare il ricevitore wireless.

## Verifiche concrete, revisione ancora aperta

La suite corrente 1.3.1 ha superato **23 gruppi di test automatici** con fixture sintetiche, compresi percorsi di acquisizione e codec, regressioni dell’abbinamento wireless, maschere, OCR, report ed export creator. Questi risultati verificano percorsi specifici, non ogni dispositivo, rete o durata di utilizzo.

```sh
./test.sh
# Compila i test senza eseguirli:
./test.sh --build-only
```

I risultati sono in `.build/test-results`. I test completi richiedono accesso ai normali servizi multimediali di macOS. [VALIDAZIONE.txt](VALIDAZIONE.txt) separa test automatici correnti, verifiche UI precedenti e prove con iPhone fisico del **17 ottobre 2026**. Quelle prove hardware non sono state ripetute sulla build 7. Restano aperti i collaudi della build corrente con iPhone/iPad, sessioni lunghe, cambi di orientamento, più dispositivi e primo avvio su un altro Mac.

L’app è destinata a **macOS su Apple Silicon**. Non sono disponibili build Windows, Linux o Intel Mac. Non sono implementati controllo remoto del dispositivo, ascolto audio dal vivo, montaggio multiclip o export video con alpha. I contenuti protetti potrebbero non essere acquisibili.

## Rilascio, sorgenti e licenze

Il rilascio previsto è **gratuito**. La pubblicazione di un’anteprima del prodotto non equivale al rilascio pubblico dell’app e non chiude le verifiche necessarie.

Prima di distribuire l’app vanno risolti i punti aperti sulla provenienza di codice e risorse, disponibilità del nome, obblighi di licenza e dipendenza FairPlay del ricevitore: [UxPlay documenta un’incertezza legale sulla libreria](https://github.com/FDH2/UxPlay/blob/4e95a9ec013c52d8555d88dbc55abe346e94d56e/README.md#disclaimer). Le licenze open source da sole non dimostrano tutti i diritti necessari. Restano aperti anche firma Developer ID, notarizzazione e collaudi hardware finali. Vedi [RELEASE_CHECKLIST.txt](RELEASE_CHECKLIST.txt).

Il progetto dichiara **GPL-3.0-or-later**. I componenti di terze parti conservano copyright e licenze propri. Vedi [LICENSE](LICENSE) e [ThirdParty/NOTICE.txt](ThirdParty/NOTICE.txt); i testi sono inclusi anche nell’app. Per distribuire un binario occorre rendere disponibili i sorgenti corrispondenti di quella build secondo le licenze applicabili.

| Documento | Contenuti |
| --- | --- |
| [LEGGIMI.txt](LEGGIMI.txt) | Istruzioni complete d’uso e compilazione |
| [VALIDAZIONE.txt](VALIDAZIONE.txt) | Verifiche svolte, date e scenari ancora da provare |
| [UPSTREAM_AUDIT.txt](UPSTREAM_AUDIT.txt) | Confronti con sorgenti ufficiali, modifiche locali e limiti dell’audit |
| [PROJECT_STATUS.md](PROJECT_STATUS.md) | Architettura e stato del progetto |
| [RELEASE_CHECKLIST.txt](RELEASE_CHECKLIST.txt) | Verifiche ancora aperte per la distribuzione |
| [Kit di lancio](marketing/LAUNCH.md) | Posizionamento, piano demo e bozze non pubblicate |

`python3 scripts/release.py` prepara pacchetti locali ricompilando le dipendenze ed eseguendo test e build da una copia isolata. `--source-only` prepara i soli sorgenti senza validare l’app. Pacchetti e checksum vengono salvati in `.build/releases/1.3.1/`. Nessun comando pubblica file. Il confronto upstream è ripetibile con `python3 scripts/verify_upstream.py --download` oppure `--offline`. Il ramo OpenSSL 3.6 incluso termina il supporto il **1° novembre 2026**; la migrazione resta un’attività di manutenzione da chiudere per il rilascio.

## Un progetto di Elia Gentili

Specchio Studio unisce acquisizione nativa, elaborazione multimediale e flussi di esportazione pratici. È un progetto portfolio costruito attorno a un compito concreto: aiutare una persona a mostrare ciò che ha realizzato e spiegare ciò che va corretto.

[Esplora l’anteprima del prodotto](https://eliagentili.github.io/specchio-studio-site/it/) · [Altri progetti di Elia su GitHub](https://github.com/eliagentili)
