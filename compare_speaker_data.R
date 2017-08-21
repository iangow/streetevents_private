library(DBI)
library(RPostgreSQL)
library(dplyr, warn.conflicts = FALSE)

Sys.setenv(PGHOST = "aaz.chicagobooth.edu", PGDATABASE = "postgres")

pg <- dbConnect(PostgreSQL())

dbGetQuery(pg, "SET work_mem='15GB'")
speaker_data_old <- tbl(pg, sql("SELECT * FROM streetevents.speaker_data"))

speaker_data_alt <- tbl(pg, sql("SELECT * FROM streetevents.speaker_data_alt"))

calls <- tbl(pg, sql("SELECT * FROM streetevents.calls"))

speaker_data_new <-
    speaker_data_alt %>%
    inner_join(
        calls %>%
            select(file_path, file_name, last_update)) %>%
    select(-file_path) %>%
    compute(indexes=list(c("file_name", "last_update",
                           "context", "speaker_number")))

num_secs <-
    speaker_data_new %>%
    group_by(file_name, last_update, context, speaker_number) %>%
    summarize(num_sections = n()) %>%
    group_by(file_name, last_update) %>%
    summarize(num_sections = max(num_sections)) %>%
    ungroup() %>%
    compute()

clean_files <-
    num_secs %>%
    filter(num_sections==1L)

speaker_data_new_filtered <-
    speaker_data_new %>%
    semi_join(clean_files)

speaker_data_merged <-
    speaker_data_new_filtered %>%
    inner_join(speaker_data_old, by=c("file_name", "last_update",
                                      "context", "speaker_number")) %>%
    compute(name="speaker_data_merged")


