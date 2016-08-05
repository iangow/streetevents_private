library(dplyr)

pg <- src_postgres(host="aaz.chicagobooth.edu", dbname="postgres")

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
stocknames <- tbl_pg("crsp.stocknames")

# How many firms have the same PERMNO as identified with
# the ticker match?
match_compare <-
    crsp_link %>%
    inner_join(company_link, by="file_name", suffix=c(".crsp", ".comp")) %>%
    mutate(same_permno=permno.crsp==permno.comp) %>%
    compute()

match_compare_summary <-
    match_compare %>%
    group_by(same_permno) %>%
    summarize(count=n())

match_compare_diff_permno <-
    match_compare %>%
    filter(!same_permno) %>%
    inner_join(calls)

permno.crsp_permco <-
    match_compare %>%
    inner_join(select(stocknames, permco, permno), by=c("permno.crsp"="permno"))

permno.comp_permco <-
    match_compare %>%
    # select(file_name, permno.y) %>%
    inner_join(select(stocknames, permco, permno), by=c("permno.comp"="permno"))

match_compare_permco <-
    permno.crsp_permco %>%
    inner_join(select(permno.comp_permco, permco, file_name), by="file_name",
               suffix=c(".crsp", ".comp"))

match_compare_permco_diff_permno <-
    match_compare_permco %>%
    filter(!same_permno) %>%
    group_by(file_name) %>%
    filter(row_number() == 1) %>%
    ungroup() %>%
    mutate(same_permco=permco.crsp==permco.comp) %>%
    compute()

diff_permco_summary <-
    match_compare_permco_diff_permno %>%
    group_by(same_permco) %>%
    summarize(count=n())

diff_permco <-
    match_compare_permco_diff_permno %>%
    filter(!same_permco)

diff_permco_calls <-
    match_compare_permco_diff_permno %>%
    inner_join(calls, by="file_name")
