library(dplyr, warn.conflicts = FALSE)
library(RPostgreSQL)

pg <- src_postgres()
dbGetQuery(pg$con, "SET work_mem='15GB'")

qa_pairs <- tbl(pg, sql("SELECT * FROM streetevents.qa_pairs"))

duplicates <-
    qa_pairs %>%
    group_by(file_name, last_update, answer_nums, question_nums) %>%
    summarize(count = n()) %>%
    filter(count > 1) %>%
    ungroup() %>%
    compute()

# duplicates %>% count()
# duplicates %>% select(file_name) %>% distinct() %>% count()
# duplicates

dupe_file_names <- duplicates %>% select(file_name) %>% distinct() %>% collect()
dbDisconnect(pg)

delete_qa_data <- function(file_name) {

    pg <- dbConnect(PostgreSQL())
    sql <- sprintf("DELETE FROM streetevents.qa_pairs WHERE file_name='%s'",
                   file_name)
    res <- dbGetQuery(pg, sql)

    dbDisconnect(pg)
    res
}


library(parallel)
mclapply(dupe_file_names$file_name, delete_qa_data, mc.cores=8)
