# Methodology notes

A condensed reference. Full code-level details live in `CLAUDE.md`.

## Weighting

Every figure in the dashboard is **weighted** using the Sakernas individual weight (`wt`).
All averages, medians, totals, and shares are computed at the weighted level — never on raw
sample counts alone.

## Small-N filter

Cells where the denominator weight falls below thresholds are flagged or hidden:

| Tier | Weighted threshold | Raw ~equivalent | Treatment |
| --- | --- | --- | --- |
| **Hide** | < 1,000 | < 3 respondents | Drop entirely from chart |
| **Show with warning** (⚠) | 1,000 - 17,000 | 3-50 respondents | Render with pale colour + tooltip caveat |
| **Reliable** | ≥ 17,000 | ≥ 50 respondents | Render as normal |

The 50-respondent threshold follows standard Small-Area Estimation (SAE) and ILO statistical
publication norms.

## Wage definitions

The dashboard distinguishes between two wage concepts because they describe different
populations:

| Variable | Population | Source variable | Aggregator |
| --- | --- | --- | --- |
| `wage_nom` (mean) | Wage earners only (status 3+4) | `work_wage` | `01_agg_main_cubes.py` |
| `wage_nom_median` | Wage earners only | `work_wage` | `05_agg_medians.py` |
| `wage_all_mean` | **All workers** including self-employed | `work_earnings` | `08_agg_workearnings.py` |
| `wage_all_median` | **All workers** including self-employed | `work_earnings` | `06_agg_medians_all.py` |
| `wage_real` | Same as `wage_nom` but CPI-deflated | `work_wage / CPI` | `01_agg_main_cubes.py` |

`wage_all` figures are systematically lower than `wage_nom` because the self-employed often
report lower monthly earnings than salaried employees.

## Informality definitions

Two competing definitions, both surfaced:

| Variable | Definition | Available years |
| --- | --- | --- |
| `informal` (classic BPS) | Status-based: workers whose `work_status` ∈ {1 (own-account), 2 (employer w/ helpers), 5 (casual agri), 6 (casual non-agri), 7 (unpaid family)} | 2001-2024 (all years) |
| `informal_icls` | **Multi-criteria (ICLS-17)**: lacking at least one of: (1) written work contract, (2) adequate social protection (BPJS / national health & employment insurance / severance / pension). Family workers are always informal by definition. | 2019, 2021+ only (variables not consistently available before then) |

ICLS-17 gives a more accurate picture of vulnerability — a salaried employee at an informal
firm with no contract / BPJS would count as "formal" under the BPS classic but "informal"
under ICLS-17.

## Specific data-quality fixes

### 2001 dropped

The first Sakernas year (2001) has substantial data fallout. All aggregators skip rows
where `year == 2001`. The dashboard begins at 2002.

### 2010 weights halved

The 2010 dataset in our pipeline ships with **doubled weights** (equivalent to "Feb + Aug
consolidated" without divisor). Result: all absolute counts for 2010 are 2× true; ratios
are unaffected.

**Fix**: in `unpackCube()` (client-side, see `dashboard_template.html`), all absolute metric
values for `year === 2010` are halved. This applies **only to CUBE10**; CUBE97 (which uses
single-period weighting) is left alone.

### 2011 interpolated

Sakernas 2011 had data fallout (limited regency coverage) + mid-survey sector
reclassification. Some metrics show an artificial "plunge" in 2011 followed by rebound in
2012.

**Fix**: in `fixupY2011()` (client-side), every metric value for 2011 is replaced with
`avg(2010 value, 2012 value)` per dimension combination. Applied to CUBE10, CUBE97, MEDIANS,
WAGE_ALL, NEWVARS. The smoothing is more representative than the artefactual original.

### 2014 occupation revision

KBJI codes changed from 1990 → 2014 scheme. The Stata cleaning step recodes pre-2014 to a
mapping consistent with the 2014 1-digit groupings.

### 2016 sector revision

Slight regrouping in KBLI 2014 → KBLI 2014 (revision). Already recoded in Stata.

### Field of study (`educ_major`)

Only valid for diploma-and-above graduates (`heduc ∈ {6, 7, 8}` = D1, D2-S1, S2+). All
`educ_major` analysis is restricted to this filtered population. Vocational secondary
(SMK) is dropped because `educ_major` is not populated for that group.

## 2010 vs 2010 vs national totals

Because of the 2010 halving, the dashboard's national 2010 population reads ~115M
(matches BPS). If you see a number that looks 2× too big in your own analysis on the raw
data, that's the un-halved version.

## Cube structure

The pre-aggregated cube uses a compact rows-as-arrays format:

```json
"single": {
  "urban": [
    [2010, 0, 12345, 56789, 234567, ...],
    [2010, 1, 23456, 67890, 345678, ...]
  ]
}
```

First N elements are dimension values (`[year, urban_code]`); remaining elements are
metric numerators/denominators in `cube.metrics` order. Client unpacks back to objects on
load.

## Tab-level methodology notes

- **Sankey** is a *visual aid* for compositional shift, **not** a flow tracker. Sakernas is
  cross-sectional, not a panel; we cannot follow individual workers between 2002 and 2024.
  Sankey shows aggregate composition change, not worker-level mobility.
- **Hours** in CUBE10 are **main-job hours** (`hour_main`). The newer `hour_total` metric
  in NEWVARS sums hours across all jobs.
- **Sector6** (low/high value-added grouping) bins KBLI 17 sectors into 6 broad categories:
  primary, mining, manufacturing, services-low-VA (trade, transport, accommodation),
  services-high-VA (info, finance, real estate, professional), public-sector (govt, ed, health).

For any question, see [`CLAUDE.md`](../CLAUDE.md) — section 7 "Key technical patterns" and
section 10 "Gotchas".
