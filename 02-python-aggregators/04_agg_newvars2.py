"""Aggregate 4 ADDITIONAL new vars per year into a small supplement cube.

Metrics added:
  - benefit (BPJS/social-protection coverage): 2019, 2021-2024 only
  - paidleave: 2021-2024 only
  - formal_icls (ICLS international formality standard): 2019, 2021-2024 only
  - potential_exp (years of potential work experience = age - school - 6): 1997-2024 full

Output: newvars2_cube.json (~5 MB target).
Resumable via newvars2_cube_partial.pkl.
Run repeatedly until DONE message appears.
"""
import pandas as pd, numpy as np, json, os, time, pickle, sys

CLEAN_DIR = '/sessions/relaxed-focused-wozniak/mnt/Indonesia Labour in Numbers/clean'
OUT_PATH  = '/sessions/relaxed-focused-wozniak/mnt/outputs/newvars2_cube.json'
PARTIAL   = '/sessions/relaxed-focused-wozniak/mnt/outputs/newvars2_cube_partial_v2.pkl'

PROV_REMAP = {91:91, 92:94, 93:94, 95:94, 96:91}
PROV_TO_REGION = {
    11:1, 12:1, 13:1, 14:1, 15:1, 16:1, 17:1, 18:1, 19:1, 21:1,
    31:2, 32:2, 33:2, 34:2, 35:2, 36:2, 51:2,
    52:5, 53:5,
    61:3, 62:3, 63:3, 64:3, 65:3,
    71:4, 72:4, 73:4, 74:4, 75:4, 76:4,
    81:6, 82:6,
    91:7, 94:7,
}
# Mirror NEWVARS dim list for consistency.
DIMS = ['prov_34','region','urban','male','agegroup','educ_group','heduc','sector17','sector9','sector6','sector3',
        'educ_major','worktype','work_status','status']
SECTOR17_TO_SECTOR6 = {
    1:1,
    2:3, 4:3, 5:3, 6:3,
    3:2,
    7:4, 9:4, 17:4,
    8:5, 10:5, 11:5, 12:5, 13:5,
    14:6, 15:6, 16:6
}
PAIRS = []
for i in range(len(DIMS)):
    for j in range(i+1, len(DIMS)):
        a, b = sorted([DIMS[i], DIMS[j]])
        PAIRS.append((a, b))

NEW_METRIC_FIELDS = [
    'benefit_n','benefit_d',         # share with BPJS/benefit
    'paidleave_n','paidleave_d',     # share with paid leave
    'formal_icls_n','formal_icls_d', # share ICLS-formal
    'potexp_n','potexp_d',           # MEAN potential experience (years)
]
NMET = len(NEW_METRIC_FIELDS)

def process_year(yr, accum, accum_pair=None):
    fp = f'{CLEAN_DIR}/clean_sakernas_{yr}_updated.dta'
    if not os.path.exists(fp): return 0
    # Read only the columns we need (saves memory)
    itr = pd.read_stata(fp, iterator=True)
    cols_all = list(itr.variable_labels().keys())
    want_dims = ['prov','wt','age','employment','lf','unemp','sector','sector17','sector9',
                 'urban','male','educ_group','heduc','educ_major','worktype','work_status']
    want_metrics = ['benefit','paidleave','formal_icls','potential_exp']
    # Also need raw status from newvars (already in updated.dta as 'status')
    want_status = ['status']
    use_cols = [c for c in want_dims + want_metrics + want_status if c in cols_all]
    df = pd.read_stata(fp, columns=use_cols, convert_categoricals=False)

    # Derive dims (same logic as agg_newvars.py)
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

    n = len(df)
    wt = df.get('wt', pd.Series(np.ones(n), index=df.index)).fillna(0).astype('float32').to_numpy()
    def g(col):
        return df[col].fillna(0).astype('float32').to_numpy() if col in df.columns else np.zeros(n,'float32')
    def gv(col):
        return df[col].notna().astype('float32').to_numpy() if col in df.columns else np.zeros(n,'float32')
    if 'employment' in df.columns:
        emp = (df['employment'].fillna(0) == 1).astype('float32').to_numpy()
    else:
        emp = ((df.get('lf', pd.Series(0,index=df.index)).fillna(0)==1) & (df.get('unemp', pd.Series(0,index=df.index)).fillna(0)==0)).astype('float32').to_numpy()

    # Metric vectors with validity
    benefit = g('benefit');         benefit_v = gv('benefit')
    paidleave = g('paidleave');     paidleave_v = gv('paidleave')
    formal_icls = g('formal_icls'); formal_icls_v = gv('formal_icls')
    potexp = g('potential_exp');    potexp_v = gv('potential_exp')

    # Stack metric columns. Denom semantics:
    # - benefit/paidleave/formal_icls: denom = wt * emp * validity (employed workers where var asked)
    # - potexp: MEAN over employed workers with non-null value
    metrics = np.column_stack([
        wt * benefit * emp * benefit_v,            # benefit_n
        wt * emp * benefit_v,                      # benefit_d
        wt * paidleave * emp * paidleave_v,        # paidleave_n
        wt * emp * paidleave_v,                    # paidleave_d
        wt * formal_icls * emp * formal_icls_v,   # formal_icls_n
        wt * emp * formal_icls_v,                  # formal_icls_d
        wt * potexp * emp * potexp_v,              # potexp_n: sum(wt * exp)
        wt * emp * potexp_v,                       # potexp_d: sum(wt) where valid
    ]).astype('float64')

    # Per-dim groupby
    for d in DIMS:
        if d not in df.columns: continue
        codes = df[d].to_numpy()
        mask = ~np.isnan(codes) if codes.dtype.kind == 'f' else codes != -1
        if not mask.any(): continue
        c_int = codes[mask].astype('int32')
        m_arr = metrics[mask]
        unique, inverse = np.unique(c_int, return_inverse=True)
        for i, code in enumerate(unique):
            sel = (inverse == i)
            sums = m_arr[sel].sum(axis=0)
            # Skip totally-empty cells (all metrics zero) — keeps JSON small
            if not sums.any(): continue
            key = (int(yr), int(code))
            cell = accum[d].setdefault(key, [0.0]*NMET)
            for j in range(NMET):
                cell[j] += float(sums[j])
    # Pair aggregations
    if accum_pair is not None:
        for (a, b) in PAIRS:
            if a not in df.columns or b not in df.columns: continue
            ca = df[a].to_numpy(); cb = df[b].to_numpy()
            m1 = ~np.isnan(ca) if ca.dtype.kind == 'f' else ca != -1
            m2 = ~np.isnan(cb) if cb.dtype.kind == 'f' else cb != -1
            mask = m1 & m2
            if not mask.any(): continue
            ca_i = ca[mask].astype('int32'); cb_i = cb[mask].astype('int32')
            composite = ca_i.astype('int64') * 10_000_000 + cb_i.astype('int64')
            m_arr = metrics[mask]
            unique, inverse = np.unique(composite, return_inverse=True)
            pair_key = (a, b)
            for i, comp in enumerate(unique):
                sel = (inverse == i)
                sums = m_arr[sel].sum(axis=0)
                if not sums.any(): continue
                code_a = int(comp // 10_000_000); code_b = int(comp % 10_000_000)
                key = (int(yr), code_a, code_b)
                cell = accum_pair[pair_key].setdefault(key, [0.0]*NMET)
                for j in range(NMET):
                    cell[j] += float(sums[j])
    return n

def main():
    t0 = time.time()
    if os.path.exists(PARTIAL):
        with open(PARTIAL, 'rb') as f: state = pickle.load(f)
        accum = state['single']
        accum_pair = state['pair']
        done_years = sorted({y for d in accum.values() for (y, _) in d.keys()})
        start_yr = (max(done_years) + 1) if done_years else 1997
        print(f'Resume from {start_yr} (already done up to {done_years[-1] if done_years else "none"})', flush=True)
    else:
        accum = {d: {} for d in DIMS}
        accum_pair = {(a,b): {} for (a,b) in PAIRS}
        start_yr = 1997

    # Time budget per call: aim ~35s; bail out if approaching it.
    BUDGET = float(os.environ.get('BUDGET', '35'))
    for yr in range(start_yr, 2025):
        if time.time() - t0 > BUDGET:
            print(f'  budget reached at year {yr}, saving partial state', flush=True)
            with open(PARTIAL, 'wb') as f: pickle.dump({'single': accum, 'pair': accum_pair}, f, protocol=4)
            return
        n = process_year(yr, accum, accum_pair)
        npair_cells = sum(len(v) for v in accum_pair.values())
        nsingle_cells = sum(len(v) for v in accum.values())
        print(f'  {yr}: {n:,} rows  single_cells={nsingle_cells:,}  pair_cells={npair_cells:,}  elapsed={time.time()-t0:.1f}s', flush=True)
        with open(PARTIAL, 'wb') as f: pickle.dump({'single': accum, 'pair': accum_pair}, f, protocol=4)
    # Finalize
    out = {'metrics': NEW_METRIC_FIELDS, 'single': {}, 'pair': {}}
    for d, cells in accum.items():
        rows = []
        for (y, code), vals in sorted(cells.items()):
            rows.append([y, code] + [round(v, 2) for v in vals])
        out['single'][d] = rows
    for (a, b), cells in accum_pair.items():
        if not cells: continue
        rows = []
        for (y, ca, cb), vals in sorted(cells.items()):
            rows.append([y, ca, cb] + [round(v, 2) for v in vals])
        out['pair'][f'{a}__{b}'] = rows
    with open(OUT_PATH, 'w') as f:
        json.dump(out, f, separators=(',', ':'))
    sz = os.path.getsize(OUT_PATH) / 1024
    print(f'\n=== DONE in {time.time()-t0:.1f}s. Wrote {OUT_PATH} ({sz:.1f} KB) ===')
    if os.path.exists(PARTIAL):
        try: os.remove(PARTIAL)
        except: pass

main()
