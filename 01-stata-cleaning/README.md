# Step 1 — Stata cleaning

Convert raw, year-by-year Sakernas microdata into a single harmonised panel that the
Python aggregators can read.

## Inputs (NOT in this repo)

You need the raw Sakernas .dta files from BPS. Typical filename pattern:

```
sak<YEAR>_full.dta          e.g. sak2024_full.dta
```

Cover at least 2001 → 2024. Earlier years rely on a different variable scheme; the
do-files handle the harmonisation.

## What the do-files do

| File | Purpose |
| --- | --- |
| `Clean_sakernas97-24_v2.do` | Master cleaning script. Reads each year's raw `.dta`, recodes variables to a consistent 2001-2024 scheme (education codes 1-8, KBLI 1-17 merged from 2-digit, etc.), drops missing/invalid records, writes `clean_sakernas_<YEAR>_updated.dta` per year. |
| `SAKERNAS_PIPELINE_FULL.do` | The end-to-end pipeline that orchestrates: per-year cleaning → append → derive panel variables → write the master pool. |
| `append_to_master_pool.do` | Concatenates the per-year cleaned files into `final_sakernas_97_24.dta` and `final_sakernas_10_24.dta`. |

## Outputs (intermediate — NOT pushed to GitHub)

Per-year cleaned files:

```
clean_sakernas_1997_updated.dta
clean_sakernas_1998_updated.dta
…
clean_sakernas_2024_updated.dta
```

Master pool panels (both used by the Python step):

```
final_sakernas_97_24.dta   ← long history 1997–2024
final_sakernas_10_24.dta   ← from 2010 onwards (more harmonised dimensions)
```

## Variables produced

After cleaning, every row has at minimum:

| Group | Variables |
| --- | --- |
| **Demographics** | `male`, `age`, `agegroup`, `urban`, `prov_34`, `heduc`, `educ_group`, `educ_major` |
| **Labour-market status** | `lf` (labour force), `employment`, `unemp`, `work_status`, `worktype` (KBJI 1-digit) |
| **Earnings** | `work_wage` (paid employees only), `work_earnings` (all workers incl. self-employed), `wage_real` (deflated to a base year) |
| **Hours** | `hour_main`, `hour_total`, `underemp_inv`, `underemp_vol` |
| **Income class** | `social_status` (poor / vulnerable / aspiring / middle / upper) |
| **Job quality** (2019, 2021+) | `formal_icls`, `benefit` (BPJS), `paidleave` |
| **Sector** | `sector`, `sector3`, `sector6`, `sector9`, `sector17` (KBLI 2014) |
| **Other** | `tertiary`, `whitecoll`, `certif`, `jobdur`, `wt` (survey weight) |

## How to run

```bash
# From the project root, in Stata batch mode
stata-mp -b do 01-stata-cleaning/Clean_sakernas97-24_v2.do

# Or, if you prefer to run interactively, open Stata then:
. do "01-stata-cleaning/Clean_sakernas97-24_v2.do"
```

Set the `RAW_DIR` and `OUT_DIR` globals at the top of the do-file to point at your local
Sakernas raw directory and your preferred output location.

## Known data-quality treatments

- **2001 dropped** — survey artefacts make the year unreliable; aggregators skip it.
- **2010 weights halved** — the 2010 dataset doubles weights (Feb + Aug consolidated without
  divisor). The Python aggregator halves all absolute counts for 2010 only.
- **2011 interpolated** — Sakernas 2011 had data fallout + mid-survey reclassification;
  the dashboard interpolates 2011 = avg(2010, 2012) post-aggregation.
- **ICLS-17 informality** (`formal_icls`) only reliably derivable from 2019 onwards — earlier
  years lack the BPJS / contract / severance underlying variables.

See [`docs/METHODOLOGY.md`](../docs/METHODOLOGY.md) for the full rationale on each treatment.

## Reference: original questionnaires

Sakernas blank questionnaires (1997-2024, public PDFs from BPS) are archived at
[`reference/kuesioner-sakernas/`](../reference/kuesioner-sakernas/). Use them
to verify the exact wording of any survey question and to trace variables
across the cross-year harmonisation in this cleaning step.
