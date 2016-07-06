import re, nltk, json

# check for a letter or digit; https://docs.python.org/3/library/re.html
nonPunct = re.compile('\w')

from nltk.corpus import cmudict
dic = cmudict.dict()
from collections import Counter
from nltk import sent_tokenize, word_tokenize

def nsyl(word):
    """ Function that uses CMU dictionary from NLTK to count syllables in
        a word. If the word is unrecognized, return value will be None.

        If alternative pronunciations are found, function returns maximum
        value.
    """
    if word in dic:
        pronunciations = dic[word]
        num_syls = [len([syl for syl in pron if re.findall('[0-9]', syl)])
                             for pron in pronunciations]
        return max(num_syls)

def flatten(a_list):
    return [item for sublist in a_list for item in sublist]

def syllable_data(text):

    # Use NLTK to 'tokenize' text into sentences, then into words
    sents = sent_tokenize(text)
    word_tokens = flatten([word_tokenize(s) for s in sents])

    # Get words that have letters in them (this excludes pure punctuation
    # tokens like `,
    words = [w for w in word_tokens if nonPunct.match(w)]
    words_7 = [word for word in words if len(word)>7]


    sylls = [nsyl(word.lower()) for word in words]
    syl_dict = {
            'sent_count': len(sents),
            'word_count': len(words),
            'word_7_count': len(words_7),
            'num_syllables': sum([syll for syll in sylls if syll is not None]),
            'syllable_counts': \
                Counter([syll for syll in  sylls if syll is not None])}
    return json.dumps(syl_dict)
