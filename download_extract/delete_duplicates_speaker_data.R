library(dplyr, warn.conflicts = FALSE)
library(RPostgreSQL)
#> Loading required package: DBI

pg <- src_postgres()
dbGetQuery(pg$con, "SET work_mem='15GB'")

speaker_data <- tbl(pg, sql("SELECT * FROM streetevents.speaker_data"))

duplicates <-
    speaker_data %>%
    group_by(file_name, last_update, speaker_number, context) %>%
    summarize(count = n()) %>%
    filter(count > 1) %>%
    ungroup() %>%
    compute()

# duplicates %>% count()
# duplicates %>% select(file_name) %>% distinct() %>% count()
# duplicates

dupe_file_names <- duplicates %>% select(file_name) %>% distinct() %>% collect()
dbDisconnect(pg)

# speaker_data %>%
#     semi_join(duplicates %>% filter(file_name == dupe_file_names$file_name[1])) %>%
#     arrange(context, speaker_number) %>%
#     select(speaker_text)


delete_speaker_data <- function(file_name) {

    pg <- dbConnect(PostgreSQL())
    sql <- sprintf("DELETE FROM streetevents.speaker_data WHERE file_name='%s'",
                   file_name)
    res <- dbGetQuery(pg, sql)

    dbDisconnect(pg)
    res
}


delete_qa_data <- function(file_name) {

    pg <- dbConnect(PostgreSQL())
    sql <- sprintf("DELETE FROM streetevents.qa_pairs WHERE file_name='%s'",
                   file_name)
    res <- dbGetQuery(pg, sql)

    dbDisconnect(pg)
    res
}


library(parallel)

### delete duplicates from speaker_data
mclapply(dupe_file_names$file_name, delete_speaker_data, mc.cores=8)

### delete the same duplicates from qa_pairs
# mclapply(dupe_file_names$file_name, delete_qa_data, mc.cores=8)
