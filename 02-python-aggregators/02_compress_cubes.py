"""Compress v6 cube JSON to compact array format."""
import json, os

METRIC_COLS = ['pop',
               'lf_n','lf_d','emp_n','emp_d',
               'wage_real_n','wage_real_d','wage_nom_n','wage_nom_d',
               'hours_n','hours_d',
               'informal_n','informal_d','unemp_n','unemp_d',
               'whitecoll_n','whitecoll_d','neet_n','neet_d','underemp_n','underemp_d',
               'certif_n','certif_d',
               'school_n','school_d',
               'jobdur_n','jobdur_d',
               'act_school_n','act_school_d',
               'act_hh_n','act_hh_d',
               'act_other_n','act_other_d',
               'under_ump_n','under_ump_d',
               'sdur1_n','sdur1_d','sdur2_n','sdur2_d','sdur3_n','sdur3_d','sdur4_n','sdur4_d',
               'tertiary_n','tertiary_d']

def compress(in_path, out_path):
    with open(in_path) as f: d = json.load(f)
    out = {'metrics': METRIC_COLS, 'single': {}, 'pair': {}, 'labels': d.get('labels', {})}
    for dim, rows in d['data']['single'].items():
        compact = []
        for r in rows:
            row_data = [r['year'], r[dim]]
            for m in METRIC_COLS:
                v = r.get(m, 0)
                if v is None: row_data.append(0)
                elif abs(v) >= 1e6: row_data.append(round(v))
                else: row_data.append(round(v, 2))
            compact.append(row_data)
        out['single'][dim] = compact
    for pair_key, rows in d['data']['pair'].items():
        a, b = pair_key.split('__')
        compact = []
        for r in rows:
            row_data = [r['year'], r[a], r[b]]
            for m in METRIC_COLS:
                v = r.get(m, 0)
                if v is None: row_data.append(0)
                elif abs(v) >= 1e6: row_data.append(round(v))
                else: row_data.append(round(v, 2))
            compact.append(row_data)
        out['pair'][pair_key] = compact
    with open(out_path,'w') as f: json.dump(out, f, separators=(',',':'))
    sz = os.path.getsize(out_path)
    in_sz = os.path.getsize(in_path)
    print(f'{in_path} → {out_path}: {in_sz/1024/1024:.1f}MB → {sz/1024/1024:.1f}MB ({100*(1-sz/in_sz):.0f}% smaller)')

compress('/sessions/relaxed-focused-wozniak/mnt/outputs/agg_10_24_v8.json',
         '/sessions/relaxed-focused-wozniak/mnt/outputs/agg_10_24_v8_compact.json')
compress('/sessions/relaxed-focused-wozniak/mnt/outputs/agg_97_24_v8.json',
         '/sessions/relaxed-focused-wozniak/mnt/outputs/agg_97_24_v8_compact.json')
