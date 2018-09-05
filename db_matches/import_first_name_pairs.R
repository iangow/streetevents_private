library(dplyr, warn.conflicts = FALSE)
library(RPostgreSQL)
library(googlesheets)
pg <- dbConnect(PostgreSQL())

gs <- gs_key("1Yafgmt7hYjgzy30k5v41Cx7-uiiTvmvvgl8MHjDf4yc")

first_name_pairs <-
    gs_read(gs, ws = "first_name_combos.csv") %>%
    filter(valid) %>%
    select(fname_alt, first_name)

dbGetQuery(pg, "DROP TABLE IF EXISTS streetevents.first_name_pairs")
copy_to(pg, first_name_pairs, temporary = FALSE)

dbGetQuery(pg, "ALTER TABLE first_name_pairs SET SCHEMA streetevents")
dbGetQuery(pg, "ALTER TABLE streetevents.first_name_pairs OWNER TO streetevents")
dbGetQuery(pg, "GRANT SELECT ON TABLE streetevents.first_name_pairs TO streetevents_access")

comment <- 'CREATED USING import_first_name_pairs.R'
sql <- paste0("COMMENT ON TABLE streetevents.first_name_pairs IS '",
              comment, " ON ", Sys.time() , "'")
rs <- dbGetQuery(pg, sql)
dbDisconnect(pg)
