"""Aggregator v6 (BPS-compliant):
- unemp_d = wt * lf  → TPT (Tingkat Pengangguran Terbuka)
- informal_d, whitecoll_d, underemp_d, certif_d = wt * employed  → % di antara pekerja
- neet_n, neet_d → NEET pemuda 15-24 (BPS)
- act_school/hh/other _d = wt * (1-lf) → % di antara bukan angkatan kerja
- tertiary_d = wt * age15plus → % pendidikan tinggi di antara penduduk 15+
- Tambah lf_n/lf_d (LFPR), emp_n/emp_d (EPR)
"""
import pandas as pd, numpy as np, json, os, time, gc, sys, pickle

FP10 = '/sessions/relaxed-focused-wozniak/mnt/Indonesia Labour in Numbers/finaloutput/final_sakernas_10_24.dta'
FP97 = '/sessions/relaxed-focused-wozniak/mnt/Indonesia Labour in Numbers/finaloutput/final_sakernas_97_24.dta'

COLS_10 = ['year','wt','urban','male','agegroup','region','prov_34',
    'educ_group','heduc','sector6','sector17','sector9','sector3','educ_major',
    'worktype','work_status','status','status_earn','work_informal','work_certif',
    'unemp','employment','lf','work_whitecoll','act_neet','act_school','act_household','act_others',
    'work_hours','work_wage','real_work_wage','underemp','agriculture',
    'school_years','work_jobdur','work_searchdur_1','work_searchdur_2','work_searchdur_3','work_searchdur_4',
    'minwage','pop15_64']
COLS_97 = ['year','wt','urban','male','agegroup','region','prov_34',
    'educ_group','sector9','sector3','sector17','work_status',
    'work_informal','work_certif','unemp','employment','lf','work_whitecoll',
    'act_neet','act_school','act_household','act_others','work_hours',
    'work_wage','real_wage','underemp','mid','poor','vul','asp','upp','agriculture',
    'school_years','work_jobdur','work_searchdur_1','work_searchdur_2','work_searchdur_3','work_searchdur_4',
    'under_ump']

DIMS_10 = ['urban','male','agegroup','region','prov_34','educ_group','heduc',
           'sector6','sector17','sector9','sector3','educ_major','worktype','work_status',
           'status','status_earn','work_certif','agriculture','lf','act_neet']
DIMS_97 = ['urban','male','agegroup','region','prov_34','educ_group',
           'sector3','sector9','sector17','work_status','work_certif','agriculture','lf','act_neet']

def build_pairs(dims, primary):
    pairs = set()
    def add(a,b):
        if a!=b: pairs.add(tuple(sorted([a,b])))
    for d in primary:
        for o in dims:
            if o!=d: add(d, o)
    return [tuple(p) for p in pairs]

PAIRS_10 = build_pairs(DIMS_10, ['urban','male','agegroup','region','prov_34','educ_group','heduc',
                                  'sector17','sector6','sector9','worktype','status','educ_major','work_status'])
PAIRS_97 = build_pairs(DIMS_97, ['urban','male','agegroup','region','prov_34','educ_group','sector9','sector17','work_status'])

# v6 metrics — explicit denominators per BPS convention
METRIC_COLS = ['pop',
               'lf_n','lf_d',                  # LFPR: lf_n/lf_d  (denom = wt*age15plus)
               'emp_n','emp_d',                # EPR:  emp_n/emp_d (denom = wt*age15plus)
               'wage_real_n','wage_real_d','wage_nom_n','wage_nom_d',
               'hours_n','hours_d',
               'informal_n','informal_d',      # informal_d = wt*employed
               'unemp_n','unemp_d',            # unemp_d   = wt*lf  → TPT
               'whitecoll_n','whitecoll_d',    # whitecoll_d = wt*employed
               'neet_n','neet_d',              # NEET pemuda 15-24
               'underemp_n','underemp_d',      # underemp_d = wt*employed
               'certif_n','certif_d',          # certif_d   = wt*employed
               'school_n','school_d',
               'jobdur_n','jobdur_d',
               'act_school_n','act_school_d',  # act_*_d = wt*(1-lf)
               'act_hh_n','act_hh_d',
               'act_other_n','act_other_d',
               'under_ump_n','under_ump_d',
               'sdur1_n','sdur1_d','sdur2_n','sdur2_d','sdur3_n','sdur3_d','sdur4_n','sdur4_d',
               'tertiary_n','tertiary_d']      # tertiary_d = wt*age15plus

def stream_one_run(fp, cols, dims, pairs, wage_real_col, year_min, ckpt_path, has_under_ump, has_heduc, max_chunks, chunk_size=250000):
    accum = None; resume_from = 0
    if os.path.exists(ckpt_path):
        try:
            with open(ckpt_path,'rb') as f: ck=pickle.load(f)
            accum=ck['accum']; resume_from=ck['n_chunks']
            print(f'Resume {resume_from}', flush=True)
        except: pass
    if accum is None:
        accum = {f's__{d}':{} for d in dims}
        for a,b in pairs: accum[f'p__{a}__{b}'] = {}

    n_chunks=0; t0=time.time(); processed=0; done=False
    reader = pd.read_stata(fp, columns=cols, chunksize=chunk_size, convert_categoricals=False)
    for chunk in reader:
        n_chunks += 1
        if n_chunks <= resume_from: del chunk; continue
        # BUG FIX: cek max_chunks SEBELUM increment-counted; kalau break, kembalikan n_chunks
        if processed >= max_chunks:
            n_chunks -= 1  # don't claim we processed this chunk
            del chunk; break
        yr_f = chunk['year'].astype('float32').to_numpy()
        keep = yr_f >= year_min
        if not keep.any(): del chunk; processed+=1; continue
        chunk = chunk.loc[keep].reset_index(drop=True)
        wt = chunk['wt'].astype('float32').fillna(0).to_numpy()
        wr = chunk[wage_real_col].astype('float32').fillna(0).to_numpy()
        wn = chunk['work_wage'].astype('float32').fillna(0).to_numpy()
        hr = chunk['work_hours'].astype('float32').fillna(0).to_numpy()
        sy = chunk['school_years'].astype('float32').fillna(0).to_numpy()
        jd = chunk['work_jobdur'].astype('float32').fillna(0).to_numpy()
        unemp = chunk['unemp'].astype('float32').fillna(0).to_numpy()
        lf_v = chunk['lf'].astype('float32').fillna(0).to_numpy()
        emp_v = chunk['employment'].astype('float32').fillna(0).to_numpy() if 'employment' in chunk.columns else ((lf_v==1)&(unemp==0)).astype('float32')
        age_v = chunk['agegroup'].astype('float32').fillna(-1).to_numpy()
        age15plus = (age_v >= 1).astype('float32')      # agegroup 1..10 = 15-19..>=60
        age15_24  = ((age_v >= 1) & (age_v <= 2)).astype('float32')  # 15-19 + 20-24
        notlf = (1.0 - lf_v).astype('float32')

        # Tertiary indicator: heduc >= 6 (D1+) — only available in 10_24
        if has_heduc and 'heduc' in chunk.columns:
            heduc_v = chunk['heduc'].astype('float32').fillna(-1).to_numpy()
            tert_flag = (heduc_v >= 6).astype('float32')
        else:
            tert_flag = np.zeros(len(chunk), dtype='float32')
        wmr = (wr>0).astype('float32'); wmn = (wn>0).astype('float32'); hm = (hr>0).astype('float32')
        sym = (sy>=0).astype('float32')
        jdm = ((jd>0) & (unemp==1)).astype('float32')

        df = pd.DataFrame({'year': chunk['year'].astype('int32')})
        for d in dims:
            if d in chunk.columns: df[d] = chunk[d].astype('float32')
            else: df[d] = np.nan

        # Core counts
        df['pop'] = wt
        df['lf_n']  = wt * lf_v
        df['lf_d']  = wt * age15plus
        df['emp_n'] = wt * emp_v
        df['emp_d'] = wt * age15plus

        # Wages & hours (denom = wage earners / valid hours)
        df['wage_real_n']=wt*wr*wmr; df['wage_real_d']=wt*wmr
        df['wage_nom_n']=wt*wn*wmn; df['wage_nom_d']=wt*wmn
        df['hours_n']=wt*hr*hm; df['hours_d']=wt*hm
        df['school_n']=wt*sy*sym; df['school_d']=wt*sym
        df['jobdur_n']=wt*jd*jdm; df['jobdur_d']=wt*jdm

        # Indicators with BPS-correct denominators
        informal_v   = chunk['work_informal'].astype('float32').fillna(0).to_numpy()
        whitecoll_v  = chunk['work_whitecoll'].astype('float32').fillna(0).to_numpy()
        underemp_v   = chunk['underemp'].astype('float32').fillna(0).to_numpy()
        certif_v     = chunk['work_certif'].astype('float32').fillna(0).to_numpy()
        act_neet_v   = chunk['act_neet'].astype('float32').fillna(0).to_numpy()
        act_school_v = chunk['act_school'].astype('float32').fillna(0).to_numpy()
        act_hh_v     = chunk['act_household'].astype('float32').fillna(0).to_numpy()
        act_oth_v    = chunk['act_others'].astype('float32').fillna(0).to_numpy()

        # % di antara pekerja (employed)
        df['informal_n']  = wt * informal_v;   df['informal_d']  = wt * emp_v
        df['whitecoll_n'] = wt * whitecoll_v;  df['whitecoll_d'] = wt * emp_v
        df['underemp_n']  = wt * underemp_v;   df['underemp_d']  = wt * emp_v
        df['certif_n']    = wt * certif_v;     df['certif_d']    = wt * emp_v

        # TPT: % di antara angkatan kerja
        df['unemp_n'] = wt * unemp;            df['unemp_d'] = wt * lf_v

        # NEET pemuda 15-24
        df['neet_n'] = wt * act_neet_v * age15_24
        df['neet_d'] = wt * age15_24

        # Aktivitas: % di antara Bukan Angkatan Kerja
        df['act_school_n'] = wt * act_school_v; df['act_school_d'] = wt * notlf
        df['act_hh_n']     = wt * act_hh_v;     df['act_hh_d']     = wt * notlf
        df['act_other_n']  = wt * act_oth_v;    df['act_other_d']  = wt * notlf

        # under_ump: % di antara pekerja berupah (sudah benar di v5)
        if has_under_ump and 'under_ump' in chunk.columns:
            uu = chunk['under_ump'].astype('float32').fillna(0).to_numpy()
            df['under_ump_n'] = wt * uu * wmn
            df['under_ump_d'] = wt * wmn
        else:
            df['under_ump_n'] = 0.0; df['under_ump_d'] = 0.0

        # Durasi pencarian kerja (distribusi di antara penganggur)
        for k in [1,2,3,4]:
            v = chunk[f'work_searchdur_{k}'].astype('float32').fillna(0).to_numpy()
            df[f'sdur{k}_n'] = wt * v
            df[f'sdur{k}_d'] = wt * unemp

        # Tertiary: % di antara penduduk 15+
        df['tertiary_n'] = wt * tert_flag
        df['tertiary_d'] = wt * age15plus

        del chunk, wt, wr, wn, hr, sy, jd, unemp, wmr, wmn, hm, sym, jdm, tert_flag
        del lf_v, emp_v, age_v, age15plus, age15_24, notlf
        del informal_v, whitecoll_v, underemp_v, certif_v, act_neet_v, act_school_v, act_hh_v, act_oth_v
        gc.collect()

        for d in dims:
            sub = df[['year',d]+METRIC_COLS].dropna(subset=['year',d])
            if sub.empty: continue
            sub=sub.copy(); sub[d]=sub[d].astype('int32')
            g = sub.groupby(['year',d], sort=False, observed=True)[METRIC_COLS].sum()
            store = accum[f's__{d}']
            for key,row in g.iterrows():
                k=(int(key[0]),int(key[1])); v=row.values
                if k in store: store[k]+=v
                else: store[k]=v.copy()
        for a,b in pairs:
            sub = df[['year',a,b]+METRIC_COLS].dropna(subset=['year',a,b])
            if sub.empty: continue
            sub=sub.copy(); sub[a]=sub[a].astype('int32'); sub[b]=sub[b].astype('int32')
            g = sub.groupby(['year',a,b], sort=False, observed=True)[METRIC_COLS].sum()
            store = accum[f'p__{a}__{b}']
            for key,row in g.iterrows():
                k=(int(key[0]),int(key[1]),int(key[2])); v=row.values
                if k in store: store[k]+=v
                else: store[k]=v.copy()
        del df; gc.collect()
        processed += 1
        if processed % 3 == 0:
            print(f'  chunk {n_chunks} (run: {processed}) t={time.time()-t0:.1f}s', flush=True)
    else: done=True

    # Atomic checkpoint write: write to tmp then rename
    tmp_path = ckpt_path + '.tmp'
    with open(tmp_path,'wb') as f: pickle.dump({'accum':accum,'n_chunks':n_chunks,'done':done}, f)
    os.replace(tmp_path, ckpt_path)
    print(f'Run done processed={processed} n={n_chunks} done={done} t={time.time()-t0:.1f}s', flush=True)
    return accum, done

def serialize(accum, dims, pairs):
    final={'single':{},'pair':{}}
    for d in dims:
        rows=[]
        for k,v in accum[f's__{d}'].items():
            rec={'year':k[0], d:k[1]}
            for ci,c in enumerate(METRIC_COLS):
                rec[c] = round(float(v[ci]),2)
            rows.append(rec)
        final['single'][d] = rows
    for a,b in pairs:
        rows=[]
        for k,v in accum[f'p__{a}__{b}'].items():
            rec={'year':k[0], a:k[1], b:k[2]}
            for ci,c in enumerate(METRIC_COLS):
                rec[c] = round(float(v[ci]),2)
            rows.append(rec)
        final['pair'][f'{a}__{b}'] = rows
    return final

if __name__=='__main__':
    target = sys.argv[1] if len(sys.argv)>1 else '10'
    max_chunks = int(sys.argv[2]) if len(sys.argv)>2 else 3
    if target=='10':
        ckpt = '/sessions/relaxed-focused-wozniak/mnt/outputs/ckpt_10_v8.pkl'
        accum,done = stream_one_run(FP10, COLS_10, DIMS_10, PAIRS_10, 'real_work_wage', 2010, ckpt, False, True, max_chunks)
        if done:
            out = serialize(accum, DIMS_10, PAIRS_10)
            with pd.io.stata.StataReader(FP10) as r: vl = r.value_labels()
            labels = {k: {int(kk): str(vv) for kk,vv in v.items()} for k,v in vl.items()}
            op = '/sessions/relaxed-focused-wozniak/mnt/outputs/agg_10_24_v8.json'
            with open(op,'w') as f: json.dump({'data':out,'labels':labels}, f, separators=(',',':'))
            print('FINAL', op, os.path.getsize(op))
    else:
        ckpt = '/sessions/relaxed-focused-wozniak/mnt/outputs/ckpt_97_v8.pkl'
        accum,done = stream_one_run(FP97, COLS_97, DIMS_97, PAIRS_97, 'real_wage', 1997, ckpt, True, False, max_chunks)
        if done:
            out = serialize(accum, DIMS_97, PAIRS_97)
            with pd.io.stata.StataReader(FP97) as r: vl = r.value_labels()
            labels = {k: {int(kk): str(vv) for kk,vv in v.items()} for k,v in vl.items()}
            op = '/sessions/relaxed-focused-wozniak/mnt/outputs/agg_97_24_v8.json'
            with open(op,'w') as f: json.dump({'data':out,'labels':labels}, f, separators=(',',':'))
            print('FINAL', op, os.path.getsize(op))
