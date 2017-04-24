import re
 
def num_count(text):
    # Regular expression to pick up months as described in Lundholm, Rogo and Zhang (2014)
    months = ['January', 'February', 'March', 'April', 'May', 'June', 'July',
                    'August', 'September', 'October', 
                    'November', 'December']     
    months_abbrev = [ month[0:3] + '\.?' for month in months]
    month_re = '(?:' + '|'.join(months + months_abbrev) + ')'
     
    # Years are four-digit numbers without commas.
    # I have a better rule using the fact that years will begin with 19 or 20, etc.
    years = '\s*\d{4}\.?'
     
    # Keep matching numbers, as well as month portion, if any
    matches =  re.findall('(?:' + month_re + '\s+)?[0-9][0-9,\.]*', text)
     
    # return matches that aren't years and aren't preceded by months
    return len([ a_match for a_match in matches
                if not re.match(years, a_match) 
                    and not re.match(month_re, a_match)])
