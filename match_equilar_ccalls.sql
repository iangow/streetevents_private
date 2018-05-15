SET work_mem='15GB';

DROP TABLE IF EXISTS streetevents.executive_link;

-- Match Equilar with PERMNOs (Equilar's looseness with CUSIPs is one
-- potential source of non-matches).
CREATE TABLE streetevents.executive_link AS
WITH equilar_permno AS (
    SELECT DISTINCT director.equilar_id(company_id) AS equilar_id,
        a.cusip, permno::int, fy_end
    FROM board.co_fin AS a
    LEFT JOIN crsp.stocknames AS b
    ON substr(a.cusip, 1, 8)=b.cusip),

-- We draw from calls that we've matched to PERMNOs, AND for which we have
-- matching firm-years on Equilar. One issue that I'm sidestepping here is
-- the absence of firm-years on Equilar in the relevant period.
matched_calls AS (
    SELECT DISTINCT file_name, call_date, equilar_id, fy_end
    FROM streetevents.calls
    INNER JOIN streetevents.crsp_link
    USING (file_name)
    INNER JOIN equilar_permno
    USING (permno)
    WHERE 
        call_date BETWEEN fy_end - interval '12 months'
            AND fy_end + interval '12 months'
        AND equilar_id IS NOT NULL
    ORDER BY file_name),

-- Get executive data from Equilar
-- Get executive data from Equilar
executive AS (
    SELECT executive.executive_id(executive_id) AS equilar_executive_id,
        executive.equilar_id(executive_id) AS equilar_id, executive,
        fy_end
    FROM executive.executive
    UNION
    SELECT executive.executive_id(executive_id) AS equilar_executive_id,
        executive.equilar_id(executive_id) AS equilar_id, executive,
        fy_end
    FROM executive.executive_nd),

executives AS (
    SELECT equilar_id, fy_end, a.equilar_executive_id, b.file_name
    FROM executive AS a
    INNER JOIN matched_calls AS b
    USING (equilar_id, fy_end)),

executives_mod AS (
    SELECT file_name, equilar_id, equilar_executive_id, max(fy_end) AS fy_end
    FROM executives
    GROUP BY file_name, equilar_id, equilar_executive_id),

executive_plus AS (
    SELECT a.*, director.parse_name(executive) AS name, b.file_name
    FROM executive AS a
    INNER JOIN executives_mod AS b
    USING (equilar_id, equilar_executive_id, fy_end)),

-- Get the CEOs on StreetEvents
speakers AS (
    SELECT DISTINCT file_name, call_date, speaker_name, fy_end,
        role, employer, equilar_id,
        streetevents.parse_name(speaker_name) AS name
    FROM streetevents.speaker_data
    INNER JOIN matched_calls
    USING (file_name)
    WHERE speaker_name !~* '^(Unident|Operator)'
        AND role != 'Analyst' AND role ~ 'C\.?E\.?O|Chief Executive|Chair'
        AND (file_name, speaker_name) NOT IN
            (SELECT file_name, speaker_name
             FROM streetevents.executive_manual_matches)),

-- Try to match speakers with Equilar executives
-- First, use a manual match, then full-name matches, then last-name matching.
-- False matches often will need to be corrected by making manual non-matches.
manual_match AS (
    SELECT file_name, speaker_name, executive,
        equilar_id::integer, equilar_executive_id
    FROM streetevents.executive_manual_matches),

match_full_name AS (
    SELECT a.file_name, a.speaker_name, b.executive,
        a.equilar_id, a.fy_end,
        b.equilar_executive_id,
        a.name, (a.name).last_name AS last_name
    FROM speakers AS a
    LEFT JOIN executive_plus AS b
    ON a.file_name=b.file_name AND a.fy_end=b.fy_end
        AND (b.name).first_name=upper((a.name).first_name)
        AND (b.name).last_name=upper((a.name).last_name)),

match_last_name AS (
    SELECT a.file_name, a.speaker_name, b.executive,
        a.equilar_id, a.fy_end, b.equilar_executive_id,
        a.name, (a.name).last_name AS last_name
    FROM match_full_name AS a
    LEFT JOIN executive_plus AS b
    ON a.file_name=b.file_name AND a.fy_end=b.fy_end
        AND (b.name).last_name=upper((a.name).last_name)
    WHERE a.executive IS NULL),

non_matches AS (
    SELECT file_name, speaker_name, equilar_id, fy_end, name
    FROM match_last_name
    WHERE (file_name, speaker_name) NOT IN (
        SELECT file_name, speaker_name
        FROM match_last_name
        WHERE executive IS NOT NULL
        UNION
        SELECT file_name, speaker_name
        FROM match_full_name
        WHERE executive IS NOT NULL)),

non_match_fy AS (
    SELECT file_name, speaker_name, max(fy_end) AS fy_end
    FROM non_matches
    GROUP BY file_name, speaker_name),

non_match_final AS (
    SELECT a.file_name, a.speaker_name, NULL::text AS executive,
        a.equilar_id, b.fy_end, NULL::integer AS equilar_executive_id,
        a.name, (a.name).last_name AS last_name
    FROM non_matches AS a
    INNER JOIN non_match_fy AS b
    USING (file_name, speaker_name)),

all_matches AS (
    SELECT  file_name, speaker_name, executive,
        equilar_id, NULL::date AS fy_end, equilar_executive_id,
        'manual' AS match_type
    FROM manual_match
    UNION
    SELECT file_name, speaker_name, executive,
        equilar_id, fy_end,  equilar_executive_id,
        'full name' AS match_type
    FROM match_full_name
    WHERE executive IS NOT NULL
    UNION
    SELECT file_name, speaker_name, executive,
        equilar_id, fy_end, equilar_executive_id,
        'last name' AS match_type
    FROM match_last_name
    WHERE executive IS NOT NULL
    UNION
    SELECT file_name, speaker_name, executive,
        equilar_id, fy_end, equilar_executive_id,
        'no match' AS match_type
    FROM non_match_final),

ambiguous_matches AS (
    SELECT file_name, speaker_name, count(*) > 1 AS ambiguous
    FROM all_matches
    GROUP BY file_name, speaker_name)

SELECT a.*, b.ambiguous, c.call_type
FROM ambiguous_matches AS b
INNER JOIN all_matches AS a
USING (file_name, speaker_name)
INNER JOIN streetevents.calls AS c
USING (file_name);

ALTER TABLE streetevents.executive_link OWNER TO personality_access;

CREATE INDEX ON streetevents.executive_link (file_name);
