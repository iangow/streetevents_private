library(googlesheets)
library(tidyr)
library(dplyr)
# Run gs_auth() as once-per-computer authorization step
gs <- gs_key("1vy700CT6VZ3zuhQQ5iO-RCdwcA_Hw-VMQheiGk7SnYk")

investigation <-
    gs_read(gs) %>%
    mutate(file_names=gsub("(^\\{|\\}$)", "", file_names)) %>%
    unnest(file_name=strsplit(file_names, ",")) %>%
    select(-file_names)


pg <- src_postgres(host="aaz.chicagobooth.edu", dbname="postgres")

tbl_pg <- function(table) {
    tbl(pg, sql(paste0("SELECT * FROM ", table)))
}

# Run code in streetevents/crsp_link.sql to create
# streetevents.crsp_link
crsp_link <- tbl_pg("streetevents.crsp_link")
company_link <- tbl_pg("streetevents.company_link")

# Type 1: Observations on crsp_link already.
# Here we need to work out which PERMNO is correct and add to
# manual_permno_matches spreadsheet:
# https://docs.google.com/spreadsheets/d/14F6zjJQZRsf5PonOfZ0GJrYubvx5e_eHMV_hCGe42Qg

type_1_cases <-
    investigation %>%
    subset(investigate) %>%
    inner_join(crsp_link %>% collect %>% rename(permno_crsp_link=permno)) %>%
    inner_join(company_link %>% collect %>% rename(permno_company_link=permno)) %>%
    # exclude existing manual matches
    filter(match_type != 0L)

type_1_cases %>% select(permno_crsp_link) %>% distinct %>% count

# Type 2: Observations not on crsp_link. Here we need to see if the PERMNO
# on company_link is correct and, if not, replace it where possible.

# If the PERMNO is confirmed correct, then it may be easiest to change
# "investigate" to FALSE in the "investigation" Google Sheets document, perhaps
# noting that the case has been investigated there.
type_2_cases <-
    investigation %>%
    subset(investigate) %>%
    anti_join(crsp_link %>% collect) %>%
    inner_join(company_link %>% collect) %>%
    arrange(permno)

type_2_cases %>% select(permno) %>% distinct %>% count

type_2_cases
