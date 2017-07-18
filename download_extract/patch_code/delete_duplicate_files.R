library(dplyr, warn.conflicts = FALSE)
library(RPostgreSQL)

pg <- src_postgres()

dbGetQuery(pg$con, "SET work_mem='10GB'")

# Three main tables for StreetEvents
calls <- tbl(pg, sql("SELECT * FROM streetevents.calls"))
call_files <- tbl(pg, sql("SELECT * FROM streetevents.call_files"))
speaker_data <- tbl(pg, sql("SELECT * FROM streetevents.speaker_data"))

# Cases with duplicate files
dupe_file_names <-
    call_files %>%
    inner_join(calls, by=c("file_path", "file_name")) %>%
    select(file_name, last_update, sha1, file_path) %>%
    distinct() %>%
    group_by(file_name, last_update, sha1) %>%
    filter(n() > 1) %>%
    ungroup() %>%
    compute()

# Cases with duplicate data in speaker_data (what we care about)
duplicate_speakers <-
    speaker_data %>%
    group_by(file_name, last_update, speaker_number, context) %>%
    filter(count > 1) %>%
    ungroup() %>%
    compute()

duplicate_speakers %>% select(file_name) %>% distinct() %>% semi_join(calls %>% filter(call_type==1L)) %>% inner_join(calls) %>% collect() %>% ggplot(aes(x=last_update)) + geom_histogram(binwidth=30) + scale_x_datetime()

library(RPostgreSQL)
delete_speaker_data <- function(file_name) {
    # Function to delete data from speaker_data
    pg <- dbConnect(PostgreSQL())
    sql <- sprintf("DELETE FROM streetevents.speaker_data WHERE file_name='%s'",
                   file_name)
    res <- dbGetQuery(pg, sql)

    dbDisconnect(pg)
    res
}

# We want to delete duplicates in speaker_data *caused* by duplicate files
to_delete <-
    dupe_file_names %>%
    semi_join(duplicate_speakers) %>%
    select(file_name) %>%
    distinct() %>%
    collect()

# Run the function
library(parallel)
mclapply(to_delete$file_name, delete_speaker_data, mc.cores=8)

