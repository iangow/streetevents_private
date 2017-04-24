from sqlalchemy import create_engine
import os

host = os.getenv('PGHOST', "localhost")
dbname = os.getenv('PGDATABASE', "postgres")

conn_string = 'postgresql://' + host + '/' + dbname
engine = create_engine(conn_string)

from pandas import read_sql

df = read_sql("SELECT * FROM streetevents.lm_tone", engine)

categories = [category for category in df['category']]

import re, json

def flatten(a_list):
    return [item for sublist in a_list for item in sublist]

mod_word_list = {}
for cat in categories:
    word_list = flatten(df.loc[df["category"] == cat, "word_list"])
    mod_word_list[cat] = [word.lower() for word in word_list]

# Pre-compile regular expressions.
regex_list = {}
for key in mod_word_list.keys():
    regex = '\\b(?:' + '|'.join(mod_word_list[key]) + ')\\b'
    regex_list[key] = re.compile(regex)

def get_tone_data(the_text, category):

    # rest of function
    """Function to return number of matches against tone categories in a text"""
    # text = re.sub(u'\u2019', "'", the_text).lower()
    return len(re.findall(regex_list[category], the_text))
