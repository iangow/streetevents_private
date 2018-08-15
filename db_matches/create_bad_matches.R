library(dplyr, warn.conflicts = FALSE)
library(RPostgreSQL)
library(googlesheets)
library(readr)

pg <- dbConnect(PostgreSQL())
calls <- tbl(pg, sql("SELECT * FROM streetevents.calls"))
crsp_link <- tbl(pg, sql("SELECT * FROM streetevents.crsp_link"))
bad_matches <- tbl(pg, sql("SELECT * FROM streetevents.bad_matches"))

regex <- "(?:Earnings(?: Conference Call)?|Financial and Operating Results|Financial Results Call|"
regex <- paste0(regex, "Results Conference Call|Analyst Meeting)")
regex <- paste0("^(.*) (", regex, ")")
qtr_regex <- "(Preliminary Half Year|Full Year|Q[1-4])"
year_regex <- "(20[0-9]{2}(?:-[0-9]{2}|/20[0-9]{2})?)"
period_regex <- paste0("^", qtr_regex, " ", year_regex," (.*)")

calls_mod <- 
    calls %>% 
    mutate(fisc_qtr_data = regexp_matches(event_title, period_regex)) %>%
    mutate(event_co_name = sql("fisc_qtr_data[3]")) %>%
    mutate(event_co_name = regexp_matches(event_co_name, regex)) %>%
    mutate(event_co_name = sql("event_co_name[1]")) %>% 
    select(file_name, event_title, event_co_name) %>% 
    inner_join(crsp_link %>% # file_name, permno
                   filter(!is.na(permno)), 
               by = "file_name") %>% 
    select(-match_type, - match_type_desc) %>% 
    distinct() %>% 
    compute()

name_checks <- 
    gs_read(gs_key("1_RKRJah6iuUHC-y_kHP58Dl6UaptIhBNPRSyTjIjSSM"))

dbGetQuery(pg, "DROP TABLE IF EXISTS public.bad_matches")

bad_matches <- 
    name_checks %>% 
    filter(valid == FALSE) %>% 
    inner_join(calls_mod, by = c("event_co_name", "permno"), copy = TRUE) %>% 
    select(file_name, permno, valid, event_co_name, comnams, event_title) %>% 
    union(bad_matches) %>% 
    copy_to(pg, ., name = 'bad_matches', temporary = FALSE)

dbGetQuery(pg, "DROP TABLE IF EXISTS streetevents.bad_matches")
dbGetQuery(pg, "ALTER TABLE public.bad_matches SET SCHEMA streetevents")
dbGetQuery(pg, "ALTER TABLE streetevents.bad_matches OWNER TO streetevents")
dbGetQuery(pg, "GRANT SELECT ON streetevents.bad_matches TO streetevents_access")
db_comment <- paste0("CREATED USING create_bad_matches.R ON ", Sys.time())
dbGetQuery(pg, sprintf("COMMENT ON TABLE streetevents.bad_matches IS '%s';", db_comment))
