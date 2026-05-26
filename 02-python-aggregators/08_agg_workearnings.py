"""Hitung mean work_earnings (UPAH SELURUH PEKERJA) per (tahun, dim).
Berbeda dari wage_nom di cube yang hanya buruh/karyawan+employer (status 3+4),
ini cakup SEMUA pekerja dengan work_earnings > 0 (termasuk self-employed dll).

Output: outputs/wage_all.json
"""
import pandas as pd
import numpy as np
import json, time
from collections import defaultdict

DTA = '/sessions/relaxed-focused-wozniak/mnt/Indonesia Labour in Numbers/finaloutput/final_sakernas_97_24.dta'
DIMS = ['prov_34', 'sector17', 'sector9', 'agegroup', 'educ_group',
        'male', 'urban', 'social_status', 'region']

def main():
    t0 = time.time()
    base_cols = ['year', 'work_earnings', 'wt']
    cols = base_cols + [d for d in DIMS if d not in base_cols]
    print('Streaming DTA...')

    by_natl = defaultdict(lambda: {'n':0.0, 'd':0.0})
    by_dim = {d: defaultdict(lambda: {'n':0.0, 'd':0.0}) for d in DIMS}

    n_total = 0; n_kept = 0
    with pd.read_stata(DTA, columns=cols, iterator=True, chunksize=500_000,
                       convert_categoricals=False) as r:
        for i, ch in enumerate(r):
            n_total += len(ch)
            ch = ch[(ch.work_earnings > 0) & ch.wt.notna() & ch.year.notna()]
            if len(ch) == 0: continue
            ch.year = ch.year.astype(int)
            n_kept += len(ch)
            for y, sub in ch.groupby('year'):
                if y < 2002: continue
                w = sub.wt.to_numpy(np.float64)
                e = sub.work_earnings.to_numpy(np.float64)
                by_natl[y]['n'] += (e * w).sum()
                by_natl[y]['d'] += w.sum()
                for d in DIMS:
                    if d not in sub.columns: continue
                    sub2 = sub.dropna(subset=[d])
                    if len(sub2) == 0: continue
                    sub2 = sub2.copy()
                    sub2[d] = sub2[d].astype(int)
                    for code, sub3 in sub2.groupby(d):
                        if code < 0: continue
                        w3 = sub3.wt.to_numpy(np.float64)
                        e3 = sub3.work_earnings.to_numpy(np.float64)
                        by_dim[d][(y, code)]['n'] += (e3 * w3).sum()
                        by_dim[d][(y, code)]['d'] += w3.sum()
            if i % 5 == 0:
                print(f'  chunk {i+1}: total={n_total:,} kept={n_kept:,} elapsed={time.time()-t0:.1f}s')

    print(f'\nLoaded {n_kept:,} rows in {time.time()-t0:.1f}s')

    # Build output
    out = {'national': {}, 'by_dim': {}}
    for y, d in by_natl.items():
        if d['d'] > 0:
            out['national'][str(y)] = round(d['n']/d['d'])
    for dim, cells in by_dim.items():
        out['by_dim'][dim] = {}
        for (y, code), d in cells.items():
            if d['d'] < 17000: continue  # min-N filter
            out['by_dim'][dim].setdefault(str(y), {})[str(code)] = round(d['n']/d['d'])

    path = '/sessions/relaxed-focused-wozniak/mnt/outputs/wage_all.json'
    with open(path, 'w') as f:
        json.dump(out, f, separators=(',',':'))
    import os
    print(f'\nWrote {path} ({os.path.getsize(path)/1024:.1f} KB)')
    print(f'Sample national 2024: Rp {out["national"]["2024"]:,}')
    print(f'Sample national 2010: Rp {out["national"]["2010"]:,}')

main()
