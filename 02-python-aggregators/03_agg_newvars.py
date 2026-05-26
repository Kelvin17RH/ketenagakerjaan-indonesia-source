"""Aggregate 12 NEW vars per year into a supplement cube. Per-year streaming, no giant concat.

Resumable: saves partial state to newvars_cube_partial.pkl after each year.
"""
import pandas as pd, numpy as np, json, os, time, pickle, sys

CLEAN_DIR = '/sessions/relaxed-focused-wozniak/mnt/Indonesia Labour in Numbers/clean'
OUT_PATH  = '/sessions/relaxed-focused-wozniak/mnt/outputs/newvars_cube.json'
PARTIAL   = '/sessions/relaxed-focused-wozniak/mnt/outputs/newvars_cube_partial.pkl'

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
DIMS = ['prov_34','region','urban','male','agegroup','educ_group','heduc','sector17','sector9','sector6','sector3',
        'educ_major','worktype','work_status','status']
# sector6 derivation from sector17 (matches existing DIM_LABELS in dashboard):
#   1=Pertanian (s17 1), 2=Manufaktur (s17 3), 3=Industri Lain (s17 2,4,5,6),
#   4=Jasa Low-VA (s17 7,9,17), 5=Jasa High-VA (s17 8,10,11,12,13), 6=Sektor Publik (s17 14,15,16)
SECTOR17_TO_SECTOR6 = {
    1:1,
    2:3, 4:3, 5:3, 6:3,
    3:2,
    7:4, 9:4, 17:4,
    8:5, 10:5, 11:5, 12:5, 13:5,
    14:6, 15:6, 16:6
}
# All pairs (sorted alphabetically per pair) — mirrors existing CUBE10 pair structure
PAIRS = []
for i in range(len(DIMS)):
    for j in range(i+1, len(DIMS)):
        a, b = sorted([DIMS[i], DIMS[j]])
        PAIRS.append((a, b))
NEW_METRIC_FIELDS = [
    'hour_total_n','hour_total_d',
    'underemp_inv_n','underemp_inv_d',
    'underemp_vol_n','underemp_vol_d',
    'hour_under_n','hour_under_d',
    'formal_simple_n','formal_simple_d',
    'formal_new_n','formal_new_d',
    'formal_old_n','formal_old_d',
    # Mean wage across ALL workers (incl. self-employed) — uses work_earnings.
    # n = sum(wt × earnings) where earnings > 0; d = sum(wt) where earnings > 0
    'wage_all_mean_n','wage_all_mean_d'
]
NMET = len(NEW_METRIC_FIELDS)

def process_year(yr, accum, accum_pair=None):
    fp = f'{CLEAN_DIR}/clean_sakernas_{yr}_updated.dta'
    if not os.path.exists(fp): return 0
    df = pd.read_stata(fp, convert_categoricals=False)
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
    # sector3: raw `sector` col is BPS 3-category Pertanian/Industri/Jasa
    if 'sector' in df.columns:
        df['sector3'] = df['sector'].astype('float32')
    # sector6: derive from sector17 via mapping table
    if 'sector17' in df.columns:
        df['sector6'] = df['sector17'].map(lambda x: SECTOR17_TO_SECTOR6.get(int(x), None) if pd.notna(x) else None).astype('float32')

    # Pre-compute weighted metric arrays
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
    # Validity masks: only count rows where the raw var is non-null
    hour = g('hour'); hour_v = gv('hour')
    under_inv = g('underemp_invol'); under_inv_v = gv('underemp_invol')
    under_vol = g('underemp_vol');   under_vol_v = gv('underemp_vol')
    hour_under = g('hour_under'); hour_under_v = gv('hour_under')
    fs = g('formal_simple'); fs_v = gv('formal_simple')
    fn = g('formal_new');    fn_v = gv('formal_new')
    fo = g('formal_old');    fo_v = gv('formal_old')
    # wage_all: ambil work_earnings; valid hanya saat > 0
    earnings = g('work_earnings')
    earnings_pos = (earnings > 0).astype('float32')

    # Stack 14 metric cols (n × 14) as a numpy array
    # Denominator semantics:
    # - underemp_inv/vol: % dari SEMUA pekerja (denom = wt * emp), bukan % dari underemp subset.
    #   underemp_invol/vol hanya non-null untuk underemp subset, sehingga numerator otomatis
    #   tergated ke underemp workers via validity. Denominator pakai emp saja (semua pekerja).
    # - hour_total / hour_under / formal_*: denom pakai validity karena di luar valid rows
    #   memang tidak punya kontribusi (NaN bukan 0).
    metrics = np.column_stack([
        wt * hour * hour_v,                 # hour_total_n
        wt * hour_v,                        # hour_total_d (rows where hour is non-null)
        wt * under_inv * emp * under_inv_v, # underemp_inv_n: only invol underemp
        wt * emp,                           # underemp_inv_d: ALL employed (BPS standard rate)
        wt * under_vol * emp * under_vol_v, # underemp_vol_n: only vol underemp
        wt * emp,                           # underemp_vol_d: ALL employed
        wt * hour_under * hour_under_v,     # hour_under_n
        wt * hour_under_v,                  # hour_under_d
        wt * fs * fs_v,
        wt * fs_v,
        wt * fn * fn_v,
        wt * fn_v,
        wt * fo * fo_v,
        wt * fo_v,
        wt * earnings * earnings_pos,  # wage_all_mean_n: sum(wt × earnings) for earnings>0
        wt * earnings_pos,             # wage_all_mean_d: sum(wt) for earnings>0
    ]).astype('float64')

    # Per-dim groupby: use numpy bincount for speed
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
            key = (int(yr), int(code))
            cell = accum[d].setdefault(key, [0.0]*NMET)
            for j in range(NMET):
                cell[j] += float(sums[j])
    # Pair aggregations: groupby (dim_a, dim_b) per year
    if accum_pair is not None:
        for (a, b) in PAIRS:
            if a not in df.columns or b not in df.columns: continue
            ca = df[a].to_numpy(); cb = df[b].to_numpy()
            m1 = ~np.isnan(ca) if ca.dtype.kind == 'f' else ca != -1
            m2 = ~np.isnan(cb) if cb.dtype.kind == 'f' else cb != -1
            mask = m1 & m2
            if not mask.any(): continue
            ca_i = ca[mask].astype('int32'); cb_i = cb[mask].astype('int32')
            # Encode composite key: code_a * 1e7 + code_b (codes are <10000 so safe)
            composite = ca_i.astype('int64') * 10_000_000 + cb_i.astype('int64')
            m_arr = metrics[mask]
            unique, inverse = np.unique(composite, return_inverse=True)
            pair_key = (a, b)
            for i, comp in enumerate(unique):
                sel = (inverse == i)
                sums = m_arr[sel].sum(axis=0)
                code_a = int(comp // 10_000_000); code_b = int(comp % 10_000_000)
                key = (int(yr), code_a, code_b)
                cell = accum_pair[pair_key].setdefault(key, [0.0]*NMET)
                for j in range(NMET):
                    cell[j] += float(sums[j])
    return n

def main():
    t0 = time.time()
    accum_pair = {(a,b): {} for (a,b) in PAIRS}
    if os.path.exists(PARTIAL):
        with open(PARTIAL, 'rb') as f: state = pickle.load(f)
        # Backward-compat: old partial was {dim: {...}}; new is {'single': {...}, 'pair': {...}}
        if isinstance(state, dict) and 'single' in state:
            accum = state['single']
            accum_pair = state.get('pair', accum_pair)
        else:
            accum = state
        done_years = sorted({y for d in accum.values() for (y, _) in d.keys()})
        start_yr = (max(done_years) + 1) if done_years else 2002
        print(f'Resume from {start_yr} (already done up to {done_years[-1] if done_years else "none"})', flush=True)
    else:
        accum = {d: {} for d in DIMS}
        start_yr = 2002
    for yr in range(start_yr, 2025):
        n = process_year(yr, accum, accum_pair)
        # Estimate pair size for status
        npair_cells = sum(len(v) for v in accum_pair.values())
        print(f'  {yr}: {n:,} rows  single_cells={sum(len(v) for v in accum.values()):,}  pair_cells={npair_cells:,}  elapsed={time.time()-t0:.1f}s', flush=True)
        with open(PARTIAL, 'wb') as f: pickle.dump({'single': accum, 'pair': accum_pair}, f, protocol=4)
    # Finalize: dump JSON
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
