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
    # Consider earnings call only
    filter(event_type == 1) %>%
    # Filter file_name with no valid information
    filter(!is.na(start_date)) %>%
    summarize(last_update = max(last_update, na.rm = TRUE),
              has_company_id = max(as.integer(!is.na(company_id)), na.rm = TRUE)) %>%
    ungroup()

dbGetQuery(pg, "DROP TABLE IF EXISTS selected_calls")

selected_calls <-
    calls %>%
    mutate(has_company_id = as.integer(!is.na(company_id))) %>%
    semi_join(latest_calls) %>%
    group_by(file_name) %>%
    summarize(file_path = max(file_path, na.rm = TRUE)) %>%
    ungroup() %>%
    inner_join(latest_calls) %>%
    group_by(file_name, file_path) %>%
    summarise(last_update = max(last_update, na.rm = TRUE)) %>%
    ungroup() %>%
    compute(name = "selected_calls", temporary = FALSE)

dbGetQuery(pg, "ALTER TABLE selected_calls OWNER TO streetevents")
dbGetQuery(pg, "GRANT SELECT ON TABLE selected_calls TO streetevents_access")

comment <- 'CREATED USING iangow/streetevents_private/create_selected_calls.R'
sql <- paste0("COMMENT ON TABLE selected_calls IS '",
              comment, " ON ", Sys.time() , "'")
rs <- dbGetQuery(pg, sql)
dbDisconnect(pg)
