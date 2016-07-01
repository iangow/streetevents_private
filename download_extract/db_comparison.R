library(dplyr)

pg_aaz <- src_postgres(host="aaz.chicagobooth.edu", db="postgres")

calls_aaz <- tbl(pg_aaz, sql("SELECT * FROM streetevents.calls"))
speaker_aaz <- tbl(pg_aaz, sql("SELECT * FROM streetevents.speaker_data"))

pg_ig <- src_postgres(host="iangow.me", db="crsp")

calls_ig <- tbl(pg_ig, sql("SELECT * FROM streetevents.calls"))
speaker_ig <- tbl(pg_ig, sql("SELECT * FROM streetevents.speaker_data"))

pg_lh <- src_postgres(host="localhost", db="crsp")

calls_lh <- tbl(pg_lh, sql("SELECT * FROM streetevents.calls"))
speaker_lh <- tbl(pg_lh, sql("SELECT * FROM streetevents.speaker_data"))
call_files_lh <- tbl(pg_lh, sql("SELECT * FROM streetevents.call_files"))

calls_aaz %>%
    select(file_path) %>%
    distinct() %>%
    summarize(count=n())

calls_lh %>%
    select(file_path) %>%
    distinct() %>%
    summarize(count=n())

calls_ig %>%
    select(file_path) %>%
    distinct() %>%
    summarize(count=n())



speaker_aaz %>%
    select(file_name) %>%
    distinct() %>%
    summarize(count=n())

speaker_lh %>%
    select(file_name) %>%
    distinct() %>%
    summarize(count=n())

speaker_ig %>%
    select(file_name) %>%
    distinct() %>%
    summarize(count=n())

# missing_lh <-
#     calls_ig %>%
#     collect() %>%
#     anti_join(calls_lh %>% collect())
