from sqlalchemy import create_engine
import os
conn_string = 'postgresql://' + os.environ['PGHOST'] + '/' + os.environ['PGDATABASE']
engine = create_engine(conn_string)

the_table = "syllable_data"
the_schema = "streetevents"

from syllable_count import syllable_data
from pandas import to_datetime

def processFile(file_name):

    # Get syllable data for the file_name
    engine.execute("SET time zone 'UTC'")
    df = getQuestionData(file_name)
    df['syllable_data'] = df['speaker_text'].map(syllable_data)
    df = df.drop(['speaker_text'], 1)

    # Submit dataframe to database
    conn = engine.connect()
    df['last_update'] =  df['last_update'].apply(lambda d: to_datetime(str(d)))
    conn.execute("SET time zone 'UTC'")
    df.to_sql(the_table, conn, schema=the_schema, if_exists='append',
              index=False)
    conn.close()

def getQuestionData(file_name):
    from pandas.io.sql import read_sql

    conn = engine.connect()
    table_exists = engine.dialect.has_table(conn, the_table, schema=the_schema)
    conn.close()

    # It may be better to explicitly create the table elsewhere.
    # Checking like this might be slower.
    if table_exists:
        sql = "DELETE FROM %s.%s WHERE file_name='%s'" % \
            (the_schema, the_table, file_name)
        engine.execute(sql)

    sql = """
       	SELECT file_name, last_update, context, section, speaker_number, speaker_text
        FROM streetevents.speaker_data
        WHERE file_name='%s'
        """ % (file_name)

    df = read_sql(sql, engine)
    df['last_update'] =  df['last_update'].apply(lambda d: to_datetime(str(d)))
    return df

