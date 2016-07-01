library(dplyr)

pg <- src_postgres()

tbl_pg <- function(table) {
    tbl(pg, sql(paste0("SELECT * FROM ", table)))
}

# Run code in streetevents/crsp_link.sql to create
# streetevents.crsp_link
crsp_link <- tbl_pg("streetevents.crsp_link")
company_link <- tbl_pg("streetevents.company_link")
executive_link <- tbl_pg("streetevents.executive_link")
manual_permno_matches <- tbl_pg("streetevents.manual_permno_matches")
calls <- tbl_pg("streetevents.calls")

# How many firms have the same PERMNO as identified with
# the ticker match?
match_compare <-
    crsp_link %>%
    inner_join(company_link, by="file_name") %>%
    mutate(same_permno=permno.x==permno.y) %>%
    compute()

match_compare %>%
    group_by(same_permno) %>%
    summarize(count=n())

match_compare %>%
    filter(!same_permno) %>%
    inner_join(calls) %>%
    View()
