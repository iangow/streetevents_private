import re

categories = ["positive", "negative", "uncertainty",
                "litigious", "modal_strong", "modal_weak"]

base_url = "http://www3.nd.edu/~mcdonald/Data/Finance_Word_Lists"

partial_urls = ["LoughranMcDonald_Positive.csv",
        "LoughranMcDonald_Negative.csv",
        "LoughranMcDonald_Uncertainty.csv",
        "LoughranMcDonald_Litigious.csv",
        "LoughranMcDonald_ModalStrong.csv",
         "LoughranMcDonald_ModalWeak.csv"]

urls = [base_url + "/" + url for url in partial_urls]

def get_word_list(url):
    import csv
    import urllib.request

    webpage = urllib.request.urlopen(url)
    datareader = csv.reader(webpage.read().decode('utf-8').splitlines())
    return [row[0].lower() for row in datareader]

[get_word_list(url) for url in urls]

mod_word_list = {tuple[0]: get_word_list(tuple[1]) for tuple in zip(categories, urls)}

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
