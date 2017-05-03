#!/usr/bin/env Rscript
library(xml2)
library(stringr)
library(dplyr)
library(parallel)

se_path <- file.path(Sys.getenv("EDGAR_DIR"), "streetevents_project")

extract_speaker_data <- function(file_path) {
    full_path <- file.path(se_path, file_path)
    # print(full_path)
    if (!file.exists(full_path)) return(NULL)
    file_xml <- read_xml(file.path(se_path, file_path))
    file_list <- as_list(file_xml)
    print(file_path)
    lines <- xml_text(xml_child(file_xml, search = "EventStory/Body"))

    lines <- gsub("\\r\\n", "\n", lines, perl = TRUE)

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

    clean_speaker <- function(speaker) {
        speaker <- gsub("\\n", " ", speaker)
        speaker <- gsub("\\s{2,}", " ", speaker)
        speaker <- str_trim(speaker)
        speaker <- str_replace_all(speaker, "\\t+", "")
        return(speaker)
    }

    extract_speaker <- function(speaker) {
        temp <- str_match(speaker, "^(.*)\\s+\\[(\\d+)\\]")
        speaker_number <- temp[, 3]
        full_name <- temp[ ,2]

        temp <- str_match(full_name, "^([^,]*),\\s*(.*)\\s+-\\s+(.*)$")
        speaker_name = if_else(is.na(temp[, 2]), full_name, str_trim(temp[, 2]))
        employer <- str_trim(coalesce(temp[, 3], ""))
        role <- str_trim(coalesce(temp[, 4], ""))

        tibble(file_path, speaker_name, employer, role, speaker_number)
    }

    pres <- sections[grepl("^(Presentation|Transcript)", sections)]

    if (length(pres) > 0) {
        pres_df <-
            analyze_text(pres) %>%
            mutate(context = "pres")
    } else {
        return(NULL)
    }

    qa <- sections[grepl("^(Questions and Answers|q and a)", sections)]

    if (length(qa) > 0) {
        qa_df <-
            analyze_text(qa) %>%
            mutate(context = "qa")
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
           context text,
           speaker_text text);

       CREATE INDEX ON streetevents.speaker_data_alt (file_path);")
}
rs <- dbDisconnect(pg)

process_calls <- function(num_calls = 1000) {
    pg <- src_postgres()

    calls <- tbl(pg, sql("SELECT * FROM streetevents.call_files ORDER BY random()"))
    speaker_data_alt <- tbl(pg, sql("SELECT * FROM streetevents.speaker_data_alt"))

    file_list <- calls %>%
        anti_join(speaker_data_alt, by = "file_path") %>%
        collect(n=num_calls)

    speaker_data <- do.call(bind_rows,
                            mclapply(file_list$file_path, extract_speaker_data,
                                     mc.cores=6))

    dbWriteTable(pg$con, c("streetevents", "speaker_data_alt"), speaker_data,
                 row.names=FALSE, append=TRUE)
}

system.time(process_calls())

pg <- src_postgres()

calls <- tbl(pg, sql("SELECT * FROM streetevents.call_files"))
speaker_data_alt <- tbl(pg, sql("SELECT * FROM streetevents.speaker_data_alt"))
speaker_data_alt %>% select(file_path) %>% distinct() %>% count()
