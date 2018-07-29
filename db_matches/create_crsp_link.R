# Create_crsp_link.R
library(dplyr, warn.conflicts = FALSE)
library(RPostgreSQL)
library(googlesheets)
library(readr)

pg <- dbConnect(PostgreSQL())

dbGetQuery(pg, read_file('crsp_link.sql'))

db_comment <- paste0("CREATED USING create_crsp_link.R ON ", Sys.time())
dbGetQuery(pg, sprintf("COMMENT ON TABLE streetevents.crsp_link IS '%s';", db_comment))
