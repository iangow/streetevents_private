suppressPackageStartupMessages(library(dplyr))

pg <- src_postgres()

tbl_pg <- function(table) {
    tbl(pg, sql(paste0("SELECT * FROM ", table)))
}

# Run code in streetevents/crsp_link.sql to create
# streetevents.crsp_link
crsp_link <- tbl_pg("streetevents.crsp_link")
company_link <- tbl_pg("streetevents.company_link")

crsp_link %>%
    select(file_name, permno) %>%
    distinct() %>%
    mutate(has_permno=!is.na(permno)) %>%
    count(has_permno)

company_link %>%
    select(file_name, permno) %>%
    distinct() %>%
    mutate(has_permno=!is.na(permno)) %>%
    count(has_permno)
