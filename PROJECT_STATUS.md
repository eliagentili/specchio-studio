# Project status

Updated on **18 October 2026**. Published version: **1.3.1, build 7**, arm64, macOS 14 target. The first **[free experimental pre-release v1.3.1-preview.1](https://github.com/eliagentili/specchio-studio/releases/tag/v1.3.1-preview.1)** was published at the owner’s explicit choice with the uncertainties disclosed. Publication does not close the rights review, hardware validation or notarization work.

Development version: **1.4.0, build 8**, adding English and Italian app localization. English is the default, with an explicit language preference and a system-language option. Validation and publication of this development build are still in progress. Public website and first-party documentation are being standardized on English.

## Features

USB, dedicated wireless and window/screen capture; H.264/HEVC MOV recording with source audio when available; screenshots, composition, annotations, local OCR, and H.264 video export with audio and time trimming.

The current icon and demo image are reproducible from included code: `scripts/generate_icon.swift` and the rendering in `Tests/StudioTests.swift`. This does not replace review of the initial contributions’ provenance.

Automatic, Portrait 9:16, Square 1:1 and Landscape 16:9 formats are shared by screenshots and videos. Video presets export at 1080×1920, 1080×1080 and 1920×1080 pixels. Screenshot export scale multiplies these dimensions.

## Entry points

- `Sources/App.swift`: app startup and commands.
- `Sources/StudioView.swift`: Studio interface and workflows.
- `Sources/Canvas.swift`: composition and output formats.
- `Sources/CaptureEngine.swift`: capture, snapshots and recording.
- `Sources/WirelessSource.swift` and `Native/WirelessBridge.m`: receiver, pairing, decoders and stream lifecycle.
- `Sources/ScreenSource.swift`: capture through the native macOS picker.
- `Sources/VideoExporter.swift`: composed video export.
- `scripts/generate_icon.swift`: reproducible geometric icon, without external images or fonts.
- `scripts/bundle_licenses.py`: license texts in the app bundle.
- `scripts/release.py`: local source and binary packages, source information and checksums.

## Validation

`VALIDAZIONE.txt` distinguishes current tests from historical results. The complete 1.3 suite passed, including redaction, reports, creator packs and OCR invalidation. Earlier 1.2 checks are preserved in the report; the optimized build, signature and UI paths for privacy, reports, packs and decimal trimming were verified. The documented USB and wireless tests with a physical iPhone date from **17 October 2026** and were not repeated on build 7.

Open manual checks include renewed iPhone testing, iPad, long sessions, orientation changes, multiple devices and first launch on another Mac. Remote control and live audio monitoring remain unavailable. The bilingual development build still needs its own recorded validation results.

## Distribution preparation

`python3 scripts/release.py` runs tests and a build, then prepares a source archive without Git history, an app ZIP, `SOURCE-INFO.txt` and checksums under the version’s directory in `.build/releases/`. The published 1.3.1 packages are in `.build/releases/1.3.1/`. The `--source-only` option prepares only source files in the `source-only/` subdirectory and does not validate the program. Neither mode publishes files or changes the remote repository state.

The pre-release uses an ad hoc signature, without Developer ID or notarization. Signature integrity is verified; local `spctl --assess` rejects it with exit code 3. macOS may therefore block a download. Items in `RELEASE_CHECKLIST.txt` remain open: contribution and asset provenance, name availability, FairPlay dependency review and license compliance. Authorization for experimental publication does not certify these matters.

The pre-release page distributes the app ZIP, corresponding source without `.git`, `SOURCE-INFO.txt` and checksums. Packages derive from commit `d6e0bd84f334d3064c0e5e4af163254a08611cf4`, before the documentation updates announcing publication. Fresh isolated preparation rebuilt dependencies and ran 23 test groups and an optimized build; the 653 source manifest hashes, checksums and ad hoc signature integrity were verified. These checks are neither new physical testing nor a rights review.

`PROMO.txt` and `marketing/LAUNCH.md` contain promotional copy and social drafts; no social posts have been sent. The public website links the experimental download and states its limitations.

Pairing keys reside in the app’s local data. Builds, personal recordings and pairing data must remain excluded from distributed source.

## 1.3 workflows

`Sources/Privacy.swift`: raster masks, local OCR suggestions and editor.
`Sources/BugReport.swift`: local reports with attachments and sanitized OCR; original image opt-in.
`Sources/CreatorExport.swift`: atomic image/video packs with three formats and a cover.
`Sources/StudioTools.swift`: UI workflows, persistent styles and annotation reprojection.
Image and video masks are separate; styles do not persist source data.

## Patch 1.3.1 and upstream

Updated to libplist 2.8.0 and OpenSSL 3.6.5; PIN pairing size/state checks added, with AddressSanitizer regressions and a complete synthetic authenticated exchange. Comparison with official source is repeatable through `scripts/verify_upstream.py`; pins and hashes are in `ThirdParty/upstream.json`.

`UPSTREAM_AUDIT.txt` records the historical review’s scope and limits. With the owner’s authorization, main was initially replaced by a single root commit of the reviewed version; marketing and pre-release documentation commits followed. Backups and analysis materials are kept privately outside the project. History rewriting does not remove service caches or previous clones and does not change code provenance. The OpenSSL 3.6 branch reaches end of support on 1 November 2026, so migration needs planning. Subsequent experimental publication does not change the scope or limits of the earlier audit.

## Public presentation

English landing page: [Specchio Studio](https://eliagentili.github.io/specchio-studio-site/). Former `/it/` links are retained for compatibility and lead to English content. The public `eliagentili/specchio-studio-site` repository contains only the website, original images and website license, with independent history. The `eliagentili/specchio-studio` app repository is public and hosts the experimental pre-release, source and notes on open validation work.

`docs/` contains the static website source; `scripts/build_site.py` regenerates English pages, `scripts/check_site.py` checks links, metadata and asset integrity, and `scripts/package_site.py` prepares an isolated directory through an explicit file allowlist. `marketing/SITE.md` describes maintenance; `marketing/LAUNCH.md` contains positioning, storyboards and LinkedIn drafts.
