DROP FUNCTION IF EXISTS streetevents.parse_name(text);

CREATE OR REPLACE FUNCTION streetevents.parse_name(text)
  RETURNS parsed_name AS
$BODY$
    # Reset variables
    my ($prefix, $names, $suffixes, $first_names, $last_names);
    my ($last_name, $first_name, $middle_initial);

    # StreetEvents names have prefixes ("Mr" or "Dr.") that
    # we need to extract.
    $prefixes = "[MD]rs?\.?";
    $last_name_prefixes = '(?:(?:[Dd][eu]|[Dd]e la|[Vv]an [Dd]e[rn]?|[Vv]an)\s)';

    if (defined($_[0])) {

        # No commas in names, but commas are used to distinguish
        # suffixes
        if ($_[0] =~ /^(.*?)(?:, (.*))?$/) {
            ($names, $suffixes) = ($1, $2);
        }

        # Extract and remove prefixes
        if ($names =~ /^($prefixes)\s+/) {
            $prefix = $1;
            $names =~ s/^($prefixes)\s+//;
        }

        # Split rest on spaces. Greediness of .* is used to
        # ensure it is the last space that gets used.
        #
        if ($names =~ /^(.*?)\s($last_name_prefixes?[^\s]+)$/) {
            ($first_names, $last_name) = ($1, $2);
            if ($first_names =~ /([-\w\.]+)\s*([\w\.]+)?/) {
                ($first_name, $middle_initial) = ($1, $2);
            }
        }
    }
    return {first_name => $first_name, middle_initial => $middle_initial,
            last_name => $last_name, suffix => $suffixes, prefix => $prefix };

$BODY$ LANGUAGE plperl;

ALTER FUNCTION streetevents.parse_name(text) OWNER TO personality_access;
