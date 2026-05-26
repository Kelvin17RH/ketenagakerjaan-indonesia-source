"""Aggregator for the 'Labor Space' visualization.

Three hierarchical levels of nodes:
  L1: sector17                              → 17 big bubbles per major sector
  L2: sector17 × work_status                → ~120 bubbles
  L3: sector17 × work_status × worktype     → ~528 bubbles (leaf level)

For each node, compute:
  - n_workers (weighted)
  - wage_med  (weighted median of work_earnings, IDR)
  - informal_rate (1 - formal_icls share, 0-1)

Multi-year snapshots: ICLS-17 informality (formal_icls) requires the
BPJS / contract / severance derivations which are reliably available from
2019 onwards. 2020 deliberately skipped (COVID Sakernas anomaly).

Output: outputs/labor_space.json — single file keyed by year for client-side switching.
"""
import pandas as pd, numpy as np, json, os

CLEAN_DIR = '/sessions/relaxed-focused-wozniak/mnt/Indonesia Labour in Numbers/clean'
OUT_PATH = '/sessions/relaxed-focused-wozniak/mnt/outputs/labor_space.json'

# Snapshot years where ICLS-17 informality is reliably derivable.
YEARS = [2019, 2021, 2022, 2023, 2024]
DEFAULT_YEAR = 2024
MIN_WT_OK   = 17000   # ≥50 raw → reliable
MIN_WT_SHOW = 3400    # ≥10 raw → show with low-conf flag
MIN_WT_HIDE = 1000    # <3 raw → hide entirely

def weighted_median(values, weights):
    if len(values) == 0: return None
    sorter = np.argsort(values)
    v = values[sorter]; w = weights[sorter]
    cum = np.cumsum(w)
    cutoff = cum[-1] / 2.0
    idx = np.searchsorted(cum, cutoff)
    if idx >= len(v): idx = len(v) - 1
    return float(v[idx])

def compute_node(g):
    """Take a group of rows, compute (n, wage_med, informal_rate, conf)."""
    w_total = g['wt'].sum()
    if w_total < MIN_WT_HIDE: return None
    if w_total >= MIN_WT_OK: conf = 'ok'
    elif w_total >= MIN_WT_SHOW: conf = 'low'
    else: conf = 'hide'  # render with placeholders

    # Median wage on positive earnings only
    wage_med = None
    valid = g[(g['work_earnings'].notna()) & (g['work_earnings'] > 0)]
    if len(valid) > 0 and conf != 'hide':
        if valid['wt'].sum() >= MIN_WT_SHOW:
            wage_med = weighted_median(
                valid['work_earnings'].values.astype('float64'),
                valid['wt'].values.astype('float64')
            )
            if wage_med is not None: wage_med = round(wage_med, -3)

    # Informality rate (1 - formal_icls weighted share)
    informal_rate = None
    valid_f = g[g['formal_icls'].notna()]
    if len(valid_f) > 0 and conf != 'hide':
        w_f = valid_f['wt'].sum()
        if w_f >= MIN_WT_SHOW:
            formal_share = (valid_f['formal_icls'] * valid_f['wt']).sum() / w_f
            informal_rate = round(float(1 - formal_share), 4)

    return {
        'n': int(round(float(w_total))),
        'w': None if wage_med is None else int(float(wage_med)),
        'i': None if informal_rate is None else round(float(informal_rate), 3),
        'conf': conf,
    }

def process_year(year):
    fp = f'{CLEAN_DIR}/clean_sakernas_{year}_updated.dta'
    if not os.path.exists(fp):
        print(f'  Skipping {year}: file not found ({fp})')
        return None
    # Probe columns for this year — formal_icls may be absent in older snapshots.
    itr = pd.read_stata(fp, iterator=True)
    cols_all = list(itr.variable_labels().keys())
    needed = ['sector17','work_status','worktype','work_earnings','wt','employment']
    has_icls = 'formal_icls' in cols_all
    use = needed + (['formal_icls'] if has_icls else [])
    use = [c for c in use if c in cols_all]
    df = pd.read_stata(fp, columns=use, convert_categoricals=False)
    if 'formal_icls' not in df.columns:
        df['formal_icls'] = pd.NA  # informality side will be None
    if 'employment' in df.columns:
        df = df[df['employment'] == 1]
    print(f'  {year}: loaded {len(df):,} employed rows')

    # L1: per sector
    L1 = []
    for s, g in df.groupby('sector17'):
        if pd.isna(s): continue
        node = compute_node(g)
        if node:
            node = {'s': int(s), **node}
            L1.append(node)

    # L2: per (sector × status)
    L2 = []
    for (s, ws), g in df.groupby(['sector17','work_status']):
        if pd.isna(s) or pd.isna(ws): continue
        node = compute_node(g)
        if node:
            node = {'s': int(s), 'ws': int(ws), **node}
            L2.append(node)

    # L3: per (sector × status × occupation)
    L3 = []
    for (s, ws, wt), g in df.groupby(['sector17','work_status','worktype']):
        if pd.isna(s) or pd.isna(ws) or pd.isna(wt): continue
        node = compute_node(g)
        if node:
            node = {'s': int(s), 'ws': int(ws), 'wt': int(wt), **node}
            L3.append(node)

    national_node = compute_node(df)
    national = {
        'n': national_node['n'],
        'w': national_node['w'],
        'i': national_node['i'],
    }
    print(f'  {year}: L1={len(L1)}, L2={len(L2)}, L3={len(L3)} | national n={national["n"]/1e6:.1f}M wage={national["w"]} inf={national["i"]}')
    return {
        'national': national,
        'levels': {'L1': L1, 'L2': L2, 'L3': L3},
        # Keep `nodes` for backward-compat with v1 client (= L3)
        'nodes': L3,
    }

def main():
    out = {
        'years': [],
        'default_year': DEFAULT_YEAR,
        'min_wt_ok': MIN_WT_OK,
        'min_wt_show': MIN_WT_SHOW,
        'by_year': {},
    }
    for yr in YEARS:
        print(f'Processing {yr}...')
        snap = process_year(yr)
        if snap is None: continue
        out['by_year'][str(yr)] = snap
        out['years'].append(yr)
    if not out['years']:
        raise SystemExit('No years could be processed.')
    if out['default_year'] not in out['years']:
        out['default_year'] = out['years'][-1]

    with open(OUT_PATH, 'w') as f:
        json.dump(out, f, separators=(',', ':'))
    sz = os.path.getsize(OUT_PATH) / 1024
    print(f'\nWrote {OUT_PATH} ({sz:.1f} KB) — years={out["years"]}, default={out["default_year"]}')

main()
