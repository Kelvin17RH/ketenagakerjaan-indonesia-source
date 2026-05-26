# Deployment guide

How the live dashboard at <https://ketenagakerjaan-indonesia.netlify.app> is updated.

## The split-build architecture

To keep first-paint fast, the built dashboard is split into:

- `index.html` — small shell (~2.7 MB) containing the HTML template, CSS, JS app code,
  and the small data cubes (`MEDIANS`, `WAGE_ALL`, `INEQUALITY`, etc., each <1 MB).
- `data/cube_10_24.json` (~40 MB) — fetched on first interactive use.
- `data/cube_97_24.json` (~30 MB) — lazy-loaded after window.load + 800 ms idle, or on
  first click of the "Perubahan" tab.
- `data/newvars_cube.json` (~19 MB), `data/newvars2_cube.json` (~6 MB),
  `data/medians_pair.json` (~2 MB) — fetched per tab need.

A `_headers` file tells Netlify to long-cache the `data/*.json` files (they only change
when we rebake).

## Two repos

| Repo | Contents | Why separate |
| --- | --- | --- |
| **This repo** (workflow source) | Stata + Python + HTML template + build scripts | Public, reproducible pipeline |
| [`Kelvin17RH/ketenagakerjaan-indonesia`](https://github.com/Kelvin17RH/ketenagakerjaan-indonesia) | Just the built `index.html` + `data/*.json` + `og-image.png` + `_headers` | Netlify auto-builds from `main` push |

Netlify Pages watches the second repo. Every push to `main` triggers a build (no build
command — it's already-baked static files) and serves at the live URL within ~30 seconds.

## One-time setup (already done — documented for handover)

### 1. Save the GitHub PAT in macOS Keychain

Generate a Personal Access Token with `repo` scope at
<https://github.com/settings/tokens>, then:

```bash
security add-generic-password -a $USER -s github_netlify_pat -w 'ghp_xxxxxxxxxxxx'
```

### 2. Add the `deploy` alias to `~/.zshrc`

```bash
deploy() {
  TOKEN=$(security find-generic-password -a $USER -s github_netlify_pat -w) \
  bash "$HOME/Documents/Claude/Projects/Indonesia Labour in Numbers/update_netlify_split.sh" "$1"
}
```

Reload with `source ~/.zshrc`.

### 3. Verify

```bash
type deploy        # should show the function definition
```

## Daily deploy

```bash
# After making changes to template / aggregators, run the bake first:
cd "$HOME/Documents/Claude/Projects/Indonesia Labour in Numbers"
python3 03-dashboard/build_split.py

# Then push:
deploy "Concise commit message describing what changed"
```

What `update_netlify_split.sh` does:

1. Validates `$TOKEN` is set.
2. Validates `index.html` + `data/` exist in the source folder.
3. Clones (or pulls) the Netlify-watched repo into `~/Documents/ketenagakerjaan-indonesia/`.
4. Copies fresh `index.html`, `_headers`, `og-image.png`, and `data/*.json`.
5. Removes any stale `Indonesia_Labour_Dashboard.html` (legacy single-file build).
6. `git add` everything, `git commit -m "$1"`, `git push origin main`.
7. Netlify auto-build triggers within ~30 seconds.

## Validate before deploying (recommended)

```bash
# JS syntax check
cd "$HOME/Documents/Claude/Projects/Indonesia Labour in Numbers"
python3 -c "
import re
with open('03-dashboard/dashboard_template.html') as f: html = f.read()
pat = re.compile(r'<script(?![^>]*\b(?:id|type)=)[^>]*>(.*?)</script>', re.DOTALL)
js = '\n;\n'.join(pat.findall(html))
for ph in ['__DATA_JSON__','__CUBE_10__','__CUBE_97__','__PROD_WAGE__','__INEQUALITY__','__MEDIANS__','__MEDIANS_ALL__','__WAGE_ALL__','__NEWVARS__','__NEWVARS2__','__MEDIANS_PAIR__','__LABOR_SPACE__']:
  js = js.replace(ph, '{\"metrics\":[],\"single\":{},\"pair\":{},\"labels\":{}}' if 'CUBE' in ph or 'NEWVARS' in ph or 'MEDIANS_PAIR' in ph else '{}')
open('/tmp/jscheck.js','w').write(js)
" && node --check /tmp/jscheck.js && echo "✓ JS valid"
```

Should print `✓ JS valid`. If `node --check` errors, **do not deploy** — the dashboard
will fail to boot in browsers.

## Rollback

Every deploy is a Git commit on the `main` branch of the Netlify-watched repo. To roll back:

```bash
cd ~/Documents/ketenagakerjaan-indonesia
git log --oneline | head           # find the commit hash to roll back to
git revert <hash> --no-edit
git push origin main               # Netlify auto-builds the revert within 30s
```

Or via the Netlify UI: Site Overview → Deploys → click on a previous deploy → **Publish
deploy**.

## Monitoring

- **Netlify build status**: <https://app.netlify.com/sites/ketenagakerjaan-indonesia/deploys>
- **Live URL**: <https://ketenagakerjaan-indonesia.netlify.app>
- **GitHub repo (built artefacts)**: <https://github.com/Kelvin17RH/ketenagakerjaan-indonesia>

## Things that can go wrong

| Symptom | Likely cause | Fix |
| --- | --- | --- |
| Dashboard 404 on first paint | `data/*.json` not pushed | Re-run `python3 build_split.py` then `deploy` |
| `Memuat data sejarah panjang…` stuck forever | CUBE97 fetch failed | Open browser console; usually a transient Netlify CDN issue, hard-refresh |
| New language toggles don't translate | i18n key missing | Check `I18N.id[key]` and `I18N.en[key]` both exist in `dashboard_template.html` |
| Push rejected (non-fast-forward) | Another deploy happened first | `cd ~/Documents/ketenagakerjaan-indonesia && git pull --rebase origin main && git push` |
| `$TOKEN not set` error | Keychain access blocked or PAT expired | Re-create PAT and `security add-generic-password ...` again |
