#!/usr/bin/env python3
import pandas as pd
from sqlalchemy import create_engine
from multiprocessing import Pool
from process_file_linguistic_features import processFile, conn_string, \
        input_table, input_schema, output_table, output_schema


engine = create_engine(conn_string)


def getFileNames(output_table, output_schema, num_files=None):
    import pandas as pd

    # Using LIMIT is much faster than getting all files and ditching
    # unneeded ones.
    if num_files==None:
        limit_clause = ""
    else:
        limit_clause = "LIMIT %s" % (num_files)

    # Get a list of unprocessed files. Query differs according to whether
    # any files have been processed (i.e., output_table exists)
    conn = engine.connect()
    table_exists = engine.dialect.has_table(conn, output_table, schema=output_schema)
    conn.close()

    if table_exists:
        sql = """
            WITH latest_call AS (
                SELECT file_name, last_update
                FROM streetevents.calls
                WHERE call_type=1)
            SELECT DISTINCT file_name, last_update
            FROM latest_call
            EXCEPT
            SELECT file_name, last_update
            FROM %s.%s
            %s
        """ % (output_schema, output_table, limit_clause)
        files = pd.read_sql(sql, engine)
    else:
        sql = """CREATE TABLE %s.%s
                (
                    file_name text,
                    last_update timestamp without time zone,
                    speaker_name text,
                    employer text,
                    role text,
                    speaker_number integer,
                    context text,
                    language text,
                    positive int,
                    negative int,
                    uncertainty int,
                    litigious int,
                    modal_strong int,
                    modal_weak int,
                    num_count int)
            """ % (output_schema, output_table)
        engine.execute(sql)

        sql = """
            SELECT DISTINCT file_name, last_update
            FROM streetevents.calls
            WHERE call_type=1
            %s
        """ % (limit_clause)
        files = pd.read_sql(sql, engine)

    return files

# Get a list of files to work on.
num_threads = 8
files = getFileNames(output_table, output_schema, 100)
files = files['file_name']
#files.

# Set up multiprocessing environment
pool = Pool(num_threads)

# Do the work!
pool.map(processFile, files)


