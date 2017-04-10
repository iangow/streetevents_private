# Linguistic features

`run_syllable_count.py` calls `process_file_syllables.py`,
which in turn uses functions from `syllable_count.py` to process syllable data
for a given file.

The code in `syllable_count.py` is pretty self-explanatory.
The "syllable data", which includes the number of words (`word_count`)
and sentences (`sent_count`), is stored in a `jsonb` column just because
it was easy to do so.
