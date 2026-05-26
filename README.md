# Sekilas Ketenagakerjaan Indonesia — Workflow Source

Reproducible pipeline for the dashboard at **<https://ketenagakerjaan-indonesia.netlify.app>**.

The dashboard summarises Indonesia's labour-market conditions from 2002 to 2024 based on
**Sakernas** (Survei Angkatan Kerja Nasional / National Labour Force Survey) microdata
published by **BPS**. This repository contains everything needed to rebuild the dashboard
from raw microdata — **except the microdata itself**, which is restricted and must be
requested directly from BPS.

> The deployed live dashboard is in a separate repo
> ([`Kelvin17RH/ketenagakerjaan-indonesia`](https://github.com/Kelvin17RH/ketenagakerjaan-indonesia))
> that only holds the built artefacts (`index.html` + `data/*.json`). This repo holds the
> **source** — Stata cleaning, Python aggregators, the HTML template, and build scripts.

---

## Folder structure

```
workflow-source/
├── README.md                      ← you are here
├── CLAUDE.md                      ← project bible (architecture, design choices, gotchas)
├── LICENSE                        ← MIT (code only; Sakernas microdata excluded)
├── .gitignore                     ← excludes microdata + rebuildable cubes
│
├── 01-stata-cleaning/             ← STEP 1: clean raw Sakernas → harmonised per-year .dta
│   ├── README.md
│   ├── Clean_sakernas97-24_v2.do
│   ├── SAKERNAS_PIPELINE_FULL.do
│   └── append_to_master_pool.do
│
├── 02-python-aggregators/         ← STEP 2: aggregate clean .dta → JSON cubes
│   ├── README.md
│   ├── requirements.txt
│   ├── 01_agg_main_cubes.py       ← CUBE10 + CUBE97 (single + pair dimensions)
│   ├── 02_compress_cubes.py       ← rows → compact array encoding
│   ├── 03_agg_newvars.py          ← 12 newer harmonised metrics (hours, underemp, etc.)
│   ├── 04_agg_newvars2.py         ← job-quality metrics (BPJS, paid leave, ICLS-17)
│   ├── 05_agg_medians.py          ← weighted median wage per single dim (wage earners)
│   ├── 06_agg_medians_all.py      ← weighted median wage all workers (incl. self-employed)
│   ├── 07_agg_pair_medians.py     ← weighted median per (dim × dim) cell
│   ├── 08_agg_workearnings.py     ← mean wage_all per (year × dim)
│   ├── 09_agg_inequality.py       ← Gini, decile shares, P50/P90 ratios
│   └── 10_agg_labor_space.py      ← Labor Space hierarchical L1/L2/L3 nodes
│
├── 03-dashboard/                  ← STEP 3: inject cube JSONs into HTML + deploy
│   ├── README.md
│   ├── dashboard_template.html    ← single-page app source (with __PLACEHOLDER__ markers)
│   ├── build_split.py             ← splits the shell HTML from data/*.json
│   ├── serve.command              ← macOS double-click local dev server
│   ├── _headers                   ← Netlify cache policy
│   └── update_netlify_split.sh    ← deploy to the Netlify-watched GitHub repo
│
├── docs/
│   ├── METHODOLOGY.md             ← statistical methodology + sample handling
│   ├── DATA_SOURCES.md            ← Sakernas details + how to request microdata
│   └── DEPLOYMENT.md              ← how to deploy to Netlify
│
└── reference/
    └── kuesioner-sakernas/        ← Sakernas questionnaires 1997-2024 (PDF, public)
```

---

## The full workflow at a glance

```
            ┌─────────────────────────┐
   BPS  →   │ Raw Sakernas .dta files │   (NOT in this repo — request from BPS)
            └────────────┬────────────┘
                         │
                         ▼
                ┌────────────────┐
                │ Stata cleaning │   01-stata-cleaning/*.do
                └────────┬───────┘
                         │
                         ▼
            ┌─────────────────────────────┐
            │ clean_sakernas_YYYY.dta     │   (harmonised per-year files, NOT in repo)
            │ final_sakernas_*.dta        │
            └────────────┬────────────────┘
                         │
                         ▼
              ┌──────────────────────┐
              │ Python aggregators   │   02-python-aggregators/*.py
              └────────┬─────────────┘
                       │
                       ▼
              ┌───────────────────────────────┐
              │ Pre-aggregated cube JSONs     │   (NOT in repo — regenerable)
              │ agg_10_24_v8_compact.json     │
              │ agg_97_24_v8_compact.json     │
              │ newvars_cube.json             │
              │ medians_pair.json … etc.      │
              └────────┬──────────────────────┘
                       │
                       ▼
            ┌─────────────────────────┐
            │ build_split.py          │   03-dashboard/build_split.py
            │ → index.html + data/    │
            └────────┬────────────────┘
                     │
                     ▼
              ┌───────────────────┐
              │ git push (deploy) │   03-dashboard/update_netlify_split.sh
              └────────┬──────────┘
                       │
                       ▼
       https://ketenagakerjaan-indonesia.netlify.app
```

---

## Running it end to end

Prerequisites:

- **Stata** 16+ (for cleaning step)
- **Python** 3.9+ with `pandas` + `numpy` (`pip install -r 02-python-aggregators/requirements.txt`)
- **Node.js** 18+ (only for the optional `node --check` JS-syntax validation)
- **Git** + a GitHub Personal Access Token (only for deployment)
- The Sakernas microdata, which **must be requested from BPS separately** —
  see [docs/DATA_SOURCES.md](docs/DATA_SOURCES.md).

```bash
# Step 1 — Stata cleaning (run inside Stata GUI or batch mode)
#   produces clean_sakernas_YYYY_updated.dta per year + final_sakernas_*.dta panels
stata-mp -b do 01-stata-cleaning/Clean_sakernas97-24_v2.do

# Step 2 — Python aggregators (each writes a JSON cube to ./outputs/)
cd 02-python-aggregators
pip install -r requirements.txt
python 01_agg_main_cubes.py          # ~5-10 min on a 16 GB Mac
python 02_compress_cubes.py
python 03_agg_newvars.py
python 04_agg_newvars2.py
python 05_agg_medians.py
python 06_agg_medians_all.py
python 07_agg_pair_medians.py
python 08_agg_workearnings.py
python 09_agg_inequality.py
python 10_agg_labor_space.py

# Step 3 — Bake the dashboard HTML
cd ../03-dashboard
python build_split.py
#   → outputs/index.html (2.7 MB shell) + outputs/data/*.json (~96 MB total)

# Step 4 — Deploy to Netlify (after setting up the PAT in macOS Keychain)
./update_netlify_split.sh "Deploy fresh build"
```

Read each subfolder's `README.md` for full detail on the inputs, outputs, and any flags.

---

## What is **not** in this repo

- **Sakernas microdata** (`*.dta`) — restricted. Request from BPS.
- **Per-year cleaned files** (`clean_sakernas_YYYY.dta`) — derived from the microdata, still individual-level.
- **Pre-aggregated cube JSONs** — large (~96 MB), trivially regenerable from the aggregators.
- **The built `index.html`** — regenerable via `build_split.py`.
- **The deployed `og-image.png`** — regenerable via the OG image generator.
- **Any GitHub Personal Access Tokens** — stored in macOS Keychain only; deployment script reads via `$TOKEN`.

---

## Project bible

The deepest reference is [`CLAUDE.md`](CLAUDE.md) — a hybrid developer + AI-collaboration
document that covers architecture, design decisions, methodology gotchas, and the full task
backlog. New contributors should read it before making changes.

---

## Citation

If you use this dashboard or pipeline in research, policy, or media work, please cite:

> Hidayat, Kelvin Ramadhan (2026). *Sekilas Ketenagakerjaan Indonesia: an
> interactive dashboard of Indonesia's labour market, 2002–2024*.
> <https://ketenagakerjaan-indonesia.netlify.app>

Source data: BPS, Survei Angkatan Kerja Nasional (Sakernas) 2001–2024.

---

## Contact

Issues, feature requests, data corrections — open a GitHub Issue on the source repo.
