"""Hitung median upah nominal per (tahun, dim) untuk berbagai single dim.

Output: outputs/medians.json — di-inject ke dashboard, dipakai di tempat yang
sekarang nampilkan upah nominal rata-rata.

Populasi: pekerja penerima upah (work_status ∈ {3,4}) dengan work_earnings > 0.
"""
import pandas as pd
import numpy as np
import json, time
from collections import defaultdict

DTA = '/sessions/relaxed-focused-wozniak/mnt/Indonesia Labour in Numbers/finaloutput/final_sakernas_97_24.dta'
WAGE_EARNER_STATUS = {3, 4}

DIMS = ['prov_34', 'sector17', 'sector9', 'agegroup', 'educ_group',
        'male', 'urban', 'work_status', 'social_status', 'region']

def weighted_percentile(values, weights, q):
    v = np.asarray(values, dtype=np.float64)
    w = np.asarray(weights, dtype=np.float64)
    idx = np.argsort(v)
    v = v[idx]; w = w[idx]
    if w.sum() <= 0: return None
    cumw = np.cumsum(w) / w.sum()
    return float(np.interp(q, cumw, v))

def main():
    t0 = time.time()
    print('Streaming DTA...')
    base_cols = ['year', 'work_earnings', 'work_status', 'wt']
    cols = base_cols + [d for d in DIMS if d not in base_cols]
    
    # Akumulator: per (year, dim, code) -> list (wages, weights)
    by_dim = {d: defaultdict(lambda: [[], []]) for d in DIMS}
    by_natl = defaultdict(lambda: [[], []])  # year -> (wages, weights)
    
    n_total = 0; n_kept = 0
    with pd.read_stata(DTA, columns=cols, iterator=True, chunksize=500_000,
                       convert_categoricals=False) as r:
        for i, ch in enumerate(r):
            n_total += len(ch)
            ch = ch[ch.work_status.isin(WAGE_EARNER_STATUS)
                    & (ch.work_earnings > 0) & ch.wt.notna() & ch.year.notna()]
            if len(ch) == 0: continue
            ch.year = ch.year.astype(int)
            n_kept += len(ch)
            for y, sub in ch.groupby('year'):
                if y < 2002: continue
                by_natl[y][0].append(sub.work_earnings.to_numpy(np.float32))
                by_natl[y][1].append(sub.wt.to_numpy(np.float32))
                for d in DIMS:
                    if d not in sub.columns: continue
                    sub2 = sub.dropna(subset=[d])
                    if len(sub2) == 0: continue
                    sub2 = sub2.copy()
                    sub2[d] = sub2[d].astype(int)
                    for code, sub3 in sub2.groupby(d):
                        if code < 0: continue
                        by_dim[d][(y, code)][0].append(sub3.work_earnings.to_numpy(np.float32))
                        by_dim[d][(y, code)][1].append(sub3.wt.to_numpy(np.float32))
            if i % 5 == 0:
                print(f'  chunk {i+1}: total={n_total:,} kept={n_kept:,} elapsed={time.time()-t0:.1f}s')
    
    print(f'\nLoaded {n_kept:,} valid rows in {time.time()-t0:.1f}s')
    
    # Compute median per (year, dim, code)
    print('Computing medians...')
    out = {'national': {}, 'by_dim': {}}
    for y in sorted(by_natl):
        vs = np.concatenate(by_natl[y][0])
        ws = np.concatenate(by_natl[y][1])
        out['national'][y] = round(weighted_percentile(vs, ws, 0.50))
    
    for d, cells in by_dim.items():
        out['by_dim'][d] = {}
        for (y, code), (vlist, wlist) in cells.items():
            if not vlist: continue
            vs = np.concatenate(vlist); ws = np.concatenate(wlist)
            if len(vs) < 20: continue  # too few samples
            p50 = weighted_percentile(vs, ws, 0.50)
            if p50 is None: continue
            out['by_dim'][d].setdefault(str(y), {})[str(code)] = round(p50)
        print(f'  {d}: {sum(len(v) for v in out["by_dim"][d].values())} cells across {len(out["by_dim"][d])} years')
    
    # Save
    path = '/sessions/relaxed-focused-wozniak/mnt/outputs/medians.json'
    with open(path, 'w') as f:
        json.dump(out, f, separators=(',',':'))
    import os
    print(f'\nWrote {path} ({os.path.getsize(path)/1024:.1f} KB) in {time.time()-t0:.1f}s')

main()
