#!/usr/bin/env Rscript
library(RPostgreSQL)

pg <- dbConnect(PostgreSQL())

# If table doesn't exist, create it.
if (!dbExistsTable(pg, c("streetevents", "qa_pairs"))) {
    dbGetQuery(pg, "
        DROP TABLE IF EXISTS streetevents.qa_pairs;

        CREATE TABLE streetevents.qa_pairs
        (
          file_name text,
          last_update timestamp with time zone,
          answer_nums integer[],
          question_nums integer[]
        );

        CREATE INDEX ON streetevents.qa_pairs (file_name, last_update);
        ALTER TABLE streetevents.qa_pairs OWNER TO streetevents;
        GRANT SELECT ON streetevents.qa_pairs TO streetevents_access;")
}

rs <- dbDisconnect(pg)

# Get a list of files on StreetEvents, but not on qa_pairs table.
library(dplyr, warn.conflicts = FALSE)
pg <- dbConnect(PostgreSQL())

calls <- tbl(pg, sql("SELECT * FROM streetevents.calls"))
qa_pairs <- tbl(pg, sql("SELECT * FROM streetevents.qa_pairs"))

file_list <-
    calls %>%
    filter(event_type == 1L) %>%
    select(file_name, last_update) %>%
    anti_join(qa_pairs) %>%
    collect(n = Inf)

# A function that calls the parameterized query to process each file
addQAPairs <- function(file_name) {
    library(RPostgreSQL)
    sql <- paste(readLines("qa_pairs/create_qa_pairs.sql"), collapse="\n")

    pg <- dbConnect(PostgreSQL())
    dbGetQuery(pg, sprintf(sql, file_name, file_name))
    dbDisconnect(pg)
}

# Code that applies addQAPairs to function in parallel.
library(parallel)
system.time(res <- unlist(mclapply(file_list$file_name, addQAPairs, mc.cores=20)))

