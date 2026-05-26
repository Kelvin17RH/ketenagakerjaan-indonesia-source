"""Single-dim weighted median of work_earnings (ALL workers, includes self-employed).

Output: outputs/medians_all.json with same shape as medians.json (wage_nom_median):
  { national: {"2010": 1234567, ...},
    by_dim: { "sector17": {"2010": {"1": ..., "2": ...}, ...}, ... } }

Reads per-year clean dta from /clean (small files), year-by-year (~25MB each).
Resumable via /tmp/agg_medians_all_partial.pkl.
"""
import pandas as pd, numpy as np, json, os, time, pickle

CLEAN_DIR = '/sessions/relaxed-focused-wozniak/mnt/Indonesia Labour in Numbers/clean'
OUT_PATH  = '/sessions/relaxed-focused-wozniak/mnt/outputs/medians_all.json'
PARTIAL   = '/tmp/agg_medians_all_partial.pkl'
YEARS = list(range(2002, 2025))  # match medians.json range
MIN_WT = 17000

# Same province remap + region as agg_pair_medians.py
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

DIMS = ['prov_34','sector17','sector9','agegroup','educ_group',
        'male','urban','work_status','social_status','region']

def weighted_median(values, weights):
    if len(values) == 0: return np.nan
    sorter = np.argsort(values)
    v = values[sorter]; w = weights[sorter]
    cum = np.cumsum(w)
    cutoff = cum[-1] / 2.0
    idx = np.searchsorted(cum, cutoff)
    if idx >= len(v): idx = len(v) - 1
    return float(v[idx])

def process_year(yr, accum):
    fp = f'{CLEAN_DIR}/clean_sakernas_{yr}_updated.dta'
    if not os.path.exists(fp): return None
    itr = pd.read_stata(fp, iterator=True)
    cols_all = list(itr.variable_labels().keys())
    want = ['prov','wt','age','employment','sector17','sector9',
            'urban','male','educ_group','heduc','work_status','social_status',
            'work_earnings']
    use = [c for c in want if c in cols_all]
    df = pd.read_stata(fp, columns=use, convert_categoricals=False)
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

    # Employed only + work_earnings > 0
    if 'employment' in df.columns:
        df = df[df['employment'] == 1]
    if 'work_earnings' not in df.columns:
        return None
    df = df[(df['work_earnings'] > 0) & df['wt'].notna()]
    if len(df) == 0: return None

    wt = df['wt'].astype('float64').to_numpy()
    we = df['work_earnings'].astype('float64').to_numpy()
    # National
    accum.setdefault('national', {})[yr] = round(weighted_median(we, wt))
    # Each dim
    for d in DIMS:
        if d not in df.columns: continue
        codes = df[d].to_numpy()
        valid_m = ~np.isnan(codes) if codes.dtype.kind == 'f' else (codes != -1)
        if not valid_m.any(): continue
        ci = codes[valid_m].astype('int32')
        wt_v = wt[valid_m]
        we_v = we[valid_m]
        accum.setdefault(d, {})
        store = accum[d].setdefault(yr, {})
        for code in np.unique(ci):
            if code < 0: continue
            sel = ci == code
            if wt_v[sel].sum() < MIN_WT: continue
            med = weighted_median(we_v[sel], wt_v[sel])
            if np.isnan(med): continue
            store[int(code)] = round(med)
    return len(df)

def main():
    t0 = time.time()
    if os.path.exists(PARTIAL):
        with open(PARTIAL,'rb') as f: accum = pickle.load(f)
        done = sorted([y for y in accum.get('national', {}).keys()])
        start = (max(done)+1) if done else YEARS[0]
        print(f'Resume from {start} (done up to {done[-1] if done else "none"})', flush=True)
    else:
        accum = {}
        start = YEARS[0]

    BUDGET = 36.0
    for yr in YEARS:
        if yr < start: continue
        if time.time() - t0 > BUDGET:
            print(f'  budget reached, checkpointing at {yr}', flush=True)
            with open(PARTIAL,'wb') as f: pickle.dump(accum, f, protocol=4)
            return
        n = process_year(yr, accum)
        print(f'  {yr}: {n:,} rows, elapsed={time.time()-t0:.1f}s', flush=True)
        with open(PARTIAL,'wb') as f: pickle.dump(accum, f, protocol=4)

    # Finalize
    natl = accum.get('national', {})
    out = {'national': {str(y): v for y, v in natl.items()}, 'by_dim': {}}
    for d in DIMS:
        if d not in accum: continue
        out['by_dim'][d] = {}
        for y, codes in accum[d].items():
            out['by_dim'][d][str(y)] = {str(k): v for k, v in codes.items()}

    # 2011 interpolation (Sakernas anomaly fix)
    for d, by_y in out['by_dim'].items():
        c10 = by_y.get('2010'); c11 = by_y.get('2011'); c12 = by_y.get('2012')
        if not (c10 and c11 and c12): continue
        for k, v11 in list(c11.items()):
            a, b = c10.get(k), c12.get(k)
            if a is not None and b is not None:
                c11[k] = round((a + b) / 2)
    if '2010' in out['national'] and '2011' in out['national'] and '2012' in out['national']:
        out['national']['2011'] = round((out['national']['2010'] + out['national']['2012']) / 2)

    with open(OUT_PATH, 'w') as f:
        json.dump(out, f, separators=(',',':'))
    sz = os.path.getsize(OUT_PATH) / 1024
    print(f'\nWrote {OUT_PATH} ({sz:.1f} KB) in {time.time()-t0:.1f}s')
    if '2024' in out['national']:
        print(f'national 2024: Rp {out["national"]["2024"]:,}')
    if os.path.exists(PARTIAL): os.remove(PARTIAL)
    print('DONE')

main()
