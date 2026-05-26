# Step 2 — Python aggregators

Read the cleaned Sakernas `.dta` files (from Step 1) and produce pre-aggregated **JSON
cubes** that the dashboard reads at runtime. None of the cube JSONs are committed to this
repo — they're rebuildable on demand and individually can run to ~40 MB.

## Setup

```bash
pip install -r requirements.txt
```

Tested with Python 3.9–3.12, pandas 2.x, numpy 1.24+.

## Running order (numbered prefixes match the suggested order)

| # | Script | Input | Output JSON | ~Size | Notes |
| -- | --- | --- | --- | --- | --- |
| 1 | `01_agg_main_cubes.py`  | `final_sakernas_10_24.dta` + `final_sakernas_97_24.dta` | `agg_10_24_v8.json` + `agg_97_24_v8.json` | ~80 MB | CUBE10 (2010–2024) + CUBE97 (1997–2024) with single + pair dim aggregations |
| 2 | `02_compress_cubes.py`  | the two `agg_*_v8.json` above | `agg_10_24_v8_compact.json` + `agg_97_24_v8_compact.json` | ~70 MB | converts dict rows → compact array rows to shrink ~25% |
| 3 | `03_agg_newvars.py`     | per-year `clean_sakernas_<yr>_updated.dta` | `newvars_cube.json` | ~19 MB | 12 newer metrics (hours, underemp, etc.) |
| 4 | `04_agg_newvars2.py`    | per-year `clean_sakernas_<yr>_updated.dta` | `newvars2_cube.json` | ~6 MB | Job-quality metrics (BPJS, paid leave, ICLS-17 informality) |
| 5 | `05_agg_medians.py`     | `final_sakernas_97_24.dta` | `medians.json` | ~25 KB | Weighted median wage per (year, dim, code) — wage earners only |
| 6 | `06_agg_medians_all.py` | per-year `clean_sakernas_<yr>_updated.dta` | `medians_all.json` | ~26 KB | Weighted median wage per (year, dim, code) — **all workers** incl. self-employed |
| 7 | `07_agg_pair_medians.py`| per-year `clean_sakernas_<yr>_updated.dta` | `medians_pair.json` | ~2 MB | True weighted median per (year, dimA × dimB) cell for heatmap |
| 8 | `08_agg_workearnings.py`| `final_sakernas_97_24.dta` | `wage_all.json` | ~50 KB | Mean `work_earnings` (all workers) per (year, dim) |
| 9 | `09_agg_inequality.py`  | `final_sakernas_97_24.dta` | `inequality.json` | ~1 MB | Gini, decile shares, P50/P90/P10 ratios |
| 10 | `10_agg_labor_space.py`| per-year `clean_sakernas_<yr>_updated.dta` | `labor_space.json` | ~330 KB | Hierarchical L1/L2/L3 nodes for Labor Space visual (5 snapshot years) |

## Paths

Every aggregator assumes the cleaned `.dta` files live in:

```
<project>/clean/clean_sakernas_<YEAR>_updated.dta
<project>/finaloutput/final_sakernas_<YEAR_RANGE>.dta
```

And writes output JSON to:

```
<project>/outputs/<NAME>.json
```

If your layout is different, edit the `CLEAN_DIR`, `DTA`, or `OUT_PATH` constants at the top
of each script.

## Resumable aggregators

Some aggregators (especially `06_agg_medians_all.py` and `07_agg_pair_medians.py`) work on
large per-year files and can exceed wall-clock limits in restricted environments. They write
checkpoint pickles between years and resume from where they left off if re-run. To force a
fresh run, delete the `*_state.pkl` / `*_partial.pkl` files in `/tmp/`.

## Methodology highlights

- **Small-N filter**: cells with denominator weight < 17,000 (~50 raw respondents) are
  hidden or flagged. Standard for Small-Area Estimation (SAE) and ILO publication norms.
- **2010 halving**: only applied to CUBE10 inside the aggregator. CUBE97 unaffected.
- **2011 interpolation**: applied client-side in the dashboard, NOT in the aggregator
  outputs (so the cube JSON stays "raw" and we can revisit the policy).
- **Informality definition** uses status-based (BPS classic) `informal` everywhere except
  the new `informal_icls` metric which uses the ICLS-17 multi-criteria definition.

See [`docs/METHODOLOGY.md`](../docs/METHODOLOGY.md) for the full statistical notes.
