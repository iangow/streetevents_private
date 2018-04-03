library(dplyr, warn.conflicts = FALSE)
library(RPostgreSQL)
pg <- dbConnect(PostgreSQL())

rs <- dbExecute(pg, "SET work_mem='3GB'")
rs <- dbExecute(pg, "SET search_path TO streetevents")

speaker_data <- tbl(pg, "speaker_data")

speaker_names_raw <-
    speaker_data %>%
    filter(speaker_name %!~*% '^(Unindent|Operator)',
           role %!~*% 'Analyst') %>%
    select(speaker_name) %>%
    distinct() %>%
    compute()

lname_regex <- paste0("((?:((?:[Dd][aeu]|[Dd]e [Ll]a|[Vv][ao]n [Dd]e[rn]?|[Vv][ao]n))\\s)*",
                      ".*?)$")
lname_regex_alt <- "(?:(.*?)\\s)([^\\s]*)$"
prefix_regex <- paste0("(?:",
                       "Sir|Sen\\.|Maj\\.SEN\\.|SIR\\.|Rep\\.|M[RS]\\.|DR\\.|MRS\\.|Gov\\.",
                       "Prof\\.?|Dr\\.(?: Dr\\.)?|Prof\\.? Dr\\.|Ms\\.?|REP\\.?|[MD]rs?\\.?|Dr\\.\\s?-Ing\\.|",
                       "Lcda.|Miss\\.",
                       ")")

name_regex <- paste0("^(?:(", prefix_regex, ")\\s)?", "(.*?)\\s", "(.*)$")

rs <- dbExecute(pg, "DROP TABLE IF EXISTS speaker_names")
speaker_names <-
    speaker_names_raw %>%
    mutate(name = regexp_matches(speaker_name, name_regex)) %>%
    mutate(prefix = sql("name[1]"),
           first_name = sql("name[2]"),
           last_name = sql("name[3]")) %>%
    mutate(last_name = regexp_matches(last_name, lname_regex)) %>%
    mutate(last_name = sql("last_name[1]"),
           last_name_prefix = sql("last_name[2]")) %>%
    mutate(last_names = if_else(!is.na(last_name_prefix),
                                regexp_split_to_array(last_name, last_name_prefix),
                                regexp_split_to_array(last_name, "\\s"))) %>%
    mutate(lname_len = array_length(last_names, 1L)) %>%
    mutate(middle_name = if_else(lname_len > 1, sql("last_names[1]"), NA_character_),
           last_name = if_else(lname_len > 1, sql("array_to_string(last_names[2:array_length(last_names,1)], ' ')"),
                               sql("last_names[1]"))) %>%
    mutate(middle_name = if_else(middle_name == "", NA_character_, middle_name)) %>%
    mutate(last_name = if_else(is.na(last_name_prefix), last_name, last_name_prefix %||% ' ' %||% last_name)) %>%
    mutate(last_name = trim(last_name), first_name = trim(first_name)) %>%
    select(speaker_name, prefix, first_name, middle_name, last_name) %>%
    compute(name = "speaker_names", temporary = FALSE)

# Some cases have just a prefix and no first name. These could
# be cleaned up using prefix_regex
speaker_names %>%
    filter(first_name %~% paste0("^", prefix_regex, "$")) %>%
    count(prefix, first_name) %>%
    arrange(desc(n)) %>%
    print(n=Inf)

speaker_names

rs <- dbDisconnect(pg)
