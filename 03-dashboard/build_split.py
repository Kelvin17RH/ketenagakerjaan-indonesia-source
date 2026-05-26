"""Bake split build: shell HTML + separate data/*.json files for big cubes.

Phase 2: externalize 5 cubes (CUBE10 + CUBE97 + NEWVARS + NEWVARS2 + MEDIANS_PAIR).
Shell drops from 98 MB → ~3 MB.

Output:
  PROJ_DIR/index.html              # the shell (~3 MB, small cubes still inlined)
  PROJ_DIR/data/cube_10_24.json    # ~40 MB raw, ~4-5 MB gzipped
  PROJ_DIR/data/cube_97_24.json    # ~30 MB raw, ~3-4 MB gzipped
  PROJ_DIR/data/newvars_cube.json  # ~20 MB raw, ~2-3 MB gzipped
  PROJ_DIR/data/newvars2_cube.json # ~6 MB raw, <1 MB gzipped
  PROJ_DIR/data/medians_pair.json  # ~2 MB raw, <500 KB gzipped
"""
import os, sys, shutil

OUT_DIR = '/sessions/relaxed-focused-wozniak/mnt/outputs'
PROJ_DIR = '/sessions/relaxed-focused-wozniak/mnt/Indonesia Labour in Numbers'
DATA_DIR = f'{PROJ_DIR}/data'

os.makedirs(DATA_DIR, exist_ok=True)

with open(f'{OUT_DIR}/dashboard_template.html') as f: tpl = f.read()
def load_raw(p):
    with open(p) as f: return f.read()

# Substitute SMALL cubes inline (still in HTML)
out = tpl.replace('__DATA_JSON__', load_raw(f'{OUT_DIR}/extended_data.json')) \
         .replace('__PROD_WAGE__', load_raw(f'{OUT_DIR}/prod_wage_gap.json')) \
         .replace('__INEQUALITY__',load_raw(f'{OUT_DIR}/inequality.json')) \
         .replace('__MEDIANS__',   load_raw(f'{OUT_DIR}/medians.json')) \
         .replace('__MEDIANS_ALL__', load_raw(f'{OUT_DIR}/medians_all.json')) \
         .replace('__WAGE_ALL__',  load_raw(f'{OUT_DIR}/wage_all.json')) \
         .replace('__LABOR_SPACE__', load_raw(f'{OUT_DIR}/labor_space.json'))

# LARGE cubes — replace placeholders with empty stubs (fetched at runtime)
EMPTY_CUBE = '{"metrics":[],"single":{},"pair":{},"labels":{}}'
out = out.replace('__CUBE_10__', EMPTY_CUBE)
out = out.replace('__CUBE_97__', EMPTY_CUBE)
out = out.replace('__NEWVARS__', EMPTY_CUBE)
out = out.replace('__NEWVARS2__', EMPTY_CUBE)
out = out.replace('__MEDIANS_PAIR__', '{"metrics":[],"pair":{}}')

# Write the shell HTML
dest_html = f'{PROJ_DIR}/index.html'
with open(dest_html, 'w') as f: f.write(out)
sz_html = os.path.getsize(dest_html) / 1024 / 1024
print(f'Wrote {dest_html} ({sz_html:.2f} MB)')

# Copy the big cube JSON files to data/ folder for fetch()
CUBES = [
    ('agg_10_24_v8_compact.json',  'cube_10_24.json'),
    ('agg_97_24_v8_compact.json',  'cube_97_24.json'),
    ('newvars_cube.json',          'newvars_cube.json'),
    ('newvars2_cube.json',         'newvars2_cube.json'),
    ('medians_pair.json',          'medians_pair.json'),
]
total_data = 0
for src, dst in CUBES:
    src_path = f'{OUT_DIR}/{src}'
    dst_path = f'{DATA_DIR}/{dst}'
    shutil.copy(src_path, dst_path)
    sz = os.path.getsize(dst_path) / 1024 / 1024
    total_data += sz
    print(f'Wrote {dst_path} ({sz:.2f} MB)')

# Copy the Open Graph image (1200×630 PNG) next to index.html so social cards work.
og_src = f'{OUT_DIR}/og-image.png'
og_dst = f'{PROJ_DIR}/og-image.png'
if os.path.exists(og_src):
    shutil.copy(og_src, og_dst)
    print(f'Wrote {og_dst} ({os.path.getsize(og_dst)/1024:.1f} KB)')

# Sanity check: no placeholders remaining
for ph in ['__DATA_JSON__','__CUBE_10__','__CUBE_97__','__PROD_WAGE__','__INEQUALITY__',
           '__MEDIANS__','__MEDIANS_ALL__','__WAGE_ALL__','__NEWVARS__','__NEWVARS2__','__MEDIANS_PAIR__','__LABOR_SPACE__']:
    if ph in out: print(f'  WARN: placeholder {ph} still present!'); sys.exit(2)
print('OK: all placeholders substituted, 5 big cubes externalized')
print(f'Shell HTML: {sz_html:.2f} MB | Data folder: {total_data:.2f} MB | Total: {sz_html+total_data:.2f} MB')
print(f'After gzip (estimated on Netlify): shell ~{sz_html*0.18:.1f} MB + data ~{total_data*0.12:.1f} MB')
