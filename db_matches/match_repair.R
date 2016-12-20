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
stocknames <- tbl_pg("crsp.stocknames")

comnams <-
    stocknames %>%
    select(permno, permco, comnam) %>%
    distinct() %>%
    group_by(permno, permco) %>%
    summarize(comnams=array_agg(comnam)) %>%
    ungroup() %>%
    compute()

# How many firms have the same PERMNO as identified with
# the ticker match?
match_compare <-
    crsp_link %>%
    inner_join(company_link, by="file_name", suffix=c(".crsp", ".comp")) %>%
    mutate(same_permno=permno.crsp==permno.comp) %>%
    compute()

match_repair <-
    match_compare %>%
    select(-match_type_desc) %>%
    filter(!same_permno) %>%
    inner_join(calls %>%
                   select(file_name, co_name, call_desc, call_date)) %>%
    inner_join(comnams %>% rename(permno.crsp=permno,
                                  comnams.crsp=comnams,
                                  permco.crsp=permco)) %>%
    inner_join(comnams %>% rename(permno.comp=permno,
                                  comnams.comp=comnams,
                                  permco.comp=permco)) %>%
    filter(permco.crsp != permco.comp) %>%
    compute()

match_repair %>%
    View()

match_repair %>%
    mutate(year=sql("extract(year FROM call_date)")) %>%
    group_by(year) %>%
    summarize(count=n()) %>%
    arrange(year) %>%
    print(n=100)
