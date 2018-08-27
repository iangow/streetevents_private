# StreetEvents data

The code here transforms XML files for conference calls supplied by Thomson Reuters into structured tables in a PostgreSQL database.

## 1. Requirements

To use this code you will need a few things.

1. A directory containing the `.xml` files.
2. A PostgreSQL database to point to.
    - Database should have a schema `streetevents` and a role `streetevents`. The following SQL does
      this:

```sql
CREATE SCHEMA streetevents;
CREATE ROLE streetevents;
CREATE ROLE streetevents_access;
```

3. The following environment variables set:
    - `PGHOST`: The host address of the PostgreSQL database server.
    - `PGDATABASE`: The name of the PostgreSQL database.
    - `SE_DIR`: The path to the directory containing the `.xml` files.
    - `PGUSER` (optional): The default is your log-in ID; if that's not correct, set this variable.
    - `PGPASSWORD` (optional): This is not the recommended way to set your password, but is one
      approach.
4. R and the following packages: `xml2`, `stringr`, `dplyr`, `parallel`, `RPostgreSQL`, `digest`

## 2. Processing core tables

1. Get files from server.

```
rsync -avz iangow@45.113.235.201:~/uploads/ $SE_DIR
```

2. Run basic code.

The following three code files need to be run in the following order:

- The file `create_call_files.R` extracts details about the files associated with each call (e.g., `mtime`) and puts it in `streetevents.call_files`.
- The file `import_calls.R` extracts call-level data (e.g., ticker, call time, call type) and puts it in `streetevents.calls`.
- The file `import_speaker_data.R` parse the speaker-level data from the XML call files and puts it
  in `streetevents.speaker_data`.

## 3. Processing additional tables
The script `update_se.sh` does both of the steps above.

A number of other tables are created using code from this repository. These generally depend on the
three tables above.
### 3.1 streetevents.crsp_link
- `streetevents.crsp_link` is created by code `crsp_link.sql` that calls `crsp_link.sql`. 
This uses tickers and call dates to match firms to PERMNOs, but with some data integrity checks and manual overrides.
The underlying tables are `streetevents.calls`, `streetevents.calls_hbs`, `streetevents.manual_permno_matches`, 
`crsp.stocknames` and `streetevents.bad_matches`.

`streetevents.manual_permno_matches` is created by `import_manual_permno_matches.R`, the underlying spreadsheet is `gs_key("14F6zjJQZRsf5PonOfZ0GJrYubvx5e_eHMV_hCGe42Qg")`.

`streetevents.bad_matches` is created by `create_bad_matches.R`, the underlying spreadsheet is `gs_key("1_RKRJah6iuUHC-y_kHP58Dl6UaptIhBNPRSyTjIjSSM")`.

**To update `crsp_link`** (eg. after updating `streetevents.calls` or `crsp.stocknames`):
1. Append the output of the code below to `name_checks`(`gs_key("1_RKRJah6iuUHC-y_kHP58Dl6UaptIhBNPRSyTjIjSSM")`).
```r
library(dplyr, warn.conflicts = FALSE)
library(DBI)
library(readr)
library(googlesheets)

pg <- dbConnect(RPostgreSQL::PostgreSQL())
rs <- dbExecute(pg, "SET work_mem = '10GB'")
calls <- tbl(pg, sql("SELECT * FROM streetevents.calls"))
crsp_link <- tbl(pg, sql("SELECT * FROM streetevents.crsp_link"))
stocknames <- tbl(pg, sql("SELECT * FROM crsp.stocknames"))
name_checks <- 
    gs_read(gs_key("1_RKRJah6iuUHC-y_kHP58Dl6UaptIhBNPRSyTjIjSSM"))
crsp_names <-
    stocknames %>%
    distinct(permno, comnam) %>%
    group_by(permno) %>%
    summarize(comnams = array_agg(comnam)) %>%
    compute()

se_link <- 
    crsp_link %>%
    filter(!is.na(permno)) %>%
    distinct(file_name, permno)
# |Q&A Session
regex <- "(?:Earnings(?: Conference Call)?|Financial and Operating Results|Financial Results Call|"
regex <- paste0(regex, "Results Conference Call|Analyst Meeting)")
regex <- paste0("^(.*) (", regex, ")")

qtr_regex <- "(Preliminary Half Year|Full Year|Q[1-4])"
year_regex <- "(20[0-9]{2}(?:-[0-9]{2}|/20[0-9]{2})?)"
period_regex <- paste0("^", qtr_regex, " ", year_regex," (.*)")
calls_mod <- 
    calls %>%
    filter(event_type == 1L) %>%
    distinct(file_name, cusip, start_date, event_title) %>%
    mutate(fisc_qtr_data = regexp_matches(event_title, period_regex)) %>%
    mutate(event_co_name = sql("fisc_qtr_data[3]")) %>%
    mutate(event_co_name = regexp_matches(event_co_name, regex)) %>%
    mutate(event_co_name = sql("event_co_name[1]"),
           event_desc = sql("event_co_name[2]")) %>%
    mutate(fisc_qtr_data = sql("fisc_qtr_data[1] || ' ' || fisc_qtr_data[2]")) %>%
    compute()

dupes <- 
    calls_mod %>%
    inner_join(se_link) %>% 
    group_by(permno, fisc_qtr_data) %>%
    filter(n() > 1) %>%
    ungroup() %>%
    compute()

dupes %>% 
    count()

dupes %>% 
    distinct(permno) %>%
    count()

dupes %>% 
    group_by(permno) %>%
    count() %>%
    arrange(desc(n))

dupes %>%
    inner_join(crsp_names) %>%
    distinct(event_co_name, permno, comnams) %>%
    anti_join(name_checks, by = c("event_co_name", "permno"), copy = TRUE) %>% 
    arrange(permno) %>%
    collect() %>%
    write.csv("~/name_checks.csv")
```

2. Run `create_bad_matches.R` to update `bad_matches` table.
3. Run `create_crsp_link.R` to update `crsp_link` table.
4. Run the code below to check consistency and find out the problematic matches.
```r
library(dplyr)
library(RPostgreSQL)
pg <- dbConnect(PostgreSQL())
proxy_company <- 
    tbl(pg, sql("SELECT * FROM executive.proxy_company")) %>% 
    distinct(company_id, company_name)
calls <- tbl(pg, sql("SELECT * FROM streetevents.calls"))
se_call_link <- tbl(pg, sql("SELECT * FROM executive.se_call_link")) 

regex <- "(?:Earnings(?: Conference Call)?|Financial and Operating Results|Financial Results Call|"
regex <- paste0(regex, "Results Conference Call|Analyst Meeting)")
regex <- paste0("^(.*) (", regex, ")")
qtr_regex <- "(Preliminary Half Year|Full Year|Q[1-4])"
year_regex <- "(20[0-9]{2}(?:-[0-9]{2}|/20[0-9]{2})?)"
period_regex <- paste0("^", qtr_regex, " ", year_regex," (.*)")

# Consistency check
se_call_link %>% 
    group_by(file_name, company_id) %>% 
    filter(n() > 1) # Should be None

se_call_link %>% group_by(file_name) %>% filter(n() > 1) # Should be None

problem <- # 839
    se_call_link %>% # file_name, permno, company_id, fy_end
    group_by(company_id, fy_end) %>% 
    mutate(cnt = n()) %>% 
    ungroup() %>% 
    filter(cnt > 5) %>% # 706 -> 2293
    left_join(calls %>% 
                  select(file_name, event_title, start_date, last_update) %>% 
                  distinct() %>% 
                  group_by(file_name) %>% 
                  filter(last_update == max(last_update, na.rm = TRUE)) %>% 
                  ungroup() %>% 
                  select(-last_update),
               by = "file_name") %>% 
    inner_join(proxy_company, by = "company_id") %>% # Add company_name
    compute()

problem <- # 313
    problem %>% 
    mutate(fisc_qtr_data = regexp_matches(event_title, period_regex)) %>%
    mutate(event_co_name = sql("fisc_qtr_data[3]")) %>%
    mutate(event_co_name = regexp_matches(event_co_name, regex)) %>%
    mutate(event_co_name = sql("event_co_name[1]")) %>%
    arrange(company_id, fy_end) %>% 
    right_join(problem) %>% 
    compute() 

problem %>% arrange(company_id, fy_end, start_date) %>% View()
```
5. Most of the matches in `problem` are actually good matches. For the incorrect matches (due to company name or date), append `file_name` to `manual_permno_matches`(`gs_key("14F6zjJQZRsf5PonOfZ0GJrYubvx5e_eHMV_hCGe42Qg")`) and leave `permno` column blank, so the code will exclude this call record.

6. Run `import_manual_permno_matches.R` again, and then `create_crsp_link.R`. Do consistency check again, if anything pops out, redo step 1-4 until all matches are fine.

7. Run `create_se_call_link.R` and `create_se_exec_link.R` in `executive` repo to update `executive.se_call_link` and `executive.se_exec_link` tables.

### 3.2 streetevents.qa_pairs
- `streetevents.qa_pairs` is created by `create_qa_pairs.R`.
This table attempts to group distinguish questions from answers and group questions and answers.
Often a single question will prompt multiple responses (e.g., the CEO answers at one level and the CFO provides more detail).

