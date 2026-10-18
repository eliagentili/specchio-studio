# Specchio Studio — launch kit

Prepared for **Elia Gentili**, 18 October 2026. Current app: **1.3.1, build 7**. Campaign copy is a draft; no social post or outreach message has been sent. The product page presents a preview. The planned app release is free, with no public app download currently available.

## The position to own

**Your device. Ready to share.**

Specchio Studio turns iPhone and iPad captures into product demos, creator assets and clearer bug reports on your Mac.

Italian:

**Il tuo dispositivo. Pronto da condividere.**

Specchio Studio trasforma le acquisizioni di iPhone e iPad in demo di prodotto, contenuti e segnalazioni bug più chiare, dal Mac.

The useful connection is the work after capture: presentation, selected privacy masks and organized exports. Show the actual files these workflows produce. Lead with a concrete task that someone already needs to finish.

| Audience | A concrete job | Lead with | Show as evidence |
| --- | --- | --- | --- |
| Mobile developers and indie makers | Demonstrate a new interaction | “Show what you built.” | A short composed video from a synthetic app flow |
| Developers and QA | Explain a reproducible issue | “Give the bug some context.” | An annotated screenshot beside report.md and OCR.txt |
| Product makers and content creators | Prepare one capture for several layouts | “Prepare all three formats together.” | Actual 9:16, 1:1 and 16:9 exports plus their cover |

The broad product page can cover all three. Each social post should demonstrate one job from start to finish.

## Make the author visible through the work

Use **“Created by Elia Gentili”** / **“Creato da Elia Gentili”** next to the product identity, in the footer and in demonstration end cards. Link to [Elia's GitHub profile](https://github.com/eliagentili). Do not add unverified job titles, employer affiliations, client work, awards or contact links.

The portfolio story should connect each technical decision to what a user receives:

| Work | User-facing result | Portfolio discussion |
| --- | --- | --- |
| SwiftUI and AppKit | A native Mac workspace | State, permissions and task lifecycle |
| AVFoundation and VideoToolbox | Capture, recording and composed exports | Codec transitions, audio, trimming and cancellation |
| Vision and opaque pixel masking | Local OCR and inspectable privacy controls | OCR races, coordinate systems and reviewing suggestions |
| Structured export workflows | Creator folders and Markdown/JSON bug reports | File integrity, output manifests and cleanup on failure |

Describe the work and its tests. Do not imply every included dependency was authored by Elia; preserve upstream attributions.

## The product-page sequence

1. Lead with the result, a clearly labeled synthetic product visual and a short platform/status line.
2. Let the visitor choose a familiar job: demo, creator package or bug report.
3. Show the actual workflow and the files it creates.
4. Explain local processing and reviewable masks, with the static-video-mask limitation nearby.
5. Introduce Elia and the technical work behind the experience.
6. Close with the free-release plan and current review status. During preview, the action is to explore the workflow or Elia's projects. After release, it becomes downloading the verified release and its matching source.

Use the same wording in the README, page metadata and social card. A public product preview can coexist with a private app repository; do not expose private-source links as if visitors can use them. Do not add a disabled download button, fabricated waiting list, invented testimonials or a suggested price.

## GitHub presentation

**Repository description:**

> Native Mac studio for iPhone/iPad captures, demos, creator exports and bug reports. Local OCR and opaque masks. By Elia Gentili. Apple Silicon/macOS 14+.

**Suggested topics:** `macos`, `swift`, `swiftui`, `iphone`, `ipad`, `screen-capture`, `video`, `ocr`, `developer-tools`.

**Preview-page description:**

> Specchio Studio by Elia Gentili. Turn device captures into demos, creator assets and clearer bug reports on your Mac. A preview of a planned free app.

The README should give visitors the result first, then setup, evidence and limits. Keep current version, platform and availability accurate. Do not add stars, download counts, review scores or performance numbers without a verifiable source.

## Demonstration plan

Create one concise visual walkthrough with synthetic data, then three smaller demonstrations. The durations below are editorial targets, not claims about app performance. Use the current app, visibly follow real steps and label any edited waiting time. Show the app's actual behavior.

### Main walkthrough: about 45–60 seconds

| Segment | What to show | On-screen copy |
| --- | --- | --- |
| 0–5 s | Final composed screenshot and output files | “Your device. Ready to share.” |
| 5–15 s | Import a synthetic source image or record a synthetic app flow | “Start with a capture.” |
| 15–25 s | Draw a mask over a fake email; review the result | “Cover selected details.” |
| 25–38 s | Export a creator package and open all three actual outputs | “Portrait. Square. Landscape.” |
| 38–50 s | Annotate the image, enter a short bug description, export and open report.md | “Give the issue context.” |
| 50–60 s | Product name, author and platform/status | “Specchio Studio · Created by Elia Gentili · Mac preview · Planned free release” |

An import-based walkthrough must be labeled as imported/synthetic content. To demonstrate real device capture, record a fresh USB/wireless session on the current build and document the tested device, OS and path first.

### Three useful short posts

- **The bug report:** show an ambiguous screenshot, the annotation step and the resulting local report folder. Include fake reproduction steps and clearly distinguish expected/actual results.
- **The creator package:** start from one image, show the package action, then compare the three actual outputs and cover. Make the aspect ratios readable at phone size.
- **The privacy control:** show a fake email, a manually confirmed mask, the output image and OCR.txt without that email. Say that suggestions need review. Do not claim automatic, exhaustive protection.

Record text large enough to read on mobile. Use captions and alt text. Avoid personal device names, real notifications, pairing keys and private source paths. Original recordings and audio may contain data even when the composed visual is masked.

## LinkedIn drafts — preview stage

The drafts below are ready for editorial review, not automatic posting. Attach a real, labeled demonstration. The intended product URL is [the English preview](https://eliagentili.github.io/specchio-studio-site/) and [the Italian preview](https://eliagentili.github.io/specchio-studio-site/it/). Verify that the page is live before using it in a post. These drafts do not announce a downloadable app.

### Italian · initial presentation

> Uno screenshot mostra un’interfaccia. Per farne una demo o spiegare un bug serve anche il lavoro che viene dopo.
>
> Ho creato **Specchio Studio** per riunire quel lavoro sul Mac: acquisire lo schermo, preparare la composizione, coprire dettagli selezionati ed esportare i file da condividere.
>
> I tre percorsi su cui ho lavorato:
>
> - demo video con sfondo, cornice e taglio;
> - pacchetti creator in 9:16, 1:1 e 16:9, con copertina;
> - segnalazioni bug con screenshot annotato, OCR e report Markdown/JSON.
>
> L’elaborazione dei media e l’OCR avvengono sul Mac. Le maschere sono controlli espliciti da verificare; nei video restano fisse e non seguono il movimento.
>
> Dal lato tecnico, il progetto mi ha portato a lavorare su SwiftUI, AVFoundation, VideoToolbox e Vision, insieme ai casi meno visibili: audio, orientamento, annullamento degli export e integrità dei file.
>
> Il rilascio previsto è gratuito. Per ora condivido un’anteprima: l’app è ancora in revisione e non ha un download pubblico.
>
> Sviluppate app mobile? Quale di questi passaggi vi fa perdere più tempo oggi?
>
> Elia Gentili
> https://eliagentili.github.io/specchio-studio-site/it/
>
> #SwiftUI #macOS #MobileDevelopment

### English · initial presentation

> A screenshot shows an interface. Turning it into a useful demo or bug report takes a few more steps.
>
> I created **Specchio Studio** to bring those steps together on the Mac: capture a screen, compose the result, cover selected details and export the files you need.
>
> Three workflows shape the app:
>
> - composed video demos with trimming;
> - creator packages in 9:16, 1:1 and 16:9, with a cover;
> - bug reports with annotated screenshots, local OCR, Markdown and JSON.
>
> Media processing and OCR run on the Mac. Privacy masks are explicit controls to review; video masks are fixed areas, without motion tracking.
>
> Building this brought together SwiftUI, AVFoundation, VideoToolbox and Vision, plus the less visible work around audio, orientation, export cancellation and file integrity.
>
> I plan to release it for free. This is a preview: the app is still under review, with no public download yet. Its current interface is Italian, targeting Apple Silicon Macs on macOS 14+.
>
> If you build mobile apps, which part of preparing a demo or reporting a bug takes you the most effort today?
>
> Elia Gentili
> https://eliagentili.github.io/specchio-studio-site/
>
> #SwiftUI #macOS #MobileDevelopment

### Italian · follow-up about one workflow

> Tre proporzioni, lo stesso contenuto.
>
> Nel pacchetto creator di Specchio Studio, un’immagine o un video diventa una cartella con versioni 9:16, 1:1 e 16:9, una copertina e un riepilogo dei file.
>
> Nella demo mostro gli export reali da contenuto sintetico: nessun dato personale. Le annotazioni sono per le immagini; i video supportano composizione, taglio e maschere fisse.
>
> L’obiettivo è semplice: preparare gli allegati da condividere nello stesso flusso di lavoro.
>
> Un progetto di Elia Gentili. Anteprima per Mac, rilascio gratuito previsto; download pubblico non ancora disponibile.
>
> https://eliagentili.github.io/specchio-studio-site/it/

## Later release copy — blocked on a verified release

Use this section only after the release checklist has been resolved, a clean-Mac launch has been verified and the actual release URL provides the binary, corresponding source, requirements and known limitations.

**IT opening:** “Ho pubblicato Specchio Studio, un’app gratuita per Mac che trasforma acquisizioni di iPhone e iPad in demo, contenuti e segnalazioni bug.”

**EN opening:** “I've released Specchio Studio, a free Mac app for turning iPhone and iPad captures into demos, creator assets and bug reports.”

Follow with one demonstrated workflow and a real release link. State Apple Silicon, minimum macOS, interface language and signing/notarization status applicable to that release. Do not describe the app as universally compatible, commercially validated or legally risk-free.

## Validate value without charging

Recruit **5–8 people** who currently develop or test mobile apps for an initial qualitative round. This is a study plan, not an existing user count. Ask each person to complete one familiar job using synthetic or approved content, then compare with their usual method.

| Question | Observe | Record without embellishment |
| --- | --- | --- |
| Can a new user finish the job? | Connect/import, prepare and export without coaching | Completed steps, confusion and any failures |
| Does it reduce effort? | The same task with their usual tools and the app | Time measured per task, interventions and output quality |
| Is the output useful? | The recipient reads the demo/report | Missing context and changes needed before sharing |
| Is there recurring value? | A return to a real job during the following week | Actual reuse and which workflow was used |
| Would they pay for this job to be easier? | Ask after use, while explaining the app stays free | Alternatives, objections and an optional price range |

Use neutral prompts: “Show me the last time you needed to do this,” “What would you change before sending this?” and “What would you use instead?” Hypothetical willingness to pay is useful context, not a sale or proof of demand. Repeated use and independently finished tasks are stronger signals. Obtain permission before quoting or naming anyone; never invent testimonials.

After the round, publish a short case study with the task, environment, sample size, observations, changes made and limits. Do not convert a small qualitative group into market-wide conversion statistics.

## Launch sequence

| Stage | Deliverable | Condition |
| --- | --- | --- |
| Preview | Bilingual product page, README and synthetic workflow visuals | Accurate status; no app download promises |
| Product proof | Fresh current-build hardware demos and first-user task observations | Record device/OS, outcome and failures |
| Release | Verified package, source, checksums and public documentation | Resolve rights, name, licensing, dependency and distribution checks |
| Portfolio story | A case study by Elia with one complete workflow | Use observed results and documented decisions |
| Follow-up | One focused demonstration per post | Answer actual questions and show improvements |

Use the product page as the stable destination once public and verified. Choose a few relevant communities only where sharing is appropriate; permission to prepare this kit is not permission to post or send messages. A personal GitHub profile pin can help after the relevant repository is public and the current content is ready to show.

## Claims and evidence

| Safe statement for this preview | Important boundary |
| --- | --- |
| “Designed for a free release” | No public app download currently available |
| “Native macOS app by Elia Gentili” | Apple Silicon, macOS 14+, current interface in Italian; included dependencies retain their authorship |
| “Local media processing and OCR” | Files and original recordings still need review before sharing |
| “Opaque masks applied to applicable exports” | Suggestions are incomplete; video masks are static; audio/originals/manual report text are not automatically redacted |
| “23 automated test groups passed for 1.3.1” | Synthetic fixtures and specific paths; not all devices, networks, durations or UI flows |
| “Creator exports in three aspect ratios” | Do not promise that this capability is unique |
| “Bug reports with organized local attachments” | No automatic issue submission or integration with external trackers |

The rights and release review remains material: code/resource provenance, name availability, licenses, the [upstream FairPlay uncertainty](https://github.com/FDH2/UxPlay/blob/4e95a9ec013c52d8555d88dbc55abe346e94d56e/README.md#disclaimer), signing, notarization and final hardware trials are unresolved. See [the release checklist](../RELEASE_CHECKLIST.txt), [validation record](../VALIDAZIONE.txt) and [upstream audit](../UPSTREAM_AUDIT.txt). A marketing preview does not resolve them.
