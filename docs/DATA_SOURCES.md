# Data sources

## Sakernas

**Survei Angkatan Kerja Nasional** (National Labour Force Survey) — the workhorse Indonesian
labour-market dataset, conducted by **Badan Pusat Statistik** (BPS-Statistics Indonesia)
annually since 1986 and semesterly in some years.

- **Coverage**: ~700,000 to 1.2 million respondents per round, weighted up to the Indonesian
  population aged 15+.
- **Geographic units**: 34 provinces (post-2012 split). Earlier years had 33 / 32 provinces;
  the cleaning step harmonises codes via `PROV_REMAP` (see `01-stata-cleaning/Clean_sakernas97-24_v2.do`).
- **Frequency**: annual file used in this dashboard. Many years also have a February + August
  semester file; we use the August consolidated file where available (or both rolled-up).
- **Period covered in this dashboard**: 2001-2024.
  - **2001 dropped** in all aggregators because of data fallout in early Sakernas.
  - **2011 interpolated** as avg(2010, 2012) in MEDIANS / WAGE_ALL / NEWVARS cubes because of
    Sakernas 2011 data fallout + mid-survey reclassification.
  - **2020 dropped** from the Labor Space aggregator because of COVID-related survey anomaly.

### How to request the microdata

Sakernas microdata is **not freely downloadable** but is available to researchers,
government bodies, and journalists through formal request:

1. Submit a written request to your nearest BPS Provincial Office or the central BPS Jakarta
   Data Service. Specify the years and variables required.
2. Provide an institutional letter (university, research institute, government agency,
   media outlet) explaining the intended use.
3. Sign BPS's data-use agreement.

Once approved, BPS issues `.dta` (Stata) files via secure transfer. Pricing varies by
year-coverage and number of variables.

### Variable schemes by era

Sakernas variable codes have changed across years; the cleaning step (Step 1) harmonises
everything into a consistent 2001-2024 scheme. Notable shifts:

| Variable group | Pre-2014 | 2014+ |
| --- | --- | --- |
| **Sector** | KBLI 2-digit codes 1-99 | KBLI 2014 (17 1-digit sections) |
| **Occupation** | KBJI 1990 | KBJI 2014 (Indonesian SOC) |
| **Education** | 9-level scheme | 9-level scheme (recoded to consistent 1-8) |
| **Geography** | 33 provinces | 34 provinces (Kaltara split off 2013) |

| Variable | Pre-2019 | 2019, 2021+ |
| --- | --- | --- |
| **Formal/informal (ICLS-17)** | Not derivable (missing BPJS + contract + severance) | Derivable as `formal_icls` |
| **BPJS coverage** | Partially | Full coverage by 2021 |

The Stata cleaning script (`Clean_sakernas97-24_v2.do`) handles all the recoding.

## Other supporting data

This dashboard pulls **only** from Sakernas. Other datasets that could enrich future
versions but are not currently used:

- **Susenas** (Survei Sosial Ekonomi Nasional) — household consumption + welfare
- **Sakernas Februari** — semesterly variant
- **CPI** (Consumer Price Index from BPS Statistik Harga) — used externally by us to
  compute `wage_real` (deflated wages) inside the Stata cleaning step.
- **GeoJSON** for province choropleth — wishlisted (#73 in backlog) but not yet built.

## Citation requirements

When using outputs from this dashboard, please attribute:

> Source: BPS, Survei Angkatan Kerja Nasional (Sakernas) 2001-2024, aggregated by
> Sekretariat Staf Ahli SPK Bappenas via the public dashboard at
> <https://ketenagakerjaan-indonesia.netlify.app>.
