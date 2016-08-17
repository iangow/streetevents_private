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
    diff_permco %>%
    inner_join(calls, by="file_name")

diff_permco_calls_manual <-
    diff_permco_calls %>%
    inner_join(manual_permno_matches, by="file_name")

compare_co_name <-
    calls %>%
    mutate(co_name_matches=regexp_matches(call_desc, regex)) %>%
    mutate(call_co_name=sql("trim(both from co_name_matches[1])")) %>%
    select(file_name, call_desc, call_co_name, co_name) %>%
    mutate(same_co_name=call_co_name==co_name)

compareNames <- function(name1, name2) {
    clean <- function(name) {
        return(gsub("[,.`']|INC\\w*|LTD|CORP\\w*|\\bCO\\b|COMP\\w*|\ ", "",
                    toupper(name)))
    }
    return(clean(name1)==clean(name2))
}

regex <- '(?:[0-9]{4}|[0-9]{4}/[0-9]{2})(.*)(?=Results|Earnings)'
df <-
    diff_permco_calls %>%
    # drops 1 row here: 1294427_T, "The Wendy's Co" & "Wendy's International"
    mutate(co_name_matches=regexp_matches(call_desc, regex)) %>%
    mutate(call_co_name=sql("trim(both from co_name_matches[1])")) %>%
    select(file_name, same_permco, co_name, call_co_name) %>%
    collect()

df$same_co_name <- compareNames(df$call_co_name, df$co_name)

diff_permco_calls_compare_name <- df

diff_permco_co_names <-
    diff_permco_calls_compare_name %>%
    filter(!same_permco) %>%
    select(co_name, call_co_name, same_co_name)

diff_permco_co_names_summary <-
    diff_permco_co_names %>%
    group_by(same_co_name) %>%
    summarise(count=n())

diff_permco_distinct_co_names <-
    diff_permco_calls_compare_name %>%
    select(co_name, call_co_name, same_co_name) %>%
    distinct() %>%
    arrange(co_name)
