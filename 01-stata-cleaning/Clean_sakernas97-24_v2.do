
/**************************************************************************
 * Project       : Sakernas Data Processing – 1997-2024
 * Author        : Kelvin Ramadhan H
 * Date          : March, 02 2024
 * Description   : Import, recode, clean, and append Sakernas 1997-2024 data.
 * Institution	 : TNP2K (tim asistensi kebijakan)
 **************************************************************************/

 /*
Big thanks to Mas Iman Satya for laying the dofile foundation 
*/

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
if inlist("$user", "kelvinramadhan") {
    cd /Users/kelvinramadhan/Documents/
}

gl source  "TNP2K/Middle-Class/sakernas"
gl import  "TNP2K/Middle-Class/import"
gl output  "TNP2K/Middle-Class/output"
gl dofile  "TNP2K/Middle-Class/dofile"
gl comp    "TNP2K/Middle-Class/compressed"
gl clean   "TNP2K/Middle-Class/clean"
gl finaloutput "TNP2K/Middle-Class/finaloutput"

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

*-----------------------------------------------------------
* SET YEAR AND IMPORT DATA
*-----------------------------------------------------------

/*************************************************************
 * Sakernas 1997 - August period (numbers matched)
 *************************************************************/
 
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
gen month		 = "8"

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

* Matching employment statistics with BPS report (manual adjustments)
replace employment = 1 if employment == 0 & work_status != .

*-----------------------------------------------------------
* Non-Labor Force Activity Dummies
*-----------------------------------------------------------
gen act_school    = (B4P4A2 == 1 & B4P4B == 2 & lf == 0)
gen act_household = (B4P4A3 == 1 & B4P4B == 3 & lf == 0)
gen act_others    = (B4P4A5 == 1 & B4P4B == 5 & lf == 0)

* NEET (Not in Education, Employment, or Training)
	gen act_neet = 1
	replace act_neet = 0 if employment == 1
	replace act_neet = 0 if inlist(B3P7, 2) & act_neet == 1
		//replace act_neet = 0 if b5_r7 == 2 & act_neet == 1
	replace act_neet = . if !inrange(age, 15, 24)

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
// save $output/temp_sakernas_`year', replace

*-----------------------------------------------------------
* CREATE CLEAN DATASET: KEEP ONLY SELECT VARIABLES
*-----------------------------------------------------------
keep prov`year' wt urban male age educ unemp employment lf school_years sector9 month ///
       work_informal work_status act_neet act_school act_household act_others ///
       work_hours work_whitecoll work_earnings work_wage work_jobdur* educ_group ///
       work_searchdur_* year

save $clean/clean_sakernas_`year', replace

/*************************
 * End of Sakernas 1997
 ************************/

/************************************************
 * Sakernas 1998 - August period (numbers matched)
 ***********************************************/

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
gen month		 = "8"
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

* Matching employment statistics with BPS report (manual adjustment)
replace employment = 1 if employment == 0 & work_status != .

*-----------------------------------------------------------
* Non-Labor Force Activity Dummies
*-----------------------------------------------------------
gen act_school    = (B4P2A2 == 1 & B4P2B == 2 & lf == 0)
gen act_household = (B4P2A3 == 1 & B4P2B == 3 & lf == 0)
gen others = 0 if (act_school == 1 | act_household == 1)
replace others = 1 if others == .
gen act_others= lf == 0 & others == 1
	gen act_neet = 1
	replace act_neet = 0 if employment == 1
	replace act_neet = 0 if inlist(B3P7, 2) & act_neet == 1
		//replace act_neet = 0 if b5_r7 == 2 & act_neet == 1
	replace act_neet = . if !inrange(age, 15, 24)

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
keep prov`year' wt urban male age educ unemp employment lf school_years sector9 month ///
     work_informal work_status act_neet act_school act_household act_others work_hours work_whitecoll ///
     work_earnings work_wage work_jobdur* educ_group work_searchdur_* year
save $clean/clean_sakernas_`year', replace

/*************************
 * End of Sakernas 1998
 ************************/
 
/*********************************************************
 * Sakernas 1999 - August period (numbers matched)
 ********************************************************/

clear
set more off

*-----------------------------------------------------------
* Set Year and Import Data
*-----------------------------------------------------------
local year = 1999
use $source/sakernas_`year', clear

*-----------------------------------------------------------
* Generate Basic Variables
*-----------------------------------------------------------
gen prov`year'   = B1P1
gen wt           = WEIGHT
gen urban        = (B1P5 == 1)
gen male         = (B3K4 == 1)
gen age          = B3K5            // WARNING: AGE OUTSIDE LF DETECTED
gen educ         = B4P1A
gen month		 = "8"

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

* Matching employment statistics with BPS report (manual adjustment)
replace employment = 1 if employment == 0 & work_status != .

*-----------------------------------------------------------
* Non-Labor Force Activity Dummies
*-----------------------------------------------------------
gen act_school    = (B4P2A2 == 1 & B4P2B == 2 & lf == 0)
gen act_household = (B4P2A3 == 1 & B4P2B == 3 & lf == 0)
gen others = 0 if (act_school == 1 | act_household == 1)
replace others = 1 if others == .
gen act_others= lf == 0 & others == 1
	gen act_neet = 1
	replace act_neet = 0 if employment == 1
	replace act_neet = 0 if inlist(B3K7, 2) & act_neet == 1
		//replace act_neet = 0 if b5_r7 == 2 & act_neet == 1
	replace act_neet = . if !inrange(age, 15, 24)

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
keep prov`year' wt urban male age educ unemp employment lf school_years sector9 month ///
     work_informal work_status act_neet act_school act_household act_others work_hours work_whitecoll ///
     work_earnings work_wage work_jobdur* educ_group work_searchdur_* year
save $clean/clean_sakernas_`year', replace

/*************************
 * End of Sakernas 1999
 ************************/

/*************************************************
 * Sakernas 2000 - August period (numbers matched)
 ************************************************/

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
gen month	   = "8"

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

*-----------------------------------------------------------
* Matching Employment Statistics Adjustment
*-----------------------------------------------------------
replace employment = 1 if employment == 0 & work_status != .

*-----------------------------------------------------------
* Non-Labor Force Activity Dummies
*-----------------------------------------------------------
gen act_school    = (b4p2a2 == 1 & b4p2b == 2 & lf == 0)
gen act_household = (b4p2a3 == 1 & b4p2b == 3 & lf == 0)
gen act_others    = (b4p2a4 == 1 & b4p2b == 4 & lf == 0)
	gen act_neet = 1
	replace act_neet = 0 if employment == 1
	replace act_neet = 0 if inlist(sek, 2) & act_neet == 1
		//replace act_neet = 0 if b5_r7 == 2 & act_neet == 1
	replace act_neet = . if !inrange(age, 15, 24)

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
 work_earnings work_wage work_jobdur* educ_group work_searchdur_* year month
save $clean/clean_sakernas_`year', replace


/*************************
 * End of Sakernas 2000
 ************************/

/*******************************************************
 * Sakernas 2001 - August period (numbers matched)
 ******************************************************/
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
gen month = "8"

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

gen work_informal = inlist(b4p10, 1, 2, 5)
gen work_status   = b4p10
// gen work_certif = .   // (Not defined here)
gen work_whitecoll = inrange(b4p8, 1, 599)

*-----------------------------------------------------------
* Adjust Employment to Match BPS Report
*-----------------------------------------------------------
replace employment = 1 if employment == 0 & work_status != .

*-----------------------------------------------------------
* Non-Labor Force Activity Dummies
*-----------------------------------------------------------
gen act_school    = (b4p2a2 == 1 & b4p2b == 2 & lf == 0)
gen act_household = (b4p2a3 == 1 & b4p2b == 3 & lf == 0)
gen act_others    = (b4p2a4 == 1 & b4p2b == 4 & lf == 0)

	gen act_neet = 1
	replace act_neet = 0 if employment == 1
	replace act_neet = 0 if inlist(sek, 2) & act_neet == 1
		//replace act_neet = 0 if b5_r7 == 2 & act_neet == 1
	replace act_neet = . if !inrange(age, 15, 24)

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

keep prov`year' wt urban male age educ unemp employment lf school_years sector9 month ///
     work_informal work_status act_neet act_school act_household act_others work_hours ///
     work_whitecoll work_earnings work_wage work_jobdur* educ_group work_searchdur_* year
save $clean/clean_sakernas_`year', replace

/*************************
 * End of Sakernas 2001
 ************************/

/**************************************************
 * Sakernas 2002 - August period (numbers matched)
 *************************************************/
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
gen month = "8"

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

gen work_informal = inlist(b4cr10a, 1, 2, 5, 6, 7)
gen work_status   = b4cr10a
gen work_whitecoll = inrange(b4cr8, 1, 599)

*-----------------------------------------------------------
* Matching Employment Statistics
*-----------------------------------------------------------
replace employment = 1 if employment == 0 & work_status != .

*-----------------------------------------------------------
* Non-Labor Force Activity Dummies
*-----------------------------------------------------------
gen act_school    = b4br2a2 == 1 & b4br2b == 2 & lf == 0
gen act_household = b4br2a3 == 1 & b4br2b == 3 & lf == 0
gen act_others    = b4br2a4 == 1 & b4br2b == 4 & lf == 0
	gen act_neet = 1
	replace act_neet = 0 if employment == 1
	replace act_neet = 0 if inlist(b3k7, 2) & act_neet == 1
		//replace act_neet = 0 if b5_r7 == 2 & act_neet == 1
	replace act_neet = . if !inrange(age, 15, 24)

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

keep prov`year' wt urban male age educ unemp employment lf school_years sector9 work_informal work_status month ///
     act_neet act_school act_household act_others work_hours work_whitecoll work_earnings work_wage work_jobdur* ///
     educ_group work_searchdur_* year
save $clean/clean_sakernas_`year', replace

/*************************
 * End of Sakernas 2002
 ************************/

/**********************************************
 * Sakernas 2003 - August period (numbers matched)
 *********************************************/

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
gen month	   = "8"

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

gen work_informal = inlist(b4p10, 1, 2, 5, 6, 7)
gen work_status   = b4p10
// gen work_certif = .  // (Not defined)
gen work_whitecoll = inrange(b4p8, 1, 599)

*-----------------------------------------------------------
* Non-Labor Force Activity Dummies
*-----------------------------------------------------------
gen act_school = b4p2a2 == 1 & b4p2b == 2 & lf == 0
gen act_household = b4p2a3 == 1 & b4p2b == 3 & lf == 0
gen act_others    = b4p2a4 == 1 & b4p2b == 4 & lf == 0	
	gen act_neet = 1
	replace act_neet = 0 if employment == 1
	replace act_neet = 0 if inlist(sek, 2) & act_neet == 1
		//replace act_neet = 0 if b5_r7 == 2 & act_neet == 1
	replace act_neet = . if !inrange(age, 15, 24)

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

keep prov`year' wt urban male age educ unemp employment lf school_years sector9 work_informal ///
work_status act_neet act_school act_household act_others work_hours work_whitecoll work_earnings ///
work_wage work_jobdur* educ_group work_searchdur_* year month

save $clean/clean_sakernas_`year', replace

/*************************
 * End of Sakernas 2003
 ************************/

/*************************
 * Sakernas 2004 - August Period (others activity still not matched)
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
gen month	   = "8"

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

gen work_informal  = inlist(b4p10, 1, 2, 5, 6, 7)
gen work_status    = b4p10
// gen work_certif = .   // (Not defined)
gen work_whitecoll = inrange(b4p8, 1, 599)

*-----------------------------------------------------------
* Adjust Employment for Consistency
*-----------------------------------------------------------
replace employment = 1 if employment == 0 & work_status != .

*-----------------------------------------------------------
* Non-Labor Force Activity Dummies
*-----------------------------------------------------------
gen act_school     = (b4p2a2 == 1 | b4p2a2 == 2) & b4p2b == 2 & lf == 0
gen act_household  = (b4p2a3 == 1 | b4p2a3 == 2) & b4p2b == 3 & lf == 0
gen act_others     = (b4p2a4 == 1 | b4p2a4 == 2) & b4p2b == 4 & lf == 0

gen act_neet = 1
	replace act_neet = 0 if employment == 1
	replace act_neet = 0 if inlist(sek, 2) & act_neet == 1
		//replace act_neet = 0 if b5_r7 == 2 & act_neet == 1
	replace act_neet = . if !inrange(age, 15, 24)

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
keep prov`year' wt urban male age educ unemp employment lf school_years sector9 month ///
work_informal work_status act_neet act_school act_others act_household work_hours ///
work_whitecoll work_earnings work_wage work_jobdur* educ_group work_searchdur_* year
save $clean/clean_sakernas_`year', replace

/*************************
 * End of Sakernas 2004
 ************************/

/*********************************************
 * Sakernas 2005 - August period (numbers matched)
 ********************************************/

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
gen month 	   = "8"

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

gen work_informal = inlist(b4p10, 1, 2, 5, 6, 7)
gen work_status   = b4p10
// gen work_certif = .  // (Not defined)
gen work_whitecoll = inrange(b4p8, 1, 599)

*-----------------------------------------------------------
* Adjust Employment for Consistency
*-----------------------------------------------------------
replace employment = 1 if employment == 0 & work_status != .

*-----------------------------------------------------------
* Non-Labor Force Activity Dummies
*-----------------------------------------------------------
gen act_school    = (b4p2a2 == 1 & b4p2b == 2 & lf == 0)
gen act_household = (b4p2a3 == 1 & b4p2b == 3 & lf == 0)
gen act_others    = (b4p2a4 == 1 & b4p2b == 4 & lf == 0)
gen act_neet = 1
	replace act_neet = 0 if employment == 1
	replace act_neet = 0 if inlist(sek, 2) & act_neet == 1
		//replace act_neet = 0 if b5_r7 == 2 & act_neet == 1
	replace act_neet = . if !inrange(age, 15, 24)

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

 keep prov`year' wt urban male age educ unemp employment lf school_years sector9 month ///
 work_informal work_status act_neet act_school act_household act_others work_hours ///
 work_whitecoll work_earnings work_wage work_jobdur* educ_group work_searchdur_* year
save $clean/clean_sakernas_`year', replace

/*************************
 * End of Sakernas 2005
 ************************/

/*************************************************
 * Sakernas 2006 - August period (numbers matched)
 ************************************************/

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
gen month	   = "8"

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

gen work_informal  = inlist(b4p10, 1, 2, 5, 6, 7)
gen work_status    = b4p10
// gen work_certif  = .   // (Not defined)
gen work_whitecoll = inrange(b4p8, 1, 599)

*-----------------------------------------------------------
* Matching Employment Statistics
*-----------------------------------------------------------
replace employment = 1 if employment == 0 & work_status != .

*-----------------------------------------------------------
* Non-Labor Force Activity Dummies
*-----------------------------------------------------------
gen act_school     = (b4p2a2 == 1 & b4p2b == 2 & lf == 0)
gen act_household  = (b4p2a3 == 1 & b4p2b == 3 & lf == 0)
gen act_others     = (b4p2a4 == 1 & b4p2b == 4 & lf == 0)

// adjusting the household activity numbers --> still 1404 obs left out
gen household = 0 if (act_school == 1 | act_household == 1 | act_others == 1)
replace household = 1 if household == .
replace act_household= 1 if lf == 0 & household == 1
// done matched

gen act_neet = 1
	replace act_neet = 0 if employment == 1
	replace act_neet = 0 if inlist(sek, 2) & act_neet == 1
		//replace act_neet = 0 if b5_r7 == 2 & act_neet == 1
	replace act_neet = . if !inrange(age, 15, 24)

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

keep prov`year' wt urban male age educ unemp employment lf school_years sector9 month ///
 work_informal work_status act_neet act_school act_household act_others work_hours ///
 work_whitecoll work_earnings work_wage work_jobdur* educ_group work_searchdur_* year
save $clean/clean_sakernas_`year', replace

/*************************
 * End of Sakernas 2006
 ************************/
 
 /*************************************************
 * Sakernas 2007 - August period (numbers matched)
 *************************************************/

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
gen month 	   = "8"

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

gen work_informal = inlist(b4p11a, 1, 2, 5, 6, 7)
gen work_status   = b4p11a
gen work_certif   = (b4p1c == 1)
    replace work_certif = . if lf == 0
gen work_whitecoll = inrange(b4p8, 1, 5999)

*-----------------------------------------------------------
* Employment Adjustment
*-----------------------------------------------------------
replace employment = 1 if employment == 0 & work_status != .

*-----------------------------------------------------------
* Non-Labor Force Activity Dummies
*-----------------------------------------------------------
gen act_school    = ( (b4p2a2 == 1 | b4p2a2 == 2) & b4p2b == 2 & lf == 0 )
gen act_household = ( (b4p2a3 == 1 | b4p2a3 == 2) & b4p2b == 3 & lf == 0 )
gen act_others    = ( (b4p2a4 == 1 | b4p2a4 == 2) & b4p2b == 4 & lf == 0 )
gen act_neet = 1
	replace act_neet = 0 if employment == 1
	replace act_neet = 0 if inlist(sek, 2) & act_neet == 1
		//replace act_neet = 0 if b5_r7 == 2 & act_neet == 1
	replace act_neet = . if !inrange(age, 15, 24)

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


keep prov`year' wt urban male age educ unemp employment lf school_years sector9 month ///
     work_informal work_status act_neet act_school act_household act_others work_hours ///
     work_whitecoll work_earnings work_wage work_jobdur* educ_group work_searchdur_* year work_certif
save $clean/clean_sakernas_`year', replace

/*************************
 * End of Sakernas 2007
 ************************/

/*************************
 * Sakernas 2008 - August period (numbers matched)
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
gen month	   = "8"

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
gen work_informal = inlist(b5p10a, 1, 2, 5, 6, 7)
gen work_status   = b5p10a
gen work_certif   = b5p1d == 1
    replace work_certif = . if lf == 0
gen work_whitecoll = inrange(b5p8, 1, 5999)

*-----------------------------------------------------------
* Adjust Employment for Consistency
*-----------------------------------------------------------
replace employment = 1 if employment == 0 & work_status != .

*-----------------------------------------------------------
* Non-Labor Force Activity Dummies
*-----------------------------------------------------------
gen act_school    = ((b5p2a2 == 1 | b5p2a2 == 2) & b5p2b == 2 & lf == 0)
gen act_household = (b5p2a3 == 1 | b5p2a3 == 2)  & b5p2b == 3 & lf == 0
gen act_others    = (b5p2a4 == 1 | b5p2a4 == 2)  & b5p2b == 4 & lf == 0
	gen act_neet = 1
	replace act_neet = 0 if employment == 1
	replace act_neet = 0 if inlist(sek, 2) & act_neet == 1
		//replace act_neet = 0 if b5_r7 == 2 & act_neet == 1
	replace act_neet = . if !inrange(age, 15, 24)

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

keep prov`year' wt urban male age educ unemp employment lf school_years sector9 month ///
     work_informal work_status act_neet act_school act_household act_others work_hours ///
     work_whitecoll work_earnings work_wage work_jobdur* educ_group work_searchdur_* year work_certif
	 
save $clean/clean_sakernas_`year', replace
/*************************
 * End of Sakernas 2008
 ************************/

/*************************
 * Sakernas 2009 - August period (numbers matched)
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
gen month	   = "8"

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
gen work_informal = inlist(b5p10a, 1, 2, 5, 6, 7)
gen work_status   = b5p10a
gen work_certif   = b5p1d == 1
    replace work_certif = . if lf == 0
gen work_whitecoll = inrange(b5p8, 1, 5999)

*-----------------------------------------------------------
* Adjust Employment for Consistency
*-----------------------------------------------------------
replace employment = 1 if employment == 0 & work_status != .

*-----------------------------------------------------------
* Non-Labor Force Activity Dummies
*-----------------------------------------------------------
gen act_school    = (b5p2a2 == 1 | b5p2a2 == 2) & b5p2b == 2 & lf == 0
gen act_household = (b5p2a3 == 1 | b5p2a3 == 2) & b5p2b == 3 & lf == 0
gen act_others    = (b5p2a4 == 1 | b5p2a4 == 2) & b5p2b == 4 & lf == 0

	gen act_neet = 1
	replace act_neet = 0 if employment == 1
	replace act_neet = 0 if inlist(sek, 2) & act_neet == 1
		//replace act_neet = 0 if b5_r7 == 2 & act_neet == 1
	replace act_neet = . if !inrange(age, 15, 24)

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

keep prov`year' wt urban male age educ unemp employment lf school_years sector9 month ///
     work_informal work_status act_neet act_school act_household act_others work_hours ///
     work_whitecoll work_earnings work_wage work_jobdur* educ_group work_searchdur_* year work_certif

	 save $clean/clean_sakernas_`year', replace
/*************************
 * End of Sakernas 2009
 ************************/

/*************************
 * Sakernas 2010  - August period (numbers matched)
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
gen month 	   = "8"

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
gen work_informal = inlist(b5p10a, 1, 2, 5, 6, 7)
gen work_status   = b5p10a
gen work_certif   = b5p1d == 1
    replace work_certif = . if lf == 0
gen work_whitecoll = inrange(b5p8, 1, 5999)

*-----------------------------------------------------------
* Adjust Employment for Consistency
*-----------------------------------------------------------
replace employment = 1 if employment == 0 & work_status != .

*-----------------------------------------------------------
* Non-Labor Force Activity Dummies
*-----------------------------------------------------------
gen act_school    = (b5p2a2 == 1 | b5p2a2 == 2) & b5p2b == 2 & lf == 0
gen act_household = (b5p2a3 == 1 | b5p2a3 == 2) & b5p2b == 3 & lf == 0
gen act_others    = (b5p2a4 == 1 | b5p2a4 == 2) & b5p2b == 4 & lf == 0
		gen act_neet = 1
		replace act_neet = 0 if employment == 1
		replace act_neet = 0 if inlist(sek, 2) & act_neet == 1
		//replace act_neet = 0 if b5_r7 == 2 & act_neet == 1
		replace act_neet = . if !inrange(age, 15, 24)

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

keep prov`year' wt urban male age educ unemp employment lf school_years sector9 month ///
     work_informal work_status act_neet act_school act_household act_others work_hours ///
     work_whitecoll work_earnings work_wage work_jobdur* educ_group work_searchdur_* year work_certif

save $clean/clean_sakernas_`year', replace
	 
/*************************
 * End of Sakernas 2010
 ************************/

/*************************
 * Sakernas 2011  - August period (numbers not matched)
 ************************/
 
 *NOTES: there are some number updates in bps website, but still matched with the actual-published 2011 bps report ("Keadaan Angkatan Kerja di Indonesia")

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
gen month = "8"

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
gen work_informal = inlist(b5p12, 1, 2, 5, 6, 7)
gen work_status   = b5p12
gen work_certif   = (b5p1d1 == 1)    // (Supposed to be b5p1c)
    replace work_certif = . if lf == 0
gen work_whitecoll = inrange(kbji2000_1, 1, 5)

*-----------------------------------------------------------
* Employment Matching Adjustment
*-----------------------------------------------------------
replace employment = 1 if employment == 0 & work_status != .

*-----------------------------------------------------------
* Non-Labor Force Activity Dummies
*-----------------------------------------------------------
gen act_school    = ( (b5p2a2 == 1 | b5p2a2 == 2) & b5p2b == 2 & lf == 0 )
gen act_household = ( b5p2a3 == 1 | b5p2a3 == 2 ) & b5p2b == 3 & lf == 0
gen act_others    = ( b5p2a4 == 1 | b5p2a4 == 2 ) & b5p2b == 4 & lf == 0
		gen act_neet = 1
		replace act_neet = 0 if employment == 1
		replace act_neet = 0 if inlist(sek, 2, 3) & act_neet == 1
		//replace act_neet = 0 if b5_r7 == 2 & act_neet == 1
		replace act_neet = . if !inrange(age, 15, 24)

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
* 2011 Clean Data (WB-adopted)
*-----------------------------------------------------------
keep prov`year' wt urban male age educ unemp employment lf school_years sector9 work_informal work_status month ///
     act_neet act_school act_household act_others work_hours work_whitecoll work_earnings work_wage work_jobdur* ///
     educ_group work_searchdur_* year work_certif
save $clean/clean_sakernas_`year', replace

/*************************
 * End of Sakernas 2011
 ************************/

/**************************************************
 * Sakernas 2012 - August period (numbers not matched)
 *************************************************/
// (WB-adopted code)

 *NOTES: due to data backcasted, so there are some number updates in bps website, but still matched with the actual-published 2012 bps report ("keadaan angkatan kerja di Indonesia"")

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
gen month	   = "8"
keep if age >= 15


*-----------------------------------------------------------
* Employment Structure Using WB-adopted Definitions
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
		gen act_neet = 1
		replace act_neet = 0 if employment == 1
		replace act_neet = 0 if inlist(sek, 2, 3) & act_neet == 1
		//replace act_neet = 0 if b5_r7 == 2 & act_neet == 1
		replace act_neet = . if !inrange(age, 15, 24)

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
* 2012 Clean Data (WB-adopted)
*-----------------------------------------------------------
keep prov`year' wt urban male age educ unemp employment lf school_years sector9 work_informal work_status month ///
     act_neet act_school act_household act_others work_hours work_whitecoll work_earnings work_wage work_jobdur* ///
     educ_group work_searchdur_* year work_certif
save $clean/clean_sakernas_`year', replace

/*************************
 * End of Sakernas 2012 
 ************************/

/****************************************************************
 * Sakernas 2013 - August period (numbers succesfully rematched)
 ****************************************************************/

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
gen month      = "8"

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
gen work_informal = inlist(b5p12, 1, 2, 5, 6, 7)
gen work_status   = b5p12
gen work_certif   = (b5p1c == 1)
    replace work_certif = . if lf == 0
gen work_whitecoll = inrange(kbji2000, 1, 5)

*-----------------------------------------------------------
* Employment Matching Adjustment
*-----------------------------------------------------------
replace employment = 1 if employment == 0 & work_status != .

*-----------------------------------------------------------
* Non-Labor Force Activity Dummies
*-----------------------------------------------------------
gen act_school    = ( (b5p2a2 == 1 | b5p2a2 == 2) & b5p2b == 2 & lf == 0 )
gen act_household = ( (b5p2a3 == 1 | b5p2a3 == 2) & b5p2b == 3 & lf == 0 )
gen act_others    = ( (b5p2a4 == 1 | b5p2a4 == 2) & b5p2b == 4 & lf == 0 )
		gen act_neet = 1
		replace act_neet = 0 if employment == 1
		replace act_neet = 0 if inlist(sek, 2, 3) & act_neet == 1
		//replace act_neet = 0 if b5_r7 == 2 & act_neet == 1
		replace act_neet = . if !inrange(age, 15, 24)

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
* 2013 Clean Data (WB-adopted)
*-----------------------------------------------------------
keep prov`year' wt urban male age educ unemp employment lf school_years sector9 work_informal work_status month ///
     act_neet act_school act_household act_others work_hours work_whitecoll work_earnings work_wage work_jobdur* ///
     educ_group work_searchdur_* year work_certif
save $clean/clean_sakernas_`year', replace

/*************************
 * End of Sakernas 2013
 ************************/
 
/*************************
 * Sakernas 2014 - August period (numbers matched)
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
gen month      = "8"

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
gen work_informal = inlist(b5_r12, 1, 2, 5, 6, 7)
gen work_status   = b5_r12
gen work_certif   = (b5_r1c == 1)
    replace work_certif = . if lf == 0
gen work_whitecoll = inrange(kbji2000, 1, 5)

*-----------------------------------------------------------
* Employment Adjustment
*-----------------------------------------------------------
replace employment = 1 if employment == 0 & work_status != .


*-----------------------------------------------------------
* Non-Labor Force Activity Dummies
*-----------------------------------------------------------
gen act_school    = ((b5_r2a2 == 1 | b5_r2a2 == 2) & b5_r2b == 2 & lf == 0)
gen act_household = ((b5_r2a3 == 1 | b5_r2a3 == 2) & b5_r2b == 3 & lf == 0)
gen act_others    = ((b5_r2a4 == 1 | b5_r2a4 == 2) & b5_r2b == 4 & lf == 0)

		gen act_neet = 1
		replace act_neet = 0 if employment == 1
		replace act_neet = 0 if inlist(b4_k7, 2, 3) & act_neet == 1
		//replace act_neet = 0 if b5_r7 == 2 & act_neet == 1
		replace act_neet = . if !inrange(age, 15, 24)

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
* 2014 Clean Data
*-----------------------------------------------------------
keep prov`year' wt urban male age educ unemp employment lf school_years sector9 work_informal work_status month ///
     act_neet act_school act_household act_others work_hours work_whitecoll work_earnings work_wage work_jobdur* ///
     educ_group work_searchdur_* year work_certif
save $clean/clean_sakernas_`year', replace

/*************************
 * End of Sakernas 2014
 ************************/
 
 /****************************************************************************************************
 * Sakernas 2015 (WB-Adopted employment calculation) - August period (numbers matched)
 ****************************************************************************************************/

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
gen month	   = "8"
keep if age >= 15

*-----------------------------------------------------------
* Define Employment Structure (WB-Adopted)
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
		gen act_neet = 1
		replace act_neet = 0 if employment == 1
		replace act_neet = 0 if inlist(b4_k7, 2, 3) & act_neet == 1
		//replace act_neet = 0 if b5_r7 == 2 & act_neet == 1
		replace act_neet = . if !inrange(age, 15, 24)

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
* 2015 Clean Data (WB-adopted)
*-----------------------------------------------------------
keep prov`year' wt urban male age educ unemp employment lf school_years sector9 work_informal work_status month ///
     act_neet act_school act_household act_others work_hours work_whitecoll work_earnings work_wage work_jobdur* ///
     educ_group work_searchdur_* year work_certif
save $clean/clean_sakernas_`year', replace

/*************************
 * End of Sakernas 2015
 ************************/

 /****************************************************************************************************
 * Sakernas 2016 (WB-Adopted employment calculation) - August period (numbers matched)
 ****************************************************************************************************/

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
gen month      = "8"
keep if age >= 15

*-----------------------------------------------------------
* Define Employment Using WB-Adopted Indicators
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
		gen act_neet = 1
		replace act_neet = 0 if employment == 1
		replace act_neet = 0 if b4_k8 == 2 & act_neet == 1
		replace act_neet = 0 if b5_r7 == 2 & act_neet == 1
		replace act_neet = . if !inrange(age, 15, 24)

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
* 2016 Clean Data (WB-adopted)
*-----------------------------------------------------------
keep prov`year' wt urban male age educ unemp employment lf school_years sector9 work_informal work_status month ///
     act_neet act_school act_household act_others work_hours work_whitecoll work_earnings work_wage work_jobdur* ///
     educ_group work_searchdur_* year work_certif
save $clean/clean_sakernas_`year', replace

/*************************
 * End of Sakernas 2016
 ************************/
 
 /****************************************************************************************************
 * Sakernas 2017 (WB-Adopted employment calculation) - August period (numbers matched)
 ****************************************************************************************************/

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
gen month      = "8"
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

gen work_informal = inlist(b5_r27a, 1, 2, 5, 6, 7)
gen work_status   = b5_r27a
gen work_certif   = (b5_r1d == 1)
    replace work_certif = . if lf == 0
gen work_whitecoll = inrange(b5_r24_200, 1, 5)

gen act_school = ((b5_r5a2 == 3 | b5_r5a2 == 4) & b5_r5b == 2 & lf == 0)
gen act_household = ((b5_r5a3 == 1 | b5_r5a3 == 2) & b5_r5b == 3 & lf == 0)
gen act_others = ((b5_r5a4 == 3 | b5_r5a4 == 4) & b5_r5b == 4 & lf == 0)
		gen act_neet = 1
			replace act_neet = 0 if employment == 1
			replace act_neet = 0 if b4_k7 == 2 & act_neet == 1
			replace act_neet = 0 if b5_r1e == 1 & act_neet == 1
			replace act_neet = . if !inrange(age, 15, 24)

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
* 2017 Clean Data (WB-adopted)
*-----------------------------------------------------------
keep prov`year' wt urban male age educ unemp employment lf school_years sector9 work_informal work_status month ///
     act_neet act_school act_household act_others work_hours work_whitecoll work_earnings work_wage work_jobdur* ///
     educ_group work_searchdur_* year work_certif
save $clean/clean_sakernas_`year', replace

/*************************
 * End of Sakernas 2017
 ************************/

 /*************************
 * Sakernas 2018 - August period (numbers matched)
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
gen month  	   = "8"
keep if age >= 15

*-----------------------------------------------------------
* Unemployment and Labor Force
*-----------------------------------------------------------
gen employment = (b5_r5a1 == 1 | b5_r6 == 1)
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
* Sector Classification (WB-Adopted)
*-----------------------------------------------------------
* Create 17-sector variable then recode to 9-sector format
gen sector17 = b5_r23_sek
replace sector17 = . if sector17 == 0

* 9 sectors WB-adopted
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
		gen act_neet = 1
			replace act_neet = 0 if employment == 1
			replace act_neet = 0 if b4_k9 == 2 & act_neet == 1
			replace act_neet = 0 if b5_r1f == 1 & act_neet == 1
			replace act_neet = . if !inrange(age, 15, 24)

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
* 2018 Clean Data (WB-adopted)
*-----------------------------------------------------------

keep prov`year' wt urban male age educ unemp employment lf school_years sector9 sector17 work_informal work_status ///
     act_neet act_school act_household act_others work_hours work_whitecoll work_earnings work_wage work_jobdur* ///
     educ_group work_searchdur_* year work_certif month
save $clean/clean_sakernas_`year', replace

/*************************
 * End of Sakernas 2018
 ************************/
 
 /*************************
 * Sakernas 2019 - August period (numbers matched)
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
gen month  	   = "8"
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
		gen act_neet = 1
			replace act_neet = 0 if employment == 1
			replace act_neet = 0 if b4_k9 == 2 & act_neet == 1
			replace act_neet = 0 if b5_r1f == 1 & act_neet == 1
			replace act_neet = . if !inrange(age, 15, 24)

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
* 2019 Clean Data (WB-adopted)
*-----------------------------------------------------------
local year = 2019
keep prov`year' wt urban male age educ unemp employment lf school_years sector9 sector17 work_informal work_status ///
     act_neet act_school act_household act_others work_hours work_whitecoll work_earnings work_wage work_jobdur* ///
     educ_group work_searchdur_* year work_certif month
save $clean/clean_sakernas_`year', replace

/*************************
 * End of Sakernas 2019
 ************************/
 
 /*************************
 * Sakernas 2020 - August period (numbers matched)
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
gen month  	   = "8"

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
   Sector Classification (17-sector then WB-adopted 9-sector)
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
		gen act_neet = 1
			replace act_neet = 0 if employment == 1
			replace act_neet = 0 if R5 == 2 & act_neet == 1
			replace act_neet = 0 if R6E == 1 & act_neet == 1
			replace act_neet = . if !inrange(age, 15, 24)


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
* 2020 Clean Data (WB-adopted)
*-----------------------------------------------------------

keep prov`year' wt urban male age educ unemp employment lf school_years sector9 sector17 work_informal work_status ///
     act_neet act_school act_household act_others work_hours work_whitecoll work_earnings work_wage work_jobdur* ///
     educ_group work_searchdur_* year work_certif month
save $clean/clean_sakernas_`year', replace

/*************************
 * End of Sakernas 2020
 ************************/

 /*************************
 * Sakernas 2021 - August period (numbers matched)
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
gen month      = "8"
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
   Sector Classification (WB-Adopted)
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
		gen act_neet = 1
			replace act_neet = 0 if employment == 1
			replace act_neet = 0 if R5 == 2 & act_neet == 1
			replace act_neet = 0 if R6I == 1 & act_neet == 1
			replace act_neet = . if !inrange(age, 15, 24)

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
* 2021 Clean Data (WB-adopted)
*-----------------------------------------------------------

keep prov`year' wt urban male age educ unemp employment lf school_years sector9 sector17 work_informal work_status ///
     act_neet act_school act_household act_others work_hours work_whitecoll work_earnings work_wage work_jobdur* ///
     educ_group work_searchdur_* year work_certif month
save $clean/clean_sakernas_`year', replace

/*************************
 * End of Sakernas 2021
 ************************/
 
 /*************************
 * Sakernas 2022 - August period (numbers matched)
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
gen month 	   = "8"
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
   Sector Classification (WB-Adopted)
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
	gen act_neet = 1
	replace act_neet = 0 if employment == 1
	replace act_neet = 0 if R5 == 2 & act_neet == 1
	replace act_neet = 0 if R6H == 1 & act_neet == 1
	replace act_neet = . if !inrange(age, 15, 24) 

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
* 2022 Clean Data (WB-adopted)
*-----------------------------------------------------------

keep prov`year' wt urban male age educ unemp employment lf school_years sector9 sector17 work_informal work_status ///
     act_neet act_school act_household act_others work_hours work_whitecoll work_earnings work_wage work_jobdur* ///
     educ_group work_searchdur_* year work_certif month
save $clean/clean_sakernas_`year', replace

/*************************
 * End of Sakernas 2022
 ************************/

 /*************************
 * Sakernas 2023 - August period (numbers matched)
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
gen month	   = "8"

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
   Sector Classification (WB-Adopted)
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
	gen act_neet = 1
	replace act_neet = 0 if employment == 1
	replace act_neet = 0 if R5 == 2 & act_neet == 1
	replace act_neet = 0 if R6H == 1 & act_neet == 1
	replace act_neet = . if !inrange(age, 15, 24) 

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
     educ_group work_searchdur_* year work_certif month
save $clean/clean_sakernas_`year', replace

/*************************
 * End of Sakernas 2023
 ************************/

 /*************************
 * Sakernas 2024 - August period (numbers matched)
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
destring prov`year', replace
gen wt         = WEIGHT
gen urban      = (KLAS == 1)
gen male       = (K4 == 1)
gen age        = K10         // WARNING: AGE OUTSIDE LF DETECTED
gen educ       = R6A
gen month  	   = "8"

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
   Sector Classification (WB-Adopted)
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

gen act_neet = 1
replace act_neet = 0 if employment == 1
replace act_neet = 0 if R5 == 2 & act_neet == 1
replace act_neet = 0 if R6H == 1 & act_neet == 1
replace act_neet = . if !inrange(age, 15, 24) 

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
// save "$output/temp_sakernas_`year'", replace

*-----------------------------------------------------------
* 2024 Clean Data (WB-adopted)
*-----------------------------------------------------------

keep prov`year' wt urban male age educ unemp employment lf school_years sector9 sector17 work_informal work_status ///
     act_neet act_school act_household act_others work_hours work_whitecoll work_earnings work_wage work_jobdur* ///
     educ_group work_searchdur_* year work_certif month
save $clean/clean_sakernas_`year', replace

/*************************
 * End of Sakernas 2024
 ************************/
 
/************************************************************
 ***************							  ***************
 ***************							  ***************
					  APPENDIX SECTION	
 ***************							  ***************
 ***************							  ***************
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

 use $clean/clean_sakernas_1997
 gl finaloutput "/Users/kelvinramadhan/Documents/TNP2K/Middle-Class/finaloutput"
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

    save $finaloutput/final_sakernas_97_24, replace


 

 






 
