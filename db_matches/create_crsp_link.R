# Create_crsp_link.R
library(dplyr, warn.conflicts = FALSE)
library(RPostgreSQL)
library(googlesheets)

path <- system("git rev-parse --show-toplevel", intern=T)
file <- paste0(path, '/db_matches/crsp_link.sql')
pguser <- Sys.getenv("PGUSER")
db <- Sys.getenv("PGDATABASE")
host <- Sys.getenv("PGHOST")
system(paste0("psql -U ", pguser, " -d ", db, " -h ", host, " -p 5432 -f ", file))

# Clean crsp_link
name_checks <- 
    gs_read(gs_key("1_RKRJah6iuUHC-y_kHP58Dl6UaptIhBNPRSyTjIjSSM")) %>% 
    copy_to(pg, ., name = 'name_checks', temporary = TRUE)

# Clean crsp_link
pg <- dbConnect(PostgreSQL())
crsp_link <- tbl(pg, sql("SELECT * FROM streetevents.crsp_link"))
calls <- tbl(pg, sql("SELECT * FROM streetevents.calls"))

crsp_link <- 
    crsp_link %>% 
    filter(!is.na(permno)) %>% 
    anti_join(name_checks %>% 
                  filter(valid == FALSE) %>%
                  inner_join(crsp_link %>% 
                                 filter(!is.na(permno)), 
                             by = "permno", copy = TRUE) %>% 
                  inner_join(calls %>% 
                                 select(file_name, event_title),
                             by = "file_name", copy = TRUE) %>% 
                  select(-match_type, -match_type_desc) %>% 
                  filter(event_title %~% event_co_name),
              by = "file_name", 
              copy = TRUE) %>% 
    compute(name = 'crsp_link', temporary = FALSE)

dbGetQuery(pg, "DROP VIEW IF EXISTS streetevents.company_link")
dbGetQuery(pg, "DROP TABLE IF EXISTS streetevents.crsp_link")
dbGetQuery(pg, "ALTER TABLE crsp_link SET SCHEMA streetevents")
dbGetQuery(pg, "ALTER TABLE streetevents.crsp_link OWNER TO streetevents")
dbGetQuery(pg, "GRANT SELECT ON streetevents.crsp_link TO streetevents_access")
dbGetQuery(pg, "CREATE VIEW streetevents.company_link AS SELECT * FROM streetevents.crsp_link")
dbGetQuery(pg, "CREATE INDEX ON streetevents.crsp_link (file_name)")
db_comment <- paste0("CREATED USING create_crsp_link.R ON ", Sys.time())
dbGetQuery(pg, sprintf("COMMENT ON TABLE streetevents.crsp_link IS '%s';", db_comment))
