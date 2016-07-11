CREATE OR REPLACE FUNCTION array_min(an_array integer[])
  RETURNS integer AS
$BODY$
     WITH unnested AS (
        SELECT UNNEST(an_array) AS ints)

    SELECT min(ints)
    FROM unnested
$BODY$ LANGUAGE sql;
