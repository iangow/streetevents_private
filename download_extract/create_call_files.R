#!/usr/bin/env Rscript

# Code to generate a list of files in the StreetEvents directory
# and post to PostgreSQL.

# Set up stuff ----
library(parallel)
library(dplyr)
getSHA1 <- function(file_name) {
    library("digest")
    digest(file=file_name, algo="sha1")
}

# Get a list of files ----
streetevent.dir <- file.path(Sys.getenv("EDGAR_DIR"), "uploads")
full_path <- list.files(streetevent.dir,
                   pattern="*_T.xml", recursive = TRUE,
                   include.dirs=FALSE, full.names = TRUE)

file_list <-
    data_frame(full_path) %>%
    mutate(mtime = as.character(as.POSIXlt(file.mtime(full_path), tz="UTC")),
           file_path = gsub(paste0(streetevent.dir, "/"), "", full_path,
                            fixed = TRUE))

library("RPostgreSQL")
pg <- dbConnect(PostgreSQL())

new_table <- !dbExistsTable(pg, c("streetevents", "call_files"))

if (!new_table) {
    rs <- dbWriteTable(pg, c("streetevents", "call_files_temp"),
                       file_list %>%
                           select(file_path, mtime),
                       overwrite=TRUE, row.names=FALSE)
    dbGetQuery(pg, "
        CREATE INDEX ON streetevents.call_files_temp (file_path, mtime)")
    dbDisconnect(pg)

    pg <- src_postgres()

    new_files <- tbl(pg, sql("
        SELECT file_path, mtime
        FROM streetevents.call_files_temp
        EXCEPT
        SELECT file_path,
            (mtime AT TIME ZONE 'UTC')::text AS mtime
        FROM streetevents.call_files")) %>%
        collect()

    if (dim(new_files)[1]>0) {
        new_files <-
            new_files %>%
            inner_join(file.list %>% mutate(mtime = as.character(mtime)))
    }
} else {
    new_files <- file_list
}

# Process files ----
if (dim(new_files)[1]>0) {
    file_info <-
        file.info(new_files$full_path ) %>%
        as_data_frame() %>%
        transmute(file_size = size,
                  ctime = as.character(as.POSIXlt(ctime, tz="UTC")))

    new_files <-
        bind_cols(new_files, file_info) %>%
        mutate(file_name = gsub("\\.xml", "", basename(file_path))) %>%
        rowwise() %>%
        mutate(sha1 = getSHA1(full_path)) %>%
        select(file_path, file_size, mtime, ctime, file_name, sha1) %>%
        as.data.frame()

    if (!new_table) {
        pg <- dbConnect(PostgreSQL())
        rs <- dbWriteTable(pg, c("streetevents", "call_files_new"),
                           new_files,
                           append=TRUE, row.names=FALSE)
        dbGetQuery(pg, "
            ALTER TABLE streetevents.call_files_new
            ALTER mtime TYPE timestamp with time zone
            USING mtime::timestamp without time zone AT TIME ZONE 'UTC'")

        dbGetQuery(pg, "
            ALTER TABLE streetevents.call_files_new
            ALTER ctime TYPE timestamp with time zone
            USING ctime::timestamp without time zone AT TIME ZONE 'UTC'")

        dbGetQuery(pg, "INSERT INTO streetevents.call_files
            SELECT file_path, file_size, mtime, ctime, file_name, sha1
            FROM streetevents.call_files_new")

        dbGetQuery(pg, "DROP TABLE streetevents.call_files_temp")
        dbGetQuery(pg, "DROP TABLE streetevents.call_files_new")
        dbDisconnect(pg)
    }

    if (new_table) {
        pg <- dbConnect(PostgreSQL())
        rs <- dbWriteTable(pg, c("streetevents", "call_files"), new_files,
                           overwrite=TRUE, row.names=FALSE)
        dbGetQuery(pg, "
            ALTER TABLE streetevents.call_files
            ALTER mtime TYPE timestamp with time zone
            USING mtime::timestamp without time zone AT TIME ZONE 'UTC'")

        dbGetQuery(pg, "
            SET maintenance_work_mem='2GB';
            CREATE INDEX ON streetevents.call_files (file_path)")
        rs <- dbDisconnect(pg)
    }
}
