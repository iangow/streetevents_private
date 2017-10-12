Sys.setenv(PGHOST = "aaz.chicagobooth.edu", PGDATABASE = "postgres")

library(dplyr, warn.conflicts = FALSE)
library(RPostgreSQL)
library(tidyr)
#> Loading required package: DBI
pg <- dbConnect(PostgreSQL())
crsp_link <- tbl(pg, sql("SELECT * FROM se_stage.crsp_link"))
calls_hbs <- tbl(pg, sql("SELECT * FROM se_stage.calls_hbs"))
calls <- tbl(pg, sql("SELECT * FROM se_stage.calls"))
calls %>% select(file_name, start_date)
#> # Source:   lazy query [?? x 2]
#> # Database: postgres 9.4.12 [igow@aaz.chicagobooth.edu:5432/postgres]
#>    file_name          start_date
#>        <chr>              <dttm>
#>  1 8056927_T 2017-02-23 12:00:00
#>  2 8056951_T 2017-02-23 22:00:00
#>  3 8057249_T 2017-02-23 20:30:00
#>  4  805727_T 2003-11-12 15:30:00
#>  5 8057303_T 2017-02-22 14:30:00
#>  6  805731_T 2003-11-10 19:45:00
#>  7 8057355_T 2017-02-23 20:30:00
#>  8  805735_T 2003-11-11 13:30:00
#>  9  805737_T 2003-11-14 14:00:00
#> 10  805738_T 2003-11-25 21:00:00
#> # ... with more rows
all_calls <- calls %>% select(file_name, start_date, event_title) %>% 
    union_all(calls_hbs %>% select(file_name, start_date, event_title))
stocknames <- tbl(pg, sql("SELECT * FROM crsp.stocknames"))
speaker_data <- tbl(pg, sql("SELECT * FROM streetevents.speaker_data"))


permno_matches <-
    all_calls %>% 
    inner_join(crsp_link) %>%
    select(file_name, start_date, permno) %>%
    filter(!is.na(permno)) %>%
    inner_join(stocknames %>% select(permno, permco) %>% distinct()) %>%
    compute()
#> Joining, by = "file_name"
#> Joining, by = "permno"



# Here are cases where there are multiple valid PERMNOs
# Have we chosen the right one?
alt_permnos %>% 
    select(permco) %>% 
    distinct() %>% 
    count()

# Rm duplicates
alt_permnos <-
    permno_matches %>%
    inner_join(stocknames, by="permco", suffix=c("_x", "_y")) %>%
    filter(permno_x != permno_y) %>%
    filter(between(start_date, namedt, nameenddt)) %>%
    select(file_name, start_date, permco, permno_x, permno_y) %>%
    compute(name = 'mytest', temporary = FALSE)

tbl(pg, sql("select file_name, start_date, permco, unnest(try) as permno
            from(
                select file_name, start_date, permco, ARRAY[permno_x::text, permno_y::text] as try
                from public.mytest) t")) %>% 
    distinct() %>% 
    arrange(permco, start_date) %>% 
    compute(name = 'mytest2', temporary = FALSE)

alt_permnos <- 
    tbl(pg, sql("select file_name, start_date, permco, array_agg(permno) as permno
        from public.mytest2
        group by file_name, start_date, permco
        order by permco, start_date")) %>% 
    left_join(all_calls %>% select(file_name, event_title), by = c("file_name")) %>% 
    distinct()
# cnt = 3651

# stocknames PK: (permco, permno, namedt)
# perco - permno (one to many)
stocknames <- 
    tbl(pg, sql("SELECT * FROM crsp.stocknames")) %>% 
    select(permco, permno, namedt, nameenddt, comnam) %>% 
    arrange(permco, permno, namedt) 

test <- 
    alt_permnos %>% 
    left_join(stocknames, by = c("permco")) %>% 
    distinct() %>% 
    filter(start_date >= namedt, start_date <= nameenddt) %>% 
    group_by(file_name) %>% 
    mutate(cnt = n()) %>% 
    ungroup() %>% 
    filter(cnt > 1) %>% 
    select(file_name, start_date, permco, permno.x, permno.y, event_title, comnam, cnt) %>% 
    # select(permco) %>% distinct() %>% count()
