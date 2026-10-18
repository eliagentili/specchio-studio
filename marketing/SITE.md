# Website maintenance

The public preview is https://eliagentili.github.io/specchio-studio-site/ in English. Existing `/it/` and `/it/privacy.html` URLs redirect to their English equivalents. The app itself supports English and Italian from version 1.4.

Its public repository is https://github.com/eliagentili/specchio-studio-site. The website has a separate history and contains no app sources, binary, native receiver, dependency archive or private audit material. The application repository is public, with experimental release v1.4.0-preview.1 at https://github.com/eliagentili/specchio-studio/releases/tag/v1.4.0-preview.1. The first release was authorized with provenance, naming and wireless-library rights questions explicitly unresolved. The release remains experimental, signed ad hoc and not notarized.

## Update and preview

Edit English copy and shared markup in `scripts/build_site.py`. Edit styles in `docs/styles.css` and interactions in `docs/site.js`. Pages are generated into `docs/`:

```sh
python3 scripts/build_site.py
python3 scripts/check_site.py
python3 -m http.server 8766 --bind 127.0.0.1 --directory docs
```

Inspect `/` and `/privacy.html` at desktop and mobile widths. Check that `/it/` and `/it/privacy.html` redirect to the correct English pages without JavaScript. Verify keyboard tabs, privacy illustration, FAQ and the no-JavaScript fallback. System fonts, reduced-motion handling and semantic HTML are intentional. Avoid third-party embeds, remote fonts and trackers unless the privacy text is updated to match.

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

The public repo uses GitHub Pages from `main`, repository root, with HTTPS. `.nojekyll` preserves the plain static site. Keep the canonical base and all canonical/social URLs synchronized if the repository path ever changes. Publication should be verified with an unauthenticated HTTP request and the Pages build status.

## Verification before publication

Run `scripts/check_site.py` after generating pages or assets. The checker verifies English language metadata, canonical URLs, two script-free legacy redirects, local paths/fragments, script syntax and every published asset hash. The packaging allowlist excludes all app source and private material.

Inspect the landing at desktop and mobile widths. Verify workflow tabs with click and arrow keys, the privacy illustration, FAQ and the no-JavaScript fallback. Product artwork must be regenerated after changes to the actual demo canvas so no outdated Italian captions remain embedded in images. The website and its social artwork use English; the app has its own language setting.

These checks validate the website and its presentation. They do not validate hardware capture or establish app distribution rights. Real device demos and download CTAs must reflect the current app verification and release status. Publish app release v1.4.0-preview.1 before publishing this website update: its CTA links to those release notes, with Gatekeeper rejection and the open rights questions explained before visitors select an asset.
