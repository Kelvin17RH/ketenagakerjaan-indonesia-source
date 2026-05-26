"""Compute weighted median wage per (dimA, dimB) cell for heatmap pair mode.

Output: medians_pair.json with shape:
  { "metrics": ["wage_nom_median", "wage_all_median"],
    "pair": { "dimA__dimB": [[year, codeA, codeB, w_nom_med, w_all_med], ...] } }

Resumable via medians_pair_partial.pkl.
"""
import pandas as pd, numpy as np, json, os, time, pickle

CLEAN_DIR = '/sessions/relaxed-focused-wozniak/mnt/Indonesia Labour in Numbers/clean'
OUT_PATH  = '/sessions/relaxed-focused-wozniak/mnt/outputs/medians_pair.json'
PARTIAL   = '/sessions/relaxed-focused-wozniak/mnt/outputs/medians_pair_partial.pkl'

PROV_REMAP = {91:91, 92:94, 93:94, 95:94, 96:91}
PROV_TO_REGION = {
    11:1,12:1,13:1,14:1,15:1,16:1,17:1,18:1,19:1,21:1,
    31:2,32:2,33:2,34:2,35:2,36:2,51:2,
    52:5,53:5,
    61:3,62:3,63:3,64:3,65:3,
    71:4,72:4,73:4,74:4,75:4,76:4,
    81:6,82:6,
    91:7,94:7,
}
SECTOR17_TO_SECTOR6 = {
    1:1, 2:3, 4:3, 5:3, 6:3, 3:2,
    7:4, 9:4, 17:4, 8:5, 10:5, 11:5, 12:5, 13:5,
    14:6, 15:6, 16:6
}

# Pairs we support — exclude prov_34 (34×many = huge), but include other common combos.
DIMS = ['urban','male','agegroup','educ_group','heduc','sector17','sector9','sector6','sector3',
        'educ_major','worktype','work_status','region']
PAIRS = []
for i in range(len(DIMS)):
    for j in range(i+1, len(DIMS)):
        a, b = sorted([DIMS[i], DIMS[j]])
        PAIRS.append((a, b))

# Also support prov_34 paired only with low-cardinality dims (urban/male/region/agegroup)
PROV_PAIRS = [('prov_34', d) for d in ['urban','male','region','agegroup']]
for a, b in PROV_PAIRS:
    s = tuple(sorted([a, b]))
    if s not in [tuple(sorted(p)) for p in PAIRS]:
        PAIRS.append(s)

def weighted_median(values, weights):
    """Weighted median of `values` with `weights`. Returns NaN if empty."""
    if len(values) == 0: return np.nan
    sorter = np.argsort(values)
    v = values[sorter]
    w = weights[sorter]
    cum = np.cumsum(w)
    cutoff = cum[-1] / 2.0
    idx = np.searchsorted(cum, cutoff)
    if idx >= len(v): idx = len(v) - 1
    return float(v[idx])

def process_year(yr, accum):
    fp = f'{CLEAN_DIR}/clean_sakernas_{yr}_updated.dta'
    if not os.path.exists(fp): return 0
    itr = pd.read_stata(fp, iterator=True)
    cols_all = list(itr.variable_labels().keys())
    want = ['prov','wt','age','employment','sector','sector17','sector9',
            'urban','male','educ_group','heduc','educ_major','worktype','work_status',
            'work_wage','work_earnings']
    use = [c for c in want if c in cols_all]
    df = pd.read_stata(fp, columns=use, convert_categoricals=False)
    n0 = len(df)
    # Derive
    if 'prov' in df.columns:
        df['prov_34'] = df['prov'].astype('float32').map(lambda x: PROV_REMAP.get(int(x), int(x)) if pd.notna(x) else None).astype('float32')
    if 'age' in df.columns:
        age = df['age'].astype('float32')
        ag = np.floor((age - 15) / 5).astype('Int64') + 1
        ag = ag.clip(upper=10)
        df['agegroup'] = ag.where(age >= 15, other=pd.NA).astype('float32')
    if 'prov_34' in df.columns:
        df['region'] = df['prov_34'].map(lambda x: PROV_TO_REGION.get(int(x), 0) if pd.notna(x) else None).astype('float32')
    if 'sector' in df.columns:
        df['sector3'] = df['sector'].astype('float32')
    if 'sector17' in df.columns:
        df['sector6'] = df['sector17'].map(lambda x: SECTOR17_TO_SECTOR6.get(int(x), None) if pd.notna(x) else None).astype('float32')

    # Filter employed only
    if 'employment' in df.columns:
        df = df[df['employment'] == 1]
    wt = df['wt'].fillna(0).astype('float64').to_numpy() if 'wt' in df.columns else np.ones(len(df))

    # Two wage variables
    wage_nom_arr = df['work_wage'].fillna(-1).astype('float64').to_numpy() if 'work_wage' in df.columns else np.full(len(df), -1.0)
    wage_all_arr = df['work_earnings'].fillna(-1).astype('float64').to_numpy() if 'work_earnings' in df.columns else np.full(len(df), -1.0)

    # For each pair, compute weighted median per cell
    for (a, b) in PAIRS:
        if a not in df.columns or b not in df.columns: continue
        ca = df[a].to_numpy(); cb = df[b].to_numpy()
        m1 = ~np.isnan(ca) if ca.dtype.kind == 'f' else (ca != -1)
        m2 = ~np.isnan(cb) if cb.dtype.kind == 'f' else (cb != -1)
        valid_dims = m1 & m2
        # wage_nom valid: positive
        valid_nom = valid_dims & (wage_nom_arr > 0)
        # wage_all valid: positive
        valid_all = valid_dims & (wage_all_arr > 0)
        # Composite key per (cell)
        ca_i = ca[valid_dims].astype('int32')
        cb_i = cb[valid_dims].astype('int32')
        composite = ca_i.astype('int64') * 10_000_000 + cb_i.astype('int64')
        uniq = np.unique(composite)
        # Pre-mask wage arrays to valid_dims for indexing
        wt_v = wt[valid_dims]
        nom_v = wage_nom_arr[valid_dims]
        all_v = wage_all_arr[valid_dims]
        cells = accum.setdefault((a, b), {})
        for comp in uniq:
            sel = (composite == comp)
            code_a = int(comp // 10_000_000); code_b = int(comp % 10_000_000)
            key = (yr, code_a, code_b)
            if key in cells: continue  # already processed this year (shouldn't happen)
            # wage_nom_median
            nom_sel = sel & (nom_v > 0)
            w_nom = wt_v[nom_sel]
            n_nom = nom_v[nom_sel]
            wnm = weighted_median(n_nom, w_nom) if len(n_nom) >= 10 else np.nan
            # wage_all_median
            all_sel = sel & (all_v > 0)
            w_all = wt_v[all_sel]
            n_all = all_v[all_sel]
            wam = weighted_median(n_all, w_all) if len(n_all) >= 10 else np.nan
            # Cell weight (for small-N filter)
            cell_wt = float(wt_v[sel].sum())
            cells[key] = (
                None if np.isnan(wnm) else round(wnm, 2),
                None if np.isnan(wam) else round(wam, 2),
                round(cell_wt, 2),
            )
    return n0

def main():
    t0 = time.time()
    if os.path.exists(PARTIAL):
        with open(PARTIAL,'rb') as f: accum = pickle.load(f)
        done = sorted({y for cells in accum.values() for (y,_,_) in cells.keys()})
        start = (max(done)+1) if done else 2010
        print(f'Resume from {start} (already done up to {done[-1] if done else "none"})', flush=True)
    else:
        accum = {}
        start = 2010

    BUDGET = float(os.environ.get('BUDGET', '35'))
    for yr in range(start, 2025):
        if time.time() - t0 > BUDGET:
            print(f'  budget reached at {yr}, saving partial', flush=True)
            with open(PARTIAL,'wb') as f: pickle.dump(accum, f, protocol=4)
            return
        n = process_year(yr, accum)
        ncells = sum(len(v) for v in accum.values())
        print(f'  {yr}: {n:,} rows  cells={ncells:,}  elapsed={time.time()-t0:.1f}s', flush=True)
        with open(PARTIAL,'wb') as f: pickle.dump(accum, f, protocol=4)

    # Finalize
    out = {'metrics': ['wage_nom_median', 'wage_all_median', 'cell_wt'], 'pair': {}}
    for (a, b), cells in accum.items():
        if not cells: continue
        rows = []
        for (y, ca, cb), vals in sorted(cells.items()):
            rows.append([y, ca, cb, vals[0], vals[1], vals[2]])
        out['pair'][f'{a}__{b}'] = rows
    with open(OUT_PATH, 'w') as f:
        json.dump(out, f, separators=(',',':'))
    sz = os.path.getsize(OUT_PATH) / 1024
    print(f'\n=== DONE in {time.time()-t0:.1f}s. Wrote {OUT_PATH} ({sz:.1f} KB) ===')
    if os.path.exists(PARTIAL):
        try: os.remove(PARTIAL)
        except: pass

main()
