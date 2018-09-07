# Related to https://github.com/iangow/personality/issues/75
# Back fill executive_id to spreadsheet 
# Matching on company_id and names

# Load data ----
library(dplyr)
library(googlesheets)
library(RPostgreSQL)

pg <- src_postgres()
# gs_auth()
executive_manual_matches <- 
    gs_read(ws = "Sheet1", gs_key("1n2OgXzqFlvegHdlnvoitXGuwxbBai77_FqIyhPbua3c")) %>% 
    filter(good_match == TRUE) %>% 
    copy_to(pg, ., name = 'executive_manual_matches', temporary = FALSE)

executive_manual_matches <- 
    executive_manual_matches %>% 
    compute()

manual_add_exe_id <- 
    gs_read(ws = "manual_add_executive_id", gs_key("1n2OgXzqFlvegHdlnvoitXGuwxbBai77_FqIyhPbua3c"))
proxy_management <- tbl(pg, sql("SELECT * FROM executive.proxy_management"))

manual_matches <- # file_name, speaker_name, company_id, management_id  # Need executive_id
    executive_manual_matches %>%
    select(file_name, speaker_name, equilar_id, equilar_executive_id) %>%
    rename(company_id = equilar_id) %>% 
    rename(management_id = equilar_executive_id)
mgt_link <-
    proxy_management %>% 
    select(company_id, management_id, executive_id, fname, lname) %>%
    mutate(full_name = sql("fname || ' ' || lname")) %>% 
    select(-fname, -lname) %>% 
    distinct()

# Handle names ----
split_names <- function(df){
    lname_regex <- paste0("((?:((?:[Dd][aeu]|[Dd]e [Ll]a|[Vv][ao]n [Dd]e[rn]?|[Vv][ao]n))\\s)*",
                          ".*?)$")
    lname_regex_alt <- "(?:(.*?)\\s)([^\\s]*)$"
    prefix_regex <- paste0("(?:",
                           "Sir|Sen\\.|Maj\\.SEN\\.|SIR\\.|Rep\\.|M[RS]\\.|DR\\.|MRS\\.|Gov\\.",
                           "Prof\\.?|Dr\\.(?: Dr\\.)?|Prof\\.? Dr\\.|Ms\\.?|REP\\.?|[MD]rs?\\.?|Dr\\.\\s?-Ing\\.|",
                           "Lcda.|Miss\\.",
                           ")")
    
    name_regex <- paste0("^(?:(", prefix_regex, ")\\s)?", "(.*?)\\s", "(.*)$")
    suffix <- paste0("(?:", "\\sJr\\.?|II|III|MD", ")")

    df <-
        df %>% 
        mutate(full_names = regexp_split_to_array(full_name, suffix)) %>% 
        mutate(full_name_new = sql("full_names[1]")) %>% 
        mutate(name = regexp_matches(full_name_new, name_regex)) %>%
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
        mutate(last_names = regexp_split_to_array(last_name, ",")) %>% 
        mutate(last_name = sql("last_names[1]")) %>% 
        mutate(last_name = if_else(last_name == '' & middle_name != '', middle_name, last_name),
               middle_name = if_else(middle_name == last_name, '', middle_name)) %>% 
        select(full_name, prefix, first_name, middle_name, last_name) %>%
        compute()
    return(df)
}

mgt_link <- 
    mgt_link %>% 
    left_join(
        mgt_link %>% 
            select(full_name) %>% 
            distinct() %>% 
            split_names(),
        by = c("full_name")) %>% 
    select(company_id, management_id, executive_id, first_name, last_name) %>% 
    compute()

manual_matches <- 
    manual_matches %>% 
    left_join(
        manual_matches %>% 
            select(speaker_name) %>% 
            distinct() %>% 
            rename(full_name = speaker_name) %>% 
            split_names() %>% 
            rename(speaker_name = full_name),
        by = "speaker_name") %>% 
    select(-prefix, - middle_name) %>% 
    compute()

# Case 1: Management_id remains the same ----
result <- 
    manual_matches %>% 
    left_join(mgt_link, by = c("company_id", "management_id")) %>% 
    mutate(has_match = !is.na(executive_id)) %>%
    compute()

manual_matches_exe_id <- # 2299
    result %>% 
    filter(has_match == TRUE) %>% 
    select(file_name, speaker_name, company_id, management_id,executive_id) %>% 
    mutate(exe_id_match = as.character("(company_id, management_id)"))

# Case 2: Manual match ----
manual_match <- # 633
    result %>% 
    filter(is.na(executive_id)) %>% 
    select(file_name, speaker_name, company_id, first_name.x, last_name.x) %>% 
    mutate(first_name = upper(first_name.x),
           last_name = upper(last_name.x)) %>% 
    select(-first_name.x, -last_name.x) %>% 
    distinct() %>% 
    left_join(manual_add_exe_id, by = c("file_name", "speaker_name", "company_id"), copy = TRUE)

manual_matches_exe_id <- # 2311
    manual_match %>% 
    filter(!is.na(executive_id)) %>% 
    select(file_name, speaker_name, company_id, management_id, executive_id) %>% 
    mutate(exe_id_match = as.character("from gs: (manual_add_executive_id)")) %>% 
    union(manual_matches_exe_id)

# Case 3: (fname, lname) match ----
full_match <- 
    manual_match %>% 
    filter(is.na(executive_id)) %>% 
    select(file_name, speaker_name, company_id, first_name, last_name) %>% 
    mutate(first_name = upper(first_name),
           last_name = upper(last_name)) %>% 
    distinct() %>% 
    left_join(mgt_link, by = c("company_id", "first_name" , "last_name")) 

manual_matches_exe_id <- # 2437
    full_match %>% 
    filter(!is.na(executive_id)) %>% 
    select(file_name, speaker_name, company_id, management_id, executive_id) %>% # 132
    mutate(exe_id_match = as.character("(company_id, fname, lname)")) %>% 
    union(manual_matches_exe_id)

# Case 4: Last name match ----
lname_match <- 
    full_match %>% 
    filter(is.na(executive_id)) %>% 
    select(file_name, speaker_name, company_id, first_name, last_name) %>% 
    left_join(mgt_link, by = c("company_id", "last_name")) 

manual_matches_exe_id <- # 2610
    lname_match %>% 
    filter(!is.na(executive_id)) %>% 
    select(file_name, speaker_name, company_id, management_id, executive_id) %>% # 177
    mutate(exe_id_match = as.character("(company_id, lname)")) %>% 
    union(manual_matches_exe_id)

# Upload to pg ----
dbGetQuery(pg$con, "DROP TABLE IF EXISTS public.executive_manual_matches")
dbGetQuery(pg$con, "DROP TABLE IF EXISTS streetevents.executive_manual_matches")
executive_manual_matches_new <- 
    manual_matches_exe_id %>% 
    left_join(executive_manual_matches %>% 
                  rename(company_id = equilar_id) %>% 
                  rename(management_id = equilar_executive_id), 
              by = c("file_name", "speaker_name", "company_id")) %>% 
    rename(management_id = management_id.y) %>% 
    select(file_name, speaker_name, executive, company_id, management_id, executive_id, match_type, good_match, comments, exe_id_match) %>% 
    distinct() %>% 
    compute(name = 'executive_manual_matches', temporary = FALSE)

dbGetQuery(pg$con, "ALTER TABLE executive_manual_matches SET SCHEMA streetevents")
dbGetQuery(pg$con, "ALTER TABLE streetevents.executive_manual_matches OWNER TO streetevents")
dbGetQuery(pg$con, "GRANT SELECT ON streetevents.executive_manual_matches TO streetevents_access")
db_comment <- paste0("CREATED USING iangow/streetevents_private/import_executive_manual_matches.R ON ", Sys.time(), ".")
dbGetQuery(pg$con, sprintf("COMMENT ON TABLE streetevents.executive_manual_matches IS '%s';", db_comment))

# Check no match ----
no_match <- # 621
    manual_match %>% 
    filter(is.na(executive_id)) %>% 
    select(file_name, speaker_name, company_id, first_name, last_name)

# Only 69/152 remaining company_ids have matches in mgt_link using company_id
no_match %>% select(company_id) %>% distinct() %>% # 152
    inner_join(mgt_link %>% select(company_id) %>% distinct()) %>% 
    count() # 69

no_match %>% 
    inner_join(mgt_link, by = "company_id") %>% count()
    select(file_name, speaker_name, matches("first_name"), matches("last_name"), everything()) %>% 
    arrange(file_name, speaker_name, company_id) %>% 
    View()

