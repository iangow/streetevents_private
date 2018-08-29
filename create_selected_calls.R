# This code removes the duplicated call records from two sources
library(dplyr, warn.conflicts = FALSE)
library(RPostgreSQL)
pg <- dbConnect(PostgreSQL())

rs <- dbGetQuery(pg, "SET search_path='streetevents'")
crsp_link <- tbl(pg, "crsp_link")
calls <- tbl(pg, "calls")

latest_calls <-
    calls %>%
    group_by(file_name) %>%
    # Filter file_name with no valid information
    filter(!is.na(start_date)) %>%
    summarize(last_update = max(last_update, na.rm = TRUE),
              has_company_id = bool_or(!is.na(company_id))) %>%
    ungroup() 

dbGetQuery(pg, "DROP TABLE IF EXISTS selected_calls")

selected_calls <-
    calls %>%
    mutate(has_company_id = !is.na(company_id)) %>%
    semi_join(latest_calls, by = c("file_name", "last_update", "has_company_id")) %>%
    group_by(file_name) %>%
    summarize(file_path = max(file_path, na.rm = TRUE)) %>%
    ungroup() %>%
    inner_join(latest_calls, by = "file_name") %>%
    distinct(file_name, file_path, last_update) %>% compute()
    compute(name = "selected_calls", temporary = FALSE)

dbGetQuery(pg, "ALTER TABLE selected_calls OWNER TO streetevents")
dbGetQuery(pg, "GRANT SELECT ON TABLE selected_calls TO streetevents_access")
dbGetQuery(pg, "CREATE INDEX ON streetevents.selected_calls (file_path)")
dbGetQuery(pg, "CREATE INDEX ON streetevents.selected_calls (file_name, file_path)")

comment <- 'CREATED USING iangow/streetevents_private/create_selected_calls.R'
sql <- paste0("COMMENT ON TABLE selected_calls IS '",
              comment, " ON ", Sys.time() , "'")
rs <- dbGetQuery(pg, sql)
dbDisconnect(pg)
