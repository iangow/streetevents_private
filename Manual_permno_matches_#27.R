library(dplyr, warn.conflicts = FALSE)
library(RPostgreSQL)
pg <- dbConnect(PostgreSQL())

# Env setting ----
crsp_link <- tbl(pg, sql("SELECT * FROM se_stage.crsp_link")) # file_name, permno
calls <- tbl(pg, sql("SELECT * FROM se_stage.calls"))
calls_hbs <- tbl(pg, sql("SELECT * FROM se_stage.calls_hbs"))
stocknames <- tbl(pg, sql("SELECT * FROM crsp.stocknames")) # permno, permco
speaker_data <- tbl(pg, sql("SELECT * FROM streetevents.speaker_data"))

permcos <-   # permno, permco
    stocknames %>%
    select(permno, permco) %>%
    distinct() %>%
    compute()

all_calls <-
    calls %>% 
    full_join(calls_hbs) %>%
    compute()

mult_permcos <-  # file_name, permco
    crsp_link %>%
    filter(!is.na(permno)) %>%
    inner_join(permcos) %>%
    select(file_name, permco) %>%
    distinct() %>%
    group_by(file_name) %>%
    filter(n() > 1) %>%
    ungroup() %>%
    arrange(permco) %>%
    compute()

mult_permcos %>% summarize(n_distinct(permco)) %>% pull()

details <-
    mult_permcos %>% 
    inner_join(all_calls) %>%
    select(file_name, permco, company_name, start_date, call_desc, event_type, event_title) %>%
    compute()

mult_tickers <-
    details %>% 
    select(file_name) %>% 
    inner_join(all_calls) %>%
    select(file_name, company_ticker) %>%
    distinct() %>% 
    group_by(file_name) %>%
    filter(n()>1) %>%
    summarize(tickers = array_agg(company_ticker)) %>%
    compute()

remaining_cases <-
    details %>% 
    anti_join(mult_tickers) %>%    
    filter(start_date < '2017-01-01') %>%
    select(permco) %>% 
    distinct() %>%
    inner_join(details) %>%
    distinct() %>%
    arrange(file_name)


# Manual check----
remaining_cases
my_file_name = "4683650_T"  # <-- update here
# Check every item in detail for multiple `permco`s
remaining_cases %>% filter(file_name == my_file_name)
# If it does, find the ***correct coname*** at the time of `start_date`
speaker_data %>% filter(file_name == my_file_name, context=="pres")  # might don't have value

# Find the ***correct `permno`*** using `coname`  / `start_date`
# Vector here is the `permco`s in `details` above
lst_permco <- c(10429L, 53887L)  # <-- update here
stocknames %>% filter(permco %in% lst_permco)   # stocknames %>% filter(permco == 55056L)

# First make sure all `file_name` with this `permno` belong to this company
real_permno <- 79477   # <-- update here
fixes <-
    mult_permcos %>% 
    inner_join(permcos) %>% 
    filter(permno == real_permno) %>%
    inner_join(all_calls) %>%
    compute()

fixes %>% 
    select(company_name) %>%   # If multiple names, might belong to the same compnay, check it
    distinct()

# Write affected `file_name` and `permno` to a csv
fixes %>% 
    select(file_name, permno, company_name) %>% 
    distinct() %>% 
    collect() %>% 
    write_csv("temp.csv")

# Shrink remaining dataset
remaining_cases <- 
    remaining_cases %>% # filter(permco != 55056L)
    filter(!(permco %in% lst_permco)) 


