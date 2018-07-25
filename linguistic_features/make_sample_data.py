#!/usr/bin/env python3
from sqlalchemy import create_engine
from pandas import read_sql
import os
import feather

host = os.getenv('PGHOST', "localhost")
dbname = os.getenv('PGDATABASE', "postgres")

conn_string = 'postgresql://' + host + '/' + dbname
engine = create_engine(conn_string)

speaker_data = read_sql("SELECT * FROM streetevents.speaker_data WHERE file_name = '5189334_T'", engine)

feather.write_dataframe(df=speaker_data, dest="sample.feather")
