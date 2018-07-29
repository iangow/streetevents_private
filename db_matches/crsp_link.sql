/*******************************
OBJECTIVE: Match streetevents.calls with PERMNOs from crsp.stocknames
*******************************/
DROP VIEW IF EXISTS streetevents.company_link;

DROP TABLE IF EXISTS streetevents.crsp_link;

CREATE TABLE streetevents.crsp_link AS
WITH

calls_combined AS (
    SELECT file_name, last_update,
        COALESCE(b.company_name, a.company_name) AS company_name,
        COALESCE(a.start_date, b.start_date) AS start_date,
        COALESCE(b.company_ticker, a.company_ticker) AS company_ticker
    FROM streetevents.calls AS a
    FULL OUTER JOIN streetevents.calls_hbs AS b
    USING (file_name, last_update)),

calls_combined_filtered AS (
    SELECT *
    FROM calls_combined
    WHERE start_date <= (SELECT max(end_date) AS max_date FROM crsp.stocknames)),

earliest_calls AS (
    SELECT file_name, min(last_update) AS last_update
    FROM calls_combined_filtered
    WHERE (company_ticker ~ '\.A$' OR company_ticker !~ '\.[A-Z]+$')
        AND company_ticker IS NOT NULL
    GROUP BY file_name),

earliest_calls_merged AS (
    SELECT *
    FROM calls_combined_filtered
    INNER JOIN earliest_calls
    USING (file_name, last_update)),

calls AS (
    SELECT streetevents.clean_tickers(company_ticker) AS ticker, file_name,
        company_name AS co_name, start_date::date AS call_date
    FROM earliest_calls_merged),

manual_permno_matches AS (
    SELECT file_name, co_name, permno,
        '0. Manual matches'::text AS match_type_desc
    FROM streetevents.manual_permno_matches),

match0 AS (
    SELECT DISTINCT a.file_name, a.ticker, COALESCE(b.co_name, a.co_name) AS co_name,
        a.call_date, b.permno, b.match_type_desc
    FROM calls AS a
    LEFT JOIN manual_permno_matches AS b
    ON a.file_name=b.file_name),

match1 AS (
    SELECT DISTINCT file_name, a.ticker, co_name, call_date, b.permno,
        '1. Match on ticker & exact Soundex between ticker dates'::text AS match_type_desc
    FROM match0 AS a
    LEFT JOIN crsp.stocknames AS b
    ON a.ticker=b.ticker
        AND (a.call_date BETWEEN b.namedt AND b.nameenddt)
        -- The difference function converts two strings to their Soundex codes and
        -- then reports the number of matching code positions. Since Soundex codes
        -- have four characters, four is an exact match.
        -- Note: lower() has no impact.
        AND difference(a.co_name,b.comnam) = 4
    WHERE a.permno IS NULL AND a.match_type_desc IS NULL),

/* Roll back and forward permno for companies that changed tickers at some point. Example:
    permno   namedt         nameenddt       ticker    st_date         end_date
    91029    "2005-12-16"   "2009-05-06"    "SPSN"    "2005-12-30"    "2009-05-29"
    93387    "2010-05-18"   "2010-06-22"    "CODE"    "2010-05-28"    "2013-06-28"
    93387    "2010-06-23"   "2013-06-28"    "CODE"    "2010-05-28"    "2013-06-28"

    In StreetEvents, SPANSION ticker is only CODE from 2006-2013
*/
roll_match1 AS (
    SELECT DISTINCT co_name, ticker, permno
    FROM match1
    WHERE permno IS NOT NULL),

match2 AS (
    SELECT a.file_name, a.ticker, a.co_name, a.call_date, b.permno,
        '2. Roll matches back & forward in StreetEvents'::text AS match_type_desc
    FROM match1 AS a
    LEFT JOIN roll_match1 AS b
    USING (ticker, co_name)
    WHERE a.permno IS NULL),

match3 AS (
    SELECT DISTINCT file_name, streetevents.remove_trailing_q(a.ticker) AS ticker,
        co_name, call_date, b.permno,
        '3. #1 with trailing Q removed'::text AS match_type_desc
    FROM match2 AS a
    LEFT JOIN crsp.stocknames AS b
    ON streetevents.remove_trailing_q(a.ticker)=b.ticker
        AND (a.call_date BETWEEN b.namedt AND b.nameenddt)
        AND difference(a.co_name, b.comnam) = 4
    WHERE a.permno IS NULL),

roll_match3 AS (
    SELECT DISTINCT co_name, ticker, permno
    FROM match3
    WHERE permno IS NOT NULL),

match4 AS (
    SELECT a.file_name, a.ticker, a.co_name, a.call_date, b.permno,
        '4. Roll matches back & forward on #3'::text AS match_type_desc
    FROM match3 AS a
    LEFT JOIN roll_match3 as b
    USING (ticker, co_name)
    WHERE a.permno IS NULL),

match5 AS (
    SELECT DISTINCT file_name, a.ticker, co_name, call_date, b.permno,
        '5. Match on ticker and exact name Soundex between company dates'::text AS match_type_desc
    FROM match4 AS a
    LEFT JOIN crsp.stocknames AS b
    ON a.ticker=b.ticker
        AND (a.call_date BETWEEN b.st_date AND b.end_date)
        AND DIFFERENCE(a.co_name, b.comnam) = 4
    WHERE a.permno IS NULL),

roll_match5 AS (
    SELECT DISTINCT co_name, ticker, permno
    FROM match5
    WHERE permno IS NOT NULL),

match6 AS (
    SELECT DISTINCT a.file_name, a.ticker, a.co_name, a.call_date, b.permno,
        '6. Roll matches back and forward on #5'::text AS match_type_desc
    FROM match5 AS a
    LEFT JOIN roll_match5 as b
    USING (ticker, co_name)
    WHERE a.permno IS NULL),

match7 AS (
    SELECT DISTINCT file_name, a.ticker, co_name, call_date, b.permno,
        '7. Match ticker & fuzzy name Soundex between company dates'::text AS match_type_desc
    FROM match6 AS a
    LEFT JOIN crsp.stocknames AS b
    ON a.ticker=b.ticker
        AND (a.call_date BETWEEN b.st_date AND b.end_date)
        AND difference(a.co_name, b.comnam) >= 2
    WHERE a.permno IS NULL),

roll_match7 AS (
    SELECT DISTINCT co_name, ticker, permno
    FROM match7
    WHERE permno IS NOT NULL),

match8 AS (
    SELECT a.file_name, a.ticker, a.co_name, a.call_date, b.permno,
        '8. Roll matches back & forward on #7'::text AS match_type_desc
    FROM match7 AS a
    LEFT JOIN roll_match7 as b
    USING (ticker, co_name)
    WHERE a.permno IS NULL),

match9 AS (
    SELECT DISTINCT file_name, a.ticker, co_name, call_date, b.permno,
        '9. Match ticker w/diff of 2 & exact name between ticker dates'::text AS match_type_desc
    FROM match8 AS a
    LEFT JOIN crsp.stocknames AS b
        ON levenshtein(a.ticker, b.ticker) <= 2
        AND (a.call_date BETWEEN b.namedt AND b.nameenddt)
        AND lower(co_name) = lower(comnam)
    WHERE a.permno IS NULL),

roll_match9 AS (
    SELECT DISTINCT co_name, ticker, permno
    FROM match9
    WHERE permno IS NOT NULL),

match10 AS (
    SELECT a.file_name, a.ticker, a.co_name, a.call_date, b.permno,
        CASE WHEN b.permno IS NOT NULL
            THEN '10. Roll matches back & forward on #9'
            ELSE '11. No match'
        END AS match_type_desc
    FROM match9 AS a
    LEFT JOIN roll_match9 as b
    USING (ticker, co_name)
    WHERE a.permno IS NULL),

all_matches AS (
    SELECT file_name, ticker, co_name, call_date, permno, match_type_desc
    FROM match0
    WHERE permno IS NOT NULL
    UNION ALL
    SELECT file_name, ticker, co_name, call_date, permno, match_type_desc
    FROM match1
    WHERE permno IS NOT NULL
    UNION ALL
    SELECT file_name, ticker, co_name, call_date, permno, match_type_desc
    FROM match2
    WHERE permno IS NOT NULL
    UNION ALL
    SELECT file_name, ticker, co_name, call_date, permno, match_type_desc
    FROM match3
    WHERE permno IS NOT NULL
    UNION ALL
    SELECT file_name, ticker, co_name, call_date, permno, match_type_desc
    FROM match4
    WHERE permno IS NOT NULL
    UNION ALL
    SELECT file_name, ticker, co_name, call_date, permno, match_type_desc
    FROM match5
    WHERE permno IS NOT NULL
    UNION ALL
    SELECT file_name, ticker, co_name, call_date, permno, match_type_desc
    FROM match6
    WHERE permno IS NOT NULL
    UNION ALL
    SELECT file_name, ticker, co_name, call_date, permno, match_type_desc
    FROM match7
    WHERE permno IS NOT NULL
    UNION ALL
    SELECT file_name, ticker, co_name, call_date, permno, match_type_desc
    FROM match8
    WHERE permno IS NOT NULL
    UNION ALL
    SELECT file_name, ticker, co_name, call_date, permno, match_type_desc
    FROM match9
    WHERE permno IS NOT NULL
    UNION ALL
    SELECT file_name, ticker, co_name, call_date, permno, match_type_desc
    FROM match10)

SELECT file_name, permno,
    regexp_replace(match_type_desc, '^([0-9]+).*', '\1')::int AS match_type,
    match_type_desc
FROM all_matches
WHERE (file_name, permno) NOT IN (
    SELECT DISTINCT file_name, permno
    FROM streetevents.bad_matches
)
ORDER BY file_name;

ALTER TABLE streetevents.crsp_link OWNER TO streetevents;
GRANT SELECT ON streetevents.crsp_link TO streetevents_access;

CREATE INDEX ON streetevents.crsp_link (file_name);

CREATE VIEW streetevents.company_link AS SELECT * FROM streetevents.crsp_link;
