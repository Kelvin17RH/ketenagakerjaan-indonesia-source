"""Hitung Gini upah NOMINAL per tahun, deciles, dan dekomposisi sektor.

Definisi BPS untuk analisis upah: berlaku untuk pekerja penerima upah, yaitu
buruh/karyawan (work_status=4) DAN berusaha dibantu buruh tetap (work_status=3).

Variable: work_earnings (pendapatan nominal Rp/bulan dari pekerjaan utama).

Untuk dekomposisi & per-sektor pakai sector17 (KBLI 2014) cross-year 2010-2024.
Untuk decomp 2002-2009 pakai sector9 karena sector17 belum tersedia.

Output: outputs/inequality.json — dipakai di tab Ketimpangan dashboard.
"""
import pandas as pd
import numpy as np
import json, time

DTA = '/sessions/relaxed-focused-wozniak/mnt/Indonesia Labour in Numbers/finaloutput/final_sakernas_97_24.dta'
WAGE_EARNER_STATUS = {3, 4}  # 3=employer/berusaha dibantu buruh tetap; 4=buruh/karyawan

def gini_weighted(values, weights):
    v = np.asarray(values, dtype=np.float64)
    w = np.asarray(weights, dtype=np.float64)
    idx = np.argsort(v)
    v = v[idx]; w = w[idx]
    cumw = np.cumsum(w)
    cumwv = np.cumsum(v * w)
    L = cumwv / cumwv[-1]
    F = cumw / cumw[-1]
    L_prev = np.concatenate([[0], L[:-1]])
    F_prev = np.concatenate([[0], F[:-1]])
    G = 1 - np.sum((F - F_prev) * (L + L_prev))
    return float(G)

def weighted_percentile(values, weights, q):
    v = np.asarray(values, dtype=np.float64)
    w = np.asarray(weights, dtype=np.float64)
    idx = np.argsort(v)
    v = v[idx]; w = w[idx]
    cumw = np.cumsum(w) / w.sum()
    return float(np.interp(q, cumw, v))

def lorenz_points(values, weights, n=20):
    v = np.asarray(values, dtype=np.float64)
    w = np.asarray(weights, dtype=np.float64)
    idx = np.argsort(v)
    v = v[idx]; w = w[idx]
    cumw = np.cumsum(w) / w.sum()
    cumwv = np.cumsum(v * w) / (v * w).sum()
    F_grid = np.linspace(0, 1, n+1)
    L_grid = np.interp(F_grid, cumw, cumwv)
    L_grid[0] = 0.0
    return [(round(float(f),4), round(float(l),4)) for f, l in zip(F_grid, L_grid)]

def main():
    t0 = time.time()
    print('=== Streaming DTA ===')
    wages_by_year = {}
    wages_by_year_s9 = {}    # untuk decomp 2002-2024 (full coverage)
    wages_by_year_s17 = {}   # untuk per-sector display 2010-2024

    cols = ['year','work_earnings','work_status','wt','sector9','sector17']
    n_total = 0
    n_kept = 0
    with pd.read_stata(DTA, columns=cols, iterator=True,
                       chunksize=500_000, convert_categoricals=False) as r:
        for i, ch in enumerate(r):
            n_total += len(ch)
            ch = ch[ch.work_status.isin(WAGE_EARNER_STATUS)
                    & (ch.work_earnings > 0) & ch.wt.notna() & ch.year.notna()]
            if len(ch) == 0: continue
            ch.year = ch.year.astype(int)
            ch.sector9 = ch.sector9.fillna(0).astype(int)
            ch.sector17 = ch.sector17.fillna(0).astype(int)
            n_kept += len(ch)
            for y, sub in ch.groupby('year'):
                if y < 2002: continue
                wages_by_year.setdefault(y, ([], []))
                wages_by_year[y][0].append(sub.work_earnings.to_numpy(np.float32))
                wages_by_year[y][1].append(sub.wt.to_numpy(np.float32))
                for s, sub2 in sub.groupby('sector9'):
                    if s == 0 or s > 9: continue
                    wages_by_year_s9.setdefault((y, s), ([], []))
                    wages_by_year_s9[(y, s)][0].append(sub2.work_earnings.to_numpy(np.float32))
                    wages_by_year_s9[(y, s)][1].append(sub2.wt.to_numpy(np.float32))
                if y >= 2010:
                    for s, sub2 in sub.groupby('sector17'):
                        if s == 0 or s > 17: continue
                        wages_by_year_s17.setdefault((y, s), ([], []))
                        wages_by_year_s17[(y, s)][0].append(sub2.work_earnings.to_numpy(np.float32))
                        wages_by_year_s17[(y, s)][1].append(sub2.wt.to_numpy(np.float32))
            if i % 5 == 0:
                print(f'  chunk {i+1}: total={n_total:,} kept={n_kept:,} elapsed={time.time()-t0:.1f}s')

    print(f'\n=== Loaded: total {n_total:,}, kept {n_kept:,} ({n_kept/n_total*100:.1f}%) in {time.time()-t0:.1f}s ===')

    # National Gini + decile per tahun
    print('\n=== National Gini & deciles ===')
    results = {'national': {}, 'by_sector17': {}, 'decomp': {},
               'meta': {'wage_var': 'work_earnings (nominal Rp/bulan)',
                        'population': 'work_status in (3,4): buruh/karyawan + berusaha dibantu buruh tetap',
                        'sector_classification_per_sector': 'sector17 (KBLI 2014, mulai 2010)',
                        'sector_classification_decomp': 'sector9 (cakupan 2002-2024)'}}
    for y in sorted(wages_by_year):
        vs = np.concatenate(wages_by_year[y][0])
        ws = np.concatenate(wages_by_year[y][1])
        g = gini_weighted(vs, ws)
        p10 = weighted_percentile(vs, ws, 0.10)
        p25 = weighted_percentile(vs, ws, 0.25)
        p50 = weighted_percentile(vs, ws, 0.50)
        p75 = weighted_percentile(vs, ws, 0.75)
        p90 = weighted_percentile(vs, ws, 0.90)
        p99 = weighted_percentile(vs, ws, 0.99)
        mean_w = float((vs * ws).sum() / ws.sum())
        lorenz = lorenz_points(vs, ws, 20) if y in [2002, 2010, 2015, 2019, 2024] else None
        results['national'][y] = {
            'gini': round(g, 4),
            'mean_wage': round(mean_w),
            'p10': round(p10), 'p25': round(p25), 'p50': round(p50),
            'p75': round(p75), 'p90': round(p90), 'p99': round(p99),
            'p90_p10': round(p90/p10, 2) if p10 > 0 else None,
            'p50_p10': round(p50/p10, 2) if p10 > 0 else None,
            'p90_p50': round(p90/p50, 2) if p50 > 0 else None,
            'n_obs': int(ws.sum()),
            'lorenz': lorenz
        }
        print(f'  {y}: G={g:.4f} P50={p50/1e3:.0f}k mean={mean_w/1e3:.0f}k n_obs={int(ws.sum()):,}')

    # Per sektor17, cross-year 2010-2024
    print('\n=== Gini per sektor17 (cross-year 2010-2024) ===')
    by_sector17 = {}
    for (y, s), (vlist, wlist) in wages_by_year_s17.items():
        vs = np.concatenate(vlist); ws = np.concatenate(wlist)
        if len(vs) < 50: continue
        g = gini_weighted(vs, ws)
        mean_w = float((vs * ws).sum() / ws.sum())
        by_sector17.setdefault(y, {})[s] = {
            'gini': round(g, 4),
            'mean_wage': round(mean_w),
            'n_obs': int(ws.sum()),
            'p50': round(weighted_percentile(vs, ws, 0.50))
        }
    results['by_sector17'] = by_sector17

    # Dekomposisi: pakai sector9 (lebih panjang cakupan 2002-2024)
    print('\n=== Dekomposisi within/between sektor (sector9, MLD) ===')
    decomp = {}
    for y in sorted(wages_by_year):
        vs = np.concatenate(wages_by_year[y][0])
        ws = np.concatenate(wages_by_year[y][1])
        if (vs <= 0).any(): vs = np.maximum(vs, 1)
        mean_overall = (vs * ws).sum() / ws.sum()
        T_total = ((np.log(mean_overall / vs)) * ws).sum() / ws.sum()
        T_between = 0.0; T_within = 0.0
        for s in range(1, 10):
            key = (y, s)
            if key not in wages_by_year_s9: continue
            vs_s = np.concatenate(wages_by_year_s9[key][0])
            ws_s = np.concatenate(wages_by_year_s9[key][1])
            vs_s = np.maximum(vs_s, 1)
            mean_s = (vs_s * ws_s).sum() / ws_s.sum()
            p_g = ws_s.sum() / ws.sum()
            T_between += p_g * np.log(mean_overall / mean_s)
            T_g = ((np.log(mean_s / vs_s)) * ws_s).sum() / ws_s.sum()
            T_within += p_g * T_g
        decomp[y] = {
            'mld_total': round(float(T_total), 4),
            'mld_between': round(float(T_between), 4),
            'mld_within': round(float(T_within), 4),
            'between_share': round(float(T_between / T_total * 100), 2) if T_total > 0 else None,
        }
        print(f'  {y}: Tot={T_total:.4f} Bet={T_between:.4f} ({T_between/T_total*100:.1f}%) Wit={T_within:.4f}')
    results['decomp'] = decomp

    out_path = '/sessions/relaxed-focused-wozniak/mnt/outputs/inequality.json'
    with open(out_path, 'w') as f:
        json.dump(results, f, separators=(',',':'))
    import os
    print(f'\nWrote {out_path} ({os.path.getsize(out_path)/1024:.1f} KB) in {time.time()-t0:.1f}s total')

main()
