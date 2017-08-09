import pandas as pd
from sqlalchemy import create_engine
import difflib
from difflib import ndiff, unified_diff
from nltk import sent_tokenize
import re

# Step 1: Find diff rows, write to a tmp file
def clean_text(text):
    # Eliminate markup from speaker text
    text = re.sub(r"]]></Body>", "", text)

    # Convert newlines to spaces
    text = re.sub(r"\n", " ", text)

    # Eliminate multiple spaces (perhaps created by previous step)
    text = re.sub(r"\s{2,}", " ", text)
    return text.strip()

engine = create_engine("postgresql://aaz.chicagobooth.edu/postgres")


df = pd.read_sql_query("SELECT * FROM zjy_speaker_data_merged_new_alt", con=engine)

df["speaker_text_alt_clean"] = df["speaker_text_alt"].map(clean_text)
df["speaker_text_new_clean"] = df["speaker_text_new"].map(clean_text)

fname = '/home/zjy/result.txt'
f = open(fname, "a")
cnt_same = 0
cnt_diff = 0
for i in range(len(df)):
    sents_x = sent_tokenize(df["speaker_text_alt_clean"][i])
    sents_y = sent_tokenize(df["speaker_text_new_clean"][i])
    
    if sents_x == sents_y:
        cnt_same += 1
        continue

    for diff in unified_diff(sents_x, sents_y):
        if diff and type(diff) == unicode:
            if diff.startswith("+") or diff.startswith("-"):
                cnt_diff += 1
                tmpdiff = diff.split()
                tmpdiff = ' '.join(tmpdiff)
                tmpdiff = tmpdiff + '\n'
                f.write(tmpdiff.encode('utf-8'))
                # f.read().decode('utf8')
    
f.close()

print 'Total row =', len(df)
print 'Same row =', cnt_same, 'Diff row =',cnt_diff

# Step 2: Analyze diff rows in tmp file
# f = open(fname, "r")
# content = f.read().decode('utf-8')
# f.close()

# if len(content) == 0:
#     print 'No difference. Empty file:', fname

        
# tmp_content = content.split('$$$$$')
# for i in tmp_content:
#     print i
#print tmp_content