library(dplyr)

summarize_counts_by <- function(data, ...) {
    data %>%
    group_by(...) %>%
    summarize(count=n()) %>%
    return()
}

compareNames <- function(name1, name2) {
    # Perform non-strict comparison of company names, ignoring punctuation and
    # words like 'Inc', 'Ltd', 'Corp', etc.
    clean <- function(name) {
        return(gsub("[,.`']|INC\\w*|LTD|CORP\\w*|\\bCO\\b|COMP\\w*|\ ", "",
                    toupper(name)))
    }
    return(clean(name1)==clean(name2))
}

check_co_name <- function(data, exact) {
    # Take a table containing co_name and call_desc, extract call_co_name from
    # call_desc, and compute same_co_name to compare co_name and call_co_name
    # using the compareNames function
    # NOTE: drops 1 row: 1294427_T, "The Wendy's Co" & "Wendy's International"
    if (missing(exact)) {
        exact <- FALSE
    }
    regex <- '(?:[0-9]{4}|[0-9]{4}/[0-9]{2})(.*)(?=Results|Earnings)'
    df <-
        data %>%
        mutate(co_name_matches=regexp_matches(call_desc, regex)) %>%
        mutate(call_co_name=sql("trim(both from co_name_matches[1])")) %>%
        select(-co_name_matches) %>%
        distinct() %>%
        as.data.frame()
    if (exact) {
        df$same_co_name <- df$call_co_name == df$co_name
    } else {
        df$same_co_name <- compareNames(df$call_co_name, df$co_name)
    }
    return(df)
}

tbl_pg <- function(table) {
    tbl(pg, sql(paste0("SELECT * FROM ", table)))
}

pg <- src_postgres(host="aaz.chicagobooth.edu", dbname="postgres")

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
    summarize_counts_by(same_permno)

match_compare_diff_permno <-
    match_compare %>%
    filter(!same_permno) %>%
    inner_join(calls)

# Add permco matching permno.crsp to comparison
permno.crsp_permco <-
    match_compare %>%
    inner_join(select(stocknames, permco, permno), by=c("permno.crsp"="permno"))

# Add permco matching permno.comp to comparison
permno.comp_permco <-
    match_compare %>%
    inner_join(select(stocknames, permco, permno), by=c("permno.comp"="permno"))

# Join the tables with permco for both crsp and comp
match_compare_permco <-
    permno.crsp_permco %>%
    inner_join(select(permno.comp_permco, permco, file_name), by="file_name",
               suffix=c(".crsp", ".comp")) %>%
    mutate(same_permco=permco.crsp==permco.comp)

permno_co_name_summary <-
    match_compare_permco %>%
    inner_join(calls, by="file_name") %>%
    check_co_name() %>%
    summarize_counts_by(same_permno, same_co_name) %>%
    arrange(desc(same_permno), desc(same_co_name))

# Count of (match_type, same_permno, same_permco) for all combinations:
# 0 <= match_type < 11, same_permno, same_permco = TRUE | FALSE
match_type_permno_permco_summary <-
    match_compare_permco %>%
    as.data.frame() %>%
    summarize_counts_by(match_type, same_permno, same_permco) %>%
    ungroup() %>%
    complete(match_type, same_permno, same_permco, fill=list(count=0)) %>%
    arrange(match_type, desc(same_permno), desc(same_permco))

diff_permno_comp_permco <-
    match_compare_permco %>%
    filter(!same_permno)

diff_permco_summary <-
    diff_permno_comp_permco %>%
    summarize_counts_by(same_permco)

diff_permco <-
    diff_permno_comp_permco %>%
    filter(!same_permco)

diff_permco_calls <-
    diff_permco %>%
    inner_join(calls, by="file_name")

diff_permco_calls_manual <-
    diff_permco_calls %>%
    inner_join(manual_permno_matches, by="file_name")

compare_co_name <-
    calls %>%
    check_co_name(exact=TRUE) %>%
    select(file_name, call_desc, call_co_name, co_name)

diff_permco_calls_compare_name <-
    diff_permco_calls %>%
    check_co_name() %>%
    select(file_name, same_permco, co_name, call_co_name, same_co_name) %>%
    collect()

diff_permco_co_names <-
    diff_permco_calls_compare_name %>%
    filter(!same_permco) %>%
    select(co_name, call_co_name, same_co_name)

diff_permco_co_names_summary <-
    diff_permco_co_names %>%
    summarize_counts_by(same_co_name)

diff_permco_distinct_co_names <-
    diff_permco_calls_compare_name %>%
    select(co_name, call_co_name, same_co_name) %>%
    distinct() %>%
    arrange(co_name)

diff_permco_match_type_summary <-
    diff_permno_comp_permco %>%
    inner_join(calls, by="file_name") %>%
    filter(!same_permco) %>%
    summarize_counts_by(match_type)

same_permco_match_type_summary <-
    diff_permno_comp_permco %>%
    inner_join(calls, by="file_name") %>%
    filter(same_permco) %>%
    summarize_counts_by(match_type)
