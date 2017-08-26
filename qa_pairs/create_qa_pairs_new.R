library(RPostgreSQL)
library(dplyr, warn.conflicts = FALSE)

pg <- dbConnect(PostgreSQL())

speaker_data <- tbl(pg, sql("SELECT * FROM streetevents.speaker_data"))
calls <- tbl(pg, sql("SELECT * FROM streetevents.calls"))

dbSendQuery(pg, "SET work_mem='15GB'")

sample_transcripts <-
    speaker_data %>%
    inner_join(calls) %>%
    mutate(is_answer = role %!~% 'Analyst',
           is_question = role %~% 'Analyst' & speaker_text %~% '\\?') %>%
    filter(event_type==1L, context=='qa', speaker_name != 'Operator',
           section == 1) %>%
    select(file_name, last_update, section, context, speaker_number,
           speaker_name, is_question, is_answer, role) %>%
    compute()
    #    AND file_name='%s'

grouped <-
    sample_transcripts %>%
    mutate(is_question = as.integer(is_question)) %>%
    select(file_name, last_update, role, speaker_number, speaker_name,
           is_question) %>%
    group_by(file_name, last_update) %>%
    window_frame(-Inf, 0) %>%
    window_order(speaker_number) %>%
    mutate(question_group = sum(is_question)) %>%
    compute()

questions_raw <-
    grouped %>%
    mutate(is_question = sql("is_question::boolean")) %>%
    filter(role == 'Analyst') %>%
    group_by(file_name, last_update, question_group) %>%
    summarise(speaker_numbers = sql("array_agg(speaker_number ORDER BY speaker_number)"))

questions_inter <-
    questions_raw %>%
    group_by(file_name, last_update) %>%
    window_order(speaker_numbers) %>%
    mutate(lead_speaker_numbers = lead(speaker_numbers))

questions <-
    questions_inter %>%
    mutate(first_speaker_num= array_min(speaker_numbers),
        last_speaker_num = array_min(lead_speaker_numbers) - 1) %>%
    inner_join(grouped) %>%
    rename(questioner= speaker_name) %>%
    rename(question_nums = speaker_numbers) %>%
    select(file_name, last_update, questioner,
        question_nums, first_speaker_num, last_speaker_num)

answers <-
    sample_transcripts %>%
    filter(is_answer) %>%
    inner_join(questions, by=c("file_name", "last_update")) %>%
    filter(speaker_number >= first_speaker_num,
           speaker_number <= last_speaker_num | is.na(last_speaker_num)) %>%
    group_by(file_name, last_update, first_speaker_num) %>%
    summarize(answer_nums = sql("array_agg(DISTINCT speaker_number ORDER BY speaker_number)")) %>%
    ungroup() %>%
    distinct() %>%
    compute()

final <-
    questions %>%
    inner_join(answers) %>%
    select(file_name, last_update, question_nums, answer_nums) %>%
    distinct() %>%
    compute(name = "qa_pairs", temporary = FALSE)

dbSentQuery(pg, "ALTER TABLE qa_pairs SET SCHEMA streetevents")
dbSentQuery(pg, "ALTER TABLE streetevents.qa_pairs OWNER TO streetevents")
dbSentQuery(pg, "GRANT SELECT ON streetevents.qa_pairs TO streetevents_access")

dbDisconnect(pg)
