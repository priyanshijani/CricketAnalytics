"""Generates the Cricket Analytics Platform sample dataset.

Produces everything under 02_SampleData/source/: the CricketSource seed script, match JSON files,
CSV files, the demo_changes dataset, and the accompanying schema/data-quality documentation.
Re-running this script regenerates the baseline dataset from scratch with the same seed, so the
data and its documentation never drift apart.

Standard library only - no external dependencies.
"""

from __future__ import annotations

import csv
import hashlib
import json
import random
from datetime import date, timedelta
from pathlib import Path

SEED = 20260101
random.seed(SEED)

GENERATOR_DIR = Path(__file__).resolve().parent
SOURCE_DIR = GENERATOR_DIR.parent / "source"
SEASONS = ["2023", "2024", "2025"]
MATCHES_PER_SEASON = 40
FORMAT_CODE = "T20"
OVERS_PER_INNINGS = 20
BALLS_PER_OVER = 6
MAX_OVERS_PER_BOWLER = 4

# ---------------------------------------------------------------------------
# Reference data
# ---------------------------------------------------------------------------

# (code, name in 2023, name from 2024 onward, country)
TEAMS = [
    ("MUM", "Mumbai Sharks", "Mumbai Sharks", "India"),
    ("DEL", "Delhi Falcons", "Delhi Comets", "India"),  # planted rename - exercises Dim_Team SCD2
    ("CHE", "Chennai Kings", "Chennai Kings", "India"),
    ("KOL", "Kolkata Tigers", "Kolkata Tigers", "India"),
    ("BLR", "Bangalore Royals", "Bangalore Royals", "India"),
    ("HYD", "Hyderabad Hawks", "Hyderabad Hawks", "India"),
    ("PUN", "Punjab Warriors", "Punjab Warriors", "India"),
    ("RAJ", "Rajasthan Titans", "Rajasthan Titans", "India"),
]

# (code, name, city, country, capacity) - HYD01's city is deliberately missing
VENUES = [
    ("MUM01", "Wankhede Ground", "Mumbai", "India", 33000),
    ("DEL01", "Feroz Arena", "Delhi", "India", 41000),
    ("CHE01", "Chepauk Stadium", "Chennai", "India", 38000),
    ("KOL01", "Eden Fields", "Kolkata", "India", 42000),
    ("BLR01", "Chinnaswamy Park", "Bangalore", "India", 35000),
    ("HYD01", "Uppal Arena", None, "India", 30000),  # planted missing information
    ("PUN01", "Mullanpur Ground", "Chandigarh", "India", 34000),
    ("RAJ01", "Jaipur Dome", "Jaipur", "India", 28000),
]

FIRST_NAMES = [
    "Arjun", "Rohan", "Vikram", "Karan", "Aditya", "Rahul", "Siddharth", "Manish", "Nikhil", "Varun",
    "Sanjay", "Ishaan", "Devendra", "Farhan", "Gautam", "Harish", "Imran", "Jayant", "Kabir", "Lakshay",
    "Mohit", "Naveen", "Omar", "Pranav", "Qasim", "Rajat", "Suresh", "Tarun", "Uday", "Vishal",
    "Amit", "Bhavesh", "Chetan", "Dhruv", "Eshan",
]
LAST_NAMES = [
    "Sharma", "Verma", "Kapoor", "Mehta", "Iyer", "Nair", "Reddy", "Khan", "Chauhan", "Malhotra",
    "Bhatt", "Joshi", "Pillai", "Rao", "Sinha", "Gill", "Dhawan", "Agarwal", "Kulkarni", "Menon",
    "Pandey", "Saxena", "Trivedi", "Yadav", "Bose", "Ghosh", "Desai", "Shetty", "Naidu", "Chopra",
]
COUNTRIES = ["India", "Australia", "England", "South Africa", "New Zealand", "Pakistan", "Sri Lanka", "West Indies"]
BATTING_STYLES = ["Right-hand bat", "Left-hand bat"]
BOWLING_STYLES = ["Right-arm fast", "Left-arm fast", "Right-arm off-spin", "Left-arm orthodox", "Right-arm leg-spin", None]
ROLES = ["Batter", "Bowler", "AllRounder", "WicketKeeper"]

DISMISSAL_TYPES = ["Bowled", "Caught", "LBW", "RunOut", "Stumped"]

RESULT_MARGIN_TYPE = {"Runs": "Runs", "Wickets": "Wickets"}


# ---------------------------------------------------------------------------
# Players
# ---------------------------------------------------------------------------

def generate_players() -> list[dict]:
    used_names = set()
    players = []
    player_seq = 1
    for team_code, _, _, _ in TEAMS:
        roster_size = 19
        for _ in range(roster_size):
            while True:
                name = f"{random.choice(FIRST_NAMES)} {random.choice(LAST_NAMES)}"
                if name not in used_names:
                    used_names.add(name)
                    break
            role = random.choices(ROLES, weights=[35, 35, 20, 10])[0]
            birth_year = random.randint(1988, 2005)
            dob = date(birth_year, random.randint(1, 12), random.randint(1, 28))
            debut = date(min(birth_year + random.randint(18, 22), 2022), random.randint(1, 12), random.randint(1, 28))
            players.append({
                "code": f"P{player_seq:04d}",
                "name": name,
                "dob": dob,
                "country": random.choice(COUNTRIES),
                "batting_style": random.choice(BATTING_STYLES),
                "bowling_style": None if role == "Batter" else random.choice(BOWLING_STYLES),
                "role": role,
                "debut": debut,
                "home_team": team_code,
            })
            player_seq += 1
    return players


def assign_rosters(players: list[dict]) -> dict[str, dict[str, list[dict]]]:
    """Season -> team_code -> ordered squad (batting order 1-11 first)."""
    by_team = {code: [p for p in players if p["home_team"] == code] for code, *_ in TEAMS}
    rosters: dict[str, dict[str, list[dict]]] = {}
    swapped_once = set()
    for season_idx, season in enumerate(SEASONS):
        rosters[season] = {}
        for team_code, squad in by_team.items():
            xi = squad[:11]
            # A handful of players switch teams for one season, to exercise the bridge table.
            if season_idx > 0 and team_code not in swapped_once and random.random() < 0.4:
                other_team = random.choice([c for c, *_ in TEAMS if c != team_code])
                mover = squad[11] if len(squad) > 11 else squad[-1]
                by_team[other_team].append(mover)
                by_team[team_code] = [p for p in squad if p is not mover]
                swapped_once.add(team_code)
            rosters[season][team_code] = by_team[team_code][:11] + by_team[team_code][11:]
    return rosters


# ---------------------------------------------------------------------------
# Match simulation
# ---------------------------------------------------------------------------

def pick_match_xi(season_roster: list[dict]) -> list[dict]:
    core = season_roster[:11]
    bench = season_roster[11:]
    xi = list(core)
    for i in range(len(xi)):
        if bench and random.random() < 0.10:
            xi[i] = random.choice(bench)
    return xi


def simulate_innings(match_id: str, innings_no: int, batting_xi: list[dict], bowling_xi: list[dict]):
    bowlers = [p for p in bowling_xi if p["role"] in ("Bowler", "AllRounder")]
    if len(bowlers) < 5:
        bowlers = bowlers + [p for p in bowling_xi if p not in bowlers][: 5 - len(bowlers)]

    deliveries = []
    striker_idx = 0
    non_striker_idx = 1
    next_batsman_idx = 2
    wickets = 0
    total_runs = 0
    total_extras = 0
    bowler_overs: dict[str, int] = {b["code"]: 0 for b in bowlers}
    last_bowler = None
    balls_bowled = 0

    for over_no in range(1, OVERS_PER_INNINGS + 1):
        if wickets >= 10:
            break
        eligible = [b for b in bowlers if bowler_overs[b["code"]] < MAX_OVERS_PER_BOWLER and b["code"] != last_bowler]
        if not eligible:
            eligible = [b for b in bowlers if bowler_overs[b["code"]] < MAX_OVERS_PER_BOWLER]
        bowler = random.choice(eligible) if eligible else random.choice(bowlers)
        bowler_overs[bowler["code"]] += 1
        last_bowler = bowler["code"]

        legal_balls = 0
        delivery_seq = 0  # counts every attempt in the over, legal or extra - always unique per over
        while legal_balls < BALLS_PER_OVER and wickets < 10:
            outcome = random.choices(
                ["dot", "one", "two", "three", "four", "six", "wicket", "extra"],
                weights=[33, 28, 8, 1, 12, 6, 6, 6],
            )[0]
            striker = batting_xi[striker_idx]
            delivery_seq += 1

            if outcome == "extra":
                total_extras += 1
                total_runs += 1
                deliveries.append(_delivery_row(
                    match_id, innings_no, over_no, delivery_seq, striker, bowler,
                    runs_off_bat=0, extra_runs=1, extra_type=random.choice(["Wide", "NoBall"]),
                    is_wicket=False, dismissal_type=None, dismissed=None,
                ))
                continue  # does not count as a legal ball

            legal_balls += 1
            if outcome == "wicket":
                wickets += 1
                dismissal = random.choice(DISMISSAL_TYPES)
                deliveries.append(_delivery_row(
                    match_id, innings_no, over_no, delivery_seq, striker, bowler,
                    runs_off_bat=0, extra_runs=0, extra_type=None,
                    is_wicket=True, dismissal_type=dismissal, dismissed=striker,
                ))
                if wickets < 10 and next_batsman_idx < len(batting_xi):
                    striker_idx = next_batsman_idx
                    next_batsman_idx += 1
                continue

            runs_map = {"dot": 0, "one": 1, "two": 2, "three": 3, "four": 4, "six": 6}
            runs = runs_map[outcome]
            total_runs += runs
            deliveries.append(_delivery_row(
                match_id, innings_no, over_no, delivery_seq, striker, bowler,
                runs_off_bat=runs, extra_runs=0, extra_type=None,
                is_wicket=False, dismissal_type=None, dismissed=None,
            ))
            if runs % 2 == 1:
                striker_idx, non_striker_idx = non_striker_idx, striker_idx
        balls_bowled += legal_balls
        if legal_balls == BALLS_PER_OVER:
            striker_idx, non_striker_idx = non_striker_idx, striker_idx

    overs_played = round(balls_bowled / BALLS_PER_OVER + (balls_bowled % BALLS_PER_OVER) * 0.1, 1)
    overs_played = balls_bowled // BALLS_PER_OVER + (balls_bowled % BALLS_PER_OVER) / 10
    return {
        "innings_no": innings_no,
        "runs": total_runs,
        "wickets": wickets,
        "overs": round(overs_played, 1),
        "extras": total_extras,
    }, deliveries


def _delivery_row(match_id, innings_no, over_no, ball_no, striker, bowler,
                   runs_off_bat, extra_runs, extra_type, is_wicket, dismissal_type, dismissed):
    return {
        "match_id": match_id,
        "innings_no": innings_no,
        "over_no": over_no,
        "ball_no": ball_no,
        "batsman_code": striker["code"],
        "bowler_code": bowler["code"],
        "runs_off_bat": runs_off_bat,
        "extra_runs": extra_runs,
        "extra_type": extra_type or "",
        "is_wicket": "Y" if is_wicket else "N",
        "dismissal_type": dismissal_type or "",
        "dismissed_player_code": dismissed["code"] if dismissed else "",
    }


def simulate_match(match_id: str, season: str, match_date: date, team_a: str, team_b: str,
                    venue_code: str, rosters: dict, team_name_lookup, mode: str = "normal") -> tuple[dict, list[dict]]:
    xi_a = pick_match_xi(rosters[season][team_a])
    xi_b = pick_match_xi(rosters[season][team_b])
    toss_winner = random.choice([team_a, team_b])
    toss_decision = random.choice(["Bat", "Field"])
    if (toss_decision == "Bat") == (toss_winner == team_a):
        bat_first, bowl_first, xi_bat, xi_bowl = team_a, team_b, xi_a, xi_b
    else:
        bat_first, bowl_first, xi_bat, xi_bowl = team_b, team_a, xi_b, xi_a

    base_fields = {
        "match_id": match_id, "season": season, "format": FORMAT_CODE, "date": match_date.isoformat(),
        "venue_code": venue_code, "team_a": team_a, "team_b": team_b,
        "team_a_name": team_name_lookup(team_a, season), "team_b_name": team_name_lookup(team_b, season),
        "toss_winner": toss_winner, "toss_decision": toss_decision,
    }

    if mode == "abandoned":
        # No play at all - a genuinely unresolved match. innings stays empty, not missing.
        return {**base_fields, "result_method": "Abandoned", "winner": None, "margin": None,
                "margin_type": None, "man_of_match": None, "innings": []}, []

    if mode == "no_result":
        # Play started, rain ended it before a second innings - a legitimate partial match.
        innings1, deliveries1 = simulate_innings(match_id, 1, xi_bat, xi_bowl)
        innings1["batting_team"], innings1["bowling_team"] = bat_first, bowl_first
        return {**base_fields, "result_method": "NoResult", "winner": None, "margin": None,
                "margin_type": None, "man_of_match": None, "innings": [innings1]}, deliveries1

    if mode in ("tied", "super_over"):
        # Retry until the two innings land on the same score - deterministic given the fixed seed.
        for _ in range(500):
            innings1, deliveries1 = simulate_innings(match_id, 1, xi_bat, xi_bowl)
            innings2, deliveries2 = simulate_innings(match_id, 2, xi_bowl, xi_bat)
            if innings1["runs"] == innings2["runs"]:
                break
    else:
        innings1, deliveries1 = simulate_innings(match_id, 1, xi_bat, xi_bowl)
        innings2, deliveries2 = simulate_innings(match_id, 2, xi_bowl, xi_bat)

    innings1["batting_team"], innings1["bowling_team"] = bat_first, bowl_first
    innings2["batting_team"], innings2["bowling_team"] = bowl_first, bat_first

    if innings1["runs"] == innings2["runs"]:
        if mode == "super_over":
            method, winner, margin, margin_type = "SuperOver", random.choice([team_a, team_b]), 1, "Runs"
        else:
            method, winner, margin, margin_type = "Tied", None, None, None
    elif innings2["runs"] > innings1["runs"]:
        method, winner = "Normal", innings2["batting_team"]
        margin, margin_type = 10 - innings2["wickets"], "Wickets"
    else:
        method, winner = "Normal", innings1["batting_team"]
        margin, margin_type = innings1["runs"] - innings2["runs"], "Runs"

    all_players = xi_bat + xi_bowl
    mom_code = random.choice(all_players)["code"] if winner else None

    match_record = {
        **base_fields,
        "result_method": method,
        "winner": winner,
        "margin": margin,
        "margin_type": margin_type,
        "man_of_match": mom_code,
        "innings": [innings1, innings2],
    }
    return match_record, deliveries1 + deliveries2


# ---------------------------------------------------------------------------
# Scheduling
# ---------------------------------------------------------------------------

def schedule_matches() -> list[tuple[str, date, str, str]]:
    """Returns (season, date, team_a, team_b) tuples, team_a is the home team."""
    schedule = []
    team_codes = [c for c, *_ in TEAMS]
    for season_idx, season in enumerate(SEASONS):
        season_start = date(2023 + season_idx, 4, 1)
        pairs = []
        for i, home in enumerate(team_codes):
            for away in team_codes[i + 1:]:
                pairs.append((home, away))
                pairs.append((away, home))  # home-and-away, so a season has enough fixtures to draw from
        random.shuffle(pairs)
        chosen = pairs[:MATCHES_PER_SEASON]
        chosen.sort(key=lambda _: random.random())
        for i, (home, away) in enumerate(chosen):
            match_date = season_start + timedelta(days=i * 2)
            schedule.append((season, match_date, home, away))
    return schedule


# ---------------------------------------------------------------------------
# Output writers
# ---------------------------------------------------------------------------

def write_json(path: Path, record: dict) -> str:
    path.parent.mkdir(parents=True, exist_ok=True)
    text = json.dumps(record, indent=2, default=str)
    path.write_text(text, encoding="utf-8")
    return hashlib.sha256(text.encode("utf-8")).hexdigest()


def match_to_json_record(m: dict) -> dict:
    return {
        "match_id": m["match_id"],
        "season": m["season"],
        "format": m["format"],
        "date": m["date"],
        "venue": {"code": m["venue_code"]},
        "teams": [
            {"code": m["team_a"], "name": m["team_a_name"]},
            {"code": m["team_b"], "name": m["team_b_name"]},
        ],
        "toss": {"winner": m["toss_winner"], "decision": m["toss_decision"]},
        "result": {
            "method": m["result_method"],
            "winner": m["winner"],
            "margin": m["margin"],
            "margin_type": m["margin_type"],
            "man_of_match": m["man_of_match"],
        },
        "innings": [
            {
                k: v for k, v in {
                    "innings_no": inn["innings_no"],
                    "batting_team": inn["batting_team"],
                    "bowling_team": inn["bowling_team"],
                    "runs": inn.get("runs"),  # deliberately absent on one planted match (DQ03)
                    "wickets": inn["wickets"],
                    "overs": inn["overs"],
                    "extras": inn["extras"],
                }.items() if not (k == "runs" and "runs" not in inn)
            }
            for inn in m["innings"]
        ],
    }


def write_deliveries_csv(path: Path, deliveries: list[dict]) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    fieldnames = ["match_id", "innings_no", "over_no", "ball_no", "batsman_code", "bowler_code",
                  "runs_off_bat", "extra_runs", "extra_type", "is_wicket", "dismissal_type",
                  "dismissed_player_code"]
    with path.open("w", newline="", encoding="utf-8") as f:
        writer = csv.DictWriter(f, fieldnames=fieldnames)
        writer.writeheader()
        writer.writerows(deliveries)


def sql_str(value) -> str:
    if value is None:
        return "NULL"
    return "N'" + str(value).replace("'", "''") + "'"


def sql_val(value) -> str:
    if value is None:
        return "NULL"
    if isinstance(value, (int, float)):
        return str(value)
    return sql_str(value)


# ---------------------------------------------------------------------------
# Main generation flow
# ---------------------------------------------------------------------------

def main() -> None:
    players = generate_players()
    rosters = assign_rosters(players)
    schedule = schedule_matches()

    team_current_name = {code: (name_2023 if False else name_2024) for code, name_2023, name_2024, _ in TEAMS}

    def team_name_lookup(code: str, season: str) -> str:
        for c, name_2023, name_2024, _ in TEAMS:
            if c == code:
                return name_2023 if season == "2023" else name_2024
        raise KeyError(code)

    matches = []
    deliveries_by_season: dict[str, list[dict]] = {s: [] for s in SEASONS}

    # Deterministic result-type edge cases, by schedule position - see DATA_QUALITY_ISSUES.md's
    # "legitimate edge cases" section, which documents these by the match IDs actually produced here.
    special_modes = {60: "abandoned", 65: "no_result", 70: "tied", 75: "super_over"}

    match_seq = 1
    for idx, (season, match_date, home, away) in enumerate(schedule):
        match_id = f"M{match_seq:04d}"
        venue_code = next(v[0] for v in VENUES if v[0].startswith(home))
        mode = special_modes.get(idx, "normal")
        record, deliveries = simulate_match(match_id, season, match_date, home, away, venue_code, rosters, team_name_lookup, mode=mode)
        matches.append(record)
        deliveries_by_season[season].extend(deliveries)
        match_seq += 1

    inject_baseline_dq_issues(matches, deliveries_by_season, players)

    matches_dir = SOURCE_DIR / "json" / "matches"
    for m in matches:
        write_json(matches_dir / f"{m['match_id']}.json", match_to_json_record(m))

    # Duplicate delivery: the same match JSON written a second time under a different filename.
    dup_source = matches[10]
    write_json(matches_dir / f"{dup_source['match_id']}_redelivered.json", match_to_json_record(dup_source))

    for season in SEASONS:
        write_deliveries_csv(SOURCE_DIR / "csv" / "deliveries" / f"deliveries_{season}.csv", deliveries_by_season[season])

    write_player_rankings_csv(matches, players)
    write_historical_stats_csv(matches, deliveries_by_season, players)
    write_seed_sql(players, rosters)
    write_baseline_malformed_files(matches_dir)
    write_demo_changes(matches, deliveries_by_season, players, team_name_lookup)
    write_documentation(players, matches)

    print(f"Generated {len(matches)} matches across {len(SEASONS)} seasons.")
    print(f"Generated {len(players)} players across {len(TEAMS)} teams.")
    total_deliveries = sum(len(v) for v in deliveries_by_season.values())
    print(f"Generated {total_deliveries} ball-by-ball delivery rows.")


def inject_baseline_dq_issues(matches, deliveries_by_season, players) -> None:
    # Future date of birth - deliberately invalid value.
    players[3]["dob"] = date(2027, 1, 1)

    # Missing date of birth - deliberately absent value, on five different players.
    for i in (7, 8, 9, 10, 11):
        players[i]["dob"] = None

    # Missing scores - a normal completed match with an innings summary field stripped out.
    target = matches[5]
    del target["innings"][1]["runs"]

    # Wickets exceeding ten in an innings - a provider reporting error on the summary figure.
    matches[7]["innings"][0]["wickets"] = 11

    # Orphan foreign key - one match references a team code absent from CricketSource.Teams.
    matches[12]["team_b"] = "XYZ"
    matches[12]["team_b_name"] = "Unknown XYZ"

    # Negative runs on one delivery.
    season_with_rows = next(s for s, rows in deliveries_by_season.items() if rows)
    deliveries_by_season[season_with_rows][20]["runs_off_bat"] = -1

    # Performance CSV referencing an unknown player.
    deliveries_by_season[season_with_rows][21]["batsman_code"] = "P9999"


def write_player_rankings_csv(matches, players) -> None:
    path = SOURCE_DIR / "csv" / "player_rankings" / "player_rankings.csv"
    path.parent.mkdir(parents=True, exist_ok=True)
    rows = []
    ranking_dates = []
    for season_idx, season in enumerate(SEASONS):
        for month in (5, 8, 11):
            ranking_dates.append((season, date(2023 + season_idx, month, 1)))

    scored = {p["code"]: random.randint(200, 900) for p in players}
    for season, rdate in ranking_dates:
        for discipline in ("Batting", "Bowling", "AllRounder"):
            eligible = [p for p in players if discipline == "AllRounder" and p["role"] == "AllRounder"
                        or discipline == "Batting" and p["role"] in ("Batter", "WicketKeeper")
                        or discipline == "Bowling" and p["role"] == "Bowler"]
            ranked = sorted(eligible, key=lambda p: -scored[p["code"]])[:30]
            for pos, p in enumerate(ranked, start=1):
                name = p["name"]
                if p["code"] == players[1]["code"]:
                    name = name.upper()  # planted casing inconsistency vs. the SQL master
                # Date format deliberately inconsistent with historical_stats.csv (dd/mm/yyyy vs ISO).
                rows.append({
                    "player_code": p["code"],
                    "player_name": name,
                    "format_code": FORMAT_CODE,
                    "discipline": discipline,
                    "ranking_date": rdate.strftime("%d/%m/%Y"),
                    "rank_position": pos,
                    "rating_points": scored[p["code"]] - pos * 3,
                })
            for p in eligible:
                scored[p["code"]] += random.randint(-40, 60)

    with path.open("w", newline="", encoding="utf-8") as f:
        writer = csv.DictWriter(f, fieldnames=["player_code", "player_name", "format_code", "discipline",
                                                 "ranking_date", "rank_position", "rating_points"])
        writer.writeheader()
        writer.writerows(rows)


def write_historical_stats_csv(matches, deliveries_by_season, players) -> None:
    path = SOURCE_DIR / "csv" / "historical_stats" / "historical_stats.csv"
    path.parent.mkdir(parents=True, exist_ok=True)
    rows = []
    for season in SEASONS:
        runs_by_player: dict[str, int] = {}
        wickets_by_player: dict[str, int] = {}
        matches_by_player: dict[str, set] = {}
        for d in deliveries_by_season[season]:
            bat = d["batsman_code"]
            matches_by_player.setdefault(bat, set()).add(d["match_id"])
            runs_by_player[bat] = runs_by_player.get(bat, 0) + max(d["runs_off_bat"], 0)
            if d["is_wicket"] == "Y":
                bowler = d["bowler_code"]
                matches_by_player.setdefault(bowler, set()).add(d["match_id"])
                wickets_by_player[bowler] = wickets_by_player.get(bowler, 0) + 1
        player_codes = set(runs_by_player) | set(wickets_by_player)
        name_lookup = {p["code"]: p["name"] for p in players}
        for code in sorted(player_codes):
            rows.append({
                "player_code": code,
                "player_name": name_lookup.get(code, "Unknown"),
                "season": season,
                "format_code": FORMAT_CODE,
                "matches_played": len(matches_by_player.get(code, set())),
                "runs_scored": runs_by_player.get(code, 0),
                "wickets_taken": wickets_by_player.get(code, 0),
                "season_start_date": date(2023 + SEASONS.index(season), 4, 1).isoformat(),
            })
    with path.open("w", newline="", encoding="utf-8") as f:
        writer = csv.DictWriter(f, fieldnames=["player_code", "player_name", "season", "format_code",
                                                 "matches_played", "runs_scored", "wickets_taken",
                                                 "season_start_date"])
        writer.writeheader()
        writer.writerows(rows)


def write_seed_sql(players, rosters) -> None:
    path = SOURCE_DIR / "sql_server" / "seed_data.sql"
    path.parent.mkdir(parents=True, exist_ok=True)
    lines = [
        "-- Generated by 02_SampleData/generator/generate_sample_data.py. Do not edit by hand.",
        "-- Seeds CricketSource with the baseline master/reference dataset.",
        "USE CricketSource;",
        "GO",
        "",
        "DELETE FROM dbo.Teams;",
        "DELETE FROM dbo.Players;",
        "DELETE FROM dbo.Venues;",
        "GO",
        "",
    ]

    for code, name_2023, name_2024, country in TEAMS:
        current_name = name_2024  # CricketSource holds the current name only; history lives in Dim_Team
        lines.append(
            f"INSERT INTO dbo.Teams (TeamCode, TeamName, Country, FoundedYear, IsActive) VALUES "
            f"({sql_val(code)}, {sql_val(current_name)}, {sql_val(country)}, {2005 + TEAMS.index((code, name_2023, name_2024, country)) % 15}, 1);"
        )
    lines.append("GO")
    lines.append("")

    for code, name, city, country, capacity in VENUES:
        lines.append(
            f"INSERT INTO dbo.Venues (VenueCode, VenueName, City, Country, Capacity) VALUES "
            f"({sql_val(code)}, {sql_val(name)}, {sql_val(city)}, {sql_val(country)}, {sql_val(capacity)});"
        )
    lines.append("GO")
    lines.append("")

    for p in players:
        dob = p["dob"].isoformat() if p["dob"] is not None else None
        lines.append(
            "INSERT INTO dbo.Players (PlayerCode, FullName, DateOfBirth, Country, BattingStyle, "
            "BowlingStyle, PlayerRole, DebutDate) VALUES "
            f"({sql_val(p['code'])}, {sql_val(p['name'])}, {sql_val(dob)}, {sql_val(p['country'])}, "
            f"{sql_val(p['batting_style'])}, {sql_val(p['bowling_style'])}, {sql_val(p['role'])}, "
            f"{sql_val(p['debut'].isoformat())});"
        )
    lines.append("GO")

    path.write_text("\n".join(lines) + "\n", encoding="utf-8")


def write_baseline_malformed_files(matches_dir: Path) -> None:
    (matches_dir / "MALFORMED_broken_syntax.json").write_text(
        '{\n  "match_id": "M9001",\n  "season": "2023",\n  "teams": [\n    {"code": "MUM", "name": "Mumbai Sharks"},\n  ]\n', # trailing comma, unclosed braces
        encoding="utf-8",
    )
    (matches_dir / "MALFORMED_missing_match_id.json").write_text(
        json.dumps({
            "season": "2023", "format": "T20", "date": "2023-05-01",
            "venue": {"code": "MUM01"},
            "teams": [{"code": "MUM", "name": "Mumbai Sharks"}, {"code": "CHE", "name": "Chennai Kings"}],
        }, indent=2),
        encoding="utf-8",
    )
    csv_dir = SOURCE_DIR / "csv" / "deliveries"
    with (csv_dir / "MALFORMED_wrong_columns.csv").open("w", newline="", encoding="utf-8") as f:
        f.write("match_id,innings_no,over_no,ball_no,batsman_code,bowler_code,runs_off_bat\n")
        f.write("M0001,1,1,1,P0001,P0002,4,EXTRA_COLUMN,ANOTHER\n")
        f.write("M0001,1,1\n")


def write_demo_changes(matches, deliveries_by_season, players, team_name_lookup) -> None:
    demo_dir = SOURCE_DIR / "demo_changes"

    # new_matches: one match not present in the baseline dataset.
    new_match_id = "M0121"
    new_date = date(2025, 12, 15)
    record, deliveries = simulate_match(
        new_match_id, "2025", new_date, "MUM", "CHE", "MUM01",
        {s: {c: [p for p in players if p["home_team"] == c][:11] for c, *_ in TEAMS} for s in SEASONS},
        team_name_lookup,
    )
    write_json(demo_dir / "new_matches" / f"{new_match_id}.json", match_to_json_record(record))
    write_deliveries_csv(demo_dir / "new_matches" / f"deliveries_{new_match_id}.csv", deliveries)

    # corrected_files: a revised version of an already-loaded match, with a different result.
    original = matches[30]
    corrected = json.loads(json.dumps(match_to_json_record(original), default=str))
    corrected["result"]["winner"] = original["team_b"] if original["winner"] == original["team_a"] else original["team_a"]
    corrected["result"]["margin"] = (corrected["result"]["margin"] or 10) + 5
    corrected["innings"][0]["runs"] = corrected["innings"][0]["runs"] + 15
    write_json(demo_dir / "corrected_files" / f"{original['match_id']}.json", corrected)

    # duplicate_files: an exact copy of an already-loaded baseline file.
    dup_original = matches[50]
    write_json(demo_dir / "duplicate_files" / f"{dup_original['match_id']}.json", match_to_json_record(dup_original))

    # malformed_files: broken JSON, wrong-schema CSV, and JSON missing its match identity.
    malformed_dir = demo_dir / "malformed_files"
    malformed_dir.mkdir(parents=True, exist_ok=True)
    (malformed_dir / "M0999_broken.json").write_text(
        '{"match_id": "M0999", "teams": [{"code": "MUM"} "missing_comma_above"]}',
        encoding="utf-8",
    )
    (malformed_dir / "M0998_missing_identity.json").write_text(
        json.dumps({"season": "2025", "format": "T20", "teams": [{"code": "KOL"}, {"code": "BLR"}]}, indent=2),
        encoding="utf-8",
    )
    with (malformed_dir / "MALFORMED_deliveries_wrong_schema.csv").open("w", newline="", encoding="utf-8") as f:
        f.write("match_id,innings_no,over_no\n")
        f.write("M0997,1,1,extra,columns,here\n")


def write_documentation(players, matches) -> None:
    dob_missing = [p["code"] for p in players if p["dob"] is None]
    future_dob_player = players[3]
    abandoned_match = next(m for m in matches if m["result_method"] == "Abandoned")
    no_result_match = next(m for m in matches if m["result_method"] == "NoResult")
    tied_match = next(m for m in matches if m["result_method"] == "Tied")
    super_over_match = next(m for m in matches if m["result_method"] == "SuperOver")
    not_out_example = next(m for m in matches if m["result_method"] == "Normal")
    path = SOURCE_DIR / "DATA_QUALITY_ISSUES.md"
    path.write_text(f"""# Data Quality Issues Catalogue

Generated by `02_SampleData/generator/generate_sample_data.py`. Every issue below is planted deliberately in
the baseline dataset, so the actual file and record are listed rather than a generic description.

Handling is implemented by Alteryx workflow `04_dq_validation` with the rules in `config.DQRule`
(`01_Setup/sql/06_dq_metadata_schema.sql`); see `07_Docs/steps/04_data_quality.md`. Every rule outcome is
logged to `audit.Audit_DQException`. The cross-source consistency rules (scorecard totals vs ball-by-ball)
also detect DQ04 and DQ06 independently, without knowing they were planted. One issue that was not planted
was found later by the warehouse reconciliation - the same batsman dismissed twice in one innings - and is now
caught by rule `batsman_dismissed_twice` (Flagged).

## Injected issues

| ID | File / Table | Issue Type | Detail | Expected Handling |
|---|---|---|---|---|
| DQ01 | `sql_server/seed_data.sql` | Missing information | Players {', '.join(dob_missing)} have no date of birth | Loads with DOB NULL; logged with rule `missing_date_of_birth` (Flagged) |
| DQ02 | `sql_server/seed_data.sql` | Invalid value | Player {future_dob_player['code']} ({future_dob_player['name']}) has a date of birth in the future | Logged with rule `future_date_of_birth` (Defaulted): the player loads with DOB NULL, so his deliveries are not orphaned |
| DQ03 | `json/matches/{matches[5]['match_id']}.json` | Missing information | Second innings is missing its `runs` field | Innings rejected (`missing_required_field`); match header still loads; match flagged `InningsStatus = Incomplete`, and its ball-by-ball held (those deliveries would have no innings) |
| DQ04 | `json/matches/{matches[7]['match_id']}.json` | Invalid value | First innings reports 11 wickets | Innings rejected (`wickets_exceed_ten`); also flagged `innings_wickets_mismatch` against the ball-by-ball, so the match's ball-by-ball is held; match flagged Incomplete |
| DQ05 | `json/matches/{matches[12]['match_id']}.json` | Incorrect relationship | References team code `XYZ`, absent from `CricketSource.Teams` | Match rejected (`orphan_team_reference`, `winner_not_participant`); its innings (`parent_match_rejected`) and deliveries (`orphan_match_reference`) rejected; file status `Rejected` |
| DQ06 | `csv/deliveries/` | Invalid value | One delivery has `runs_off_bat = -1` | Delivery rejected (`negative_runs`); the match is the unit of acceptance, so all of that match's ball-by-ball is held (`match_ballbyball_held`); the scorecard mismatch is flagged (`innings_runs_mismatch`) |
| DQ07 | `csv/deliveries/` | Incorrect relationship | One delivery references batsman code `P9999`, not in `CricketSource.Players` | Delivery rejected (`orphan_player_reference`), and that match's ball-by-ball held; the same code in `historical_stats.csv` is also rejected |
| DQ08 | `json/matches/{matches[10]['match_id']}.json` and `{matches[10]['match_id']}_redelivered.json` | Duplicate | Identical match content delivered under two filenames | Second file detected by content hash (`duplicate_file`, Rejected); file status `Duplicate`; the first file loads |
| DQ09 | `csv/player_rankings/player_rankings.csv` | Inconsistent format | Player {players[1]['code']} ({players[1]['name']}) appears in upper case, unlike the SQL master | Not checked: `player_name` is not staged, and names in the warehouse come from the `CricketSource` master (design decision) |
| DQ10 | `csv/player_rankings/player_rankings.csv` vs. `csv/historical_stats/historical_stats.csv` | Inconsistent format | Ranking dates are `dd/mm/yyyy`; historical stats dates are ISO `yyyy-mm-dd` | Both parsed per their documented format in `CSV_SCHEMA.md` (rankings with style 103); `invalid_date` fires only if a date does not parse |
| DQ11 | `json/matches/MALFORMED_broken_syntax.json` | Malformed file | Invalid JSON syntax (unclosed structure) | 02 parses it partially (as match `M9001`); rejected with `missing_required_field`; file status `Rejected`; rest of the batch proceeds. Moving the file to the runtime error folder is not implemented yet |
| DQ12 | `json/matches/MALFORMED_missing_match_id.json` | Malformed file | Valid JSON, but no `match_id` field | Rejected (`missing_match_identity`); file status `Rejected` |
| DQ13 | `csv/deliveries/MALFORMED_wrong_columns.csv` | Malformed file | Rows with inconsistent column counts | Never staged by 03; 04 rejects it with `schema_mismatch` (header matches no `config.DQEntity.ExpectedHeader`); file status `Rejected` |

## Legitimate edge cases (must not be treated as errors)

| Case | Where | Why It's Valid |
|---|---|---|
| Abandoned match, null winner, no innings at all | `json/matches/{abandoned_match['match_id']}.json` | No play occurred; `result.method = "Abandoned"`, `innings` is an empty array. Not missing data - there was nothing to record. |
| No-result match, one innings only | `json/matches/{no_result_match['match_id']}.json` | Play started and was called off before a second innings; `result.method = "NoResult"`, `innings` has one element, not two. |
| Tied match | `json/matches/{tied_match['match_id']}.json` | Both innings scored the same total; `result.method = "Tied"`, winner is null - a real, valid outcome. |
| Super over match | `json/matches/{super_over_match['match_id']}.json` | Main innings tied; `result.method = "SuperOver"` with a winner assigned despite the tied score. |
| Not-out batsman | Every completed innings that ends on overs rather than all-out, e.g. `json/matches/{not_out_example['match_id']}.json` | The not-out batsman has no `dismissal_type` in the ball-by-ball data - absence of a value is correct here. |
| All-rounder in both batting and bowling facts | Any player with `role = "AllRounder"` | Expected - they contribute in both disciplines within the same match. |
| Sparse ball-by-ball for a demo-only match | `demo_changes/new_matches/` | A file arriving standalone, outside the normal season batch, is still a valid delivery. |
""", encoding="utf-8")

    sql_setup_path = SOURCE_DIR / "sql_server" / "SQL_SERVER_SETUP.md"
    sql_setup_path.write_text("""# SQL Server Setup

`CricketSource` holds the master/reference data seeded by `seed_data.sql`. Setup is handled entirely by
`01_Setup/setup_database.bat`, which reads the instance name and authentication mode from
`config/local.config`.

## Steps

1. Copy `config/local.config.example` to `config/local.config` and set `SQL_INSTANCE` to your instance
   name (for example `localhost`, `.\\SQLEXPRESS`, or a named instance).
2. Run `01_Setup/check_prerequisites.bat` to confirm `sqlcmd` (go-sqlcmd) and the ODBC Driver 17 for
   SQL Server are available.
3. Run `01_Setup/setup_database.bat`. This creates `CricketSource` and `CricketDW`, runs every script in
   `01_Setup/sql/` in order, and seeds `CricketSource` from `seed_data.sql`.

## Verification

```sql
USE CricketSource;
SELECT COUNT(*) AS TeamCount FROM dbo.Teams;      -- expect 8
SELECT COUNT(*) AS VenueCount FROM dbo.Venues;    -- expect 8
SELECT COUNT(*) AS PlayerCount FROM dbo.Players;  -- expect 150ish, see CricketSource_SCHEMA.md
```

## Troubleshooting

- **`sqlcmd` not found**: install go-sqlcmd (`winget install sqlcmd`) and open a new terminal. See
  `07_Docs/deployment.md` Prerequisites.
- **Login failed**: check `SQL_AUTH_MODE` in `config/local.config` matches how your instance is
  configured (Windows Authentication is the default).
""", encoding="utf-8")

    schema_path = SOURCE_DIR / "sql_server" / "CricketSource_SCHEMA.md"
    schema_path.write_text(f"""# CricketSource Schema

## dbo.Teams

| Column | Type | Nullable | Key | Meaning |
|---|---|---|---|---|
| TeamId | INT IDENTITY | No | PK | Surrogate key |
| TeamCode | VARCHAR(10) | No | Natural key | Stable across renames |
| TeamName | VARCHAR(100) | No | | Current display name |
| Country | VARCHAR(50) | Yes | | |
| FoundedYear | INT | Yes | | |
| IsActive | BIT | No | | |

Row count: {len(TEAMS)}. One team (DEL) has a different name in `json/matches/` files from season 2023
versus 2024 onward - `CricketSource.Teams` reflects only the current name; the historical name is
recovered from match data by `Dim_Team`'s Type-2 SCD tracking.

## dbo.Players

| Column | Type | Nullable | Key | Meaning |
|---|---|---|---|---|
| PlayerId | INT IDENTITY | No | PK | Surrogate key |
| PlayerCode | VARCHAR(20) | No | Natural key | |
| FullName | VARCHAR(150) | No | | |
| DateOfBirth | DATE | Yes | | Planted missing-data case: 5 players have no value |
| Country | VARCHAR(50) | Yes | | |
| BattingStyle | VARCHAR(30) | Yes | | |
| BowlingStyle | VARCHAR(30) | Yes | | Null for pure batters |
| PlayerRole | VARCHAR(30) | Yes | | Batter / Bowler / AllRounder / WicketKeeper |
| DebutDate | DATE | Yes | | |

Row count: {len(players)}.

## dbo.Venues

| Column | Type | Nullable | Key | Meaning |
|---|---|---|---|---|
| VenueId | INT IDENTITY | No | PK | Surrogate key |
| VenueCode | VARCHAR(20) | No | Natural key | |
| VenueName | VARCHAR(150) | No | | |
| City | VARCHAR(100) | Yes | | Planted missing-data case: HYD01 has no value |
| Country | VARCHAR(50) | Yes | | |
| Capacity | INT | Yes | | |

Row count: {len(VENUES)}.
""", encoding="utf-8")

    json_schema_path = SOURCE_DIR / "json" / "JSON_SCHEMA.md"
    json_schema_path.write_text("""# Match JSON Schema

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
""", encoding="utf-8")

    schema_json = {
        "$schema": "http://json-schema.org/draft-07/schema#",
        "title": "Cricket match",
        "type": "object",
        "required": ["match_id", "season", "format", "date", "venue", "teams", "toss", "result", "innings"],
        "properties": {
            "match_id": {"type": "string"},
            "season": {"type": "string"},
            "format": {"type": "string", "enum": ["T20", "ODI", "Test", "T10"]},
            "date": {"type": "string", "format": "date"},
            "venue": {"type": "object", "required": ["code"], "properties": {"code": {"type": "string"}}},
            "teams": {
                "type": "array", "minItems": 2, "maxItems": 2,
                "items": {
                    "type": "object", "required": ["code", "name"],
                    "properties": {"code": {"type": "string"}, "name": {"type": "string"}},
                },
            },
            "toss": {
                "type": "object", "required": ["winner", "decision"],
                "properties": {"winner": {"type": "string"}, "decision": {"type": "string", "enum": ["Bat", "Field"]}},
            },
            "result": {
                "type": "object", "required": ["method"],
                "properties": {
                    "method": {"type": "string", "enum": ["Normal", "Tied", "NoResult", "Abandoned", "SuperOver"]},
                    "winner": {"type": ["string", "null"]},
                    "margin": {"type": ["number", "null"]},
                    "margin_type": {"type": ["string", "null"], "enum": ["Runs", "Wickets", None]},
                    "man_of_match": {"type": ["string", "null"]},
                },
            },
            "innings": {
                "type": "array", "maxItems": 2,
                "items": {
                    "type": "object", "required": ["innings_no", "batting_team", "bowling_team", "wickets", "overs", "extras"],
                    "properties": {
                        "innings_no": {"type": "integer"},
                        "batting_team": {"type": "string"},
                        "bowling_team": {"type": "string"},
                        "runs": {"type": "integer"},
                        "wickets": {"type": "integer", "minimum": 0},
                        "overs": {"type": "number"},
                        "extras": {"type": "integer"},
                    },
                },
            },
        },
    }
    (SOURCE_DIR / "json" / "match.schema.json").write_text(json.dumps(schema_json, indent=2), encoding="utf-8")

    csv_schema_path = SOURCE_DIR / "csv" / "CSV_SCHEMA.md"
    csv_schema_path.write_text("""# CSV Schema

## deliveries/deliveries_<season>.csv

One row per legal or extra delivery. Grain: match + innings + over + ball (extras share the ball number
of the legal delivery they preceded, since they don't advance the over).

| Column | Type | Notes |
|---|---|---|
| match_id | string | Foreign key to the match JSON's `match_id` |
| innings_no | integer | 1 or 2 |
| over_no | integer | 1-20 |
| ball_no | integer | Sequence within the over, counting every delivery attempt including wides/no-balls - not capped at 6, since an over with an extra has more than six deliveries |
| batsman_code | string | Foreign key to CricketSource.Players |
| bowler_code | string | Foreign key to CricketSource.Players |
| runs_off_bat | integer | Can be negative in one planted invalid-value case |
| extra_runs | integer | 0 or 1 |
| extra_type | string | "Wide", "NoBall", or blank |
| is_wicket | string | "Y" or "N" |
| dismissal_type | string | Blank when not a wicket |
| dismissed_player_code | string | Blank when not a wicket |

## player_rankings/player_rankings.csv

Grain: player + format + discipline + ranking date.

| Column | Type | Notes |
|---|---|---|
| player_code | string | Foreign key to CricketSource.Players |
| player_name | string | Redundant display name - one planted casing mismatch against the SQL master |
| format_code | string | |
| discipline | string | Batting / Bowling / AllRounder |
| ranking_date | string | **dd/mm/yyyy** - deliberately different format from historical_stats.csv |
| rank_position | integer | |
| rating_points | integer | |

## historical_stats/historical_stats.csv

Grain: player + season + format.

| Column | Type | Notes |
|---|---|---|
| player_code | string | Foreign key to CricketSource.Players |
| player_name | string | |
| season | string | |
| format_code | string | |
| matches_played | integer | |
| runs_scored | integer | |
| wickets_taken | integer | |
| season_start_date | string | **yyyy-mm-dd** (ISO) - deliberately different format from player_rankings.csv |
""", encoding="utf-8")

    demo_readme_path = SOURCE_DIR / "demo_changes" / "README.md"
    demo_readme_path.write_text(f"""# 02_SampleData/source/demo_changes

The "Additional data" - files held back from the baseline build and pre-staged for the live demo, so
the Additional Challenge has a rehearsed, verifiable outcome rather than an improvised one.

| Folder | File(s) | Expected outcome when staged and the orchestration macro is run |
|---|---|---|
| `new_matches/` | `M0121.json`, `deliveries_M0121.csv` | A new match appears: `Fact_MatchResult` gains one row, `Fact_BallByBall` gains its deliveries, all five dashboards reflect it |
| `corrected_files/` | `{matches[30]['match_id']}.json` | The existing match's result and first-innings score change; every dependent fact row for this match is replaced, not merged |
| `duplicate_files/` | `{matches[50]['match_id']}.json` | No change to the warehouse; `Audit_FileControl` logs a `Duplicate` status for this file |
| `malformed_files/` | `M0999_broken.json`, `M0998_missing_identity.json`, `MALFORMED_deliveries_wrong_schema.csv` | All three are quarantined with a logged reason; no other file in the same run is affected |

To use one: run `02_SampleData/stage_demo_change.bat <category>`, then open the orchestration macro in
`03_Alteryx/macros/` in Designer and run it - the same way as any other pipeline run.
""", encoding="utf-8")


if __name__ == "__main__":
    main()
