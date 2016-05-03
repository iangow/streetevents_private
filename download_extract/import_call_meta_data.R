#!/usr/bin/env Rscript

# Delete files that no longer exist ----
library(RPostgreSQL)
pg <- dbConnect(PostgreSQL())

last_update <- dbGetQuery(pg, "
    DELETE FROM streetevents.calls AS a
    USING streetevents.calls AS b
    LEFT JOIN streetevents.call_files AS c
    USING (file_path)
    WHERE c.file_path IS NULL AND a.file_path=b.file_path")

rs <- dbDisconnect(pg)

# Get a list of files that need to be processed ----

# Note that this assumes that streetevents.calls is up to date.
library("RPostgreSQL")
print(Sys.getenv("PGHOST"))

pg <- dbConnect(PostgreSQL())

if (!dbExistsTable(pg, c("streetevents", "calls"))) {
    dbGetQuery(pg, "
        CREATE TABLE streetevents.calls
        (
          file_path text NOT NULL,
          file_name text,
          ticker text,
          co_name text,
          call_desc text,
          call_date timestamp without time zone,
          city text,
          call_type integer,
          last_update timestamp without time zone,
          PRIMARY KEY (file_path)
        );

        CREATE INDEX ON streetevents.calls (file_name);")
}

file_list <- dbGetQuery(pg, "
    SET work_mem='2GB';

    SELECT DISTINCT file_path
    FROM streetevents.call_files
    WHERE file_path NOT IN (SELECT file_path FROM streetevents.calls)")

rs <- dbDisconnect(pg)

# Create function to parse a StreetEvents XML file ----
parseFile <- function(file_path) {
    full_path <- file.path(Sys.getenv("EDGAR_DIR"), "streetevents_project",
                           file_path)
    # Parse the indicate file using a Perl script
    cmd <- paste("download_extract/parse_xml_files.pl", full_path)
    # cat(cmd)
    system(cmd, intern = TRUE)
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
sql <- paste0("COMMENT ON TABLE streetevents.calls IS '",
              "Last update on ", last_update , "'")
rs <- dbGetQuery(pg, sql)
dbDisconnect(pg)

# Add comment to reflect last update ----
library(RPostgreSQL)
pg <- dbConnect(PostgreSQL())
last_update <- dbGetQuery(pg,
                          "SELECT max(last_update)::text FROM streetevents.calls")
sql <- paste0("COMMENT ON TABLE streetevents.call_files IS '",
              "Last update on ", last_update , "'")
rs <- dbGetQuery(pg, sql)
dbDisconnect(pg)

