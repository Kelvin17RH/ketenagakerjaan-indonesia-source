# Indonesia Labour in Numbers — Project Walkthrough

Interactive dashboard of Indonesia's labour-market conditions, 2001-2024. Live at **https://ketenagakerjaan-indonesia.netlify.app**.

This document is hybrid: technical enough that Claude in a future session can pick up without re-onboarding, and narrative enough that a human developer could take the project over. Read the section you need — the top is orientation, the bottom is deep dive.

---

## Table of contents

1. 30-second orientation
2. Data source
3. High-level architecture
4. File map
5. Data pipeline: from raw Sakernas to JSON cube
6. Dashboard anatomy: 6 tabs
7. Key technical patterns
8. Build pipeline
9. Deploy flow
10. Gotchas (the ones that bite)
11. Wishlist & backlog

---

## 1. 30-second orientation

- **What**: A one-page public dashboard showing the transformation of Indonesia's labour market from 2001 to 2024, based on the Sakernas survey.
- **For whom**: General-to-policy audience — researchers, journalists, students, analysts. Not for data-scientist-tier researchers (who would pull microdata directly).
- **Technical form**: A single static HTML file around 90 MB. All data is embedded as JSON inside `<script type="application/json">` tags. No backend. No database.
- **Stack**: Vanilla JS + Chart.js 4.4.1 from CDN. Bilingual ID/EN with locale-aware number formatting.
- **Hosting**: GitHub repo `Kelvin17RH/ketenagakerjaan-indonesia` → Netlify auto-build → gzip/brotli at the edge.
- **Status**: Active iteration. 149 tasks completed (see backlog below).

---

## 2. Data source

**Sakernas (Survei Angkatan Kerja Nasional / National Labour Force Survey)**, conducted by Indonesia's national statistics agency annually 2001-2024 — except 2001 is dropped because of data fallout, and 2011 is interpolated from 2010+2012 due to limited coverage + mid-survey sector reclassification. Roughly 700K-1.2M respondents per year, weighted up to the Indonesian population aged 15+.

**Raw data location**: on the user's Mac, in `.dta` (Stata) format. The Claude sandbox **cannot** run Stata, so the user does the initial derivation (cleaning, variable recoding) in Stata locally, producing intermediate CSV / clean `.dta` files. After that, Python aggregator scripts run in the sandbox to produce cube JSON.

Variables already wired into the pipeline:

- **Demographics**: sex (`male`), age group (`agegroup`), urban/rural (`urban`), 34 provinces (`prov_34`), highest education (`heduc`), field of study (`educ_major`).
- **Employment**: labour-market status (employed/unemployed/inactive), employment status (`work_status` — self-employed / self-employed with helpers / employee / family worker), occupation (KISCO/KBJI 10-digit rolled up to 1-digit), sector (sector3/sector6/sector17 — ISIC/KBLI scheme).
- **Earnings**: nominal wages for paid employees (`wage_nom`), work earnings covering all workers including self-employed (`work_earnings` / `wage_all`).
- **Hours worked**: total hours across all jobs (`hour_total`), main-job hours, involuntary/voluntary underemployment, hours <35.
- **Income class**: poor / vulnerable / aspiring / middle / upper based on equivalent World Bank thresholds rolled forward to 2024 prices.
- **Other**: informality (informal employment per the national definition), tertiary-education share (D1+), LFPR, EPR, unemployment rate.

Always weighted (`weight` column in Sakernas).

---

## 3. High-level architecture

```
┌─────────────────────────────────────────────────────────────┐
│  Indonesia_Labour_Dashboard.html (90 MB single file)        │
│  ┌──────────────────────────────────────────────────────┐   │
│  │ <head> Tailwind-style inline CSS                     │   │
│  │ <body> Sidebar nav + 6 tab sections                  │   │
│  │ <script type="application/json" id="cube-10-24">…</script>  (40 MB)│
│  │ <script type="application/json" id="cube-97-24">…</script>  (29 MB, lazy)│
│  │ <script type="application/json" id="newvars-cube">…</script> (19 MB)│
│  │ <script type="application/json" id="dashboard-data">…</script> (0.4 MB)│
│  │ <script type="application/json" id="prod-wage">…</script>    (1.4 MB)│
│  │ <script type="application/json" id="medians|wage-all|inequality">…</script>│
│  │ <script> // Inline app code (~330 KB)                │   │
│  │   - i18n dictionary (ID + EN)                        │   │
│  │   - unpackCube() — converts compact rows to objects  │   │
│  │   - Chart.js setup + custom plugins                  │   │
│  │   - Each tab's build/render functions                │   │
│  │ </script>                                            │   │
│  └──────────────────────────────────────────────────────┘   │
└─────────────────────────────────────────────────────────────┘
```

**Key architectural decisions:**

- **Single static file**: trivial deploy (just copy the file). No server. The browser caches one file.
- **JSON embedded, not fetched separately**: avoids a second roundtrip + CORS issues + dependency on Netlify to serve separate assets. Trade-off: first paint is heavy (~90 MB), but Netlify gzip brings actual transfer down to ~9-12 MB.
- **Lazy-load CUBE97**: CUBE10 (2010-2024, 175 dim-pair, 40 MB) is parsed eagerly because every tab uses it. CUBE97 (2001-2024 long history, 29 MB) is parsed only when the user opens the Perubahan ("Change") tab, or after an 800 ms idle window. Cuts first paint from ~5-8 s to ~2 s. See section 7.5 for details.
- **No framework**: vanilla JS so the bundle stays minimal with no compile step. Chart.js from CDN.
- **Pre-aggregated cube**: the client never sees row-level data. All dim×dim×year aggregates are pre-computed by Python in the sandbox. The client just picks cells. Privacy bonus: no individual respondent is ever exposed.

---

## 4. File map

### User working directory (persisted on Mac)

```
/Users/kelvinramadhan/Documents/Claude/Projects/Indonesia Labour in Numbers/
├── Indonesia_Labour_Dashboard.html    # Deployed file (90 MB) — final product
├── CLAUDE.md                          # This file
├── deploy.sh                          # One-time GitHub deploy (not used daily)
└── update_netlify.sh                  # Daily deploy: push to Netlify-watched repo
```

`update_netlify.sh` is the normal deploy path. It needs a `$TOKEN` env var containing a GitHub PAT (stored in macOS Keychain — see section 9).

### Sandbox working directory (ephemeral, cleared every session)

```
/Users/kelvinramadhan/Library/.../outputs/        # Path used by Claude file tools
/sessions/<id>/mnt/outputs/                       # Equivalent path for bash
├── dashboard_template.html             # Template — same as deployed but with __XXX__ placeholders
├── extended_data.json                  # → __DATA_JSON__
├── agg_10_24_v8_compact.json           # → __CUBE_10__
├── agg_97_24_v8_compact.json           # → __CUBE_97__
├── newvars_cube.json                   # → __NEWVARS__
├── prod_wage_gap.json                  # → __PROD_WAGE__
├── inequality.json                     # → __INEQUALITY__
├── medians.json                        # → __MEDIANS__
├── wage_all.json                       # → __WAGE_ALL__
├── agg*.py                             # Resumable Python aggregator scripts
├── build_data*.py                      # Bake scripts (replace __XXX__ → JSON content)
└── /tmp/build_final.py                 # Latest bake script (see section 8)
```

### Netlify-watched repo (on GitHub)

`Kelvin17RH/ketenagakerjaan-indonesia` — contains only `index.html` (renamed from `Indonesia_Labour_Dashboard.html`) plus a README. Netlify auto-deploys on push to main.

NOTE: don't confuse this with `Kelvin17RH/potret-ketenagakerjaan-indonesia` (an older repo, not Netlify-watched).

---

## 5. Data pipeline: from raw Sakernas to JSON cube

### Step 1 — User: derivation in Stata (local on Mac)

The user has raw `sak<year>_full.dta` files on their laptop. For each year, run a Stata do-file that:

- Standardises variable names (Sakernas column codes differ across years).
- Recodes categories into a consistent 2001-2024 scheme (e.g. education codes 1-8, ISIC/KBLI sector codes 1-17 merged from 2-digit).
- Drops missing/invalid records.
- Outputs: `clean_sak<year>.dta` or an equivalent CSV.

This step is outside Claude's scope — Stata does not run in the sandbox.

### Step 2 — Sandbox: Python aggregator (runs in sandbox)

Aggregator scripts (`agg11.py`, `agg12.py`, `agg_inequality.py`, etc.) read the per-year clean files and produce compact cube JSON. Same pattern:

```python
# For each dimension combination (single dim or pair):
#   For each unique dimension value:
#     Compute sum(weight * is_unemployed), sum(weight * in_labor_force), ...
#     Write to output as array of arrays [year, dim_value, m1, m2, m3, ...]
```

Output cube structure:

```json
{
  "metrics": ["unemp_n", "unemp_d", "lf_n", "lf_d", "pop", "wage_nom_n", "wage_nom_d", ...],
  "single": {
    "urban":     [[2010, 0, 1234.5, 5678.9, ...], [2010, 1, ...], [2011, 0, ...], ...],
    "sector17":  [[2010, 1, ...], ..., [2024, 17, ...]],
    "heduc":     [...],
    "agegroup":  [...],
    "male":      [...],
    "prov_34":   [...],
    "educ_major":[...],
    "work_status":[...],
    "worktype":  [...]
  },
  "pair": {
    "sector17__work_status":   [[2010, 1, 1, m1, m2, ...], ...],
    "heduc__urban":            [...],
    "agegroup__male":          [...]
  },
  "labels": {
    "province": { "11": "Aceh", "12": "Sumatera Utara" },
    "sector17": { "1": "Agriculture, Forestry, Fisheries" }
  }
}
```

**Resumable aggregators**: heavy aggregators (e.g. 12 new metrics × 24 years × ~10 pair combinations) frequently exceed the 45-second sandbox timeout. Use a pickle partial-state pattern:

```python
import pickle, os
STATE = '/tmp/agg_state.pkl'
if os.path.exists(STATE):
    with open(STATE,'rb') as f: done = pickle.load(f)
else:
    done = {}
# ... process item, save progress ...
with open(STATE,'wb') as f: pickle.dump(done, f)
```

Each sandbox call runs a ~30-second chunk and exits. Call it repeatedly until all keys are filled. Don't rely on background processes — the sandbox kills them.

### Step 3 — Sandbox: bake template → deployed HTML

See section 8 (Build pipeline).

---

## 6. Dashboard anatomy: 6 tabs

The left sidebar navigates between tabs. Each tab follows the same structure:
1. **Headline** — title + 2-3 sentence intro.
2. **Filter bar** — dropdowns for dimension / year / metric.
3. **Visualization** — chart or table.
4. **Takeaway box** — 1-2 paragraph interpretation.

### Tab 1 — Beranda (Landing)

Purpose: quick orientation for new visitors.

Components:
- **8 hero KPI cards** with big-number latest year + 15-24-year historic sparkline. KPIs: unemployment rate, LFPR, informality, mean wage, median wage, tertiary-education share, manufacturing-sector share, female LFPR.
- **6 story cards** — popular questions with a one-sentence data answer + mini bar chart + click-through CTA to the relevant tab. Examples: "How big is the male-female wage gap?", "How big was the agriculture → services shift?"
- **Onboarding modal** for first visits (detected via flag).

Code anchor: `function buildHeroKPI(){...}` (line ~6320 in the template) + `function buildStories(){...}` (line ~6620).

### Tab 2 — Bandingkan (Main crosstab)

Purpose: explore the intersection of two dimensions.

Filters: `Row` × `Column` × `Metric` × `Year`. Output: heatmap-style table with cell values and tooltip.

Smart cube routing via `pickCube()`:
1. Try CUBE10 first (default, 2010-2024).
2. If the metric uses NEWVARS-only vars (e.g. `hour_total`, `underemp_inv`) → routes to NEWVARS.
3. If year <2010 or "All years" → fall back to CUBE97.

Small-N filter active: cells with denominator <17K (≈ 50 raw respondents) display as "-" with tooltip "Sample too small for a reliable estimate".

Code anchor: `function pickCube(){...}` (line ~3593).

### Tab 3 — Hubungan Variabel (Scatter Lab)

Purpose: correlation between two metrics in one plot.

Filters: `X axis` × `Y axis` × `Granularity level` (province / sector17 / sector17-year / national) × `Reference year`. Optional: 2-year comparison mode (delta arrows from Y1 to Y2).

Visualisation: scatter plot with quadrant guide lines (mean lines), colour by region/sector, full hover tooltip.

Code anchor: `function buildScatter(){...}` (line ~4900).

### Tab 4 — Pola & Gap (Patterns)

Purpose: exploration + storytelling around patterns.

Components:
- **Heatmap dim×dim** — every dimension combination on the axes. Brand-consistent colour scale. Tooltip with undersampling explanation. "Year" option for a year-axis heatmap.
- **Arrow plot (Perubahan)** — category on y-axis, metric value on x-axis, arrows from year A to year B. Small-N filter, x-axis clipped to data range.
- **Sector job-creation bubble chart** — composite 17×N bubbles (17 sectors × N sub-categories such as employment status / occupation / education). X-axis can be median wage / mean wage / all-worker earnings / informal share. Y-axis: change in worker counts. Radius: target-year population.
- **Time slider + ▶ play animation** for the bubble chart — drag the target year, or play a loop from baseYr+1 to 2024.
- **Heuristic auto-insight** per chart — 3-4 sentence narrative from pattern detection (total flow direction, top winner, top loser, weighted correlation hint).

Code anchor: `function renderBubble(){...}` (line ~5092), `eventAnnotationsPlugin` (line ~2622), insight generation at the tail of renderBubble.

### Tab 5 — Perubahan (Evolution)

Purpose: historical narrative 2001-2024.

Components:
- **Composition trend** — stacked area chart, normalised to 100% per year. See whose share is growing and whose is shrinking.
- **Single-indicator trend** — trajectory of one metric (unemployment, wages, informality) year over year, broken down by group (urban/rural, sector, etc.).
- **Annotated events overlay** — dashed vertical lines + pill labels at 2008 (GFC) and 2020 (COVID). Custom Chart.js plugin `eventAnnotationsPlugin`.

This tab is the **primary CUBE97 consumer**. Other tabs can fall back to CUBE10 for first paint; this one must wait for CUBE97 to be ready.

Code anchor: `function buildEvolusi(){...}` (line ~5846).

### Tab 6 — Telusur (Drill down / Profile)

Purpose: a one-page fact sheet per province or per sector.

Filters: `Mode` (province / sector17) × `Entity` × `Year`. Output: 10 standard KPIs (unemployment, LFPR, EPR, informality, median wage, self-employed share, tertiary share, …) + education-composition chart + mini trend.

Code anchor: `function buildProfil(){...}` (line ~6750).

---

## 7. Key technical patterns

### 7.1 Cube structure + unpacking

Cube JSON uses a compact rows-as-arrays format to save bytes:

```json
"single": {
  "urban": [
    [2010, 0, 12345, 56789, 234567],
    [2010, 1, 23456, 67890, 345678]
  ]
}
```

The first N elements are dimension values (e.g. `[year, urban]`), the rest are metric values in `cube.metrics` order.

Client-side `unpackCube(raw, cubeName)` (in the template ~line 2504) converts to an array of objects:

```js
[
  { year: 2010, urban: 0, unemp_n: 12345, unemp_d: 56789, pop: 234567 }
]
```

While unpacking, it also: drops 2001 (data fallout), halves 2010 (double-count fix), interpolates 2011 (Sakernas anomaly), restricts educ_major to D1+, and so on.

### 7.2 Small-N filter (SAE / ILO standard)

`MIN_N = 17000` weighted ≈ 50 raw respondents. Cells with a denominator below this threshold are masked because the variance is too wide for a reliable estimate. Standard in Small-Area Estimation and ILO statistical guidelines.

Implementation in tooltip:

```js
const isEmpty = val === '-' || val === '' || val == null;
tip.innerHTML = `...${isEmpty
  ? `<div>${t('hm_undersample_tip')}</div>`
  : `<div>${metricLabel}: ${val}</div>`}`;
```

Test cell: find a rare combination — e.g. small province × minority sector × early year.

### 7.3 2011 Sakernas anomaly fix

**Problem**: Sakernas 2011 had data fallout (limited regency coverage) + a mid-survey sector code reclassification. Result: 2011 numbers for some variables (e.g. agriculture share) appear to "plunge" then rebound in 2012 — not real dynamics.

**Fix**: in `fixupY2011()` (inside `unpackCube()`), linearly interpolate metric values per dimension combination:

```js
// For each group (combination of non-year dim values):
//   r10 = row 2010, r11 = row 2011, r12 = row 2012
//   If r11 exists → overwrite metrics: r11[m] = (r10[m] + r12[m]) / 2
```

Applied to CUBE10, CUBE97, and post-load fix for MEDIANS/WAGE_ALL/NEWVARS (at JS load).

Trade-off: 2011 becomes "smoothed", not original. But the original numbers are wrong because of survey artefacts, so smoothing is more representative. The disclaimer is in the methodology footer.

### 7.4 2010 double-count fix

**Problem**: the 2010 dataset in our pipeline ships with a doubled raw weight — equivalent to "February + August consolidated" without a divisor. Result: all absolutes (pop, n, d) are double-counted, while ratios (n/d) stay accurate.

**Fix**: in `unpackCube()`, halve all absolute metric values in 2010:

```js
const HALVE_YEARS = cubeName === '10' ? new Set([2010]) : new Set();
if (HALVE_YEARS.has(obj.year)){
  metrics.forEach(mm => { if (obj[mm] != null) obj[mm] *= 0.5; });
}
```

Applies **only** to CUBE10. CUBE97 (whose aggregator uses single-period weighting) is not halved. Important!

### 7.5 Lazy-load CUBE97 (latest addition — task #149)

**Motivation**: a 90 MB total payload makes first paint ~5-8 s on a home connection. CUBE97 (29 MB) is only required for the Perubahan tab + long hero sparklines. Other tabs use CUBE10 or have a fallback.

**Implementation**:

```js
// 1. Stub Proxy — returns [] for single, null for pair
const _cube97Stub = {
  __loaded: false,
  data: {
    single: new Proxy({}, { get: () => [] }),
    pair:   new Proxy({}, { get: () => null })
  },
  labels: {}
};
let CUBE97 = _cube97Stub;

// 2. Promise-based loader
let _cube97Promise = null;
function ensureCube97(){
  if (CUBE97.__loaded) return Promise.resolve(CUBE97);
  if (_cube97Promise) return _cube97Promise;
  _cube97Promise = new Promise((resolve) => {
    requestAnimationFrame(() => {
      const raw = JSON.parse(_cube97Node.textContent);
      const cube = unpackCube(raw, '97');
      cube.labels.province = CUBE10.labels.province;  // patch label
      cube.__loaded = true;
      CUBE97 = cube;
      _cube97Node.textContent = '';  // free 30 MB DOM string
      // Re-render consumers
      try { window.__buildHeroKPI && window.__buildHeroKPI(); } catch(_){}
      try { window.__buildStoryGrid && window.__buildStoryGrid(); } catch(_){}
      resolve(cube);
    });
  });
  return _cube97Promise;
}

// 3. Idle prefetch
window.addEventListener('load', () => {
  setTimeout(() => { ensureCube97(); }, 800);
});

// 4. Tab click trigger + loader spinner
if (t.dataset.tab === 'evolusi' && !CUBE97.__loaded){
  // inject loader element
  ensureCube97().then(() => {
    // remove loader, render chart
  });
}
```

**Important gotcha**: the old pattern `CUBE97.X || CUBE10.X` is BROKEN because the stub returns `[]`, which is truthy. You must use a `.length` check:

```js
// CORRECT:
const c97 = CUBE97.data.single.urban;
const rows = (c97 && c97.length) ? c97 : (CUBE10.data.single.urban || []);

// WRONG:
const rows = CUBE97.data.single.urban || CUBE10.data.single.urban || [];
// stub returns [] which is truthy, always picks CUBE97
```

Hero KPI, story cards, the Telusur year selector, and the `rowsForDim` helper have all been patched with the `.length` pattern. If you add a new CUBE97 consumer anywhere else, remember this.

### 7.6 i18n pattern

Dictionaries at `I18N.id[key]` and `I18N.en[key]`. Helper `t(key)` resolves to the string for the active locale. `interp(template, vars)` substitutes `{var}` placeholders.

DOM markup uses a data attribute:

```html
<span data-i18n="hl_evolusi_tag">Two decades of change</span>
```

Switch language → iterate every `[data-i18n]` element, replace `textContent` with `t(el.dataset.i18n)`.

Locale-aware number formatters:
- `fmtN(n)` → `1.234.567` (ID) / `1,234,567` (EN)
- `fmtIDR(n)` → `Rp 1.234.567` / `Rp 1,234,567`
- `fmtRpJt(n)` → `Rp 1,2 jt` / `Rp 1.2M`
- `_bbMn(v)` → bubble chart axis abbrev, e.g. `2,5 jt` / `2.5M`

Always test in both languages after touching number code — `.toFixed(1).replace('.', ',')` is ID-only.

### 7.7 URL state persistence

```js
const STATE_FIELDS = ['x-row','x-col','x-metric','x-year','sc-x','sc-y'];

function scheduleUrlUpdate(){
  clearTimeout(_urlT);
  _urlT = setTimeout(() => {
    const params = new URLSearchParams();
    STATE_FIELDS.forEach(id => {
      const el = document.getElementById(id);
      if (el && el.value) params.set(id, el.value);
    });
    history.replaceState(null, '', '?' + params.toString());
  }, 200);
}

document.addEventListener('change', (e) => {
  if (e.target.id && STATE_FIELDS.includes(e.target.id)) scheduleUrlUpdate();
});

window.addEventListener('load', () => {
  setTimeout(() => applyStateFromURL(), 50);
});
```

Users can share a link with a specific state, e.g. `?x-row=heduc&x-col=urban&x-metric=wage_nom&x-year=2024`. Bookmarks preserve the view too.

### 7.8 CSV exports per panel

`attachPanelTools()` is called after window.load. Every `.panel` that has a `data-csv-builder` attribute gets a download button. The builder function collects the current chart's data + settings → returns a CSV string. `Blob` + `URL.createObjectURL` triggers the download.

### 7.9 Heuristic auto-insight (task #148)

The Pola & Gap bubble chart generates a 3-4 sentence narrative on every render:

- **P1** — total flow direction & magnitude ("Total workers grew by 12.3 million from 2010 to 2024…")
- **P2** — top winner ("The Health Services sector grew the most, +1.2 million…")
- **P3** — top loser or "broad-based growth" message
- **P4** — pattern hint via weighted correlation between x-axis and delta-y; threshold `|corr| > 0.3` triggers:
  - positive corr + wage X-axis → "quality-led growth: higher-wage sectors grew faster"
  - negative corr + wage X-axis → "low-quality transition: growth concentrated in lower-wage sectors"
  - positive corr + informal X-axis → "informal-led growth"

Styled in a teal gradient box with a ✨ Auto Insight pill header + transparency disclaimer.

Full i18n: `bb_insight_p1`, `bb_insight_p2_grow`, `bb_insight_p2_shrink`, `bb_insight_p3_no_shrink`, `bb_insight_p3_no_grow`, `bb_insight_p4_wage_pos`, `bb_insight_p4_wage_neg`, etc.

### 7.10 Annotated timeline events (task #146)

A custom Chart.js plugin that draws a dashed vertical line + coloured pill label at major-shock years:

```js
const MAJOR_EVENTS = () => CURRENT_LANG === 'en' ? [
  { year: 2008, label: 'GFC', fullLabel: 'Global Financial Crisis', color: '#f59e0b' },
  { year: 2020, label: 'COVID-19', fullLabel: 'COVID-19 Pandemic', color: '#8b5cf6' }
] : [
  { year: 2008, label: 'GFC', fullLabel: 'Krisis Keuangan Global', color: '#f59e0b' },
  { year: 2020, label: 'COVID-19', fullLabel: 'Pandemi COVID-19', color: '#8b5cf6' }
];
const eventAnnotationsPlugin = {
  id: 'eventAnnotations',
  afterDatasetsDraw(chart, args, opts){
    // draw dashed line at xScale.getPixelForValue(ev.year)
    // draw rounded pill at top with ev.label
  }
};
Chart.register(eventAnnotationsPlugin);

// Per chart:
new Chart(ctx, {
  plugins: { eventAnnotations: { events: MAJOR_EVENTS() } }
});
```

Wired into `ch-evolusi` (composition area) and `ch-evolusi2` (single indicator).

### 7.11 Time slider + play animation (task #147)

The Pola & Gap bubble chart has a control strip above the chart:

```html
<button id="bb-play">▶ Play Animation</button>
<input id="bb-slider" type="range" min="2011" max="2024" step="1" value="2024">
<span id="bb-slider-val">2024</span>
```

Logic:

```js
let bbPlayTimer = null;
function startBBPlay(){
  const baseYr = parseInt(bbYrA.value);
  let cur = Math.max(baseYr + 1, parseInt(bbSlider.value));
  if (cur >= maxSlider) cur = baseYr + 1;
  bbPlayTimer = setInterval(() => {
    bbSlider.value = cur; bbYrB.value = cur; renderBubble();
    cur += 1;
    if (cur > maxSlider) stopBBPlay();
  }, 1200);
}
```

Manual slider drag → stop play. Filter change → stop play.

---

## 8. Build pipeline

### Bake template → deployed file

`/tmp/build_final.py`:

```python
"""Inject all data into template."""
OUT_DIR = '/sessions/.../mnt/outputs'
PROJ_DIR = '/sessions/.../mnt/Indonesia Labour in Numbers'
with open(f'{OUT_DIR}/dashboard_template.html') as f: tpl = f.read()
def load_raw(p):
    with open(p) as f: return f.read()
out = tpl.replace('__DATA_JSON__', load_raw(f'{OUT_DIR}/extended_data.json')) \
         .replace('__CUBE_10__',   load_raw(f'{OUT_DIR}/agg_10_24_v8_compact.json')) \
         .replace('__CUBE_97__',   load_raw(f'{OUT_DIR}/agg_97_24_v8_compact.json')) \
         .replace('__PROD_WAGE__', load_raw(f'{OUT_DIR}/prod_wage_gap.json')) \
         .replace('__INEQUALITY__',load_raw(f'{OUT_DIR}/inequality.json')) \
         .replace('__MEDIANS__',   load_raw(f'{OUT_DIR}/medians.json')) \
         .replace('__WAGE_ALL__',  load_raw(f'{OUT_DIR}/wage_all.json')) \
         .replace('__NEWVARS__',   load_raw(f'{OUT_DIR}/newvars_cube.json'))
dest = f'{PROJ_DIR}/Indonesia_Labour_Dashboard.html'
with open(dest, 'w') as f: f.write(out)
print(f'Wrote {dest} ({len(out)/1024/1024:.2f} MB)')
```

Run every time the template changes OR a cube JSON changes:

```bash
python3 /tmp/build_final.py
# → 90 MB file at /Users/.../Indonesia_Labour_Dashboard.html
```

### Validate before deploy

```bash
# JS syntax check (extract inline blocks, replace placeholders with stub, node --check)
python3 -c "
import re
with open('/sessions/.../mnt/outputs/dashboard_template.html') as f: html=f.read()
pat = re.compile(r'<script(?![^>]+\bid=)[^>]*>(.*?)</script>', re.DOTALL)
js = '\n;\n'.join(pat.findall(html))
for ph in ['__DATA_JSON__','__CUBE_10__','__CUBE_97__','__PROD_WAGE__','__INEQUALITY__','__MEDIANS__','__WAGE_ALL__','__NEWVARS__']:
  js = js.replace(ph, '{\"metrics\":[],\"single\":{},\"pair\":{},\"labels\":{}}' if 'CUBE' in ph else '{}')
open('/tmp/jscheck.js','w').write(js)
"
node --check /tmp/jscheck.js
```

Output `OK: JS syntax valid` means safe to proceed with bake + deploy.

---

## 9. Deploy flow

### First-time setup (already done, just documenting)

The GitHub PAT is stored in macOS Keychain:

```bash
# Save (once)
security add-generic-password -a $USER -s github_netlify_pat -w 'ghp_xxxxxxxxxxxx'

# Read (for deploy)
security find-generic-password -a $USER -s github_netlify_pat -w
```

`deploy` alias in `.zshrc`:

```bash
deploy() {
  TOKEN=$(security find-generic-password -a $USER -s github_netlify_pat -w) \
  bash "$HOME/Documents/Claude/Projects/Indonesia Labour in Numbers/update_netlify.sh" "$1"
}
```

### Daily deploy (from user's Mac)

```bash
deploy "Commit message here"
```

What happens:
1. The script reads `$TOKEN` from Keychain.
2. Clones (or pulls) the repo `Kelvin17RH/ketenagakerjaan-indonesia` into `~/Documents/ketenagakerjaan-indonesia/`.
3. `cp Indonesia_Labour_Dashboard.html ~/Documents/ketenagakerjaan-indonesia/index.html`.
4. `git add index.html && git commit -m "$1" && git push origin main`.
5. If there are local commits not yet pushed (e.g. after a previous crash), pushes those too.
6. Netlify auto-triggers a build within ~30 s.
7. Live at https://ketenagakerjaan-indonesia.netlify.app

**Important constraints**:
- `deploy` **must** run on the user's Mac. The Claude sandbox **does not** have Keychain access and **must not** see the PAT in plaintext.
- After deploy succeeds, share the live URL so the user can verify.

---

## 10. Gotchas (the ones that bite)

### Claude sandbox

- **No Stata** → user runs raw derivation on their Mac.
- **No background processes** → each bash call is independent, no PID retention. Long-running aggregators must be resumable (pickle state).
- **45-second timeout per bash call** → chunk the work.
- **No `curl`/`wget` to arbitrary URLs** — only `WebFetch`/`WebSearch` built-ins. The PAT must never leave Keychain.

### Data quality

- **2001 is dropped** — data fallout in the first Sakernas year. Aggregators skip 2001.
- **2010 halving** — only on CUBE10, not CUBE97. Hard-coded in `unpackCube()`.
- **2011 interpolation** — applied to CUBE10, CUBE97, plus a post-load fix for MEDIANS/WAGE_ALL/NEWVARS.
- **2014 occupation revision** — pre-2014 occupation codes differ. Already recoded in the Stata step.
- **2016 sector revision** — sector17 codes have slight regrouping. Already recoded.
- **Field of study (educ_major)** — analysis is restricted to D1+ only (heduc ∈ {6,7,8}). Vocational secondary (SMK) is dropped because `educ_major` is only valid for diploma-and-above graduates. Logic in `unpackCube()`.

### CUBE97 lazy-load

- **Stub `[]` is truthy** → use `(c97 && c97.length)`, not `c97 || c10`.
- **`labels.province` patch** — now inside `ensureCube97()`, no longer eager. Don't duplicate.
- **Consumers that must re-render after lazy-load**: `window.__buildHeroKPI`, `window.__buildStoryGrid`, the Telusur year selector. Already wired.
- **Perubahan tab clicked before prefetch** → loader spinner appears; don't remove it.

### Chart.js

- **Hidden → visible reflow** — when switching to a tab whose chart is currently in a hidden section, Chart.js needs `setTimeout(() => chart.render(), 50)` after it becomes visible. Already handled in the tab-switch handler.
- **Tooltip positioning** — tooltips are absolute-positioned. On chart resize, positions can go stale.
- **Custom legend** — bubble chart composite mode uses a `generateLabels` callback to show one entry per sector (not per bubble).

### i18n

- **Number format** — `.toFixed(1).replace('.',',')` is ID-only. EN uses plain `.toFixed(1)`. Test both languages.
- **DIM_LABELS, METRIC_META, OPT_GROUPS** — separate per-language dictionaries in JS. Keep in sync with dropdown options.
- **Em-dashes** are avoided (replaced with hyphen-space) for older browser/font compatibility.

### Deploy

- **Netlify-watched repo**: `Kelvin17RH/ketenagakerjaan-indonesia` (not `potret-...`).
- **PAT Keychain service name**: `github_netlify_pat`.
- **Index file in repo**: `index.html` (renamed from `Indonesia_Labour_Dashboard.html`).
- **Netlify build**: no build step. Just serves `index.html` as-is. Gzip/brotli are automatic at the edge.

---

## 11. Wishlist & backlog

### Pending / parked

- **#73 Indonesia Choropleth Map** — the biggest remaining gap for a policy audience. Needs GeoJSON for the 34 provinces + a Chart.js plugin or D3. Effort estimate: 1-2 days.
- **Apply the heuristic-insight pattern to other charts** — currently only the bubble chart. Could extend to the main crosstab (top growing/shrinking cell), the Evolusi year-over-year panel (slope hint), and the heatmap (hotspot detection). Small effort, big UX consistency win.
- **Provincial fact-sheet 1-pager PDF export** — the Telusur tab has the data; just render to PDF via the `pdf` skill. Useful to share with regional governments.
- **Side-by-side province comparison** — Telusur currently shows one province at a time. A comparison mode would help.
- **Annotated events for Indonesia-specific shocks** — 2005 (fuel hike), 2013 (fuel hike), 2015 (rupiah crisis). Currently only GFC and COVID.

### Recently completed (highlights)

- #149 Lazy-load CUBE97 (cuts first paint by ~3-6 s)
- #148 Heuristic auto-insight (bubble chart)
- #147 Time slider + play animation
- #146 Annotated timeline events (GFC, COVID)
- #145 Bubble chart composite 17×N + all-worker earnings axis
- #144 Bubble chart sector focus + breakdown dropdowns
- #142 Fix 2011 Sakernas anomaly (interpolate 2010/2012)
- #141 Add wage_all_mean pair aggregation (work_earnings)
- #134 Apply small-N filter (MIN_N=17000) to newvar lookups
- #132 Extend newvars cube with pair aggregations
- #127 Wire 12 new vars from clean_*.dta to dashboard pipeline
- #113-#125 Full i18n expansion (11 iterations)
- #126 Shareable state via URL + per-panel CSV downloads

Full backlog: tracked in the task list — 149 tasks completed.

---

## Quick reference cheat sheet

### "Where do I go to change X?"

| Need | Location |
|---|---|
| Add a dropdown filter | `<div class="field">` in the tab section + `.addEventListener('change', renderXXX)` listener |
| Add a new metric | Edit Python aggregator → re-aggregate → add to METRIC_META + dropdown options |
| Change a label/copy | `I18N.id` and `I18N.en` dictionaries at the top of the JS |
| Add an event annotation | Edit the `MAJOR_EVENTS()` array |
| Change colour palette | `T.palette`, `T.classCols`, or per-chart inline |
| Add a story card | Edit `buildStories()` — add a `story_xxx()` function + push to the `stories` array in `renderStoryGrid()` |
| Add a KPI card | Edit `buildHeroKPI()` — add an entry to the `kpis` array |
| Re-render after a data update | Re-bake via `python3 /tmp/build_final.py` → verify with `node --check` |

### Most-used commands

```bash
# Sandbox: validate JS
node --check /tmp/jscheck.js

# Sandbox: rebuild deployed file
python3 /tmp/build_final.py

# Mac: deploy to Netlify
deploy "Commit message"

# Mac: check live file size
ls -lh ~/Documents/Claude/Projects/Indonesia\ Labour\ in\ Numbers/Indonesia_Labour_Dashboard.html
```

### Data-lookup patterns in JS

```js
// Single dim — prefer CUBE10, fall back to CUBE97 (for long-history metrics)
function rowsForDim(dim){
  const c97 = CUBE97.data.single[dim];
  if (c97 && c97.length) return c97;  // prefer long history if loaded
  return CUBE10.data.single[dim] || null;
}

// Pair dim
function rowsForPair(a, b){
  const k1 = `${a}__${b}`, k2 = `${b}__${a}`;
  return CUBE10.data.pair[k1] || CUBE10.data.pair[k2]
      || CUBE97.data.pair[k1] || CUBE97.data.pair[k2] || null;
}

// NEWVARS (12 additional metrics)
function rowsForNewvarsPair(a, b){
  const k1 = `${a}__${b}`, k2 = `${b}__${a}`;
  return NEWVARS.data.pair[k1] || NEWVARS.data.pair[k2] || null;
}
```

---

## Glossary

- **Sakernas** — Survei Angkatan Kerja Nasional, Indonesia's National Labour Force Survey. Annual (previously semesterly). ~700K-1.2M respondents per round.
- **KBLI** — Indonesian Standard Industrial Classification. The 17-sector scheme.
- **KBJI** — Indonesian Standard Occupational Classification. 1-digit rolled up from raw 10-digit codes.
- **TPT** — Tingkat Pengangguran Terbuka (Open Unemployment Rate).
- **LFPR** — Labour Force Participation Rate. In Indonesian: TPAK.
- **EPR** — Employment-to-Population Ratio.
- **SAE** — Small Area Estimation. The standard for handling small-N cells.
- **Cube** — Pre-aggregated multidimensional data structure. Single (1 dim) and Pair (2 dim) splits.
- **D1+** — Diploma 1 and above (heduc codes 6, 7, 8). This filter applies to all `educ_major` analysis.

---

**Last updated**: 2026-05-22 (session #149 — lazy-load CUBE97).
**Maintained by**: Claude (Cowork mode).
