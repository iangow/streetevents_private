# This code removes the duplicated call records from two sources
library(dplyr, warn.conflicts = FALSE)
library(RPostgreSQL)
pg <- dbConnect(PostgreSQL())

crsp_link <- tbl(pg, sql("SELECT * FROM streetevents.crsp_link")) 
calls <- tbl(pg, sql("select * from streetevents.calls")) 

latest_calls <-
    calls %>%
    group_by(file_name) %>%
    # Consider earnings call only
    filter(event_type == 1) %>%
    # Filter file_name with no valid information
    filter(!is.na(start_date)) %>%
    summarize(last_update = max(last_update, na.rm = TRUE),
              has_company_id = max(as.integer(!is.na(company_id)), na.rm = TRUE))

selected_calls <-
    calls %>%
    mutate(has_company_id = as.integer(!is.na(company_id))) %>%
    semi_join(latest_calls) %>% 
    group_by(file_name) %>% 
    summarize(file_path = max(file_path, na.rm = TRUE)) %>%
    inner_join(latest_calls) %>%
    select(file_name, file_path) %>%
    compute(name = "selected_calls", temporary = FALSE)

dbGetQuery(pg, "DROP TABLE IF EXISTS streetevents.selected_calls")
dbGetQuery(pg, "ALTER TABLE selected_calls SET SCHEMA streetevents")
dbGetQuery(pg, "ALTER TABLE streetevents.selected_calls OWNER TO streetevents")
dbGetQuery(pg, "GRANT SELECT ON TABLE streetevents.selected_calls TO streetevents_access")

comment <- 'CREATED USING iangow/streetevents_private/create_selected_calls.R'
sql <- paste0("COMMENT ON TABLE streetevents.selected_calls IS '",
              comment, " ON ", Sys.time() , "'")
rs <- dbGetQuery(pg, sql)
rm(pg)