CREATE OR REPLACE FUNCTION extract_conm(call_desc text)
RETURNS text AS $$
    SELECT regexp_replace(overlay(regexp_replace(call_desc, 'Earnings Conference Call', '') placing '' from 1 for 8),
	        '^The ', '')
$$ LANGUAGE sql;
