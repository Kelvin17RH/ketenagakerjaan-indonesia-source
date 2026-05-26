
/**************************************************************************
 * SAKERNAS PROCESSING PIPELINE
 * Import, recode, clean, and append Sakernas microdata 1997-2024
 **************************************************************************/

 

clear
set more off

*-----------------------------------------------------------
* Date Stamp (if S_DATE is provided in environment)
*-----------------------------------------------------------
local datestamp: di %tdCYND daily("$S_DATE", "DMY")
di "Datestamp: `datestamp'"

*-----------------------------------------------------------
* Global Macros for File Paths
*-----------------------------------------------------------
gl user    = c(username)
if 0 {
    cd "your/working/directory"
}

gl source  "your_project_root/sakernas"
gl import  "your_project_root/import"
gl output  "your_project_root/output"
gl dofile  "your_project_root/dofile"
gl comp    "your_project_root/compressed"
gl clean   "your_project_root/clean"
gl finaloutput "your_project_root/finaloutput"

*----------------------------------------------------------------------------------------------------------
* IMPORTING CORRESPONDENCE CODE (currently commented out until find the agreed correspondence)
*----------------------------------------------------------------------------------------------------------
/*
***********************************
** IMPORTING CORRESPONDENCE CODE ** -> Need to be updated with newer data
***********************************

** Korespondensi Sektor
import delimited "$import/your_sector_file.csv", encoding(utf8) clear
tempfile corsector
save `corsector'

** Korespondensi Provinsi
import delimited "$import/your_province_file.csv", encoding(utf8) clear
tempfile corprov
save `corprov'

** Consumer Price Index (1996 = 100)
import delimited "$import/your_cpi_file.csv", encoding(utf8) clear
tempfile cpi
save `cpi'
*/


**---------------------------------------------------------------------------
** Formality Matrix (wrktype2011)
** Status (rows 1-7) × Occupation (columns 1-8). Cell = 1 if formal.
**---------------------------------------------------------------------------
#delimit ;
matrix wrktype2011 = J(7,8,0);
matrix input wrktype2011 = (
    1, 1, 1, 0, 0, 0, 0, 0 \\    /* status 1 */
    1, 1, 1, 1, 1, 0, 1, 0 \\    /* status 2 */
    1, 1, 1, 1, 1, 1, 1, 1 \\    /* status 3 */
    1, 1, 1, 1, 1, 1, 1, 1 \\    /* status 4 */
    1, 1, 1, 0, 0, 0, 0, 0 \\    /* status 5 */
    1, 1, 1, 0, 0, 0, 0, 0 \\    /* status 6 */
    0, 0, 0, 0, 0, 0, 0, 0      /* status 7 */
);
#delimit cr

*-----------------------------------------------------------
* SET YEAR AND IMPORT DATA
*-----------------------------------------------------------

/****************
 * Sakernas 1997 (numbers matched)
 ***************/
 
local year = 1997
use $source/sakernas_`year', clear

*-----------------------------------------------------------
* DESCRIPTIVE CONVERSION AND VARIABLE CREATION
*-----------------------------------------------------------
destring *, replace
sort B1P1 B1P5

// Generate worker/regional characteristics
gen prov`year'   = B1P1
gen wt           = TIMBANG
gen urban        = (B1P5 == 1)
gen male         = (B3P4 == 1)
gen age          = B3P5               // WARNING: AGE OUTSIDE LF DETECTED

* Adjust education: divide by 10 then floor the result
gen educ         = B4P1
replace educ     = educ/10
replace educ     = floor(educ)

*-----------------------------------------------------------
* EMPLOYMENT STRUCTURE
*-----------------------------------------------------------
* Unemployment (using conditions from the original coding)
gen unemp = .
replace unemp = 1 if B4P4A1 == 2 & B4P6 == 2 & B4P15 == 1
replace unemp = 0 if unemp != 1

* Employment (working people)
gen employment = .
replace employment = 1 if B4P4A1 == 1
replace employment = 1 if B4P6 == 1
replace employment = 0 if unemp == 1

* Labor Force (LF)
gen lf = .
replace lf = 1 if employment == 1
replace lf = 1 if unemp == 1
replace lf = 0 if age < 15
replace lf = 0 if lf != 1
replace unemp = . if lf == 0
replace employment = . if lf == 0

* Sector Categories (9 sectors)
gen sector9 = B4P8
replace sector9 = sector9/10
replace sector9 = floor(sector9)
replace sector9 = . if sector9 == 0

* Informality: using work type indicator
gen work_informal = inlist(B4P11, 1, 2, 5)

* Work Status
gen work_status = B4P11

* Job Certification: check across multiple variables
gen work_certif = .
foreach x of varlist B4P3A B4P3B B4P3C B4P3D B4P3E B4P3F B4P3G B4P3H {
    replace work_certif = 1 if `x' == 1
}
replace work_certif = 0 if work_certif != 1

* White-collar indicator
gen work_whitecoll = inrange(B4P9, 1, 59)

*-----------------------------------------------------------
* ACTIVITIES OUTSIDE LABOR FORCE
*-----------------------------------------------------------
gen act_school    = (B4P4A2 == 1 & B4P4B == 2 & lf == 0)
gen act_household = (B4P4A3 == 1 & B4P4B == 3 & lf == 0)
gen act_others    = (B4P4A5 == 1 & B4P4B == 5 & lf == 0)

* NEET (Not in Education, Employment, or Training)
gen act_neet = 0
replace act_neet = 1 if B4P4A1 == 2 & B4P4A2 == 2 & B4P4A4 == 2 
replace act_neet = 0 if act_school == 1
replace act_neet = . if age >= 25
replace act_neet = . if age <= 14

* Matching employment statistics with BPS report (manual adjustments)
replace employment = 1 if employment == 0 & work_status != .

*-----------------------------------------------------------
* WORK CHARACTERISTICS
*-----------------------------------------------------------
gen work_hours    = B4P10
gen work_earnings = B4P12A1 + B4P12A2
gen work_wage     = (B4P12A1 + B4P12A2) if B4P11 == 4
gen work_jobdur   = B4P18

* Recode education into groups
recode educ 0/2 = 1 3/6 = 2 7/9 = 3, generate(educ_group)

* Recode job duration into categorical groups
recode work_jobdur 0/3 = 1 4/12 = 2 12/24 = 3 25/99 = 4, gen(work_jobdur_cat)

* Estimate years of schooling based on education level
gen school_years = .
replace school_years = 0  if educ == 0
replace school_years = 0  if educ == 1
replace school_years = 6  if educ == 2
replace school_years = 9  if educ == 3
replace school_years = 9  if educ == 4
replace school_years = 12 if educ == 5
replace school_years = 12 if educ == 6
replace school_years = 14 if educ == 7
replace school_years = 15 if educ == 8
replace school_years = 16 if educ == 9

* Label for job search duration
la de searchdur 1 "1. <=3 bulan" 2 "2. 4-12 bulan" 3 "3. 13-24 bulan" 4 "4. >24 bulan"
la val work_jobdur_cat searchdur

* Create dummy variables for each job duration category
forval x = 1/4 {
    gen work_searchdur_`x' = (work_jobdur_cat == `x')
    replace work_searchdur_`x' = . if lf == 0 | work_jobdur_cat == .
}

* Set work-related variables to missing if not employed or not in LF
foreach var of varlist work_hours work_earnings work_wage {
    replace `var' = . if employment == 0 | lf == 0
}

* Assign year variable and drop unwanted observations
gen year = `year'
drop if prov == 54  // Exclude Timor-Timor observations

*-----------------------------------------------------------
* SAVE TEMPORARY OUTPUT
*-----------------------------------------------------------
save $output/percobaan_sakernas_`year', replace

*-----------------------------------------------------------
* CREATE CLEAN DATASET: KEEP ONLY SELECT VARIABLES
*-----------------------------------------------------------
keep prov`year' wt urban male age educ unemp employment lf school_years sector9 ///
       work_informal work_status act_neet act_school act_household act_others ///
       work_hours work_whitecoll work_earnings work_wage work_jobdur* educ_group ///
       work_searchdur_* year


**---------------------------------------------------------------------------
** Derived Labour Indicators (1997: limited raw data, set to missing)
**---------------------------------------------------------------------------
foreach v in hour underemp underemp_invol underemp_vol hour_under hour_vol hour_invol status worktype formal_simple formal_new formal_old {
    cap gen `v' = .
}

save $clean/percobaan_sakernas_`year', replace

/*************************
 * End of Sakernas 1997
 ************************/

/****************
 * Sakernas 1998 (numbers matched)
 ***************/

clear
set more off

*-----------------------------------------------------------
* Set Year and Import Data
*-----------------------------------------------------------
local year = 1998
use $source/sakernas_`year', clear

*-----------------------------------------------------------
* Variable Conversion
*-----------------------------------------------------------
destring *, replace

*-----------------------------------------------------------
* Generate Basic Variables
*-----------------------------------------------------------
gen prov`year'   = B1P1
gen wt           = TIMBANG
gen urban        = (B1P5 == 1)
gen male         = (B3P4 == 1)  // Note: Ensure B3P4 is available; if not, adjust accordingly.
gen age          = B3P5       // WARNING: AGE OUTSIDE LF DETECTED
gen educ         = B4P1A
* Unemployment: using conditions for 1998
gen unemp = .
replace unemp = 1 if B4P2A1 == 2 & B4P4 == 2 & B4P13 == 1
replace unemp = 0 if unemp != 1
* Employment: assign working status
gen employment = .
replace employment = 1 if B4P2A1 == 1
replace employment = 1 if B4P4 == 1
replace employment = 0 if unemp == 1

*-----------------------------------------------------------
* Labor Force and Sector Classification
*-----------------------------------------------------------
gen lf = .
replace lf = 1 if employment == 1
replace lf = 1 if unemp == 1
replace lf = 0 if age < 15
replace lf = 0 if lf != 1
replace unemp = . if lf == 0
replace employment = . if lf == 0

* Sector classification (9 sectors)
gen sector9 = B4P6
replace sector9 = sector9/10
replace sector9 = floor(sector9)

*-----------------------------------------------------------
* Work Status and Informality
*-----------------------------------------------------------
gen work_informal = inlist(B4P9, 1, 2, 5)
gen work_status   = B4P9
* White-collar indicator
gen work_whitecoll = inrange(B4P7, 1, 59)

*-----------------------------------------------------------
* Activities Outside the Labor Force
*-----------------------------------------------------------
gen act_school    = (B4P2A2 == 1 & B4P2B == 2 & lf == 0)
gen act_household = (B4P2A3 == 1 & B4P2B == 3 & lf == 0)
gen others = 0 if (act_school == 1 | act_household == 1)
replace others = 1 if others == .
gen act_others= lf == 0 & others == 1

gen act_neet      = 0
replace act_neet = 1 if B4P2A1 == 2 & B4P2A2 == 2
replace act_neet = 0 if act_school == 1
replace act_neet = . if age >= 25
replace act_neet = . if age <= 14

* Matching employment statistics with BPS report (manual adjustment)
replace employment = 1 if employment == 0 & work_status != .

*-----------------------------------------------------------
* Work Characteristics
*-----------------------------------------------------------
gen work_hours    = B4P8
gen work_earnings = B4P10A + B4P10B
gen work_wage     = (B4P10A + B4P10B) if B4P9 == 4
gen work_jobdur   = B4P16

*-----------------------------------------------------------
* Recode Education and Job Duration
*-----------------------------------------------------------
recode educ 0 = 3 1/3 = 1 4/7 = 2 8/9 = 3, generate(educ_group)
recode work_jobdur 0/3 = 1 4/12 = 2 12/24 = 3 25/99 = 4, gen(work_jobdur_cat)

* Estimate years of schooling based on education level
gen school_years = .
replace school_years = 0  if educ == 1
replace school_years = 0  if educ == 2
replace school_years = 6  if educ == 3
replace school_years = 9  if educ == 4
replace school_years = 9  if educ == 5
replace school_years = 12 if educ == 6
replace school_years = 12 if educ == 7
replace school_years = 14 if educ == 8
replace school_years = 15 if educ == 9
replace school_years = 16 if educ == 0

*-----------------------------------------------------------
* Job Search Duration Labels and Dummies
*-----------------------------------------------------------
la de searchdur 1 "1. <=3 bulan" 2 "2. 4-12 bulan" ///
                 3 "3. 13-24 bulan" 4 "4. >24 bulan"
la val work_jobdur_cat searchdur

forval x = 1/4 {
    gen work_searchdur_`x' = (work_jobdur_cat == `x')
}
forval x = 1/4 {
    replace work_searchdur_`x' = . if lf == 0
    replace work_searchdur_`x' = . if work_jobdur_cat == .
}

*-----------------------------------------------------------
* Set Work Variable Missing for Non-employed / Not in LF
*-----------------------------------------------------------
foreach var of varlist work_hours work_earnings work_wage {
    replace `var' = . if unemp == 1 | lf == 0
}

*-----------------------------------------------------------
* Final Adjustments and Save
*-----------------------------------------------------------
gen year = `year'
drop if prov`year' == 54   // Drop observations for Timor-Timor

* Save temporary master dataset
// save $output/temp_sakernas_`year', replace

* Save clean dataset (separating out key variables)
keep prov`year' wt urban male age educ unemp employment lf school_years sector9 ///
     work_informal work_status act_neet act_school act_household act_others work_hours work_whitecoll ///
     work_earnings work_wage work_jobdur* educ_group work_searchdur_* year

**---------------------------------------------------------------------------
** Derived Labour Indicators (1998: limited raw data, set to missing)
**---------------------------------------------------------------------------
foreach v in hour underemp underemp_invol underemp_vol hour_under hour_vol hour_invol status worktype formal_simple formal_new formal_old {
    cap gen `v' = .
}

save $clean/clean_sakernas_`year', replace

/*************************
 * End of Sakernas 1998
 ************************/
 
/*************************
 * Sakernas 1999 (numbers matched)
 ************************/

clear
set more off

*-----------------------------------------------------------
* Set Year and Import Data
*-----------------------------------------------------------
local year = 1999
use "$source/sakernas_`year'", clear

*-----------------------------------------------------------
* Generate Basic Variables
*-----------------------------------------------------------
gen prov`year'   = B1P1
gen wt           = WEIGHT
gen urban        = (B1P5 == 1)
gen male         = (B3K4 == 1)
gen age          = B3K5            // WARNING: AGE OUTSIDE LF DETECTED
gen educ         = B4P1A

*-----------------------------------------------------------
* Employment Status Calculation
*-----------------------------------------------------------
* Unemployment indicator
gen unemp = .
replace unemp = 1 if B4P2A1 == 2 & B4P4 == 2 & B4P13 == 1
replace unemp = 0 if unemp != 1

* Employment indicator
gen employment = .
replace employment = 1 if B4P2A1 == 1
replace employment = 1 if B4P4 == 1
replace employment = 0 if unemp == 1

*-----------------------------------------------------------
* Labor Force (LF) Determination
*-----------------------------------------------------------
gen lf = .
replace lf = 1 if employment == 1
replace lf = 1 if unemp == 1
replace lf = 0 if age < 15
replace lf = 0 if lf != 1
replace unemp = . if lf == 0
replace employment = . if lf == 0

*-----------------------------------------------------------
* Sector and Work Characteristics
*-----------------------------------------------------------
* Sector classification: 9 sectors
gen sector9 = B4P6
replace sector9 = sector9/10
replace sector9 = floor(sector9)

* Work informality indicator
gen work_informal = inlist(B4P9, 1, 2, 5)

* Work status variable
gen work_status = B4P9

* White-collar indicator based on B4P7
gen work_whitecoll = inrange(B4P7, 1, 59)

*-----------------------------------------------------------
* Activities Outside the Labor Force
*-----------------------------------------------------------
gen act_school    = (B4P2A2 == 1 & B4P2B == 2 & lf == 0)
gen act_household = (B4P2A3 == 1 & B4P2B == 3 & lf == 0)
gen others = 0 if (act_school == 1 | act_household == 1)
replace others = 1 if others == .
gen act_others= lf == 0 & others == 1

gen act_neet = 0
replace act_neet = 1 if B4P2A1 == 2 & B4P2A2 == 2
replace act_neet = 0 if act_school == 1
replace act_neet = . if age >= 25
replace act_neet = . if age <= 14

* Matching employment statistics with BPS report (manual adjustment)
replace employment = 1 if employment == 0 & work_status != .

*-----------------------------------------------------------
* Work Characteristics
*-----------------------------------------------------------
gen work_hours    = B4P8
gen work_earnings = B4P10A1 + B4P10A2
gen work_wage     = (B4P10A1 + B4P10A2) if B4P9 == 4
gen work_jobdur   = B4P16

*-----------------------------------------------------------
* Recode Education and Job Duration
*-----------------------------------------------------------
recode educ 0 = 3 1/3 = 1 4/7 = 2 8/9 = 3, generate(educ_group)
recode work_jobdur 0/3 = 1 4/12 = 2 12/24 = 3 25/99 = 4, gen(work_jobdur_cat)

gen school_years = .
replace school_years = 0  if educ == 1
replace school_years = 0  if educ == 2
replace school_years = 6  if educ == 3
replace school_years = 9  if educ == 4
replace school_years = 9  if educ == 5
replace school_years = 12 if educ == 6
replace school_years = 12 if educ == 7
replace school_years = 14 if educ == 8
replace school_years = 15 if educ == 9
replace school_years = 16 if educ == 0

*-----------------------------------------------------------
* Job Search Duration: Labels and Dummy Variables
*-----------------------------------------------------------
la de searchdur 1 "1. <=3 bulan" 2 "2. 4-12 bulan" ///
                 3 "3. 13-24 bulan" 4 "4. >24 bulan"
la val work_jobdur_cat searchdur

forval x = 1/4 {
    gen work_searchdur_`x' = (work_jobdur_cat == `x')
}
forval x = 1/4 {
    replace work_searchdur_`x' = . if lf == 0
    replace work_searchdur_`x' = . if work_jobdur_cat == .
}

*-----------------------------------------------------------
* Set Work Variables to Missing for Non-employed/Non-LF
*-----------------------------------------------------------
foreach var of varlist work_hours work_earnings work_wage {
    replace `var' = . if unemp == 1
    replace `var' = . if lf == 0
}

*-----------------------------------------------------------
* Final Adjustments and Save Data
*-----------------------------------------------------------
gen year = `year'
* Save the master temporary dataset
// save $output/temp_sakernas_`year', replace

* Save clean dataset (separating out key variables)
keep prov`year' wt urban male age educ unemp employment lf school_years sector9 ///
     work_informal work_status act_neet act_school act_household act_others work_hours work_whitecoll ///
     work_earnings work_wage work_jobdur* educ_group work_searchdur_* year

**---------------------------------------------------------------------------
** Derived Labour Indicators (1999: limited raw data, set to missing)
**---------------------------------------------------------------------------
foreach v in hour underemp underemp_invol underemp_vol hour_under hour_vol hour_invol status worktype formal_simple formal_new formal_old {
    cap gen `v' = .
}

save $clean/clean_sakernas_`year', replace

/*************************
 * End of Sakernas 1999
 ************************/

/*************************
 * Sakernas 2000 (numbers matched)
 ************************/

clear
set more off

*-----------------------------------------------------------
* Set Year and Import Data
*-----------------------------------------------------------
local year = 2000
use $source/sakernas_`year', clear

*-----------------------------------------------------------
* Generate Basic Variables
*-----------------------------------------------------------
gen prov`year' = b1p01
gen wt         = timbang
gen urban      = (b1p05 == 1)
gen male       = (jk == 1)
gen age        = umur               // WARNING: AGE OUTSIDE LF DETECTED
gen educ       = b4p1a

*-----------------------------------------------------------
* Compute Unemployment and Employment Status
*-----------------------------------------------------------
gen unemp = .
replace unemp = 1 if b4p2a1 == 2 & b4p4 == 2 & b4p5 == 1
// replace unemp = 1 if b4p2a1 == 2 & inlist(b4p19,1)
replace unemp = 0 if unemp != 1

gen employment = .
replace employment = 1 if b4p2a1 == 1
replace employment = 1 if b4p4 == 1
replace employment = 0 if unemp == 1

*-----------------------------------------------------------
* Define Labor Force (LF)
*-----------------------------------------------------------
gen lf = .
replace lf = 1 if employment == 1 | unemp == 1
replace lf = 0 if age < 15
replace lf = 0 if lf != 1
replace unemp = . if lf == 0
replace employment = . if lf == 0

*-----------------------------------------------------------
* Sector Classification
*-----------------------------------------------------------
recode b4p7 0/59=1 100/149=2 150/379=3 400/419=4 450/459=5 500/559=6 600/649=7 650/749=8 750/999=9, generate(sector9)

*-----------------------------------------------------------
* Work Characteristics and Activity Variables
*-----------------------------------------------------------
gen work_informal = inlist(b4p10, 1, 2, 5)
gen work_status   = b4p10
// gen work_certif  = .   // (Not defined here)
gen work_whitecoll = inrange(b4p8, 1, 599)

gen act_school    = (b4p2a2 == 1 & b4p2b == 2 & lf == 0)
gen act_household = (b4p2a3 == 1 & b4p2b == 3 & lf == 0)
gen act_others    = (b4p2a4 == 1 & b4p2b == 4 & lf == 0)

gen act_neet = 0
replace act_neet = 1 if b4p2a1 == 2 & b4p2a2 == 2
replace act_neet = 0 if act_school == 1
// replace act_neet = 0 if act_household == 1
replace act_neet = . if age >= 25
replace act_neet = . if age <= 14

*-----------------------------------------------------------
* Matching Employment Statistics Adjustment
*-----------------------------------------------------------
replace employment = 1 if employment == 0 & work_status != .

*-----------------------------------------------------------
* Create Work-related Variables
*-----------------------------------------------------------
gen work_hours   = b4p9
gen work_earnings = b4p11a1 + b4p11a2
gen work_wage    = (b4p11a1 + b4p11a2) if b4p10 == 4
gen work_jobdur  = b4p17

*-----------------------------------------------------------
* Recode Education and Job Duration
*-----------------------------------------------------------
recode educ 0=3 1/3=1 4/7=2 8/9=3, generate(educ_group)
recode work_jobdur 0/3=1 4/12=2 12/24=3 25/99=4, gen(work_jobdur_cat)

*-----------------------------------------------------------
* Estimate Years of Schooling
*-----------------------------------------------------------
gen school_years = .
replace school_years = 0 if educ == 1 | educ == 2
replace school_years = 6 if educ == 3
replace school_years = 9 if educ == 4 | educ == 5
replace school_years = 12 if educ == 6 | educ == 7
replace school_years = 14 if educ == 8
replace school_years = 15 if educ == 9
replace school_years = 16 if educ == 0

*-----------------------------------------------------------
* Job Search Duration Dummies
*-----------------------------------------------------------
la de searchdur 1 "1. <=3 bulan" 2 "2. 4-12 bulan" 3 "3. 13-24 bulan" 4 "4. >24 bulan"
la val work_jobdur_cat searchdur

forval x = 1/4 {
    gen work_searchdur_`x' = (work_jobdur_cat == `x')
    replace work_searchdur_`x' = . if lf == 0 | work_jobdur_cat == .
}

*-----------------------------------------------------------
* Adjust Work Variables for Non-employment Cases
*-----------------------------------------------------------
foreach var of varlist work_hours work_earnings work_wage {
    replace `var' = . if unemp == 1 | lf == 0
}

*-----------------------------------------------------------
* Finalize and Save Dataset
*-----------------------------------------------------------
gen year = `year'
//save $output/temp_sakernas_`year', replace

* Save clean dataset (separating out key variables)
keep prov`year' wt urban male age educ unemp employment lf school_years sector9 work_informal ///
 work_status act_neet act_school act_others act_household work_hours work_whitecoll ///
 work_earnings work_wage work_jobdur* educ_group work_searchdur_* year

**---------------------------------------------------------------------------
** Derived Labour Indicators (2000: limited raw data, set to missing)
**---------------------------------------------------------------------------
foreach v in hour underemp underemp_invol underemp_vol hour_under hour_vol hour_invol status worktype formal_simple formal_new formal_old {
    cap gen `v' = .
}

save $clean/clean_sakernas_`year', replace


/*************************
 * End of Sakernas 2000
 ************************/

/*************************
 * Sakernas 2001 (numbers matched)
 ************************/
// NOTE: IRREGULAR PROV CODE

clear
set more off

* Set year and import data
local year = 2001
use $source/sakernas_`year', clear

*-----------------------------------------------------------
* Generate Identifier and Basic Variables
*-----------------------------------------------------------
gen prov`year' = b1p01
    // Adjust irregular province codes:
    replace prov = 81 if inrange(prov, 81, 82)
    replace prov = 82 if inrange(prov, 91, 93)
    replace prov = 32 if prov == 36
    replace prov = 71 if prov == 75
gen wt    = weight
gen urban = (b1p05 == 1)
gen male  = (jk == 1)
gen age   = umur   // WARNING: AGE OUTSIDE LF DETECTED
gen educ  = b4p1a

*-----------------------------------------------------------
* Compute Employment and Unemployment Status
*-----------------------------------------------------------
gen employment = .
    replace employment = 1 if b4p2a1 == 1
    replace employment = 1 if b4p3 == 1

gen unemp = .
    replace unemp = 1 if b4p2a1 == 2 & b4p3 == 2 & b4p4 == 1 
    replace unemp = 1 if b4p2a1 == 2 & b4p3 == 2 & b4p5 == 1 
    replace unemp = 1 if b4p2a1 == 2 & inlist(b4p21, 1, 2) & employment != 1
    replace unemp = 0 if unemp != 1
    replace employment = 0 if unemp == 1

*-----------------------------------------------------------
* Define Labor Force (LF)
*-----------------------------------------------------------
gen lf = .
    replace lf = 1 if employment == 1 | unemp == 1
    replace lf = 0 if age < 15
    replace lf = 0 if lf != 1
    replace unemp = . if lf == 0
    replace employment = . if lf == 0

*-----------------------------------------------------------
* Sector Classification and Work Variables
*-----------------------------------------------------------
recode b4p7 0/59 = 1 ///
       100/149 = 2 ///
       150/379 = 3 ///
       400/419 = 4 ///
       450/459 = 5 ///
       500/559 = 6 ///
       600/649 = 7 ///
       650/749 = 8 ///
       750/999 = 9, generate(sector9)

recode b4p7 	///
(011/100 =  1) (101/150 =  2) (151/400 =  3) ///
(401/403 =  4) (410 =  5)  (450/499 =  6) ///
(500/550 =  7) (601/633 635 639=  8) ///
(551 552 =  9) (641 642 = 10) (651/672 = 11) ///
(701/703 = 12) (634 711/750 = 13)  (751/753 = 14) ///
(801/809 = 15) (851/853 = 16) ///
(634 900/990 = 17) (0 = 18), gen(sector17)

gen work_informal = inlist(b4p10, 1, 2, 5)
gen work_status   = b4p10
// gen work_certif = .   // (Not defined here)
gen work_whitecoll = inrange(b4p8, 1, 599)

gen act_school    = (b4p2a2 == 1 & b4p2b == 2 & lf == 0)
gen act_household = (b4p2a3 == 1 & b4p2b == 3 & lf == 0)
gen act_others    = (b4p2a4 == 1 & b4p2b == 4 & lf == 0)
gen act_neet = 0
    replace act_neet = 1 if b4p2a1 == 2 & b4p2a2 == 2
    replace act_neet = 0 if act_school == 1
    // replace act_neet = 0 if act_household == 1
    replace act_neet = . if age >= 25
    replace act_neet = . if age <= 14

*-----------------------------------------------------------
* Adjust Employment to Match BPS Report
*-----------------------------------------------------------
replace employment = 1 if employment == 0 & work_status != .

*-----------------------------------------------------------
* Create Work-related Variables
*-----------------------------------------------------------
gen work_hours    = b4p9
gen work_earnings = b4p12a + b4p12b
gen work_wage     = (b4p12a + b4p12b) if b4p10 == 4
gen work_jobdur   = b4p19

*-----------------------------------------------------------
* Recodes and Derived Variables
*-----------------------------------------------------------
recode educ 0 = 3 1/3 = 1 4/7 = 2 8/9 = 3, generate(educ_group)
recode work_jobdur 0/3 = 1 4/12 = 2 12/24 = 3 25/99 = 4, gen(work_jobdur_cat)

gen school_years = .
    replace school_years = 0 if educ == 1
    replace school_years = 0 if educ == 2
    replace school_years = 6 if educ == 3
    replace school_years = 9 if educ == 4
    replace school_years = 9 if educ == 5
    replace school_years = 12 if educ == 6
    replace school_years = 12 if educ == 7
    replace school_years = 14 if educ == 8
    replace school_years = 15 if educ == 9
    replace school_years = 16 if educ == 0

*-----------------------------------------------------------
* Job Search Duration Dummies
*-----------------------------------------------------------
la de searchdur 1 "1. <=3 bulan" 2 "2. 4-12 bulan" ///
                 3 "3. 13-24 bulan" 4 "4. >24 bulan"
la val work_jobdur_cat searchdur

forval x = 1/4 {
    gen work_searchdur_`x' = (work_jobdur_cat == `x')
    replace work_searchdur_`x' = . if lf == 0 | work_jobdur_cat == .
}

foreach var of varlist work_hours work_earnings work_wage {
    replace `var' = . if unemp == 1 | lf == 0
}

*-----------------------------------------------------------
* Finalize and Save 2001 Data
*-----------------------------------------------------------
gen year = `year'
// save $output/temp_sakernas_`year', replace

keep prov`year' wt urban male age educ unemp employment lf school_years sector9 sector17 ///
     work_informal work_status act_neet act_school act_household act_others work_hours ///
     work_whitecoll work_earnings work_wage work_jobdur* educ_group work_searchdur_* year

**---------------------------------------------------------------------------
** Working Hours, Underemployment, Status, and Formality Indicators (2001)
** Raw inputs: hours=b4p6b  status=b4p10  occupation=jenpek  involuntary=(b4p4, b4p24)
**---------------------------------------------------------------------------

* hour: total working hours of all jobs (week)
cap confirm variable b4p6b
if !_rc {
    cap drop hour
    gen hour = b4p6b if employment == 1
}
else {
    cap gen hour = .
}

* underemp: hour<35 & employed
cap drop underemp
gen underemp = 1 if hour < 35 & hour > 0
replace underemp = 0 if hour == 0
replace underemp = 0 if hour >= 35 & hour != .

* underemp_invol & underemp_vol (legacy formula)
cap drop underemp_invol underemp_vol
gen underemp_invol = .
cap confirm variable b4p4
local has_i1 = !_rc
cap confirm variable b4p24
local has_i2 = !_rc
if `has_i1' & `has_i2' {
    replace underemp_invol = 0 if underemp == 1
    replace underemp_invol = 1 if (b4p4 == 1 | b4p24 == 1) & underemp == 1
}
gen underemp_vol = .
replace underemp_vol = 1 if underemp == 1 & underemp_invol == 0
replace underemp_vol = 0 if underemp == 1 & underemp_invol == 1

* hour decomposed
cap drop hour_under hour_vol hour_invol
gen hour_under = hour if underemp == 1
gen hour_vol   = hour if underemp_vol == 1
gen hour_invol = hour if underemp_invol == 1

* status (employment status, 1-7)
cap drop status
cap confirm variable b4p10
if !_rc {
    gen status = b4p10 if employment == 1
    replace status = . if status == 0
}
else {
    gen status = .
}

* worktype (1-digit code; take first digit if multi-digit)
cap drop worktype
cap confirm variable jenpek
if !_rc {
    gen _wt_raw = jenpek if employment == 1
    gen worktype = .
    replace worktype = real(substr(string(int(abs(_wt_raw))), 1, 1)) if _wt_raw != . & _wt_raw > 0
    replace worktype = _wt_raw if abs(_wt_raw) < 10 & _wt_raw != .
    drop _wt_raw
}
else {
    gen worktype = .
}

* formal_simple: status in (3,4)
cap drop formal_simple
gen formal_simple = inrange(status, 3, 4) if status != . & employment == 1

* formal_new: wrktype2011 matrix
cap drop formal_new
gen formal_new = .
replace formal_new = wrktype2011[status, worktype] ///
    if status != . & worktype != . & employment == 1 ///
    & inrange(status, 1, 7) & inrange(worktype, 1, 8)

* formal_old: formal_new + casual workers in agri/construction
cap drop formal_old
gen formal_old = formal_new
replace formal_old = 1 if (status == 5 & sector9 == 1) & employment == 1
replace formal_old = 1 if (status == 6 & sector9 == 5) & employment == 1

* labels
cap label var hour           "working hours per week (all jobs combined)"
cap label var underemp       "underemployed dummy (less than 35 hours per week)"
cap label var underemp_invol "involuntary underemployment"
cap label var underemp_vol   "voluntary underemployment"
cap label var hour_under     "weekly hours among underemployed"
cap label var hour_vol       "weekly hours among voluntary underemployed"
cap label var hour_invol     "weekly hours among involuntary underemployed"
cap label var status         "main employment status"
cap label var worktype       "main occupation (1-digit KBJI)"
cap label var formal_simple  "simplified formality (employee or assisted employer)"
cap label var formal_new     "formality (wrktype2011 matrix)"
cap label var formal_old     "formality including casual workers in agriculture and construction"
**---------------------------------------------------------------------------
** Additional Employment Indicators
**---------------------------------------------------------------------------
cap drop employee casual_worker potential_exp
gen employee = work_status == 4 if work_status != .
gen casual_worker = inlist(work_status, 5, 6) if work_status != .
gen potential_exp = age - school_years if age != . & school_years != .
cap label var employee      "employee dummy"
cap label var casual_worker "casual worker dummy"
cap label var potential_exp "potential work experience"


save $clean/clean_sakernas_`year', replace

/*************************
 * End of Sakernas 2001
 ************************/

 

/*************************
 * Sakernas 2002 (numbers matched)
 ************************/
// NOTE: IRREGULAR PROV CODE

clear
set more off
local year = 2002
use "$source/sakernas_`year'", clear

*-----------------------------------------------------------
* Destring and Import Adjusted Variables
*-----------------------------------------------------------
destring *, replace

*-----------------------------------------------------------
* Generate Identifier and Basic Variables
*-----------------------------------------------------------
gen prov`year' = b1r1
    replace prov = 81 if inrange(prov, 81, 82)
    replace prov = 82 if inrange(prov, 91, 93)
    replace prov = 32 if prov == 36
    replace prov = 71 if prov == 75
gen wt    = infl
gen urban = (b1r5 == 1)
gen male  = (b3k4 == 1)
gen age   = b3k5   // WARNING: AGE OUTSIDE LF DETECTED
drop if age < 10
gen educ  = b4ar1a

*-----------------------------------------------------------
* Compute Employment and Unemployment
*-----------------------------------------------------------
gen employment = .
    replace employment = 1 if b4br2a1 == 1
    replace employment = 1 if b4br3 == 1

gen unemp = .
    replace unemp = 1 if b4br2a1 == 2 & b4br3 == 2 & b4br4 == 1
    replace unemp = 1 if b4br2a1 == 2 & b4br3 == 2 & b4br5 == 1
    replace unemp = 1 if b4br2a1 == 2 & inlist(b4er21, 1, 2) & employment == .
    replace unemp = 0 if unemp != 1
    replace employment = 0 if unemp == 1

*-----------------------------------------------------------
* Define Labor Force (LF)
*-----------------------------------------------------------
gen lf = .
    replace lf = 1 if employment == 1 | unemp == 1
    replace lf = 0 if age < 15
    replace lf = 0 if lf != 1
    replace unemp = . if lf == 0
    replace employment = . if lf == 0

*-----------------------------------------------------------
* Sector and Work Variables
*-----------------------------------------------------------
recode b4cr7 0/59 = 1 ///
       100/149 = 2 ///
       150/379 = 3 ///
       400/419 = 4 ///
       450/459 = 5 ///
       500/559 = 6 ///
       600/649 = 7 ///
       650/749 = 8 ///
       750/999 = 9, generate(sector9)
	   
recode b4cr7 	///
(011/100 =  1) (101/150 =  2) (151/400 =  3) ///
(401/403 =  4) (410 =  5)  (450/499 =  6) ///
(500/550 =  7) (601/633 635 639=  8) ///
(551 552 =  9) (641 642 = 10) (651/672 = 11) ///
(701/703 = 12) (634 711/750 = 13)  (751/753 = 14) ///
(801/809 = 15) (851/853 = 16) ///
(634 900/990 = 17) (0 = 18), gen(sector17)

gen work_informal = inlist(b4cr10a, 1, 2, 5, 6, 7)
gen work_status   = b4cr10a
gen work_whitecoll = inrange(b4cr8, 1, 599)
gen act_school    = b4br2a2 == 1 & b4br2b == 2 & lf == 0
gen act_household = b4br2a3 == 1 & b4br2b == 3 & lf == 0
gen act_others    = b4br2a4 == 1 & b4br2b == 4 & lf == 0
gen act_neet = 0
    replace act_neet = 1 if b4br2a1 == 2 & b4br2a2 == 2
    replace act_neet = 0 if act_school == 1
    replace act_neet = . if age >= 25
    replace act_neet = . if age <= 14

*-----------------------------------------------------------
* Matching Employment Statistics
*-----------------------------------------------------------
replace employment = 1 if employment == 0 & work_status != .

*-----------------------------------------------------------
* Work-related Variables
*-----------------------------------------------------------
gen work_hours    = b4cr9
gen work_earnings = b4cr12a + b4cr12b
gen work_wage     = (b4cr12a + b4cr12b) if b4cr10a == 4
gen work_jobdur   = b4er19

*-----------------------------------------------------------
* Recodes and Derived Variables
*-----------------------------------------------------------
recode educ 0 = 3 1/3 = 1 4/7 = 2 8/9 = 3, generate(educ_group)
recode work_jobdur 0/3 = 1 4/12 = 2 12/24 = 3 25/99 = 4, gen(work_jobdur_cat)

gen school_years = .
    replace school_years = 0 if educ == 1
    replace school_years = 0 if educ == 2
    replace school_years = 6 if educ == 3
    replace school_years = 9 if educ == 4
    replace school_years = 9 if educ == 5
    replace school_years = 12 if educ == 6
    replace school_years = 12 if educ == 7
    replace school_years = 14 if educ == 8
    replace school_years = 15 if educ == 9
    replace school_years = 16 if educ == 0

la de searchdur 1 "1. <=3 bulan" 2 "2. 4-12 bulan" 3 "3. 13-24 bulan" 4 "4. >24 bulan"
la val work_jobdur_cat searchdur

forval x = 1/4 {
    gen work_searchdur_`x' = (work_jobdur_cat == `x')
    replace work_searchdur_`x' = . if lf == 0 | work_jobdur_cat == .
}

foreach var of varlist work_hours work_earnings work_wage {
    replace `var' = . if unemp == 1 | lf == 0
}

gen year = `year'

*-----------------------------------------------------------
* Save 2002 Data
*-----------------------------------------------------------
local year = 2002
// save $output/temp_sakernas_`year', replace

keep prov`year' wt urban male age educ unemp employment lf school_years sector9 sector17 work_informal work_status ///
     act_neet act_school act_household act_others work_hours work_whitecoll work_earnings work_wage work_jobdur* ///
     educ_group work_searchdur_* year

**---------------------------------------------------------------------------
** Working Hours, Underemployment, Status, and Formality Indicators (2002)
** Raw inputs: hours=b4br6b  status=b4cr10a  occupation=jenpek  involuntary=(b4br4, b4fr24)
**---------------------------------------------------------------------------

* hour: total working hours of all jobs (week)
cap confirm variable b4br6b
if !_rc {
    cap drop hour
    gen hour = b4br6b if employment == 1
}
else {
    cap gen hour = .
}

* underemp: hour<35 & employed
cap drop underemp
gen underemp = 1 if hour < 35 & hour > 0
replace underemp = 0 if hour == 0
replace underemp = 0 if hour >= 35 & hour != .

* underemp_invol & underemp_vol (legacy formula)
cap drop underemp_invol underemp_vol
gen underemp_invol = .
cap confirm variable b4br4
local has_i1 = !_rc
cap confirm variable b4fr24
local has_i2 = !_rc
if `has_i1' & `has_i2' {
    replace underemp_invol = 0 if underemp == 1
    replace underemp_invol = 1 if (b4br4 == 1 | b4fr24 == 1) & underemp == 1
}
gen underemp_vol = .
replace underemp_vol = 1 if underemp == 1 & underemp_invol == 0
replace underemp_vol = 0 if underemp == 1 & underemp_invol == 1

* hour decomposed
cap drop hour_under hour_vol hour_invol
gen hour_under = hour if underemp == 1
gen hour_vol   = hour if underemp_vol == 1
gen hour_invol = hour if underemp_invol == 1

* status (employment status, 1-7)
cap drop status
cap confirm variable b4cr10a
if !_rc {
    gen status = b4cr10a if employment == 1
    replace status = . if status == 0
}
else {
    gen status = .
}

* worktype (1-digit code; take first digit if multi-digit)
cap drop worktype
cap confirm variable jenpek
if !_rc {
    gen _wt_raw = jenpek if employment == 1
    gen worktype = .
    replace worktype = real(substr(string(int(abs(_wt_raw))), 1, 1)) if _wt_raw != . & _wt_raw > 0
    replace worktype = _wt_raw if abs(_wt_raw) < 10 & _wt_raw != .
    drop _wt_raw
}
else {
    gen worktype = .
}

* formal_simple: status in (3,4)
cap drop formal_simple
gen formal_simple = inrange(status, 3, 4) if status != . & employment == 1

* formal_new: wrktype2011 matrix
cap drop formal_new
gen formal_new = .
replace formal_new = wrktype2011[status, worktype] ///
    if status != . & worktype != . & employment == 1 ///
    & inrange(status, 1, 7) & inrange(worktype, 1, 8)

* formal_old: formal_new + casual workers in agri/construction
cap drop formal_old
gen formal_old = formal_new
replace formal_old = 1 if (status == 5 & sector9 == 1) & employment == 1
replace formal_old = 1 if (status == 6 & sector9 == 5) & employment == 1

* labels
cap label var hour           "working hours per week (all jobs combined)"
cap label var underemp       "underemployed dummy (less than 35 hours per week)"
cap label var underemp_invol "involuntary underemployment"
cap label var underemp_vol   "voluntary underemployment"
cap label var hour_under     "weekly hours among underemployed"
cap label var hour_vol       "weekly hours among voluntary underemployed"
cap label var hour_invol     "weekly hours among involuntary underemployed"
cap label var status         "main employment status"
cap label var worktype       "main occupation (1-digit KBJI)"
cap label var formal_simple  "simplified formality (employee or assisted employer)"
cap label var formal_new     "formality (wrktype2011 matrix)"
cap label var formal_old     "formality including casual workers in agriculture and construction"
**---------------------------------------------------------------------------
** Additional Employment Indicators
**---------------------------------------------------------------------------
cap drop employee casual_worker potential_exp
gen employee = work_status == 4 if work_status != .
gen casual_worker = inlist(work_status, 5, 6) if work_status != .
gen potential_exp = age - school_years if age != . & school_years != .
cap label var employee      "employee dummy"
cap label var casual_worker "casual worker dummy"
cap label var potential_exp "potential work experience"


save $clean/clean_sakernas_`year', replace

/*************************
 * End of Sakernas 2002
 ************************/


/*************************
 * Sakernas 2003 (numbers matched)
 ************************/

clear
set more off
local year = 2003
use $source/sakernas_`year', clear

*-----------------------------------------------------------
* Generate Identifier and Basic Variables
*-----------------------------------------------------------
gen prov`year' = b1p01
gen wt         = weight
gen urban      = (b1p05 == 1)
gen male       = (jk == 1)
gen age        = umur    // WARNING: AGE OUTSIDE LF DETECTED
gen educ       = b4p1a

*-----------------------------------------------------------
* Compute Employment and Unemployment Status
*-----------------------------------------------------------
gen employment = .
    replace employment = 1 if b4p2a1 == 1
    replace employment = 1 if b4p3 == 1

gen unemp = .
    replace unemp = 1 if b4p2a1 == 2 & b4p3 == 2 & b4p4 == 1
    replace unemp = 1 if b4p2a1 == 2 & b4p3 == 2 & b4p5 == 1
    replace unemp = 1 if b4p2a1 == 2 & inlist(b4p21, 1, 2) & employment == .
    replace unemp = 0 if unemp != 1
    replace employment = 0 if unemp == 1

*-----------------------------------------------------------
* Define Labor Force (LF)
*-----------------------------------------------------------
gen lf = .
    replace lf = 1 if employment == 1 | unemp == 1
    replace lf = 0 if age < 15
    replace lf = 0 if lf != 1
    replace unemp = . if lf == 0
    replace employment = . if lf == 0

*-----------------------------------------------------------
* Sector Classification and Work Variables
*-----------------------------------------------------------
recode b4p7 0/59 = 1 ///
       100/149 = 2 ///
       150/379 = 3 ///
       400/419 = 4 ///
       450/459 = 5 ///
       500/559 = 6 ///
       600/649 = 7 ///
       650/749 = 8 ///
       750/999 = 9, generate(sector9)
	   
recode b4p7 	///
(011/100 =  1) (101/150 =  2) (151/400 =  3) ///
(401/403 =  4) (410 =  5)  (450/499 =  6) ///
(500/550 =  7) (601/633 635 639=  8) ///
(551 552 =  9) (641 642 = 10) (651/672 = 11) ///
(701/703 = 12) (634 711/750 = 13)  (751/753 = 14) ///
(801/809 = 15) (851/853 = 16) ///
(634 900/990 = 17) (0 = 18), gen(sector17)

gen work_informal = inlist(b4p10, 1, 2, 5, 6, 7)
gen work_status   = b4p10
// gen work_certif = .  // (Not defined)
gen work_whitecoll = inrange(b4p8, 1, 599)

gen act_school = b4p2a2 == 1 & b4p2b == 2 & lf == 0
gen act_household = b4p2a3 == 1 & b4p2b == 3 & lf == 0
gen act_others    = b4p2a4 == 1 & b4p2b == 4 & lf == 0
gen act_neet = 0
    replace act_neet = 1 if b4p2a1 == 2 & b4p2a2 == 2
    replace act_neet = 0 if act_school == 1
    replace act_neet = . if age >= 25
    replace act_neet = . if age <= 14

*-----------------------------------------------------------
* Create Work-related Variables
*-----------------------------------------------------------
gen work_hours    = b4p9
gen work_earnings = b4p12a + b4p12b
gen work_wage     = (b4p12a + b4p12b) if b4p10 == 4
gen work_jobdur   = b4p19

*-----------------------------------------------------------
* Recodes and Derived Variables
*-----------------------------------------------------------
recode educ 1/3 = 1 4/7 = 2 8/10 = 3, generate(educ_group)
recode work_jobdur 0/3 = 1 4/12 = 2 12/24 = 3 25/99 = 4, gen(work_jobdur_cat)

gen school_years = .
    replace school_years = 0 if educ == 1
    replace school_years = 0 if educ == 2
    replace school_years = 6 if educ == 3
    replace school_years = 9 if educ == 4
    replace school_years = 9 if educ == 5
    replace school_years = 12 if educ == 6
    replace school_years = 12 if educ == 7
    replace school_years = 14 if educ == 8
    replace school_years = 15 if educ == 9
    replace school_years = 16 if educ == 0

la de searchdur 1 "1. <=3 bulan" 2 "2. 4-12 bulan" 3 "3. 13-24 bulan" 4 "4. >24 bulan"
la val work_jobdur_cat searchdur

forval x = 1/4 {
    gen work_searchdur_`x' = (work_jobdur_cat == `x')
    replace work_searchdur_`x' = . if lf == 0 | work_jobdur_cat == .
}

foreach var of varlist work_hours work_earnings work_wage {
    replace `var' = . if unemp == 1 | lf == 0
}

gen year = `year'

*-----------------------------------------------------------
* Save 2003 Data
*-----------------------------------------------------------
local year = 2003
// save $output/temp_sakernas_`year', replace

keep prov`year' wt urban male age educ unemp employment lf school_years sector9 sector17 work_informal work_status act_neet act_school act_household act_others work_hours work_whitecoll work_earnings work_wage work_jobdur* educ_group work_searchdur_* year


**---------------------------------------------------------------------------
** Working Hours, Underemployment, Status, and Formality Indicators (2003)
** Raw inputs: hours=b4p6b  status=b4p10  occupation=jenpek  involuntary=(b4p4, b4p24)
**---------------------------------------------------------------------------

* hour: total working hours of all jobs (week)
cap confirm variable b4p6b
if !_rc {
    cap drop hour
    gen hour = b4p6b if employment == 1
}
else {
    cap gen hour = .
}

* underemp: hour<35 & employed
cap drop underemp
gen underemp = 1 if hour < 35 & hour > 0
replace underemp = 0 if hour == 0
replace underemp = 0 if hour >= 35 & hour != .

* underemp_invol & underemp_vol (legacy formula)
cap drop underemp_invol underemp_vol
gen underemp_invol = .
cap confirm variable b4p4
local has_i1 = !_rc
cap confirm variable b4p24
local has_i2 = !_rc
if `has_i1' & `has_i2' {
    replace underemp_invol = 0 if underemp == 1
    replace underemp_invol = 1 if (b4p4 == 1 | b4p24 == 1) & underemp == 1
}
gen underemp_vol = .
replace underemp_vol = 1 if underemp == 1 & underemp_invol == 0
replace underemp_vol = 0 if underemp == 1 & underemp_invol == 1

* hour decomposed
cap drop hour_under hour_vol hour_invol
gen hour_under = hour if underemp == 1
gen hour_vol   = hour if underemp_vol == 1
gen hour_invol = hour if underemp_invol == 1

* status (employment status, 1-7)
cap drop status
cap confirm variable b4p10
if !_rc {
    gen status = b4p10 if employment == 1
    replace status = . if status == 0
}
else {
    gen status = .
}

* worktype (1-digit code; take first digit if multi-digit)
cap drop worktype
cap confirm variable jenpek
if !_rc {
    gen _wt_raw = jenpek if employment == 1
    gen worktype = .
    replace worktype = real(substr(string(int(abs(_wt_raw))), 1, 1)) if _wt_raw != . & _wt_raw > 0
    replace worktype = _wt_raw if abs(_wt_raw) < 10 & _wt_raw != .
    drop _wt_raw
}
else {
    gen worktype = .
}

* formal_simple: status in (3,4)
cap drop formal_simple
gen formal_simple = inrange(status, 3, 4) if status != . & employment == 1

* formal_new: wrktype2011 matrix
cap drop formal_new
gen formal_new = .
replace formal_new = wrktype2011[status, worktype] ///
    if status != . & worktype != . & employment == 1 ///
    & inrange(status, 1, 7) & inrange(worktype, 1, 8)

* formal_old: formal_new + casual workers in agri/construction
cap drop formal_old
gen formal_old = formal_new
replace formal_old = 1 if (status == 5 & sector9 == 1) & employment == 1
replace formal_old = 1 if (status == 6 & sector9 == 5) & employment == 1

* labels
cap label var hour           "working hours per week (all jobs combined)"
cap label var underemp       "underemployed dummy (less than 35 hours per week)"
cap label var underemp_invol "involuntary underemployment"
cap label var underemp_vol   "voluntary underemployment"
cap label var hour_under     "weekly hours among underemployed"
cap label var hour_vol       "weekly hours among voluntary underemployed"
cap label var hour_invol     "weekly hours among involuntary underemployed"
cap label var status         "main employment status"
cap label var worktype       "main occupation (1-digit KBJI)"
cap label var formal_simple  "simplified formality (employee or assisted employer)"
cap label var formal_new     "formality (wrktype2011 matrix)"
cap label var formal_old     "formality including casual workers in agriculture and construction"
**---------------------------------------------------------------------------
** Additional Employment Indicators
**---------------------------------------------------------------------------
cap drop employee casual_worker potential_exp
gen employee = work_status == 4 if work_status != .
gen casual_worker = inlist(work_status, 5, 6) if work_status != .
gen potential_exp = age - school_years if age != . & school_years != .
cap label var employee      "employee dummy"
cap label var casual_worker "casual worker dummy"
cap label var potential_exp "potential work experience"


save $clean/clean_sakernas_`year', replace

/*************************
 * End of Sakernas 2003
 ************************/

/*************************
 * Sakernas 2004 (others activity still not matched)
 ************************/

clear
set more off
local year = 2004
use $source/sakernas_`year', clear

*-----------------------------------------------------------
* Generate Identifier and Basic Variables
*-----------------------------------------------------------
gen prov`year' = b1p01
gen wt         = weight
gen urban      = (b1p05 == 1)
gen male       = (jk == 1)
gen age        = umur        // WARNING: AGE OUTSIDE LF DETECTED
gen educ       = b4p1a

*-----------------------------------------------------------
* Compute Employment and Unemployment Status
*-----------------------------------------------------------
gen employment = .
replace employment = 1 if b4p2a1 == 1
replace employment = 1 if b4p3 == 1

gen unemp = .
replace unemp = 1 if b4p2a1 == 2 & b4p3 == 2 & b4p4 == 1
replace unemp = 1 if b4p2a1 == 2 & b4p3 == 2 & b4p5 == 1
replace unemp = 1 if b4p2a1 == 2 & inlist(b4p21, 1, 2) & employment == .
replace unemp = 0 if unemp != 1
replace employment = 0 if unemp == 1

*-----------------------------------------------------------
* Define Labor Force (LF)
*-----------------------------------------------------------
gen lf = .
replace lf = 1 if employment == 1 | unemp == 1
replace lf = 0 if age < 15
replace lf = 0 if lf != 1
replace unemp = . if lf == 0
replace employment = . if lf == 0

*-----------------------------------------------------------
* Sector Classification and Work-Related Variables
*-----------------------------------------------------------
recode b4p7 0/59 = 1 ///
       100/149 = 2 ///
       150/379 = 3 ///
       400/419 = 4 ///
       450/459 = 5 ///
       500/559 = 6 ///
       600/649 = 7 ///
       650/749 = 8 ///
       750/999 = 9, generate(sector9)
	   
recode b4p7 	///
(011/100 =  1) (101/150 =  2) (151/400 =  3) ///
(401/403 =  4) (410 =  5)  (450/499 =  6) ///
(500/550 =  7) (601/633 635 639=  8) ///
(551 552 =  9) (641 642 = 10) (651/672 = 11) ///
(701/703 = 12) (634 711/750 = 13)  (751/753 = 14) ///
(801/809 = 15) (851/853 = 16) ///
(634 900/990 = 17) (0 = 18), gen(sector17)


gen work_informal  = inlist(b4p10, 1, 2, 5, 6, 7)
gen work_status    = b4p10
// gen work_certif = .   // (Not defined)
gen work_whitecoll = inrange(b4p8, 1, 599)

gen act_school     = (b4p2a2 == 1 | b4p2a2 == 2) & b4p2b == 2 & lf == 0
gen act_household  = (b4p2a3 == 1 | b4p2a3 == 2) & b4p2b == 3 & lf == 0
gen act_others     = (b4p2a4 == 1 | b4p2a4 == 2) & b4p2b == 4 & lf == 0

gen act_neet = 0
replace act_neet = 1 if b4p2a1 == 2 & b4p2a2 == 2
replace act_neet = 0 if act_school == 1
replace act_neet = . if age >= 25 | age <= 14

*-----------------------------------------------------------
* Adjust Employment for Consistency
*-----------------------------------------------------------
replace employment = 1 if employment == 0 & work_status != .

*-----------------------------------------------------------
* Create Work Outcome Variables
*-----------------------------------------------------------
gen work_hours   = b4p9
gen work_earnings = b4p12a + b4p12b
gen work_wage    = (b4p12a + b4p12b) if b4p10 == 4
gen work_jobdur  = b4p19

*-----------------------------------------------------------
* Recodes and Derived Variables
*-----------------------------------------------------------
recode educ 0 = 3 1/3 = 1 4/7 = 2 8/9 = 3, generate(educ_group)
recode work_jobdur 0/3 = 1 4/12 = 2 12/24 = 3 25/99 = 4, gen(work_jobdur_cat)

gen school_years = .
replace school_years = 0 if educ == 1 | educ == 2
replace school_years = 6 if educ == 3
replace school_years = 9 if educ == 4 | educ == 5
replace school_years = 12 if educ == 6 | educ == 7
replace school_years = 14 if educ == 8
replace school_years = 15 if educ == 9
replace school_years = 16 if educ == 0

*-----------------------------------------------------------
* Job Search Duration Dummies
*-----------------------------------------------------------
la de searchdur 1 "1. <=3 bulan" 2 "2. 4-12 bulan" 3 "3. 13-24 bulan" 4 "4. >24 bulan"
la val work_jobdur_cat searchdur

forval x = 1/4 {
    gen work_searchdur_`x' = (work_jobdur_cat == `x')
    replace work_searchdur_`x' = . if lf == 0 | work_jobdur_cat == .
}

foreach var of varlist work_hours work_earnings work_wage {
    replace `var' = . if unemp == 1 | lf == 0
}

*-----------------------------------------------------------
* Finalize and Save 2004 Data
*-----------------------------------------------------------
gen year = `year'
// save $output/temp_sakernas_`year', replace

// keep only key variables before saving clean data

**---------------------------------------------------------------------------
** Working Hours, Underemployment, Status, and Formality Indicators (2004)
** Raw inputs: hours=b4p6b  status=b4p10  occupation=jenpek  involuntary=(b4p4, b4p24)
**---------------------------------------------------------------------------

* hour: total working hours of all jobs (week)
cap confirm variable b4p6b
if !_rc {
    cap drop hour
    gen hour = b4p6b if employment == 1
}
else {
    cap gen hour = .
}

* underemp: hour<35 & employed
cap drop underemp
gen underemp = 1 if hour < 35 & hour > 0
replace underemp = 0 if hour == 0
replace underemp = 0 if hour >= 35 & hour != .

* underemp_invol & underemp_vol (legacy formula)
cap drop underemp_invol underemp_vol
gen underemp_invol = .
cap confirm variable b4p4
local has_i1 = !_rc
cap confirm variable b4p24
local has_i2 = !_rc
if `has_i1' & `has_i2' {
    replace underemp_invol = 0 if underemp == 1
    replace underemp_invol = 1 if (b4p4 == 1 | b4p24 == 1) & underemp == 1
}
gen underemp_vol = .
replace underemp_vol = 1 if underemp == 1 & underemp_invol == 0
replace underemp_vol = 0 if underemp == 1 & underemp_invol == 1

* hour decomposed
cap drop hour_under hour_vol hour_invol
gen hour_under = hour if underemp == 1
gen hour_vol   = hour if underemp_vol == 1
gen hour_invol = hour if underemp_invol == 1

* status (employment status, 1-7)
cap drop status
cap confirm variable b4p10
if !_rc {
    gen status = b4p10 if employment == 1
    replace status = . if status == 0
}
else {
    gen status = .
}

* worktype (1-digit code; take first digit if multi-digit)
cap drop worktype
cap confirm variable jenpek
if !_rc {
    gen _wt_raw = jenpek if employment == 1
    gen worktype = .
    replace worktype = real(substr(string(int(abs(_wt_raw))), 1, 1)) if _wt_raw != . & _wt_raw > 0
    replace worktype = _wt_raw if abs(_wt_raw) < 10 & _wt_raw != .
    drop _wt_raw
}
else {
    gen worktype = .
}

* formal_simple: status in (3,4)
cap drop formal_simple
gen formal_simple = inrange(status, 3, 4) if status != . & employment == 1

* formal_new: wrktype2011 matrix
cap drop formal_new
gen formal_new = .
replace formal_new = wrktype2011[status, worktype] ///
    if status != . & worktype != . & employment == 1 ///
    & inrange(status, 1, 7) & inrange(worktype, 1, 8)

* formal_old: formal_new + casual workers in agri/construction
cap drop formal_old
gen formal_old = formal_new
replace formal_old = 1 if (status == 5 & sector9 == 1) & employment == 1
replace formal_old = 1 if (status == 6 & sector9 == 5) & employment == 1

* labels
cap label var hour           "working hours per week (all jobs combined)"
cap label var underemp       "underemployed dummy (less than 35 hours per week)"
cap label var underemp_invol "involuntary underemployment"
cap label var underemp_vol   "voluntary underemployment"
cap label var hour_under     "weekly hours among underemployed"
cap label var hour_vol       "weekly hours among voluntary underemployed"
cap label var hour_invol     "weekly hours among involuntary underemployed"
cap label var status         "main employment status"
cap label var worktype       "main occupation (1-digit KBJI)"
cap label var formal_simple  "simplified formality (employee or assisted employer)"
cap label var formal_new     "formality (wrktype2011 matrix)"
cap label var formal_old     "formality including casual workers in agriculture and construction"
**---------------------------------------------------------------------------
** Additional Employment Indicators
**---------------------------------------------------------------------------
cap drop employee casual_worker potential_exp
gen employee = work_status == 4 if work_status != .
gen casual_worker = inlist(work_status, 5, 6) if work_status != .
gen potential_exp = age - school_years if age != . & school_years != .
cap label var employee      "employee dummy"
cap label var casual_worker "casual worker dummy"
cap label var potential_exp "potential work experience"


keep prov`year' wt urban male age educ unemp employment lf school_years sector9 sector17 work_informal work_status act_neet act_school act_others act_household work_hours work_whitecoll work_earnings work_wage work_jobdur* educ_group work_searchdur_* year
save $clean/clean_sakernas_`year', replace

/*************************
 * End of Sakernas 2004
 ************************/



/*************************
 * Sakernas 2005
 ************************/

clear
set more off
local year = 2005
use "$source/sakernas_`year'", clear

*-----------------------------------------------------------
* Generate Identifier and Basic Variables
*-----------------------------------------------------------
gen prov`year' = prop
gen wt         = timbang
gen urban      = (daerah == 1)
gen male       = (jk == 1)
gen age        = umur        // WARNING: AGE OUTSIDE LF DETECTED
gen educ       = b4p1a

*-----------------------------------------------------------
* Compute Employment and Unemployment Status
*-----------------------------------------------------------
gen unemp = .
replace unemp = 1 if b4p2a1 == 2 & b4p3 == 2 & b4p4 == 1
replace unemp = 1 if b4p2a1 == 2 & b4p3 == 2 & b4p5 == 1
replace unemp = 1 if b4p2a1 == 2 & inlist(b4p21, 1, 2)
replace unemp = 0 if unemp != 1

gen employment = .
replace employment = 1 if b4p2a1 == 1
replace employment = 1 if b4p3 == 1
replace employment = 0 if unemp == 1

*-----------------------------------------------------------
* Define Labor Force (LF)
*-----------------------------------------------------------
gen lf = .
replace lf = 1 if employment == 1 | unemp == 1
replace lf = 0 if age < 15
replace lf = 0 if lf != 1
replace unemp = . if lf == 0
replace employment = . if lf == 0

*-----------------------------------------------------------
* Sector Classification and Work Variables
*-----------------------------------------------------------
recode b4p7 0/59 = 1 ///
       100/149 = 2 ///
       150/379 = 3 ///
       400/419 = 4 ///
       450/459 = 5 ///
       500/559 = 6 ///
       600/649 = 7 ///
       650/749 = 8 ///
       750/999 = 9, generate(sector9)

recode b4p7 	///
(011/100 =  1) (101/150 =  2) (151/400 =  3) ///
(401/403 =  4) (410 =  5)  (450/499 =  6) ///
(500/550 =  7) (601/633 635 639=  8) ///
(551 552 =  9) (641 642 = 10) (651/672 = 11) ///
(701/703 = 12) (634 711/750 = 13)  (751/753 = 14) ///
(801/809 = 15) (851/853 = 16) ///
(634 900/990 = 17) (0 = 18), gen(sector17)

gen work_informal = inlist(b4p10, 1, 2, 5, 6, 7)
gen work_status   = b4p10
// gen work_certif = .  // (Not defined)
gen work_whitecoll = inrange(b4p8, 1, 599)

gen act_school    = (b4p2a2 == 1 & b4p2b == 2 & lf == 0)
gen act_household = (b4p2a3 == 1 & b4p2b == 3 & lf == 0)
gen act_others    = (b4p2a4 == 1 & b4p2b == 4 & lf == 0)

gen act_neet = 0
replace act_neet = 1 if b4p2a1 == 2 & b4p2a2 == 2
replace act_neet = 0 if act_school == 1
replace act_neet = . if age >= 25 | age <= 14

*-----------------------------------------------------------
* Adjust Employment for Consistency
*-----------------------------------------------------------
replace employment = 1 if employment == 0 & work_status != .

*-----------------------------------------------------------
* Create Work-related Outcome Variables
*-----------------------------------------------------------
gen work_hours    = b4p9
gen work_earnings = b4p12a + b4p12b
gen work_wage     = (b4p12a + b4p12b) if b4p10 == 4
gen work_jobdur   = b4p19

*-----------------------------------------------------------
* Recodes and Derived Variables
*-----------------------------------------------------------
recode educ 0/2 = 1 3/6 = 2 7/9 = 3, generate(educ_group)
recode work_jobdur 0/3 = 1 4/12 = 2 12/24 = 3 25/99 = 4, gen(work_jobdur_cat)

gen school_years = .
replace school_years = 0 if educ == 0
replace school_years = 0 if educ == 1
replace school_years = 6 if educ == 2
replace school_years = 9 if educ == 3
replace school_years = 9 if educ == 4
replace school_years = 12 if educ == 5
replace school_years = 12 if educ == 6
replace school_years = 14 if educ == 7
replace school_years = 15 if educ == 8
replace school_years = 16 if educ == 9

*-----------------------------------------------------------
* Job Search Duration Dummies
*-----------------------------------------------------------
la de searchdur 1 "1. <=3 bulan" 2 "2. 4-12 bulan" 3 "3. 13-24 bulan" 4 "4. >24 bulan"
la val work_jobdur_cat searchdur

forval x = 1/4 {
    gen work_searchdur_`x' = (work_jobdur_cat == `x')
    replace work_searchdur_`x' = . if lf == 0 | work_jobdur_cat == .
}

foreach var of varlist work_hours work_earnings work_wage {
    replace `var' = . if unemp == 1 | lf == 0
}

gen year = `year'

*-----------------------------------------------------------
* Save 2005 Data
*-----------------------------------------------------------
save $output/temp_sakernas_`year', replace

// keep only key variables before saving clean data


**---------------------------------------------------------------------------
** Working Hours, Underemployment, Status, and Formality Indicators (2005)
** Raw inputs: hours=b4p6b  status=b4p10  occupation=jenpek  involuntary=(b4p4, b4p24)
**---------------------------------------------------------------------------

* hour: total working hours of all jobs (week)
cap confirm variable b4p6b
if !_rc {
    cap drop hour
    gen hour = b4p6b if employment == 1
}
else {
    cap gen hour = .
}

* underemp: hour<35 & employed
cap drop underemp
gen underemp = 1 if hour < 35 & hour > 0
replace underemp = 0 if hour == 0
replace underemp = 0 if hour >= 35 & hour != .

* underemp_invol & underemp_vol (legacy formula)
cap drop underemp_invol underemp_vol
gen underemp_invol = .
cap confirm variable b4p4
local has_i1 = !_rc
cap confirm variable b4p24
local has_i2 = !_rc
if `has_i1' & `has_i2' {
    replace underemp_invol = 0 if underemp == 1
    replace underemp_invol = 1 if (b4p4 == 1 | b4p24 == 1) & underemp == 1
}
gen underemp_vol = .
replace underemp_vol = 1 if underemp == 1 & underemp_invol == 0
replace underemp_vol = 0 if underemp == 1 & underemp_invol == 1

* hour decomposed
cap drop hour_under hour_vol hour_invol
gen hour_under = hour if underemp == 1
gen hour_vol   = hour if underemp_vol == 1
gen hour_invol = hour if underemp_invol == 1

* status (employment status, 1-7)
cap drop status
cap confirm variable b4p10
if !_rc {
    gen status = b4p10 if employment == 1
    replace status = . if status == 0
}
else {
    gen status = .
}

* worktype (1-digit code; take first digit if multi-digit)
cap drop worktype
cap confirm variable jenpek
if !_rc {
    gen _wt_raw = jenpek if employment == 1
    gen worktype = .
    replace worktype = real(substr(string(int(abs(_wt_raw))), 1, 1)) if _wt_raw != . & _wt_raw > 0
    replace worktype = _wt_raw if abs(_wt_raw) < 10 & _wt_raw != .
    drop _wt_raw
}
else {
    gen worktype = .
}

* formal_simple: status in (3,4)
cap drop formal_simple
gen formal_simple = inrange(status, 3, 4) if status != . & employment == 1

* formal_new: wrktype2011 matrix
cap drop formal_new
gen formal_new = .
replace formal_new = wrktype2011[status, worktype] ///
    if status != . & worktype != . & employment == 1 ///
    & inrange(status, 1, 7) & inrange(worktype, 1, 8)

* formal_old: formal_new + casual workers in agri/construction
cap drop formal_old
gen formal_old = formal_new
replace formal_old = 1 if (status == 5 & sector9 == 1) & employment == 1
replace formal_old = 1 if (status == 6 & sector9 == 5) & employment == 1

* labels
cap label var hour           "working hours per week (all jobs combined)"
cap label var underemp       "underemployed dummy (less than 35 hours per week)"
cap label var underemp_invol "involuntary underemployment"
cap label var underemp_vol   "voluntary underemployment"
cap label var hour_under     "weekly hours among underemployed"
cap label var hour_vol       "weekly hours among voluntary underemployed"
cap label var hour_invol     "weekly hours among involuntary underemployed"
cap label var status         "main employment status"
cap label var worktype       "main occupation (1-digit KBJI)"
cap label var formal_simple  "simplified formality (employee or assisted employer)"
cap label var formal_new     "formality (wrktype2011 matrix)"
cap label var formal_old     "formality including casual workers in agriculture and construction"
**---------------------------------------------------------------------------
** Additional Employment Indicators
**---------------------------------------------------------------------------
cap drop employee casual_worker potential_exp
gen employee = work_status == 4 if work_status != .
gen casual_worker = inlist(work_status, 5, 6) if work_status != .
gen potential_exp = age - school_years if age != . & school_years != .
cap label var employee      "employee dummy"
cap label var casual_worker "casual worker dummy"
cap label var potential_exp "potential work experience"


 keep prov`year' wt urban male age educ unemp employment lf school_years sector9 sector17 work_informal work_status act_neet act_school act_household act_others work_hours work_whitecoll work_earnings work_wage work_jobdur* educ_group work_searchdur_* year
save $clean/clean_sakernas_`year', replace

/*************************
 * End of Sakernas 2005
 ************************/

/*************************
 * Sakernas 2006
 ************************/

clear
set more off
local year = 2006
use $source/sakernas_`year', clear

*-----------------------------------------------------------
* Generate Identifier and Basic Variables
*-----------------------------------------------------------
gen prov`year' = prop
gen wt         = weight
gen urban      = (b1p05 == 1)
gen male       = (jk == 1)
gen age        = umur        // WARNING: AGE OUTSIDE LF DETECTED
gen educ       = b4p1a

*-----------------------------------------------------------
* Compute Employment and Unemployment Status
*-----------------------------------------------------------
gen unemp = .
replace unemp = 1 if b4p2a1 == 2 & b4p3 == 2 & b4p4 == 1
replace unemp = 1 if b4p2a1 == 2 & b4p3 == 2 & b4p5 == 1
replace unemp = 1 if b4p2a1 == 2 & inlist(b4p21, 1, 2)
replace unemp = 0 if unemp != 1

gen employment = .
replace employment = 1 if b4p2a1 == 1
replace employment = 1 if b4p3 == 1
replace employment = 0 if unemp == 1

*-----------------------------------------------------------
* Define Labor Force (LF)
*-----------------------------------------------------------
gen lf = .
replace lf = 1 if employment == 1 | unemp == 1
replace lf = 0 if age < 15
replace lf = 0 if lf != 1
replace unemp = . if lf == 0
replace employment = . if lf == 0

*-----------------------------------------------------------
* Sector and Work Variables
*-----------------------------------------------------------
recode b4p7 0/59 = 1 ///
       100/149 = 2 ///
       150/379 = 3 ///
       400/419 = 4 ///
       450/459 = 5 ///
       500/559 = 6 ///
       600/649 = 7 ///
       650/749 = 8 ///
       750/999 = 9, generate(sector9)

recode b4p7 	///
(011/100 =  1) (101/150 =  2) (151/400 =  3) ///
(401/403 =  4) (410 =  5)  (450/499 =  6) ///
(500/550 =  7) (601/633 635 639=  8) ///
(551 552 =  9) (641 642 = 10) (651/672 = 11) ///
(701/703 = 12) (634 711/750 = 13)  (751/753 = 14) ///
(801/809 = 15) (851/853 = 16) ///
(634 900/990 = 17) (0 = 18), gen(sector17)


gen work_informal  = inlist(b4p10, 1, 2, 5, 6, 7)
gen work_status    = b4p10
// gen work_certif  = .   // (Not defined)
gen work_whitecoll = inrange(b4p8, 1, 599)

gen act_school     = (b4p2a2 == 1 & b4p2b == 2 & lf == 0)
gen act_household  = (b4p2a3 == 1 & b4p2b == 3 & lf == 0)
gen act_others     = (b4p2a4 == 1 & b4p2b == 4 & lf == 0)

// adjusting the household activity numbers --> still 1404 obs left out
gen household = 0 if (act_school == 1 | act_household == 1 | act_others == 1)
replace household = 1 if household == .
replace act_household= 1 if lf == 0 & household == 1
// done matched

gen act_neet = 0
replace act_neet = 1 if b4p2a1 == 2 & b4p2a2 == 2
replace act_neet = 0 if act_school == 1
replace act_neet = . if age >= 25 | age <= 14

*-----------------------------------------------------------
* Matching Employment Statistics
*-----------------------------------------------------------
replace employment = 1 if employment == 0 & work_status != .

*-----------------------------------------------------------
* Create Work Outcome Variables
*-----------------------------------------------------------
gen work_hours    = b4p9
gen work_earnings = b4p12a + b4p12b
gen work_wage     = (b4p12a + b4p12b) if b4p10 == 4
gen work_jobdur   = b4p19

*-----------------------------------------------------------
* Recodes and Derived Variables
*-----------------------------------------------------------
recode educ 0/2 = 1 3/6 = 2 7/9 = 3, generate(educ_group)
recode work_jobdur 0/3 = 1 4/12 = 2 12/24 = 3 25/99 = 4, gen(work_jobdur_cat)

gen school_years = .
replace school_years = 0 if educ == 0
replace school_years = 0 if educ == 1
replace school_years = 6 if educ == 2
replace school_years = 9 if educ == 3
replace school_years = 9 if educ == 4
replace school_years = 12 if educ == 5
replace school_years = 12 if educ == 6
replace school_years = 14 if educ == 7
replace school_years = 15 if educ == 8
replace school_years = 16 if educ == 9

*-----------------------------------------------------------
* Job Search Duration Dummies
*-----------------------------------------------------------
la de searchdur 1 "1. <=3 bulan" 2 "2. 4-12 bulan" 3 "3. 13-24 bulan" 4 "4. >24 bulan"
la val work_jobdur_cat searchdur

forval x = 1/4 {
    gen work_searchdur_`x' = (work_jobdur_cat == `x')
    replace work_searchdur_`x' = . if lf == 0 | work_jobdur_cat == .
}

foreach var of varlist work_hours work_earnings work_wage {
    replace `var' = . if unemp == 1 | lf == 0
}

*-----------------------------------------------------------
* Finalize and Save 2006 Data
*-----------------------------------------------------------
gen year = `year'
// save $output/temp_sakernas_`year', replace

// keep only key variables before saving clean data


**---------------------------------------------------------------------------
** Working Hours, Underemployment, Status, and Formality Indicators (2006)
** Raw inputs: hours=b4p6b  status=b4p10  occupation=jenpek  involuntary=(b4p4, b4p24)
**---------------------------------------------------------------------------

* hour: total working hours of all jobs (week)
cap confirm variable b4p6b
if !_rc {
    cap drop hour
    gen hour = b4p6b if employment == 1
}
else {
    cap gen hour = .
}

* underemp: hour<35 & employed
cap drop underemp
gen underemp = 1 if hour < 35 & hour > 0
replace underemp = 0 if hour == 0
replace underemp = 0 if hour >= 35 & hour != .

* underemp_invol & underemp_vol (legacy formula)
cap drop underemp_invol underemp_vol
gen underemp_invol = .
cap confirm variable b4p4
local has_i1 = !_rc
cap confirm variable b4p24
local has_i2 = !_rc
if `has_i1' & `has_i2' {
    replace underemp_invol = 0 if underemp == 1
    replace underemp_invol = 1 if (b4p4 == 1 | b4p24 == 1) & underemp == 1
}
gen underemp_vol = .
replace underemp_vol = 1 if underemp == 1 & underemp_invol == 0
replace underemp_vol = 0 if underemp == 1 & underemp_invol == 1

* hour decomposed
cap drop hour_under hour_vol hour_invol
gen hour_under = hour if underemp == 1
gen hour_vol   = hour if underemp_vol == 1
gen hour_invol = hour if underemp_invol == 1

* status (employment status, 1-7)
cap drop status
cap confirm variable b4p10
if !_rc {
    gen status = b4p10 if employment == 1
    replace status = . if status == 0
}
else {
    gen status = .
}

* worktype (1-digit code; take first digit if multi-digit)
cap drop worktype
cap confirm variable jenpek
if !_rc {
    gen _wt_raw = jenpek if employment == 1
    gen worktype = .
    replace worktype = real(substr(string(int(abs(_wt_raw))), 1, 1)) if _wt_raw != . & _wt_raw > 0
    replace worktype = _wt_raw if abs(_wt_raw) < 10 & _wt_raw != .
    drop _wt_raw
}
else {
    gen worktype = .
}

* formal_simple: status in (3,4)
cap drop formal_simple
gen formal_simple = inrange(status, 3, 4) if status != . & employment == 1

* formal_new: wrktype2011 matrix
cap drop formal_new
gen formal_new = .
replace formal_new = wrktype2011[status, worktype] ///
    if status != . & worktype != . & employment == 1 ///
    & inrange(status, 1, 7) & inrange(worktype, 1, 8)

* formal_old: formal_new + casual workers in agri/construction
cap drop formal_old
gen formal_old = formal_new
replace formal_old = 1 if (status == 5 & sector9 == 1) & employment == 1
replace formal_old = 1 if (status == 6 & sector9 == 5) & employment == 1

* labels
cap label var hour           "working hours per week (all jobs combined)"
cap label var underemp       "underemployed dummy (less than 35 hours per week)"
cap label var underemp_invol "involuntary underemployment"
cap label var underemp_vol   "voluntary underemployment"
cap label var hour_under     "weekly hours among underemployed"
cap label var hour_vol       "weekly hours among voluntary underemployed"
cap label var hour_invol     "weekly hours among involuntary underemployed"
cap label var status         "main employment status"
cap label var worktype       "main occupation (1-digit KBJI)"
cap label var formal_simple  "simplified formality (employee or assisted employer)"
cap label var formal_new     "formality (wrktype2011 matrix)"
cap label var formal_old     "formality including casual workers in agriculture and construction"
**---------------------------------------------------------------------------
** Additional Employment Indicators
**---------------------------------------------------------------------------
cap drop employee casual_worker potential_exp
gen employee = work_status == 4 if work_status != .
gen casual_worker = inlist(work_status, 5, 6) if work_status != .
gen potential_exp = age - school_years if age != . & school_years != .
cap label var employee      "employee dummy"
cap label var casual_worker "casual worker dummy"
cap label var potential_exp "potential work experience"


keep prov`year' wt urban male age educ unemp employment lf school_years sector9 sector17 work_informal work_status act_neet act_school act_household act_others work_hours work_whitecoll work_earnings work_wage work_jobdur* educ_group work_searchdur_* year
save $clean/clean_sakernas_`year', replace

/*************************
 * End of Sakernas 2006
 ************************/
 
 /*************************
 * Sakernas 2007
 ************************/

clear
set more off
local year = 2007
use $source/sakernas_`year', clear

*-----------------------------------------------------------
* Basic Variables and Identifiers
*-----------------------------------------------------------
gen prov`year' = b1p01
gen wt         = weight
gen urban      = (b1p05 == 1)
gen male       = (jk == 1)
gen age        = umur         // WARNING: AGE OUTSIDE LF DETECTED
gen educ       = b4p1a

*-----------------------------------------------------------
* Employment and Unemployment Status
*-----------------------------------------------------------
gen unemp = .
replace unemp = 1 if b4p2a1 == 2 & b4p3 == 2 & b4p4 == 1
replace unemp = 1 if b4p2a1 == 2 & b4p3 == 2 & b4p5 == 1
replace unemp = 1 if b4p2a1 == 2 & inlist(b4p23, 1, 2)
replace unemp = 0 if unemp != 1

gen employment = .
replace employment = 1 if b4p2a1 == 1
replace employment = 1 if b4p3 == 1
replace employment = 0 if unemp == 1

*-----------------------------------------------------------
* Labor Force Definition
*-----------------------------------------------------------
gen lf = .
replace lf = 1 if employment == 1 | unemp == 1
replace lf = 0 if age < 15
replace lf = 0 if lf != 1
replace unemp = . if lf == 0
replace employment = . if lf == 0

*-----------------------------------------------------------
* Sector and Work-Related Variables
*-----------------------------------------------------------
gen sector9 = klui  // Use the variable "klui" as provided
// (Sector recoding not needed if "klui" is already a proper code)

#d;
									recode b4p7
										(0 = 18)
										(111 = 1)
										(504 = 1)
										(527 = 7)
										(1111 = 1)
										(1112 = 1)
										(1113 = 1)
										(1114 = 1)
										(1115 = 1)
										(1116 = 1)
										(1117 = 1)
										(1118 = 1)
										(1119 = 1)
										(1121 = 1)
										(1122 = 1)
										(1123 = 1)
										(1124 = 1)
										(1125 = 1)
										(1131 = 1)
										(1132 = 1)
										(1133 = 1)
										(1134 = 1)
										(1135 = 1)
										(1136 = 1)
										(1137 = 1)
										(1138 = 1)
										(1139 = 1)
										(1211 = 1)
										(1212 = 1)
										(1213 = 1)
										(1214 = 1)
										(1215 = 1)
										(1216 = 1)
										(1217 = 1)
										(1218 = 1)
										(1221 = 1)
										(1222 = 1)
										(1223 = 1)
										(1224 = 1)
										(1225 = 1)
										(1226 = 1)
										(1227 = 1)
										(1228 = 1)
										(1229 = 1)
										(1401 = 1)
										(1402 = 1)
										(1403 = 1)
										(1404 = 1)
										(1405 = 1)
										(1406 = 1)
										(1407 = 1)
										(1408 = 1)
										(1410 = 2)
										(1501 = 1)
										(1502 = 1)
										(2011 = 1)
										(2012 = 1)
										(2013 = 1)
										(2014 = 1)
										(2015 = 1)
										(2016 = 1)
										(2017 = 1)
										(2018 = 1)
										(2019 = 1)
										(2020 = 1)
										(2031 = 1)
										(2032 = 1)
										(2033 = 1)
										(2034 = 1)
										(2035 = 1)
										(2039 = 1)
										(2041 = 1)
										(2042 = 1)
										(2043 = 1)
										(2049 = 1)
										(2051 = 1)
										(2052 = 1)
										(2059 = 1)
										(5011 = 1)
										(5012 = 1)
										(5013 = 1)
										(5014 = 1)
										(5015 = 1)
										(5021 = 1)
										(5022 = 1)
										(5031 = 1)
										(5032 = 1)
										(5041 = 1)
										(5042 = 1)
										(5043 = 1)
										(5044 = 1)
										(5051 = 1)
										(5052 = 1)
										(5053 = 1)
										(5054 = 1)
										(5055 = 1)
										(5056 = 1)
										(5521 = 9)
										(6021 = 8)
										(6711 = 11)
										(6712 = 11)
										(7523 = 14)
										(8011 = 15)
										(10101 = 2)
										(10102 = 2)
										(10200 = 3)
										(11101 = 2)
										(11102 = 2)
										(11200 = 2)
										(12000 = 2)
										(13101 = 2)
										(13102 = 2)
										(13201 = 2)
										(13202 = 2)
										(13203 = 2)
										(13204 = 2)
										(13205 = 2)
										(13206 = 2)
										(13207 = 2)
										(13209 = 2)
										(14101 = 2)
										(14102 = 2)
										(14103 = 2)
										(14104 = 2)
										(14105 = 2)
										(14106 = 2)
										(14211 = 2)
										(14212 = 2)
										(14213 = 2)
										(14214 = 2)
										(14215 = 2)
										(14219 = 2)
										(14220 = 2)
										(14291 = 2)
										(14292 = 2)
										(14299 = 2)
										(15111 = 3)
										(15112 = 3)
										(15121 = 3)
										(15122 = 3)
										(15123 = 3)
										(15124 = 3)
										(15125 = 3)
										(15129 = 3)
										(15131 = 3)
										(15132 = 3)
										(15133 = 3)
										(15134 = 3)
										(15139 = 3)
										(15141 = 3)
										(15142 = 3)
										(15143 = 3)
										(15144 = 3)
										(15145 = 3)
										(15149 = 3)
										(15201 = 3)
										(15202 = 3)
										(15203 = 3)
										(15311 = 3)
										(15312 = 3)
										(15313 = 3)
										(15314 = 3)
										(15315 = 3)
										(15316 = 3)
										(15317 = 3)
										(15318 = 3)
										(15321 = 3)
										(15322 = 3)
										(15323 = 3)
										(15324 = 3)
										(15329 = 3)
										(15331 = 3)
										(15332 = 3)
										(15410 = 3)
										(15421 = 3)
										(15422 = 3)
										(15423 = 3)
										(15424 = 3)
										(15429 = 3)
										(15431 = 3)
										(15432 = 3)
										(15440 = 3)
										(15491 = 3)
										(15492 = 3)
										(15493 = 3)
										(15494 = 3)
										(15495 = 3)
										(15496 = 3)
										(15497 = 3)
										(15498 = 3)
										(15499 = 3)
										(15510 = 3)
										(15520 = 3)
										(15530 = 3)
										(15541 = 3)
										(15542 = 3)
										(16001 = 3)
										(16002 = 3)
										(16003 = 3)
										(16004 = 3)
										(16009 = 3)
										(17111 = 3)
										(17112 = 3)
										(17113 = 3)
										(17114 = 3)
										(17115 = 3)
										(17121 = 3)
										(17122 = 3)
										(17123 = 3)
										(17124 = 3)
										(17211 = 3)
										(17212 = 3)
										(17213 = 3)
										(17214 = 3)
										(17215 = 3)
										(17220 = 3)
										(17231 = 3)
										(17232 = 3)
										(17291 = 3)
										(17292 = 3)
										(17293 = 3)
										(17294 = 3)
										(17295 = 3)
										(17299 = 3)
										(17301 = 3)
										(17302 = 3)
										(17303 = 3)
										(17304 = 3)
										(17400 = 3)
										(18101 = 3)
										(18102 = 3)
										(18201 = 3)
										(18202 = 3)
										(18203 = 3)
										(19111 = 3)
										(19112 = 3)
										(19113 = 3)
										(19121 = 3)
										(19122 = 3)
										(19123 = 3)
										(19129 = 3)
										(19201 = 3)
										(19202 = 3)
										(19203 = 3)
										(19209 = 3)
										(20101 = 3)
										(20102 = 3)
										(20103 = 3)
										(20104 = 3)
										(20211 = 3)
										(20212 = 3)
										(20213 = 3)
										(20214 = 3)
										(20220 = 3)
										(20230 = 3)
										(20291 = 3)
										(20292 = 3)
										(20293 = 3)
										(20294 = 3)
										(20299 = 3)
										(21011 = 3)
										(21012 = 3)
										(21013 = 3)
										(21014 = 3)
										(21015 = 3)
										(21016 = 3)
										(21019 = 3)
										(21020 = 3)
										(21090 = 3)
										(22110 = 10)
										(22120 = 10)
										(22130 = 10)
										(22140 = 3)
										(22190 = 10)
										(22210 = 3)
										(22220 = 3)
										(22301 = 3)
										(22302 = 3)
										(23100 = 3)
										(23201 = 3)
										(23202 = 4)
										(23203 = 3)
										(23204 = 3)
										(23205 = 3)
										(23300 = 3)
										(24111 = 3)
										(24112 = 3)
										(24113 = 3)
										(24114 = 3)
										(24115 = 3)
										(24116 = 3)
										(24117 = 3)
										(24118 = 3)
										(24119 = 3)
										(24121 = 5)
										(24122 = 3)
										(24123 = 3)
										(24124 = 3)
										(24125 = 3)
										(24126 = 3)
										(24127 = 3)
										(24129 = 3)
										(24131 = 3)
										(24132 = 3)
										(24211 = 3)
										(24212 = 3)
										(24213 = 3)
										(24214 = 3)
										(24221 = 3)
										(24222 = 3)
										(24223 = 3)
										(24231 = 3)
										(24232 = 3)
										(24233 = 3)
										(24234 = 3)
										(24235 = 3)
										(24241 = 3)
										(24242 = 3)
										(24291 = 3)
										(24292 = 3)
										(24293 = 3)
										(24294 = 3)
										(24295 = 3)
										(24299 = 3)
										(24301 = 3)
										(24302 = 3)
										(25111 = 3)
										(25112 = 3)
										(25121 = 3)
										(25122 = 3)
										(25123 = 3)
										(25191 = 3)
										(25192 = 3)
										(25199 = 3)
										(25201 = 3)
										(25202 = 3)
										(25203 = 3)
										(25204 = 3)
										(25205 = 3)
										(25206 = 3)
										(25209 = 3)
										(26111 = 3)
										(26112 = 3)
										(26119 = 3)
										(26121 = 3)
										(26122 = 3)
										(26123 = 3)
										(26124 = 3)
										(26129 = 3)
										(26201 = 3)
										(26202 = 3)
										(26203 = 3)
										(26209 = 3)
										(26311 = 3)
										(26319 = 3)
										(26321 = 3)
										(26322 = 3)
										(26323 = 3)
										(26324 = 3)
										(26411 = 3)
										(26412 = 3)
										(26413 = 3)
										(26421 = 3)
										(26422 = 3)
										(26423 = 3)
										(26429 = 3)
										(26501 = 3)
										(26502 = 3)
										(26503 = 3)
										(26509 = 3)
										(26601 = 3)
										(26602 = 3)
										(26609 = 3)
										(26900 = 3)
										(27101 = 3)
										(27102 = 3)
										(27103 = 3)
										(27201 = 3)
										(27202 = 3)
										(27203 = 3)
										(27204 = 3)
										(27310 = 3)
										(27320 = 3)
										(28111 = 3)
										(28112 = 3)
										(28113 = 3)
										(28119 = 3)
										(28120 = 3)
										(28910 = 3)
										(28920 = 3)
										(28931 = 3)
										(28932 = 3)
										(28933 = 3)
										(28939 = 3)
										(28991 = 3)
										(28992 = 3)
										(28993 = 3)
										(28994 = 3)
										(28995 = 3)
										(28996 = 3)
										(28997 = 3)
										(28998 = 3)
										(28999 = 3)
										(29111 = 3)
										(29112 = 3)
										(29113 = 3)
										(29114 = 3)
										(29120 = 3)
										(29130 = 3)
										(29141 = 3)
										(29142 = 3)
										(29150 = 3)
										(29191 = 3)
										(29192 = 3)
										(29193 = 3)
										(29199 = 3)
										(29211 = 3)
										(29212 = 3)
										(29221 = 3)
										(29222 = 3)
										(29223 = 3)
										(29224 = 3)
										(29230 = 3)
										(29240 = 3)
										(29250 = 3)
										(29261 = 3)
										(29262 = 3)
										(29263 = 3)
										(29264 = 3)
										(29270 = 3)
										(29291 = 3)
										(29292 = 3)
										(29299 = 3)
										(29301 = 3)
										(29302 = 3)
										(29309 = 3)
										(30001 = 3)
										(30002 = 3)
										(30003 = 3)
										(30004 = 3)
										(31101 = 3)
										(31102 = 3)
										(31103 = 3)
										(31201 = 3)
										(31202 = 3)
										(31300 = 3)
										(31401 = 3)
										(31402 = 3)
										(31501 = 3)
										(31502 = 3)
										(31509 = 3)
										(31900 = 3)
										(32100 = 3)
										(32200 = 3)
										(32300 = 3)
										(33111 = 3)
										(33112 = 3)
										(33113 = 3)
										(33119 = 3)
										(33121 = 3)
										(33122 = 3)
										(33123 = 3)
										(33130 = 3)
										(33201 = 3)
										(33202 = 3)
										(33203 = 3)
										(33204 = 3)
										(33300 = 3)
										(34100 = 3)
										(34200 = 3)
										(34300 = 3)
										(35111 = 3)
										(35112 = 3)
										(35113 = 3)
										(35114 = 5)
										(35115 = 3)
										(35120 = 3)
										(35201 = 3)
										(35202 = 3)
										(35301 = 3)
										(35302 = 3)
										(35911 = 3)
										(35912 = 3)
										(35921 = 3)
										(35922 = 3)
										(35990 = 3)
										(36101 = 3)
										(36102 = 3)
										(36103 = 3)
										(36104 = 3)
										(36109 = 3)
										(36911 = 3)
										(36912 = 3)
										(36913 = 3)
										(36914 = 3)
										(36915 = 3)
										(36921 = 3)
										(36922 = 3)
										(36930 = 3)
										(36941 = 3)
										(36942 = 3)
										(36991 = 3)
										(36992 = 3)
										(36993 = 3)
										(36999 = 3)
										(37100 = 5)
										(37200 = 5)
										(40101 = 4)
										(40102 = 4)
										(40103 = 4)
										(40104 = 4)
										(40201 = 4)
										(40202 = 4)
										(40300 = 4)
										(41001 = 5)
										(41002 = 5)
										(41003 = 5)
										(45100 = 6)
										(45211 = 6)
										(45212 = 6)
										(45213 = 6)
										(45214 = 6)
										(45215 = 6)
										(45216 = 6)
										(45217 = 6)
										(45218 = 6)
										(45219 = 6)
										(45221 = 6)
										(45222 = 6)
										(45223 = 6)
										(45224 = 6)
										(45225 = 6)
										(45226 = 6)
										(45227 = 6)
										(45229 = 6)
										(45231 = 6)
										(45232 = 6)
										(45233 = 6)
										(45234 = 6)
										(45235 = 6)
										(45239 = 6)
										(45241 = 6)
										(45242 = 6)
										(45243 = 6)
										(45244 = 6)
										(45245 = 6)
										(45246 = 6)
										(45249 = 6)
										(45311 = 6)
										(45312 = 6)
										(45313 = 6)
										(45314 = 6)
										(45315 = 6)
										(45316 = 6)
										(45317 = 6)
										(45319 = 6)
										(45321 = 6)
										(45322 = 6)
										(45323 = 6)
										(45324 = 6)
										(45325 = 6)
										(45326 = 6)
										(45327 = 6)
										(45328 = 6)
										(45329 = 6)
										(45401 = 6)
										(45402 = 6)
										(45403 = 6)
										(45404 = 6)
										(45405 = 6)
										(45409 = 6)
										(45500 = 6)
										(50101 = 7)
										(50102 = 7)
										(50201 = 7)
										(50202 = 7)
										(50301 = 7)
										(50302 = 7)
										(50400 = 7)
										(51100 = 7)
										(51211 = 7)
										(51212 = 7)
										(51213 = 7)
										(51214 = 7)
										(51220 = 7)
										(51310 = 7)
										(51391 = 7)
										(51392 = 7)
										(51399 = 7)
										(51410 = 7)
										(51420 = 7)
										(51431 = 7)
										(51432 = 7)
										(51433 = 7)
										(51434 = 7)
										(51435 = 7)
										(51436 = 7)
										(51437 = 7)
										(51438 = 7)
										(51439 = 7)
										(51490 = 7)
										(51501 = 7)
										(51502 = 7)
										(51503 = 7)
										(51504 = 7)
										(51900 = 7)
										(52111 = 7)
										(52112 = 7)
										(52191 = 7)
										(52192 = 7)
										(52211 = 7)
										(52212 = 7)
										(52213 = 7)
										(52214 = 7)
										(52215 = 7)
										(52219 = 7)
										(52221 = 7)
										(52222 = 7)
										(52223 = 7)
										(52224 = 7)
										(52225 = 7)
										(52226 = 7)
										(52227 = 7)
										(52228 = 7)
										(52229 = 7)
										(52311 = 7)
										(52312 = 7)
										(52313 = 7)
										(52314 = 7)
										(52315 = 7)
										(52316 = 7)
										(52317 = 7)
										(52318 = 7)
										(52319 = 7)
										(52321 = 7)
										(52322 = 7)
										(52323 = 7)
										(52324 = 7)
										(52325 = 7)
										(52326 = 7)
										(52327 = 7)
										(52328 = 7)
										(52329 = 7)
										(52331 = 7)
										(52332 = 7)
										(52333 = 7)
										(52334 = 7)
										(52335 = 7)
										(52336 = 7)
										(52337 = 7)
										(52338 = 7)
										(52339 = 7)
										(52341 = 7)
										(52342 = 7)
										(52343 = 7)
										(52344 = 7)
										(52345 = 7)
										(52346 = 7)
										(52347 = 7)
										(52348 = 7)
										(52349 = 7)
										(52351 = 7)
										(52352 = 7)
										(52353 = 7)
										(52354 = 7)
										(52359 = 7)
										(52361 = 7)
										(52362 = 7)
										(52363 = 7)
										(52364 = 7)
										(52365 = 7)
										(52366 = 7)
										(52367 = 7)
										(52368 = 7)
										(52371 = 7)
										(52372 = 7)
										(52373 = 7)
										(52374 = 7)
										(52375 = 7)
										(52381 = 7)
										(52382 = 7)
										(52383 = 7)
										(52384 = 7)
										(52385 = 7)
										(52386 = 7)
										(52389 = 7)
										(52391 = 7)
										(52392 = 7)
										(52393 = 7)
										(52394 = 7)
										(52395 = 7)
										(52399 = 7)
										(52401 = 7)
										(52402 = 7)
										(52403 = 7)
										(52404 = 7)
										(52405 = 7)
										(52406 = 7)
										(52409 = 7)
										(52511 = 7)
										(52512 = 7)
										(52513 = 7)
										(52514 = 7)
										(52515 = 7)
										(52516 = 7)
										(52521 = 7)
										(52522 = 7)
										(52523 = 7)
										(52524 = 7)
										(52525 = 7)
										(52526 = 7)
										(52527 = 7)
										(52528 = 7)
										(52529 = 7)
										(52531 = 7)
										(52532 = 7)
										(52533 = 7)
										(52534 = 7)
										(52535 = 7)
										(52536 = 7)
										(52539 = 7)
										(52541 = 7)
										(52542 = 7)
										(52543 = 7)
										(52544 = 7)
										(52545 = 7)
										(52546 = 7)
										(52547 = 7)
										(52548 = 7)
										(52549 = 7)
										(52551 = 7)
										(52552 = 7)
										(52553 = 7)
										(52554 = 7)
										(52555 = 7)
										(52556 = 7)
										(52557 = 7)
										(52559 = 7)
										(52561 = 7)
										(52569 = 7)
										(52571 = 7)
										(52572 = 7)
										(52573 = 7)
										(52574 = 7)
										(52575 = 7)
										(52576 = 7)
										(52577 = 7)
										(52581 = 7)
										(52582 = 7)
										(52583 = 7)
										(52591 = 7)
										(52592 = 7)
										(52593 = 7)
										(52594 = 7)
										(52595 = 7)
										(52600 = 7)
										(52711 = 7)
										(52712 = 7)
										(52713 = 7)
										(52714 = 7)
										(52719 = 7)
										(52721 = 7)
										(52722 = 7)
										(52723 = 7)
										(52724 = 7)
										(52725 = 7)
										(52726 = 7)
										(52727 = 7)
										(52728 = 7)
										(52729 = 7)
										(53100 = 7)
										(53211 = 7)
										(53212 = 7)
										(53213 = 7)
										(53214 = 7)
										(53220 = 7)
										(53310 = 7)
										(53391 = 7)
										(53392 = 7)
										(53399 = 7)
										(53410 = 7)
										(53420 = 7)
										(53430 = 7)
										(53491 = 7)
										(53492 = 7)
										(53500 = 7)
										(53900 = 7)
										(54100 = 7)
										(54211 = 7)
										(54212 = 7)
										(54213 = 7)
										(54214 = 7)
										(54220 = 7)
										(54310 = 7)
										(54391 = 7)
										(54392 = 7)
										(54399 = 7)
										(54410 = 7)
										(54420 = 7)
										(54430 = 7)
										(54491 = 7)
										(54492 = 7)
										(54500 = 7)
										(54900 = 7)
										(55111 = 9)
										(55112 = 9)
										(55113 = 9)
										(55114 = 9)
										(55115 = 9)
										(55120 = 9)
										(55130 = 9)
										(55140 = 9)
										(55150 = 9)
										(55160 = 9)
										(55190 = 9)
										(55211 = 9)
										(55212 = 9)
										(55213 = 9)
										(55214 = 9)
										(55220 = 9)
										(55230 = 9)
										(55240 = 9)
										(55250 = 9)
										(55260 = 9)
										(60110 = 8)
										(60120 = 8)
										(60139 = 8)
										(60211 = 8)
										(60212 = 8)
										(60213 = 8)
										(60214 = 8)
										(60215 = 8)
										(60216 = 8)
										(60217 = 8)
										(60221 = 8)
										(60222 = 8)
										(60223 = 8)
										(60224 = 8)
										(60225 = 8)
										(60231 = 8)
										(60232 = 8)
										(60233 = 8)
										(60300 = 8)
										(61111 = 8)
										(61112 = 8)
										(61113 = 8)
										(61114 = 8)
										(61115 = 8)
										(61116 = 8)
										(61117 = 8)
										(61118 = 8)
										(61121 = 8)
										(61122 = 8)
										(61123 = 8)
										(61124 = 8)
										(61125 = 8)
										(61126 = 8)
										(61127 = 8)
										(61211 = 8)
										(61212 = 8)
										(61213 = 8)
										(61214 = 8)
										(61215 = 8)
										(61216 = 8)
										(61221 = 8)
										(61222 = 8)
										(61223 = 8)
										(61224 = 8)
										(61225 = 8)
										(61226 = 8)
										(62111 = 8)
										(62112 = 8)
										(62120 = 8)
										(62201 = 8)
										(62202 = 8)
										(62311 = 1)
										(62312 = 13)
										(62313 = 8)
										(62314 = 16)
										(62320 = 15)
										(62390 = 8)
										(63100 = 8)
										(63210 = 8)
										(63220 = 8)
										(63230 = 8)
										(63290 = 8)
										(63310 = 8)
										(63321 = 8)
										(63322 = 8)
										(63323 = 8)
										(63330 = 8)
										(63340 = 8)
										(63351 = 8)
										(63352 = 8)
										(63390 = 8)
										(63411 = 13)
										(63412 = 13)
										(63413 = 13)
										(63414 = 13)
										(63415 = 13)
										(63420 = 13)
										(63430 = 13)
										(63440 = 13)
										(63450 = 17)
										(63460 = 13)
										(63470 = 13)
										(63490 = 13)
										(63510 = 8)
										(63520 = 8)
										(63530 = 8)
										(63540 = 8)
										(63590 = 8)
										(63900 = 8)
										(64110 = 8)
										(64120 = 8)
										(64130 = 8)
										(64210 = 10)
										(64221 = 10)
										(64222 = 10)
										(64223 = 10)
										(64311 = 10)
										(64312 = 10)
										(64313 = 10)
										(64314 = 10)
										(64319 = 10)
										(64321 = 10)
										(64322 = 10)
										(64323 = 7)
										(64324 = 10)
										(64325 = 10)
										(64329 = 10)
										(64410 = 10)
										(64420 = 10)
										(64430 = 10)
										(65110 = 11)
										(65121 = 11)
										(65122 = 11)
										(65123 = 11)
										(65191 = 11)
										(65192 = 11)
										(65199 = 11)
										(65910 = 11)
										(65921 = 11)
										(65922 = 11)
										(65923 = 11)
										(65929 = 11)
										(65930 = 11)
										(65940 = 11)
										(65950 = 11)
										(65991 = 11)
										(65999 = 13)
										(66010 = 11)
										(66020 = 11)
										(66030 = 11)
										(67111 = 11)
										(67112 = 11)
										(67113 = 11)
										(67121 = 11)
										(67122 = 11)
										(67123 = 11)
										(67131 = 11)
										(67132 = 11)
										(67133 = 11)
										(67134 = 11)
										(67191 = 11)
										(67199 = 11)
										(67201 = 11)
										(67202 = 11)
										(67203 = 11)
										(67204 = 11)
										(67209 = 11)
										(70101 = 12)
										(70102 = 9)
										(70200 = 12)
										(70310 = 12)
										(70320 = 17)
										(71110 = 13)
										(71120 = 13)
										(71130 = 13)
										(71210 = 13)
										(71220 = 13)
										(71230 = 13)
										(71290 = 13)
										(71301 = 13)
										(71302 = 13)
										(71303 = 13)
										(71304 = 13)
										(71305 = 13)
										(71306 = 13)
										(71309 = 13)
										(72100 = 10)
										(72200 = 10)
										(72300 = 10)
										(72400 = 10)
										(72500 = 3)
										(72900 = 10)
										(73110 = 13)
										(73120 = 13)
										(73210 = 13)
										(73220 = 13)
										(74110 = 13)
										(74120 = 13)
										(74130 = 13)
										(74140 = 13)
										(74210 = 13)
										(74220 = 13)
										(74300 = 13)
										(74910 = 13)
										(74920 = 13)
										(74930 = 13)
										(74940 = 13)
										(74950 = 13)
										(74990 = 13)
										(75111 = 14)
										(75112 = 14)
										(75113 = 14)
										(75114 = 14)
										(75115 = 14)
										(75121 = 14)
										(75122 = 14)
										(75123 = 14)
										(75124 = 14)
										(75125 = 14)
										(75126 = 14)
										(75127 = 14)
										(75129 = 14)
										(75131 = 14)
										(75132 = 14)
										(75133 = 14)
										(75134 = 14)
										(75135 = 14)
										(75136 = 14)
										(75137 = 14)
										(75138 = 14)
										(75139 = 14)
										(75140 = 14)
										(75210 = 14)
										(75221 = 14)
										(75222 = 14)
										(75223 = 14)
										(75224 = 14)
										(75231 = 14)
										(75232 = 14)
										(75233 = 14)
										(75300 = 14)
										(80111 = 15)
										(80112 = 15)
										(80113 = 15)
										(80121 = 15)
										(80122 = 15)
										(80123 = 15)
										(80211 = 15)
										(80212 = 15)
										(80221 = 15)
										(80222 = 15)
										(80311 = 15)
										(80312 = 15)
										(80321 = 15)
										(80322 = 15)
										(80910 = 15)
										(80921 = 15)
										(80922 = 15)
										(80923 = 15)
										(80929 = 15)
										(85111 = 16)
										(85112 = 16)
										(85113 = 16)
										(85114 = 16)
										(85119 = 16)
										(85121 = 16)
										(85122 = 16)
										(85123 = 16)
										(85191 = 16)
										(85192 = 16)
										(85193 = 16)
										(85200 = 13)
										(85311 = 16)
										(85312 = 16)
										(85313 = 16)
										(85314 = 16)
										(85319 = 16)
										(85321 = 16)
										(85322 = 16)
										(90001 = 5)
										(90002 = 5)
										(91110 = 17)
										(91121 = 17)
										(91122 = 17)
										(91200 = 17)
										(91910 = 17)
										(91920 = 17)
										(91990 = 17)
										(92111 = 10)
										(92112 = 10)
										(92120 = 10)
										(92131 = 10)
										(92132 = 10)
										(92141 = 17)
										(92142 = 17)
										(92143 = 13)
										(92190 = 17)
										(92201 = 10)
										(92202 = 10)
										(92203 = 17)
										(92311 = 17)
										(92312 = 17)
										(92321 = 17)
										(92322 = 17)
										(92323 = 17)
										(92324 = 17)
										(92331 = 17)
										(92332 = 17)
										(92333 = 17)
										(92334 = 17)
										(92335 = 17)
										(92336 = 17)
										(92339 = 17)
										(92411 = 17)
										(92412 = 17)
										(92413 = 17)
										(92414 = 17)
										(92415 = 17)
										(92416 = 17)
										(92417 = 17)
										(92418 = 17)
										(92419 = 17)
										(92421 = 17)
										(92422 = 17)
										(92423 = 17)
										(92424 = 17)
										(92425 = 9)
										(92426 = 17)
										(92427 = 17)
										(92428 = 17)
										(92429 = 17)
										(92431 = 17)
										(92432 = 17)
										(92433 = 17)
										(92434 = 17)
										(92439 = 17)
										(93010 = 17)
										(93021 = 17)
										(93022 = 17)
										(93030 = 17)
										(93040 = 7)
										(93050 = 7)
										(93061 = 17)
										(93062 = 17)
										(93069 = 17)
										(93091 = 3)
										(93092 = 13)
										(93093 = 17)
										(93094 = 17)
										(95000 = 17)
										(99000 = 17)
										(99999 = 17)
										(1300 = 1)
										(15211 = 3)
										(15212 = 3)
										(26329 = 3)
										(50401 = 7)
										(50402 = 7)
										(50500 = 7)
										(52216 = 7)
										(52602 = 7)
										(92148 = 7)
										(51339 = 7)
										(60112 = 8)
										(60131 = 8)
										(63120 = 8), gen(sector17)
									;
									#d cr

gen work_informal = inlist(b4p11a, 1, 2, 5, 6, 7)
gen work_status   = b4p11a
gen work_certif   = (b4p1c == 1)
    replace work_certif = . if lf == 0
gen work_whitecoll = inrange(b4p8, 1, 5999)

gen act_school    = ( (b4p2a2 == 1 | b4p2a2 == 2) & b4p2b == 2 & lf == 0 )
gen act_household = ( (b4p2a3 == 1 | b4p2a3 == 2) & b4p2b == 3 & lf == 0 )
gen act_others    = ( (b4p2a4 == 1 | b4p2a4 == 2) & b4p2b == 4 & lf == 0 )
gen act_neet = 0
replace act_neet = 1 if b4p2a1 == 2 & b4p2a2 == 2
replace act_neet = 0 if act_school == 1
// (Optional: adjust if household should affect NEET)
replace act_neet = . if age >= 25 | age <= 14

*-----------------------------------------------------------
* Employment Adjustment
*-----------------------------------------------------------
replace employment = 1 if employment == 0 & work_status != .

*-----------------------------------------------------------
* Work Outcome Variables
*-----------------------------------------------------------
gen work_hours    = b4p9
gen work_earnings = b4p13a + b4p13b
gen work_wage     = (b4p13a + b4p13b) if b4p11a == 4
gen work_jobdur   = b4p21

*-----------------------------------------------------------
* Recoding Education and Job Duration
*-----------------------------------------------------------
recode educ 1/3 = 1 4/7 = 2 8/10 = 3, generate(educ_group)
recode work_jobdur 0/3 = 1 4/12 = 2 12/24 = 3 25/99 = 4, gen(work_jobdur_cat)

*-----------------------------------------------------------
* Estimate Years of Schooling
*-----------------------------------------------------------
gen school_years = .
replace school_years = 0 if educ == 1 | educ == 2
replace school_years = 6 if educ == 3
replace school_years = 9 if educ == 4
replace school_years = 9 if educ == 5
replace school_years = 12 if educ == 6
replace school_years = 12 if educ == 7
replace school_years = 14 if educ == 8
replace school_years = 15 if educ == 9
replace school_years = 16 if educ == 10

*-----------------------------------------------------------
* Job Search Duration Dummies
*-----------------------------------------------------------
la de searchdur 1 "1. <=3 bulan" 2 "2. 4-12 bulan" 3 "3. 13-24 bulan" 4 "4. >24 bulan"
la val work_jobdur_cat searchdur

forval x = 1/4 {
    gen work_searchdur_`x' = (work_jobdur_cat == `x')
    replace work_searchdur_`x' = . if lf == 0 | work_jobdur_cat == .
}

foreach var of varlist work_hours work_earnings work_wage {
    replace `var' = . if unemp == 1 | lf == 0
}

*-----------------------------------------------------------
* Finalize and Save 2007 Data
*-----------------------------------------------------------
gen year = `year'
// save $output/temp_sakernas_`year', replace


keep prov`year' wt urban male age educ unemp employment lf school_years sector9 sector17 ///
     work_informal work_status act_neet act_school act_household act_others work_hours ///
     work_whitecoll work_earnings work_wage work_jobdur* educ_group work_searchdur_* year work_certif

**---------------------------------------------------------------------------
** Working Hours, Underemployment, Status, and Formality Indicators (2007)
** Raw inputs: hours=b4p6b  status=b4p11a  occupation=kji82_1dgt  involuntary=(b4p4, b4p24)
**---------------------------------------------------------------------------

* hour: total working hours of all jobs (week)
cap confirm variable b4p6b
if !_rc {
    cap drop hour
    gen hour = b4p6b if employment == 1
}
else {
    cap gen hour = .
}

* underemp: hour<35 & employed
cap drop underemp
gen underemp = 1 if hour < 35 & hour > 0
replace underemp = 0 if hour == 0
replace underemp = 0 if hour >= 35 & hour != .

* underemp_invol & underemp_vol (legacy formula)
cap drop underemp_invol underemp_vol
gen underemp_invol = .
cap confirm variable b4p4
local has_i1 = !_rc
cap confirm variable b4p24
local has_i2 = !_rc
if `has_i1' & `has_i2' {
    replace underemp_invol = 0 if underemp == 1
    replace underemp_invol = 1 if (b4p4 == 1 | b4p24 == 1) & underemp == 1
}
gen underemp_vol = .
replace underemp_vol = 1 if underemp == 1 & underemp_invol == 0
replace underemp_vol = 0 if underemp == 1 & underemp_invol == 1

* hour decomposed
cap drop hour_under hour_vol hour_invol
gen hour_under = hour if underemp == 1
gen hour_vol   = hour if underemp_vol == 1
gen hour_invol = hour if underemp_invol == 1

* status (employment status, 1-7)
cap drop status
cap confirm variable b4p11a
if !_rc {
    gen status = b4p11a if employment == 1
    replace status = . if status == 0
}
else {
    gen status = .
}

* worktype (1-digit code; take first digit if multi-digit)
cap drop worktype
cap confirm variable kji82_1dgt
if !_rc {
    gen _wt_raw = kji82_1dgt if employment == 1
    gen worktype = .
    replace worktype = real(substr(string(int(abs(_wt_raw))), 1, 1)) if _wt_raw != . & _wt_raw > 0
    replace worktype = _wt_raw if abs(_wt_raw) < 10 & _wt_raw != .
    drop _wt_raw
}
else {
    gen worktype = .
}

* formal_simple: status in (3,4)
cap drop formal_simple
gen formal_simple = inrange(status, 3, 4) if status != . & employment == 1

* formal_new: wrktype2011 matrix
cap drop formal_new
gen formal_new = .
replace formal_new = wrktype2011[status, worktype] ///
    if status != . & worktype != . & employment == 1 ///
    & inrange(status, 1, 7) & inrange(worktype, 1, 8)

* formal_old: formal_new + casual workers in agri/construction
cap drop formal_old
gen formal_old = formal_new
replace formal_old = 1 if (status == 5 & sector9 == 1) & employment == 1
replace formal_old = 1 if (status == 6 & sector9 == 5) & employment == 1

* labels
cap label var hour           "working hours per week (all jobs combined)"
cap label var underemp       "underemployed dummy (less than 35 hours per week)"
cap label var underemp_invol "involuntary underemployment"
cap label var underemp_vol   "voluntary underemployment"
cap label var hour_under     "weekly hours among underemployed"
cap label var hour_vol       "weekly hours among voluntary underemployed"
cap label var hour_invol     "weekly hours among involuntary underemployed"
cap label var status         "main employment status"
cap label var worktype       "main occupation (1-digit KBJI)"
cap label var formal_simple  "simplified formality (employee or assisted employer)"
cap label var formal_new     "formality (wrktype2011 matrix)"
cap label var formal_old     "formality including casual workers in agriculture and construction"
**---------------------------------------------------------------------------
** Additional Employment Indicators
**---------------------------------------------------------------------------
cap drop employee casual_worker potential_exp
gen employee = work_status == 4 if work_status != .
gen casual_worker = inlist(work_status, 5, 6) if work_status != .
gen potential_exp = age - school_years if age != . & school_years != .
cap label var employee      "employee dummy"
cap label var casual_worker "casual worker dummy"
cap label var potential_exp "potential work experience"


save $clean/clean_sakernas_`year', replace

/*************************
 * End of Sakernas 2007
 ************************/

/*************************
 * Sakernas 2008
 ************************/

clear
set more off
local year = 2008
use $source/sakernas_`year', clear

*-----------------------------------------------------------
* Generate Basic Variables
*-----------------------------------------------------------
gen prov`year' = b1p01
gen wt         = weight
gen urban      = (b1p05 == 1)
gen male       = (jk == 1)
gen age        = umur         // WARNING: AGE OUTSIDE LF DETECTED
gen educ       = b5p1a

*-----------------------------------------------------------
* Employment and Unemployment Status
*-----------------------------------------------------------
gen unemp = .
replace unemp = 1 if b5p2a1 == 2 & b5p3 == 2 & b5p4 == 1
replace unemp = 1 if b5p2a1 == 2 & b5p3 == 2 & b5p5 == 1
replace unemp = 1 if b5p2a1 == 2 & inlist(b5p23, 1, 2)
replace unemp = 0 if unemp != 1

gen employment = .
replace employment = 1 if b5p2a1 == 1
replace employment = 1 if b5p3 == 1
replace employment = 0 if unemp == 1

*-----------------------------------------------------------
* Define Labor Force (LF)
*-----------------------------------------------------------
gen lf = .
replace lf = 1 if employment == 1 | unemp == 1
replace lf = 0 if age < 15
replace lf = 0 if lf != 1
replace unemp = . if lf == 0
replace employment = . if lf == 0

*-----------------------------------------------------------
* Sector and Work Variables
*-----------------------------------------------------------
gen sector9 = klui

#d;
									recode b5p7
										(0 = 18)
										(111 = 1)
										(504 = 1)
										(527 = 7)
										(1111 = 1)
										(1112 = 1)
										(1113 = 1)
										(1114 = 1)
										(1115 = 1)
										(1116 = 1)
										(1117 = 1)
										(1118 = 1)
										(1119 = 1)
										(1121 = 1)
										(1122 = 1)
										(1123 = 1)
										(1124 = 1)
										(1125 = 1)
										(1131 = 1)
										(1132 = 1)
										(1133 = 1)
										(1134 = 1)
										(1135 = 1)
										(1136 = 1)
										(1137 = 1)
										(1138 = 1)
										(1139 = 1)
										(1211 = 1)
										(1212 = 1)
										(1213 = 1)
										(1214 = 1)
										(1215 = 1)
										(1216 = 1)
										(1217 = 1)
										(1218 = 1)
										(1221 = 1)
										(1222 = 1)
										(1223 = 1)
										(1224 = 1)
										(1225 = 1)
										(1226 = 1)
										(1227 = 1)
										(1228 = 1)
										(1229 = 1)
										(1401 = 1)
										(1402 = 1)
										(1403 = 1)
										(1404 = 1)
										(1405 = 1)
										(1406 = 1)
										(1407 = 1)
										(1408 = 1)
										(1410 = 2)
										(1501 = 1)
										(1502 = 1)
										(2011 = 1)
										(2012 = 1)
										(2013 = 1)
										(2014 = 1)
										(2015 = 1)
										(2016 = 1)
										(2017 = 1)
										(2018 = 1)
										(2019 = 1)
										(2020 = 1)
										(2031 = 1)
										(2032 = 1)
										(2033 = 1)
										(2034 = 1)
										(2035 = 1)
										(2039 = 1)
										(2041 = 1)
										(2042 = 1)
										(2043 = 1)
										(2049 = 1)
										(2051 = 1)
										(2052 = 1)
										(2059 = 1)
										(5011 = 1)
										(5012 = 1)
										(5013 = 1)
										(5014 = 1)
										(5015 = 1)
										(5021 = 1)
										(5022 = 1)
										(5031 = 1)
										(5032 = 1)
										(5041 = 1)
										(5042 = 1)
										(5043 = 1)
										(5044 = 1)
										(5051 = 1)
										(5052 = 1)
										(5053 = 1)
										(5054 = 1)
										(5055 = 1)
										(5056 = 1)
										(5521 = 9)
										(6021 = 8)
										(6711 = 11)
										(6712 = 11)
										(7523 = 14)
										(8011 = 15)
										(10101 = 2)
										(10102 = 2)
										(10200 = 3)
										(11101 = 2)
										(11102 = 2)
										(11200 = 2)
										(12000 = 2)
										(13101 = 2)
										(13102 = 2)
										(13201 = 2)
										(13202 = 2)
										(13203 = 2)
										(13204 = 2)
										(13205 = 2)
										(13206 = 2)
										(13207 = 2)
										(13209 = 2)
										(14101 = 2)
										(14102 = 2)
										(14103 = 2)
										(14104 = 2)
										(14105 = 2)
										(14106 = 2)
										(14211 = 2)
										(14212 = 2)
										(14213 = 2)
										(14214 = 2)
										(14215 = 2)
										(14219 = 2)
										(14220 = 2)
										(14291 = 2)
										(14292 = 2)
										(14299 = 2)
										(15111 = 3)
										(15112 = 3)
										(15121 = 3)
										(15122 = 3)
										(15123 = 3)
										(15124 = 3)
										(15125 = 3)
										(15129 = 3)
										(15131 = 3)
										(15132 = 3)
										(15133 = 3)
										(15134 = 3)
										(15139 = 3)
										(15141 = 3)
										(15142 = 3)
										(15143 = 3)
										(15144 = 3)
										(15145 = 3)
										(15149 = 3)
										(15201 = 3)
										(15202 = 3)
										(15203 = 3)
										(15311 = 3)
										(15312 = 3)
										(15313 = 3)
										(15314 = 3)
										(15315 = 3)
										(15316 = 3)
										(15317 = 3)
										(15318 = 3)
										(15321 = 3)
										(15322 = 3)
										(15323 = 3)
										(15324 = 3)
										(15329 = 3)
										(15331 = 3)
										(15332 = 3)
										(15410 = 3)
										(15421 = 3)
										(15422 = 3)
										(15423 = 3)
										(15424 = 3)
										(15429 = 3)
										(15431 = 3)
										(15432 = 3)
										(15440 = 3)
										(15491 = 3)
										(15492 = 3)
										(15493 = 3)
										(15494 = 3)
										(15495 = 3)
										(15496 = 3)
										(15497 = 3)
										(15498 = 3)
										(15499 = 3)
										(15510 = 3)
										(15520 = 3)
										(15530 = 3)
										(15541 = 3)
										(15542 = 3)
										(16001 = 3)
										(16002 = 3)
										(16003 = 3)
										(16004 = 3)
										(16009 = 3)
										(17111 = 3)
										(17112 = 3)
										(17113 = 3)
										(17114 = 3)
										(17115 = 3)
										(17121 = 3)
										(17122 = 3)
										(17123 = 3)
										(17124 = 3)
										(17211 = 3)
										(17212 = 3)
										(17213 = 3)
										(17214 = 3)
										(17215 = 3)
										(17220 = 3)
										(17231 = 3)
										(17232 = 3)
										(17291 = 3)
										(17292 = 3)
										(17293 = 3)
										(17294 = 3)
										(17295 = 3)
										(17299 = 3)
										(17301 = 3)
										(17302 = 3)
										(17303 = 3)
										(17304 = 3)
										(17400 = 3)
										(18101 = 3)
										(18102 = 3)
										(18201 = 3)
										(18202 = 3)
										(18203 = 3)
										(19111 = 3)
										(19112 = 3)
										(19113 = 3)
										(19121 = 3)
										(19122 = 3)
										(19123 = 3)
										(19129 = 3)
										(19201 = 3)
										(19202 = 3)
										(19203 = 3)
										(19209 = 3)
										(20101 = 3)
										(20102 = 3)
										(20103 = 3)
										(20104 = 3)
										(20211 = 3)
										(20212 = 3)
										(20213 = 3)
										(20214 = 3)
										(20220 = 3)
										(20230 = 3)
										(20291 = 3)
										(20292 = 3)
										(20293 = 3)
										(20294 = 3)
										(20299 = 3)
										(21011 = 3)
										(21012 = 3)
										(21013 = 3)
										(21014 = 3)
										(21015 = 3)
										(21016 = 3)
										(21019 = 3)
										(21020 = 3)
										(21090 = 3)
										(22110 = 10)
										(22120 = 10)
										(22130 = 10)
										(22140 = 3)
										(22190 = 10)
										(22210 = 3)
										(22220 = 3)
										(22301 = 3)
										(22302 = 3)
										(23100 = 3)
										(23201 = 3)
										(23202 = 4)
										(23203 = 3)
										(23204 = 3)
										(23205 = 3)
										(23300 = 3)
										(24111 = 3)
										(24112 = 3)
										(24113 = 3)
										(24114 = 3)
										(24115 = 3)
										(24116 = 3)
										(24117 = 3)
										(24118 = 3)
										(24119 = 3)
										(24121 = 5)
										(24122 = 3)
										(24123 = 3)
										(24124 = 3)
										(24125 = 3)
										(24126 = 3)
										(24127 = 3)
										(24129 = 3)
										(24131 = 3)
										(24132 = 3)
										(24211 = 3)
										(24212 = 3)
										(24213 = 3)
										(24214 = 3)
										(24221 = 3)
										(24222 = 3)
										(24223 = 3)
										(24231 = 3)
										(24232 = 3)
										(24233 = 3)
										(24234 = 3)
										(24235 = 3)
										(24241 = 3)
										(24242 = 3)
										(24291 = 3)
										(24292 = 3)
										(24293 = 3)
										(24294 = 3)
										(24295 = 3)
										(24299 = 3)
										(24301 = 3)
										(24302 = 3)
										(25111 = 3)
										(25112 = 3)
										(25121 = 3)
										(25122 = 3)
										(25123 = 3)
										(25191 = 3)
										(25192 = 3)
										(25199 = 3)
										(25201 = 3)
										(25202 = 3)
										(25203 = 3)
										(25204 = 3)
										(25205 = 3)
										(25206 = 3)
										(25209 = 3)
										(26111 = 3)
										(26112 = 3)
										(26119 = 3)
										(26121 = 3)
										(26122 = 3)
										(26123 = 3)
										(26124 = 3)
										(26129 = 3)
										(26201 = 3)
										(26202 = 3)
										(26203 = 3)
										(26209 = 3)
										(26311 = 3)
										(26319 = 3)
										(26321 = 3)
										(26322 = 3)
										(26323 = 3)
										(26324 = 3)
										(26411 = 3)
										(26412 = 3)
										(26413 = 3)
										(26421 = 3)
										(26422 = 3)
										(26423 = 3)
										(26429 = 3)
										(26501 = 3)
										(26502 = 3)
										(26503 = 3)
										(26509 = 3)
										(26601 = 3)
										(26602 = 3)
										(26609 = 3)
										(26900 = 3)
										(27101 = 3)
										(27102 = 3)
										(27103 = 3)
										(27201 = 3)
										(27202 = 3)
										(27203 = 3)
										(27204 = 3)
										(27310 = 3)
										(27320 = 3)
										(28111 = 3)
										(28112 = 3)
										(28113 = 3)
										(28119 = 3)
										(28120 = 3)
										(28910 = 3)
										(28920 = 3)
										(28931 = 3)
										(28932 = 3)
										(28933 = 3)
										(28939 = 3)
										(28991 = 3)
										(28992 = 3)
										(28993 = 3)
										(28994 = 3)
										(28995 = 3)
										(28996 = 3)
										(28997 = 3)
										(28998 = 3)
										(28999 = 3)
										(29111 = 3)
										(29112 = 3)
										(29113 = 3)
										(29114 = 3)
										(29120 = 3)
										(29130 = 3)
										(29141 = 3)
										(29142 = 3)
										(29150 = 3)
										(29191 = 3)
										(29192 = 3)
										(29193 = 3)
										(29199 = 3)
										(29211 = 3)
										(29212 = 3)
										(29221 = 3)
										(29222 = 3)
										(29223 = 3)
										(29224 = 3)
										(29230 = 3)
										(29240 = 3)
										(29250 = 3)
										(29261 = 3)
										(29262 = 3)
										(29263 = 3)
										(29264 = 3)
										(29270 = 3)
										(29291 = 3)
										(29292 = 3)
										(29299 = 3)
										(29301 = 3)
										(29302 = 3)
										(29309 = 3)
										(30001 = 3)
										(30002 = 3)
										(30003 = 3)
										(30004 = 3)
										(31101 = 3)
										(31102 = 3)
										(31103 = 3)
										(31201 = 3)
										(31202 = 3)
										(31300 = 3)
										(31401 = 3)
										(31402 = 3)
										(31501 = 3)
										(31502 = 3)
										(31509 = 3)
										(31900 = 3)
										(32100 = 3)
										(32200 = 3)
										(32300 = 3)
										(33111 = 3)
										(33112 = 3)
										(33113 = 3)
										(33119 = 3)
										(33121 = 3)
										(33122 = 3)
										(33123 = 3)
										(33130 = 3)
										(33201 = 3)
										(33202 = 3)
										(33203 = 3)
										(33204 = 3)
										(33300 = 3)
										(34100 = 3)
										(34200 = 3)
										(34300 = 3)
										(35111 = 3)
										(35112 = 3)
										(35113 = 3)
										(35114 = 5)
										(35115 = 3)
										(35120 = 3)
										(35201 = 3)
										(35202 = 3)
										(35301 = 3)
										(35302 = 3)
										(35911 = 3)
										(35912 = 3)
										(35921 = 3)
										(35922 = 3)
										(35990 = 3)
										(36101 = 3)
										(36102 = 3)
										(36103 = 3)
										(36104 = 3)
										(36109 = 3)
										(36911 = 3)
										(36912 = 3)
										(36913 = 3)
										(36914 = 3)
										(36915 = 3)
										(36921 = 3)
										(36922 = 3)
										(36930 = 3)
										(36941 = 3)
										(36942 = 3)
										(36991 = 3)
										(36992 = 3)
										(36993 = 3)
										(36999 = 3)
										(37100 = 5)
										(37200 = 5)
										(40101 = 4)
										(40102 = 4)
										(40103 = 4)
										(40104 = 4)
										(40201 = 4)
										(40202 = 4)
										(40300 = 4)
										(41001 = 5)
										(41002 = 5)
										(41003 = 5)
										(45100 = 6)
										(45211 = 6)
										(45212 = 6)
										(45213 = 6)
										(45214 = 6)
										(45215 = 6)
										(45216 = 6)
										(45217 = 6)
										(45218 = 6)
										(45219 = 6)
										(45221 = 6)
										(45222 = 6)
										(45223 = 6)
										(45224 = 6)
										(45225 = 6)
										(45226 = 6)
										(45227 = 6)
										(45229 = 6)
										(45231 = 6)
										(45232 = 6)
										(45233 = 6)
										(45234 = 6)
										(45235 = 6)
										(45239 = 6)
										(45241 = 6)
										(45242 = 6)
										(45243 = 6)
										(45244 = 6)
										(45245 = 6)
										(45246 = 6)
										(45249 = 6)
										(45311 = 6)
										(45312 = 6)
										(45313 = 6)
										(45314 = 6)
										(45315 = 6)
										(45316 = 6)
										(45317 = 6)
										(45319 = 6)
										(45321 = 6)
										(45322 = 6)
										(45323 = 6)
										(45324 = 6)
										(45325 = 6)
										(45326 = 6)
										(45327 = 6)
										(45328 = 6)
										(45329 = 6)
										(45401 = 6)
										(45402 = 6)
										(45403 = 6)
										(45404 = 6)
										(45405 = 6)
										(45409 = 6)
										(45500 = 6)
										(50101 = 7)
										(50102 = 7)
										(50201 = 7)
										(50202 = 7)
										(50301 = 7)
										(50302 = 7)
										(50400 = 7)
										(51100 = 7)
										(51211 = 7)
										(51212 = 7)
										(51213 = 7)
										(51214 = 7)
										(51220 = 7)
										(51310 = 7)
										(51391 = 7)
										(51392 = 7)
										(51399 = 7)
										(51410 = 7)
										(51420 = 7)
										(51431 = 7)
										(51432 = 7)
										(51433 = 7)
										(51434 = 7)
										(51435 = 7)
										(51436 = 7)
										(51437 = 7)
										(51438 = 7)
										(51439 = 7)
										(51490 = 7)
										(51501 = 7)
										(51502 = 7)
										(51503 = 7)
										(51504 = 7)
										(51900 = 7)
										(52111 = 7)
										(52112 = 7)
										(52191 = 7)
										(52192 = 7)
										(52211 = 7)
										(52212 = 7)
										(52213 = 7)
										(52214 = 7)
										(52215 = 7)
										(52219 = 7)
										(52221 = 7)
										(52222 = 7)
										(52223 = 7)
										(52224 = 7)
										(52225 = 7)
										(52226 = 7)
										(52227 = 7)
										(52228 = 7)
										(52229 = 7)
										(52311 = 7)
										(52312 = 7)
										(52313 = 7)
										(52314 = 7)
										(52315 = 7)
										(52316 = 7)
										(52317 = 7)
										(52318 = 7)
										(52319 = 7)
										(52321 = 7)
										(52322 = 7)
										(52323 = 7)
										(52324 = 7)
										(52325 = 7)
										(52326 = 7)
										(52327 = 7)
										(52328 = 7)
										(52329 = 7)
										(52331 = 7)
										(52332 = 7)
										(52333 = 7)
										(52334 = 7)
										(52335 = 7)
										(52336 = 7)
										(52337 = 7)
										(52338 = 7)
										(52339 = 7)
										(52341 = 7)
										(52342 = 7)
										(52343 = 7)
										(52344 = 7)
										(52345 = 7)
										(52346 = 7)
										(52347 = 7)
										(52348 = 7)
										(52349 = 7)
										(52351 = 7)
										(52352 = 7)
										(52353 = 7)
										(52354 = 7)
										(52359 = 7)
										(52361 = 7)
										(52362 = 7)
										(52363 = 7)
										(52364 = 7)
										(52365 = 7)
										(52366 = 7)
										(52367 = 7)
										(52368 = 7)
										(52371 = 7)
										(52372 = 7)
										(52373 = 7)
										(52374 = 7)
										(52375 = 7)
										(52381 = 7)
										(52382 = 7)
										(52383 = 7)
										(52384 = 7)
										(52385 = 7)
										(52386 = 7)
										(52389 = 7)
										(52391 = 7)
										(52392 = 7)
										(52393 = 7)
										(52394 = 7)
										(52395 = 7)
										(52399 = 7)
										(52401 = 7)
										(52402 = 7)
										(52403 = 7)
										(52404 = 7)
										(52405 = 7)
										(52406 = 7)
										(52409 = 7)
										(52511 = 7)
										(52512 = 7)
										(52513 = 7)
										(52514 = 7)
										(52515 = 7)
										(52516 = 7)
										(52521 = 7)
										(52522 = 7)
										(52523 = 7)
										(52524 = 7)
										(52525 = 7)
										(52526 = 7)
										(52527 = 7)
										(52528 = 7)
										(52529 = 7)
										(52531 = 7)
										(52532 = 7)
										(52533 = 7)
										(52534 = 7)
										(52535 = 7)
										(52536 = 7)
										(52539 = 7)
										(52541 = 7)
										(52542 = 7)
										(52543 = 7)
										(52544 = 7)
										(52545 = 7)
										(52546 = 7)
										(52547 = 7)
										(52548 = 7)
										(52549 = 7)
										(52551 = 7)
										(52552 = 7)
										(52553 = 7)
										(52554 = 7)
										(52555 = 7)
										(52556 = 7)
										(52557 = 7)
										(52559 = 7)
										(52561 = 7)
										(52569 = 7)
										(52571 = 7)
										(52572 = 7)
										(52573 = 7)
										(52574 = 7)
										(52575 = 7)
										(52576 = 7)
										(52577 = 7)
										(52581 = 7)
										(52582 = 7)
										(52583 = 7)
										(52591 = 7)
										(52592 = 7)
										(52593 = 7)
										(52594 = 7)
										(52595 = 7)
										(52600 = 7)
										(52711 = 7)
										(52712 = 7)
										(52713 = 7)
										(52714 = 7)
										(52719 = 7)
										(52721 = 7)
										(52722 = 7)
										(52723 = 7)
										(52724 = 7)
										(52725 = 7)
										(52726 = 7)
										(52727 = 7)
										(52728 = 7)
										(52729 = 7)
										(53100 = 7)
										(53211 = 7)
										(53212 = 7)
										(53213 = 7)
										(53214 = 7)
										(53220 = 7)
										(53310 = 7)
										(53391 = 7)
										(53392 = 7)
										(53399 = 7)
										(53410 = 7)
										(53420 = 7)
										(53430 = 7)
										(53491 = 7)
										(53492 = 7)
										(53500 = 7)
										(53900 = 7)
										(54100 = 7)
										(54211 = 7)
										(54212 = 7)
										(54213 = 7)
										(54214 = 7)
										(54220 = 7)
										(54310 = 7)
										(54391 = 7)
										(54392 = 7)
										(54399 = 7)
										(54410 = 7)
										(54420 = 7)
										(54430 = 7)
										(54491 = 7)
										(54492 = 7)
										(54500 = 7)
										(54900 = 7)
										(55111 = 9)
										(55112 = 9)
										(55113 = 9)
										(55114 = 9)
										(55115 = 9)
										(55120 = 9)
										(55130 = 9)
										(55140 = 9)
										(55150 = 9)
										(55160 = 9)
										(55190 = 9)
										(55211 = 9)
										(55212 = 9)
										(55213 = 9)
										(55214 = 9)
										(55220 = 9)
										(55230 = 9)
										(55240 = 9)
										(55250 = 9)
										(55260 = 9)
										(60110 = 8)
										(60120 = 8)
										(60139 = 8)
										(60211 = 8)
										(60212 = 8)
										(60213 = 8)
										(60214 = 8)
										(60215 = 8)
										(60216 = 8)
										(60217 = 8)
										(60221 = 8)
										(60222 = 8)
										(60223 = 8)
										(60224 = 8)
										(60225 = 8)
										(60231 = 8)
										(60232 = 8)
										(60233 = 8)
										(60300 = 8)
										(61111 = 8)
										(61112 = 8)
										(61113 = 8)
										(61114 = 8)
										(61115 = 8)
										(61116 = 8)
										(61117 = 8)
										(61118 = 8)
										(61121 = 8)
										(61122 = 8)
										(61123 = 8)
										(61124 = 8)
										(61125 = 8)
										(61126 = 8)
										(61127 = 8)
										(61211 = 8)
										(61212 = 8)
										(61213 = 8)
										(61214 = 8)
										(61215 = 8)
										(61216 = 8)
										(61221 = 8)
										(61222 = 8)
										(61223 = 8)
										(61224 = 8)
										(61225 = 8)
										(61226 = 8)
										(62111 = 8)
										(62112 = 8)
										(62120 = 8)
										(62201 = 8)
										(62202 = 8)
										(62311 = 1)
										(62312 = 13)
										(62313 = 8)
										(62314 = 16)
										(62320 = 15)
										(62390 = 8)
										(63100 = 8)
										(63210 = 8)
										(63220 = 8)
										(63230 = 8)
										(63290 = 8)
										(63310 = 8)
										(63321 = 8)
										(63322 = 8)
										(63323 = 8)
										(63330 = 8)
										(63340 = 8)
										(63351 = 8)
										(63352 = 8)
										(63390 = 8)
										(63411 = 13)
										(63412 = 13)
										(63413 = 13)
										(63414 = 13)
										(63415 = 13)
										(63420 = 13)
										(63430 = 13)
										(63440 = 13)
										(63450 = 17)
										(63460 = 13)
										(63470 = 13)
										(63490 = 13)
										(63510 = 8)
										(63520 = 8)
										(63530 = 8)
										(63540 = 8)
										(63590 = 8)
										(63900 = 8)
										(64110 = 8)
										(64120 = 8)
										(64130 = 8)
										(64210 = 10)
										(64221 = 10)
										(64222 = 10)
										(64223 = 10)
										(64311 = 10)
										(64312 = 10)
										(64313 = 10)
										(64314 = 10)
										(64319 = 10)
										(64321 = 10)
										(64322 = 10)
										(64323 = 7)
										(64324 = 10)
										(64325 = 10)
										(64329 = 10)
										(64410 = 10)
										(64420 = 10)
										(64430 = 10)
										(65110 = 11)
										(65121 = 11)
										(65122 = 11)
										(65123 = 11)
										(65191 = 11)
										(65192 = 11)
										(65199 = 11)
										(65910 = 11)
										(65921 = 11)
										(65922 = 11)
										(65923 = 11)
										(65929 = 11)
										(65930 = 11)
										(65940 = 11)
										(65950 = 11)
										(65991 = 11)
										(65999 = 13)
										(66010 = 11)
										(66020 = 11)
										(66030 = 11)
										(67111 = 11)
										(67112 = 11)
										(67113 = 11)
										(67121 = 11)
										(67122 = 11)
										(67123 = 11)
										(67131 = 11)
										(67132 = 11)
										(67133 = 11)
										(67134 = 11)
										(67191 = 11)
										(67199 = 11)
										(67201 = 11)
										(67202 = 11)
										(67203 = 11)
										(67204 = 11)
										(67209 = 11)
										(70101 = 12)
										(70102 = 9)
										(70200 = 12)
										(70310 = 12)
										(70320 = 17)
										(71110 = 13)
										(71120 = 13)
										(71130 = 13)
										(71210 = 13)
										(71220 = 13)
										(71230 = 13)
										(71290 = 13)
										(71301 = 13)
										(71302 = 13)
										(71303 = 13)
										(71304 = 13)
										(71305 = 13)
										(71306 = 13)
										(71309 = 13)
										(72100 = 10)
										(72200 = 10)
										(72300 = 10)
										(72400 = 10)
										(72500 = 3)
										(72900 = 10)
										(73110 = 13)
										(73120 = 13)
										(73210 = 13)
										(73220 = 13)
										(74110 = 13)
										(74120 = 13)
										(74130 = 13)
										(74140 = 13)
										(74210 = 13)
										(74220 = 13)
										(74300 = 13)
										(74910 = 13)
										(74920 = 13)
										(74930 = 13)
										(74940 = 13)
										(74950 = 13)
										(74990 = 13)
										(75111 = 14)
										(75112 = 14)
										(75113 = 14)
										(75114 = 14)
										(75115 = 14)
										(75121 = 14)
										(75122 = 14)
										(75123 = 14)
										(75124 = 14)
										(75125 = 14)
										(75126 = 14)
										(75127 = 14)
										(75129 = 14)
										(75131 = 14)
										(75132 = 14)
										(75133 = 14)
										(75134 = 14)
										(75135 = 14)
										(75136 = 14)
										(75137 = 14)
										(75138 = 14)
										(75139 = 14)
										(75140 = 14)
										(75210 = 14)
										(75221 = 14)
										(75222 = 14)
										(75223 = 14)
										(75224 = 14)
										(75231 = 14)
										(75232 = 14)
										(75233 = 14)
										(75300 = 14)
										(80111 = 15)
										(80112 = 15)
										(80113 = 15)
										(80121 = 15)
										(80122 = 15)
										(80123 = 15)
										(80211 = 15)
										(80212 = 15)
										(80221 = 15)
										(80222 = 15)
										(80311 = 15)
										(80312 = 15)
										(80321 = 15)
										(80322 = 15)
										(80910 = 15)
										(80921 = 15)
										(80922 = 15)
										(80923 = 15)
										(80929 = 15)
										(85111 = 16)
										(85112 = 16)
										(85113 = 16)
										(85114 = 16)
										(85119 = 16)
										(85121 = 16)
										(85122 = 16)
										(85123 = 16)
										(85191 = 16)
										(85192 = 16)
										(85193 = 16)
										(85200 = 13)
										(85311 = 16)
										(85312 = 16)
										(85313 = 16)
										(85314 = 16)
										(85319 = 16)
										(85321 = 16)
										(85322 = 16)
										(90001 = 5)
										(90002 = 5)
										(91110 = 17)
										(91121 = 17)
										(91122 = 17)
										(91200 = 17)
										(91910 = 17)
										(91920 = 17)
										(91990 = 17)
										(92111 = 10)
										(92112 = 10)
										(92120 = 10)
										(92131 = 10)
										(92132 = 10)
										(92141 = 17)
										(92142 = 17)
										(92143 = 13)
										(92190 = 17)
										(92201 = 10)
										(92202 = 10)
										(92203 = 17)
										(92311 = 17)
										(92312 = 17)
										(92321 = 17)
										(92322 = 17)
										(92323 = 17)
										(92324 = 17)
										(92331 = 17)
										(92332 = 17)
										(92333 = 17)
										(92334 = 17)
										(92335 = 17)
										(92336 = 17)
										(92339 = 17)
										(92411 = 17)
										(92412 = 17)
										(92413 = 17)
										(92414 = 17)
										(92415 = 17)
										(92416 = 17)
										(92417 = 17)
										(92418 = 17)
										(92419 = 17)
										(92421 = 17)
										(92422 = 17)
										(92423 = 17)
										(92424 = 17)
										(92425 = 9)
										(92426 = 17)
										(92427 = 17)
										(92428 = 17)
										(92429 = 17)
										(92431 = 17)
										(92432 = 17)
										(92433 = 17)
										(92434 = 17)
										(92439 = 17)
										(93010 = 17)
										(93021 = 17)
										(93022 = 17)
										(93030 = 17)
										(93040 = 7)
										(93050 = 7)
										(93061 = 17)
										(93062 = 17)
										(93069 = 17)
										(93091 = 3)
										(93092 = 13)
										(93093 = 17)
										(93094 = 17)
										(95000 = 17)
										(99000 = 17)
										(99999 = 17)
										(1300 = 1)
										(15211 = 3)
										(15212 = 3)
										(26329 = 3)
										(50401 = 7)
										(50402 = 7)
										(50500 = 7)
										(52216 = 7)
										(52602 = 7)
										(92148 = 7)
										(51339 = 7)
										(60112 = 8)
										(60131 = 8)
										(63120 = 8), gen(sector17)
									;
									#d cr
									
gen work_informal = inlist(b5p10a, 1, 2, 5, 6, 7)
gen work_status   = b5p10a
gen work_certif   = b5p1d == 1
    replace work_certif = . if lf == 0
gen work_whitecoll = inrange(b5p8, 1, 5999)

gen act_school    = ((b5p2a2 == 1 | b5p2a2 == 2) & b5p2b == 2 & lf == 0)
gen act_household = (b5p2a3 == 1 | b5p2a3 == 2)  & b5p2b == 3 & lf == 0
gen act_others    = (b5p2a4 == 1 | b5p2a4 == 2)  & b5p2b == 4 & lf == 0
gen act_neet = 0
replace act_neet = 1 if b5p2a1 == 2 & b5p2a2 == 2
replace act_neet = 0 if act_school == 1
replace act_neet = . if age >= 25 | age <= 14

*-----------------------------------------------------------
* Adjust Employment for Consistency
*-----------------------------------------------------------
replace employment = 1 if employment == 0 & work_status != .

*-----------------------------------------------------------
* Create Work Outcome Variables
*-----------------------------------------------------------
gen work_hours    = b5p9
gen work_earnings = b5p12a + b5p12b
gen work_wage     = (b5p12a + b5p12b) if b5p10a == 4
gen work_jobdur   = .
    replace b5p21a = . if b5p21a == 99
    replace b5p21b = . if b5p21b == 99
    replace work_jobdur = (b5p21a * 12) + b5p21b
    replace work_jobdur = . if work_jobdur > 98

*-----------------------------------------------------------
* Recodes and Derived Variables
*-----------------------------------------------------------
recode educ 1/3 = 1 4/7 = 2 8/11 = 3, generate(educ_group)
recode work_jobdur 0/3 = 1 4/12 = 2 12/24 = 3 25/9999 = 4, gen(work_jobdur_cat)

gen school_years = .
replace school_years = 0 if educ == 1 | educ == 2
replace school_years = 6 if educ == 3
replace school_years = 9 if educ == 4
replace school_years = 9 if educ == 5
replace school_years = 12 if educ == 6
replace school_years = 12 if educ == 7
replace school_years = 14 if educ == 8
replace school_years = 15 if educ == 9
replace school_years = 16 if educ == 10
replace school_years = 20 if educ == 11

*-----------------------------------------------------------
* Job Search Duration Dummies
*-----------------------------------------------------------
la de searchdur 1 "1. <=3 bulan" 2 "2. 4-12 bulan" 3 "3. 13-24 bulan" 4 "4. >24 bulan"
la val work_jobdur_cat searchdur

forval x = 1/4 {
    gen work_searchdur_`x' = (work_jobdur_cat == `x')
    replace work_searchdur_`x' = . if lf == 0 | work_jobdur_cat == .
}

foreach var of varlist work_hours work_earnings work_wage {
    replace `var' = . if unemp == 1 | lf == 0
}

*-----------------------------------------------------------
* Finalize and Save 2008 Data
*-----------------------------------------------------------
gen year = `year'
// save "$output/temp_sakernas_`year'", replace

keep prov`year' wt urban male age educ unemp employment lf school_years sector9 sector17 ///
     work_informal work_status act_neet act_school act_household act_others work_hours ///
     work_whitecoll work_earnings work_wage work_jobdur* educ_group work_searchdur_* year work_certif
	 

**---------------------------------------------------------------------------
** Working Hours, Underemployment, Status, and Formality Indicators (2008)
** Raw inputs: hours=b5p6b  status=b5p10a  occupation=kji82_1dgt  involuntary=(b5p4, b5p24)
**---------------------------------------------------------------------------

* hour: total working hours of all jobs (week)
cap confirm variable b5p6b
if !_rc {
    cap drop hour
    gen hour = b5p6b if employment == 1
}
else {
    cap gen hour = .
}

* underemp: hour<35 & employed
cap drop underemp
gen underemp = 1 if hour < 35 & hour > 0
replace underemp = 0 if hour == 0
replace underemp = 0 if hour >= 35 & hour != .

* underemp_invol & underemp_vol (legacy formula)
cap drop underemp_invol underemp_vol
gen underemp_invol = .
cap confirm variable b5p4
local has_i1 = !_rc
cap confirm variable b5p24
local has_i2 = !_rc
if `has_i1' & `has_i2' {
    replace underemp_invol = 0 if underemp == 1
    replace underemp_invol = 1 if (b5p4 == 1 | b5p24 == 1) & underemp == 1
}
gen underemp_vol = .
replace underemp_vol = 1 if underemp == 1 & underemp_invol == 0
replace underemp_vol = 0 if underemp == 1 & underemp_invol == 1

* hour decomposed
cap drop hour_under hour_vol hour_invol
gen hour_under = hour if underemp == 1
gen hour_vol   = hour if underemp_vol == 1
gen hour_invol = hour if underemp_invol == 1

* status (employment status, 1-7)
cap drop status
cap confirm variable b5p10a
if !_rc {
    gen status = b5p10a if employment == 1
    replace status = . if status == 0
}
else {
    gen status = .
}

* worktype (1-digit code; take first digit if multi-digit)
cap drop worktype
cap confirm variable kji82_1dgt
if !_rc {
    gen _wt_raw = kji82_1dgt if employment == 1
    gen worktype = .
    replace worktype = real(substr(string(int(abs(_wt_raw))), 1, 1)) if _wt_raw != . & _wt_raw > 0
    replace worktype = _wt_raw if abs(_wt_raw) < 10 & _wt_raw != .
    drop _wt_raw
}
else {
    gen worktype = .
}

* formal_simple: status in (3,4)
cap drop formal_simple
gen formal_simple = inrange(status, 3, 4) if status != . & employment == 1

* formal_new: wrktype2011 matrix
cap drop formal_new
gen formal_new = .
replace formal_new = wrktype2011[status, worktype] ///
    if status != . & worktype != . & employment == 1 ///
    & inrange(status, 1, 7) & inrange(worktype, 1, 8)

* formal_old: formal_new + casual workers in agri/construction
cap drop formal_old
gen formal_old = formal_new
replace formal_old = 1 if (status == 5 & sector9 == 1) & employment == 1
replace formal_old = 1 if (status == 6 & sector9 == 5) & employment == 1

* labels
cap label var hour           "working hours per week (all jobs combined)"
cap label var underemp       "underemployed dummy (less than 35 hours per week)"
cap label var underemp_invol "involuntary underemployment"
cap label var underemp_vol   "voluntary underemployment"
cap label var hour_under     "weekly hours among underemployed"
cap label var hour_vol       "weekly hours among voluntary underemployed"
cap label var hour_invol     "weekly hours among involuntary underemployed"
cap label var status         "main employment status"
cap label var worktype       "main occupation (1-digit KBJI)"
cap label var formal_simple  "simplified formality (employee or assisted employer)"
cap label var formal_new     "formality (wrktype2011 matrix)"
cap label var formal_old     "formality including casual workers in agriculture and construction"
**---------------------------------------------------------------------------
** Additional Employment Indicators
**---------------------------------------------------------------------------
cap drop employee casual_worker potential_exp
gen employee = work_status == 4 if work_status != .
gen casual_worker = inlist(work_status, 5, 6) if work_status != .
gen potential_exp = age - school_years if age != . & school_years != .
cap label var employee      "employee dummy"
cap label var casual_worker "casual worker dummy"
cap label var potential_exp "potential work experience"


save $clean/clean_sakernas_`year', replace
/*************************
 * End of Sakernas 2008
 ************************/

/*************************
 * Sakernas 2009
 ************************/

clear
set more off
local year = 2009
use $source/sakernas_`year', clear

*-----------------------------------------------------------
* Generate Basic Variables
*-----------------------------------------------------------
gen prov`year' = b1p01
gen wt         = weight
gen urban      = (b1p05 == 1)
gen male       = (jk == 1)
gen age        = umur         // WARNING: AGE OUTSIDE LF DETECTED
gen educ       = b5p1a

*-----------------------------------------------------------
* Employment and Unemployment Status
*-----------------------------------------------------------
gen unemp = .
replace unemp = 1 if b5p2a1 == 2 & b5p3 == 2 & b5p4 == 1
replace unemp = 1 if b5p2a1 == 2 & b5p3 == 2 & b5p5 == 1
replace unemp = 1 if b5p2a1 == 2 & inlist(b5p22, 1, 2)
replace unemp = 0 if unemp != 1

gen employment = .
replace employment = 1 if b5p2a1 == 1
replace employment = 1 if b5p3 == 1
replace employment = 0 if unemp == 1

*-----------------------------------------------------------
* Define Labor Force (LF)
*-----------------------------------------------------------
gen lf = .
replace lf = 1 if employment == 1 | unemp == 1
replace lf = 0 if age < 15
replace lf = 0 if lf != 1
replace unemp = . if lf == 0
replace employment = . if lf == 0

*-----------------------------------------------------------
* Sector and Work Variables
*-----------------------------------------------------------
gen sector9 = klui

#d;
									recode b5p7
										(0 = 18)
										(111 = 1)
										(504 = 1)
										(527 = 7)
										(1111 = 1)
										(1112 = 1)
										(1113 = 1)
										(1114 = 1)
										(1115 = 1)
										(1116 = 1)
										(1117 = 1)
										(1118 = 1)
										(1119 = 1)
										(1121 = 1)
										(1122 = 1)
										(1123 = 1)
										(1124 = 1)
										(1125 = 1)
										(1131 = 1)
										(1132 = 1)
										(1133 = 1)
										(1134 = 1)
										(1135 = 1)
										(1136 = 1)
										(1137 = 1)
										(1138 = 1)
										(1139 = 1)
										(1211 = 1)
										(1212 = 1)
										(1213 = 1)
										(1214 = 1)
										(1215 = 1)
										(1216 = 1)
										(1217 = 1)
										(1218 = 1)
										(1221 = 1)
										(1222 = 1)
										(1223 = 1)
										(1224 = 1)
										(1225 = 1)
										(1226 = 1)
										(1227 = 1)
										(1228 = 1)
										(1229 = 1)
										(1401 = 1)
										(1402 = 1)
										(1403 = 1)
										(1404 = 1)
										(1405 = 1)
										(1406 = 1)
										(1407 = 1)
										(1408 = 1)
										(1410 = 2)
										(1501 = 1)
										(1502 = 1)
										(2011 = 1)
										(2012 = 1)
										(2013 = 1)
										(2014 = 1)
										(2015 = 1)
										(2016 = 1)
										(2017 = 1)
										(2018 = 1)
										(2019 = 1)
										(2020 = 1)
										(2031 = 1)
										(2032 = 1)
										(2033 = 1)
										(2034 = 1)
										(2035 = 1)
										(2039 = 1)
										(2041 = 1)
										(2042 = 1)
										(2043 = 1)
										(2049 = 1)
										(2051 = 1)
										(2052 = 1)
										(2059 = 1)
										(5011 = 1)
										(5012 = 1)
										(5013 = 1)
										(5014 = 1)
										(5015 = 1)
										(5021 = 1)
										(5022 = 1)
										(5031 = 1)
										(5032 = 1)
										(5041 = 1)
										(5042 = 1)
										(5043 = 1)
										(5044 = 1)
										(5051 = 1)
										(5052 = 1)
										(5053 = 1)
										(5054 = 1)
										(5055 = 1)
										(5056 = 1)
										(5521 = 9)
										(6021 = 8)
										(6711 = 11)
										(6712 = 11)
										(7523 = 14)
										(8011 = 15)
										(10101 = 2)
										(10102 = 2)
										(10200 = 3)
										(11101 = 2)
										(11102 = 2)
										(11200 = 2)
										(12000 = 2)
										(13101 = 2)
										(13102 = 2)
										(13201 = 2)
										(13202 = 2)
										(13203 = 2)
										(13204 = 2)
										(13205 = 2)
										(13206 = 2)
										(13207 = 2)
										(13209 = 2)
										(14101 = 2)
										(14102 = 2)
										(14103 = 2)
										(14104 = 2)
										(14105 = 2)
										(14106 = 2)
										(14211 = 2)
										(14212 = 2)
										(14213 = 2)
										(14214 = 2)
										(14215 = 2)
										(14219 = 2)
										(14220 = 2)
										(14291 = 2)
										(14292 = 2)
										(14299 = 2)
										(15111 = 3)
										(15112 = 3)
										(15121 = 3)
										(15122 = 3)
										(15123 = 3)
										(15124 = 3)
										(15125 = 3)
										(15129 = 3)
										(15131 = 3)
										(15132 = 3)
										(15133 = 3)
										(15134 = 3)
										(15139 = 3)
										(15141 = 3)
										(15142 = 3)
										(15143 = 3)
										(15144 = 3)
										(15145 = 3)
										(15149 = 3)
										(15201 = 3)
										(15202 = 3)
										(15203 = 3)
										(15311 = 3)
										(15312 = 3)
										(15313 = 3)
										(15314 = 3)
										(15315 = 3)
										(15316 = 3)
										(15317 = 3)
										(15318 = 3)
										(15321 = 3)
										(15322 = 3)
										(15323 = 3)
										(15324 = 3)
										(15329 = 3)
										(15331 = 3)
										(15332 = 3)
										(15410 = 3)
										(15421 = 3)
										(15422 = 3)
										(15423 = 3)
										(15424 = 3)
										(15429 = 3)
										(15431 = 3)
										(15432 = 3)
										(15440 = 3)
										(15491 = 3)
										(15492 = 3)
										(15493 = 3)
										(15494 = 3)
										(15495 = 3)
										(15496 = 3)
										(15497 = 3)
										(15498 = 3)
										(15499 = 3)
										(15510 = 3)
										(15520 = 3)
										(15530 = 3)
										(15541 = 3)
										(15542 = 3)
										(16001 = 3)
										(16002 = 3)
										(16003 = 3)
										(16004 = 3)
										(16009 = 3)
										(17111 = 3)
										(17112 = 3)
										(17113 = 3)
										(17114 = 3)
										(17115 = 3)
										(17121 = 3)
										(17122 = 3)
										(17123 = 3)
										(17124 = 3)
										(17211 = 3)
										(17212 = 3)
										(17213 = 3)
										(17214 = 3)
										(17215 = 3)
										(17220 = 3)
										(17231 = 3)
										(17232 = 3)
										(17291 = 3)
										(17292 = 3)
										(17293 = 3)
										(17294 = 3)
										(17295 = 3)
										(17299 = 3)
										(17301 = 3)
										(17302 = 3)
										(17303 = 3)
										(17304 = 3)
										(17400 = 3)
										(18101 = 3)
										(18102 = 3)
										(18201 = 3)
										(18202 = 3)
										(18203 = 3)
										(19111 = 3)
										(19112 = 3)
										(19113 = 3)
										(19121 = 3)
										(19122 = 3)
										(19123 = 3)
										(19129 = 3)
										(19201 = 3)
										(19202 = 3)
										(19203 = 3)
										(19209 = 3)
										(20101 = 3)
										(20102 = 3)
										(20103 = 3)
										(20104 = 3)
										(20211 = 3)
										(20212 = 3)
										(20213 = 3)
										(20214 = 3)
										(20220 = 3)
										(20230 = 3)
										(20291 = 3)
										(20292 = 3)
										(20293 = 3)
										(20294 = 3)
										(20299 = 3)
										(21011 = 3)
										(21012 = 3)
										(21013 = 3)
										(21014 = 3)
										(21015 = 3)
										(21016 = 3)
										(21019 = 3)
										(21020 = 3)
										(21090 = 3)
										(22110 = 10)
										(22120 = 10)
										(22130 = 10)
										(22140 = 3)
										(22190 = 10)
										(22210 = 3)
										(22220 = 3)
										(22301 = 3)
										(22302 = 3)
										(23100 = 3)
										(23201 = 3)
										(23202 = 4)
										(23203 = 3)
										(23204 = 3)
										(23205 = 3)
										(23300 = 3)
										(24111 = 3)
										(24112 = 3)
										(24113 = 3)
										(24114 = 3)
										(24115 = 3)
										(24116 = 3)
										(24117 = 3)
										(24118 = 3)
										(24119 = 3)
										(24121 = 5)
										(24122 = 3)
										(24123 = 3)
										(24124 = 3)
										(24125 = 3)
										(24126 = 3)
										(24127 = 3)
										(24129 = 3)
										(24131 = 3)
										(24132 = 3)
										(24211 = 3)
										(24212 = 3)
										(24213 = 3)
										(24214 = 3)
										(24221 = 3)
										(24222 = 3)
										(24223 = 3)
										(24231 = 3)
										(24232 = 3)
										(24233 = 3)
										(24234 = 3)
										(24235 = 3)
										(24241 = 3)
										(24242 = 3)
										(24291 = 3)
										(24292 = 3)
										(24293 = 3)
										(24294 = 3)
										(24295 = 3)
										(24299 = 3)
										(24301 = 3)
										(24302 = 3)
										(25111 = 3)
										(25112 = 3)
										(25121 = 3)
										(25122 = 3)
										(25123 = 3)
										(25191 = 3)
										(25192 = 3)
										(25199 = 3)
										(25201 = 3)
										(25202 = 3)
										(25203 = 3)
										(25204 = 3)
										(25205 = 3)
										(25206 = 3)
										(25209 = 3)
										(26111 = 3)
										(26112 = 3)
										(26119 = 3)
										(26121 = 3)
										(26122 = 3)
										(26123 = 3)
										(26124 = 3)
										(26129 = 3)
										(26201 = 3)
										(26202 = 3)
										(26203 = 3)
										(26209 = 3)
										(26311 = 3)
										(26319 = 3)
										(26321 = 3)
										(26322 = 3)
										(26323 = 3)
										(26324 = 3)
										(26411 = 3)
										(26412 = 3)
										(26413 = 3)
										(26421 = 3)
										(26422 = 3)
										(26423 = 3)
										(26429 = 3)
										(26501 = 3)
										(26502 = 3)
										(26503 = 3)
										(26509 = 3)
										(26601 = 3)
										(26602 = 3)
										(26609 = 3)
										(26900 = 3)
										(27101 = 3)
										(27102 = 3)
										(27103 = 3)
										(27201 = 3)
										(27202 = 3)
										(27203 = 3)
										(27204 = 3)
										(27310 = 3)
										(27320 = 3)
										(28111 = 3)
										(28112 = 3)
										(28113 = 3)
										(28119 = 3)
										(28120 = 3)
										(28910 = 3)
										(28920 = 3)
										(28931 = 3)
										(28932 = 3)
										(28933 = 3)
										(28939 = 3)
										(28991 = 3)
										(28992 = 3)
										(28993 = 3)
										(28994 = 3)
										(28995 = 3)
										(28996 = 3)
										(28997 = 3)
										(28998 = 3)
										(28999 = 3)
										(29111 = 3)
										(29112 = 3)
										(29113 = 3)
										(29114 = 3)
										(29120 = 3)
										(29130 = 3)
										(29141 = 3)
										(29142 = 3)
										(29150 = 3)
										(29191 = 3)
										(29192 = 3)
										(29193 = 3)
										(29199 = 3)
										(29211 = 3)
										(29212 = 3)
										(29221 = 3)
										(29222 = 3)
										(29223 = 3)
										(29224 = 3)
										(29230 = 3)
										(29240 = 3)
										(29250 = 3)
										(29261 = 3)
										(29262 = 3)
										(29263 = 3)
										(29264 = 3)
										(29270 = 3)
										(29291 = 3)
										(29292 = 3)
										(29299 = 3)
										(29301 = 3)
										(29302 = 3)
										(29309 = 3)
										(30001 = 3)
										(30002 = 3)
										(30003 = 3)
										(30004 = 3)
										(31101 = 3)
										(31102 = 3)
										(31103 = 3)
										(31201 = 3)
										(31202 = 3)
										(31300 = 3)
										(31401 = 3)
										(31402 = 3)
										(31501 = 3)
										(31502 = 3)
										(31509 = 3)
										(31900 = 3)
										(32100 = 3)
										(32200 = 3)
										(32300 = 3)
										(33111 = 3)
										(33112 = 3)
										(33113 = 3)
										(33119 = 3)
										(33121 = 3)
										(33122 = 3)
										(33123 = 3)
										(33130 = 3)
										(33201 = 3)
										(33202 = 3)
										(33203 = 3)
										(33204 = 3)
										(33300 = 3)
										(34100 = 3)
										(34200 = 3)
										(34300 = 3)
										(35111 = 3)
										(35112 = 3)
										(35113 = 3)
										(35114 = 5)
										(35115 = 3)
										(35120 = 3)
										(35201 = 3)
										(35202 = 3)
										(35301 = 3)
										(35302 = 3)
										(35911 = 3)
										(35912 = 3)
										(35921 = 3)
										(35922 = 3)
										(35990 = 3)
										(36101 = 3)
										(36102 = 3)
										(36103 = 3)
										(36104 = 3)
										(36109 = 3)
										(36911 = 3)
										(36912 = 3)
										(36913 = 3)
										(36914 = 3)
										(36915 = 3)
										(36921 = 3)
										(36922 = 3)
										(36930 = 3)
										(36941 = 3)
										(36942 = 3)
										(36991 = 3)
										(36992 = 3)
										(36993 = 3)
										(36999 = 3)
										(37100 = 5)
										(37200 = 5)
										(40101 = 4)
										(40102 = 4)
										(40103 = 4)
										(40104 = 4)
										(40201 = 4)
										(40202 = 4)
										(40300 = 4)
										(41001 = 5)
										(41002 = 5)
										(41003 = 5)
										(45100 = 6)
										(45211 = 6)
										(45212 = 6)
										(45213 = 6)
										(45214 = 6)
										(45215 = 6)
										(45216 = 6)
										(45217 = 6)
										(45218 = 6)
										(45219 = 6)
										(45221 = 6)
										(45222 = 6)
										(45223 = 6)
										(45224 = 6)
										(45225 = 6)
										(45226 = 6)
										(45227 = 6)
										(45229 = 6)
										(45231 = 6)
										(45232 = 6)
										(45233 = 6)
										(45234 = 6)
										(45235 = 6)
										(45239 = 6)
										(45241 = 6)
										(45242 = 6)
										(45243 = 6)
										(45244 = 6)
										(45245 = 6)
										(45246 = 6)
										(45249 = 6)
										(45311 = 6)
										(45312 = 6)
										(45313 = 6)
										(45314 = 6)
										(45315 = 6)
										(45316 = 6)
										(45317 = 6)
										(45319 = 6)
										(45321 = 6)
										(45322 = 6)
										(45323 = 6)
										(45324 = 6)
										(45325 = 6)
										(45326 = 6)
										(45327 = 6)
										(45328 = 6)
										(45329 = 6)
										(45401 = 6)
										(45402 = 6)
										(45403 = 6)
										(45404 = 6)
										(45405 = 6)
										(45409 = 6)
										(45500 = 6)
										(50101 = 7)
										(50102 = 7)
										(50201 = 7)
										(50202 = 7)
										(50301 = 7)
										(50302 = 7)
										(50400 = 7)
										(51100 = 7)
										(51211 = 7)
										(51212 = 7)
										(51213 = 7)
										(51214 = 7)
										(51220 = 7)
										(51310 = 7)
										(51391 = 7)
										(51392 = 7)
										(51399 = 7)
										(51410 = 7)
										(51420 = 7)
										(51431 = 7)
										(51432 = 7)
										(51433 = 7)
										(51434 = 7)
										(51435 = 7)
										(51436 = 7)
										(51437 = 7)
										(51438 = 7)
										(51439 = 7)
										(51490 = 7)
										(51501 = 7)
										(51502 = 7)
										(51503 = 7)
										(51504 = 7)
										(51900 = 7)
										(52111 = 7)
										(52112 = 7)
										(52191 = 7)
										(52192 = 7)
										(52211 = 7)
										(52212 = 7)
										(52213 = 7)
										(52214 = 7)
										(52215 = 7)
										(52219 = 7)
										(52221 = 7)
										(52222 = 7)
										(52223 = 7)
										(52224 = 7)
										(52225 = 7)
										(52226 = 7)
										(52227 = 7)
										(52228 = 7)
										(52229 = 7)
										(52311 = 7)
										(52312 = 7)
										(52313 = 7)
										(52314 = 7)
										(52315 = 7)
										(52316 = 7)
										(52317 = 7)
										(52318 = 7)
										(52319 = 7)
										(52321 = 7)
										(52322 = 7)
										(52323 = 7)
										(52324 = 7)
										(52325 = 7)
										(52326 = 7)
										(52327 = 7)
										(52328 = 7)
										(52329 = 7)
										(52331 = 7)
										(52332 = 7)
										(52333 = 7)
										(52334 = 7)
										(52335 = 7)
										(52336 = 7)
										(52337 = 7)
										(52338 = 7)
										(52339 = 7)
										(52341 = 7)
										(52342 = 7)
										(52343 = 7)
										(52344 = 7)
										(52345 = 7)
										(52346 = 7)
										(52347 = 7)
										(52348 = 7)
										(52349 = 7)
										(52351 = 7)
										(52352 = 7)
										(52353 = 7)
										(52354 = 7)
										(52359 = 7)
										(52361 = 7)
										(52362 = 7)
										(52363 = 7)
										(52364 = 7)
										(52365 = 7)
										(52366 = 7)
										(52367 = 7)
										(52368 = 7)
										(52371 = 7)
										(52372 = 7)
										(52373 = 7)
										(52374 = 7)
										(52375 = 7)
										(52381 = 7)
										(52382 = 7)
										(52383 = 7)
										(52384 = 7)
										(52385 = 7)
										(52386 = 7)
										(52389 = 7)
										(52391 = 7)
										(52392 = 7)
										(52393 = 7)
										(52394 = 7)
										(52395 = 7)
										(52399 = 7)
										(52401 = 7)
										(52402 = 7)
										(52403 = 7)
										(52404 = 7)
										(52405 = 7)
										(52406 = 7)
										(52409 = 7)
										(52511 = 7)
										(52512 = 7)
										(52513 = 7)
										(52514 = 7)
										(52515 = 7)
										(52516 = 7)
										(52521 = 7)
										(52522 = 7)
										(52523 = 7)
										(52524 = 7)
										(52525 = 7)
										(52526 = 7)
										(52527 = 7)
										(52528 = 7)
										(52529 = 7)
										(52531 = 7)
										(52532 = 7)
										(52533 = 7)
										(52534 = 7)
										(52535 = 7)
										(52536 = 7)
										(52539 = 7)
										(52541 = 7)
										(52542 = 7)
										(52543 = 7)
										(52544 = 7)
										(52545 = 7)
										(52546 = 7)
										(52547 = 7)
										(52548 = 7)
										(52549 = 7)
										(52551 = 7)
										(52552 = 7)
										(52553 = 7)
										(52554 = 7)
										(52555 = 7)
										(52556 = 7)
										(52557 = 7)
										(52559 = 7)
										(52561 = 7)
										(52569 = 7)
										(52571 = 7)
										(52572 = 7)
										(52573 = 7)
										(52574 = 7)
										(52575 = 7)
										(52576 = 7)
										(52577 = 7)
										(52581 = 7)
										(52582 = 7)
										(52583 = 7)
										(52591 = 7)
										(52592 = 7)
										(52593 = 7)
										(52594 = 7)
										(52595 = 7)
										(52600 = 7)
										(52711 = 7)
										(52712 = 7)
										(52713 = 7)
										(52714 = 7)
										(52719 = 7)
										(52721 = 7)
										(52722 = 7)
										(52723 = 7)
										(52724 = 7)
										(52725 = 7)
										(52726 = 7)
										(52727 = 7)
										(52728 = 7)
										(52729 = 7)
										(53100 = 7)
										(53211 = 7)
										(53212 = 7)
										(53213 = 7)
										(53214 = 7)
										(53220 = 7)
										(53310 = 7)
										(53391 = 7)
										(53392 = 7)
										(53399 = 7)
										(53410 = 7)
										(53420 = 7)
										(53430 = 7)
										(53491 = 7)
										(53492 = 7)
										(53500 = 7)
										(53900 = 7)
										(54100 = 7)
										(54211 = 7)
										(54212 = 7)
										(54213 = 7)
										(54214 = 7)
										(54220 = 7)
										(54310 = 7)
										(54391 = 7)
										(54392 = 7)
										(54399 = 7)
										(54410 = 7)
										(54420 = 7)
										(54430 = 7)
										(54491 = 7)
										(54492 = 7)
										(54500 = 7)
										(54900 = 7)
										(55111 = 9)
										(55112 = 9)
										(55113 = 9)
										(55114 = 9)
										(55115 = 9)
										(55120 = 9)
										(55130 = 9)
										(55140 = 9)
										(55150 = 9)
										(55160 = 9)
										(55190 = 9)
										(55211 = 9)
										(55212 = 9)
										(55213 = 9)
										(55214 = 9)
										(55220 = 9)
										(55230 = 9)
										(55240 = 9)
										(55250 = 9)
										(55260 = 9)
										(60110 = 8)
										(60120 = 8)
										(60139 = 8)
										(60211 = 8)
										(60212 = 8)
										(60213 = 8)
										(60214 = 8)
										(60215 = 8)
										(60216 = 8)
										(60217 = 8)
										(60221 = 8)
										(60222 = 8)
										(60223 = 8)
										(60224 = 8)
										(60225 = 8)
										(60231 = 8)
										(60232 = 8)
										(60233 = 8)
										(60300 = 8)
										(61111 = 8)
										(61112 = 8)
										(61113 = 8)
										(61114 = 8)
										(61115 = 8)
										(61116 = 8)
										(61117 = 8)
										(61118 = 8)
										(61121 = 8)
										(61122 = 8)
										(61123 = 8)
										(61124 = 8)
										(61125 = 8)
										(61126 = 8)
										(61127 = 8)
										(61211 = 8)
										(61212 = 8)
										(61213 = 8)
										(61214 = 8)
										(61215 = 8)
										(61216 = 8)
										(61221 = 8)
										(61222 = 8)
										(61223 = 8)
										(61224 = 8)
										(61225 = 8)
										(61226 = 8)
										(62111 = 8)
										(62112 = 8)
										(62120 = 8)
										(62201 = 8)
										(62202 = 8)
										(62311 = 1)
										(62312 = 13)
										(62313 = 8)
										(62314 = 16)
										(62320 = 15)
										(62390 = 8)
										(63100 = 8)
										(63210 = 8)
										(63220 = 8)
										(63230 = 8)
										(63290 = 8)
										(63310 = 8)
										(63321 = 8)
										(63322 = 8)
										(63323 = 8)
										(63330 = 8)
										(63340 = 8)
										(63351 = 8)
										(63352 = 8)
										(63390 = 8)
										(63411 = 13)
										(63412 = 13)
										(63413 = 13)
										(63414 = 13)
										(63415 = 13)
										(63420 = 13)
										(63430 = 13)
										(63440 = 13)
										(63450 = 17)
										(63460 = 13)
										(63470 = 13)
										(63490 = 13)
										(63510 = 8)
										(63520 = 8)
										(63530 = 8)
										(63540 = 8)
										(63590 = 8)
										(63900 = 8)
										(64110 = 8)
										(64120 = 8)
										(64130 = 8)
										(64210 = 10)
										(64221 = 10)
										(64222 = 10)
										(64223 = 10)
										(64311 = 10)
										(64312 = 10)
										(64313 = 10)
										(64314 = 10)
										(64319 = 10)
										(64321 = 10)
										(64322 = 10)
										(64323 = 7)
										(64324 = 10)
										(64325 = 10)
										(64329 = 10)
										(64410 = 10)
										(64420 = 10)
										(64430 = 10)
										(65110 = 11)
										(65121 = 11)
										(65122 = 11)
										(65123 = 11)
										(65191 = 11)
										(65192 = 11)
										(65199 = 11)
										(65910 = 11)
										(65921 = 11)
										(65922 = 11)
										(65923 = 11)
										(65929 = 11)
										(65930 = 11)
										(65940 = 11)
										(65950 = 11)
										(65991 = 11)
										(65999 = 13)
										(66010 = 11)
										(66020 = 11)
										(66030 = 11)
										(67111 = 11)
										(67112 = 11)
										(67113 = 11)
										(67121 = 11)
										(67122 = 11)
										(67123 = 11)
										(67131 = 11)
										(67132 = 11)
										(67133 = 11)
										(67134 = 11)
										(67191 = 11)
										(67199 = 11)
										(67201 = 11)
										(67202 = 11)
										(67203 = 11)
										(67204 = 11)
										(67209 = 11)
										(70101 = 12)
										(70102 = 9)
										(70200 = 12)
										(70310 = 12)
										(70320 = 17)
										(71110 = 13)
										(71120 = 13)
										(71130 = 13)
										(71210 = 13)
										(71220 = 13)
										(71230 = 13)
										(71290 = 13)
										(71301 = 13)
										(71302 = 13)
										(71303 = 13)
										(71304 = 13)
										(71305 = 13)
										(71306 = 13)
										(71309 = 13)
										(72100 = 10)
										(72200 = 10)
										(72300 = 10)
										(72400 = 10)
										(72500 = 3)
										(72900 = 10)
										(73110 = 13)
										(73120 = 13)
										(73210 = 13)
										(73220 = 13)
										(74110 = 13)
										(74120 = 13)
										(74130 = 13)
										(74140 = 13)
										(74210 = 13)
										(74220 = 13)
										(74300 = 13)
										(74910 = 13)
										(74920 = 13)
										(74930 = 13)
										(74940 = 13)
										(74950 = 13)
										(74990 = 13)
										(75111 = 14)
										(75112 = 14)
										(75113 = 14)
										(75114 = 14)
										(75115 = 14)
										(75121 = 14)
										(75122 = 14)
										(75123 = 14)
										(75124 = 14)
										(75125 = 14)
										(75126 = 14)
										(75127 = 14)
										(75129 = 14)
										(75131 = 14)
										(75132 = 14)
										(75133 = 14)
										(75134 = 14)
										(75135 = 14)
										(75136 = 14)
										(75137 = 14)
										(75138 = 14)
										(75139 = 14)
										(75140 = 14)
										(75210 = 14)
										(75221 = 14)
										(75222 = 14)
										(75223 = 14)
										(75224 = 14)
										(75231 = 14)
										(75232 = 14)
										(75233 = 14)
										(75300 = 14)
										(80111 = 15)
										(80112 = 15)
										(80113 = 15)
										(80121 = 15)
										(80122 = 15)
										(80123 = 15)
										(80211 = 15)
										(80212 = 15)
										(80221 = 15)
										(80222 = 15)
										(80311 = 15)
										(80312 = 15)
										(80321 = 15)
										(80322 = 15)
										(80910 = 15)
										(80921 = 15)
										(80922 = 15)
										(80923 = 15)
										(80929 = 15)
										(85111 = 16)
										(85112 = 16)
										(85113 = 16)
										(85114 = 16)
										(85119 = 16)
										(85121 = 16)
										(85122 = 16)
										(85123 = 16)
										(85191 = 16)
										(85192 = 16)
										(85193 = 16)
										(85200 = 13)
										(85311 = 16)
										(85312 = 16)
										(85313 = 16)
										(85314 = 16)
										(85319 = 16)
										(85321 = 16)
										(85322 = 16)
										(90001 = 5)
										(90002 = 5)
										(91110 = 17)
										(91121 = 17)
										(91122 = 17)
										(91200 = 17)
										(91910 = 17)
										(91920 = 17)
										(91990 = 17)
										(92111 = 10)
										(92112 = 10)
										(92120 = 10)
										(92131 = 10)
										(92132 = 10)
										(92141 = 17)
										(92142 = 17)
										(92143 = 13)
										(92190 = 17)
										(92201 = 10)
										(92202 = 10)
										(92203 = 17)
										(92311 = 17)
										(92312 = 17)
										(92321 = 17)
										(92322 = 17)
										(92323 = 17)
										(92324 = 17)
										(92331 = 17)
										(92332 = 17)
										(92333 = 17)
										(92334 = 17)
										(92335 = 17)
										(92336 = 17)
										(92339 = 17)
										(92411 = 17)
										(92412 = 17)
										(92413 = 17)
										(92414 = 17)
										(92415 = 17)
										(92416 = 17)
										(92417 = 17)
										(92418 = 17)
										(92419 = 17)
										(92421 = 17)
										(92422 = 17)
										(92423 = 17)
										(92424 = 17)
										(92425 = 9)
										(92426 = 17)
										(92427 = 17)
										(92428 = 17)
										(92429 = 17)
										(92431 = 17)
										(92432 = 17)
										(92433 = 17)
										(92434 = 17)
										(92439 = 17)
										(93010 = 17)
										(93021 = 17)
										(93022 = 17)
										(93030 = 17)
										(93040 = 7)
										(93050 = 7)
										(93061 = 17)
										(93062 = 17)
										(93069 = 17)
										(93091 = 3)
										(93092 = 13)
										(93093 = 17)
										(93094 = 17)
										(95000 = 17)
										(99000 = 17)
										(99999 = 17)
										(1300 = 1)
										(15211 = 3)
										(15212 = 3)
										(26329 = 3)
										(50401 = 7)
										(50402 = 7)
										(50500 = 7)
										(52216 = 7)
										(52602 = 7)
										(92148 = 7)
										(51339 = 7)
										(60112 = 8)
										(60131 = 8)
										(63120 = 8), gen(sector17)
									;
									#d cr
									
								
gen work_informal = inlist(b5p10a, 1, 2, 5, 6, 7)
gen work_status   = b5p10a
gen work_certif   = b5p1d == 1
    replace work_certif = . if lf == 0
gen work_whitecoll = inrange(b5p8, 1, 5999)

gen act_school    = (b5p2a2 == 1 | b5p2a2 == 2) & b5p2b == 2 & lf == 0
gen act_household = (b5p2a3 == 1 | b5p2a3 == 2) & b5p2b == 3 & lf == 0
gen act_others    = (b5p2a4 == 1 | b5p2a4 == 2) & b5p2b == 4 & lf == 0
gen act_neet = 0
replace act_neet = 1 if b5p2a1 == 2 & b5p2a2 == 2
replace act_neet = 0 if act_school == 1
replace act_neet = . if age >= 25 | age <= 14

*-----------------------------------------------------------
* Adjust Employment for Consistency
*-----------------------------------------------------------
replace employment = 1 if employment == 0 & work_status != .

*-----------------------------------------------------------
* Create Work Outcome Variables
*-----------------------------------------------------------
gen work_hours    = b5p9
gen work_earnings = b5p12a + b5p12b
gen work_wage     = (b5p12a + b5p12b) if b5p10a == 4
gen work_jobdur   = (b5p20a * 12) + b5p20b   // Watch the year+month combination

*-----------------------------------------------------------
* Recodes and Derived Variables
*-----------------------------------------------------------
recode educ 1/3 = 1 4/7 = 2 8/11 = 3, generate(educ_group)
recode work_jobdur 0/3 = 1 4/12 = 2 12/24 = 3 25/9999 = 4, gen(work_jobdur_cat)

gen school_years = .
replace school_years = 0 if educ == 1
replace school_years = 0 if educ == 2
replace school_years = 6 if educ == 3
replace school_years = 9 if educ == 4
replace school_years = 9 if educ == 5
replace school_years = 12 if educ == 6
replace school_years = 12 if educ == 7
replace school_years = 14 if educ == 8
replace school_years = 15 if educ == 9
replace school_years = 16 if educ == 10
replace school_years = 20 if educ == 11

la de searchdur 1 "1. <=3 bulan" 2 "2. 4-12 bulan" 3 "3. 13-24 bulan" 4 "4. >24 bulan"
la val work_jobdur_cat searchdur

forval x = 1/4 {
    gen work_searchdur_`x' = (work_jobdur_cat == `x')
    replace work_searchdur_`x' = . if lf == 0 | work_jobdur_cat == .
}

foreach var of varlist work_hours work_earnings work_wage {
    replace `var' = . if unemp == 1 | lf == 0
}

*-----------------------------------------------------------
* Finalize and Save 2009 Data
*-----------------------------------------------------------
gen year = `year'
// save $output/temp_sakernas_`year', replace

keep prov`year' wt urban male age educ unemp employment lf school_years sector9 sector17 ///
     work_informal work_status act_neet act_school act_household act_others work_hours ///
     work_whitecoll work_earnings work_wage work_jobdur* educ_group work_searchdur_* year work_certif


**---------------------------------------------------------------------------
** Working Hours, Underemployment, Status, and Formality Indicators (2009)
** Raw inputs: hours=b5p6b  status=b5p10a  occupation=kji  involuntary=(b5p4, b5p23)
**---------------------------------------------------------------------------

* hour: total working hours of all jobs (week)
cap confirm variable b5p6b
if !_rc {
    cap drop hour
    gen hour = b5p6b if employment == 1
}
else {
    cap gen hour = .
}

* underemp: hour<35 & employed
cap drop underemp
gen underemp = 1 if hour < 35 & hour > 0
replace underemp = 0 if hour == 0
replace underemp = 0 if hour >= 35 & hour != .

* underemp_invol & underemp_vol (legacy formula)
cap drop underemp_invol underemp_vol
gen underemp_invol = .
cap confirm variable b5p4
local has_i1 = !_rc
cap confirm variable b5p23
local has_i2 = !_rc
if `has_i1' & `has_i2' {
    replace underemp_invol = 0 if underemp == 1
    replace underemp_invol = 1 if (b5p4 == 1 | b5p23 == 1) & underemp == 1
}
gen underemp_vol = .
replace underemp_vol = 1 if underemp == 1 & underemp_invol == 0
replace underemp_vol = 0 if underemp == 1 & underemp_invol == 1

* hour decomposed
cap drop hour_under hour_vol hour_invol
gen hour_under = hour if underemp == 1
gen hour_vol   = hour if underemp_vol == 1
gen hour_invol = hour if underemp_invol == 1

* status (employment status, 1-7)
cap drop status
cap confirm variable b5p10a
if !_rc {
    gen status = b5p10a if employment == 1
    replace status = . if status == 0
}
else {
    gen status = .
}

* worktype (1-digit code; take first digit if multi-digit)
cap drop worktype
cap confirm variable kji
if !_rc {
    gen _wt_raw = kji if employment == 1
    gen worktype = .
    replace worktype = real(substr(string(int(abs(_wt_raw))), 1, 1)) if _wt_raw != . & _wt_raw > 0
    replace worktype = _wt_raw if abs(_wt_raw) < 10 & _wt_raw != .
    drop _wt_raw
}
else {
    gen worktype = .
}

* formal_simple: status in (3,4)
cap drop formal_simple
gen formal_simple = inrange(status, 3, 4) if status != . & employment == 1

* formal_new: wrktype2011 matrix
cap drop formal_new
gen formal_new = .
replace formal_new = wrktype2011[status, worktype] ///
    if status != . & worktype != . & employment == 1 ///
    & inrange(status, 1, 7) & inrange(worktype, 1, 8)

* formal_old: formal_new + casual workers in agri/construction
cap drop formal_old
gen formal_old = formal_new
replace formal_old = 1 if (status == 5 & sector9 == 1) & employment == 1
replace formal_old = 1 if (status == 6 & sector9 == 5) & employment == 1

* labels
cap label var hour           "working hours per week (all jobs combined)"
cap label var underemp       "underemployed dummy (less than 35 hours per week)"
cap label var underemp_invol "involuntary underemployment"
cap label var underemp_vol   "voluntary underemployment"
cap label var hour_under     "weekly hours among underemployed"
cap label var hour_vol       "weekly hours among voluntary underemployed"
cap label var hour_invol     "weekly hours among involuntary underemployed"
cap label var status         "main employment status"
cap label var worktype       "main occupation (1-digit KBJI)"
cap label var formal_simple  "simplified formality (employee or assisted employer)"
cap label var formal_new     "formality (wrktype2011 matrix)"
cap label var formal_old     "formality including casual workers in agriculture and construction"
**---------------------------------------------------------------------------
** Additional Employment Indicators
**---------------------------------------------------------------------------
cap drop employee casual_worker potential_exp
gen employee = work_status == 4 if work_status != .
gen casual_worker = inlist(work_status, 5, 6) if work_status != .
gen potential_exp = age - school_years if age != . & school_years != .
cap label var employee      "employee dummy"
cap label var casual_worker "casual worker dummy"
cap label var potential_exp "potential work experience"


	 save $clean/clean_sakernas_`year', replace
/*************************
 * End of Sakernas 2009
 ************************/

/*************************
 * Sakernas 2010
 ************************/

clear
set more off
local year = 2010
use $source/sakernas_`year', clear

*-----------------------------------------------------------
* Generate Basic Variables
*-----------------------------------------------------------
gen prov`year' = b1p01
gen wt         = weight
gen urban      = (b1p05 == 1)
gen male       = (jk == 1)
gen age        = umur         // WARNING: AGE OUTSIDE LF DETECTED
gen educ       = b5p1a

*-----------------------------------------------------------
* Employment and Unemployment Status
*-----------------------------------------------------------
gen unemp = .
replace unemp = 1 if b5p2a1 == 2 & b5p3 == 2 & b5p4 == 1
replace unemp = 1 if b5p2a1 == 2 & b5p3 == 2 & b5p5 == 1
replace unemp = 1 if b5p2a1 == 2 & inlist(b5p22, 1, 2)
replace unemp = 0 if unemp != 1

gen employment = .
replace employment = 1 if b5p2a1 == 1
replace employment = 1 if b5p3 == 1
replace employment = 0 if unemp == 1

*-----------------------------------------------------------
* Define Labor Force (LF)
*-----------------------------------------------------------
gen lf = .
replace lf = 1 if employment == 1 | unemp == 1
replace lf = 0 if age < 15
replace lf = 0 if lf != 1
replace unemp = . if lf == 0
replace employment = . if lf == 0

*-----------------------------------------------------------
* Sector and Work Variables
*-----------------------------------------------------------
gen sector9 = klui

#d;
									recode b5p7
										(0 = 18)
										(111 = 1)
										(504 = 1)
										(527 = 7)
										(1111 = 1)
										(1112 = 1)
										(1113 = 1)
										(1114 = 1)
										(1115 = 1)
										(1116 = 1)
										(1117 = 1)
										(1118 = 1)
										(1119 = 1)
										(1121 = 1)
										(1122 = 1)
										(1123 = 1)
										(1124 = 1)
										(1125 = 1)
										(1131 = 1)
										(1132 = 1)
										(1133 = 1)
										(1134 = 1)
										(1135 = 1)
										(1136 = 1)
										(1137 = 1)
										(1138 = 1)
										(1139 = 1)
										(1211 = 1)
										(1212 = 1)
										(1213 = 1)
										(1214 = 1)
										(1215 = 1)
										(1216 = 1)
										(1217 = 1)
										(1218 = 1)
										(1221 = 1)
										(1222 = 1)
										(1223 = 1)
										(1224 = 1)
										(1225 = 1)
										(1226 = 1)
										(1227 = 1)
										(1228 = 1)
										(1229 = 1)
										(1401 = 1)
										(1402 = 1)
										(1403 = 1)
										(1404 = 1)
										(1405 = 1)
										(1406 = 1)
										(1407 = 1)
										(1408 = 1)
										(1410 = 2)
										(1501 = 1)
										(1502 = 1)
										(2011 = 1)
										(2012 = 1)
										(2013 = 1)
										(2014 = 1)
										(2015 = 1)
										(2016 = 1)
										(2017 = 1)
										(2018 = 1)
										(2019 = 1)
										(2020 = 1)
										(2031 = 1)
										(2032 = 1)
										(2033 = 1)
										(2034 = 1)
										(2035 = 1)
										(2039 = 1)
										(2041 = 1)
										(2042 = 1)
										(2043 = 1)
										(2049 = 1)
										(2051 = 1)
										(2052 = 1)
										(2059 = 1)
										(5011 = 1)
										(5012 = 1)
										(5013 = 1)
										(5014 = 1)
										(5015 = 1)
										(5021 = 1)
										(5022 = 1)
										(5031 = 1)
										(5032 = 1)
										(5041 = 1)
										(5042 = 1)
										(5043 = 1)
										(5044 = 1)
										(5051 = 1)
										(5052 = 1)
										(5053 = 1)
										(5054 = 1)
										(5055 = 1)
										(5056 = 1)
										(5521 = 9)
										(6021 = 8)
										(6711 = 11)
										(6712 = 11)
										(7523 = 14)
										(8011 = 15)
										(10101 = 2)
										(10102 = 2)
										(10200 = 3)
										(11101 = 2)
										(11102 = 2)
										(11200 = 2)
										(12000 = 2)
										(13101 = 2)
										(13102 = 2)
										(13201 = 2)
										(13202 = 2)
										(13203 = 2)
										(13204 = 2)
										(13205 = 2)
										(13206 = 2)
										(13207 = 2)
										(13209 = 2)
										(14101 = 2)
										(14102 = 2)
										(14103 = 2)
										(14104 = 2)
										(14105 = 2)
										(14106 = 2)
										(14211 = 2)
										(14212 = 2)
										(14213 = 2)
										(14214 = 2)
										(14215 = 2)
										(14219 = 2)
										(14220 = 2)
										(14291 = 2)
										(14292 = 2)
										(14299 = 2)
										(15111 = 3)
										(15112 = 3)
										(15121 = 3)
										(15122 = 3)
										(15123 = 3)
										(15124 = 3)
										(15125 = 3)
										(15129 = 3)
										(15131 = 3)
										(15132 = 3)
										(15133 = 3)
										(15134 = 3)
										(15139 = 3)
										(15141 = 3)
										(15142 = 3)
										(15143 = 3)
										(15144 = 3)
										(15145 = 3)
										(15149 = 3)
										(15201 = 3)
										(15202 = 3)
										(15203 = 3)
										(15311 = 3)
										(15312 = 3)
										(15313 = 3)
										(15314 = 3)
										(15315 = 3)
										(15316 = 3)
										(15317 = 3)
										(15318 = 3)
										(15321 = 3)
										(15322 = 3)
										(15323 = 3)
										(15324 = 3)
										(15329 = 3)
										(15331 = 3)
										(15332 = 3)
										(15410 = 3)
										(15421 = 3)
										(15422 = 3)
										(15423 = 3)
										(15424 = 3)
										(15429 = 3)
										(15431 = 3)
										(15432 = 3)
										(15440 = 3)
										(15491 = 3)
										(15492 = 3)
										(15493 = 3)
										(15494 = 3)
										(15495 = 3)
										(15496 = 3)
										(15497 = 3)
										(15498 = 3)
										(15499 = 3)
										(15510 = 3)
										(15520 = 3)
										(15530 = 3)
										(15541 = 3)
										(15542 = 3)
										(16001 = 3)
										(16002 = 3)
										(16003 = 3)
										(16004 = 3)
										(16009 = 3)
										(17111 = 3)
										(17112 = 3)
										(17113 = 3)
										(17114 = 3)
										(17115 = 3)
										(17121 = 3)
										(17122 = 3)
										(17123 = 3)
										(17124 = 3)
										(17211 = 3)
										(17212 = 3)
										(17213 = 3)
										(17214 = 3)
										(17215 = 3)
										(17220 = 3)
										(17231 = 3)
										(17232 = 3)
										(17291 = 3)
										(17292 = 3)
										(17293 = 3)
										(17294 = 3)
										(17295 = 3)
										(17299 = 3)
										(17301 = 3)
										(17302 = 3)
										(17303 = 3)
										(17304 = 3)
										(17400 = 3)
										(18101 = 3)
										(18102 = 3)
										(18201 = 3)
										(18202 = 3)
										(18203 = 3)
										(19111 = 3)
										(19112 = 3)
										(19113 = 3)
										(19121 = 3)
										(19122 = 3)
										(19123 = 3)
										(19129 = 3)
										(19201 = 3)
										(19202 = 3)
										(19203 = 3)
										(19209 = 3)
										(20101 = 3)
										(20102 = 3)
										(20103 = 3)
										(20104 = 3)
										(20211 = 3)
										(20212 = 3)
										(20213 = 3)
										(20214 = 3)
										(20220 = 3)
										(20230 = 3)
										(20291 = 3)
										(20292 = 3)
										(20293 = 3)
										(20294 = 3)
										(20299 = 3)
										(21011 = 3)
										(21012 = 3)
										(21013 = 3)
										(21014 = 3)
										(21015 = 3)
										(21016 = 3)
										(21019 = 3)
										(21020 = 3)
										(21090 = 3)
										(22110 = 10)
										(22120 = 10)
										(22130 = 10)
										(22140 = 3)
										(22190 = 10)
										(22210 = 3)
										(22220 = 3)
										(22301 = 3)
										(22302 = 3)
										(23100 = 3)
										(23201 = 3)
										(23202 = 4)
										(23203 = 3)
										(23204 = 3)
										(23205 = 3)
										(23300 = 3)
										(24111 = 3)
										(24112 = 3)
										(24113 = 3)
										(24114 = 3)
										(24115 = 3)
										(24116 = 3)
										(24117 = 3)
										(24118 = 3)
										(24119 = 3)
										(24121 = 5)
										(24122 = 3)
										(24123 = 3)
										(24124 = 3)
										(24125 = 3)
										(24126 = 3)
										(24127 = 3)
										(24129 = 3)
										(24131 = 3)
										(24132 = 3)
										(24211 = 3)
										(24212 = 3)
										(24213 = 3)
										(24214 = 3)
										(24221 = 3)
										(24222 = 3)
										(24223 = 3)
										(24231 = 3)
										(24232 = 3)
										(24233 = 3)
										(24234 = 3)
										(24235 = 3)
										(24241 = 3)
										(24242 = 3)
										(24291 = 3)
										(24292 = 3)
										(24293 = 3)
										(24294 = 3)
										(24295 = 3)
										(24299 = 3)
										(24301 = 3)
										(24302 = 3)
										(25111 = 3)
										(25112 = 3)
										(25121 = 3)
										(25122 = 3)
										(25123 = 3)
										(25191 = 3)
										(25192 = 3)
										(25199 = 3)
										(25201 = 3)
										(25202 = 3)
										(25203 = 3)
										(25204 = 3)
										(25205 = 3)
										(25206 = 3)
										(25209 = 3)
										(26111 = 3)
										(26112 = 3)
										(26119 = 3)
										(26121 = 3)
										(26122 = 3)
										(26123 = 3)
										(26124 = 3)
										(26129 = 3)
										(26201 = 3)
										(26202 = 3)
										(26203 = 3)
										(26209 = 3)
										(26311 = 3)
										(26319 = 3)
										(26321 = 3)
										(26322 = 3)
										(26323 = 3)
										(26324 = 3)
										(26411 = 3)
										(26412 = 3)
										(26413 = 3)
										(26421 = 3)
										(26422 = 3)
										(26423 = 3)
										(26429 = 3)
										(26501 = 3)
										(26502 = 3)
										(26503 = 3)
										(26509 = 3)
										(26601 = 3)
										(26602 = 3)
										(26609 = 3)
										(26900 = 3)
										(27101 = 3)
										(27102 = 3)
										(27103 = 3)
										(27201 = 3)
										(27202 = 3)
										(27203 = 3)
										(27204 = 3)
										(27310 = 3)
										(27320 = 3)
										(28111 = 3)
										(28112 = 3)
										(28113 = 3)
										(28119 = 3)
										(28120 = 3)
										(28910 = 3)
										(28920 = 3)
										(28931 = 3)
										(28932 = 3)
										(28933 = 3)
										(28939 = 3)
										(28991 = 3)
										(28992 = 3)
										(28993 = 3)
										(28994 = 3)
										(28995 = 3)
										(28996 = 3)
										(28997 = 3)
										(28998 = 3)
										(28999 = 3)
										(29111 = 3)
										(29112 = 3)
										(29113 = 3)
										(29114 = 3)
										(29120 = 3)
										(29130 = 3)
										(29141 = 3)
										(29142 = 3)
										(29150 = 3)
										(29191 = 3)
										(29192 = 3)
										(29193 = 3)
										(29199 = 3)
										(29211 = 3)
										(29212 = 3)
										(29221 = 3)
										(29222 = 3)
										(29223 = 3)
										(29224 = 3)
										(29230 = 3)
										(29240 = 3)
										(29250 = 3)
										(29261 = 3)
										(29262 = 3)
										(29263 = 3)
										(29264 = 3)
										(29270 = 3)
										(29291 = 3)
										(29292 = 3)
										(29299 = 3)
										(29301 = 3)
										(29302 = 3)
										(29309 = 3)
										(30001 = 3)
										(30002 = 3)
										(30003 = 3)
										(30004 = 3)
										(31101 = 3)
										(31102 = 3)
										(31103 = 3)
										(31201 = 3)
										(31202 = 3)
										(31300 = 3)
										(31401 = 3)
										(31402 = 3)
										(31501 = 3)
										(31502 = 3)
										(31509 = 3)
										(31900 = 3)
										(32100 = 3)
										(32200 = 3)
										(32300 = 3)
										(33111 = 3)
										(33112 = 3)
										(33113 = 3)
										(33119 = 3)
										(33121 = 3)
										(33122 = 3)
										(33123 = 3)
										(33130 = 3)
										(33201 = 3)
										(33202 = 3)
										(33203 = 3)
										(33204 = 3)
										(33300 = 3)
										(34100 = 3)
										(34200 = 3)
										(34300 = 3)
										(35111 = 3)
										(35112 = 3)
										(35113 = 3)
										(35114 = 5)
										(35115 = 3)
										(35120 = 3)
										(35201 = 3)
										(35202 = 3)
										(35301 = 3)
										(35302 = 3)
										(35911 = 3)
										(35912 = 3)
										(35921 = 3)
										(35922 = 3)
										(35990 = 3)
										(36101 = 3)
										(36102 = 3)
										(36103 = 3)
										(36104 = 3)
										(36109 = 3)
										(36911 = 3)
										(36912 = 3)
										(36913 = 3)
										(36914 = 3)
										(36915 = 3)
										(36921 = 3)
										(36922 = 3)
										(36930 = 3)
										(36941 = 3)
										(36942 = 3)
										(36991 = 3)
										(36992 = 3)
										(36993 = 3)
										(36999 = 3)
										(37100 = 5)
										(37200 = 5)
										(40101 = 4)
										(40102 = 4)
										(40103 = 4)
										(40104 = 4)
										(40201 = 4)
										(40202 = 4)
										(40300 = 4)
										(41001 = 5)
										(41002 = 5)
										(41003 = 5)
										(45100 = 6)
										(45211 = 6)
										(45212 = 6)
										(45213 = 6)
										(45214 = 6)
										(45215 = 6)
										(45216 = 6)
										(45217 = 6)
										(45218 = 6)
										(45219 = 6)
										(45221 = 6)
										(45222 = 6)
										(45223 = 6)
										(45224 = 6)
										(45225 = 6)
										(45226 = 6)
										(45227 = 6)
										(45229 = 6)
										(45231 = 6)
										(45232 = 6)
										(45233 = 6)
										(45234 = 6)
										(45235 = 6)
										(45239 = 6)
										(45241 = 6)
										(45242 = 6)
										(45243 = 6)
										(45244 = 6)
										(45245 = 6)
										(45246 = 6)
										(45249 = 6)
										(45311 = 6)
										(45312 = 6)
										(45313 = 6)
										(45314 = 6)
										(45315 = 6)
										(45316 = 6)
										(45317 = 6)
										(45319 = 6)
										(45321 = 6)
										(45322 = 6)
										(45323 = 6)
										(45324 = 6)
										(45325 = 6)
										(45326 = 6)
										(45327 = 6)
										(45328 = 6)
										(45329 = 6)
										(45401 = 6)
										(45402 = 6)
										(45403 = 6)
										(45404 = 6)
										(45405 = 6)
										(45409 = 6)
										(45500 = 6)
										(50101 = 7)
										(50102 = 7)
										(50201 = 7)
										(50202 = 7)
										(50301 = 7)
										(50302 = 7)
										(50400 = 7)
										(51100 = 7)
										(51211 = 7)
										(51212 = 7)
										(51213 = 7)
										(51214 = 7)
										(51220 = 7)
										(51310 = 7)
										(51391 = 7)
										(51392 = 7)
										(51399 = 7)
										(51410 = 7)
										(51420 = 7)
										(51431 = 7)
										(51432 = 7)
										(51433 = 7)
										(51434 = 7)
										(51435 = 7)
										(51436 = 7)
										(51437 = 7)
										(51438 = 7)
										(51439 = 7)
										(51490 = 7)
										(51501 = 7)
										(51502 = 7)
										(51503 = 7)
										(51504 = 7)
										(51900 = 7)
										(52111 = 7)
										(52112 = 7)
										(52191 = 7)
										(52192 = 7)
										(52211 = 7)
										(52212 = 7)
										(52213 = 7)
										(52214 = 7)
										(52215 = 7)
										(52219 = 7)
										(52221 = 7)
										(52222 = 7)
										(52223 = 7)
										(52224 = 7)
										(52225 = 7)
										(52226 = 7)
										(52227 = 7)
										(52228 = 7)
										(52229 = 7)
										(52311 = 7)
										(52312 = 7)
										(52313 = 7)
										(52314 = 7)
										(52315 = 7)
										(52316 = 7)
										(52317 = 7)
										(52318 = 7)
										(52319 = 7)
										(52321 = 7)
										(52322 = 7)
										(52323 = 7)
										(52324 = 7)
										(52325 = 7)
										(52326 = 7)
										(52327 = 7)
										(52328 = 7)
										(52329 = 7)
										(52331 = 7)
										(52332 = 7)
										(52333 = 7)
										(52334 = 7)
										(52335 = 7)
										(52336 = 7)
										(52337 = 7)
										(52338 = 7)
										(52339 = 7)
										(52341 = 7)
										(52342 = 7)
										(52343 = 7)
										(52344 = 7)
										(52345 = 7)
										(52346 = 7)
										(52347 = 7)
										(52348 = 7)
										(52349 = 7)
										(52351 = 7)
										(52352 = 7)
										(52353 = 7)
										(52354 = 7)
										(52359 = 7)
										(52361 = 7)
										(52362 = 7)
										(52363 = 7)
										(52364 = 7)
										(52365 = 7)
										(52366 = 7)
										(52367 = 7)
										(52368 = 7)
										(52371 = 7)
										(52372 = 7)
										(52373 = 7)
										(52374 = 7)
										(52375 = 7)
										(52381 = 7)
										(52382 = 7)
										(52383 = 7)
										(52384 = 7)
										(52385 = 7)
										(52386 = 7)
										(52389 = 7)
										(52391 = 7)
										(52392 = 7)
										(52393 = 7)
										(52394 = 7)
										(52395 = 7)
										(52399 = 7)
										(52401 = 7)
										(52402 = 7)
										(52403 = 7)
										(52404 = 7)
										(52405 = 7)
										(52406 = 7)
										(52409 = 7)
										(52511 = 7)
										(52512 = 7)
										(52513 = 7)
										(52514 = 7)
										(52515 = 7)
										(52516 = 7)
										(52521 = 7)
										(52522 = 7)
										(52523 = 7)
										(52524 = 7)
										(52525 = 7)
										(52526 = 7)
										(52527 = 7)
										(52528 = 7)
										(52529 = 7)
										(52531 = 7)
										(52532 = 7)
										(52533 = 7)
										(52534 = 7)
										(52535 = 7)
										(52536 = 7)
										(52539 = 7)
										(52541 = 7)
										(52542 = 7)
										(52543 = 7)
										(52544 = 7)
										(52545 = 7)
										(52546 = 7)
										(52547 = 7)
										(52548 = 7)
										(52549 = 7)
										(52551 = 7)
										(52552 = 7)
										(52553 = 7)
										(52554 = 7)
										(52555 = 7)
										(52556 = 7)
										(52557 = 7)
										(52559 = 7)
										(52561 = 7)
										(52569 = 7)
										(52571 = 7)
										(52572 = 7)
										(52573 = 7)
										(52574 = 7)
										(52575 = 7)
										(52576 = 7)
										(52577 = 7)
										(52581 = 7)
										(52582 = 7)
										(52583 = 7)
										(52591 = 7)
										(52592 = 7)
										(52593 = 7)
										(52594 = 7)
										(52595 = 7)
										(52600 = 7)
										(52711 = 7)
										(52712 = 7)
										(52713 = 7)
										(52714 = 7)
										(52719 = 7)
										(52721 = 7)
										(52722 = 7)
										(52723 = 7)
										(52724 = 7)
										(52725 = 7)
										(52726 = 7)
										(52727 = 7)
										(52728 = 7)
										(52729 = 7)
										(53100 = 7)
										(53211 = 7)
										(53212 = 7)
										(53213 = 7)
										(53214 = 7)
										(53220 = 7)
										(53310 = 7)
										(53391 = 7)
										(53392 = 7)
										(53399 = 7)
										(53410 = 7)
										(53420 = 7)
										(53430 = 7)
										(53491 = 7)
										(53492 = 7)
										(53500 = 7)
										(53900 = 7)
										(54100 = 7)
										(54211 = 7)
										(54212 = 7)
										(54213 = 7)
										(54214 = 7)
										(54220 = 7)
										(54310 = 7)
										(54391 = 7)
										(54392 = 7)
										(54399 = 7)
										(54410 = 7)
										(54420 = 7)
										(54430 = 7)
										(54491 = 7)
										(54492 = 7)
										(54500 = 7)
										(54900 = 7)
										(55111 = 9)
										(55112 = 9)
										(55113 = 9)
										(55114 = 9)
										(55115 = 9)
										(55120 = 9)
										(55130 = 9)
										(55140 = 9)
										(55150 = 9)
										(55160 = 9)
										(55190 = 9)
										(55211 = 9)
										(55212 = 9)
										(55213 = 9)
										(55214 = 9)
										(55220 = 9)
										(55230 = 9)
										(55240 = 9)
										(55250 = 9)
										(55260 = 9)
										(60110 = 8)
										(60120 = 8)
										(60139 = 8)
										(60211 = 8)
										(60212 = 8)
										(60213 = 8)
										(60214 = 8)
										(60215 = 8)
										(60216 = 8)
										(60217 = 8)
										(60221 = 8)
										(60222 = 8)
										(60223 = 8)
										(60224 = 8)
										(60225 = 8)
										(60231 = 8)
										(60232 = 8)
										(60233 = 8)
										(60300 = 8)
										(61111 = 8)
										(61112 = 8)
										(61113 = 8)
										(61114 = 8)
										(61115 = 8)
										(61116 = 8)
										(61117 = 8)
										(61118 = 8)
										(61121 = 8)
										(61122 = 8)
										(61123 = 8)
										(61124 = 8)
										(61125 = 8)
										(61126 = 8)
										(61127 = 8)
										(61211 = 8)
										(61212 = 8)
										(61213 = 8)
										(61214 = 8)
										(61215 = 8)
										(61216 = 8)
										(61221 = 8)
										(61222 = 8)
										(61223 = 8)
										(61224 = 8)
										(61225 = 8)
										(61226 = 8)
										(62111 = 8)
										(62112 = 8)
										(62120 = 8)
										(62201 = 8)
										(62202 = 8)
										(62311 = 1)
										(62312 = 13)
										(62313 = 8)
										(62314 = 16)
										(62320 = 15)
										(62390 = 8)
										(63100 = 8)
										(63210 = 8)
										(63220 = 8)
										(63230 = 8)
										(63290 = 8)
										(63310 = 8)
										(63321 = 8)
										(63322 = 8)
										(63323 = 8)
										(63330 = 8)
										(63340 = 8)
										(63351 = 8)
										(63352 = 8)
										(63390 = 8)
										(63411 = 13)
										(63412 = 13)
										(63413 = 13)
										(63414 = 13)
										(63415 = 13)
										(63420 = 13)
										(63430 = 13)
										(63440 = 13)
										(63450 = 17)
										(63460 = 13)
										(63470 = 13)
										(63490 = 13)
										(63510 = 8)
										(63520 = 8)
										(63530 = 8)
										(63540 = 8)
										(63590 = 8)
										(63900 = 8)
										(64110 = 8)
										(64120 = 8)
										(64130 = 8)
										(64210 = 10)
										(64221 = 10)
										(64222 = 10)
										(64223 = 10)
										(64311 = 10)
										(64312 = 10)
										(64313 = 10)
										(64314 = 10)
										(64319 = 10)
										(64321 = 10)
										(64322 = 10)
										(64323 = 7)
										(64324 = 10)
										(64325 = 10)
										(64329 = 10)
										(64410 = 10)
										(64420 = 10)
										(64430 = 10)
										(65110 = 11)
										(65121 = 11)
										(65122 = 11)
										(65123 = 11)
										(65191 = 11)
										(65192 = 11)
										(65199 = 11)
										(65910 = 11)
										(65921 = 11)
										(65922 = 11)
										(65923 = 11)
										(65929 = 11)
										(65930 = 11)
										(65940 = 11)
										(65950 = 11)
										(65991 = 11)
										(65999 = 13)
										(66010 = 11)
										(66020 = 11)
										(66030 = 11)
										(67111 = 11)
										(67112 = 11)
										(67113 = 11)
										(67121 = 11)
										(67122 = 11)
										(67123 = 11)
										(67131 = 11)
										(67132 = 11)
										(67133 = 11)
										(67134 = 11)
										(67191 = 11)
										(67199 = 11)
										(67201 = 11)
										(67202 = 11)
										(67203 = 11)
										(67204 = 11)
										(67209 = 11)
										(70101 = 12)
										(70102 = 9)
										(70200 = 12)
										(70310 = 12)
										(70320 = 17)
										(71110 = 13)
										(71120 = 13)
										(71130 = 13)
										(71210 = 13)
										(71220 = 13)
										(71230 = 13)
										(71290 = 13)
										(71301 = 13)
										(71302 = 13)
										(71303 = 13)
										(71304 = 13)
										(71305 = 13)
										(71306 = 13)
										(71309 = 13)
										(72100 = 10)
										(72200 = 10)
										(72300 = 10)
										(72400 = 10)
										(72500 = 3)
										(72900 = 10)
										(73110 = 13)
										(73120 = 13)
										(73210 = 13)
										(73220 = 13)
										(74110 = 13)
										(74120 = 13)
										(74130 = 13)
										(74140 = 13)
										(74210 = 13)
										(74220 = 13)
										(74300 = 13)
										(74910 = 13)
										(74920 = 13)
										(74930 = 13)
										(74940 = 13)
										(74950 = 13)
										(74990 = 13)
										(75111 = 14)
										(75112 = 14)
										(75113 = 14)
										(75114 = 14)
										(75115 = 14)
										(75121 = 14)
										(75122 = 14)
										(75123 = 14)
										(75124 = 14)
										(75125 = 14)
										(75126 = 14)
										(75127 = 14)
										(75129 = 14)
										(75131 = 14)
										(75132 = 14)
										(75133 = 14)
										(75134 = 14)
										(75135 = 14)
										(75136 = 14)
										(75137 = 14)
										(75138 = 14)
										(75139 = 14)
										(75140 = 14)
										(75210 = 14)
										(75221 = 14)
										(75222 = 14)
										(75223 = 14)
										(75224 = 14)
										(75231 = 14)
										(75232 = 14)
										(75233 = 14)
										(75300 = 14)
										(80111 = 15)
										(80112 = 15)
										(80113 = 15)
										(80121 = 15)
										(80122 = 15)
										(80123 = 15)
										(80211 = 15)
										(80212 = 15)
										(80221 = 15)
										(80222 = 15)
										(80311 = 15)
										(80312 = 15)
										(80321 = 15)
										(80322 = 15)
										(80910 = 15)
										(80921 = 15)
										(80922 = 15)
										(80923 = 15)
										(80929 = 15)
										(85111 = 16)
										(85112 = 16)
										(85113 = 16)
										(85114 = 16)
										(85119 = 16)
										(85121 = 16)
										(85122 = 16)
										(85123 = 16)
										(85191 = 16)
										(85192 = 16)
										(85193 = 16)
										(85200 = 13)
										(85311 = 16)
										(85312 = 16)
										(85313 = 16)
										(85314 = 16)
										(85319 = 16)
										(85321 = 16)
										(85322 = 16)
										(90001 = 5)
										(90002 = 5)
										(91110 = 17)
										(91121 = 17)
										(91122 = 17)
										(91200 = 17)
										(91910 = 17)
										(91920 = 17)
										(91990 = 17)
										(92111 = 10)
										(92112 = 10)
										(92120 = 10)
										(92131 = 10)
										(92132 = 10)
										(92141 = 17)
										(92142 = 17)
										(92143 = 13)
										(92190 = 17)
										(92201 = 10)
										(92202 = 10)
										(92203 = 17)
										(92311 = 17)
										(92312 = 17)
										(92321 = 17)
										(92322 = 17)
										(92323 = 17)
										(92324 = 17)
										(92331 = 17)
										(92332 = 17)
										(92333 = 17)
										(92334 = 17)
										(92335 = 17)
										(92336 = 17)
										(92339 = 17)
										(92411 = 17)
										(92412 = 17)
										(92413 = 17)
										(92414 = 17)
										(92415 = 17)
										(92416 = 17)
										(92417 = 17)
										(92418 = 17)
										(92419 = 17)
										(92421 = 17)
										(92422 = 17)
										(92423 = 17)
										(92424 = 17)
										(92425 = 9)
										(92426 = 17)
										(92427 = 17)
										(92428 = 17)
										(92429 = 17)
										(92431 = 17)
										(92432 = 17)
										(92433 = 17)
										(92434 = 17)
										(92439 = 17)
										(93010 = 17)
										(93021 = 17)
										(93022 = 17)
										(93030 = 17)
										(93040 = 7)
										(93050 = 7)
										(93061 = 17)
										(93062 = 17)
										(93069 = 17)
										(93091 = 3)
										(93092 = 13)
										(93093 = 17)
										(93094 = 17)
										(95000 = 17)
										(99000 = 17)
										(99999 = 17)
										(1300 = 1)
										(15211 = 3)
										(15212 = 3)
										(26329 = 3)
										(50401 = 7)
										(50402 = 7)
										(50500 = 7)
										(52216 = 7)
										(52602 = 7)
										(92148 = 7)
										(51339 = 7)
										(60112 = 8)
										(60131 = 8)
										(63120 = 8), gen(sector17)
									;
									#d cr
									
gen work_informal = inlist(b5p10a, 1, 2, 5, 6, 7)
gen work_status   = b5p10a
gen work_certif   = b5p1d == 1
    replace work_certif = . if lf == 0
gen work_whitecoll = inrange(b5p8, 1, 5999)

gen act_school    = (b5p2a2 == 1 | b5p2a2 == 2) & b5p2b == 2 & lf == 0
gen act_household = (b5p2a3 == 1 | b5p2a3 == 2) & b5p2b == 3 & lf == 0
gen act_others    = (b5p2a4 == 1 | b5p2a4 == 2) & b5p2b == 4 & lf == 0
gen act_neet = 0
replace act_neet = 1 if b5p2a1 == 2 & b5p2a2 == 2
replace act_neet = 0 if act_school == 1
replace act_neet = . if age >= 25 | age <= 14

*-----------------------------------------------------------
* Adjust Employment for Consistency
*-----------------------------------------------------------
replace employment = 1 if employment == 0 & work_status != .

*-----------------------------------------------------------
* Create Work Outcome Variables
*-----------------------------------------------------------
gen work_hours    = b5p9
gen work_earnings = b5p12a + b5p12b
gen work_wage     = (b5p12a + b5p12b) if b5p10a == 4
gen work_jobdur   = (b5p20a * 12) + b5p20b   // Watch the year+month combination

*-----------------------------------------------------------
* Recodes and Derived Variables
*-----------------------------------------------------------
recode educ 1/3 = 1 4/7 = 2 8/11 = 3, generate(educ_group)
recode work_jobdur 0/3 = 1 4/12 = 2 12/24 = 3 25/9999 = 4, gen(work_jobdur_cat)

gen school_years = .
replace school_years = 0 if educ == 1
replace school_years = 0 if educ == 2
replace school_years = 6 if educ == 3
replace school_years = 9 if educ == 4
replace school_years = 9 if educ == 5
replace school_years = 12 if educ == 6
replace school_years = 12 if educ == 7
replace school_years = 14 if educ == 8
replace school_years = 15 if educ == 9
replace school_years = 16 if educ == 10
replace school_years = 20 if educ == 11

*-----------------------------------------------------------
* Job Search Duration Dummies
*-----------------------------------------------------------
la de searchdur 1 "1. <=3 bulan" 2 "2. 4-12 bulan" 3 "3. 13-24 bulan" 4 "4. >24 bulan"
la val work_jobdur_cat searchdur

forval x = 1/4 {
    gen work_searchdur_`x' = (work_jobdur_cat == `x')
    replace work_searchdur_`x' = . if lf == 0 | work_jobdur_cat == .
}

foreach var of varlist work_hours work_earnings work_wage {
    replace `var' = . if unemp == 1 | lf == 0
}

*-----------------------------------------------------------
* Finalize and Save 2010 Data
*-----------------------------------------------------------
gen year = `year'
// save "$output/temp_sakernas_`year'", replace

*-----------------------------------------------------------
* 2010 Clean Data 
*-----------------------------------------------------------

keep prov`year' wt urban male age educ unemp employment lf school_years sector9 sector17 ///
     work_informal work_status act_neet act_school act_household act_others work_hours ///
     work_whitecoll work_earnings work_wage work_jobdur* educ_group work_searchdur_* year work_certif


**---------------------------------------------------------------------------
** Working Hours, Underemployment, Status, and Formality Indicators (2010)
** Raw inputs: hours=b5p6b  status=b5p10a  occupation=kbji  involuntary=(b5p4, b5p23)
**---------------------------------------------------------------------------

* hour: total working hours of all jobs (week)
cap confirm variable b5p6b
if !_rc {
    cap drop hour
    gen hour = b5p6b if employment == 1
}
else {
    cap gen hour = .
}

* underemp: hour<35 & employed
cap drop underemp
gen underemp = 1 if hour < 35 & hour > 0
replace underemp = 0 if hour == 0
replace underemp = 0 if hour >= 35 & hour != .

* underemp_invol & underemp_vol (legacy formula)
cap drop underemp_invol underemp_vol
gen underemp_invol = .
cap confirm variable b5p4
local has_i1 = !_rc
cap confirm variable b5p23
local has_i2 = !_rc
if `has_i1' & `has_i2' {
    replace underemp_invol = 0 if underemp == 1
    replace underemp_invol = 1 if (b5p4 == 1 | b5p23 == 1) & underemp == 1
}
gen underemp_vol = .
replace underemp_vol = 1 if underemp == 1 & underemp_invol == 0
replace underemp_vol = 0 if underemp == 1 & underemp_invol == 1

* hour decomposed
cap drop hour_under hour_vol hour_invol
gen hour_under = hour if underemp == 1
gen hour_vol   = hour if underemp_vol == 1
gen hour_invol = hour if underemp_invol == 1

* status (employment status, 1-7)
cap drop status
cap confirm variable b5p10a
if !_rc {
    gen status = b5p10a if employment == 1
    replace status = . if status == 0
}
else {
    gen status = .
}

* worktype (1-digit code; take first digit if multi-digit)
cap drop worktype
cap confirm variable kbji
if !_rc {
    gen _wt_raw = kbji if employment == 1
    gen worktype = .
    replace worktype = real(substr(string(int(abs(_wt_raw))), 1, 1)) if _wt_raw != . & _wt_raw > 0
    replace worktype = _wt_raw if abs(_wt_raw) < 10 & _wt_raw != .
    drop _wt_raw
}
else {
    gen worktype = .
}

* formal_simple: status in (3,4)
cap drop formal_simple
gen formal_simple = inrange(status, 3, 4) if status != . & employment == 1

* formal_new: wrktype2011 matrix
cap drop formal_new
gen formal_new = .
replace formal_new = wrktype2011[status, worktype] ///
    if status != . & worktype != . & employment == 1 ///
    & inrange(status, 1, 7) & inrange(worktype, 1, 8)

* formal_old: formal_new + casual workers in agri/construction
cap drop formal_old
gen formal_old = formal_new
replace formal_old = 1 if (status == 5 & sector9 == 1) & employment == 1
replace formal_old = 1 if (status == 6 & sector9 == 5) & employment == 1

* labels
cap label var hour           "working hours per week (all jobs combined)"
cap label var underemp       "underemployed dummy (less than 35 hours per week)"
cap label var underemp_invol "involuntary underemployment"
cap label var underemp_vol   "voluntary underemployment"
cap label var hour_under     "weekly hours among underemployed"
cap label var hour_vol       "weekly hours among voluntary underemployed"
cap label var hour_invol     "weekly hours among involuntary underemployed"
cap label var status         "main employment status"
cap label var worktype       "main occupation (1-digit KBJI)"
cap label var formal_simple  "simplified formality (employee or assisted employer)"
cap label var formal_new     "formality (wrktype2011 matrix)"
cap label var formal_old     "formality including casual workers in agriculture and construction"
**---------------------------------------------------------------------------
** Additional Employment Indicators
**---------------------------------------------------------------------------
cap drop employee casual_worker potential_exp
gen employee = work_status == 4 if work_status != .
gen casual_worker = inlist(work_status, 5, 6) if work_status != .
gen potential_exp = age - school_years if age != . & school_years != .
cap label var employee      "employee dummy"
cap label var casual_worker "casual worker dummy"
cap label var potential_exp "potential work experience"

**---------------------------------------------------------------------------
** Education Major Classification
**---------------------------------------------------------------------------
cap drop educ_major
capture confirm variable b5p1b
if !_rc {
    gen educ_major = b5p1b
    /* Recode rules by education level:
       Different recode rules for different education levels (SMA vs Diploma/S1+)
       Codes: 0=SMP/under, 1=Sosio-hum, 2=Medika-FKH, 3=Pertanian, 4=Sains, 5=Teknik,
              6=Pendidikan, 7=Lainnya, 998=No info, 999=Other */
    capture confirm variable b5p1a
    if !_rc {
        recode educ_major (38 41 43/45 = 1) (42 = 4) (37 39/40 = 5) (27 46 = 998) (50 = 999) if inrange(b5p1a, 6, 7)
        recode educ_major (2/5 7/10 12 15/16 18 23 38 41 42/45 = 1) (13 = 2) (14 19 20 22 = 3) (6 21 24/25 42 = 4) (11 17 37 39 40 = 5) (26 = 6) (1 = 7) (27 46 = 998) (50 = 999) if b5p1a == 8
        recode educ_major (2/5 7/10 12 15/16 18 23 38 41 42/45 = 1) (13 = 2) (14 19 20 22 = 3) (6 21 24/25 42 = 4) (11 17 37 39 40 = 5) (26 = 6) (1 = 7) (27 46 = 998) (50 = 999) if b5p1a == 9
        recode educ_major (2/5 7/10 12 15/16 18 23 38 41 42/45 = 1) (13 = 2) (14 19 20 22 = 3) (6 21 24/25 42 = 4) (11 17 37 39 40 = 5) (26 = 6) (1 = 7) (27 46 = 998) (50 = 999) if inlist(b5p1a, 10, 11, 12, 13, 14)
    }
    label define educ_major 0 "No major (SMP or under)" 1 "Sosio-humaniora" 2 "Medika-FKH" ///
                            3 "Pertanian" 4 "Sains" 5 "Teknik" 6 "Pendidikan" 7 "Lainnya" ///
                            998 "No information" 999 "Other", replace
    label values educ_major educ_major
    label var educ_major "education major (post-2010 surveys)"
}



save $clean/clean_sakernas_`year', replace
	 
/*************************
 * End of Sakernas 2010
 ************************/

/*************************
 * Sakernas 2011
 ************************/
 
 *NOTES: there are some number updates in bps website, but still matched with the actual 2011 bps report (keadaan angkatan kerja di Indonesia)

clear
set more off
local year = 2011
use $source/sakernas_backcast_`year', clear

*-----------------------------------------------------------
* Basic Variables and Identifiers
*-----------------------------------------------------------
gen prov`year' = b1p01
    /* Adjust irregular province codes:
    replace prov = 81 if inrange(prov, 81, 82)
    replace prov = 82 if inrange(prov, 91, 93)
    replace prov = 32 if prov == 36
    replace prov = 71 if prov == 75*/
gen wt    = weight
gen urban = (b1p05 == 1)
gen male  = (jk == 1)
gen age   = umur           // WARNING: AGE OUTSIDE LF DETECTED
gen educ  = b5p1a

*-----------------------------------------------------------
* Employment and Unemployment Status
*-----------------------------------------------------------
gen unemp = .
replace unemp = 1 if b5p2a1 == 2 & b5p3 == 2 & b5p4 == 1
replace unemp = 1 if b5p2a1 == 2 & b5p3 == 2 & b5p5 == 1
replace unemp = 1 if b5p2a1 == 2 & inlist(b5p6, 1, 2)
replace unemp = 0 if unemp != 1

gen employment = .
replace employment = 1 if b5p2a1 == 1
replace employment = 1 if b5p3 == 1
replace employment = 0 if unemp == 1

*-----------------------------------------------------------
* Define Labor Force (LF)
*-----------------------------------------------------------
gen lf = .
replace lf = 1 if employment == 1 | unemp == 1
replace lf = 0 if age < 15
replace lf = 0 if lf != 1
replace unemp = . if lf == 0
replace employment = . if lf == 0

*-----------------------------------------------------------
* Sector and Work-Related Variables
*-----------------------------------------------------------
gen sector9 = kbji2002  // Sector variable as provided

recode kbli2009_2 (1/3 = 1) (5/9 = 2) ///
														(10/33 = 3) (35 = 4) ///
														(36/39 = 5) (41/43 = 6) ///
														(45/47 = 7) (49/53 = 8) ///
														(55/56 = 9) (58/63 = 10) ///
														(64/66 = 11) (68 = 12) ///
														(69/82 = 13) (84 = 14) ///
														(85 = 15) (86/88 = 16) ///
														(90/99 = 17) (0 = 18), ///
														gen(sector17)
														
														
gen work_informal = inlist(b5p12, 1, 2, 5, 6, 7)
gen work_status   = b5p12
gen work_certif   = (b5p1d1 == 1)    // (Supposed to be b5p1c)
    replace work_certif = . if lf == 0
gen work_whitecoll = inrange(kbji2000_1, 1, 5)

gen act_school    = ( (b5p2a2 == 1 | b5p2a2 == 2) & b5p2b == 2 & lf == 0 )
gen act_household = ( b5p2a3 == 1 | b5p2a3 == 2 ) & b5p2b == 3 & lf == 0
gen act_others    = ( b5p2a4 == 1 | b5p2a4 == 2 ) & b5p2b == 4 & lf == 0

gen act_neet = 0
replace act_neet = 1 if b5p2a1 == 2 & b5p2a2 == 2
replace act_neet = 0 if act_school == 1
replace act_neet = . if age >= 25 | age <= 14

*-----------------------------------------------------------
* Employment Matching Adjustment
*-----------------------------------------------------------
replace employment = 1 if employment == 0 & work_status != .

*-----------------------------------------------------------
* Work Outcome Variables
*-----------------------------------------------------------
gen work_hours    = b5p11
gen work_earnings = b5p13a + b5p13b
    replace work_earnings = 0 if work_earnings < 0
gen work_wage     = (b5p13a + b5p13b) if b5p12 == 4
    replace work_wage = 0 if work_wage < 0
gen work_jobdur   = (b5p21a * 12) + b5p21b   // Watch the year+month combination

*-----------------------------------------------------------
* Recodes and Derived Variables
*-----------------------------------------------------------
recode educ 1/4 = 1 5/10 = 2 11/14 = 3, generate(educ_group)
recode work_jobdur 0/3 = 1 4/12 = 2 12/24 = 3 25/9999 = 4, gen(work_jobdur_cat)

gen school_years = .
replace school_years = 0 if educ == 1
replace school_years = 0 if educ == 2
replace school_years = 6 if educ == 3
replace school_years = 6 if educ == 4
replace school_years = 9 if educ == 5
replace school_years = 9 if educ == 6
replace school_years = 9 if educ == 7
replace school_years = 12 if educ == 8
replace school_years = 12 if educ == 9
replace school_years = 12 if educ == 10
replace school_years = 14 if educ == 11
replace school_years = 15 if educ == 12
replace school_years = 16 if educ == 13
replace school_years = 20 if educ == 14

*-----------------------------------------------------------
* Job Search Duration Dummies
*-----------------------------------------------------------
la de searchdur 1 "1. <=3 bulan" 2 "2. 4-12 bulan" 3 "3. 13-24 bulan" 4 "4. >24 bulan"
la val work_jobdur_cat searchdur

forval x = 1/4 {
    gen work_searchdur_`x' = (work_jobdur_cat == `x')
    replace work_searchdur_`x' = . if lf == 0 | work_jobdur_cat == .
}

foreach var of varlist work_hours work_earnings work_wage {
    replace `var' = . if unemp == 1 | lf == 0
}

*-----------------------------------------------------------
* Finalize and Save 2011 Data
*-----------------------------------------------------------
gen year = `year'
// save $output/temp_sakernas_`year', replace

*-----------------------------------------------------------
* 2011 Clean Data (standard)
*-----------------------------------------------------------
keep prov`year' wt urban male age educ unemp employment lf school_years sector9 sector17 work_informal work_status ///
     act_neet act_school act_household act_others work_hours work_whitecoll work_earnings work_wage work_jobdur* ///
     educ_group work_searchdur_* year work_certif

**---------------------------------------------------------------------------
** Working Hours, Underemployment, Status, and Formality Indicators (2011)
** Raw inputs: hours=b5p8b  status=b5p12  occupation=kbji2000  involuntary=(b5p4, b5p7)
**---------------------------------------------------------------------------

* hour: total working hours of all jobs (week)
cap confirm variable b5p8b
if !_rc {
    cap drop hour
    gen hour = b5p8b if employment == 1
}
else {
    cap gen hour = .
}

* underemp: hour<35 & employed
cap drop underemp
gen underemp = 1 if hour < 35 & hour > 0
replace underemp = 0 if hour == 0
replace underemp = 0 if hour >= 35 & hour != .

* underemp_invol & underemp_vol (legacy formula)
cap drop underemp_invol underemp_vol
gen underemp_invol = .
cap confirm variable b5p4
local has_i1 = !_rc
cap confirm variable b5p7
local has_i2 = !_rc
if `has_i1' & `has_i2' {
    replace underemp_invol = 0 if underemp == 1
    replace underemp_invol = 1 if (b5p4 == 1 | b5p7 == 1) & underemp == 1
}
gen underemp_vol = .
replace underemp_vol = 1 if underemp == 1 & underemp_invol == 0
replace underemp_vol = 0 if underemp == 1 & underemp_invol == 1

* hour decomposed
cap drop hour_under hour_vol hour_invol
gen hour_under = hour if underemp == 1
gen hour_vol   = hour if underemp_vol == 1
gen hour_invol = hour if underemp_invol == 1

* status (employment status, 1-7)
cap drop status
cap confirm variable b5p12
if !_rc {
    gen status = b5p12 if employment == 1
    replace status = . if status == 0
}
else {
    gen status = .
}

* worktype (1-digit code; take first digit if multi-digit)
cap drop worktype
cap confirm variable kbji2000
if !_rc {
    gen _wt_raw = kbji2000 if employment == 1
    gen worktype = .
    replace worktype = real(substr(string(int(abs(_wt_raw))), 1, 1)) if _wt_raw != . & _wt_raw > 0
    replace worktype = _wt_raw if abs(_wt_raw) < 10 & _wt_raw != .
    drop _wt_raw
}
else {
    gen worktype = .
}

* formal_simple: status in (3,4)
cap drop formal_simple
gen formal_simple = inrange(status, 3, 4) if status != . & employment == 1

* formal_new: wrktype2011 matrix
cap drop formal_new
gen formal_new = .
replace formal_new = wrktype2011[status, worktype] ///
    if status != . & worktype != . & employment == 1 ///
    & inrange(status, 1, 7) & inrange(worktype, 1, 8)

* formal_old: formal_new + casual workers in agri/construction
cap drop formal_old
gen formal_old = formal_new
replace formal_old = 1 if (status == 5 & sector9 == 1) & employment == 1
replace formal_old = 1 if (status == 6 & sector9 == 5) & employment == 1

* labels
cap label var hour           "working hours per week (all jobs combined)"
cap label var underemp       "underemployed dummy (less than 35 hours per week)"
cap label var underemp_invol "involuntary underemployment"
cap label var underemp_vol   "voluntary underemployment"
cap label var hour_under     "weekly hours among underemployed"
cap label var hour_vol       "weekly hours among voluntary underemployed"
cap label var hour_invol     "weekly hours among involuntary underemployed"
cap label var status         "main employment status"
cap label var worktype       "main occupation (1-digit KBJI)"
cap label var formal_simple  "simplified formality (employee or assisted employer)"
cap label var formal_new     "formality (wrktype2011 matrix)"
cap label var formal_old     "formality including casual workers in agriculture and construction"
**---------------------------------------------------------------------------
** Additional Employment Indicators
**---------------------------------------------------------------------------
cap drop employee casual_worker potential_exp
gen employee = work_status == 4 if work_status != .
gen casual_worker = inlist(work_status, 5, 6) if work_status != .
gen potential_exp = age - school_years if age != . & school_years != .
cap label var employee      "employee dummy"
cap label var casual_worker "casual worker dummy"
cap label var potential_exp "potential work experience"

**---------------------------------------------------------------------------
** Education Major Classification
**---------------------------------------------------------------------------
cap drop educ_major
capture confirm variable b5p1b
if !_rc {
    gen educ_major = b5p1b
    /* Recode rules by education level:
       Different recode rules for different education levels (SMA vs Diploma/S1+)
       Codes: 0=SMP/under, 1=Sosio-hum, 2=Medika-FKH, 3=Pertanian, 4=Sains, 5=Teknik,
              6=Pendidikan, 7=Lainnya, 998=No info, 999=Other */
    capture confirm variable b5p1a
    if !_rc {
        recode educ_major (38 41 43/45 = 1) (42 = 4) (37 39/40 = 5) (27 46 = 998) (50 = 999) if inrange(b5p1a, 6, 7)
        recode educ_major (2/5 7/10 12 15/16 18 23 38 41 42/45 = 1) (13 = 2) (14 19 20 22 = 3) (6 21 24/25 42 = 4) (11 17 37 39 40 = 5) (26 = 6) (1 = 7) (27 46 = 998) (50 = 999) if b5p1a == 8
        recode educ_major (2/5 7/10 12 15/16 18 23 38 41 42/45 = 1) (13 = 2) (14 19 20 22 = 3) (6 21 24/25 42 = 4) (11 17 37 39 40 = 5) (26 = 6) (1 = 7) (27 46 = 998) (50 = 999) if b5p1a == 9
        recode educ_major (2/5 7/10 12 15/16 18 23 38 41 42/45 = 1) (13 = 2) (14 19 20 22 = 3) (6 21 24/25 42 = 4) (11 17 37 39 40 = 5) (26 = 6) (1 = 7) (27 46 = 998) (50 = 999) if inlist(b5p1a, 10, 11, 12, 13, 14)
    }
    label define educ_major 0 "No major (SMP or under)" 1 "Sosio-humaniora" 2 "Medika-FKH" ///
                            3 "Pertanian" 4 "Sains" 5 "Teknik" 6 "Pendidikan" 7 "Lainnya" ///
                            998 "No information" 999 "Other", replace
    label values educ_major educ_major
    label var educ_major "education major (post-2010 surveys)"
}



save $clean/clean_sakernas_`year', replace

/*************************
 * End of Sakernas 2011
 ************************/

/*************************
 * Sakernas 2012
 ************************/
// (standard code)

 *NOTES: due to data backcasting, so there are some number updates in bps website, but still matched with the actual 2012 bps report (keadaan angkatan kerja di Indonesia)

clear
set more off
local year = 2012
use $source/sakernas_backcast_`year', clear

*-----------------------------------------------------------
* Basic Variables and Filter
*-----------------------------------------------------------
gen prov`year' = b1p01
gen wt         = weight
gen urban      = (b1p05 == 1)
gen male       = (jk == 1)
gen age        = umur        // WARNING: AGE OUTSIDE LF DETECTED
gen educ       = b5p1a
keep if age >= 15

*-----------------------------------------------------------
* Employment Structure Using standard Definitions
*-----------------------------------------------------------
gen employment = (b5p2a1 == 1 | b5p3 == 1)

gen caker1 = (b5p4 == 1)    // looking for work
gen caker2 = (b5p5 == 1)    // establishing a new business/firm
gen caker3 = (b5p6 == 1)    // hopeless of job
gen caker4 = (b5p6 == 2)    // have a job in future start

gen dlabforce = cond(employment == 1, 1, ///
                cond(caker1 == 1, 2, ///
                cond(caker2 == 1, 3, ///
                cond(caker3 == 1, 4, ///
                cond(caker4 == 1, 5, ///
                cond(b5p2b == 2, 6, ///
                cond(b5p2b == 3, 7, 8)))))))
label define dlabforce 1 "Working" 2 "Looking" 3 "Establishing new business" 4 "Discouraged" 5 "Future job arranged" 6 "Student" 7 "Housekeeping" 8 "Others"
label val dlabforce dlabforce

*-----------------------------------------------------------
* Define Labor Force Based on WB Definitions
*-----------------------------------------------------------
gen labforce_core = cond(inrange(dlabforce, 1, 2), 1, 2)
recode labforce_core 2 = 0

gen labforce_broad = cond(inrange(dlabforce, 1, 5), 1, 2)
recode labforce_broad 2 = 0

gen lf = inrange(dlabforce, 1, 5)
label define lf 1 "Economically Active" 0 "Not Economically Active"
label value lf lf

replace employment = . if labforce_broad == 0

* Core unemployment
gen unemp = (employment == 0) if employment != .
gen unemp_core = unemp
replace unemp_core = . if labforce_core == 0

*-----------------------------------------------------------
* Sector and Work Variables
*-----------------------------------------------------------
gen sector9 = klui9

recode kbli2009_2 (1/3 = 1) (5/9 = 2) ///
														(10/33 = 3) (35 = 4) ///
														(36/39 = 5) (41/43 = 6) ///
														(45/47 = 7) (49/53 = 8) ///
														(55/56 = 9) (58/63 = 10) ///
														(64/66 = 11) (68 = 12) ///
														(69/82 = 13) (84 = 14) ///
														(85 = 15) (86/88 = 16) ///
														(90/99 = 17) (0 = 18), ///
														gen(sector17)
			
gen work_informal = inlist(b5p12, 1, 2, 5, 6, 7)
gen work_status   = b5p12
gen work_certif   = (b5p1c == 1)
    replace work_certif = . if lf == 0
gen work_whitecoll = inrange(kji, 1, 5)

*-----------------------------------------------------------
* Non-Labor Force Activity Dummies
*-----------------------------------------------------------
gen act_school = (dlabforce == 6) if labforce_broad == 0
gen act_household = (dlabforce == 7) if labforce_broad == 0
gen act_others = (dlabforce == 8) if labforce_broad == 0

gen act_neet = 0
replace act_neet = 1 if b5p2a1 == 2 & b5p2a2 == 2
replace act_neet = 0 if act_school == 1
replace act_neet = . if age >= 25 | age <= 14

*-----------------------------------------------------------
* Work Outcome Variables
*-----------------------------------------------------------
gen work_hours    = b5p11
gen work_earnings = b5p13a + b5p13b
    replace work_earnings = 0 if work_earnings < 0
gen work_wage     = (b5p13a + b5p13b) if b5p12 == 4
    replace work_wage = 0 if work_wage < 0
gen work_jobdur   = (b5p21a * 12) + b5p21b

*-----------------------------------------------------------
* Recodes and Derived Variables
*-----------------------------------------------------------
recode educ 1/4 = 1 5/10 = 2 11/14 = 3, generate(educ_group)
recode work_jobdur 0/3 = 1 4/12 = 2 12/24 = 3 25/9999 = 4, gen(work_jobdur_cat)

gen school_years = .
replace school_years = 0 if educ == 1 | educ == 2
replace school_years = 6 if educ == 3
replace school_years = 9 if educ == 4
replace school_years = 9 if educ == 5
replace school_years = 12 if educ == 6
replace school_years = 12 if educ == 7
replace school_years = 14 if educ == 8
replace school_years = 15 if educ == 9
replace school_years = 16 if educ == 10
replace school_years = 20 if educ == 11

*-----------------------------------------------------------
* Job Search Duration Dummies
*-----------------------------------------------------------
la de searchdur 1 "1. <=3 bulan" 2 "2. 4-12 bulan" 3 "3. 13-24 bulan" 4 "4. >24 bulan"
la val work_jobdur_cat searchdur

forval x = 1/4 {
    gen work_searchdur_`x' = (work_jobdur_cat == `x')
    replace work_searchdur_`x' = . if lf == 0 | work_jobdur_cat == .
}

foreach var of varlist work_hours work_earnings work_wage {
    replace `var' = . if unemp == 1 | lf == 0
}

*-----------------------------------------------------------
* Finalize and Save 2012 Data
*-----------------------------------------------------------
gen year = `year'
// save $output/temp_sakernas_`year', replace

*-----------------------------------------------------------
* 2012 Clean Data (standard)
*-----------------------------------------------------------
keep prov`year' wt urban male age educ unemp employment lf school_years sector9 sector17 work_informal work_status ///
     act_neet act_school act_household act_others work_hours work_whitecoll work_earnings work_wage work_jobdur* ///
     educ_group work_searchdur_* year work_certif

**---------------------------------------------------------------------------
** Working Hours, Underemployment, Status, and Formality Indicators (2012)
** Raw inputs: hours=b5p8b  status=b5p12  occupation=kbji2000  involuntary=(b5p4, b5p7)
**---------------------------------------------------------------------------

* hour: total working hours of all jobs (week)
cap confirm variable b5p8b
if !_rc {
    cap drop hour
    gen hour = b5p8b if employment == 1
}
else {
    cap gen hour = .
}

* underemp: hour<35 & employed
cap drop underemp
gen underemp = 1 if hour < 35 & hour > 0
replace underemp = 0 if hour == 0
replace underemp = 0 if hour >= 35 & hour != .

* underemp_invol & underemp_vol (legacy formula)
cap drop underemp_invol underemp_vol
gen underemp_invol = .
cap confirm variable b5p4
local has_i1 = !_rc
cap confirm variable b5p7
local has_i2 = !_rc
if `has_i1' & `has_i2' {
    replace underemp_invol = 0 if underemp == 1
    replace underemp_invol = 1 if (b5p4 == 1 | b5p7 == 1) & underemp == 1
}
gen underemp_vol = .
replace underemp_vol = 1 if underemp == 1 & underemp_invol == 0
replace underemp_vol = 0 if underemp == 1 & underemp_invol == 1

* hour decomposed
cap drop hour_under hour_vol hour_invol
gen hour_under = hour if underemp == 1
gen hour_vol   = hour if underemp_vol == 1
gen hour_invol = hour if underemp_invol == 1

* status (employment status, 1-7)
cap drop status
cap confirm variable b5p12
if !_rc {
    gen status = b5p12 if employment == 1
    replace status = . if status == 0
}
else {
    gen status = .
}

* worktype (1-digit code; take first digit if multi-digit)
cap drop worktype
cap confirm variable kbji2000
if !_rc {
    gen _wt_raw = kbji2000 if employment == 1
    gen worktype = .
    replace worktype = real(substr(string(int(abs(_wt_raw))), 1, 1)) if _wt_raw != . & _wt_raw > 0
    replace worktype = _wt_raw if abs(_wt_raw) < 10 & _wt_raw != .
    drop _wt_raw
}
else {
    gen worktype = .
}

* formal_simple: status in (3,4)
cap drop formal_simple
gen formal_simple = inrange(status, 3, 4) if status != . & employment == 1

* formal_new: wrktype2011 matrix
cap drop formal_new
gen formal_new = .
replace formal_new = wrktype2011[status, worktype] ///
    if status != . & worktype != . & employment == 1 ///
    & inrange(status, 1, 7) & inrange(worktype, 1, 8)

* formal_old: formal_new + casual workers in agri/construction
cap drop formal_old
gen formal_old = formal_new
replace formal_old = 1 if (status == 5 & sector9 == 1) & employment == 1
replace formal_old = 1 if (status == 6 & sector9 == 5) & employment == 1

* labels
cap label var hour           "working hours per week (all jobs combined)"
cap label var underemp       "underemployed dummy (less than 35 hours per week)"
cap label var underemp_invol "involuntary underemployment"
cap label var underemp_vol   "voluntary underemployment"
cap label var hour_under     "weekly hours among underemployed"
cap label var hour_vol       "weekly hours among voluntary underemployed"
cap label var hour_invol     "weekly hours among involuntary underemployed"
cap label var status         "main employment status"
cap label var worktype       "main occupation (1-digit KBJI)"
cap label var formal_simple  "simplified formality (employee or assisted employer)"
cap label var formal_new     "formality (wrktype2011 matrix)"
cap label var formal_old     "formality including casual workers in agriculture and construction"
**---------------------------------------------------------------------------
** Additional Employment Indicators
**---------------------------------------------------------------------------
cap drop employee casual_worker potential_exp
gen employee = work_status == 4 if work_status != .
gen casual_worker = inlist(work_status, 5, 6) if work_status != .
gen potential_exp = age - school_years if age != . & school_years != .
cap label var employee      "employee dummy"
cap label var casual_worker "casual worker dummy"
cap label var potential_exp "potential work experience"

**---------------------------------------------------------------------------
** Education Major Classification
**---------------------------------------------------------------------------
cap drop educ_major
capture confirm variable b5p1b
if !_rc {
    gen educ_major = b5p1b
    /* Recode rules by education level:
       Different recode rules for different education levels (SMA vs Diploma/S1+)
       Codes: 0=SMP/under, 1=Sosio-hum, 2=Medika-FKH, 3=Pertanian, 4=Sains, 5=Teknik,
              6=Pendidikan, 7=Lainnya, 998=No info, 999=Other */
    capture confirm variable b5p1a
    if !_rc {
        recode educ_major (38 41 43/45 = 1) (42 = 4) (37 39/40 = 5) (27 46 = 998) (50 = 999) if inrange(b5p1a, 6, 7)
        recode educ_major (2/5 7/10 12 15/16 18 23 38 41 42/45 = 1) (13 = 2) (14 19 20 22 = 3) (6 21 24/25 42 = 4) (11 17 37 39 40 = 5) (26 = 6) (1 = 7) (27 46 = 998) (50 = 999) if b5p1a == 8
        recode educ_major (2/5 7/10 12 15/16 18 23 38 41 42/45 = 1) (13 = 2) (14 19 20 22 = 3) (6 21 24/25 42 = 4) (11 17 37 39 40 = 5) (26 = 6) (1 = 7) (27 46 = 998) (50 = 999) if b5p1a == 9
        recode educ_major (2/5 7/10 12 15/16 18 23 38 41 42/45 = 1) (13 = 2) (14 19 20 22 = 3) (6 21 24/25 42 = 4) (11 17 37 39 40 = 5) (26 = 6) (1 = 7) (27 46 = 998) (50 = 999) if inlist(b5p1a, 10, 11, 12, 13, 14)
    }
    label define educ_major 0 "No major (SMP or under)" 1 "Sosio-humaniora" 2 "Medika-FKH" ///
                            3 "Pertanian" 4 "Sains" 5 "Teknik" 6 "Pendidikan" 7 "Lainnya" ///
                            998 "No information" 999 "Other", replace
    label values educ_major educ_major
    label var educ_major "education major (post-2010 surveys)"
}



save $clean/clean_sakernas_`year', replace

/*************************
 * End of Sakernas 2012
 ************************/

/*************************
 * Sakernas 2013
 ************************/

clear
set more off
local year = 2013
use $source/sakernas_backcast_`year', clear
local year = 2013  // Reassign year if needed

*-----------------------------------------------------------
* Basic Variables and Identifiers
*-----------------------------------------------------------
gen prov`year' = b1p01
gen wt         = weightbc
gen urban      = (b1p05 == 1)
gen male       = (jk == 1)
gen age        = umur         // WARNING: AGE OUTSIDE LF DETECTED
gen educ       = b5p1a

*-----------------------------------------------------------
* Employment and Unemployment Status
*-----------------------------------------------------------
gen unemp = .
replace unemp = 1 if b5p2a1 == 2 & b5p3 == 2 & b5p4 == 1
replace unemp = 1 if b5p2a1 == 2 & b5p3 == 2 & b5p5 == 1
replace unemp = 1 if b5p2a1 == 2 & inlist(b5p6, 1, 2)
replace unemp = 0 if unemp != 1

gen employment = .
replace employment = 1 if b5p2a1 == 1
replace employment = 1 if b5p3 == 1
replace employment = 0 if unemp == 1

*-----------------------------------------------------------
* Define Labor Force (LF)
*-----------------------------------------------------------
gen lf = .
replace lf = 1 if employment == 1 | unemp == 1
replace lf = 0 if age < 15
replace lf = 0 if lf != 1
replace unemp = . if lf == 0
replace employment = . if lf == 0


*-----------------------------------------------------------
* Sector and Work Variables
*-----------------------------------------------------------
gen sector9 = klui9
recode kbli2009_2 (1/3 = 1) (5/9 = 2) ///
														(10/33 = 3) (35 = 4) ///
														(36/39 = 5) (41/43 = 6) ///
														(45/47 = 7) (49/53 = 8) ///
														(55/56 = 9) (58/63 = 10) ///
														(64/66 = 11) (68 = 12) ///
														(69/82 = 13) (84 = 14) ///
														(85 = 15) (86/88 = 16) ///
														(90/99 = 17) (0 = 18), ///
														gen(sector17)
														
														
gen work_informal = inlist(b5p12, 1, 2, 5, 6, 7)
gen work_status   = b5p12
gen work_certif   = (b5p1c == 1)
    replace work_certif = . if lf == 0
gen work_whitecoll = inrange(kbji2000, 1, 5)

gen act_school    = ( (b5p2a2 == 1 | b5p2a2 == 2) & b5p2b == 2 & lf == 0 )
gen act_household = ( (b5p2a3 == 1 | b5p2a3 == 2) & b5p2b == 3 & lf == 0 )
gen act_others    = ( (b5p2a4 == 1 | b5p2a4 == 2) & b5p2b == 4 & lf == 0 )
gen act_neet = 0
replace act_neet = 1 if b5p2a1 == 2 & b5p2a2 == 2
replace act_neet = 0 if act_school == 1
replace act_neet = . if age >= 25 | age <= 14

*-----------------------------------------------------------
* Employment Matching Adjustment
*-----------------------------------------------------------
replace employment = 1 if employment == 0 & work_status != .

*-----------------------------------------------------------
* Work Outcome Variables
*-----------------------------------------------------------
gen work_hours    = b5p11
gen work_earnings = b5p13a + b5p13b
    replace work_earnings = 0 if work_earnings < 0
gen work_wage     = (b5p13a + b5p13b) if b5p12 == 4
    replace work_wage = 0 if work_wage < 0
gen work_jobdur   = (b5p21a * 12) + b5p21b

*-----------------------------------------------------------
* Recodes and Derived Variables
*-----------------------------------------------------------
recode educ 1/4 = 1 5/10 = 2 11/14 = 3, generate(educ_group)
recode work_jobdur 0/3 = 1 4/12 = 2 12/24 = 3 25/9999 = 4, gen(work_jobdur_cat)

gen school_years = .
replace school_years = 0 if educ == 1
replace school_years = 0 if educ == 2
replace school_years = 6 if educ == 3
replace school_years = 9 if educ == 4
replace school_years = 9 if educ == 5
replace school_years = 12 if educ == 6
replace school_years = 12 if educ == 7
replace school_years = 14 if educ == 8
replace school_years = 15 if educ == 9
replace school_years = 16 if educ == 10
replace school_years = 20 if educ == 11

*-----------------------------------------------------------
* Job Search Duration Dummies
*-----------------------------------------------------------
la de searchdur 1 "1. <=3 bulan" 2 "2. 4-12 bulan" 3 "3. 13-24 bulan" 4 "4. >24 bulan"
la val work_jobdur_cat searchdur

forval x = 1/4 {
    gen work_searchdur_`x' = (work_jobdur_cat == `x')
    replace work_searchdur_`x' = . if lf == 0 | work_jobdur_cat == .
}

foreach var of varlist work_hours work_earnings work_wage {
    replace `var' = . if unemp == 1 | lf == 0
}

*-----------------------------------------------------------
* Finalize and Save 2013 Data
*-----------------------------------------------------------
gen year = `year'
// save $output/temp_sakernas_`year', replace

*-----------------------------------------------------------
* 2013 Clean Data (standard)
*-----------------------------------------------------------
keep prov`year' wt urban male age educ unemp employment lf school_years sector9 sector17 work_informal work_status ///
     act_neet act_school act_household act_others work_hours work_whitecoll work_earnings work_wage work_jobdur* ///
     educ_group work_searchdur_* year work_certif

**---------------------------------------------------------------------------
** Working Hours, Underemployment, Status, and Formality Indicators (2013)
** Raw inputs: hours=b5p8b  status=b5p12  occupation=kbji2000_1  involuntary=(b5p4, b5p7)
**---------------------------------------------------------------------------

* hour: total working hours of all jobs (week)
cap confirm variable b5p8b
if !_rc {
    cap drop hour
    gen hour = b5p8b if employment == 1
}
else {
    cap gen hour = .
}

* underemp: hour<35 & employed
cap drop underemp
gen underemp = 1 if hour < 35 & hour > 0
replace underemp = 0 if hour == 0
replace underemp = 0 if hour >= 35 & hour != .

* underemp_invol & underemp_vol (legacy formula)
cap drop underemp_invol underemp_vol
gen underemp_invol = .
cap confirm variable b5p4
local has_i1 = !_rc
cap confirm variable b5p7
local has_i2 = !_rc
if `has_i1' & `has_i2' {
    replace underemp_invol = 0 if underemp == 1
    replace underemp_invol = 1 if (b5p4 == 1 | b5p7 == 1) & underemp == 1
}
gen underemp_vol = .
replace underemp_vol = 1 if underemp == 1 & underemp_invol == 0
replace underemp_vol = 0 if underemp == 1 & underemp_invol == 1

* hour decomposed
cap drop hour_under hour_vol hour_invol
gen hour_under = hour if underemp == 1
gen hour_vol   = hour if underemp_vol == 1
gen hour_invol = hour if underemp_invol == 1

* status (employment status, 1-7)
cap drop status
cap confirm variable b5p12
if !_rc {
    gen status = b5p12 if employment == 1
    replace status = . if status == 0
}
else {
    gen status = .
}

* worktype (1-digit code; take first digit if multi-digit)
cap drop worktype
cap confirm variable kbji2000_1
if !_rc {
    gen _wt_raw = kbji2000_1 if employment == 1
    gen worktype = .
    replace worktype = real(substr(string(int(abs(_wt_raw))), 1, 1)) if _wt_raw != . & _wt_raw > 0
    replace worktype = _wt_raw if abs(_wt_raw) < 10 & _wt_raw != .
    drop _wt_raw
}
else {
    gen worktype = .
}

* formal_simple: status in (3,4)
cap drop formal_simple
gen formal_simple = inrange(status, 3, 4) if status != . & employment == 1

* formal_new: wrktype2011 matrix
cap drop formal_new
gen formal_new = .
replace formal_new = wrktype2011[status, worktype] ///
    if status != . & worktype != . & employment == 1 ///
    & inrange(status, 1, 7) & inrange(worktype, 1, 8)

* formal_old: formal_new + casual workers in agri/construction
cap drop formal_old
gen formal_old = formal_new
replace formal_old = 1 if (status == 5 & sector9 == 1) & employment == 1
replace formal_old = 1 if (status == 6 & sector9 == 5) & employment == 1

* labels
cap label var hour           "working hours per week (all jobs combined)"
cap label var underemp       "underemployed dummy (less than 35 hours per week)"
cap label var underemp_invol "involuntary underemployment"
cap label var underemp_vol   "voluntary underemployment"
cap label var hour_under     "weekly hours among underemployed"
cap label var hour_vol       "weekly hours among voluntary underemployed"
cap label var hour_invol     "weekly hours among involuntary underemployed"
cap label var status         "main employment status"
cap label var worktype       "main occupation (1-digit KBJI)"
cap label var formal_simple  "simplified formality (employee or assisted employer)"
cap label var formal_new     "formality (wrktype2011 matrix)"
cap label var formal_old     "formality including casual workers in agriculture and construction"
**---------------------------------------------------------------------------
** Additional Employment Indicators
**---------------------------------------------------------------------------
cap drop employee casual_worker potential_exp
gen employee = work_status == 4 if work_status != .
gen casual_worker = inlist(work_status, 5, 6) if work_status != .
gen potential_exp = age - school_years if age != . & school_years != .
cap label var employee      "employee dummy"
cap label var casual_worker "casual worker dummy"
cap label var potential_exp "potential work experience"

**---------------------------------------------------------------------------
** Education Major Classification
**---------------------------------------------------------------------------
cap drop educ_major
capture confirm variable b5p1b
if !_rc {
    gen educ_major = b5p1b
    /* Recode rules by education level:
       Different recode rules for different education levels (SMA vs Diploma/S1+)
       Codes: 0=SMP/under, 1=Sosio-hum, 2=Medika-FKH, 3=Pertanian, 4=Sains, 5=Teknik,
              6=Pendidikan, 7=Lainnya, 998=No info, 999=Other */
    capture confirm variable b5p1a
    if !_rc {
        recode educ_major (38 41 43/45 = 1) (42 = 4) (37 39/40 = 5) (27 46 = 998) (50 = 999) if inrange(b5p1a, 6, 7)
        recode educ_major (2/5 7/10 12 15/16 18 23 38 41 42/45 = 1) (13 = 2) (14 19 20 22 = 3) (6 21 24/25 42 = 4) (11 17 37 39 40 = 5) (26 = 6) (1 = 7) (27 46 = 998) (50 = 999) if b5p1a == 8
        recode educ_major (2/5 7/10 12 15/16 18 23 38 41 42/45 = 1) (13 = 2) (14 19 20 22 = 3) (6 21 24/25 42 = 4) (11 17 37 39 40 = 5) (26 = 6) (1 = 7) (27 46 = 998) (50 = 999) if b5p1a == 9
        recode educ_major (2/5 7/10 12 15/16 18 23 38 41 42/45 = 1) (13 = 2) (14 19 20 22 = 3) (6 21 24/25 42 = 4) (11 17 37 39 40 = 5) (26 = 6) (1 = 7) (27 46 = 998) (50 = 999) if inlist(b5p1a, 10, 11, 12, 13, 14)
    }
    label define educ_major 0 "No major (SMP or under)" 1 "Sosio-humaniora" 2 "Medika-FKH" ///
                            3 "Pertanian" 4 "Sains" 5 "Teknik" 6 "Pendidikan" 7 "Lainnya" ///
                            998 "No information" 999 "Other", replace
    label values educ_major educ_major
    label var educ_major "education major (post-2010 surveys)"
}



save $clean/clean_sakernas_`year', replace

/*************************
 * End of Sakernas 2013
 ************************/
 
/*************************
 * Sakernas 2014
 ************************/

clear
set more off
local year = 2014
use $source/sakernas_`year', clear

*-----------------------------------------------------------
* Basic Variables and Identifiers
*-----------------------------------------------------------
gen prov`year' = kode_pro
gen wt         = weight
gen urban      = (klasifik == 1)
gen male       = (b4_k4 == 1)
gen age        = b4_k5         // WARNING: AGE OUTSIDE LF DETECTED
gen educ       = b5_r1a

*-----------------------------------------------------------
* Employment and Unemployment Status
*-----------------------------------------------------------
gen unemp = .
replace unemp = 1 if b5_r2a1 == 2 & b5_r3 == 2 & b5_r4 == 1
replace unemp = 1 if b5_r2a1 == 2 & b5_r3 == 2 & b5_r5 == 1
replace unemp = 1 if b5_r2a1 == 2 & inlist(b5_r6, 1, 2)
replace unemp = 0 if unemp != 1

gen employment = .
replace employment = 1 if b5_r2a1 == 1
replace employment = 1 if b5_r3 == 1
replace employment = 0 if unemp == 1

*-----------------------------------------------------------
* Define Labor Force (LF)
*-----------------------------------------------------------
gen lf = .
replace lf = 1 if employment == 1 | unemp == 1
replace lf = 0 if age < 15
replace lf = 0 if lf != 1
replace unemp = . if lf == 0
replace employment = . if lf == 0


*-----------------------------------------------------------
* Sector and Work Variables
*-----------------------------------------------------------
gen sector9			= klui9

recode kbli2009 (1/3 = 1) (5/9 = 2) ///
														(10/33 = 3) (35 = 4) ///
														(36/39 = 5) (41/43 = 6) ///
														(45/47 = 7) (49/53 = 8) ///
														(55/56 = 9) (58/63 = 10) ///
														(64/66 = 11) (68 = 12) ///
														(69/82 = 13) (84 = 14) ///
														(85 = 15) (86/88 = 16) ///
														(90/99 = 17) (0 = 18), ///
														gen(sector17)
			
gen work_informal = inlist(b5_r12, 1, 2, 5, 6, 7)
gen work_status   = b5_r12
gen work_certif   = (b5_r1c == 1)
    replace work_certif = . if lf == 0
gen work_whitecoll = inrange(kbji2000, 1, 5)

gen act_school    = ((b5_r2a2 == 1 | b5_r2a2 == 2) & b5_r2b == 2 & lf == 0)
gen act_household = ((b5_r2a3 == 1 | b5_r2a3 == 2) & b5_r2b == 3 & lf == 0)
gen act_others    = ((b5_r2a4 == 1 | b5_r2a4 == 2) & b5_r2b == 4 & lf == 0)
gen act_neet = 0
replace act_neet = 1 if b5_r2a1 == 2 & b5_r2a2 == 2
replace act_neet = 0 if act_school == 1
replace act_neet = . if age >= 25 | age <= 14

*-----------------------------------------------------------
* Employment Adjustment
*-----------------------------------------------------------
replace employment = 1 if employment == 0 & work_status != .

*-----------------------------------------------------------
* Work Outcome Variables
*-----------------------------------------------------------
gen work_hours    = b5_r11
gen work_earnings = b5_r13a + b5_r13b
    replace work_earnings = 0 if work_earnings < 0
gen work_wage     = (b5_r13a + b5_r13b) if b5_r12 == 4
    replace work_wage = 0 if work_wage < 0
gen work_jobdur   = (b5_r21a * 12) + b5_r21b   // Watch the year+month combination

*-----------------------------------------------------------
* Recodes and Derived Variables
*-----------------------------------------------------------
recode educ 1/4 = 1 5/10 = 2 11/14 = 3, generate(educ_group)
recode work_jobdur 0/3 = 1 4/12 = 2 12/24 = 3 25/9999 = 4, gen(work_jobdur_cat)

gen school_years = .
replace school_years = 0 if educ == 1 | educ == 2
replace school_years = 6 if educ == 3
replace school_years = 6 if educ == 4
replace school_years = 9 if educ == 5
replace school_years = 9 if educ == 6
replace school_years = 9 if educ == 7
replace school_years = 12 if educ == 8
replace school_years = 12 if educ == 9
replace school_years = 12 if educ == 10
replace school_years = 14 if educ == 11
replace school_years = 15 if educ == 12
replace school_years = 16 if educ == 13
replace school_years = 20 if educ == 14

*-----------------------------------------------------------
* Job Search Duration Dummies
*-----------------------------------------------------------
la de searchdur 1 "1. <=3 bulan" 2 "2. 4-12 bulan" 3 "3. 13-24 bulan" 4 "4. >24 bulan"
la val work_jobdur_cat searchdur

forval x = 1/4 {
    gen work_searchdur_`x' = (work_jobdur_cat == `x')
    replace work_searchdur_`x' = . if lf == 0 | work_jobdur_cat == .
}

foreach var of varlist work_hours work_earnings work_wage {
    replace `var' = . if unemp == 1 | lf == 0
}

*-----------------------------------------------------------
* Finalize and Save 2014 Data
*-----------------------------------------------------------
gen year = `year'
// save "$output/temp_sakernas_`year'", replace

*-----------------------------------------------------------
* 2014 Clean Data (standard)
*-----------------------------------------------------------
keep prov`year' wt urban male age educ unemp employment lf school_years sector9 sector17 work_informal work_status ///
     act_neet act_school act_household act_others work_hours work_whitecoll work_earnings work_wage work_jobdur* ///
     educ_group work_searchdur_* year work_certif

**---------------------------------------------------------------------------
** Working Hours, Underemployment, Status, and Formality Indicators (2014)
** Raw inputs: hours=b5_r8b  status=b5_r12  occupation=kbji2000  involuntary=(b5_r4, b5_r7)
**---------------------------------------------------------------------------

* hour: total working hours of all jobs (week)
cap confirm variable b5_r8b
if !_rc {
    cap drop hour
    gen hour = b5_r8b if employment == 1
}
else {
    cap gen hour = .
}

* underemp: hour<35 & employed
cap drop underemp
gen underemp = 1 if hour < 35 & hour > 0
replace underemp = 0 if hour == 0
replace underemp = 0 if hour >= 35 & hour != .

* underemp_invol & underemp_vol (legacy formula)
cap drop underemp_invol underemp_vol
gen underemp_invol = .
cap confirm variable b5_r4
local has_i1 = !_rc
cap confirm variable b5_r7
local has_i2 = !_rc
if `has_i1' & `has_i2' {
    replace underemp_invol = 0 if underemp == 1
    replace underemp_invol = 1 if (b5_r4 == 1 | b5_r7 == 1) & underemp == 1
}
gen underemp_vol = .
replace underemp_vol = 1 if underemp == 1 & underemp_invol == 0
replace underemp_vol = 0 if underemp == 1 & underemp_invol == 1

* hour decomposed
cap drop hour_under hour_vol hour_invol
gen hour_under = hour if underemp == 1
gen hour_vol   = hour if underemp_vol == 1
gen hour_invol = hour if underemp_invol == 1

* status (employment status, 1-7)
cap drop status
cap confirm variable b5_r12
if !_rc {
    gen status = b5_r12 if employment == 1
    replace status = . if status == 0
}
else {
    gen status = .
}

* worktype (1-digit code; take first digit if multi-digit)
cap drop worktype
cap confirm variable kbji2000
if !_rc {
    gen _wt_raw = kbji2000 if employment == 1
    gen worktype = .
    replace worktype = real(substr(string(int(abs(_wt_raw))), 1, 1)) if _wt_raw != . & _wt_raw > 0
    replace worktype = _wt_raw if abs(_wt_raw) < 10 & _wt_raw != .
    drop _wt_raw
}
else {
    gen worktype = .
}

* formal_simple: status in (3,4)
cap drop formal_simple
gen formal_simple = inrange(status, 3, 4) if status != . & employment == 1

* formal_new: wrktype2011 matrix
cap drop formal_new
gen formal_new = .
replace formal_new = wrktype2011[status, worktype] ///
    if status != . & worktype != . & employment == 1 ///
    & inrange(status, 1, 7) & inrange(worktype, 1, 8)

* formal_old: formal_new + casual workers in agri/construction
cap drop formal_old
gen formal_old = formal_new
replace formal_old = 1 if (status == 5 & sector9 == 1) & employment == 1
replace formal_old = 1 if (status == 6 & sector9 == 5) & employment == 1

* labels
cap label var hour           "working hours per week (all jobs combined)"
cap label var underemp       "underemployed dummy (less than 35 hours per week)"
cap label var underemp_invol "involuntary underemployment"
cap label var underemp_vol   "voluntary underemployment"
cap label var hour_under     "weekly hours among underemployed"
cap label var hour_vol       "weekly hours among voluntary underemployed"
cap label var hour_invol     "weekly hours among involuntary underemployed"
cap label var status         "main employment status"
cap label var worktype       "main occupation (1-digit KBJI)"
cap label var formal_simple  "simplified formality (employee or assisted employer)"
cap label var formal_new     "formality (wrktype2011 matrix)"
cap label var formal_old     "formality including casual workers in agriculture and construction"
**---------------------------------------------------------------------------
** Additional Employment Indicators
**---------------------------------------------------------------------------
cap drop employee casual_worker potential_exp
gen employee = work_status == 4 if work_status != .
gen casual_worker = inlist(work_status, 5, 6) if work_status != .
gen potential_exp = age - school_years if age != . & school_years != .
cap label var employee      "employee dummy"
cap label var casual_worker "casual worker dummy"
cap label var potential_exp "potential work experience"

**---------------------------------------------------------------------------
** Education Major Classification
**---------------------------------------------------------------------------
cap drop educ_major
capture confirm variable b5_r1b
if !_rc {
    gen educ_major = b5_r1b
    /* Recode rules by education level:
       Different recode rules for different education levels (SMA vs Diploma/S1+)
       Codes: 0=SMP/under, 1=Sosio-hum, 2=Medika-FKH, 3=Pertanian, 4=Sains, 5=Teknik,
              6=Pendidikan, 7=Lainnya, 998=No info, 999=Other */
    capture confirm variable b5_r1a
    if !_rc {
        recode educ_major (38 41 43/45 = 1) (42 = 4) (37 39/40 = 5) (27 46 = 998) (50 = 999) if inrange(b5_r1a, 6, 7)
        recode educ_major (2/5 7/10 12 15/16 18 23 38 41 42/45 = 1) (13 = 2) (14 19 20 22 = 3) (6 21 24/25 42 = 4) (11 17 37 39 40 = 5) (26 = 6) (1 = 7) (27 46 = 998) (50 = 999) if b5_r1a == 8
        recode educ_major (2/5 7/10 12 15/16 18 23 38 41 42/45 = 1) (13 = 2) (14 19 20 22 = 3) (6 21 24/25 42 = 4) (11 17 37 39 40 = 5) (26 = 6) (1 = 7) (27 46 = 998) (50 = 999) if b5_r1a == 9
        recode educ_major (2/5 7/10 12 15/16 18 23 38 41 42/45 = 1) (13 = 2) (14 19 20 22 = 3) (6 21 24/25 42 = 4) (11 17 37 39 40 = 5) (26 = 6) (1 = 7) (27 46 = 998) (50 = 999) if inlist(b5_r1a, 10, 11, 12, 13, 14)
    }
    label define educ_major 0 "No major (SMP or under)" 1 "Sosio-humaniora" 2 "Medika-FKH" ///
                            3 "Pertanian" 4 "Sains" 5 "Teknik" 6 "Pendidikan" 7 "Lainnya" ///
                            998 "No information" 999 "Other", replace
    label values educ_major educ_major
    label var educ_major "education major (post-2010 surveys)"
}



save $clean/clean_sakernas_`year', replace

/*************************
 * End of Sakernas 2014
 ************************/
 
 /*************************
 * Sakernas 2015 (standard)
 ************************/

clear
set more off
local year = 2015
use $source/sakernas_`year', clear

*-----------------------------------------------------------
* Basic Variables and Filter
*-----------------------------------------------------------
gen prov`year' = kode_prov
gen wt         = weight
gen urban      = (klasifikas == 1)
gen male       = (b4_k4 == 1)
gen age        = b4_k5         // WARNING: AGE OUTSIDE LF DETECTED
gen educ       = b5_r1a
keep if age >= 15

*-----------------------------------------------------------
* Define Employment Structure (standard)
*-----------------------------------------------------------
gen employment = (b5_r2a1 == 1 | b5_r3 == 1)

* Define additional work status indicators (caker variables)
gen caker1 = (b5_r4 == 1)  // Looking for work
gen caker2 = (b5_r5 == 1)  // Establishing new business/firm
gen caker3 = (b5_r6 == 1)  // Hopeless of job
gen caker4 = (b5_r6 == 2)  // Have a job in future start

gen dlabforce = cond(employment == 1, 1, ///
                cond(caker1 == 1, 2, ///
                cond(caker2 == 1, 3, ///
                cond(caker3 == 1, 4, ///
                cond(caker4 == 1, 5, ///
                cond(b5_r2b == 2, 6, ///
                cond(b5_r2b == 3, 7, 8)))))))
label define dlabforce 1 "Working" 2 "Looking" 3 "Establishing new business" 4 "Discouraged" 5 "Future job arranged" 6 "Student" 7 "Housekeeping" 8 "Others"
label val dlabforce dlabforce

*-----------------------------------------------------------
* Define Labor Force Using WB Definitions
*-----------------------------------------------------------
gen labforce_core = cond(inrange(dlabforce, 1, 2), 1, 2)
recode labforce_core 2 = 0

gen labforce_broad = cond(inrange(dlabforce, 1, 5), 1, 2)
recode labforce_broad 2 = 0

gen lf = inrange(dlabforce, 1, 5)
label define lf 1 "Economically Active" 0 "Not Economically Active"
label value lf lf

replace employment = . if labforce_broad == 0

* Core unemployment
gen unemp = (employment == 0) if employment != .
gen unemp_core = unemp
replace unemp_core = . if labforce_core == 0

*-----------------------------------------------------------
* Sector and Work Variables
*-----------------------------------------------------------
gen sector9 = klui9
    replace sector9 = . if sector9 == 0
	
recode kbli2009_2 (1/3 = 1) (5/9 = 2) ///
														(10/33 = 3) (35 = 4) ///
														(36/39 = 5) (41/43 = 6) ///
														(45/47 = 7) (49/53 = 8) ///
														(55/56 = 9) (58/63 = 10) ///
														(64/66 = 11) (68 = 12) ///
														(69/82 = 13) (84 = 14) ///
														(85 = 15) (86/88 = 16) ///
														(90/99 = 17) (0 = 18), ///
														gen(sector17)
														
gen work_informal = inlist(b5_r12, 1, 2, 5, 6, 7)
gen work_status   = b5_r12
gen work_certif   = (b5_r1c == 1)
    replace work_certif = . if lf == 0
gen work_whitecoll = inrange(kbji2000, 1, 5)

*-----------------------------------------------------------
* Non-Labor Force Activity Dummies
*-----------------------------------------------------------
gen act_school = ((b5_r2a2 == 1 | b5_r2a2 == 2) & b5_r2b == 2 & lf == 0)
gen act_household = ((b5_r2a3 == 1 | b5_r2a3 == 2) & b5_r2b == 3 & lf == 0)
gen act_others = ((b5_r2a4 == 1 | b5_r2a4 == 2) & b5_r2b == 4 & lf == 0)
gen act_neet = 0
replace act_neet = 1 if b5_r2a1 == 2 & b5_r2a2 == 2
replace act_neet = 0 if act_school == 1
replace act_neet = . if age >= 25 | age <= 14

*-----------------------------------------------------------
* Work Outcome Variables
*-----------------------------------------------------------
gen work_hours = b5_r11
gen work_earnings = b5_r13a + b5_r13b
    replace work_earnings = 0 if work_earnings < 0
gen work_wage = (b5_r13a + b5_r13b) if b5_r12 == 4
    replace work_wage = 0 if work_wage < 0
gen work_jobdur = (b5_r21a * 12) + b5_r21b

*-----------------------------------------------------------
* Recodes and Derived Variables
*-----------------------------------------------------------
recode educ 1/4 = 1 5/11 = 2 12/16 = 3, generate(educ_group)
recode work_jobdur 0/3 = 1 4/12 = 2 12/24 = 3 25/9999 = 4, gen(work_jobdur_cat)

gen school_years = .
replace school_years = 0 if educ == 0
replace school_years = 0 if educ == 1
replace school_years = 6 if educ == 2
replace school_years = 9 if educ == 3
replace school_years = 9 if educ == 4
replace school_years = 12 if educ == 5
replace school_years = 12 if educ == 6
replace school_years = 14 if educ == 7
replace school_years = 15 if educ == 8
replace school_years = 16 if educ == 9

*-----------------------------------------------------------
* Job Search Duration Dummies
*-----------------------------------------------------------
la de searchdur 1 "1. <=3 bulan" 2 "2. 4-12 bulan" 3 "3. 13-24 bulan" 4 "4. >24 bulan"
la val work_jobdur_cat searchdur

forval x = 1/4 {
    gen work_searchdur_`x' = (work_jobdur_cat == `x')
    replace work_searchdur_`x' = . if lf == 0 | work_jobdur_cat == .
}

foreach var of varlist work_hours work_earnings work_wage {
    replace `var' = . if unemp == 1 | lf == 0
}

*-----------------------------------------------------------
* Finalize and Save 2015 Data
*-----------------------------------------------------------
gen year = `year'
// save $output/temp_sakernas_`year', replace

*-----------------------------------------------------------
* 2015 Clean Data (standard)
*-----------------------------------------------------------
keep prov`year' wt urban male age educ unemp employment lf school_years sector9 sector17 work_informal work_status ///
     act_neet act_school act_household act_others work_hours work_whitecoll work_earnings work_wage work_jobdur* ///
     educ_group work_searchdur_* year work_certif

**---------------------------------------------------------------------------
** Working Hours, Underemployment, Status, and Formality Indicators (2015)
** Raw inputs: hours=b5_r8b  status=b5_r12  occupation=kbji2000  involuntary=(b5_r4, b5_r7)
**---------------------------------------------------------------------------

* hour: total working hours of all jobs (week)
cap confirm variable b5_r8b
if !_rc {
    cap drop hour
    gen hour = b5_r8b if employment == 1
}
else {
    cap gen hour = .
}

* underemp: hour<35 & employed
cap drop underemp
gen underemp = 1 if hour < 35 & hour > 0
replace underemp = 0 if hour == 0
replace underemp = 0 if hour >= 35 & hour != .

* underemp_invol & underemp_vol (legacy formula)
cap drop underemp_invol underemp_vol
gen underemp_invol = .
cap confirm variable b5_r4
local has_i1 = !_rc
cap confirm variable b5_r7
local has_i2 = !_rc
if `has_i1' & `has_i2' {
    replace underemp_invol = 0 if underemp == 1
    replace underemp_invol = 1 if (b5_r4 == 1 | b5_r7 == 1) & underemp == 1
}
gen underemp_vol = .
replace underemp_vol = 1 if underemp == 1 & underemp_invol == 0
replace underemp_vol = 0 if underemp == 1 & underemp_invol == 1

* hour decomposed
cap drop hour_under hour_vol hour_invol
gen hour_under = hour if underemp == 1
gen hour_vol   = hour if underemp_vol == 1
gen hour_invol = hour if underemp_invol == 1

* status (employment status, 1-7)
cap drop status
cap confirm variable b5_r12
if !_rc {
    gen status = b5_r12 if employment == 1
    replace status = . if status == 0
}
else {
    gen status = .
}

* worktype (1-digit code; take first digit if multi-digit)
cap drop worktype
cap confirm variable kbji2000
if !_rc {
    gen _wt_raw = kbji2000 if employment == 1
    gen worktype = .
    replace worktype = real(substr(string(int(abs(_wt_raw))), 1, 1)) if _wt_raw != . & _wt_raw > 0
    replace worktype = _wt_raw if abs(_wt_raw) < 10 & _wt_raw != .
    drop _wt_raw
}
else {
    gen worktype = .
}

* formal_simple: status in (3,4)
cap drop formal_simple
gen formal_simple = inrange(status, 3, 4) if status != . & employment == 1

* formal_new: wrktype2011 matrix
cap drop formal_new
gen formal_new = .
replace formal_new = wrktype2011[status, worktype] ///
    if status != . & worktype != . & employment == 1 ///
    & inrange(status, 1, 7) & inrange(worktype, 1, 8)

* formal_old: formal_new + casual workers in agri/construction
cap drop formal_old
gen formal_old = formal_new
replace formal_old = 1 if (status == 5 & sector9 == 1) & employment == 1
replace formal_old = 1 if (status == 6 & sector9 == 5) & employment == 1

* labels
cap label var hour           "working hours per week (all jobs combined)"
cap label var underemp       "underemployed dummy (less than 35 hours per week)"
cap label var underemp_invol "involuntary underemployment"
cap label var underemp_vol   "voluntary underemployment"
cap label var hour_under     "weekly hours among underemployed"
cap label var hour_vol       "weekly hours among voluntary underemployed"
cap label var hour_invol     "weekly hours among involuntary underemployed"
cap label var status         "main employment status"
cap label var worktype       "main occupation (1-digit KBJI)"
cap label var formal_simple  "simplified formality (employee or assisted employer)"
cap label var formal_new     "formality (wrktype2011 matrix)"
cap label var formal_old     "formality including casual workers in agriculture and construction"
**---------------------------------------------------------------------------
** Additional Employment Indicators
**---------------------------------------------------------------------------
cap drop employee casual_worker potential_exp
gen employee = work_status == 4 if work_status != .
gen casual_worker = inlist(work_status, 5, 6) if work_status != .
gen potential_exp = age - school_years if age != . & school_years != .
cap label var employee      "employee dummy"
cap label var casual_worker "casual worker dummy"
cap label var potential_exp "potential work experience"

**---------------------------------------------------------------------------
** Education Major Classification
**---------------------------------------------------------------------------
cap drop educ_major
capture confirm variable b5_r1b
if !_rc {
    gen educ_major = b5_r1b
    /* Recode rules by education level:
       Different recode rules for different education levels (SMA vs Diploma/S1+)
       Codes: 0=SMP/under, 1=Sosio-hum, 2=Medika-FKH, 3=Pertanian, 4=Sains, 5=Teknik,
              6=Pendidikan, 7=Lainnya, 998=No info, 999=Other */
    capture confirm variable b5_r1a
    if !_rc {
        recode educ_major (38 41 43/45 = 1) (42 = 4) (37 39/40 = 5) (27 46 = 998) (50 = 999) if inrange(b5_r1a, 6, 7)
        recode educ_major (2/5 7/10 12 15/16 18 23 38 41 42/45 = 1) (13 = 2) (14 19 20 22 = 3) (6 21 24/25 42 = 4) (11 17 37 39 40 = 5) (26 = 6) (1 = 7) (27 46 = 998) (50 = 999) if b5_r1a == 8
        recode educ_major (2/5 7/10 12 15/16 18 23 38 41 42/45 = 1) (13 = 2) (14 19 20 22 = 3) (6 21 24/25 42 = 4) (11 17 37 39 40 = 5) (26 = 6) (1 = 7) (27 46 = 998) (50 = 999) if b5_r1a == 9
        recode educ_major (2/5 7/10 12 15/16 18 23 38 41 42/45 = 1) (13 = 2) (14 19 20 22 = 3) (6 21 24/25 42 = 4) (11 17 37 39 40 = 5) (26 = 6) (1 = 7) (27 46 = 998) (50 = 999) if inlist(b5_r1a, 10, 11, 12, 13, 14)
    }
    label define educ_major 0 "No major (SMP or under)" 1 "Sosio-humaniora" 2 "Medika-FKH" ///
                            3 "Pertanian" 4 "Sains" 5 "Teknik" 6 "Pendidikan" 7 "Lainnya" ///
                            998 "No information" 999 "Other", replace
    label values educ_major educ_major
    label var educ_major "education major (post-2010 surveys)"
}



save $clean/clean_sakernas_`year', replace

/*************************
 * End of Sakernas 2015
 ************************/

/*************************
 * Sakernas 2016 (standard)
 ************************/

clear
set more off
local year = 2016
use $source/sakernas_`year', clear

*-----------------------------------------------------------
* Basic Variables and Filter
*-----------------------------------------------------------
gen prov`year' = kode_prov
gen wt         = weight
gen urban      = (klasifikas == 1)
gen male       = (b4_k4 == 1)
gen age        = b4_k6         // WARNING: AGE OUTSIDE LF DETECTED
gen educ       = b5_r1a
keep if age >= 15

*-----------------------------------------------------------
* Define Employment Using standard Indicators
*-----------------------------------------------------------
gen employment = (b5_r5a1 == 1 | b5_r6 == 1)

* Define additional work-status indicators
gen caker1 = (b5_r11 == 1)   // looking for work
gen caker2 = (b5_r12 == 1)   // establishing new business/firm
gen caker3 = (b5_r16a == 3)  // hopeless of job
gen caker4 = (b5_r16a == 1 | b5_r16a == 2)  // have a job in future start

gen dlabforce = cond(employment == 1, 1, ///
                cond(caker1 == 1, 2, ///
                cond(caker2 == 1, 3, ///
                cond(caker3 == 1, 4, ///
                cond(caker4 == 1, 5, ///
                cond(b5_r5b == 2, 6, ///
                cond(b5_r5b == 3, 7, 8)))))))
label define dlabforce 1 "Working" 2 "Looking" 3 "Establishing new business" 4 "Discouraged" 5 "Future job arranged" 6 "Student" 7 "Housekeeping" 8 "Others"
label val dlabforce dlabforce

*-----------------------------------------------------------
* Define Labor Force Using WB Definitions
*-----------------------------------------------------------
gen labforce_core = cond(inrange(dlabforce, 1, 2), 1, 2)
recode labforce_core 2 = 0

gen labforce_broad = cond(inrange(dlabforce, 1, 5), 1, 2)
recode labforce_broad 2 = 0

gen lf = inrange(dlabforce, 1, 5)
label define lf 1 "Economically Active" 0 "Not Economically Active"
label value lf lf

replace employment = . if labforce_broad == 0

* Core unemployment
gen unemp = (employment == 0) if employment != .
gen unemp_core = unemp
replace unemp_core = . if labforce_core == 0

*-----------------------------------------------------------
* Sector and Work Variables
*-----------------------------------------------------------
gen sector9 = b5_r19_9
    replace sector9 = . if sector9 == 0
gen sector17 = b5_r19_17
	

gen work_informal = inlist(b5_r23, 1, 2, 5, 6, 7)
gen work_status   = b5_r23
gen work_certif   = (b5_r1c == 1)
    replace work_certif = . if lf == 0
gen work_whitecoll = inrange(b5_r20_2_a, 1, 5)

*-----------------------------------------------------------
* Non-Labor Force Activity Dummies
*-----------------------------------------------------------
gen act_school = ((b5_r5a2 == 3 | b5_r5a2 == 4) & b5_r5b == 2 & lf == 0)
gen act_household = ((b5_r5a3 == 1 | b5_r5a3 == 2) & b5_r5b == 3 & lf == 0)
gen act_others = ((b5_r5a4 == 3 | b5_r5a4 == 4) & b5_r5b == 4 & lf == 0)
gen act_neet = 0
replace act_neet = 1 if b5_r5a1 == 2 & b5_r5a2 == 4
replace act_neet = 0 if act_school == 1
replace act_neet = . if age >= 25 | age <= 14

*-----------------------------------------------------------
* Work Outcome Variables
*-----------------------------------------------------------
gen work_hours = b5_r22a
    replace work_hours = . if employment != 1
gen work_earnings = b5_r26a + b5_r26b
    replace work_earnings = 0 if work_earnings < 0
    replace work_earnings = . if employment != 1
gen work_wage = (b5_r26a + b5_r26b) if b5_r23 == 4
    replace work_wage = 0 if work_wage < 0
    replace work_wage = . if employment != 1
gen work_jobdur = b5_r13
    replace work_jobdur = . if work_jobdur == 0

*-----------------------------------------------------------
* Recodes and Derived Variables
*-----------------------------------------------------------
recode educ 1/4 = 1 5/11 = 2 12/16 = 3, generate(educ_group)
recode work_jobdur 0/3 = 1 4/12 = 2 12/24 = 3 25/9999 = 4, gen(work_jobdur_cat)

gen school_years = .
replace school_years = 0 if educ == 1
replace school_years = 0 if educ == 2
replace school_years = 6 if educ == 3
replace school_years = 6 if educ == 4
replace school_years = 9 if educ == 5
replace school_years = 9 if educ == 6
replace school_years = 9 if educ == 7
replace school_years = 12 if educ == 8
replace school_years = 12 if educ == 9
replace school_years = 12 if educ == 10
replace school_years = 14 if educ == 11
replace school_years = 15 if educ == 12
replace school_years = 16 if educ == 13
replace school_years = 20 if educ == 14

*-----------------------------------------------------------
* Job Search Duration Dummies
*-----------------------------------------------------------
la de searchdur 1 "1. <=3 bulan" 2 "2. 4-12 bulan" 3 "3. 13-24 bulan" 4 "4. >24 bulan"
la val work_jobdur_cat searchdur

forval x = 1/4 {
    gen work_searchdur_`x' = (work_jobdur_cat == `x')
    replace work_searchdur_`x' = . if lf == 0 | work_jobdur_cat == .
}

foreach var of varlist work_hours work_earnings work_wage {
    replace `var' = . if unemp == 1 | lf == 0
}

*-----------------------------------------------------------
* Finalize and Save 2016 Data
*-----------------------------------------------------------
gen year = `year'
// save $output/temp_sakernas_`year', replace

*-----------------------------------------------------------
* 2016 Clean Data (standard)
*-----------------------------------------------------------
keep prov`year' wt urban male age educ unemp employment lf school_years sector9 sector17 work_informal work_status ///
     act_neet act_school act_household act_others work_hours work_whitecoll work_earnings work_wage work_jobdur* ///
     educ_group work_searchdur_* year work_certif

**---------------------------------------------------------------------------
** Working Hours, Underemployment, Status, and Formality Indicators (2016)
** Raw inputs: hours=b5_r37a  status=b5_r23  occupation=b5_r20_200  involuntary=(b5_r11, b5_r17a)
**---------------------------------------------------------------------------

* hour: total working hours of all jobs (week)
cap confirm variable b5_r37a
if !_rc {
    cap drop hour
    gen hour = b5_r37a if employment == 1
}
else {
    cap gen hour = .
}

* underemp: hour<35 & employed
cap drop underemp
gen underemp = 1 if hour < 35 & hour > 0
replace underemp = 0 if hour == 0
replace underemp = 0 if hour >= 35 & hour != .

* underemp_invol & underemp_vol (legacy formula)
cap drop underemp_invol underemp_vol
gen underemp_invol = .
cap confirm variable b5_r11
local has_i1 = !_rc
cap confirm variable b5_r17a
local has_i2 = !_rc
if `has_i1' & `has_i2' {
    replace underemp_invol = 0 if underemp == 1
    replace underemp_invol = 1 if (b5_r11 == 1 | b5_r17a == 1) & underemp == 1
}
gen underemp_vol = .
replace underemp_vol = 1 if underemp == 1 & underemp_invol == 0
replace underemp_vol = 0 if underemp == 1 & underemp_invol == 1

* hour decomposed
cap drop hour_under hour_vol hour_invol
gen hour_under = hour if underemp == 1
gen hour_vol   = hour if underemp_vol == 1
gen hour_invol = hour if underemp_invol == 1

* status (employment status, 1-7)
cap drop status
cap confirm variable b5_r23
if !_rc {
    gen status = b5_r23 if employment == 1
    replace status = . if status == 0
}
else {
    gen status = .
}

* worktype (1-digit code; take first digit if multi-digit)
cap drop worktype
cap confirm variable b5_r20_200
if !_rc {
    gen _wt_raw = b5_r20_200 if employment == 1
    gen worktype = .
    replace worktype = real(substr(string(int(abs(_wt_raw))), 1, 1)) if _wt_raw != . & _wt_raw > 0
    replace worktype = _wt_raw if abs(_wt_raw) < 10 & _wt_raw != .
    drop _wt_raw
}
else {
    gen worktype = .
}

* formal_simple: status in (3,4)
cap drop formal_simple
gen formal_simple = inrange(status, 3, 4) if status != . & employment == 1

* formal_new: wrktype2011 matrix
cap drop formal_new
gen formal_new = .
replace formal_new = wrktype2011[status, worktype] ///
    if status != . & worktype != . & employment == 1 ///
    & inrange(status, 1, 7) & inrange(worktype, 1, 8)

* formal_old: formal_new + casual workers in agri/construction
cap drop formal_old
gen formal_old = formal_new
replace formal_old = 1 if (status == 5 & sector9 == 1) & employment == 1
replace formal_old = 1 if (status == 6 & sector9 == 5) & employment == 1

* labels
cap label var hour           "working hours per week (all jobs combined)"
cap label var underemp       "underemployed dummy (less than 35 hours per week)"
cap label var underemp_invol "involuntary underemployment"
cap label var underemp_vol   "voluntary underemployment"
cap label var hour_under     "weekly hours among underemployed"
cap label var hour_vol       "weekly hours among voluntary underemployed"
cap label var hour_invol     "weekly hours among involuntary underemployed"
cap label var status         "main employment status"
cap label var worktype       "main occupation (1-digit KBJI)"
cap label var formal_simple  "simplified formality (employee or assisted employer)"
cap label var formal_new     "formality (wrktype2011 matrix)"
cap label var formal_old     "formality including casual workers in agriculture and construction"
**---------------------------------------------------------------------------
** Additional Employment Indicators
**---------------------------------------------------------------------------
cap drop employee casual_worker potential_exp
gen employee = work_status == 4 if work_status != .
gen casual_worker = inlist(work_status, 5, 6) if work_status != .
gen potential_exp = age - school_years if age != . & school_years != .
cap label var employee      "employee dummy"
cap label var casual_worker "casual worker dummy"
cap label var potential_exp "potential work experience"

**---------------------------------------------------------------------------
** Education Major Classification
**---------------------------------------------------------------------------
cap drop educ_major
capture confirm variable b5_r1b
if !_rc {
    gen educ_major = b5_r1b
    /* Recode rules by education level:
       Different recode rules for different education levels (SMA vs Diploma/S1+)
       Codes: 0=SMP/under, 1=Sosio-hum, 2=Medika-FKH, 3=Pertanian, 4=Sains, 5=Teknik,
              6=Pendidikan, 7=Lainnya, 998=No info, 999=Other */
    capture confirm variable b5_r1a
    if !_rc {
        recode educ_major (38 41 43/45 = 1) (42 = 4) (37 39/40 = 5) (27 46 = 998) (50 = 999) if inrange(b5_r1a, 6, 7)
        recode educ_major (2/5 7/10 12 15/16 18 23 38 41 42/45 = 1) (13 = 2) (14 19 20 22 = 3) (6 21 24/25 42 = 4) (11 17 37 39 40 = 5) (26 = 6) (1 = 7) (27 46 = 998) (50 = 999) if b5_r1a == 8
        recode educ_major (2/5 7/10 12 15/16 18 23 38 41 42/45 = 1) (13 = 2) (14 19 20 22 = 3) (6 21 24/25 42 = 4) (11 17 37 39 40 = 5) (26 = 6) (1 = 7) (27 46 = 998) (50 = 999) if b5_r1a == 9
        recode educ_major (2/5 7/10 12 15/16 18 23 38 41 42/45 = 1) (13 = 2) (14 19 20 22 = 3) (6 21 24/25 42 = 4) (11 17 37 39 40 = 5) (26 = 6) (1 = 7) (27 46 = 998) (50 = 999) if inlist(b5_r1a, 10, 11, 12, 13, 14)
    }
    label define educ_major 0 "No major (SMP or under)" 1 "Sosio-humaniora" 2 "Medika-FKH" ///
                            3 "Pertanian" 4 "Sains" 5 "Teknik" 6 "Pendidikan" 7 "Lainnya" ///
                            998 "No information" 999 "Other", replace
    label values educ_major educ_major
    label var educ_major "education major (post-2010 surveys)"
}



save $clean/clean_sakernas_`year', replace

/*************************
 * End of Sakernas 2016
 ************************/
 
 /*************************
 * Sakernas 2017
 ************************/

clear
set more off
local year = 2017
use $source/sakernas_`year', clear

*-----------------------------------------------------------
* Basic Variables and Identifiers
*-----------------------------------------------------------
gen prov`year' = kode_prov
gen wt         = weight
gen urban      = (klasifikas == 1)
gen male       = (b4_k4 == 1)
gen age        = b4_k6         // WARNING: AGE OUTSIDE LF DETECTED
gen educ       = b5_r1a
keep if age >= 15

*-----------------------------------------------------------
* Employment and Labor Force (Using Caker Variables)
*-----------------------------------------------------------
gen employment = (b5_r5a1 == 1 | b5_r6 == 1)
gen caker1  = (b5_r15a == 1)  // looking for work
gen caker2  = (b5_r15b == 1)  // establishing new business/firm
gen caker3  = (b5_r20a == 3)  // hopeless of job
gen caker4  = (b5_r20a == 1 | b5_r20a == 2)  // have a job in future start

gen dlabforce = cond(employment == 1, 1, ///
                  cond(caker1 == 1, 2, ///
                  cond(caker2 == 1, 3, ///
                  cond(caker3 == 1, 4, ///
                  cond(caker4 == 1, 5, ///
                  cond(b5_r5b == 2, 6, ///
                  cond(b5_r5b == 3, 7, 8)))))))
label define dlabforce 1 "Working" 2 "Looking" 3 "Establishing new business" 4 "Discouraged" 5 "Future job arranged" 6 "Student" 7 "Housekeeping" 8 "Others"
label val dlabforce dlabforce

* Define labor force components (core & broad)
gen labforce_core = cond(inrange(dlabforce, 1, 2), 1, 2)
recode labforce_core 2 = 0

gen labforce_broad = cond(inrange(dlabforce, 1, 5), 1, 2)
recode labforce_broad 2 = 0

gen lf = inrange(dlabforce, 1, 5)
label define lf 1 "Economically Active" 0 "Not Economically Active"
label value lf lf

replace employment = . if labforce_broad == 0

* Core unemployment
gen unemp = (employment == 0) if employment != .
gen unemp_core = unemp
replace unemp_core = . if labforce_core == 0

*-----------------------------------------------------------
* Sector and Work-Related Variables
*-----------------------------------------------------------
gen sector9 = b5_r23_9
replace sector9 = . if sector9 == 0
gen sector17 = b5_r23_17

gen work_informal = inlist(b5_r27a, 1, 2, 5, 6, 7)
gen work_status   = b5_r27a
gen work_certif   = (b5_r1d == 1)
    replace work_certif = . if lf == 0
gen work_whitecoll = inrange(b5_r24_200, 1, 5)

gen act_school = ((b5_r5a2 == 3 | b5_r5a2 == 4) & b5_r5b == 2 & lf == 0)
gen act_household = ((b5_r5a3 == 1 | b5_r5a3 == 2) & b5_r5b == 3 & lf == 0)
gen act_others = ((b5_r5a4 == 3 | b5_r5a4 == 4) & b5_r5b == 4 & lf == 0)
gen act_neet = 0
replace act_neet = 1 if b5_r5a1 == 2 & b5_r5a2 == 4
replace act_neet = 0 if act_school == 1
replace act_neet = . if age >= 25 | age <= 14

*-----------------------------------------------------------
* Work Outcome Variables
*-----------------------------------------------------------
gen work_hours = b5_r26a
    replace work_hours = . if employment != 1
gen work_earnings = .
replace work_earnings = b5_r30b1 + b5_r30b2 if inlist(b5_r27a, 1, 5, 6)
replace work_earnings = b5_r30c11 + b5_r30c12 + b5_r30c21 + b5_r30c22 if inlist(b5_r27a, 4)
replace work_earnings = 0 if work_earnings < 0
replace work_earnings = . if employment != 1

gen work_wage = b5_r30c11 + b5_r30c12 + b5_r30c21 + b5_r30c22 if inlist(b5_r27a, 4)
replace work_wage = 0 if work_wage < 0
replace work_wage = . if employment != 1

gen work_jobdur = b5_r17
    replace work_jobdur = . if work_jobdur == 0

*-----------------------------------------------------------
* Recodes and Derived Variables
*-----------------------------------------------------------
recode educ 1/4 = 1 5/11 = 2 12/16 = 3, generate(educ_group)
recode work_jobdur 0/3 = 1 4/12 = 2 12/24 = 3 25/9999 = 4, gen(work_jobdur_cat)

gen school_years = .
replace school_years = 0 if educ == 1
replace school_years = 6 if educ == 2
replace school_years = 6 if educ == 3
replace school_years = 6 if educ == 4
replace school_years = 9 if educ == 5
replace school_years = 9 if educ == 6
replace school_years = 9 if educ == 7
replace school_years = 12 if educ == 8
replace school_years = 12 if educ == 9
replace school_years = 12 if educ == 10
replace school_years = 12 if educ == 11
replace school_years = 14 if educ == 12
replace school_years = 15 if educ == 13
replace school_years = 16 if educ == 14
replace school_years = 18 if educ == 15
replace school_years = 20 if educ == 16

*-----------------------------------------------------------
* Job Search Duration Dummies
*-----------------------------------------------------------
la de searchdur 1 "1. <=3 bulan" 2 "2. 4-12 bulan" 3 "3. 13-24 bulan" 4 "4. >24 bulan"
la val work_jobdur_cat searchdur

forval x = 1/4 {
    gen work_searchdur_`x' = (work_jobdur_cat == `x')
    replace work_searchdur_`x' = . if lf == 0 | work_jobdur_cat == .
}

foreach var of varlist work_hours work_earnings work_wage {
    replace `var' = . if unemp == 1 | lf == 0
}

*-----------------------------------------------------------
* Finalize and Save 2017 Data
*-----------------------------------------------------------
gen year = `year'
// save $output/temp_sakernas_`year', replace

*-----------------------------------------------------------
* 2017 Clean Data (standard)
*-----------------------------------------------------------
keep prov`year' wt urban male age educ unemp employment lf school_years sector9 sector17 work_informal work_status ///
     act_neet act_school act_household act_others work_hours work_whitecoll work_earnings work_wage work_jobdur* ///
     educ_group work_searchdur_* year work_certif

**---------------------------------------------------------------------------
** Working Hours, Underemployment, Status, and Formality Indicators (2017)
** Raw inputs: hours=b5_r43a  status=b5_r27a  occupation=b5_r24_198  involuntary=(b5_r15a, b5_r21a)
**---------------------------------------------------------------------------

* hour: total working hours of all jobs (week)
cap confirm variable b5_r43a
if !_rc {
    cap drop hour
    gen hour = b5_r43a if employment == 1
}
else {
    cap gen hour = .
}

* underemp: hour<35 & employed
cap drop underemp
gen underemp = 1 if hour < 35 & hour > 0
replace underemp = 0 if hour == 0
replace underemp = 0 if hour >= 35 & hour != .

* underemp_invol & underemp_vol (legacy formula)
cap drop underemp_invol underemp_vol
gen underemp_invol = .
cap confirm variable b5_r15a
local has_i1 = !_rc
cap confirm variable b5_r21a
local has_i2 = !_rc
if `has_i1' & `has_i2' {
    replace underemp_invol = 0 if underemp == 1
    replace underemp_invol = 1 if (b5_r15a == 1 | b5_r21a == 1) & underemp == 1
}
gen underemp_vol = .
replace underemp_vol = 1 if underemp == 1 & underemp_invol == 0
replace underemp_vol = 0 if underemp == 1 & underemp_invol == 1

* hour decomposed
cap drop hour_under hour_vol hour_invol
gen hour_under = hour if underemp == 1
gen hour_vol   = hour if underemp_vol == 1
gen hour_invol = hour if underemp_invol == 1

* status (employment status, 1-7)
cap drop status
cap confirm variable b5_r27a
if !_rc {
    gen status = b5_r27a if employment == 1
    replace status = . if status == 0
}
else {
    gen status = .
}

* worktype (1-digit code; take first digit if multi-digit)
cap drop worktype
cap confirm variable b5_r24_198
if !_rc {
    gen _wt_raw = b5_r24_198 if employment == 1
    gen worktype = .
    replace worktype = real(substr(string(int(abs(_wt_raw))), 1, 1)) if _wt_raw != . & _wt_raw > 0
    replace worktype = _wt_raw if abs(_wt_raw) < 10 & _wt_raw != .
    drop _wt_raw
}
else {
    gen worktype = .
}

* formal_simple: status in (3,4)
cap drop formal_simple
gen formal_simple = inrange(status, 3, 4) if status != . & employment == 1

* formal_new: wrktype2011 matrix
cap drop formal_new
gen formal_new = .
replace formal_new = wrktype2011[status, worktype] ///
    if status != . & worktype != . & employment == 1 ///
    & inrange(status, 1, 7) & inrange(worktype, 1, 8)

* formal_old: formal_new + casual workers in agri/construction
cap drop formal_old
gen formal_old = formal_new
replace formal_old = 1 if (status == 5 & sector9 == 1) & employment == 1
replace formal_old = 1 if (status == 6 & sector9 == 5) & employment == 1

* labels
cap label var hour           "working hours per week (all jobs combined)"
cap label var underemp       "underemployed dummy (less than 35 hours per week)"
cap label var underemp_invol "involuntary underemployment"
cap label var underemp_vol   "voluntary underemployment"
cap label var hour_under     "weekly hours among underemployed"
cap label var hour_vol       "weekly hours among voluntary underemployed"
cap label var hour_invol     "weekly hours among involuntary underemployed"
cap label var status         "main employment status"
cap label var worktype       "main occupation (1-digit KBJI)"
cap label var formal_simple  "simplified formality (employee or assisted employer)"
cap label var formal_new     "formality (wrktype2011 matrix)"
cap label var formal_old     "formality including casual workers in agriculture and construction"
**---------------------------------------------------------------------------
** Additional Employment Indicators
**---------------------------------------------------------------------------
cap drop employee casual_worker potential_exp
gen employee = work_status == 4 if work_status != .
gen casual_worker = inlist(work_status, 5, 6) if work_status != .
gen potential_exp = age - school_years if age != . & school_years != .
cap label var employee      "employee dummy"
cap label var casual_worker "casual worker dummy"
cap label var potential_exp "potential work experience"

**---------------------------------------------------------------------------
** Education Major Classification
**---------------------------------------------------------------------------
cap drop educ_major
capture confirm variable b5_r1b
if !_rc {
    gen educ_major = b5_r1b
    /* Recode rules by education level:
       Different recode rules for different education levels (SMA vs Diploma/S1+)
       Codes: 0=SMP/under, 1=Sosio-hum, 2=Medika-FKH, 3=Pertanian, 4=Sains, 5=Teknik,
              6=Pendidikan, 7=Lainnya, 998=No info, 999=Other */
    capture confirm variable b5_r1a
    if !_rc {
        recode educ_major (38 41 43/45 = 1) (42 = 4) (37 39/40 = 5) (27 46 = 998) (50 = 999) if inrange(b5_r1a, 6, 7)
        recode educ_major (2/5 7/10 12 15/16 18 23 38 41 42/45 = 1) (13 = 2) (14 19 20 22 = 3) (6 21 24/25 42 = 4) (11 17 37 39 40 = 5) (26 = 6) (1 = 7) (27 46 = 998) (50 = 999) if b5_r1a == 8
        recode educ_major (2/5 7/10 12 15/16 18 23 38 41 42/45 = 1) (13 = 2) (14 19 20 22 = 3) (6 21 24/25 42 = 4) (11 17 37 39 40 = 5) (26 = 6) (1 = 7) (27 46 = 998) (50 = 999) if b5_r1a == 9
        recode educ_major (2/5 7/10 12 15/16 18 23 38 41 42/45 = 1) (13 = 2) (14 19 20 22 = 3) (6 21 24/25 42 = 4) (11 17 37 39 40 = 5) (26 = 6) (1 = 7) (27 46 = 998) (50 = 999) if inlist(b5_r1a, 10, 11, 12, 13, 14)
    }
    label define educ_major 0 "No major (SMP or under)" 1 "Sosio-humaniora" 2 "Medika-FKH" ///
                            3 "Pertanian" 4 "Sains" 5 "Teknik" 6 "Pendidikan" 7 "Lainnya" ///
                            998 "No information" 999 "Other", replace
    label values educ_major educ_major
    label var educ_major "education major (post-2010 surveys)"
}



save $clean/clean_sakernas_`year', replace

/*************************
 * End of Sakernas 2017
 ************************/

 /*************************
 * Sakernas 2018
 * (Using WB matrix for sector classification)
 ************************/

clear
set more off
local year = 2018
use $source/sakernas_backcast_`year', clear

*-----------------------------------------------------------
* Basic Variables and Identifiers
*-----------------------------------------------------------
gen prov`year' = kode_prov
gen wt         = final_weig
gen urban      = (klasifikas == 1)
gen male       = (b4_k6 == 1)
gen age        = b4_k8         // WARNING: AGE OUTSIDE LF DETECTED
gen educ       = b5_r1a
gen employment = (b5_r5a1 == 1 | b5_r6 == 1)
keep if age >= 15

*-----------------------------------------------------------
* Unemployment and Labor Force
*-----------------------------------------------------------
gen unemp = .
replace unemp = 1 if b5_r5a1 == 2 & b5_r6 == 2 & b5_r15a == 1 & employment == 0
replace unemp = 1 if b5_r5a1 == 2 & b5_r6 == 2 & b5_r15b == 1 & employment == 0
replace unemp = 1 if b5_r5a1 == 2 & inlist(b5_r20a, 1, 2, 3) & employment == 0
replace unemp = 0 if unemp != 1

gen lf = .
replace lf = 1 if employment == 1 | unemp == 1
replace lf = 0 if age < 15
replace lf = 0 if lf != 1
replace unemp = . if lf == 0
replace employment = . if lf == 0

*-----------------------------------------------------------
* Sector Classification (standard)
*-----------------------------------------------------------
* Create 17-sector variable then recode to 9-sector format
gen sector17 = b5_r23_sek
replace sector17 = . if sector17 == 0

* 9 sectors standard
#delim ;
	recode b5_r23_sek
		(0		= .)
		(1		= 1)
		(2		= 2)
		(3		= 3)
		(4/5	= 4)
		(6		= 5)
		(7 9	= 6)
		(8 10	= 7)
		(11/13	= 8)
		(14/17	= 9),
		gen(sector9);
#delim cr

label define sector9 1 "Agriculture, forestry, livestock and fishing" ///
                      2 "Mining and quarrying" ///
                      3 "Manufacturing" ///
                      4 "Electricity, gas, and water supply" ///
                      5 "Construction" ///
                      6 "Wholesale and retail trade, restaurants and hotels" ///
                      7 "Transportation, storage and communications" ///
                      8 "Finance, insurance, real estate and business services" ///
                      9 "Community, social and personal services" ///
                      10 "Others"
label values sector9 sector9

*-----------------------------------------------------------
* Work-Related Variables
*-----------------------------------------------------------
gen work_informal = inlist(b5_r27a, 1, 2, 5, 6, 7)
gen work_status   = b5_r27a
gen work_certif   = (b5_r1d == 1)
    replace work_certif = . if lf == 0
gen work_whitecoll = inrange(b5_r24_kji, 1, 5)

*-----------------------------------------------------------
* Non-Labor Force Activity Dummies
*-----------------------------------------------------------
gen act_school = (b5_r5a2 == 3 | b5_r5a2 == 4) & b5_r5b == 2 & lf == 0
gen act_household = (b5_r5a3 == 1 | b5_r5a3 == 2) & b5_r5b == 3 & lf == 0
gen act_others = (b5_r5a4 == 3 | b5_r5a4 == 4) & b5_r5b == 4 & lf == 0
gen act_neet = 0
replace act_neet = 1 if b5_r5a1 == 2 & b5_r5a2 == 4
replace act_neet = 0 if act_school == 1
replace act_neet = . if age >= 25 | age <= 14

*-----------------------------------------------------------
* Work Outcome Variables
*-----------------------------------------------------------
gen work_hours = b5_r26a
    replace work_hours = . if employment != 1
gen work_earnings = .
replace work_earnings = b5_r31b1 + b5_r31b2 if inlist(b5_r27a, 1, 5, 6)
replace work_earnings = b5_r31c1 + b5_r31c2 if inlist(b5_r27a, 4)
replace work_earnings = 0 if work_earnings < 0
replace work_earnings = . if employment != 1
gen work_wage = b5_r31c1 + b5_r31c2 if inlist(b5_r27a, 4)
replace work_wage = 0 if work_wage < 0
replace work_wage = . if employment != 1
gen work_jobdur = b5_r17
    replace work_jobdur = . if work_jobdur == 0

*-----------------------------------------------------------
* Recodes and Derived Variables
*-----------------------------------------------------------
recode educ 1/4 = 1 5/11 = 2 12/16 = 3, generate(educ_group)
recode work_jobdur 0/3 = 1 4/12 = 2 12/24 = 3 25/9999 = 4, gen(work_jobdur_cat)

gen school_years = .
replace school_years = 0 if educ == 1 | educ == 2
replace school_years = 6 if educ == 3
replace school_years = 9 if educ == 4
replace school_years = 9 if educ == 5
replace school_years = 12 if educ == 6
replace school_years = 12 if educ == 7
replace school_years = 14 if educ == 8
replace school_years = 15 if educ == 9
replace school_years = 16 if educ == 10
replace school_years = 20 if educ == 11

*-----------------------------------------------------------
* Job Search Duration Dummies
*-----------------------------------------------------------
la de searchdur 1 "1. <=3 bulan" 2 "2. 4-12 bulan" 3 "3. 13-24 bulan" 4 "4. >24 bulan"
la val work_jobdur_cat searchdur

forval x = 1/4 {
    gen work_searchdur_`x' = (work_jobdur_cat == `x')
    replace work_searchdur_`x' = . if lf == 0 | work_jobdur_cat == .
}

foreach var of varlist work_hours work_earnings work_wage {
    replace `var' = . if unemp == 1 | lf == 0
}

*-----------------------------------------------------------
* Finalize and Save 2018 Data
*-----------------------------------------------------------
gen year = `year'
// save $output/temp_sakernas_`year', replace

*-----------------------------------------------------------
* 2018 Clean Data (standard)
*-----------------------------------------------------------

keep prov`year' wt urban male age educ unemp employment lf school_years sector9 sector17 work_informal work_status ///
     act_neet act_school act_household act_others work_hours work_whitecoll work_earnings work_wage work_jobdur* ///
     educ_group work_searchdur_* year work_certif

**---------------------------------------------------------------------------
** Working Hours, Underemployment, Status, and Formality Indicators (2018)
** Raw inputs: hours=b5_r47a  status=b5_r27a  occupation=b5_r24_kji  involuntary=(b5_r15a, b5_r21a)
**---------------------------------------------------------------------------

* hour: total working hours of all jobs (week)
cap confirm variable b5_r47a
if !_rc {
    cap drop hour
    gen hour = b5_r47a if employment == 1
}
else {
    cap gen hour = .
}

* underemp: hour<35 & employed
cap drop underemp
gen underemp = 1 if hour < 35 & hour > 0
replace underemp = 0 if hour == 0
replace underemp = 0 if hour >= 35 & hour != .

* underemp_invol & underemp_vol (legacy formula)
cap drop underemp_invol underemp_vol
gen underemp_invol = .
cap confirm variable b5_r15a
local has_i1 = !_rc
cap confirm variable b5_r21a
local has_i2 = !_rc
if `has_i1' & `has_i2' {
    replace underemp_invol = 0 if underemp == 1
    replace underemp_invol = 1 if (b5_r15a == 1 | b5_r21a == 1) & underemp == 1
}
gen underemp_vol = .
replace underemp_vol = 1 if underemp == 1 & underemp_invol == 0
replace underemp_vol = 0 if underemp == 1 & underemp_invol == 1

* hour decomposed
cap drop hour_under hour_vol hour_invol
gen hour_under = hour if underemp == 1
gen hour_vol   = hour if underemp_vol == 1
gen hour_invol = hour if underemp_invol == 1

* status (employment status, 1-7)
cap drop status
cap confirm variable b5_r27a
if !_rc {
    gen status = b5_r27a if employment == 1
    replace status = . if status == 0
}
else {
    gen status = .
}

* worktype (1-digit code; take first digit if multi-digit)
cap drop worktype
cap confirm variable b5_r24_kji
if !_rc {
    gen _wt_raw = b5_r24_kji if employment == 1
    gen worktype = .
    replace worktype = real(substr(string(int(abs(_wt_raw))), 1, 1)) if _wt_raw != . & _wt_raw > 0
    replace worktype = _wt_raw if abs(_wt_raw) < 10 & _wt_raw != .
    drop _wt_raw
}
else {
    gen worktype = .
}

* formal_simple: status in (3,4)
cap drop formal_simple
gen formal_simple = inrange(status, 3, 4) if status != . & employment == 1

* formal_new: wrktype2011 matrix
cap drop formal_new
gen formal_new = .
replace formal_new = wrktype2011[status, worktype] ///
    if status != . & worktype != . & employment == 1 ///
    & inrange(status, 1, 7) & inrange(worktype, 1, 8)

* formal_old: formal_new + casual workers in agri/construction
cap drop formal_old
gen formal_old = formal_new
replace formal_old = 1 if (status == 5 & sector9 == 1) & employment == 1
replace formal_old = 1 if (status == 6 & sector9 == 5) & employment == 1

* labels
cap label var hour           "working hours per week (all jobs combined)"
cap label var underemp       "underemployed dummy (less than 35 hours per week)"
cap label var underemp_invol "involuntary underemployment"
cap label var underemp_vol   "voluntary underemployment"
cap label var hour_under     "weekly hours among underemployed"
cap label var hour_vol       "weekly hours among voluntary underemployed"
cap label var hour_invol     "weekly hours among involuntary underemployed"
cap label var status         "main employment status"
cap label var worktype       "main occupation (1-digit KBJI)"
cap label var formal_simple  "simplified formality (employee or assisted employer)"
cap label var formal_new     "formality (wrktype2011 matrix)"
cap label var formal_old     "formality including casual workers in agriculture and construction"
**---------------------------------------------------------------------------
** Additional Employment Indicators
**---------------------------------------------------------------------------
cap drop employee casual_worker potential_exp
gen employee = work_status == 4 if work_status != .
gen casual_worker = inlist(work_status, 5, 6) if work_status != .
gen potential_exp = age - school_years if age != . & school_years != .
cap label var employee      "employee dummy"
cap label var casual_worker "casual worker dummy"
cap label var potential_exp "potential work experience"

**---------------------------------------------------------------------------
** Education Major Classification
**---------------------------------------------------------------------------
cap drop educ_major
capture confirm variable b5_r1b
if !_rc {
    gen educ_major = b5_r1b
    /* Recode rules by education level:
       Different recode rules for different education levels (SMA vs Diploma/S1+)
       Codes: 0=SMP/under, 1=Sosio-hum, 2=Medika-FKH, 3=Pertanian, 4=Sains, 5=Teknik,
              6=Pendidikan, 7=Lainnya, 998=No info, 999=Other */
    capture confirm variable b5_r1a
    if !_rc {
        recode educ_major (38 41 43/45 = 1) (42 = 4) (37 39/40 = 5) (27 46 = 998) (50 = 999) if inrange(b5_r1a, 6, 7)
        recode educ_major (2/5 7/10 12 15/16 18 23 38 41 42/45 = 1) (13 = 2) (14 19 20 22 = 3) (6 21 24/25 42 = 4) (11 17 37 39 40 = 5) (26 = 6) (1 = 7) (27 46 = 998) (50 = 999) if b5_r1a == 8
        recode educ_major (2/5 7/10 12 15/16 18 23 38 41 42/45 = 1) (13 = 2) (14 19 20 22 = 3) (6 21 24/25 42 = 4) (11 17 37 39 40 = 5) (26 = 6) (1 = 7) (27 46 = 998) (50 = 999) if b5_r1a == 9
        recode educ_major (2/5 7/10 12 15/16 18 23 38 41 42/45 = 1) (13 = 2) (14 19 20 22 = 3) (6 21 24/25 42 = 4) (11 17 37 39 40 = 5) (26 = 6) (1 = 7) (27 46 = 998) (50 = 999) if inlist(b5_r1a, 10, 11, 12, 13, 14)
    }
    label define educ_major 0 "No major (SMP or under)" 1 "Sosio-humaniora" 2 "Medika-FKH" ///
                            3 "Pertanian" 4 "Sains" 5 "Teknik" 6 "Pendidikan" 7 "Lainnya" ///
                            998 "No information" 999 "Other", replace
    label values educ_major educ_major
    label var educ_major "education major (post-2010 surveys)"
}



save $clean/clean_sakernas_`year', replace

/*************************
 * End of Sakernas 2018
 ************************/
 
 /*************************
 * Sakernas 2019
 * (Using WB matrix for 9-sector classification)
 ************************/

clear
set more off
local year = 2019
use $source/sakernas_backcast_`year', clear

*-----------------------------------------------------------
* Basic Variables and Identifiers
*-----------------------------------------------------------
gen prov`year' = kode_prov
gen wt         = final_weig
gen urban      = (klasifikas == 1)
gen male       = (b4_k6 == 1)
gen age        = b4_k8         // WARNING: AGE OUTSIDE LF DETECTED
gen educ       = b5_r1a

**---------------------------------------------------------------------------
** Working Hours, Underemployment, Status, and Formality Indicators (2019)
** Raw inputs: hours=b5_r44a  status=b5_r24a  occupation=b5_r21_kji  involuntary=(b5_r12a, b5_r18a)
**---------------------------------------------------------------------------

* hour: total working hours of all jobs (week)
cap confirm variable b5_r44a
if !_rc {
    cap drop hour
    gen hour = b5_r44a if employment == 1
}
else {
    cap gen hour = .
}

* underemp: hour<35 & employed
cap drop underemp
gen underemp = 1 if hour < 35 & hour > 0
replace underemp = 0 if hour == 0
replace underemp = 0 if hour >= 35 & hour != .

* underemp_invol & underemp_vol (legacy formula)
cap drop underemp_invol underemp_vol
gen underemp_invol = .
cap confirm variable b5_r12a
local has_i1 = !_rc
cap confirm variable b5_r18a
local has_i2 = !_rc
if `has_i1' & `has_i2' {
    replace underemp_invol = 0 if underemp == 1
    replace underemp_invol = 1 if (b5_r12a == 1 | b5_r18a == 1) & underemp == 1
}
gen underemp_vol = .
replace underemp_vol = 1 if underemp == 1 & underemp_invol == 0
replace underemp_vol = 0 if underemp == 1 & underemp_invol == 1

* hour decomposed
cap drop hour_under hour_vol hour_invol
gen hour_under = hour if underemp == 1
gen hour_vol   = hour if underemp_vol == 1
gen hour_invol = hour if underemp_invol == 1

* status (employment status, 1-7)
cap drop status
cap confirm variable b5_r24a
if !_rc {
    gen status = b5_r24a if employment == 1
    replace status = . if status == 0
}
else {
    gen status = .
}

* worktype (1-digit code; take first digit if multi-digit)
cap drop worktype
cap confirm variable b5_r21_kji
if !_rc {
    gen _wt_raw = b5_r21_kji if employment == 1
    gen worktype = .
    replace worktype = real(substr(string(int(abs(_wt_raw))), 1, 1)) if _wt_raw != . & _wt_raw > 0
    replace worktype = _wt_raw if abs(_wt_raw) < 10 & _wt_raw != .
    drop _wt_raw
}
else {
    gen worktype = .
}

* formal_simple: status in (3,4)
cap drop formal_simple
gen formal_simple = inrange(status, 3, 4) if status != . & employment == 1

* formal_new: wrktype2011 matrix
cap drop formal_new
gen formal_new = .
replace formal_new = wrktype2011[status, worktype] ///
    if status != . & worktype != . & employment == 1 ///
    & inrange(status, 1, 7) & inrange(worktype, 1, 8)

* formal_old: formal_new + casual workers in agri/construction
cap drop formal_old
gen formal_old = formal_new
replace formal_old = 1 if (status == 5 & sector9 == 1) & employment == 1
replace formal_old = 1 if (status == 6 & sector9 == 5) & employment == 1

* labels
cap label var hour           "working hours per week (all jobs combined)"
cap label var underemp       "underemployed dummy (less than 35 hours per week)"
cap label var underemp_invol "involuntary underemployment"
cap label var underemp_vol   "voluntary underemployment"
cap label var hour_under     "weekly hours among underemployed"
cap label var hour_vol       "weekly hours among voluntary underemployed"
cap label var hour_invol     "weekly hours among involuntary underemployed"
cap label var status         "main employment status"
cap label var worktype       "main occupation (1-digit KBJI)"
cap label var formal_simple  "simplified formality (employee or assisted employer)"
cap label var formal_new     "formality (wrktype2011 matrix)"
cap label var formal_old     "formality including casual workers in agriculture and construction"
**---------------------------------------------------------------------------
** Additional Employment Indicators
**---------------------------------------------------------------------------
cap drop employee casual_worker potential_exp
gen employee = work_status == 4 if work_status != .
gen casual_worker = inlist(work_status, 5, 6) if work_status != .
gen potential_exp = age - school_years if age != . & school_years != .
cap label var employee      "employee dummy"
cap label var casual_worker "casual worker dummy"
cap label var potential_exp "potential work experience"

**---------------------------------------------------------------------------
** Education Major Classification
**---------------------------------------------------------------------------
cap drop educ_major
capture confirm variable b5_r1b
if !_rc {
    gen educ_major = b5_r1b
    /* Recode rules by education level:
       Different recode rules for different education levels (SMA vs Diploma/S1+)
       Codes: 0=SMP/under, 1=Sosio-hum, 2=Medika-FKH, 3=Pertanian, 4=Sains, 5=Teknik,
              6=Pendidikan, 7=Lainnya, 998=No info, 999=Other */
    capture confirm variable b5_r1a
    if !_rc {
        recode educ_major (38 41 43/45 = 1) (42 = 4) (37 39/40 = 5) (27 46 = 998) (50 = 999) if inrange(b5_r1a, 6, 7)
        recode educ_major (2/5 7/10 12 15/16 18 23 38 41 42/45 = 1) (13 = 2) (14 19 20 22 = 3) (6 21 24/25 42 = 4) (11 17 37 39 40 = 5) (26 = 6) (1 = 7) (27 46 = 998) (50 = 999) if b5_r1a == 8
        recode educ_major (2/5 7/10 12 15/16 18 23 38 41 42/45 = 1) (13 = 2) (14 19 20 22 = 3) (6 21 24/25 42 = 4) (11 17 37 39 40 = 5) (26 = 6) (1 = 7) (27 46 = 998) (50 = 999) if b5_r1a == 9
        recode educ_major (2/5 7/10 12 15/16 18 23 38 41 42/45 = 1) (13 = 2) (14 19 20 22 = 3) (6 21 24/25 42 = 4) (11 17 37 39 40 = 5) (26 = 6) (1 = 7) (27 46 = 998) (50 = 999) if inlist(b5_r1a, 10, 11, 12, 13, 14)
    }
    label define educ_major 0 "No major (SMP or under)" 1 "Sosio-humaniora" 2 "Medika-FKH" ///
                            3 "Pertanian" 4 "Sains" 5 "Teknik" 6 "Pendidikan" 7 "Lainnya" ///
                            998 "No information" 999 "Other", replace
    label values educ_major educ_major
    label var educ_major "education major (post-2010 surveys)"
}



keep if age >= 15

*-----------------------------------------------------------
* Employment and Labor Force
*-----------------------------------------------------------
* (Commented out previous unemp/employment definitions)
* Define employment indicator directly:
gen employment = (b5_r5a1 == 1 | b5_r6 == 1)

gen caker1 = (b5_r12a == 1)    // looking for work
gen caker2 = (b5_r12b == 1)    // establishing new business/firm
gen caker3 = (b5_r17a == 3)    // hopeless of job
gen caker4 = (b5_r17a == 1 | b5_r17a == 2)  // have a job in future start

gen dlabforce = cond(employment == 1, 1, ///
                cond(caker1 == 1, 2, ///
                cond(caker2 == 1, 3, ///
                cond(caker3 == 1, 4, ///
                cond(caker4 == 1, 5, ///
                cond(b5_r5b == 2, 6, ///
                cond(b5_r5b == 3, 7, 8)))))))
label define dlabforce 1 "Working" 2 "Looking" 3 "Establishing new business" 4 "Discouraged" 5 "Future job arranged" 6 "Student" 7 "Housekeeping" 8 "Others"
label val dlabforce dlabforce

*-----------------------------------------------------------
* Define Labor Force Components
*-----------------------------------------------------------
gen labforce_core = cond(inrange(dlabforce, 1, 2), 1, 2)
recode labforce_core 2 = 0

gen labforce_broad = cond(inrange(dlabforce, 1, 5), 1, 2)
recode labforce_broad 2 = 0

gen lf = inrange(dlabforce, 1, 5)
label define lf 1 "Economically Active" 0 "Not Economically Active"
label value lf lf

replace employment = . if labforce_broad == 0

* Core unemployment
gen unemp = (employment == 0) if employment != .
gen unemp_core = unemp
replace unemp_core = . if labforce_core == 0

*-----------------------------------------------------------
* Sector Classification Using WB Matrix
*-----------------------------------------------------------
gen sector17 = b5_r20_kat
replace sector17 = . if sector17 == 0

#delim ;
	recode sector17
		(0		= .)
		(1		= 1)
		(2		= 2)
		(3		= 3)
		(4/5	= 4)
		(6		= 5)
		(7 9	= 6)
		(8 10	= 7)
		(11/13	= 8)
		(14/17	= 9),
		gen(sector9);
#delim cr

label define sector9 1 "Agriculture, forestry, livestock and fishing" ///
                      2 "Mining and quarrying" ///
                      3 "Manufacturing" ///
                      4 "Electricity, gas, and water supply" ///
                      5 "Construction" ///
                      6 "Wholesale and retail trade, restaurants and hotels" ///
                      7 "Transportation, storage and communications" ///
                      8 "Finance, insurance, real estate and business services" ///
                      9 "Community, social and personal services" ///
                      10 "Others"
label values sector9 sector9

*-----------------------------------------------------------
* Work-Related Variables
*-----------------------------------------------------------
gen work_informal = inlist(b5_r24a, 1, 2, 5, 6, 7)
gen work_status   = b5_r24a
gen work_certif   = (b5_r1d == 1)
    replace work_certif = . if lf == 0
gen work_whitecoll = inrange(b5_r21_kji, 1, 5)

gen act_school = (b5_r5a2 == 3 | b5_r5a2 == 4) & b5_r5b == 2 & lf == 0
gen act_household = (b5_r5a3 == 1 | b5_r5a3 == 2) & b5_r5b == 3 & lf == 0
gen act_others = (b5_r5a4 == 3 | b5_r5a4 == 4) & b5_r5b == 4 & lf == 0
gen act_neet = 0
replace act_neet = 1 if b5_r5a1 == 2 & b5_r5a2 == 4
replace act_neet = 0 if act_school == 1
replace act_neet = . if age >= 25 | age <= 14

local year = 2019
*-----------------------------------------------------------
* Work Outcome Variables
*-----------------------------------------------------------
gen work_hours = b5_r23a
    replace work_hours = . if employment != 1
gen work_earnings = .
replace work_earnings = b5_r28b1 + b5_r28b2 if inlist(b5_r24a, 1, 5, 6)
replace work_earnings = b5_r28c1 + b5_r28c2 if inlist(b5_r24a, 4)
replace work_earnings = 0 if work_earnings < 0
replace work_earnings = . if employment != 1
gen work_wage = b5_r28c1 + b5_r28c2 if inlist(b5_r24a, 4)
replace work_wage = 0 if work_wage < 0
replace work_wage = . if employment != 1
gen work_jobdur = b5_r14
    replace work_jobdur = . if work_jobdur == 0

*-----------------------------------------------------------
* Recodes and Derived Variables
*-----------------------------------------------------------
recode educ 1/4 = 1 5/11 = 2 12/16 = 3, generate(educ_group)
recode work_jobdur 0/3 = 1 4/12 = 2 12/24 = 3 25/9999 = 4, gen(work_jobdur_cat)

gen school_years = .
replace school_years = 0 if educ == 1
replace school_years = 0 if educ == 2
replace school_years = 6 if educ == 3
replace school_years = 6 if educ == 4
replace school_years = 9 if educ == 5
replace school_years = 9 if educ == 6
replace school_years = 9 if educ == 7
replace school_years = 12 if educ == 8
replace school_years = 12 if educ == 9
replace school_years = 12 if educ == 10
replace school_years = 14 if educ == 11
replace school_years = 15 if educ == 12
replace school_years = 16 if educ == 13
replace school_years = 20 if educ == 14

*-----------------------------------------------------------
* Job Search Duration Dummies
*-----------------------------------------------------------
la de searchdur 1 "1. <=3 bulan" 2 "2. 4-12 bulan" 3 "3. 13-24 bulan" 4 "4. >24 bulan"
la val work_jobdur_cat searchdur

forval x = 1/4 {
    gen work_searchdur_`x' = (work_jobdur_cat == `x')
    replace work_searchdur_`x' = . if lf == 0 | work_jobdur_cat == .
}

foreach var of varlist work_hours work_earnings work_wage {
    replace `var' = . if unemp == 1 | lf == 0
}

*-----------------------------------------------------------
* Finalize and Save 2019 Data
*-----------------------------------------------------------
gen year = `year'
// save "$output/temp_sakernas_`year'", replace

*-----------------------------------------------------------
* 2019 Clean Data (standard)
*-----------------------------------------------------------
local year = 2019
keep prov`year' wt urban male age educ unemp employment lf school_years sector9 sector17 work_informal work_status ///
     act_neet act_school act_household act_others work_hours work_whitecoll work_earnings work_wage work_jobdur* ///
     educ_group work_searchdur_* year work_certif

**---------------------------------------------------------------------------
** Working Hours, Underemployment, Status, and Formality Indicators (2019)
** Raw inputs: hours=b5_r44a  status=b5_r24a  occupation=b5_r21_kji  involuntary=(b5_r12a, b5_r18a)
**---------------------------------------------------------------------------

* hour: total working hours of all jobs (week)
cap confirm variable b5_r44a
if !_rc {
    cap drop hour
    gen hour = b5_r44a if employment == 1
}
else {
    cap gen hour = .
}

* underemp: hour<35 & employed
cap drop underemp
gen underemp = 1 if hour < 35 & hour > 0
replace underemp = 0 if hour == 0
replace underemp = 0 if hour >= 35 & hour != .

* underemp_invol & underemp_vol (legacy formula)
cap drop underemp_invol underemp_vol
gen underemp_invol = .
cap confirm variable b5_r12a
local has_i1 = !_rc
cap confirm variable b5_r18a
local has_i2 = !_rc
if `has_i1' & `has_i2' {
    replace underemp_invol = 0 if underemp == 1
    replace underemp_invol = 1 if (b5_r12a == 1 | b5_r18a == 1) & underemp == 1
}
gen underemp_vol = .
replace underemp_vol = 1 if underemp == 1 & underemp_invol == 0
replace underemp_vol = 0 if underemp == 1 & underemp_invol == 1

* hour decomposed
cap drop hour_under hour_vol hour_invol
gen hour_under = hour if underemp == 1
gen hour_vol   = hour if underemp_vol == 1
gen hour_invol = hour if underemp_invol == 1

* status (employment status, 1-7)
cap drop status
cap confirm variable b5_r24a
if !_rc {
    gen status = b5_r24a if employment == 1
    replace status = . if status == 0
}
else {
    gen status = .
}

* worktype (1-digit code; take first digit if multi-digit)
cap drop worktype
cap confirm variable b5_r21_kji
if !_rc {
    gen _wt_raw = b5_r21_kji if employment == 1
    gen worktype = .
    replace worktype = real(substr(string(int(abs(_wt_raw))), 1, 1)) if _wt_raw != . & _wt_raw > 0
    replace worktype = _wt_raw if abs(_wt_raw) < 10 & _wt_raw != .
    drop _wt_raw
}
else {
    gen worktype = .
}

* formal_simple: status in (3,4)
cap drop formal_simple
gen formal_simple = inrange(status, 3, 4) if status != . & employment == 1

* formal_new: wrktype2011 matrix
cap drop formal_new
gen formal_new = .
replace formal_new = wrktype2011[status, worktype] ///
    if status != . & worktype != . & employment == 1 ///
    & inrange(status, 1, 7) & inrange(worktype, 1, 8)

* formal_old: formal_new + casual workers in agri/construction
cap drop formal_old
gen formal_old = formal_new
replace formal_old = 1 if (status == 5 & sector9 == 1) & employment == 1
replace formal_old = 1 if (status == 6 & sector9 == 5) & employment == 1

* labels
cap label var hour           "working hours per week (all jobs combined)"
cap label var underemp       "underemployed dummy (less than 35 hours per week)"
cap label var underemp_invol "involuntary underemployment"
cap label var underemp_vol   "voluntary underemployment"
cap label var hour_under     "weekly hours among underemployed"
cap label var hour_vol       "weekly hours among voluntary underemployed"
cap label var hour_invol     "weekly hours among involuntary underemployed"
cap label var status         "main employment status"
cap label var worktype       "main occupation (1-digit KBJI)"
cap label var formal_simple  "simplified formality (employee or assisted employer)"
cap label var formal_new     "formality (wrktype2011 matrix)"
cap label var formal_old     "formality including casual workers in agriculture and construction"
**---------------------------------------------------------------------------
** Additional Employment Indicators
**---------------------------------------------------------------------------
cap drop employee casual_worker potential_exp
gen employee = work_status == 4 if work_status != .
gen casual_worker = inlist(work_status, 5, 6) if work_status != .
gen potential_exp = age - school_years if age != . & school_years != .
cap label var employee      "employee dummy"
cap label var casual_worker "casual worker dummy"
cap label var potential_exp "potential work experience"

**---------------------------------------------------------------------------
** Education Major Classification
**---------------------------------------------------------------------------
cap drop educ_major
capture confirm variable b5_r1b
if !_rc {
    gen educ_major = b5_r1b
    /* Recode rules by education level:
       Different recode rules for different education levels (SMA vs Diploma/S1+)
       Codes: 0=SMP/under, 1=Sosio-hum, 2=Medika-FKH, 3=Pertanian, 4=Sains, 5=Teknik,
              6=Pendidikan, 7=Lainnya, 998=No info, 999=Other */
    capture confirm variable b5_r1a
    if !_rc {
        recode educ_major (38 41 43/45 = 1) (42 = 4) (37 39/40 = 5) (27 46 = 998) (50 = 999) if inrange(b5_r1a, 6, 7)
        recode educ_major (2/5 7/10 12 15/16 18 23 38 41 42/45 = 1) (13 = 2) (14 19 20 22 = 3) (6 21 24/25 42 = 4) (11 17 37 39 40 = 5) (26 = 6) (1 = 7) (27 46 = 998) (50 = 999) if b5_r1a == 8
        recode educ_major (2/5 7/10 12 15/16 18 23 38 41 42/45 = 1) (13 = 2) (14 19 20 22 = 3) (6 21 24/25 42 = 4) (11 17 37 39 40 = 5) (26 = 6) (1 = 7) (27 46 = 998) (50 = 999) if b5_r1a == 9
        recode educ_major (2/5 7/10 12 15/16 18 23 38 41 42/45 = 1) (13 = 2) (14 19 20 22 = 3) (6 21 24/25 42 = 4) (11 17 37 39 40 = 5) (26 = 6) (1 = 7) (27 46 = 998) (50 = 999) if inlist(b5_r1a, 10, 11, 12, 13, 14)
    }
    label define educ_major 0 "No major (SMP or under)" 1 "Sosio-humaniora" 2 "Medika-FKH" ///
                            3 "Pertanian" 4 "Sains" 5 "Teknik" 6 "Pendidikan" 7 "Lainnya" ///
                            998 "No information" 999 "Other", replace
    label values educ_major educ_major
    label var educ_major "education major (post-2010 surveys)"
}



save $clean/clean_sakernas_`year', replace

/*************************
 * End of Sakernas 2019
 ************************/
 
 /*************************
 * Sakernas 2020
 * (Using WB matrix for 9-sector classification)
 ************************/

clear
set more off
local year = 2020
use $source/sakernas_`year', clear

/*-----------------------------------------------------------
   Basic Variables and Identifiers
-----------------------------------------------------------*/
gen prov`year' = KODE_PROV
gen wt         = FINAL_WEIG
gen urban      = (KLASIFIKAS == 1)
gen male       = (K4 == 1)
gen age        = K6         // WARNING: AGE OUTSIDE LF DETECTED
gen educ       = R6A

/*-----------------------------------------------------------
   Employment and Unemployment
-----------------------------------------------------------*/
gen employment = (R9A == 1 | R9B == 1 | R9C == 1 | R10A == 1)
gen unemp = .
    replace unemp = 1 if R9A == 2 & R10A == 2 & R22A == 1 & employment == 0
    replace unemp = 1 if R9A == 2 & R10A == 2 & R22B == 1 & employment == 0
    replace unemp = 1 if R9A == 2 & inlist(R25A, 1, 2, 3) & employment == 0
    replace unemp = 0 if unemp != 1
    replace employment = 0 if unemp == 1

/*-----------------------------------------------------------
   Define Labor Force
-----------------------------------------------------------*/
gen lf = .
replace lf = 1 if employment == 1 | unemp == 1
replace lf = 0 if age < 15
replace lf = 0 if lf != 1
replace unemp = . if lf == 0
replace employment = . if lf == 0
keep if age >= 15

/*-----------------------------------------------------------
   Sector Classification (17-sector then standard 9-sector)
-----------------------------------------------------------*/
gen sector17 = R13A_KATEG
replace sector17 = . if sector17 == 0

#delim ;
	recode sector17
		(0		= .)
		(1		= 1)
		(2		= 2)
		(3		= 3)
		(4/5	= 4)
		(6		= 5)
		(7 9	= 6)
		(8 10	= 7)
		(11/13	= 8)
		(14/17	= 9),
		gen(sector9);
#delim cr

label define sector9 1 "Agriculture, forestry, livestock and fishing" ///
                      2 "Mining and quarrying" ///
                      3 "Manufacturing" ///
                      4 "Electricity, gas, and water supply" ///
                      5 "Construction" ///
                      6 "Wholesale and retail trade, restaurants and hotels" ///
                      7 "Transportation, storage and communications" ///
                      8 "Finance, insurance, real estate and business services" ///
                      9 "Community, social and personal services" ///
                      10 "Others"
label values sector9 sector9

/*-----------------------------------------------------------
   Work-Related Variables
-----------------------------------------------------------*/
gen work_informal = inlist(R12A, 1, 2, 5, 6, 7)
gen work_status   = R12A
gen work_certif   = (R6D == 1)
    replace work_certif = . if lf == 0
gen work_whitecoll = inrange(R13B_KJI19, 1, 5)

/*-----------------------------------------------------------
   Non-Labor Force Activity Dummies
-----------------------------------------------------------*/
gen act_school    = (R31A == 1 & R31D == 1 & lf == 0)
gen act_household = (R31B == 1 & R31D == 2 & lf == 0)
gen others = 0
    replace others = 1 if others == .
gen act_others    = (lf == 0 & others == 1)
gen act_neet = 0
    replace act_neet = 1 if R9A == 2 & R31A == 2
    replace act_neet = 0 if act_school == 1
    replace act_neet = . if age >= 25 | age <= 14

/*-----------------------------------------------------------
   Work Outcome Variables
-----------------------------------------------------------*/
gen work_hours = R20B
    replace work_hours = . if employment != 1
gen work_earnings = R14A1 + R14A2
    replace work_earnings = 0 if work_earnings < 0
    replace work_earnings = . if employment != 1
gen work_wage = (R14A1 + R14A2) if R12A == 4
    replace work_wage = 0 if work_wage < 0
    replace work_wage = . if employment != 1
gen work_jobdur = (R23A * 12) + R23B
    replace work_jobdur = . if work_jobdur == 0

/*-----------------------------------------------------------
   Recodes and Derived Variables
-----------------------------------------------------------*/
recode educ 1/2 = 1 3/5 = 2 6/8 = 3, generate(educ_group)
recode work_jobdur 0/3 = 1 4/12 = 2 12/24 = 3 25/9999 = 4, gen(work_jobdur_cat)
gen school_years = .
replace school_years = 0 if educ == 1
replace school_years = 6 if educ == 2
replace school_years = 9 if educ == 3
replace school_years = 12 if educ == 4
replace school_years = 12 if educ == 5
replace school_years = 15 if educ == 6
replace school_years = 16 if educ == 7

/*-----------------------------------------------------------
   Job Search Duration Dummies
-----------------------------------------------------------*/
la de searchdur 1 "1. <=3 bulan" 2 "2. 4-12 bulan" 3 "3. 13-24 bulan" 4 "4. >24 bulan"
la val work_jobdur_cat searchdur

forval x = 1/4 {
    gen work_searchdur_`x' = (work_jobdur_cat == `x')
    replace work_searchdur_`x' = . if lf == 0 | work_jobdur_cat == .
}

foreach var of varlist work_hours work_earnings work_wage {
    replace `var' = . if unemp == 1 | lf == 0
}

/*-----------------------------------------------------------
   Finalize and Save 2020 Data
-----------------------------------------------------------*/
gen year = `year'
// save "$output/temp_sakernas_`year'", replace

*-----------------------------------------------------------
* 2020 Clean Data (standard)
*-----------------------------------------------------------

keep prov`year' wt urban male age educ unemp employment lf school_years sector9 sector17 work_informal work_status ///
     act_neet act_school act_household act_others work_hours work_whitecoll work_earnings work_wage work_jobdur* ///
     educ_group work_searchdur_* year work_certif

**---------------------------------------------------------------------------
** Working Hours, Underemployment, Status, and Formality Indicators (2020)
** Raw inputs: hours=r20b  status=r12a  occupation=r13b_kji19  involuntary=(r22a, r26)
**---------------------------------------------------------------------------

* hour: total working hours of all jobs (week)
cap confirm variable r20b
if !_rc {
    cap drop hour
    gen hour = r20b if employment == 1
}
else {
    cap gen hour = .
}

* underemp: hour<35 & employed
cap drop underemp
gen underemp = 1 if hour < 35 & hour > 0
replace underemp = 0 if hour == 0
replace underemp = 0 if hour >= 35 & hour != .

* underemp_invol & underemp_vol (legacy formula)
cap drop underemp_invol underemp_vol
gen underemp_invol = .
cap confirm variable r22a
local has_i1 = !_rc
cap confirm variable r26
local has_i2 = !_rc
if `has_i1' & `has_i2' {
    replace underemp_invol = 0 if underemp == 1
    replace underemp_invol = 1 if (r22a == 1 | r26 == 1) & underemp == 1
}
gen underemp_vol = .
replace underemp_vol = 1 if underemp == 1 & underemp_invol == 0
replace underemp_vol = 0 if underemp == 1 & underemp_invol == 1

* hour decomposed
cap drop hour_under hour_vol hour_invol
gen hour_under = hour if underemp == 1
gen hour_vol   = hour if underemp_vol == 1
gen hour_invol = hour if underemp_invol == 1

* status (employment status, 1-7)
cap drop status
cap confirm variable r12a
if !_rc {
    gen status = r12a if employment == 1
    replace status = . if status == 0
}
else {
    gen status = .
}

* worktype (1-digit code; take first digit if multi-digit)
cap drop worktype
cap confirm variable r13b_kji19
if !_rc {
    gen _wt_raw = r13b_kji19 if employment == 1
    gen worktype = .
    replace worktype = real(substr(string(int(abs(_wt_raw))), 1, 1)) if _wt_raw != . & _wt_raw > 0
    replace worktype = _wt_raw if abs(_wt_raw) < 10 & _wt_raw != .
    drop _wt_raw
}
else {
    gen worktype = .
}

* formal_simple: status in (3,4)
cap drop formal_simple
gen formal_simple = inrange(status, 3, 4) if status != . & employment == 1

* formal_new: wrktype2011 matrix
cap drop formal_new
gen formal_new = .
replace formal_new = wrktype2011[status, worktype] ///
    if status != . & worktype != . & employment == 1 ///
    & inrange(status, 1, 7) & inrange(worktype, 1, 8)

* formal_old: formal_new + casual workers in agri/construction
cap drop formal_old
gen formal_old = formal_new
replace formal_old = 1 if (status == 5 & sector9 == 1) & employment == 1
replace formal_old = 1 if (status == 6 & sector9 == 5) & employment == 1

* labels
cap label var hour           "working hours per week (all jobs combined)"
cap label var underemp       "underemployed dummy (less than 35 hours per week)"
cap label var underemp_invol "involuntary underemployment"
cap label var underemp_vol   "voluntary underemployment"
cap label var hour_under     "weekly hours among underemployed"
cap label var hour_vol       "weekly hours among voluntary underemployed"
cap label var hour_invol     "weekly hours among involuntary underemployed"
cap label var status         "main employment status"
cap label var worktype       "main occupation (1-digit KBJI)"
cap label var formal_simple  "simplified formality (employee or assisted employer)"
cap label var formal_new     "formality (wrktype2011 matrix)"
cap label var formal_old     "formality including casual workers in agriculture and construction"
**---------------------------------------------------------------------------
** Additional Employment Indicators
**---------------------------------------------------------------------------
cap drop employee casual_worker potential_exp
gen employee = work_status == 4 if work_status != .
gen casual_worker = inlist(work_status, 5, 6) if work_status != .
gen potential_exp = age - school_years if age != . & school_years != .
cap label var employee      "employee dummy"
cap label var casual_worker "casual worker dummy"
cap label var potential_exp "potential work experience"

**---------------------------------------------------------------------------
** Education Major Classification
**---------------------------------------------------------------------------
cap drop educ_major
capture confirm variable R6B
if !_rc {
    gen educ_major = R6B
    /* Recode rules by education level:
       Different recode rules for different education levels (SMA vs Diploma/S1+)
       Codes: 0=SMP/under, 1=Sosio-hum, 2=Medika-FKH, 3=Pertanian, 4=Sains, 5=Teknik,
              6=Pendidikan, 7=Lainnya, 998=No info, 999=Other */
    capture confirm variable R6A
    if !_rc {
        recode educ_major (38 41 43/45 = 1) (42 = 4) (37 39/40 = 5) (27 46 = 998) (50 = 999) if inrange(R6A, 6, 7)
        recode educ_major (2/5 7/10 12 15/16 18 23 38 41 42/45 = 1) (13 = 2) (14 19 20 22 = 3) (6 21 24/25 42 = 4) (11 17 37 39 40 = 5) (26 = 6) (1 = 7) (27 46 = 998) (50 = 999) if R6A == 8
        recode educ_major (2/5 7/10 12 15/16 18 23 38 41 42/45 = 1) (13 = 2) (14 19 20 22 = 3) (6 21 24/25 42 = 4) (11 17 37 39 40 = 5) (26 = 6) (1 = 7) (27 46 = 998) (50 = 999) if R6A == 9
        recode educ_major (2/5 7/10 12 15/16 18 23 38 41 42/45 = 1) (13 = 2) (14 19 20 22 = 3) (6 21 24/25 42 = 4) (11 17 37 39 40 = 5) (26 = 6) (1 = 7) (27 46 = 998) (50 = 999) if inlist(R6A, 10, 11, 12, 13, 14)
    }
    label define educ_major 0 "No major (SMP or under)" 1 "Sosio-humaniora" 2 "Medika-FKH" ///
                            3 "Pertanian" 4 "Sains" 5 "Teknik" 6 "Pendidikan" 7 "Lainnya" ///
                            998 "No information" 999 "Other", replace
    label values educ_major educ_major
    label var educ_major "education major (post-2010 surveys)"
}



save $clean/clean_sakernas_`year', replace

/*************************
 * End of Sakernas 2020
 ************************/

 /*************************
 * Sakernas 2021
 * (Using WB matrix for 9-sector classification)
 ************************/

clear
set more off
local year = 2021
use $source/sakernas_`year', clear

/*-----------------------------------------------------------
   Basic Variables and Identifiers
-----------------------------------------------------------*/
gen prov`year' = KODE_PROV
gen wt         = FINAL_WEIG
gen urban      = (KLAS == 1)
gen male       = (K4 == 1)
gen age        = K6         // WARNING: AGE OUTSIDE LF DETECTED
gen educ       = R6A
keep if age >= 15

/*-----------------------------------------------------------
   Employment and Unemployment
-----------------------------------------------------------*/
gen employment = (R9A == 1 | R9B == 1 | R9C == 1 | R10A == 1)
gen unemp = .
    replace unemp = 1 if R9A == 2 & R10A == 2 & R29A == 1 & employment == 0
    replace unemp = 1 if R9A == 2 & R10A == 2 & R29B == 1 & employment == 0
    replace unemp = 1 if R9A == 2 & inlist(R32A, 1, 2, 3) & employment == 0
    replace unemp = 0 if unemp != 1
replace employment = 0 if unemp == 1

gen lf = .
replace lf = 1 if employment == 1 | unemp == 1
replace lf = 0 if age < 15
replace lf = 0 if lf != 1
replace unemp = . if lf == 0
replace employment = . if lf == 0
keep if age >= 15

/*-----------------------------------------------------------
   Sector Classification (standard)
-----------------------------------------------------------*/
gen sector17 = KBLI2020_1
replace sector17 = . if sector17 == 0

#delim ;
	recode sector17
		(0		= .)
		(1		= 1)
		(2		= 2)
		(3		= 3)
		(4/5	= 4)
		(6		= 5)
		(7 9	= 6)
		(8 10	= 7)
		(11/13	= 8)
		(14/17	= 9),
		gen(sector9);
#delim cr

label define sector9 1 "Agriculture, forestry, livestock and fishing" ///
                      2 "Mining and quarrying" ///
                      3 "Manufacturing" ///
                      4 "Electricity, gas, and water supply" ///
                      5 "Construction" ///
                      6 "Wholesale and retail trade, restaurants and hotels" ///
                      7 "Transportation, storage and communications" ///
                      8 "Finance, insurance, real estate and business services" ///
                      9 "Community, social and personal services" ///
                      10 "Others"
label values sector9 sector9

/*-----------------------------------------------------------
   Work-Related Variables
-----------------------------------------------------------*/
gen work_informal = inlist(R12A, 1, 2, 5, 6, 7)
gen work_status   = R12A
gen work_certif   = (R6D == 1)
    replace work_certif = . if lf == 0
gen work_whitecoll = inrange(KBJI1982, 1, 5)

/*-----------------------------------------------------------
   Non-Labor Force Activity Dummies
-----------------------------------------------------------*/
gen act_school = (R42A == 1 & R42D == 1 & lf == 0)
gen act_household = (R42B == 1 & R42D == 2 & lf == 0)
gen others = 0
    replace others = 1 if others == .
gen act_others = (lf == 0 & others == 1)
gen act_neet = 0
    replace act_neet = 1 if R9A == 2 & R42A == 2
    replace act_neet = 0 if act_school == 1
    replace act_neet = . if age >= 25 | age <= 14

/*-----------------------------------------------------------
   Work Outcome Variables
-----------------------------------------------------------*/
gen work_hours = R16A1_BLT
    replace work_hours = . if employment != 1
gen work_earnings = R14A_UANG + R14A2_BRG
    replace work_earnings = 0 if work_earnings < 0
    replace work_earnings = . if employment != 1
gen work_wage = (R14A_UANG + R14A2_BRG) if R12A == 4
    replace work_wage = 0 if work_wage < 0
    replace work_wage = . if employment != 1
gen work_jobdur = (R30_TH * 12) + R30_BLN
    replace work_jobdur = . if work_jobdur == 0

/*-----------------------------------------------------------
   Recodes and Derived Variables
-----------------------------------------------------------*/
recode educ 1/2 = 1 3/6 = 2 7/12 = 3, generate(educ_group)
recode work_jobdur 0/3 = 1 4/12 = 2 12/24 = 3 25/9999 = 4, gen(work_jobdur_cat)
gen school_years = .
replace school_years = 0 if educ == 1
replace school_years = 6 if educ == 2
replace school_years = 9 if educ == 3
replace school_years = 12 if educ == 4
replace school_years = 12 if educ == 5
replace school_years = 15 if educ == 6
replace school_years = 16 if educ == 7

/*-----------------------------------------------------------
   Job Search Duration Dummies
-----------------------------------------------------------*/
la de searchdur 1 "1. <=3 bulan" 2 "2. 4-12 bulan" 3 "3. 13-24 bulan" 4 "4. >24 bulan"
la val work_jobdur_cat searchdur

forval x = 1/4 {
    gen work_searchdur_`x' = (work_jobdur_cat == `x')
    replace work_searchdur_`x' = . if lf == 0 | work_jobdur_cat == .
}

foreach var of varlist work_hours work_earnings work_wage {
    replace `var' = . if unemp == 1 | lf == 0
}

/*-----------------------------------------------------------
   Finalize and Save 2021 Data
-----------------------------------------------------------*/
gen year = `year'
// save "$output/temp_sakernas_`year'", replace

*-----------------------------------------------------------
* 2021 Clean Data (standard)
*-----------------------------------------------------------

keep prov`year' wt urban male age educ unemp employment lf school_years sector9 sector17 work_informal work_status ///
     act_neet act_school act_household act_others work_hours work_whitecoll work_earnings work_wage work_jobdur* ///
     educ_group work_searchdur_* year work_certif

**---------------------------------------------------------------------------
** Derived Labour Indicators (2021: limited raw data, set to missing)
**---------------------------------------------------------------------------
foreach v in hour underemp underemp_invol underemp_vol hour_under hour_vol hour_invol status worktype formal_simple formal_new formal_old {
    cap gen `v' = .
}

save $clean/clean_sakernas_`year', replace

/*************************
 * End of Sakernas 2021
 ************************/
 
 /*************************
 * Sakernas 2022
 * (Using WB matrix for 9-sector classification)
 ************************/

clear
set more off
local year = 2022
use $source/sakernas_`year', clear

/*-----------------------------------------------------------
   Basic Variables and Identifiers
-----------------------------------------------------------*/
gen prov`year' = KODE_PROV
gen wt         = WEIGHT
gen urban      = (KLAS == 1)
gen male       = (K4 == 1)
gen age        = K6         // WARNING: AGE OUTSIDE LF DETECTED
gen educ       = R6A
keep if age >= 15

/*-----------------------------------------------------------
   Employment and Unemployment
-----------------------------------------------------------*/
gen employment = (R9A == 1 | R9B == 1 | R9C == 1 | R10 == 1)
gen unemp = .
    replace unemp = 1 if R9A == 2 & R10 == 2 & R31A == 1 & employment == 0
    replace unemp = 1 if R9A == 2 & R10 == 2 & R31B == 1 & employment == 0
    replace unemp = 1 if R9A == 2 & inlist(R35A, 1, 2, 3) & employment == 0
    replace unemp = 0 if unemp != 1
replace employment = 0 if unemp == 1

gen lf = .
replace lf = 1 if employment == 1 | unemp == 1
replace lf = 0 if age < 15
replace lf = 0 if lf != 1
replace unemp = . if lf == 0
replace employment = . if lf == 0

/*-----------------------------------------------------------
   Sector Classification (standard)
-----------------------------------------------------------*/
gen sector17 = R14AKATEGO
replace sector17 = . if sector17 == 0

#delim ;
	recode sector17
		(0		= .)
		(1		= 1)
		(2		= 2)
		(3		= 3)
		(4/5	= 4)
		(6		= 5)
		(7 9	= 6)
		(8 10	= 7)
		(11/13	= 8)
		(14/17	= 9),
		gen(sector9);
#delim cr

label define sector9 1 "Agriculture, forestry, livestock and fishing" ///
                      2 "Mining and quarrying" ///
                      3 "Manufacturing" ///
                      4 "Electricity, gas, and water supply" ///
                      5 "Construction" ///
                      6 "Wholesale and retail trade, restaurants and hotels" ///
                      7 "Transportation, storage and communications" ///
                      8 "Finance, insurance, real estate and business services" ///
                      9 "Community, social and personal services" ///
                      10 "Others"
label values sector9 sector9

/*-----------------------------------------------------------
   Work-Related Variables
-----------------------------------------------------------*/
gen work_informal = inlist(R13A, 1, 2, 5, 6, 7)
gen work_status   = R13A
gen work_certif   = (R6D == 1)
    replace work_certif = . if lf == 0
gen work_whitecoll = inrange(R14BKBJI19, 1, 5)

/*-----------------------------------------------------------
   Non-Labor Force Activity Dummies
-----------------------------------------------------------*/
gen act_school = (R46A == 1 & R46D == 1 & lf == 0)
gen act_household = (R46B == 1 & R46D == 2 & lf == 0)
gen others = 0
    replace others = 1 if others == .
gen act_others = (lf == 0 & others == 1)
gen act_neet = 0
    replace act_neet = 1 if R9A == 2 & R46A == 2
    replace act_neet = 0 if act_school == 1
    replace act_neet = . if age >= 25 | age <= 14

/*-----------------------------------------------------------
   Work Outcome Variables
-----------------------------------------------------------*/
gen work_hours = R17A_BLT
    replace work_hours = . if employment != 1
gen work_earnings = R15A_UANG + R15A_BRG
    replace work_earnings = 0 if work_earnings < 0
    replace work_earnings = . if employment != 1
gen work_wage = (R15A_UANG + R15A_BRG) if R13A == 4
    replace work_wage = 0 if work_wage < 0
    replace work_wage = . if employment != 1
gen work_jobdur = (R33_TH * 12) + R33_BLN
    replace work_jobdur = . if work_jobdur == 0

/*-----------------------------------------------------------
   Recodes and Derived Variables
-----------------------------------------------------------*/
recode educ 1/2 = 1 3/6 = 2 7/12 = 3, generate(educ_group)
recode work_jobdur 0/3 = 1 4/12 = 2 12/24 = 3 25/9999 = 4, gen(work_jobdur_cat)
gen school_years = .
replace school_years = 0 if educ == 1
replace school_years = 6 if educ == 2
replace school_years = 9 if educ == 3
replace school_years = 12 if educ == 4
replace school_years = 12 if educ == 5
replace school_years = 15 if educ == 6
replace school_years = 16 if educ == 7
                      
/*-----------------------------------------------------------
   Job Search Duration Dummies
-----------------------------------------------------------*/
la de searchdur 1 "1. <=3 bulan" 2 "2. 4-12 bulan" 3 "3. 13-24 bulan" 4 "4. >24 bulan"
la val work_jobdur_cat searchdur

forval x = 1/4 {
    gen work_searchdur_`x' = (work_jobdur_cat == `x')
    replace work_searchdur_`x' = . if lf == 0 | work_jobdur_cat == .
}

foreach var of varlist work_hours work_earnings work_wage {
    replace `var' = . if unemp == 1 | lf == 0
}

/*-----------------------------------------------------------
   Finalize and Save 2022 Data
-----------------------------------------------------------*/
gen year = `year'
// save "$output/temp_sakernas_`year'", replace

*-----------------------------------------------------------
* 2022 Clean Data (standard)
*-----------------------------------------------------------

keep prov`year' wt urban male age educ unemp employment lf school_years sector9 sector17 work_informal work_status ///
     act_neet act_school act_household act_others work_hours work_whitecoll work_earnings work_wage work_jobdur* ///
     educ_group work_searchdur_* year work_certif

**---------------------------------------------------------------------------
** Working Hours, Underemployment, Status, and Formality Indicators (2022)
** Raw inputs: hours=r28b_jml  status=r13a  occupation=r14bkbji19  involuntary=(r31a, r36a)
**---------------------------------------------------------------------------

* hour: total working hours of all jobs (week)
cap confirm variable r28b_jml
if !_rc {
    cap drop hour
    gen hour = r28b_jml if employment == 1
}
else {
    cap gen hour = .
}

* underemp: hour<35 & employed
cap drop underemp
gen underemp = 1 if hour < 35 & hour > 0
replace underemp = 0 if hour == 0
replace underemp = 0 if hour >= 35 & hour != .

* underemp_invol & underemp_vol (legacy formula)
cap drop underemp_invol underemp_vol
gen underemp_invol = .
cap confirm variable r31a
local has_i1 = !_rc
cap confirm variable r36a
local has_i2 = !_rc
if `has_i1' & `has_i2' {
    replace underemp_invol = 0 if underemp == 1
    replace underemp_invol = 1 if (r31a == 1 | r36a == 1) & underemp == 1
}
gen underemp_vol = .
replace underemp_vol = 1 if underemp == 1 & underemp_invol == 0
replace underemp_vol = 0 if underemp == 1 & underemp_invol == 1

* hour decomposed
cap drop hour_under hour_vol hour_invol
gen hour_under = hour if underemp == 1
gen hour_vol   = hour if underemp_vol == 1
gen hour_invol = hour if underemp_invol == 1

* status (employment status, 1-7)
cap drop status
cap confirm variable r13a
if !_rc {
    gen status = r13a if employment == 1
    replace status = . if status == 0
}
else {
    gen status = .
}

* worktype (1-digit code; take first digit if multi-digit)
cap drop worktype
cap confirm variable r14bkbji19
if !_rc {
    gen _wt_raw = r14bkbji19 if employment == 1
    gen worktype = .
    replace worktype = real(substr(string(int(abs(_wt_raw))), 1, 1)) if _wt_raw != . & _wt_raw > 0
    replace worktype = _wt_raw if abs(_wt_raw) < 10 & _wt_raw != .
    drop _wt_raw
}
else {
    gen worktype = .
}

* formal_simple: status in (3,4)
cap drop formal_simple
gen formal_simple = inrange(status, 3, 4) if status != . & employment == 1

* formal_new: wrktype2011 matrix
cap drop formal_new
gen formal_new = .
replace formal_new = wrktype2011[status, worktype] ///
    if status != . & worktype != . & employment == 1 ///
    & inrange(status, 1, 7) & inrange(worktype, 1, 8)

* formal_old: formal_new + casual workers in agri/construction
cap drop formal_old
gen formal_old = formal_new
replace formal_old = 1 if (status == 5 & sector9 == 1) & employment == 1
replace formal_old = 1 if (status == 6 & sector9 == 5) & employment == 1

* labels
cap label var hour           "working hours per week (all jobs combined)"
cap label var underemp       "underemployed dummy (less than 35 hours per week)"
cap label var underemp_invol "involuntary underemployment"
cap label var underemp_vol   "voluntary underemployment"
cap label var hour_under     "weekly hours among underemployed"
cap label var hour_vol       "weekly hours among voluntary underemployed"
cap label var hour_invol     "weekly hours among involuntary underemployed"
cap label var status         "main employment status"
cap label var worktype       "main occupation (1-digit KBJI)"
cap label var formal_simple  "simplified formality (employee or assisted employer)"
cap label var formal_new     "formality (wrktype2011 matrix)"
cap label var formal_old     "formality including casual workers in agriculture and construction"
**---------------------------------------------------------------------------
** Additional Employment Indicators
**---------------------------------------------------------------------------
cap drop employee casual_worker potential_exp
gen employee = work_status == 4 if work_status != .
gen casual_worker = inlist(work_status, 5, 6) if work_status != .
gen potential_exp = age - school_years if age != . & school_years != .
cap label var employee      "employee dummy"
cap label var casual_worker "casual worker dummy"
cap label var potential_exp "potential work experience"

**---------------------------------------------------------------------------
** Education Major Classification
**---------------------------------------------------------------------------
cap drop educ_major
capture confirm variable R6B_KD
if !_rc {
    gen educ_major = R6B_KD
    /* Recode rules by education level:
       Different recode rules for different education levels (SMA vs Diploma/S1+)
       Codes: 0=SMP/under, 1=Sosio-hum, 2=Medika-FKH, 3=Pertanian, 4=Sains, 5=Teknik,
              6=Pendidikan, 7=Lainnya, 998=No info, 999=Other */
    capture confirm variable R6A
    if !_rc {
        recode educ_major (38 41 43/45 = 1) (42 = 4) (37 39/40 = 5) (27 46 = 998) (50 = 999) if inrange(R6A, 6, 7)
        recode educ_major (2/5 7/10 12 15/16 18 23 38 41 42/45 = 1) (13 = 2) (14 19 20 22 = 3) (6 21 24/25 42 = 4) (11 17 37 39 40 = 5) (26 = 6) (1 = 7) (27 46 = 998) (50 = 999) if R6A == 8
        recode educ_major (2/5 7/10 12 15/16 18 23 38 41 42/45 = 1) (13 = 2) (14 19 20 22 = 3) (6 21 24/25 42 = 4) (11 17 37 39 40 = 5) (26 = 6) (1 = 7) (27 46 = 998) (50 = 999) if R6A == 9
        recode educ_major (2/5 7/10 12 15/16 18 23 38 41 42/45 = 1) (13 = 2) (14 19 20 22 = 3) (6 21 24/25 42 = 4) (11 17 37 39 40 = 5) (26 = 6) (1 = 7) (27 46 = 998) (50 = 999) if inlist(R6A, 10, 11, 12, 13, 14)
    }
    label define educ_major 0 "No major (SMP or under)" 1 "Sosio-humaniora" 2 "Medika-FKH" ///
                            3 "Pertanian" 4 "Sains" 5 "Teknik" 6 "Pendidikan" 7 "Lainnya" ///
                            998 "No information" 999 "Other", replace
    label values educ_major educ_major
    label var educ_major "education major (post-2010 surveys)"
}



save $clean/clean_sakernas_`year', replace

/*************************
 * End of Sakernas 2022
 ************************/

 /*************************
 * Sakernas 2023
 * (Using WB matrix for 9-sector classification)
 ************************/

clear
set more off
local year = 2023
use $source/sakernas_`year', clear

/*-----------------------------------------------------------
   Basic Variables and Identifiers
-----------------------------------------------------------*/
gen prov`year' = KODE_PROV
gen wt         = WEIGHT
gen urban      = (KLAS == 1)
gen male       = (K4 == 1)
gen age        = K9         // WARNING: AGE OUTSIDE LF DETECTED
gen educ       = R6A

/*-----------------------------------------------------------
   Employment and Unemployment
-----------------------------------------------------------*/
gen employment = (R9A == 1 | R9B == 1 | R9C == 1 | R10 == 1)
gen unemp = .
    replace unemp = 1 if R9A == 2 & R10 == 2 & R31A == 1 & employment == 0
    replace unemp = 1 if R9A == 2 & R10 == 2 & R31B == 1 & employment == 0
    replace unemp = 1 if R9A == 2 & inlist(R35A, 1, 2, 3) & employment == 0
    replace unemp = 0 if unemp != 1
replace employment = 0 if unemp == 1
gen lf = .
replace lf = 1 if employment == 1 | unemp == 1
replace lf = 0 if lf != 1
replace unemp = . if lf == 0
replace employment = . if lf == 0
* (Optionally, you may use "keep if age >= 15" here)

/*-----------------------------------------------------------
   Sector Classification (standard)
-----------------------------------------------------------*/
gen sector17 = R14AKATEGO
* (No additional filter on sector17 here)

#delim ;
	recode sector17
		(0		= .)
		(1		= 1)
		(2		= 2)
		(3		= 3)
		(4/5	= 4)
		(6		= 5)
		(7 9	= 6)
		(8 10	= 7)
		(11/13	= 8)
		(14/17	= 9),
		gen(sector9);
#delim cr

label define sector9 1 "Agriculture, forestry, livestock and fishing" ///
                      2 "Mining and quarrying" ///
                      3 "Manufacturing" ///
                      4 "Electricity, gas, and water supply" ///
                      5 "Construction" ///
                      6 "Wholesale and retail trade, restaurants and hotels" ///
                      7 "Transportation, storage and communications" ///
                      8 "Finance, insurance, real estate and business services" ///
                      9 "Community, social and personal services" ///
                      10 "Others"
label values sector9 sector9

/*-----------------------------------------------------------
   Work-Related Variables
-----------------------------------------------------------*/
gen work_informal = inlist(R13A, 1, 2, 5, 6, 7)
gen work_status   = R13A
gen work_certif   = (R6D == 1)
    replace work_certif = . if lf == 0
gen work_whitecoll = inrange(R14BKBJI19, 1, 5)

/*-----------------------------------------------------------
   Non-Labor Force Activity Dummies
-----------------------------------------------------------*/
gen act_school    = ( (R43A == 1 | R43A == 2) & R43D == 1 & lf == 0 )
gen act_household = ( (R43B == 1 | R43B == 2) & R43D == 2 & lf == 0 )
gen others = 0
    replace others = 1 if others == 0   // set others to 1 if not already (dummy for non-education/non-household)
gen act_others    = (lf == 0 & others == 1)
gen act_neet = 0
    replace act_neet = 1 if R9A == 2 & R43A == 2
    replace act_neet = 0 if act_school == 1
    replace act_neet = . if age >= 25 | age <= 14

/*-----------------------------------------------------------
   Work Outcome Variables
-----------------------------------------------------------*/
gen work_hours = R18A_BLT
    replace work_hours = . if employment != 1
gen work_earnings = R15_UANG + R15_BRG
    replace work_earnings = 0 if work_earnings < 0
    replace work_earnings = . if employment != 1
gen work_wage = (R15_UANG + R15_BRG) if R13A == 4
    replace work_wage = 0 if work_wage < 0
    replace work_wage = . if employment != 1
gen work_jobdur = (R33_TH * 12) + R33_BLN
    replace work_jobdur = . if work_jobdur == 0

/*-----------------------------------------------------------
   Recodes and Derived Variables
-----------------------------------------------------------*/
recode educ 1/2 = 1 3/6 = 2 7/12 = 3, generate(educ_group)
recode work_jobdur 0/3 = 1 4/12 = 2 12/24 = 3 25/9999 = 4, gen(work_jobdur_cat)
gen school_years = .
replace school_years = 0 if educ == 1
replace school_years = 6 if educ == 2
replace school_years = 9 if educ == 3
replace school_years = 12 if educ == 4
replace school_years = 12 if educ == 5
replace school_years = 15 if educ == 6
replace school_years = 16 if educ == 7

/*-----------------------------------------------------------
   Job Search Duration Dummies
-----------------------------------------------------------*/
la de searchdur 1 "1. <=3 bulan" 2 "2. 4-12 bulan" 3 "3. 13-24 bulan" 4 "4. >24 bulan"
la val work_jobdur_cat searchdur
forval x = 1/4 {
    gen work_searchdur_`x' = (work_jobdur_cat == `x')
    replace work_searchdur_`x' = . if lf == 0 | work_jobdur_cat == .
}
foreach var of varlist work_hours work_earnings work_wage {
    replace `var' = . if unemp == 1 | lf == 0
}

/*-----------------------------------------------------------
   Finalize and Save 2023 Data
-----------------------------------------------------------*/
gen year = `year'
// save "$output/temp_sakernas_`year'", replace

*-----------------------------------------------------------
* 2022 Clean Data 
*-----------------------------------------------------------

keep prov`year' wt urban male age educ unemp employment lf school_years sector9 sector17 work_informal work_status ///
     act_neet act_school act_household act_others work_hours work_whitecoll work_earnings work_wage work_jobdur* ///
     educ_group work_searchdur_* year work_certif

**---------------------------------------------------------------------------
** Derived Labour Indicators (2023: limited raw data, set to missing)
**---------------------------------------------------------------------------
foreach v in hour underemp underemp_invol underemp_vol hour_under hour_vol hour_invol status worktype formal_simple formal_new formal_old {
    cap gen `v' = .
}

save $clean/clean_sakernas_`year', replace

/*************************
 * End of Sakernas 2023
 ************************/

 /*************************
 * Sakernas 2024
 * (Using WB matrix for 9-sector classification; merging two source files and renaming variables to upper case)
 ************************/

clear
set more off
local year = 2024
use $source/sakernas_`year'_1, clear
merge 1:1 urutan using $source/sakernas_`year'_2, nogen
foreach v of varlist _all {
    capture rename `v' `=upper("`v'")'
}

/*-----------------------------------------------------------
   Basic Variables and Identifiers
-----------------------------------------------------------*/
gen prov`year' = KODE_PROV
gen wt         = WEIGHT
gen urban      = (KLAS == 1)
gen male       = (K4 == 1)
gen age        = K10         // WARNING: AGE OUTSIDE LF DETECTED
gen educ       = R6A

/*-----------------------------------------------------------
   Employment and Unemployment
-----------------------------------------------------------*/
gen employment = (R10A == 1 | R10B == 1 | R10C == 1 | R11 == 1)
gen unemp = .
    replace unemp = 1 if R10A == 2 & R11 == 2 & R38A == 1 & employment == 0
    replace unemp = 1 if R10A == 2 & R11 == 2 & R38B == 1 & employment == 0
    replace unemp = 1 if R10A == 2 & inlist(R42A, 1, 2, 3) & employment == 0
    replace unemp = 0 if unemp != 1
replace employment = 0 if unemp == 1
gen lf = .
replace lf = 1 if employment == 1 | unemp == 1
replace lf = 0 if age < 15
replace lf = 0 if lf != 1
replace unemp = . if lf == 0
replace employment = . if lf == 0
* (Optionally, keep if age >= 15)

/*-----------------------------------------------------------
   Sector Classification (standard)
-----------------------------------------------------------*/
gen sector17 = R15A_KBLI2
replace sector17 = . if sector17 == 0

#delim ;
	recode sector17
		(0		= .)
		(1		= 1)
		(2		= 2)
		(3		= 3)
		(4/5	= 4)
		(6		= 5)
		(7 9	= 6)
		(8 10	= 7)
		(11/13	= 8)
		(14/17	= 9),
		gen(sector9);
#delim cr

label define sector9 1 "Agriculture, forestry, livestock and fishing" ///
                      2 "Mining and quarrying" ///
                      3 "Manufacturing" ///
                      4 "Electricity, gas, and water supply" ///
                      5 "Construction" ///
                      6 "Wholesale and retail trade, restaurants and hotels" ///
                      7 "Transportation, storage and communications" ///
                      8 "Finance, insurance, real estate and business services" ///
                      9 "Community, social and personal services" ///
                      10 "Others"
label values sector9 sector9

/*-----------------------------------------------------------
   Work-Related Variables
-----------------------------------------------------------*/
gen work_informal = inlist(R14A, 1, 2, 5, 6, 7)
gen work_status   = R14A
gen work_certif   = (R6D == 1)
    replace work_certif = . if lf == 0
gen work_whitecoll = inrange(R15B_KBJI2, 1, 5)

/*-----------------------------------------------------------
   Non-Labor Force Activity Dummies
-----------------------------------------------------------*/
gen act_school    = (R50A == 1 & R50D == 1 & lf == 0)
gen act_household = (R50B == 1 & R50D == 2 & lf == 0)
gen others = 0
    replace others = 1 if others == 0
gen act_others    = (lf == 0 & others == 1)
gen act_neet = 0
    replace act_neet = 1 if R10A == 2 & R50A == 2
    replace act_neet = 0 if act_school == 1
    replace act_neet = . if age >= 25 | age <= 14

/*-----------------------------------------------------------
   Work Outcome Variables
-----------------------------------------------------------*/
gen work_hours = R19A_BLT
    replace work_hours = . if employment != 1
gen work_earnings = R16_1 + R16_2
    replace work_earnings = 0 if work_earnings < 0
    replace work_earnings = . if employment != 1
gen work_wage = (R16_1 + R16_2) if R14A == 4
    replace work_wage = 0 if work_wage < 0
    replace work_wage = . if employment != 1
gen work_jobdur = (R40_TH * 12) + R40_BLN
    replace work_jobdur = . if work_jobdur == 0

/*-----------------------------------------------------------
   Recodes and Derived Variables
-----------------------------------------------------------*/
recode educ 1/2 = 1 3/6 = 2 7/12 = 3, generate(educ_group)
recode work_jobdur 0/3 = 1 4/12 = 2 12/24 = 3 25/9999 = 4, gen(work_jobdur_cat)
gen school_years = .
replace school_years = 0 if educ == 1
replace school_years = 6 if educ == 2
replace school_years = 9 if educ == 3
replace school_years = 12 if educ == 4
replace school_years = 12 if educ == 5
replace school_years = 15 if educ == 6
replace school_years = 16 if educ == 7

/*-----------------------------------------------------------
   Job Search Duration Dummies
-----------------------------------------------------------*/
la de searchdur 1 "1. <=3 bulan" 2 "2. 4-12 bulan" 3 "3. 13-24 bulan" 4 "4. >24 bulan"
la val work_jobdur_cat searchdur
forval x = 1/4 {
    gen work_searchdur_`x' = (work_jobdur_cat == `x')
    replace work_searchdur_`x' = . if lf == 0 | work_jobdur_cat == .
}
foreach var of varlist work_hours work_earnings work_wage {
    replace `var' = . if unemp == 1 | lf == 0
}

/*-----------------------------------------------------------
   Finalize and Save 2024 Data
-----------------------------------------------------------*/
gen year = `year'
//save "$output/temp_sakernas_`year'", replace

*-----------------------------------------------------------
* 2024 Clean Data (standard)
*-----------------------------------------------------------

keep prov`year' wt urban male age educ unemp employment lf school_years sector9 sector17 work_informal work_status ///
     act_neet act_school act_household act_others work_hours work_whitecoll work_earnings work_wage work_jobdur* ///
     educ_group work_searchdur_* year work_certif
save $clean/clean_sakernas_`year', replace

/*************************
 * End of Sakernas 2024
 ************************/
 
/************************************************************
 ***************	APPENDING SECTION		*****************
 ************************************************************/

   
 *------------------------------------------------------------
* Aligning the prov code
*------------------------------------------------------------

 forvalues y = 2001/2024 {
    use $clean/clean_sakernas_`y', clear
    capture confirm variable prov`y'
        rename prov`y' prov
    save $clean/clean_sakernas_`y', replace
    }
	
*------------------------------------------------------------
* Connecting across the years (1997-2024)
*------------------------------------------------------------

 use $clean/clean_sakernas_2001
 gl finaloutput "your/path/your_project_root/finaloutput"
 forvalues y = 2001/2024 {
    append using $clean/clean_sakernas_`y', force
 }
   save $finaloutput/final_sakernas_97_24, replace
   
*------------------------------------------------------------
* Generating some additional variables
*------------------------------------------------------------

// dropping underage population
// drop if age < 15

* under employment
gen underemp = 1 if work_hours < 35
replace underemp = 0 if work_hours == 0
replace underemp = 0 if work_hours >= 35 & work_hours != .
ta underemp [iw = wt]

* dummy of agriculture
gen agriculture = sector9==1

* productive age
gen pop15_64 = inrange(age, 15, 64)

* 3 sectors of employment (primary, secondary, & tertiary)*gen sector3 = b5_r23_3 if employed==1 & b5_r23_sek!=0
#delim ;
	recode sector9
		(0	 = .)
		(1	 = 1)
		(2/5 = 2)
		(6/19= 3),
		gen(sector3);
#delim cr

* provinces
recode prov (92 = 91) (95 96 97 = 94), gen(prov_34)
label define province 11 "Aceh" 12 "North Sumatera" 13 "West Sumatera" 14 "Riau" ///
15 "Jambi" 16 "South Sumatera" 17 "Bengkulu" 18 "Lampung" 19 "Bangka-Belitung" ///
21 "Kep Riau" 31 "DKI Jakarta" 32 "West Java" 33 "Central Java" 34 "DI Yogjakarta" 35 "East Java" ///
36 "Banten" 51 "Bali" 52 "West Nusa Tenggara" 53 "East Nusa Tenggara" 61 "West Kalimantan" 62 "Central Kalimantan" ///
63 "South Kalimantan" 64 "East Kalimantan" 65 "North Kalimantan" 71 "North Sulawesi" 72 "Central Sulawesi" ///
73 "South Sulawesi" 74 "Southeast Sulawesi" 75 "Gorontalo" 76 "West Sulawesi" ///
81 "Maluku" 82 "North Maluku" 91 "West Papua" 94 "Papua"
label values prov_34 province

* regions
gen region = 1 if prov <=21
replace region = 2 if inrange(prov,22,51)
replace region = 3 if inrange(prov,60,69)
replace region = 4 if inrange(prov,70,79)
replace region = 5 if inrange(prov,52,53)
replace region = 6 if inrange(prov,81,82)
replace region = 7 if inrange(prov,91,97)
label define region 1 "Sumatera" 2 "Java/Bali" 3 "Kalimantan" 4 "Sulawesi" 5 "Nusa Tenggara" 6 "Maluku" 7 "Papua"
label values region region

* age grouping

gen agegroup=recode(age,14,19,24,29,34,39,44,49,54,59,98)
recode agegroup 14=0 19=1 24=2 29=3 34=4 39=5 44=6 49=7 54=8 59=9 98=10
label define agegroup2 0 "<15" 1 "15-19" 2"20-24" 3"25-29" 4"30-34" 5"35-39" ///
6"40-44" 7"45-49" 8"50-54" 9"55-59" 10">=60"
label values agegroup agegroup2

*------------------------------------------------------------
* Labelling variables
*------------------------------------------------------------

*label var hhhead "dummy head of hh"
label var male "gender"
label var urban "urban/rural"
label var age "age (theres still <15 in 1997-2010)" // theres still <15 between 1997-2010 
label var agegroup "age group"
label var educ "education level (be cautious different metrics each year)"
label var educ_group "educ group"
label var school_years "years of schooling"
label var region "region of 7 big islands"
label var prov "province name"
label var lf "labor force"
label var act_school "student (non-labor force)"
label var act_household "housekeeping (non-labor force)"
label var act_others "others category (non-labor force)"
label var act_neet "not in education, employment, or training "
label var employment "dummy of employed among labor force"
label var underemp "dummy underemployed: people who work < 35 hours in a week (main job)" 
label var unemp "dummy of open unemployed among labor force"
*label var kbli21 "21 sectors of employment according to KBLI 2009"
*label var kbli63 "2 digits of sectors of employment according to KBLI 2005"
*label var kbli2005_2 "2 digits of sectors of employment according to KBLI 2005"
*label var kbli88 "2 digits of sectors of employment according to KBLI 2009"
*label var kbli2009 "2 digits of sectors of employment according to KBLI 2009"
label var sector9 "9 sectors of employment kbli2000"
label var sector17 "17 sectors of employment kbli2014"
label var sector3 "3 sectors of employment"
label var agriculture "dummy of agriculture"
*label var kji "main occupation"
*label var worktype "type of work"
label var work_status "status of employment"
label var work_whitecoll "dummy of white-collar worker"
label var work_informal "formality based on simplified definition"
label var work_hours "working hours in week of main job (second job not included)"
label var work_earnings "nominal monthly earnings for worker"
label var work_wage "nominal monthly wage for employee"
label var work_certif "dummy of worker with certification"
label var work_jobdur "job search duration (month level)"
label var work_jobdur_cat "job search duration (categorical)"
label var work_searchdur_1 "<= 3 months of job search duration"
label var work_searchdur_2 "4-12 months of job search duration"
label var work_searchdur_3 "13-24 months of job search duration"
label var work_searchdur_4 ">24 months of job search duration"

* label var realmwage_employ "real monthly income for employee"
label var year "year of the survey"
label var month "month of the survey"
*gen weight=weightbc
label var wt "individual weight"
label var pop15_64 "dummy for person with age 15-64"
*label var subsector "subsector of employment"
*label var minwage "provincial minimum wage"


**---------------------------------------------------------------------------
** Working Hours, Underemployment, Status, and Formality Indicators (2024)
** Raw inputs: hours=r35a_jml  status=r14a  occupation=r15b_kbji1  involuntary=(r38a, r43a)
**---------------------------------------------------------------------------

* hour: total working hours of all jobs (week)
cap confirm variable r35a_jml
if !_rc {
    cap drop hour
    gen hour = r35a_jml if employment == 1
}
else {
    cap gen hour = .
}

* underemp: hour<35 & employed
cap drop underemp
gen underemp = 1 if hour < 35 & hour > 0
replace underemp = 0 if hour == 0
replace underemp = 0 if hour >= 35 & hour != .

* underemp_invol & underemp_vol (legacy formula)
cap drop underemp_invol underemp_vol
gen underemp_invol = .
cap confirm variable r38a
local has_i1 = !_rc
cap confirm variable r43a
local has_i2 = !_rc
if `has_i1' & `has_i2' {
    replace underemp_invol = 0 if underemp == 1
    replace underemp_invol = 1 if (r38a == 1 | r43a == 1) & underemp == 1
}
gen underemp_vol = .
replace underemp_vol = 1 if underemp == 1 & underemp_invol == 0
replace underemp_vol = 0 if underemp == 1 & underemp_invol == 1

* hour decomposed
cap drop hour_under hour_vol hour_invol
gen hour_under = hour if underemp == 1
gen hour_vol   = hour if underemp_vol == 1
gen hour_invol = hour if underemp_invol == 1

* status (employment status, 1-7)
cap drop status
cap confirm variable r14a
if !_rc {
    gen status = r14a if employment == 1
    replace status = . if status == 0
}
else {
    gen status = .
}

* worktype (1-digit code; take first digit if multi-digit)
cap drop worktype
cap confirm variable r15b_kbji1
if !_rc {
    gen _wt_raw = r15b_kbji1 if employment == 1
    gen worktype = .
    replace worktype = real(substr(string(int(abs(_wt_raw))), 1, 1)) if _wt_raw != . & _wt_raw > 0
    replace worktype = _wt_raw if abs(_wt_raw) < 10 & _wt_raw != .
    drop _wt_raw
}
else {
    gen worktype = .
}

* formal_simple: status in (3,4)
cap drop formal_simple
gen formal_simple = inrange(status, 3, 4) if status != . & employment == 1

* formal_new: wrktype2011 matrix
cap drop formal_new
gen formal_new = .
replace formal_new = wrktype2011[status, worktype] ///
    if status != . & worktype != . & employment == 1 ///
    & inrange(status, 1, 7) & inrange(worktype, 1, 8)

* formal_old: formal_new + casual workers in agri/construction
cap drop formal_old
gen formal_old = formal_new
replace formal_old = 1 if (status == 5 & sector9 == 1) & employment == 1
replace formal_old = 1 if (status == 6 & sector9 == 5) & employment == 1

* labels
cap label var hour           "working hours per week (all jobs combined)"
cap label var underemp       "underemployed dummy (less than 35 hours per week)"
cap label var underemp_invol "involuntary underemployment"
cap label var underemp_vol   "voluntary underemployment"
cap label var hour_under     "weekly hours among underemployed"
cap label var hour_vol       "weekly hours among voluntary underemployed"
cap label var hour_invol     "weekly hours among involuntary underemployed"
cap label var status         "main employment status"
cap label var worktype       "main occupation (1-digit KBJI)"
cap label var formal_simple  "simplified formality (employee or assisted employer)"
cap label var formal_new     "formality (wrktype2011 matrix)"
cap label var formal_old     "formality including casual workers in agriculture and construction"
**---------------------------------------------------------------------------
** Additional Employment Indicators
**---------------------------------------------------------------------------
cap drop employee casual_worker potential_exp
gen employee = work_status == 4 if work_status != .
gen casual_worker = inlist(work_status, 5, 6) if work_status != .
gen potential_exp = age - school_years if age != . & school_years != .
cap label var employee      "employee dummy"
cap label var casual_worker "casual worker dummy"
cap label var potential_exp "potential work experience"

**---------------------------------------------------------------------------
** Education Major Classification
**---------------------------------------------------------------------------
cap drop educ_major
capture confirm variable R6B_J_KD
if !_rc {
    gen educ_major = R6B_J_KD
    /* Recode rules by education level:
       Different recode rules for different education levels (SMA vs Diploma/S1+)
       Codes: 0=SMP/under, 1=Sosio-hum, 2=Medika-FKH, 3=Pertanian, 4=Sains, 5=Teknik,
              6=Pendidikan, 7=Lainnya, 998=No info, 999=Other */
    capture confirm variable R6A
    if !_rc {
        recode educ_major (38 41 43/45 = 1) (42 = 4) (37 39/40 = 5) (27 46 = 998) (50 = 999) if inrange(R6A, 6, 7)
        recode educ_major (2/5 7/10 12 15/16 18 23 38 41 42/45 = 1) (13 = 2) (14 19 20 22 = 3) (6 21 24/25 42 = 4) (11 17 37 39 40 = 5) (26 = 6) (1 = 7) (27 46 = 998) (50 = 999) if R6A == 8
        recode educ_major (2/5 7/10 12 15/16 18 23 38 41 42/45 = 1) (13 = 2) (14 19 20 22 = 3) (6 21 24/25 42 = 4) (11 17 37 39 40 = 5) (26 = 6) (1 = 7) (27 46 = 998) (50 = 999) if R6A == 9
        recode educ_major (2/5 7/10 12 15/16 18 23 38 41 42/45 = 1) (13 = 2) (14 19 20 22 = 3) (6 21 24/25 42 = 4) (11 17 37 39 40 = 5) (26 = 6) (1 = 7) (27 46 = 998) (50 = 999) if inlist(R6A, 10, 11, 12, 13, 14)
    }
    label define educ_major 0 "No major (SMP or under)" 1 "Sosio-humaniora" 2 "Medika-FKH" ///
                            3 "Pertanian" 4 "Sains" 5 "Teknik" 6 "Pendidikan" 7 "Lainnya" ///
                            998 "No information" 999 "Other", replace
    label values educ_major educ_major
    label var educ_major "education major (post-2010 surveys)"
}



    save $finaloutput/final_sakernas_97_24, replace


*------------------------------------------------------------
* POVERTY LINE
*------------------------------------------------------------
merge m:m year prov using "your/path/your_project_root/poverty line/pl_prov.dta", nogen

merge m:m year prov using "your/path/your_project_root/poverty line/pl_nasional.dta", nogen

*------------------------------------------------------------
* GENERATING CLASS STATUS
*------------------------------------------------------------
 
 replace work_wage = 0 if work_wage ==.
 gen poor = work_wage < (pl_urban_prov * 4) / 1.5 if urban == 1 & employment == 1 & work_wage > 0
replace poor = work_wage < (pl_rural_prov * 4) / 1.5 if urban == 0 & employment == 1 & work_wage > 0

//tab poor [iw = weight]

* Socioeconomic class (susenas way)
gen vul = work_wage > (pl_urban_prov * 4) / 1.5 & work_wage <= (1.5 * pl_urban_prov * 4) / 1.5 if urban == 1 & employment == 1 & work_wage > 0
gen asp = work_wage > (1.5 * pl_urban_prov * 4) / 1.5 & work_wage <= (3.5 * pl_urban_prov * 4) / 1.5 if urban == 1 & employment == 1 & work_wage > 0
gen mid = work_wage > (3.5 * pl_urban_prov * 4) / 1.5 & work_wage <= (17 * pl_urban_prov * 4) / 1.5 if urban == 1 & employment == 1 & work_wage > 0
gen upp = work_wage > (17 * pl_urban_prov * 4) / 1.5 if urban == 1 & employment == 1 & work_wage > 0

replace vul = work_wage > (pl_rural_prov * 4) / 1.5 & work_wage <= (1.5 * pl_rural_prov * 4) / 1.5 if urban == 0 & employment == 1 & work_wage > 0
replace asp = work_wage > (1.5 * pl_rural_prov * 4) / 1.5 & work_wage <= (3.5 * pl_rural_prov * 4) / 1.5 if urban == 0 & employment == 1 & work_wage > 0
replace mid = work_wage > (3.5 * pl_rural_prov * 4) / 1.5 & work_wage <= (17 * pl_rural_prov * 4) / 1.5 if urban == 0 & employment == 1 & work_wage > 0
replace upp = work_wage > (17 * pl_rural_prov * 4) / 1.5 if urban == 0 & employment == 1 & work_wage > 0

gen social_status = poor
replace social_status = 2 if vul == 1
replace social_status = 3 if asp == 1
replace social_status = 4 if mid == 1
replace social_status = 5 if upp == 1

label define status 1 "Poor" ///
                     2 "Vulnerable" ///
                     3 "Aspiring" ///
                     4 "Middle" ///
                     5 "Upper"
label values social_status status


*------------------------------------------------------------
* MINIMUM WAGE
*------------------------------------------------------------

merge m:m year prov using "your/path/Provincial Minimum Wage 1997-2024.dta", nogen

gen under_ump = work_wage < minwage


label define work_status  ///
 1 "self employed" ///
 2 "own account" ///
 3 "employer" ///
 4 "employee" ///
 5 "agriculture freelance" ///
 6 "nonagriculture freelance" ///
 7 "family/unpaid worker"
 label value work_status work_status




**==============================================================
** Earnings-Based Socioeconomic Classification & External Indicators
** Requires external reference files (poverty line, minimum wage, GDRP, CPI).
** Applied after per-year processing, before final append into pooled datasets.
**
** Edit these globals to point at your external files:
**==============================================================
global povline_prov   "your/path/to/poverty_line_provincial.dta"   /* needs: year, prov, pl_urban_prov, pl_rural_prov */
global povline_natl   "your/path/to/poverty_line_national.dta"     /* needs: year, urban_national, rural_national */
global minwage_file   "your/path/to/Provincial_Minimum_Wage_1997-2024.dta"  /* needs: year, prov, minwage */
global gdrp_file      "your/path/to/gdrp_provincial.dta"           /* needs: year, prov, d18 (GDRP value) */
global cpi_file       "your/path/to/CPI_capital_city.dta"          /* needs: year, prov, cpi2022rebase */

/* Apply earnings classification and external indicator merges (skipped if files unavailable) */
foreach year of numlist 2001/2024 {

    capture confirm file "$clean/clean_sakernas_`year\'.dta"
    if _rc continue

    use "$clean/clean_sakernas_`year\'.dta", clear

    *----- Earnings class using provincial poverty line -----
    capture confirm file "$povline_prov"
    if !_rc {
        merge m:1 year prov using "$povline_prov", keep(match master) nogen

        gen poor_earn = work_earnings < (pl_urban_prov * 4) / 1.5 if urban == 1 & employment == 1 & work_earnings != .
        replace poor_earn = work_earnings < (pl_rural_prov * 4) / 1.5 if urban == 0 & employment == 1 & work_earnings != .

        gen vul_earn = work_earnings > (pl_urban_prov * 4) / 1.5 & work_earnings <= (1.5 * pl_urban_prov * 4) / 1.5 if urban == 1 & employment == 1 & work_earnings != .
        gen asp_earn = work_earnings > (1.5 * pl_urban_prov * 4) / 1.5 & work_earnings <= (3.5 * pl_urban_prov * 4) / 1.5 if urban == 1 & employment == 1 & work_earnings != .
        gen mid_earn = work_earnings > (3.5 * pl_urban_prov * 4) / 1.5 & work_earnings <= (17 * pl_urban_prov * 4) / 1.5 if urban == 1 & employment == 1 & work_earnings != .
        gen upp_earn = work_earnings > (17 * pl_urban_prov * 4) / 1.5 if urban == 1 & employment == 1 & work_earnings != .

        replace vul_earn = work_earnings > (pl_rural_prov * 4) / 1.5 & work_earnings <= (1.5 * pl_rural_prov * 4) / 1.5 if urban == 0 & employment == 1 & work_earnings != .
        replace asp_earn = work_earnings > (1.5 * pl_rural_prov * 4) / 1.5 & work_earnings <= (3.5 * pl_rural_prov * 4) / 1.5 if urban == 0 & employment == 1 & work_earnings != .
        replace mid_earn = work_earnings > (3.5 * pl_rural_prov * 4) / 1.5 & work_earnings <= (17 * pl_rural_prov * 4) / 1.5 if urban == 0 & employment == 1 & work_earnings != .
        replace upp_earn = work_earnings > (17 * pl_rural_prov * 4) / 1.5 if urban == 0 & employment == 1 & work_earnings != .

        gen status_earn = poor_earn
        replace status_earn = 2 if vul_earn == 1
        replace status_earn = 3 if asp_earn == 1
        replace status_earn = 4 if mid_earn == 1
        replace status_earn = 5 if upp_earn == 1
        label define status_earn 1 "Poor" 2 "Vulnerable" 3 "Aspiring" 4 "Middle" 5 "Upper", replace
        label values status_earn status_earn
        label var status_earn "socioeconomic class (provincial poverty line)"
        foreach v in poor_earn vul_earn asp_earn mid_earn upp_earn {
            label var `v' "earnings class dummy (provincial poverty line)"
        }
    }

    *----- Earnings class using national poverty line -----
    capture confirm file "$povline_natl"
    if !_rc {
        merge m:1 year using "$povline_natl", keep(match master) nogen

        gen poor_earn_national = work_earnings < (urban_national * 4) / 1.5 if urban == 1 & employment == 1 & work_earnings != .
        replace poor_earn_national = work_earnings < (rural_national * 4) / 1.5 if urban == 0 & employment == 1 & work_earnings != .

        gen vul_earn_national = work_earnings > (urban_national * 4) / 1.5 & work_earnings <= (1.5 * urban_national * 4) / 1.5 if urban == 1 & employment == 1 & work_earnings != .
        gen asp_earn_national = work_earnings > (1.5 * urban_national * 4) / 1.5 & work_earnings <= (3.5 * urban_national * 4) / 1.5 if urban == 1 & employment == 1 & work_earnings != .
        gen mid_earn_national = work_earnings > (3.5 * urban_national * 4) / 1.5 & work_earnings <= (17 * urban_national * 4) / 1.5 if urban == 1 & employment == 1 & work_earnings != .
        gen upp_earn_national = work_earnings > (17 * urban_national * 4) / 1.5 if urban == 1 & employment == 1 & work_earnings != .

        replace vul_earn_national = work_earnings > (rural_national * 4) / 1.5 & work_earnings <= (1.5 * rural_national * 4) / 1.5 if urban == 0 & employment == 1 & work_earnings != .
        replace asp_earn_national = work_earnings > (1.5 * rural_national * 4) / 1.5 & work_earnings <= (3.5 * rural_national * 4) / 1.5 if urban == 0 & employment == 1 & work_earnings != .
        replace mid_earn_national = work_earnings > (3.5 * rural_national * 4) / 1.5 & work_earnings <= (17 * rural_national * 4) / 1.5 if urban == 0 & employment == 1 & work_earnings != .
        replace upp_earn_national = work_earnings > (17 * rural_national * 4) / 1.5 if urban == 0 & employment == 1 & work_earnings != .

        gen status_earn_national = poor_earn_national
        replace status_earn_national = 2 if vul_earn_national == 1
        replace status_earn_national = 3 if asp_earn_national == 1
        replace status_earn_national = 4 if mid_earn_national == 1
        replace status_earn_national = 5 if upp_earn_national == 1
        label define status_earn_nat 1 "Poor" 2 "Vulnerable" 3 "Aspiring" 4 "Middle" 5 "Upper", replace
        label values status_earn_national status_earn_nat
        label var status_earn_national "socioeconomic class (national poverty line)"
        foreach v in poor_earn_national vul_earn_national asp_earn_national mid_earn_national upp_earn_national {
            label var `v' "earnings class dummy (national poverty line)"
        }
    }

    *----- External indicators: minimum wage, GDRP, CPI -----
    capture confirm file "$minwage_file"
    if !_rc {
        merge m:1 year prov using "$minwage_file", keep(match master) nogen
    }
    capture confirm file "$gdrp_file"
    if !_rc {
        merge m:1 year prov using "$gdrp_file", keep(match master) nogen
        cap gen ln_gdrp = log(d18)
        cap label var ln_gdrp "log of regional gross domestic product"
    }
    capture confirm file "$cpi_file"
    if !_rc {
        merge m:1 year prov using "$cpi_file", keep(match master) nogen
        cap gen real_minwage = minwage * (100 / cpi2022rebase)
        cap label var real_minwage "real minimum wage (2022 base year)"
    }

    save "$clean/clean_sakernas_`year'.dta", replace
}

**==============================================================
** Build Pooled Datasets
**==============================================================

* ----- Pooled 2010-2024 -----
clear
foreach y of numlist 2010/2024 {
    cap append using "$clean/clean_sakernas_`y\'.dta", force
    if !_rc di "  appended `y'"
}
compress
save "$clean/clean_sakernas_10_24.dta", replace
di "Pooled 2010-2024 saved"

* ----- Pooled 1997-2024 -----
clear
foreach y of numlist 1997/2024 {
    cap append using "$clean/clean_sakernas_`y\'.dta", force
    if !_rc di "  appended `y'"
}
compress
save "$clean/clean_sakernas_97_24.dta", replace
di "Pooled 1997-2024 saved"

di _newline "===== PIPELINE DONE ====="
