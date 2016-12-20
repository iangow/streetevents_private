# Read mapping data
library(readr)
se_mapping <- read_csv("db_matches/data/MappingFile_201606.csv",
                       locale=locale(encoding="macintosh"))

# Send to PostgreSQL
library(RPostgreSQL)
pg <- dbConnect(PostgreSQL())

dbWriteTable(pg, c("streetevents", "mapping"), se_mapping,
             overwrite=TRUE, row.names=FALSE)
rs <- dbGetQuery(pg, "ALTER TABLE streetevents.mapping
    OWNER TO streetevents_access")

dbDisconnect(pg)
