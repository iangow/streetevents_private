#!/usr/bin/env Rscript
library(xml2)
library(stringr)
library(dplyr)
library(parallel)

se_path <- file.path(Sys.getenv("EDGAR_DIR"), "streetevents_project")

unescape_xml <- function(str) {
    xml_text(read_html(paste0("<x>", str, "</x>")))
}

extract_speaker_data <- function(file_path) {
    full_path <- file.path(se_path, file_path)
    if (!file.exists(full_path)) return(NULL)

    print(file_path)
    file_xml <- read_xml(file.path(se_path, file_path), options = "NOENT")
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
        tibble(file_path, speaker_name, employer, role, speaker_number)
    }

    pres <- sections[grepl("^(Presentation|Transcript)\n", sections)]

    if (length(pres) > 0) {
        pres_df <-
            analyze_text_wrap(pres) %>%
            mutate(context = "pres") %>%
            select(file_path, speaker_name, employer, role,
                   speaker_number, speaker_text, context, section)
    } else {
        return(NULL)
    }

    qa <- sections[grepl("^(Questions and Answers|q and a)", sections)]

    if (length(qa) > 0) {
        qa_df <-
            analyze_text_wrap(qa) %>%
            mutate(context = "qa") %>%
            select(file_path, speaker_name, employer, role,
                   speaker_number, speaker_text, context, section)
        return(bind_rows(pres_df, qa_df))
    } else {
        return(pres_df)
    }
}

# Get a list of files that need to be processed ----

library(RPostgreSQL)
pg <- dbConnect(PostgreSQL())

if (!dbExistsTable(pg, c("streetevents", "speaker_data_alt"))) {
    dbGetQuery(pg, "
        CREATE TABLE streetevents.speaker_data_alt
           (
           file_path text,
           speaker_name text,
           employer text,
           role text,
           speaker_number integer,
           speaker_text text,
           context text,
            section integer,
        PRIMARY KEY (file_path, speaker_number, context, section));

       CREATE INDEX ON streetevents.speaker_data_alt (file_path);")
}

if (!dbExistsTable(pg, c("streetevents", "speaker_data_dupes"))) {
    dbGetQuery(pg, "
        CREATE TABLE streetevents.speaker_data_dupes (file_path text);")
}
rs <- dbDisconnect(pg)

process_calls <- function(num_calls = 1000, file_list = NULL) {
    pg <- src_postgres()

    calls <- tbl(pg, sql("SELECT * FROM streetevents.call_files"))
    speaker_data_alt <- tbl(pg, sql("SELECT * FROM streetevents.speaker_data_alt"))
    speaker_data_dupes <- tbl(pg, sql("SELECT * FROM streetevents.speaker_data_dupes"))

    if (is.null(file_list)) {

        file_list <-
            calls %>%
            arrange(random()) %>%
            anti_join(speaker_data_alt, by = "file_path") %>%
            anti_join(speaker_data_dupes, by = "file_path") %>%
            collect(n=num_calls)
    }

    speaker_data <-
        bind_rows(lapply(file_list$file_path, extract_speaker_data)) %>%
        filter(speaker_text != "")
    print(sprintf("Speaker data has %d rows", nrow(speaker_data)))

    if (nrow(speaker_data) == 0) {
        dupes <- file_list
    } else {
        dupes <-
            speaker_data %>%
            group_by(file_path, speaker_number, context, section) %>%
            filter(n()>1) %>%
            ungroup() %>%
            union_all(
                speaker_data %>%
                    filter(is.na(speaker_number) | is.na(context) | is.na(section)))

        speaker_data <-
            speaker_data %>%
            anti_join(dupes, by="file_path")
    }

    print("Writing data to Postgres")

    dbWriteTable(pg$con, c("streetevents", "speaker_data_alt"),
                 speaker_data, row.names=FALSE, append=TRUE)

    print("Writing dupe data to Postgres")
    file_path <- dupes %>% select(file_path) %>% distinct()
    dbWriteTable(pg$con, c("streetevents", "speaker_data_dupes"), file_path,
                 row.names=FALSE, append=TRUE)
}

for (i in 1:1) {
    system.time(process_calls(num_calls = 100))
}
library(tibble)

file_list = tibble(file_path = "StreetEvents_historical_backfill_through_May2013/dir_1/1360941_T.xml")
process_calls(file_list = file_list)

