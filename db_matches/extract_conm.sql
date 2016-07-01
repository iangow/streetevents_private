CREATE OR REPLACE FUNCTION extract_conm(call_desc text)
RETURNS text AS $$
    DECLARE
        regex text;
        matches text[];
    BEGIN
        -- Get text between e.g., "2004" or "2005/06" and "Results" or "Earnings"
        regex := '(?:[0-9]{4}|[0-9]{4}/[0-9]{2})(.*)(?=Results|Earnings)';
        matches := regexp_matches(call_desc, regex);
        RETURN matches[1];
    END;
$$ LANGUAGE plpgsql;
