#!/usr/bin/env Rscript

# Get a list of files that need to be processed ----

library("RPostgreSQL")
pg <- dbConnect(PostgreSQL())

if (!dbExistsTable(pg, c("streetevents", "speaker_data"))) {
    dbGetQuery(pg, "
        CREATE TABLE streetevents.speaker_data
           (
           file_name text,
           last_update timestamp without time zone,
           speaker_name text,
           employer text,
           role text,
           speaker_number integer,
           context text,
           speaker_text text,
           language text
           );

       SET maintenance_work_mem='3GB';

       CREATE INDEX ON streetevents.speaker_data (file_name, last_update);
       CREATE INDEX ON streetevents.speaker_data (file_name);")
}
rs <- dbDisconnect(pg)

library(dplyr, warn.conflicts = FALSE)

pg <- src_postgres()

# Three main tables for StreetEvents
calls <- tbl(pg, sql("SELECT * FROM streetevents.calls"))
call_files <- tbl(pg, sql("SELECT * FROM streetevents.call_files"))
speaker_data <- tbl(pg, sql("SELECT * FROM streetevents.speaker_data"))

latest_mtime <-
    calls %>%
    inner_join(call_files, by = c("file_name", "file_path")) %>%
    group_by(file_name, last_update) %>%
    summarize(mtime = max(mtime)) %>%
    compute()

latest_calls <-
    calls %>%
    inner_join(latest_mtime, by = c("file_name", "last_update")) %>%
    select(file_name, last_update, file_path) %>%
    inner_join(call_files, by = c("file_name", "file_path")) %>%
    group_by(sha1) %>%
    filter(file_path == min(file_path)) %>%
    ungroup() %>%
    compute()

file_list <-
    latest_calls %>%
    anti_join(speaker_data,  by = c("file_name", "last_update")) %>%
    select(file_path) %>%
    distinct() %>%
    collect()

# Note that this assumes that streetevents.calls is up to date.

# Create function to parse a StreetEvents XML file ----
parseFile <- function(file_path) {

    full_path <- file.path(Sys.getenv("EDGAR_DIR"),
                           "streetevents_project",
                           file_path)

    # Parse the indicated file using a Perl script
    system(paste("download_extract/import_speaker_data.pl",
                 full_path),
           intern = TRUE)
}

# Apply parsing function to files ----
library(parallel)
system.time({
    res <- unlist(mclapply(file_list$file_path, parseFile, mc.cores=8))
})

# Add comment to reflect last update ----
library(RPostgreSQL)
pg <- dbConnect(PostgreSQL())
last_update <- dbGetQuery(pg,
                          "SELECT max(last_update)::text FROM streetevents.calls")
sql <- paste0("COMMENT ON TABLE streetevents.speaker_data IS '",
              "Last update on ", last_update , "'")
rs <- dbGetQuery(pg, sql)
dbDisconnect(pg)
