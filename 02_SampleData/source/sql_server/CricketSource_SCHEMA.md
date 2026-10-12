# CricketSource Schema

## dbo.Teams

| Column | Type | Nullable | Key | Meaning |
|---|---|---|---|---|
| TeamId | INT IDENTITY | No | PK | Surrogate key |
| TeamCode | VARCHAR(10) | No | Natural key | Stable across renames |
| TeamName | VARCHAR(100) | No | | Current display name |
| Country | VARCHAR(50) | Yes | | |
| FoundedYear | INT | Yes | | |
| IsActive | BIT | No | | |

Row count: 8. One team (DEL) has a different name in `json/matches/` files from season 2023
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

Row count: 152.

## dbo.Venues

| Column | Type | Nullable | Key | Meaning |
|---|---|---|---|---|
| VenueId | INT IDENTITY | No | PK | Surrogate key |
| VenueCode | VARCHAR(20) | No | Natural key | |
| VenueName | VARCHAR(150) | No | | |
| City | VARCHAR(100) | Yes | | Planted missing-data case: HYD01 has no value |
| Country | VARCHAR(50) | Yes | | |
| Capacity | INT | Yes | | |

Row count: 8.
