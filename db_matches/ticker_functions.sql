
/* '.' in tickers for streetevents specifies the stock exhange
(see: http://www.sirca.org.au/2010/12/tick-history-exchange-identifiers/)
KEEP U.S.:
    .N  -> NYSE    (2 tickers for bank of cyprus with .N but is not in NYSE, thus incorrectly labelled?)
    .OQ -> NASDAQ  (0 tickers with .OQ)
    .A  -> AMEX       (4 tickers with .A -> BRK.A, FCE.A, JW.A, MOG.A)
REMOVE FOREIGN (EXAMPLES):
    .TW -> Taiwan
    .TO -> Toronto
    .T  -> Tokyo (Nikkei)
    .L  -> London (FTSE)
--remove foreign firms and obtain unmatched obs.*/

/*Some tickers in streetevents have '**' in front of the ticker. Not certain why.

    Examples:
        ticker    | co_name         | call_date
        **ADAM    | ADAM Inc        | 2008-11-06 15:00:00
        **GEH     | GE Healthcare   | 2005-04-05 08:00:00
        **DRD     | Duane Reade     | 2006-05-11 14:00:00

   Remove Asterix
*/

--DROP EXTENSION plperl CASCADE;
-- CREATE EXTENSION plperl; --postgresql-plperl not installable

CREATE OR REPLACE FUNCTION streetevents.clean_tickers (ticker text) RETURNS text AS
$BODY$
  # Remove any asterisks
  my $string = $_[0];
  $string =~ s/\*//g;

  # Remove trailing .A
  $string =~ s/\.A$//g;

  return $string;
$BODY$ LANGUAGE plperl IMMUTABLE STRICT COST 100;

ALTER FUNCTION streetevents.clean_tickers(text) OWNER TO personality_access;

/* Some tickers with ending Q causes non-matches. Examples:
    streetevents          --->  crsp.stocknames
    _______________________     _______________________________________
    ticker  co_name             ticker  comnam
    ATRNQ   Atrinsic Inc        ATRN    ATRINSIC INC
    CPICQ   CPI CORP            CPIC    C P I CORP
    DDMGQ   Digital Domain      DDMG    DIGITAL DOMAIN MEDIA GROUP INC
            Media Group Inc
*/
SET work_mem='15GB';

CREATE OR REPLACE FUNCTION streetevents.remove_trailing_q (ticker text)
RETURNS text AS
$BODY$
  # Remove trailing Qs
  my $string = $_[0];
  $string =~ s/Q$//g;

  return $string;
$BODY$ LANGUAGE plperl IMMUTABLE STRICT COST 100;

ALTER FUNCTION streetevents.remove_trailing_q(text) OWNER TO personality_access;
