library(googlesheets)
library(dplyr, warn.conflicts = FALSE)

# You may need to run gs_auth() to set this up
gs <- gs_key("14F6zjJQZRsf5PonOfZ0GJrYubvx5e_eHMV_hCGe42Qg")
permnos <- gs_read(gs, ws = "manual_permno_matches")

permnos_addl <-
    gs_read(gs, ws = "match_repair.csv") %>%
    filter(!same_permco) %>%
    select(file_name, permno, co_name) %>%
    mutate(comment = "Cases resolved using company names in 2017")

permnos <-
    gs_read(gs, ws = "manual_permno_matches") %>%
    union(permnos_addl)

pg_comment <- function(table, comment) {
    library(RPostgreSQL)
    pg <- dbConnect(PostgreSQL())
    sql <- paste0("COMMENT ON TABLE ", table, " IS '",
                  comment, " ON ", Sys.time() , "'")
    rs <- dbGetQuery(pg, sql)
    dbDisconnect(pg)
}

library(RPostgreSQL)
pg <- dbConnect(PostgreSQL())

rs <- dbWriteTable(pg, c("streetevents", "manual_permno_matches"),
                   permnos,
                   overwrite=TRUE, row.names=FALSE)

rs <- dbGetQuery(pg, "
    ALTER TABLE streetevents.manual_permno_matches
    OWNER TO streetevents_access")

rs <- dbGetQuery(pg,
    "DELETE FROM streetevents.manual_permno_matches
    WHERE file_name IN (
        SELECT file_name
        FROM streetevents.manual_permno_matches
        GROUP BY file_name
        HAVING count(DISTINCT permno)>1)
            AND comment != 'Fix by Nastia/Vincent in January 2015';

    CREATE INDEX ON streetevents.manual_permno_matches (file_name);

    ALTER TABLE streetevents.manual_permno_matches OWNER TO streetevents;

    GRANT SELECT ON streetevents.manual_permno_matches TO streetevents_access;")

rs <- dbDisconnect(pg)

rs <- pg_comment("streetevents.manual_permno_matches",
           paste0("CREATED USING import_manual_permno_matches.R ON ", Sys.time()))
