SET work_mem='32GB';

INSERT INTO streetevents.calls
SELECT *
FROM streetevents.calls_hbs
WHERE file_name NOT IN (SELECT file_name FROM streetevents.calls);
