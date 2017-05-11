#!/usr/bin/env python3
# -*- coding: utf-8 -*

import os
from sqlalchemy import create_engine
from tone_functions import categories, get_tone_data
from numerical_intensity import num_count
from fl_sents import prop_fl_sents

conn_string = 'postgresql://' + os.environ['PGHOST'] + '/' + os.environ['PGDATABASE']
engine = create_engine(conn_string)

#file_name = "5189334_T"
#file_name = files[1]

input_schema = "streetevents"
input_table = "speaker_data"
output_schema = "streetevents"
output_table = "linguistic_features"



def processFile(file_name):

    # Get syllable data for the file_name
    speaker_data = getLFData(file_name)
    for cat in categories:
        speaker_data[cat] = speaker_data['speaker_text'].map(lambda x: get_tone_data(x, cat))    
    speaker_data['num_count'] = speaker_data['speaker_text'].map(num_count)

    speaker_data = speaker_data.drop(['speaker_text'], 1)

    # Submit dataframe to database
    conn = engine.connect()
    speaker_data.to_sql(output_table, conn, schema=output_schema, if_exists='append',
              index=False)
    conn.close()

def getLFData(file_name):
    from pandas.io.sql import read_sql
    
    conn = engine.connect()
    table_exists = engine.dialect.has_table(conn, output_table, schema=output_schema)
    conn.close()

    # It may be better to explicitly create the table elsewhere.
    # Checking like this might be slower.
    if table_exists:
        sql = "DELETE FROM %s.%s WHERE file_name='%s'" % \
            (output_schema, output_table, file_name)

        engine.execute(sql)


    sql = """
       	SELECT file_name, last_update, speaker_name, employer, role, speaker_number, context, speaker_text, language
    	FROM %s.%s
	    WHERE file_name='%s'
        """ % (input_schema, input_table, file_name)

    df = read_sql(sql, engine)

    return df
