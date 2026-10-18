# Specchio Studio — launch kit

Prepared for **Elia Gentili**, 18 October 2026. Current app: **1.4.0, build 8**. The website and public campaign copy are English; the app supports English and Italian. Campaign copy is a draft; no social post or outreach message has been sent. The product page now links to the free experimental prerelease [v1.4.0-preview.1](https://github.com/eliagentili/specchio-studio/releases/tag/v1.4.0-preview.1). The user authorized publication with the stated provenance, naming and wireless-library rights uncertainties still open. This is not a stable release or legal clearance. The app is signed ad hoc and not notarized; Gatekeeper assessment rejects the build.

## The position to own

**Your device. Ready to share.**

Specchio Studio turns iPhone and iPad captures into product demos, creator assets and clearer bug reports on your Mac.

The useful connection is the work after capture: presentation, selected privacy masks and organized exports. Show the actual files these workflows produce. Lead with a concrete task that someone already needs to finish.

| Audience | A concrete job | Lead with | Show as evidence |
| --- | --- | --- | --- |
| Mobile developers and indie makers | Demonstrate a new interaction | “Show what you built.” | A short composed video from a synthetic app flow |
| Developers and QA | Explain a reproducible issue | “Give the bug some context.” | An annotated screenshot beside report.md and OCR.txt |
| Product makers and content creators | Prepare one capture for several layouts | “Prepare all three formats together.” | Actual 9:16, 1:1 and 16:9 exports plus their cover |

The broad product page can cover all three. Each social post should demonstrate one job from start to finish.

## Make the author visible through the work

Use **“Created by Elia Gentili”** next to the product identity, in the footer and in demonstration end cards. Link to [Elia's GitHub profile](https://github.com/eliagentili). Do not add unverified job titles, employer affiliations, client work, awards or contact links.

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
6. Close with the free-release plan and current review status. For this experimental release, the action links to release notes with requirements, limitations, app ZIP, matching source and checksums. Elia's projects remain linked in the maker section.

Use the same wording in the README, page metadata and social card. The app and website repositories are now public. Keep the download link on the tagged release so visitors receive the correct app, source and signing information together. Do not add a disabled download button, fabricated waiting list, invented testimonials or a suggested price.

## GitHub presentation

**Repository description:**

> Native Mac studio for iPhone/iPad captures, demos, creator exports and bug reports. Local OCR and opaque masks. By Elia Gentili. Apple Silicon/macOS 14+.

**Suggested topics:** `macos`, `swift`, `swiftui`, `iphone`, `ipad`, `screen-capture`, `video`, `ocr`, `developer-tools`.

**Preview-page description:**

> Specchio Studio by Elia Gentili. Turn device captures into demos, creator assets and clearer bug reports on your Mac. Free experimental preview for Apple Silicon Macs.

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
| 50–60 s | Product name, author and platform/status | “Specchio Studio · Created by Elia Gentili · Mac preview · Free experimental release” |

An import-based walkthrough must be labeled as imported/synthetic content. To demonstrate real device capture, record a fresh USB/wireless session on the current build and document the tested device, OS and path first.

### Three useful short posts

- **The bug report:** show an ambiguous screenshot, the annotation step and the resulting local report folder. Include fake reproduction steps and clearly distinguish expected/actual results.
- **The creator package:** start from one image, show the package action, then compare the three actual outputs and cover. Make the aspect ratios readable at phone size.
- **The privacy control:** show a fake email, a manually confirmed mask, the output image and OCR.txt without that email. Say that suggestions need review. Do not claim automatic, exhaustive protection.

Record text large enough to read on mobile. Use captions and alt text. Avoid personal device names, real notifications, pairing keys and private source paths. Original recordings and audio may contain data even when the composed visual is masked.

## LinkedIn drafts — experimental release

The drafts below are ready for editorial review, not automatic posting. Attach a real, labeled demonstration. The intended product URL is [the product website](https://eliagentili.github.io/specchio-studio-site/). Verify that the page is live before using it in a post. These drafts announce an experimental download and must preserve its signing, hardware and rights limitations.

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
> A free experimental prerelease is available for Apple Silicon Macs on macOS 14+. Version 1.4 supports English and Italian; the app is not notarized. The release notes explain Gatekeeper rejection, pending hardware tests and the rights uncertainties that remain open.
>
> If you build mobile apps, which part of preparing a demo or reporting a bug takes you the most effort today?
>
> Elia Gentili
> https://eliagentili.github.io/specchio-studio-site/
>
> #SwiftUI #macOS #MobileDevelopment

### Follow-up · one workflow

> Three proportions. The same idea.
>
> Specchio Studio turns an image or video into a creator folder with 9:16, 1:1 and 16:9 versions, a cover and a file manifest.
>
> This demo shows actual exports from synthetic content. Image exports support annotations; video exports support composition, trimming and fixed privacy masks.
>
> The goal is simple: prepare the files you need to share in one workflow.
>
> A project by Elia Gentili. Free experimental preview for Apple Silicon Macs, macOS 14+, with English and Italian interface choices. It is not notarized. Requirements, limits and unresolved rights questions are explained on the release page.
>
> https://eliagentili.github.io/specchio-studio-site/

## Later stable-release copy — pending completed review

Use this section only after the release checklist has been resolved, a clean-Mac launch has been verified and the actual release URL provides the binary, corresponding source, requirements and known limitations.

**Opening:** “I've released the first stable version of Specchio Studio, a free Mac app for turning iPhone and iPad captures into demos, creator assets and bug reports.”

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
| Experimental preview | English product page, README, synthetic visuals and tagged release | Free experimental download with requirements, signing and open rights limitations |
| Product proof | Fresh current-build hardware demos and first-user task observations | Record device/OS, outcome and failures |
| Stable release | Final package, source, checksums and public documentation | Resolve rights, name, licensing, dependency, signing and distribution checks |
| Portfolio story | A case study by Elia with one complete workflow | Use observed results and documented decisions |
| Follow-up | One focused demonstration per post | Answer actual questions and show improvements |

Use the product page as the stable destination once public and verified. Choose a few relevant communities only where sharing is appropriate; permission to prepare this kit is not permission to post or send messages. A personal GitHub profile pin can help after the relevant repository is public and the current content is ready to show.

## Claims and evidence

| Safe statement for this preview | Important boundary |
| --- | --- |
| “Free experimental prerelease available” | Signed ad hoc, not notarized; rights and hardware review remain open |
| “Native macOS app by Elia Gentili” | Apple Silicon, macOS 14+, English and Italian interface choices; included dependencies retain their authorship |
| “Local media processing and OCR” | Files and original recordings still need review before sharing |
| “Opaque masks applied to applicable exports” | Suggestions are incomplete; video masks are static; audio/originals/manual report text are not automatically redacted |
| “Automated media, export and language checks” | Quote the current validation results; synthetic fixtures do not cover all devices, networks, durations or UI flows |
| “Creator exports in three aspect ratios” | Do not promise that this capability is unique |
| “Bug reports with organized local attachments” | No automatic issue submission or integration with external trackers |

The rights and release review remains material: code/resource provenance, name availability, licenses, the [upstream FairPlay uncertainty](https://github.com/FDH2/UxPlay/blob/4e95a9ec013c52d8555d88dbc55abe346e94d56e/README.md#disclaimer), signing, notarization and final hardware trials are unresolved. See [the release checklist](../RELEASE_CHECKLIST.txt), [validation record](../VALIDAZIONE.txt) and [upstream audit](../UPSTREAM_AUDIT.txt). A marketing preview does not resolve them.
