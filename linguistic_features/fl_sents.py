import re

# Pre-compile regular expressions.
fl_regex = r"will|should|can|could|may|might|expect|anticipate|"
fl_regex += r"believe|plan|hope|intend|seek|project|forecast|objective|goal"
fl_regex = re.compile(r"(?:\b(" + fl_regex + r"))", re.I)

fl_pp = r"(?:expected|anticipated|forecasted|projected|believed)"
fl_be_pp = r"(?:was|were|had|had been)"
nfl_regex = re.compile(r"\b" + fl_be_pp + r"\s" + fl_pp, re.I)

from nltk import sent_tokenize

def prop_fl_sents(text):

    """Function to return proportion of sentences than contain
        forward-looking terms."""
    sentences = sent_tokenize(text)

    fl_sents = [sent for sent in sentences if re.findall(fl_regex, sent) and \
                                not re.findall(nfl_regex, sent)]
    if len(sentences) > 0:
        return(len(fl_sents)*1.0/len(sentences))
