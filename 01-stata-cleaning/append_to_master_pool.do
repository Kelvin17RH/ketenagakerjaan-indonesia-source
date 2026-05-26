**=========================================================================
** APPEND PER-YEAR UPDATED .DTA FILES INTO MASTER POOLED DATASETS
**
** Input  : clean_sakernas_YYYY_updated.dta (1997-2024, in this folder)
**          — already contains old vars + 12 NEW vars (hour, underemp_invol,
**            underemp_vol, hour_under/vol/invol, status, worktype,
**            formal_simple/new/old)
** Output : clean_sakernas_10_24_updated.dta (~2 GB, 9.3M rows, 2010-2024)
**          clean_sakernas_97_24_updated.dta (~3 GB, 13.9M rows, 1997-2024)
**
** Run time: ~2-5 minutes total in Stata
**=========================================================================

clear all
set more off
* Adjust if your working folder is different:
cd "your/path/to/Indonesia Labour in Numbers/clean"

* ----- Master 2010-2024 -----
clear
foreach y of numlist 2010/2024 {
    cap append using "clean_sakernas_`y'_updated.dta", force
    if !_rc di "  appended `y'"
}
compress
save "clean_sakernas_10_24_updated.dta", replace
di "Saved master 10-24"

* ----- Master 1997-2024 -----
clear
foreach y of numlist 1997/2024 {
    cap append using "clean_sakernas_`y'_updated.dta", force
    if !_rc di "  appended `y'"
}
compress
save "clean_sakernas_97_24_updated.dta", replace
di "Saved master 97-24"

di _newline "ALL DONE"
