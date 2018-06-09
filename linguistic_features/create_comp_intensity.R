library(RPostgreSQL)
library(dplyr, warn.conflicts = FALSE)

pg <- dbConnect(PostgreSQL())
rs <- dbExecute(pg, "SET search_path TO streetevents, public")
rs <- dbExecute(pg, "SET work_mem = '10GB'")
speaker_data <- tbl(pg, "speaker_data")

regex <- "((?:\\w+\\W+){0,3})([Cc]ompet(?:(?:it(?:ion|or|ive))|e|ing)s?)"
exclude_words = c("not", "less", "few", "limited")
exclude_regex <- paste0("\\W(?:", paste(exclude_words, collapse = "|"), ")\\W")

competition_words <-
    speaker_data %>%
    mutate(matches = regexp_matches(speaker_text, regex)) %>%
    mutate(preceding_words = sql("matches[1]"),
           competition_word = sql("matches[2]")) %>%
    select(file_name, last_update, section, context, speaker_number,
           preceding_words, competition_word) %>%
    compute()

exclude_words <-
    competition_words %>%
    mutate(exclude_matches = regexp_matches(preceding_words, exclude_regex)) %>%
    mutate(exclude = TRUE) %>%
    select(file_name, last_update, section, context, speaker_number,
           exclude_matches, exclude)

dbExecute(pg, "DROP TABLE IF EXISTS competition_intensity")

comp_intensity <-
    competition_words %>%
    left_join(exclude_words) %>%
    mutate(exclude = coalesce(exclude, FALSE)) %>%
    compute(name = "comp_intensity", temporary = FALSE,
            indexes = list(c("file_name", "last_update")))

rs <- dbExecute(pg, "ALTER TABLE comp_intensity OWNER TO streetevents")
rs <- dbExecute(pg, "GRANT SELECT ON comp_intensity TO streetevents_access")

rs <- dbDisconnect(pg)
