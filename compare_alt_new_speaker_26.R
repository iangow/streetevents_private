library(RPostgreSQL)
library(dplyr, warn.conflicts = FALSE)

rm(list=ls())
pg <- src_postgres() 


se_alt <- tbl(pg, sql("select * from streetevents.speaker_data_alt")) 
se_new <- tbl(pg, sql("select * from streetevents.speaker_data_new")) 

calls <- tbl(pg, sql("SELECT * FROM streetevents.calls"))
calls_new <- tbl(pg, sql("SELECT * FROM streetevents.calls_new"))

singleton_calls <-
    calls %>% 
    select(file_path, file_name, last_update) %>% 
    distinct() %>% 
    group_by(file_name) %>% 
    filter(n() == 1L) %>%
    ungroup()

# Add file_name, last_update to se_alt
se_alt_new <- 
    se_alt %>%
    inner_join(singleton_calls) %>%
    select(-file_path) %>% 
    compute(indexes=list(c("file_name", "last_update",
                           "context", "speaker_number")))

num_secs <-
    se_alt_new %>%
    group_by(file_name, last_update, context, speaker_number) %>%
    summarize(num_sections = n()) %>%
    group_by(file_name, last_update) %>%
    summarize(num_sections = max(num_sections)) %>%
    ungroup() %>%
    compute()

clean_files <-
    num_secs %>%
    filter(num_sections==1L)

se_alt_new_filtered <-
    se_alt_new %>%
    semi_join(clean_files)

se_data_merged <- 
    se_alt_new_filtered %>% 
    inner_join(se_new, by = c("file_name", "context", "speaker_number")) %>% 
    compute(name = "zjy_speaker_data_merged_new_alt")



            

colnames(se_alt)
colnames(se_new)
colnames(calls)
colnames(calls_new)
