#!/usr/bin/env Rscript
library(xml2)
library(stringr)
library(dplyr)
library(parallel)

se_path <- file.path(Sys.getenv("EDGAR_DIR"), "uploads")

unescape_xml <- function(str) {
    xml_text(read_html(paste0("<x>", str, "</x>")))
}

extract_call_data <- function(file_path) {
    full_path <- file.path(se_path, file_path)
    if (!file.exists(full_path)) return(NULL)

    file_name <- str_replace(file_path, "\\.xml$", "")
    file_xml <- read_xml(file.path(se_path, file_path), options = "NOENT")
    last_update <- as.POSIXct(xml_attr(file_xml, "lastUpdate"),
                              format="%A, %B %d, %Y at %H:%M:%S%p GMT", tz = "GMT")
    city <- xml_text(xml_child(file_xml, search = "/city"))
    company_name <- xml_text(xml_child(file_xml, search = "/companyName"))
    company_ticker <- xml_text(xml_child(file_xml, search = "/companyTicker"))
    start_date <- as.POSIXct(xml_text(xml_child(file_xml, search = "/startDate")),
                             format="%d-%b-%y %H:%M%p GMT", tz = "GMT")
    company_id <- xml_text(xml_child(file_xml, search = "/companyId"))
    cusip <- xml_text(xml_child(file_xml, search = "/CUSIP"))
    sedol <- xml_text(xml_child(file_xml, search = "/SEDOL"))
    isin <- xml_text(xml_child(file_xml, search = "/ISIN"))
    tibble(file_path, file_name, last_update, company_name,
           company_ticker, start_date, company_id, cusip, sedol, isin)
}

extract_speaker_data <- function(file_path) {

    full_path <- file.path(se_path, file_path)
    if (!file.exists(full_path)) return(NULL)
    file_name <- str_replace(file_path, "\\.xml$", "")

    file_xml <- read_xml(file.path(se_path, file_path), options = "NOENT")
    last_update <- as.POSIXct(xml_attr(file_xml, "lastUpdate"),
                              format="%A, %B %d, %Y at %H:%M:%S%p GMT", tz = "GMT")
    lines <- xml_text(xml_child(file_xml, search = "/EventStory/Body"))
    lines <- gsub("\\r\\n", "\n", lines, perl = TRUE)
    lines <- unescape_xml(lines)

    sections <- str_split(lines, "==={3,}\n")[[1]]

    analyze_text <- function(section_text) {
        values <- str_split(section_text, "\n---{3,}")
        text <- str_trim(values[[1]])
        num_speakers <- (length(text) - 1)/2
        speaker_data <- text[seq(from = 2, length.out = num_speakers, by = 2)]
        speaker_text <- text[seq(from = 3, length.out = num_speakers, by = 2)]
        speaker <- clean_speaker(speaker_data)
        bind_cols(extract_speaker(speaker), tibble(speaker_text))
    }

    analyze_text_wrap <- function(sections) {
        bind_rows(lapply(sections, analyze_text), .id="section")
    }

    clean_speaker <- function(speaker) {
        speaker <- gsub("\\n", " ", speaker)
        speaker <- gsub("\\s{2,}", " ", speaker)
        speaker <- str_trim(speaker)
        speaker <- str_replace_all(speaker, "\\t+", "")
        return(speaker)
    }

    extract_speaker <- function(speaker) {
        temp2 <- str_match(speaker, "^(.*)\\s+\\[(\\d+)\\]")
        if (dim(temp2)[2] >= 3) {
            speaker_number <- temp2[, 3]
            full_name <- temp2[, 2]

            spaces <- "[\\s\\p{WHITE_SPACE}\u3000\ua0]"
            regex <- str_c("^([^,]*),", spaces, "*(.*)", spaces, "+-", spaces,
                           "+(.*)$")
            temp3 <- str_match(full_name, regex)
            if (dim(temp3)[2] >= 4) {
                speaker_name <- if_else(is.na(full_name), full_name, str_trim(temp3[, 2]))
                speaker_name <- str_trim(speaker_name)
                employer <- str_trim(coalesce(temp3[, 3], ""))
                role <- str_trim(coalesce(temp3[, 4], ""))
            } else {
                speaker_name <- NA
                employer <- NA
                role <- NA
            }
        } else {
            speaker_number <- NA
            speaker_name <- NA
            employer <- NA
            role <- NA
        }

        tibble(file_name, last_update, speaker_name, employer, role, speaker_number)
    }

    pres <- sections[grepl("^(Presentation|Transcript)\n", sections)]

    if (length(pres) > 0) {
        pres_df <-
            analyze_text_wrap(pres) %>%
            mutate(context = "pres") %>%
            select(file_name, last_update, speaker_name, employer, role,
                   speaker_number, speaker_text, context, section)
    } else {
        return(NULL)
    }

    qa <- sections[grepl("^(Questions and Answers|q and a)", sections)]

    if (length(qa) > 0) {
        qa_df <-
            analyze_text_wrap(qa) %>%
            mutate(context = "qa") %>%
            select(file_name, last_update, speaker_name, employer, role,
                   speaker_number, speaker_text, context, section)
        return(bind_rows(pres_df, qa_df))
    } else {
        return(pres_df)
    }
}

# Get a list of files that need to be processed ----

library(RPostgreSQL)
pg <- dbConnect(PostgreSQL())

if (!dbExistsTable(pg, c("streetevents", "speaker_data_new"))) {
    dbGetQuery(pg, "
        CREATE TABLE streetevents.speaker_data_new
           (
           file_name text,
           last_update timestamp with time zone,
           speaker_name text,
           employer text,
           role text,
           speaker_number integer,
           speaker_text text,
           context text,
           section integer,
        PRIMARY KEY (file_name, last_update, speaker_number, context, section));

       CREATE INDEX ON streetevents.speaker_data_new (file_name, last_update);")
}

if (!dbExistsTable(pg, c("streetevents", "speaker_data_dupes_new"))) {
    dbGetQuery(pg, "
        CREATE TABLE streetevents.speaker_data_dupes_new (file_name text, last_update timestamp with time zone);")
}

rs <- dbDisconnect(pg)

if (FALSE) {
    library(RPostgreSQL)
    pg <- dbConnect(PostgreSQL())
    call_files <- tbl(pg, sql("SELECT * FROM streetevents.call_files"))
    file_list <-
        call_files %>%
        select(file_path) %>%
        pull()
    library(parallel)
    calls <- bind_rows(mclapply(file_list, extract_call_data, mc.cores = 12))

    rs <- dbGetQuery(pg, "SET TIME ZONE 'GMT'")

    rs <- dbWriteTable(pg, c("streetevents", "calls_new"), calls,
                       overwrite = TRUE, row.names = FALSE)

    rs <- dbGetQuery(pg, "ALTER TABLE streetevents.calls_new OWNER TO streetevents")

    rs <- dbGetQuery(pg, "GRANT SELECT ON TABLE streetevents.calls_new TO streetevents_access")

    rs <- dbDisconnect(pg)
}


process_calls <- function(num_calls = 1000, file_list = NULL) {
    pg <- dbConnect(PostgreSQL())

    call_files <- tbl(pg, sql("SELECT * FROM streetevents.call_files"))
    calls <- tbl(pg, sql("SELECT * FROM streetevents.calls_new"))
    speaker_data <- tbl(pg, sql("SELECT * FROM streetevents.speaker_data_new"))
    speaker_data_dupes <- tbl(pg, sql("SELECT * FROM streetevents.speaker_data_dupes_new"))

    if (is.null(file_list)) {

        file_list <-
            call_files %>%
            inner_join(calls, by = "file_path") %>%
            select(file_path, file_name, last_update) %>%
            distinct() %>%
            arrange(random()) %>%
            anti_join(speaker_data, by = c("file_name", "last_update")) %>%
            anti_join(speaker_data_dupes, by = c("file_name", "last_update")) %>%
            collect(n=num_calls)
    }

    library(parallel)
    speaker_data <-
        bind_rows(mclapply(file_list$file_path, extract_speaker_data, mc.cores=12)) %>%
        filter(speaker_text != "")
    print(sprintf("Speaker data has %d rows", nrow(speaker_data)))

    if (nrow(speaker_data) == 0) {
        dupes <- file_list
    } else {
        dupes <-
            speaker_data %>%
            group_by(file_name, last_update, speaker_number, context, section) %>%
            filter(n() > 1) %>%
            ungroup() %>%
            union_all(
                speaker_data %>%
                    filter(is.na(speaker_number) | is.na(context) | is.na(section)))

        speaker_data <-
            speaker_data %>%
            anti_join(dupes, by=c("file_name", "last_update"))
    }

    print("Writing data to Postgres")
    rs <- dbGetQuery(pg, "SET TIME ZONE 'GMT'")

    dbWriteTable(pg, c("streetevents", "speaker_data_new"),
                 speaker_data, row.names=FALSE, append=TRUE)

    print("Writing dupe data to Postgres")
    file_path <- dupes %>% select(file_name, last_update) %>% distinct()
    dbWriteTable(pg, c("streetevents", "speaker_data_dupes_new"), file_path,
                 row.names=FALSE, append=TRUE)
    rs <- dbDisconnect(pg)
}

for (i in 1:80) {
    tm <- system.time(process_calls(num_calls = 4000))
    print(tm)
}
