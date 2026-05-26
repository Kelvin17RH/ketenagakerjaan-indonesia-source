# Step 3 — Dashboard

Bake the aggregated cube JSONs (from Step 2) into the deployable static dashboard.

## What's here

| File | Purpose |
| --- | --- |
| `dashboard_template.html` | The single-page-app source. Contains `__PLACEHOLDER__` markers where build_split.py injects cube JSON or substitutes empty stubs (large cubes are externalised to `data/*.json` for lazy fetch). |
| `build_split.py` | The baker: read template, substitute placeholders, write `index.html` (shell, ~2.7 MB) + `data/*.json` (~96 MB total). |
| `make_og_image.py` | Generates the 1200×630 PNG used as Open Graph preview image. Requires Pillow. |
| `serve.command` | macOS helper — double-click to start a local Python HTTP server on `:8000` (because browsers block `fetch()` over `file://` for the data cubes). |
| `_headers` | Netlify cache policy — long-cache `data/*.json` since they only change when we rebake. |
| `update_netlify_split.sh` | One-shot deploy: copy fresh files to the Netlify-watched repo and `git push`. Reads `$TOKEN` from env. |

## Build the dashboard

```bash
# From the project root
cd 03-dashboard
python build_split.py
# → ../outputs/index.html + ../outputs/data/{cube_10_24,cube_97_24,newvars_cube,newvars2_cube,medians_pair}.json
```

Verify with a local server:

```bash
./serve.command            # macOS — opens http://localhost:8000/ automatically
# or:
python3 -m http.server 8000
open http://localhost:8000/
```

## Regenerate the social-card preview image (optional)

```bash
pip install Pillow
python make_og_image.py    # writes og-image.png (52 KB)
```

The image is referenced from the `<meta property="og:image">` tag in `dashboard_template.html`,
served at `https://ketenagakerjaan-indonesia.netlify.app/og-image.png`.

## Deploy to Netlify

The dashboard is hosted on Netlify, which auto-builds from the GitHub repo
[`Kelvin17RH/ketenagakerjaan-indonesia`](https://github.com/Kelvin17RH/ketenagakerjaan-indonesia).
The `update_netlify_split.sh` script pushes a fresh build to that repo.

### One-time setup (macOS — already done if you read CLAUDE.md)

```bash
# Save the GitHub Personal Access Token in macOS Keychain
security add-generic-password -a $USER -s github_netlify_pat -w 'ghp_xxxxxxxxxxxx'

# Add this alias to your ~/.zshrc:
deploy() {
  TOKEN=$(security find-generic-password -a $USER -s github_netlify_pat -w) \
  bash "$HOME/Documents/Claude/Projects/Indonesia Labour in Numbers/update_netlify_split.sh" "$1"
}
```

### Daily deploy

```bash
deploy "What changed in this build"
```

What that does:

1. Reads `$TOKEN` from Keychain.
2. Clones (or pulls) the Netlify-watched repo into `~/Documents/ketenagakerjaan-indonesia/`.
3. Copies `index.html`, `_headers`, `og-image.png`, and `data/*.json` into the repo.
4. `git add` + commit + push.
5. Netlify auto-build triggers within ~30 seconds.
6. Live at <https://ketenagakerjaan-indonesia.netlify.app>.

## Validate JS before deploy (recommended)

```bash
# Run from this folder
python3 -c "
import re
with open('dashboard_template.html') as f: html = f.read()
pat = re.compile(r'<script(?![^>]*\b(?:id|type)=)[^>]*>(.*?)</script>', re.DOTALL)
js = '\n;\n'.join(pat.findall(html))
for ph in ['__DATA_JSON__','__CUBE_10__','__CUBE_97__','__PROD_WAGE__','__INEQUALITY__','__MEDIANS__','__MEDIANS_ALL__','__WAGE_ALL__','__NEWVARS__','__NEWVARS2__','__MEDIANS_PAIR__','__LABOR_SPACE__']:
  js = js.replace(ph, '{\"metrics\":[],\"single\":{},\"pair\":{},\"labels\":{}}' if 'CUBE' in ph or 'NEWVARS' in ph or 'MEDIANS_PAIR' in ph else '{}')
open('/tmp/jscheck.js','w').write(js)
" && node --check /tmp/jscheck.js
```

Should print `OK: JS syntax valid`. If `node --check` fails, do not bake or deploy.

## See also

- [`CLAUDE.md`](../CLAUDE.md) — architecture, design decisions, the i18n system, and
  every data-quality gotcha you'll bump into.
- [`docs/DEPLOYMENT.md`](../docs/DEPLOYMENT.md) — full deploy reference.
