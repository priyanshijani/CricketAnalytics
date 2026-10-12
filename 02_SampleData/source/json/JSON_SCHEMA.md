# Match JSON Schema

One file per match. `match.schema.json` is the machine-readable version of what's described here.

## Structure

```
match_id        string, required - natural key. Missing on a malformed file (planted case).
season          string, required
format          string, required - always "T20" in this dataset
date            string (ISO date), required
venue.code      string, required - foreign key to CricketSource.Venues
teams[]         array of exactly two objects, required
teams[].code    string, required - foreign key to CricketSource.Teams
teams[].name    string, required - the team's name AS OF this match (the signal Dim_Team's
                Type-2 SCD uses to detect a rename between seasons)
toss.winner     string, required - one of the two team codes
toss.decision   string, required - "Bat" or "Field"
result.method   string, required - "Normal" | "Tied" | "NoResult" | "Abandoned" | "SuperOver"
result.winner   string, nullable - null when method is Tied, NoResult, or Abandoned
result.margin   number, nullable
result.margin_type  string, nullable - "Runs" or "Wickets"
result.man_of_match  string, nullable - player code
innings[]       array, 0-2 objects - empty for an abandoned match with no play
innings[].runs         number, optional - can be absent (planted missing-data case)
innings[].wickets       number, required - expected 0-10; a higher value is a planted invalid case
innings[].overs           number, required
innings[].extras            number, required
```

## Example

See any file in `matches/` - for instance the first match in the baseline dataset - for a complete,
valid example.
