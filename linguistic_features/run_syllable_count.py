#!/usr/bin/env python3
from sqlalchemy import create_engine
from process_file_syllables import processFile, the_table, \
                                    the_schema, conn_string
engine = create_engine(conn_string)

from multiprocessing import Pool

def getFileNames(the_table, the_schema, num_files=None):
    import pandas as pd

    # Using LIMIT is much faster than getting all files and ditching
    # unneeded ones.
    if num_files==None:
        limit_clause = ""
    else:
        limit_clause = "LIMIT %s" % (num_files)

    # Get a list of unprocessed files. Query differs according to whether
    # any files have been processed (i.e., the_table exists)
    conn = engine.connect()
    table_exists = engine.dialect.has_table(conn, the_table, schema=the_schema)
    conn.close()

    engine.execute("SET TIME ZONE 'UTC'")

    if table_exists:
        sql = """
            WITH latest_call AS (
                SELECT file_name, last_update
                FROM streetevents.calls
                WHERE event_type=1
                EXCEPT
                SELECT file_name, last_update
                FROM streetevents.speaker_data_dupes)
            SELECT file_name, last_update
            FROM latest_call
            EXCEPT
            SELECT file_name, last_update
            FROM %s.%s
            %s
        """ % (the_schema, the_table, limit_clause)
        files = pd.read_sql(sql, engine)
    else:
        sql = """CREATE TABLE %s.%s
                (
                    file_name text,
                    last_update timestamp with time zone,
                    context text,
                    section integer,
                    speaker_number integer,
                    syllable_data jsonb)
            """ % (the_schema, the_table)
        engine.execute(sql)

        sql = """CREATE INDEX ON %s.%s
            (file_name, last_update, section, context, speaker_number, section);
            """ % (the_schema, the_table)
        engine.execute(sql)

        sql = "ALTER TABLE %s.%s OWNER TO %s" % \
            (the_schema, the_table, the_schema)
        engine.execute(sql)

        sql = "GRANT SELECT ON TABLE %s.%s TO %s_access" % \
                (the_schema, the_table, the_schema)
        engine.execute(sql)

        sql = """
            SELECT file_name, last_update as last_update
            FROM streetevents.qa_pairs
            %s
        """ % (limit_clause)
        files = pd.read_sql(sql, engine)

    return files

if __name__ == "__main__":
    # Get a list of files to work on.
    num_threads = 24
    files = getFileNames(the_table, the_schema)
    files = files['file_name']
    print(files[:10])

    # Set up multiprocessing environment
    pool = Pool(num_threads)

    # Do the work!
    pool.map(processFile, files)
