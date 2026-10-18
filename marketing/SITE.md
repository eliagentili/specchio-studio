# Website maintenance

The public preview is https://eliagentili.github.io/specchio-studio-site/ with Italian at `/it/`.

Its public repository is https://github.com/eliagentili/specchio-studio-site. The website has a separate history and contains no app sources, binary, native receiver, dependency archive or private audit material. The application repository is public, with experimental release v1.3.1-preview.1 at https://github.com/eliagentili/specchio-studio/releases/tag/v1.3.1-preview.1. The first release was authorized with provenance, naming and wireless-library rights questions explicitly unresolved. The release remains experimental, signed ad hoc and not notarized.

## Update and preview

Edit bilingual copy and shared markup in `scripts/build_site.py`. Edit styles in `docs/styles.css` and interactions in `docs/site.js`. Pages are generated into `docs/`:

```sh
python3 scripts/build_site.py
python3 scripts/check_site.py
python3 -m http.server 8766 --bind 127.0.0.1 --directory docs
```

Inspect `/` and `/it/` at desktop and mobile widths. Verify keyboard tabs, privacy illustration, FAQ and the no-JavaScript fallback. System fonts, reduced-motion handling and semantic HTML are intentional. Avoid third-party embeds, remote fonts and trackers unless the privacy text is updated to match.

Original marketing artwork can be regenerated with:

```sh
swift scripts/generate_marketing_assets.swift --render-demo
```

This compiles a local renderer with the actual app canvas. It does not capture a connected device. `docs/assets/provenance.json` records descriptions, source artwork and asset hashes. Social cards are 1200 × 630. Their visibility in third-party previews may depend on those services’ caches.

## Stage the website independently

Use a new, empty destination **outside the application checkout**:

```sh
python3 scripts/package_site.py /absolute/path/to/new-empty-site-staging
```

The packager checks the site, copies an exact list of approved files and writes a manifest to stdout. It uses `marketing/SITE_README.md` as the public website README. It never copies app source or its Git history. Review the staged tree before synchronizing those same approved files with the website checkout; do not copy the entire app checkout.

The public repo uses GitHub Pages from `main`, repository root, with HTTPS. `.nojekyll` preserves the plain static site. Keep the canonical base and all language/social URLs synchronized if the repository path ever changes. Publication should be verified with an unauthenticated HTTP request and the Pages build status.

## Verified on 18 October 2026

- English desktop and Italian 393-pixel mobile layouts inspected in Chrome.
- Workflow tabs changed correctly with click and arrow keys; the privacy illustration changed its label, state and example data.
- With JavaScript disabled, all three workflow descriptions remained readable and the inactive illustration button was hidden.
- Five HTML pages, local paths/fragments, bilingual SEO, script syntax and all 12 asset hashes passed `scripts/check_site.py`.
- Independent static review confirmed the website-only publication boundary.

These checks validate the website and its presentation. They do not validate hardware capture or establish app distribution rights. Real device demos and download CTAs must reflect the current app verification and release status. The CTA links to the release notes, which explain Gatekeeper rejection and the open rights questions before the user selects an asset.
