-- Function: public.findner(text)

-- DROP FUNCTION public.findner(text);

CREATE OR REPLACE FUNCTION public.findner(the_text text)
  RETURNS jsonb AS
$BODY$

    if 'ner' in SD:
        ner = SD['ner']
        sent_tokenize = SD['sent_tokenize']
        word_tokenize = SD['word_tokenize']
        os = SD['os']
        json = SD['json']
        NER_JAR = SD['NER_JAR']
        NER_CLASSIFIER = SD['NER_CLASSIFIER']
        StanfordNERTagger = SD['StanfordNERTagger']
    else:
        import json

        # Point these toward your download of Stanford NER
        # Need to figure out which is appropriate classifier to use
        NER_JAR = '/opt/local/share/java/stanford-ner/stanford-ner.jar'
        NER_CLASSIFIER = '/opt/local/share/java/stanford-ner/classifiers/english.muc.7class.distsim.crf.ser.gz'

        # Create Stanford NER Tagger
        from nltk.tag.stanford import StanfordNERTagger
        SD['StanfordNERTagger'] = StanfordNERTagger
        ner = StanfordNERTagger(NER_CLASSIFIER, NER_JAR)
        SD['ner'] = ner

        from nltk.tokenize import sent_tokenize, word_tokenize
        SD['sent_tokenize'] = sent_tokenize
        SD['word_tokenize'] = word_tokenize

        import os
        java_path = "/usr/bin/java"
        os.environ['JAVAHOME'] = java_path
        SD['os'] = os

        SD['json'] = json
        SD['NER_JAR'] = NER_JAR
        SD['NER_CLASSIFIER'] = NER_CLASSIFIER

    sentences = sent_tokenize(the_text.decode('utf8'))
    tagged = [(key, val) for s in sentences for val, key in ner.tag(word_tokenize(s))
                    if key != "O"]

    nerTags = dict()
    for key, val in tagged:
        if key in nerTags.keys():
            nerTags[key].append(val)
        else:
            nerTags[key] = [val]

    return json.dumps(nerTags)

$BODY$
  LANGUAGE plpythonu VOLATILE
  COST 100;
ALTER FUNCTION public.findner(text)
  OWNER TO igow;
