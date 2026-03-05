local sql = require("sql")

local DB_ID = "app.lc:db"

--- Initialize the database schema.
local function init_schema()
    local db, err = sql.get(DB_ID)
    if err then return nil, err end

    db:execute([[
        CREATE TABLE IF NOT EXISTS players (
            puuid TEXT PRIMARY KEY,
            game_name TEXT NOT NULL,
            tag_line TEXT NOT NULL,
            summoner_id TEXT,
            summoner_level INTEGER,
            profile_icon_id INTEGER,
            revision_date INTEGER,
            platform TEXT DEFAULT 'EUW1',
            region TEXT DEFAULT 'EUROPE',
            updated_at TEXT NOT NULL DEFAULT (datetime('now'))
        )
    ]])

    db:execute([[
        CREATE TABLE IF NOT EXISTS player_ranked (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            puuid TEXT NOT NULL,
            queue_type TEXT NOT NULL,
            tier TEXT,
            rank TEXT,
            league_points INTEGER DEFAULT 0,
            wins INTEGER DEFAULT 0,
            losses INTEGER DEFAULT 0,
            hot_streak INTEGER DEFAULT 0,
            veteran INTEGER DEFAULT 0,
            fresh_blood INTEGER DEFAULT 0,
            updated_at TEXT NOT NULL DEFAULT (datetime('now')),
            UNIQUE(puuid, queue_type)
        )
    ]])

    db:execute([[
        CREATE TABLE IF NOT EXISTS player_mastery (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            puuid TEXT NOT NULL,
            champion_id INTEGER NOT NULL,
            champion_level INTEGER DEFAULT 0,
            champion_points INTEGER DEFAULT 0,
            updated_at TEXT NOT NULL DEFAULT (datetime('now')),
            UNIQUE(puuid, champion_id)
        )
    ]])

    db:execute([[
        CREATE TABLE IF NOT EXISTS matches (
            match_id TEXT PRIMARY KEY,
            puuid TEXT NOT NULL,
            champion_id INTEGER,
            champion_name TEXT,
            kills INTEGER DEFAULT 0,
            deaths INTEGER DEFAULT 0,
            assists INTEGER DEFAULT 0,
            cs INTEGER DEFAULT 0,
            vision_score INTEGER DEFAULT 0,
            total_damage INTEGER DEFAULT 0,
            gold_earned INTEGER DEFAULT 0,
            win INTEGER DEFAULT 0,
            game_duration INTEGER DEFAULT 0,
            game_mode TEXT,
            queue_id INTEGER,
            position TEXT,
            items TEXT,
            game_creation INTEGER,
            created_at TEXT NOT NULL DEFAULT (datetime('now'))
        )
    ]])

    db:execute([[
        CREATE INDEX IF NOT EXISTS idx_matches_puuid
        ON matches(puuid, game_creation DESC)
    ]])

    db:execute([[
        CREATE INDEX IF NOT EXISTS idx_ranked_puuid
        ON player_ranked(puuid)
    ]])

    db:execute([[
        CREATE INDEX IF NOT EXISTS idx_mastery_puuid
        ON player_mastery(puuid, champion_points DESC)
    ]])

    -- Match participants (all 10 players per match)
    db:execute([[
        CREATE TABLE IF NOT EXISTS match_participants (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            match_id TEXT NOT NULL,
            puuid TEXT,
            team_id INTEGER,
            champion_id INTEGER,
            champion_name TEXT,
            summoner_name TEXT,
            tag_line TEXT,
            kills INTEGER DEFAULT 0,
            deaths INTEGER DEFAULT 0,
            assists INTEGER DEFAULT 0,
            cs INTEGER DEFAULT 0,
            total_damage INTEGER DEFAULT 0,
            gold_earned INTEGER DEFAULT 0,
            vision_score INTEGER DEFAULT 0,
            position TEXT,
            win INTEGER DEFAULT 0,
            items TEXT,
            summoner1 INTEGER DEFAULT 0,
            summoner2 INTEGER DEFAULT 0,
            UNIQUE(match_id, puuid)
        )
    ]])

    db:execute([[
        CREATE INDEX IF NOT EXISTS idx_match_participants_match
        ON match_participants(match_id)
    ]])

    -- Player challenges cache
    db:execute([[
        CREATE TABLE IF NOT EXISTS player_challenges (
            puuid TEXT PRIMARY KEY,
            level TEXT,
            current_points INTEGER DEFAULT 0,
            max_points INTEGER DEFAULT 0,
            percentile REAL,
            updated_at TEXT NOT NULL DEFAULT (datetime('now'))
        )
    ]])

    -- Add new columns to matches (ignore errors if already exist)
    pcall(function() db:execute("ALTER TABLE matches ADD COLUMN summoner1 INTEGER DEFAULT 0") end)
    pcall(function() db:execute("ALTER TABLE matches ADD COLUMN summoner2 INTEGER DEFAULT 0") end)
    pcall(function() db:execute("ALTER TABLE matches ADD COLUMN cs_per_min REAL DEFAULT 0") end)
    -- Multi-kills
    pcall(function() db:execute("ALTER TABLE matches ADD COLUMN double_kills INTEGER DEFAULT 0") end)
    pcall(function() db:execute("ALTER TABLE matches ADD COLUMN triple_kills INTEGER DEFAULT 0") end)
    pcall(function() db:execute("ALTER TABLE matches ADD COLUMN quadra_kills INTEGER DEFAULT 0") end)
    pcall(function() db:execute("ALTER TABLE matches ADD COLUMN penta_kills INTEGER DEFAULT 0") end)
    -- Damage breakdown
    pcall(function() db:execute("ALTER TABLE matches ADD COLUMN physical_damage INTEGER DEFAULT 0") end)
    pcall(function() db:execute("ALTER TABLE matches ADD COLUMN magic_damage INTEGER DEFAULT 0") end)
    pcall(function() db:execute("ALTER TABLE matches ADD COLUMN true_damage INTEGER DEFAULT 0") end)
    pcall(function() db:execute("ALTER TABLE matches ADD COLUMN damage_taken INTEGER DEFAULT 0") end)
    -- Wards
    pcall(function() db:execute("ALTER TABLE matches ADD COLUMN wards_placed INTEGER DEFAULT 0") end)
    pcall(function() db:execute("ALTER TABLE matches ADD COLUMN wards_killed INTEGER DEFAULT 0") end)
    pcall(function() db:execute("ALTER TABLE matches ADD COLUMN control_wards INTEGER DEFAULT 0") end)
    -- Challenges per match
    pcall(function() db:execute("ALTER TABLE matches ADD COLUMN kill_participation REAL DEFAULT 0") end)
    pcall(function() db:execute("ALTER TABLE matches ADD COLUMN damage_share REAL DEFAULT 0") end)
    pcall(function() db:execute("ALTER TABLE matches ADD COLUMN gold_per_min REAL DEFAULT 0") end)
    pcall(function() db:execute("ALTER TABLE matches ADD COLUMN damage_per_min REAL DEFAULT 0") end)
    -- Runes
    pcall(function() db:execute("ALTER TABLE matches ADD COLUMN perks_primary_style INTEGER DEFAULT 0") end)
    pcall(function() db:execute("ALTER TABLE matches ADD COLUMN perks_sub_style INTEGER DEFAULT 0") end)
    pcall(function() db:execute("ALTER TABLE matches ADD COLUMN perks_keystone INTEGER DEFAULT 0") end)
    pcall(function() db:execute("ALTER TABLE matches ADD COLUMN champ_level INTEGER DEFAULT 0") end)
    pcall(function() db:execute("ALTER TABLE matches ADD COLUMN gold_spent INTEGER DEFAULT 0") end)
    -- Surrender/first blood
    pcall(function() db:execute("ALTER TABLE matches ADD COLUMN game_ended_surrender INTEGER DEFAULT 0") end)
    pcall(function() db:execute("ALTER TABLE matches ADD COLUMN first_blood INTEGER DEFAULT 0") end)
    -- Challenges-based stats
    pcall(function() db:execute("ALTER TABLE matches ADD COLUMN solo_kills INTEGER DEFAULT 0") end)
    pcall(function() db:execute("ALTER TABLE matches ADD COLUMN turret_plates INTEGER DEFAULT 0") end)
    pcall(function() db:execute("ALTER TABLE matches ADD COLUMN dragon_takedowns INTEGER DEFAULT 0") end)
    pcall(function() db:execute("ALTER TABLE matches ADD COLUMN baron_takedowns INTEGER DEFAULT 0") end)
    pcall(function() db:execute("ALTER TABLE matches ADD COLUMN rift_herald_takedowns INTEGER DEFAULT 0") end)
    pcall(function() db:execute("ALTER TABLE matches ADD COLUMN vision_per_min REAL DEFAULT 0") end)
    pcall(function() db:execute("ALTER TABLE matches ADD COLUMN lane_minions_first10 INTEGER DEFAULT 0") end)
    pcall(function() db:execute("ALTER TABLE matches ADD COLUMN max_cs_advantage REAL DEFAULT 0") end)
    pcall(function() db:execute("ALTER TABLE matches ADD COLUMN max_level_lead INTEGER DEFAULT 0") end)
    pcall(function() db:execute("ALTER TABLE matches ADD COLUMN turret_takedowns INTEGER DEFAULT 0") end)
    pcall(function() db:execute("ALTER TABLE matches ADD COLUMN inhibitor_takedowns INTEGER DEFAULT 0") end)

    -- Match participants extra columns
    pcall(function() db:execute("ALTER TABLE match_participants ADD COLUMN double_kills INTEGER DEFAULT 0") end)
    pcall(function() db:execute("ALTER TABLE match_participants ADD COLUMN triple_kills INTEGER DEFAULT 0") end)
    pcall(function() db:execute("ALTER TABLE match_participants ADD COLUMN quadra_kills INTEGER DEFAULT 0") end)
    pcall(function() db:execute("ALTER TABLE match_participants ADD COLUMN penta_kills INTEGER DEFAULT 0") end)
    pcall(function() db:execute("ALTER TABLE match_participants ADD COLUMN physical_damage INTEGER DEFAULT 0") end)
    pcall(function() db:execute("ALTER TABLE match_participants ADD COLUMN magic_damage INTEGER DEFAULT 0") end)
    pcall(function() db:execute("ALTER TABLE match_participants ADD COLUMN true_damage INTEGER DEFAULT 0") end)
    pcall(function() db:execute("ALTER TABLE match_participants ADD COLUMN damage_taken INTEGER DEFAULT 0") end)
    pcall(function() db:execute("ALTER TABLE match_participants ADD COLUMN wards_placed INTEGER DEFAULT 0") end)
    pcall(function() db:execute("ALTER TABLE match_participants ADD COLUMN wards_killed INTEGER DEFAULT 0") end)
    pcall(function() db:execute("ALTER TABLE match_participants ADD COLUMN control_wards INTEGER DEFAULT 0") end)
    pcall(function() db:execute("ALTER TABLE match_participants ADD COLUMN kill_participation REAL DEFAULT 0") end)
    pcall(function() db:execute("ALTER TABLE match_participants ADD COLUMN damage_share REAL DEFAULT 0") end)
    pcall(function() db:execute("ALTER TABLE match_participants ADD COLUMN perks_keystone INTEGER DEFAULT 0") end)
    pcall(function() db:execute("ALTER TABLE match_participants ADD COLUMN perks_primary_style INTEGER DEFAULT 0") end)
    pcall(function() db:execute("ALTER TABLE match_participants ADD COLUMN perks_sub_style INTEGER DEFAULT 0") end)
    pcall(function() db:execute("ALTER TABLE match_participants ADD COLUMN champ_level INTEGER DEFAULT 0") end)

    -- Ranked extra columns
    pcall(function() db:execute("ALTER TABLE player_ranked ADD COLUMN hot_streak INTEGER DEFAULT 0") end)
    pcall(function() db:execute("ALTER TABLE player_ranked ADD COLUMN veteran INTEGER DEFAULT 0") end)
    pcall(function() db:execute("ALTER TABLE player_ranked ADD COLUMN fresh_blood INTEGER DEFAULT 0") end)

    db:execute([[
        CREATE TABLE IF NOT EXISTS recent_searches (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            puuid TEXT NOT NULL,
            game_name TEXT NOT NULL,
            tag_line TEXT NOT NULL,
            summoner_level INTEGER,
            profile_icon_id INTEGER,
            platform TEXT DEFAULT 'EUW1',
            searched_at TEXT NOT NULL DEFAULT (datetime('now')),
            UNIQUE(puuid)
        )
    ]])

    -- LP history for ranked progression tracking
    db:execute([[
        CREATE TABLE IF NOT EXISTS ranked_history (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            puuid TEXT NOT NULL,
            queue_type TEXT NOT NULL,
            tier TEXT,
            rank TEXT,
            league_points INTEGER DEFAULT 0,
            wins INTEGER DEFAULT 0,
            losses INTEGER DEFAULT 0,
            recorded_at TEXT NOT NULL DEFAULT (datetime('now'))
        )
    ]])

    db:execute([[
        CREATE INDEX IF NOT EXISTS idx_ranked_history_puuid
        ON ranked_history(puuid, queue_type, recorded_at DESC)
    ]])

    -- DDragon cache table
    db:execute([[
        CREATE TABLE IF NOT EXISTS ddragon_cache (
            cache_key TEXT PRIMARY KEY,
            data TEXT NOT NULL,
            version TEXT,
            updated_at TEXT NOT NULL DEFAULT (datetime('now'))
        )
    ]])

    -- Index for duo partner analysis
    db:execute([[
        CREATE INDEX IF NOT EXISTS idx_match_participants_puuid
        ON match_participants(puuid)
    ]])

    -- Favorites table (#18)
    db:execute([[
        CREATE TABLE IF NOT EXISTS favorites (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            puuid TEXT NOT NULL UNIQUE,
            game_name TEXT NOT NULL,
            tag_line TEXT NOT NULL,
            platform TEXT DEFAULT 'EUW1',
            region TEXT DEFAULT 'EUROPE',
            note TEXT DEFAULT '',
            created_at TEXT NOT NULL DEFAULT (datetime('now'))
        )
    ]])

    -- Match notes table (#27)
    db:execute([[
        CREATE TABLE IF NOT EXISTS match_notes (
            match_id TEXT NOT NULL,
            puuid TEXT NOT NULL,
            note TEXT NOT NULL DEFAULT '',
            updated_at TEXT NOT NULL DEFAULT (datetime('now')),
            PRIMARY KEY (match_id, puuid)
        )
    ]])

    -- Goals table (#26)
    db:execute([[
        CREATE TABLE IF NOT EXISTS player_goals (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            puuid TEXT NOT NULL,
            goal_type TEXT NOT NULL,
            target_value TEXT NOT NULL,
            current_value TEXT DEFAULT '',
            completed INTEGER DEFAULT 0,
            created_at TEXT NOT NULL DEFAULT (datetime('now')),
            completed_at TEXT
        )
    ]])

    db:release()
    return {ok = true}
end

--- Get player profile by PUUID.
local function get_player(input)
    if not input or not input.puuid then
        return {error = "puuid is required"}
    end

    local db, err = sql.get(DB_ID)
    if err then return {error = tostring(err)} end

    local rows, qerr = db:query(
        "SELECT * FROM players WHERE puuid = ? LIMIT 1",
        {input.puuid}
    )
    db:release()

    if qerr then return {error = tostring(qerr)} end
    if not rows or #rows == 0 then return nil end

    return rows[1]
end

--- Save or update player profile.
local function save_player(input)
    if not input or not input.puuid then
        return {error = "puuid is required"}
    end

    local db, err = sql.get(DB_ID)
    if err then return {error = tostring(err)} end

    local _, exec_err = db:execute([[
        INSERT INTO players (puuid, game_name, tag_line, summoner_id, summoner_level, profile_icon_id, revision_date, platform, region, updated_at)
        VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, datetime('now'))
        ON CONFLICT(puuid) DO UPDATE SET
            game_name = excluded.game_name,
            tag_line = excluded.tag_line,
            summoner_id = excluded.summoner_id,
            summoner_level = excluded.summoner_level,
            profile_icon_id = excluded.profile_icon_id,
            revision_date = excluded.revision_date,
            platform = excluded.platform,
            region = excluded.region,
            updated_at = datetime('now')
    ]], {
        input.puuid,
        input.game_name or "",
        input.tag_line or "",
        input.summoner_id,
        input.summoner_level,
        input.profile_icon_id,
        input.revision_date,
        input.platform or "EUW1",
        input.region or "EUROPE",
    })
    db:release()

    if exec_err then return {error = tostring(exec_err)} end
    return {ok = true}
end

--- Get player ranked data.
local function get_ranked(input)
    if not input or not input.puuid then
        return {error = "puuid is required"}
    end

    local db, err = sql.get(DB_ID)
    if err then return {error = tostring(err)} end

    local rows, qerr = db:query(
        "SELECT * FROM player_ranked WHERE puuid = ? ORDER BY queue_type",
        {input.puuid}
    )
    db:release()

    if qerr then return {error = tostring(qerr)} end
    return rows or {}
end

--- Save or update ranked data for a player.
local function save_ranked(input)
    if not input or not input.puuid or not input.queue_type then
        return {error = "puuid and queue_type are required"}
    end

    local db, err = sql.get(DB_ID)
    if err then return {error = tostring(err)} end

    local _, exec_err = db:execute([[
        INSERT INTO player_ranked (puuid, queue_type, tier, rank, league_points, wins, losses, hot_streak, veteran, fresh_blood, updated_at)
        VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, datetime('now'))
        ON CONFLICT(puuid, queue_type) DO UPDATE SET
            tier = excluded.tier,
            rank = excluded.rank,
            league_points = excluded.league_points,
            wins = excluded.wins,
            losses = excluded.losses,
            hot_streak = excluded.hot_streak,
            veteran = excluded.veteran,
            fresh_blood = excluded.fresh_blood,
            updated_at = datetime('now')
    ]], {
        input.puuid,
        input.queue_type,
        input.tier,
        input.rank,
        input.league_points or 0,
        input.wins or 0,
        input.losses or 0,
        input.hot_streak and 1 or 0,
        input.veteran and 1 or 0,
        input.fresh_blood and 1 or 0,
    })
    db:release()

    if exec_err then return {error = tostring(exec_err)} end
    return {ok = true}
end

--- Get champion mastery for a player.
local function get_mastery(input)
    if not input or not input.puuid then
        return {error = "puuid is required"}
    end

    local limit = input.limit or 10

    local db, err = sql.get(DB_ID)
    if err then return {error = tostring(err)} end

    local rows, qerr = db:query(
        "SELECT * FROM player_mastery WHERE puuid = ? ORDER BY champion_points DESC LIMIT ?",
        {input.puuid, limit}
    )
    db:release()

    if qerr then return {error = tostring(qerr)} end
    return rows or {}
end

--- Save or update champion mastery.
local function save_mastery(input)
    if not input or not input.puuid or not input.champion_id then
        return {error = "puuid and champion_id are required"}
    end

    local db, err = sql.get(DB_ID)
    if err then return {error = tostring(err)} end

    local _, exec_err = db:execute([[
        INSERT INTO player_mastery (puuid, champion_id, champion_level, champion_points, updated_at)
        VALUES (?, ?, ?, ?, datetime('now'))
        ON CONFLICT(puuid, champion_id) DO UPDATE SET
            champion_level = excluded.champion_level,
            champion_points = excluded.champion_points,
            updated_at = datetime('now')
    ]], {
        input.puuid,
        input.champion_id,
        input.champion_level or 0,
        input.champion_points or 0,
    })
    db:release()

    if exec_err then return {error = tostring(exec_err)} end
    return {ok = true}
end

--- Get recent matches for a player.
local function get_matches(input)
    if not input or not input.puuid then
        return {error = "puuid is required"}
    end

    local limit = input.limit or 20

    local db, err = sql.get(DB_ID)
    if err then return {error = tostring(err)} end

    local rows, qerr = db:query(
        "SELECT * FROM matches WHERE puuid = ? ORDER BY game_creation DESC LIMIT ?",
        {input.puuid, limit}
    )
    db:release()

    if qerr then return {error = tostring(qerr)} end
    return rows or {}
end

--- Save a match record.
local function save_match(input)
    if not input or not input.match_id or not input.puuid then
        return {error = "match_id and puuid are required"}
    end

    local json = require("json")

    local db, err = sql.get(DB_ID)
    if err then return {error = tostring(err)} end

    local items_json = ""
    if input.items then
        items_json = json.encode(input.items)
    end

    local result, exec_err = db:execute([[
        INSERT OR IGNORE INTO matches
            (match_id, puuid, champion_id, champion_name, kills, deaths, assists,
             cs, vision_score, total_damage, gold_earned, win, game_duration,
             game_mode, queue_id, position, items, game_creation,
             summoner1, summoner2, cs_per_min,
             double_kills, triple_kills, quadra_kills, penta_kills,
             physical_damage, magic_damage, true_damage, damage_taken,
             wards_placed, wards_killed, control_wards,
             kill_participation, damage_share, gold_per_min, damage_per_min,
             perks_primary_style, perks_sub_style, perks_keystone,
             champ_level, gold_spent, game_ended_surrender, first_blood,
             solo_kills, turret_plates, dragon_takedowns, baron_takedowns,
             rift_herald_takedowns, vision_per_min, lane_minions_first10,
             max_cs_advantage, max_level_lead, turret_takedowns, inhibitor_takedowns)
        VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?,
                ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?,
                ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
    ]], {
        input.match_id,
        input.puuid,
        input.champion_id,
        input.champion_name,
        input.kills or 0,
        input.deaths or 0,
        input.assists or 0,
        input.cs or 0,
        input.vision_score or 0,
        input.total_damage or 0,
        input.gold_earned or 0,
        input.win and 1 or 0,
        input.game_duration or 0,
        input.game_mode,
        input.queue_id,
        input.position,
        items_json,
        input.game_creation,
        input.summoner1 or 0,
        input.summoner2 or 0,
        input.cs_per_min or 0,
        input.double_kills or 0,
        input.triple_kills or 0,
        input.quadra_kills or 0,
        input.penta_kills or 0,
        input.physical_damage or 0,
        input.magic_damage or 0,
        input.true_damage or 0,
        input.damage_taken or 0,
        input.wards_placed or 0,
        input.wards_killed or 0,
        input.control_wards or 0,
        input.kill_participation or 0,
        input.damage_share or 0,
        input.gold_per_min or 0,
        input.damage_per_min or 0,
        input.perks_primary_style or 0,
        input.perks_sub_style or 0,
        input.perks_keystone or 0,
        input.champ_level or 0,
        input.gold_spent or 0,
        input.game_ended_surrender and 1 or 0,
        input.first_blood and 1 or 0,
        input.solo_kills or 0,
        input.turret_plates or 0,
        input.dragon_takedowns or 0,
        input.baron_takedowns or 0,
        input.rift_herald_takedowns or 0,
        input.vision_per_min or 0,
        input.lane_minions_first10 or 0,
        input.max_cs_advantage or 0,
        input.max_level_lead or 0,
        input.turret_takedowns or 0,
        input.inhibitor_takedowns or 0,
    })
    db:release()

    if exec_err then return {error = tostring(exec_err)} end
    return {ok = true, inserted = (result.rows_affected > 0)}
end

--- List all tracked players with basic info.
local function list_tracked_players()
    local db, err = sql.get(DB_ID)
    if err then return {error = tostring(err)} end

    local rows, qerr = db:query([[
        SELECT p.*,
               (SELECT COUNT(*) FROM matches m WHERE m.puuid = p.puuid) as match_count
        FROM players p
        ORDER BY p.updated_at DESC
    ]])
    db:release()

    if qerr then return {error = tostring(qerr)} end
    return rows or {}
end

--- Save a recent search.
local function save_recent_search(input)
    if not input or not input.puuid then
        return {error = "puuid is required"}
    end

    local db, err = sql.get(DB_ID)
    if err then return {error = tostring(err)} end

    local _, exec_err = db:execute([[
        INSERT INTO recent_searches (puuid, game_name, tag_line, summoner_level, profile_icon_id, platform, searched_at)
        VALUES (?, ?, ?, ?, ?, ?, datetime('now'))
        ON CONFLICT(puuid) DO UPDATE SET
            game_name = excluded.game_name,
            tag_line = excluded.tag_line,
            summoner_level = excluded.summoner_level,
            profile_icon_id = excluded.profile_icon_id,
            platform = excluded.platform,
            searched_at = datetime('now')
    ]], {
        input.puuid,
        input.game_name or "",
        input.tag_line or "",
        input.summoner_level,
        input.profile_icon_id,
        input.platform or "EUW1",
    })
    db:release()

    if exec_err then return {error = tostring(exec_err)} end
    return {ok = true}
end

--- Get recent searches with ranked data.
local function get_recent_searches(input)
    local limit = (input and input.limit) or 10

    local db, err = sql.get(DB_ID)
    if err then return {error = tostring(err)} end

    local rows, qerr = db:query([[
        SELECT rs.*,
               pr_solo.tier as solo_tier, pr_solo.rank as solo_rank,
               pr_solo.league_points as solo_lp, pr_solo.wins as solo_wins, pr_solo.losses as solo_losses,
               pr_flex.tier as flex_tier, pr_flex.rank as flex_rank,
               pr_flex.league_points as flex_lp, pr_flex.wins as flex_wins, pr_flex.losses as flex_losses
        FROM recent_searches rs
        LEFT JOIN player_ranked pr_solo ON rs.puuid = pr_solo.puuid AND pr_solo.queue_type = 'RANKED_SOLO_5x5'
        LEFT JOIN player_ranked pr_flex ON rs.puuid = pr_flex.puuid AND pr_flex.queue_type = 'RANKED_FLEX_SR'
        ORDER BY rs.searched_at DESC
        LIMIT ?
    ]], {limit})
    db:release()

    if qerr then return {error = tostring(qerr)} end
    return rows or {}
end

--- Save match participants (all 10 players).
local function save_match_participants(input)
    if not input or not input.match_id or not input.participants then
        return {error = "match_id and participants are required"}
    end

    local json = require("json")

    local db, err = sql.get(DB_ID)
    if err then return {error = tostring(err)} end

    for _, p in ipairs(input.participants) do
        local items_json = ""
        if p.items then
            items_json = json.encode(p.items)
        end

        db:execute([[
            INSERT OR IGNORE INTO match_participants
                (match_id, puuid, team_id, champion_id, champion_name,
                 summoner_name, tag_line, kills, deaths, assists, cs,
                 total_damage, gold_earned, vision_score, position, win,
                 items, summoner1, summoner2,
                 double_kills, triple_kills, quadra_kills, penta_kills,
                 physical_damage, magic_damage, true_damage, damage_taken,
                 wards_placed, wards_killed, control_wards,
                 kill_participation, damage_share,
                 perks_keystone, perks_primary_style, perks_sub_style, champ_level)
            VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?,
                    ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
        ]], {
            input.match_id,
            p.puuid or "",
            p.team_id or 0,
            p.champion_id or 0,
            p.champion_name,
            p.summoner_name,
            p.tag_line or "",
            p.kills or 0,
            p.deaths or 0,
            p.assists or 0,
            p.cs or 0,
            p.total_damage or 0,
            p.gold_earned or 0,
            p.vision_score or 0,
            p.position or "",
            p.win and 1 or 0,
            items_json,
            p.summoner1 or 0,
            p.summoner2 or 0,
            p.double_kills or 0,
            p.triple_kills or 0,
            p.quadra_kills or 0,
            p.penta_kills or 0,
            p.physical_damage or 0,
            p.magic_damage or 0,
            p.true_damage or 0,
            p.damage_taken or 0,
            p.wards_placed or 0,
            p.wards_killed or 0,
            p.control_wards or 0,
            p.kill_participation or 0,
            p.damage_share or 0,
            p.perks_keystone or 0,
            p.perks_primary_style or 0,
            p.perks_sub_style or 0,
            p.champ_level or 0,
        })
    end

    db:release()
    return {ok = true}
end

--- Get match participants for a list of match IDs.
local function get_match_participants(input)
    if not input or not input.match_ids or #input.match_ids == 0 then
        return {}
    end

    local json = require("json")

    local db, err = sql.get(DB_ID)
    if err then return {error = tostring(err)} end

    -- Build placeholders
    local placeholders = {}
    for i = 1, #input.match_ids do
        placeholders[i] = "?"
    end

    local rows, qerr = db:query(
        "SELECT * FROM match_participants WHERE match_id IN (" ..
        table.concat(placeholders, ",") .. ") ORDER BY match_id, team_id",
        input.match_ids
    )
    db:release()

    if qerr then return {error = tostring(qerr)} end

    -- Parse items JSON
    if rows then
        for _, r in ipairs(rows) do
            if r.items and r.items ~= "" then
                local ok, parsed = pcall(json.decode, r.items)
                if ok then r.items = parsed else r.items = {} end
            else
                r.items = {}
            end
        end
    end

    return rows or {}
end

--- Check which match IDs already exist in the DB.
local function check_existing_matches(input)
    if not input or not input.match_ids or #input.match_ids == 0 then
        return {}
    end

    local db, err = sql.get(DB_ID)
    if err then return {error = tostring(err)} end

    local placeholders = {}
    for i = 1, #input.match_ids do
        placeholders[i] = "?"
    end

    local rows, qerr = db:query(
        "SELECT match_id FROM matches WHERE match_id IN (" ..
        table.concat(placeholders, ",") .. ")",
        input.match_ids
    )
    db:release()

    if qerr then return {error = tostring(qerr)} end

    local existing = {}
    if rows then
        for _, r in ipairs(rows) do
            existing[r.match_id] = true
        end
    end
    return existing
end

--- Save player challenges.
local function save_challenges(input)
    if not input or not input.puuid then
        return {error = "puuid is required"}
    end

    local db, err = sql.get(DB_ID)
    if err then return {error = tostring(err)} end

    local _, exec_err = db:execute([[
        INSERT INTO player_challenges (puuid, level, current_points, max_points, percentile, updated_at)
        VALUES (?, ?, ?, ?, ?, datetime('now'))
        ON CONFLICT(puuid) DO UPDATE SET
            level = excluded.level,
            current_points = excluded.current_points,
            max_points = excluded.max_points,
            percentile = excluded.percentile,
            updated_at = datetime('now')
    ]], {
        input.puuid,
        input.level,
        input.current_points or 0,
        input.max_points or 0,
        input.percentile,
    })
    db:release()

    if exec_err then return {error = tostring(exec_err)} end
    return {ok = true}
end

--- Get cached challenges.
local function get_challenges(input)
    if not input or not input.puuid then
        return nil
    end

    local db, err = sql.get(DB_ID)
    if err then return nil end

    local rows, qerr = db:query(
        "SELECT * FROM player_challenges WHERE puuid = ? LIMIT 1",
        {input.puuid}
    )
    db:release()

    if qerr or not rows or #rows == 0 then return nil end
    return rows[1]
end

--- Record LP snapshot for ranked history.
local function save_ranked_history(input)
    if not input or not input.puuid or not input.queue_type then
        return {error = "puuid and queue_type are required"}
    end

    local db, err = sql.get(DB_ID)
    if err then return {error = tostring(err)} end

    -- Only insert if different from last record (avoid duplicates)
    local last, _ = db:query([[
        SELECT tier, rank, league_points FROM ranked_history
        WHERE puuid = ? AND queue_type = ?
        ORDER BY recorded_at DESC LIMIT 1
    ]], {input.puuid, input.queue_type})

    local dominated = false
    if last and #last > 0 then
        local prev = last[1]
        if prev.tier == input.tier and prev.rank == input.rank and prev.league_points == input.league_points then
            dominated = true
        end
    end

    if not dominated then
        db:execute([[
            INSERT INTO ranked_history (puuid, queue_type, tier, rank, league_points, wins, losses, recorded_at)
            VALUES (?, ?, ?, ?, ?, ?, ?, datetime('now'))
        ]], {
            input.puuid,
            input.queue_type,
            input.tier,
            input.rank,
            input.league_points or 0,
            input.wins or 0,
            input.losses or 0,
        })
    end

    db:release()
    return {ok = true}
end

--- Get ranked history for LP progression chart.
local function get_ranked_history(input)
    if not input or not input.puuid then
        return {}
    end

    local queue_type = input.queue_type or "RANKED_SOLO_5x5"
    local limit = input.limit or 50

    local db, err = sql.get(DB_ID)
    if err then return {error = tostring(err)} end

    local rows, qerr = db:query([[
        SELECT * FROM ranked_history
        WHERE puuid = ? AND queue_type = ?
        ORDER BY recorded_at DESC
        LIMIT ?
    ]], {input.puuid, queue_type, limit})
    db:release()

    if qerr then return {error = tostring(qerr)} end
    return rows or {}
end

--- Get duo partners from match participants.
local function get_duo_partners(input)
    if not input or not input.puuid then
        return {}
    end

    local limit = input.limit or 10

    local db, err = sql.get(DB_ID)
    if err then return {error = tostring(err)} end

    local rows, qerr = db:query([[
        SELECT
            mp2.summoner_name,
            mp2.tag_line,
            mp2.puuid as partner_puuid,
            COUNT(*) as games_together,
            SUM(CASE WHEN mp1.win = 1 THEN 1 ELSE 0 END) as wins_together,
            SUM(CASE WHEN mp1.win = 0 THEN 1 ELSE 0 END) as losses_together
        FROM match_participants mp1
        JOIN match_participants mp2
            ON mp1.match_id = mp2.match_id
            AND mp1.team_id = mp2.team_id
            AND mp1.puuid != mp2.puuid
        WHERE mp1.puuid = ?
            AND mp2.puuid != ''
            AND mp2.summoner_name != ''
        GROUP BY mp2.puuid
        HAVING games_together >= 2
        ORDER BY games_together DESC
        LIMIT ?
    ]], {input.puuid, limit})
    db:release()

    if qerr then return {error = tostring(qerr)} end
    return rows or {}
end

--- Get win rate over time (daily aggregates).
local function get_winrate_history(input)
    if not input or not input.puuid then
        return {}
    end

    local days = input.days or 30

    local db, err = sql.get(DB_ID)
    if err then return {error = tostring(err)} end

    local rows, qerr = db:query([[
        SELECT
            date(game_creation / 1000, 'unixepoch') as day,
            COUNT(*) as games,
            SUM(CASE WHEN win = 1 THEN 1 ELSE 0 END) as wins,
            SUM(CASE WHEN win = 0 THEN 1 ELSE 0 END) as losses,
            ROUND(AVG(kills), 1) as avg_kills,
            ROUND(AVG(deaths), 1) as avg_deaths,
            ROUND(AVG(assists), 1) as avg_assists
        FROM matches
        WHERE puuid = ?
            AND game_creation > (strftime('%s', 'now', '-' || ? || ' days') * 1000)
        GROUP BY day
        ORDER BY day ASC
    ]], {input.puuid, days})
    db:release()

    if qerr then return {error = tostring(qerr)} end
    return rows or {}
end

--- Save DDragon cache entry.
local function save_ddragon_cache(input)
    if not input or not input.cache_key or not input.data then
        return {error = "cache_key and data are required"}
    end

    local db, err = sql.get(DB_ID)
    if err then return {error = tostring(err)} end

    local _, exec_err = db:execute([[
        INSERT INTO ddragon_cache (cache_key, data, version, updated_at)
        VALUES (?, ?, ?, datetime('now'))
        ON CONFLICT(cache_key) DO UPDATE SET
            data = excluded.data,
            version = excluded.version,
            updated_at = datetime('now')
    ]], {
        input.cache_key,
        input.data,
        input.version or "",
    })
    db:release()

    if exec_err then return {error = tostring(exec_err)} end
    return {ok = true}
end

--- Get DDragon cache entry.
local function get_ddragon_cache(input)
    if not input or not input.cache_key then
        return nil
    end

    local ttl_hours = input.ttl_hours or 24

    local db, err = sql.get(DB_ID)
    if err then return nil end

    local rows, qerr = db:query([[
        SELECT * FROM ddragon_cache
        WHERE cache_key = ?
            AND updated_at > datetime('now', '-' || ? || ' hours')
        LIMIT 1
    ]], {input.cache_key, ttl_hours})
    db:release()

    if qerr or not rows or #rows == 0 then return nil end
    return rows[1]
end

--- Save/remove favorite player (#18).
local function save_favorite(input)
    if not input or not input.puuid then
        return {error = "puuid is required"}
    end

    local db, err = sql.get(DB_ID)
    if err then return {error = tostring(err)} end

    local _, exec_err = db:execute([[
        INSERT INTO favorites (puuid, game_name, tag_line, platform, region, note, created_at)
        VALUES (?, ?, ?, ?, ?, ?, datetime('now'))
        ON CONFLICT(puuid) DO UPDATE SET
            game_name = excluded.game_name,
            tag_line = excluded.tag_line,
            platform = excluded.platform,
            region = excluded.region,
            note = excluded.note
    ]], {
        input.puuid,
        input.game_name or "",
        input.tag_line or "",
        input.platform or "EUW1",
        input.region or "EUROPE",
        input.note or "",
    })
    db:release()

    if exec_err then return {error = tostring(exec_err)} end
    return {ok = true}
end

local function remove_favorite(input)
    if not input or not input.puuid then
        return {error = "puuid is required"}
    end

    local db, err = sql.get(DB_ID)
    if err then return {error = tostring(err)} end

    db:execute("DELETE FROM favorites WHERE puuid = ?", {input.puuid})
    db:release()
    return {ok = true}
end

local function get_favorites()
    local db, err = sql.get(DB_ID)
    if err then return {favorites = {}, error = tostring(err)} end

    local rows, qerr = db:query([[
        SELECT f.*,
               pr_solo.tier as solo_tier, pr_solo.rank as solo_rank,
               pr_solo.league_points as solo_lp, pr_solo.wins as solo_wins, pr_solo.losses as solo_losses
        FROM favorites f
        LEFT JOIN player_ranked pr_solo ON f.puuid = pr_solo.puuid AND pr_solo.queue_type = 'RANKED_SOLO_5x5'
        ORDER BY f.created_at DESC
    ]])
    db:release()

    if qerr then return {favorites = {}, error = tostring(qerr)} end
    return {favorites = rows or {}}
end

local function is_favorite(input)
    if not input or not input.puuid then return {is_favorite = false} end

    local db, err = sql.get(DB_ID)
    if err then return {is_favorite = false} end

    local rows, _ = db:query("SELECT 1 FROM favorites WHERE puuid = ? LIMIT 1", {input.puuid})
    db:release()
    return {is_favorite = (rows and #rows > 0) and true or false}
end

--- Match notes (#27).
local function save_match_note(input)
    if not input or not input.match_id or not input.puuid then
        return {error = "match_id and puuid are required"}
    end

    local db, err = sql.get(DB_ID)
    if err then return {error = tostring(err)} end

    local _, exec_err = db:execute([[
        INSERT INTO match_notes (match_id, puuid, note, updated_at)
        VALUES (?, ?, ?, datetime('now'))
        ON CONFLICT(match_id, puuid) DO UPDATE SET
            note = excluded.note,
            updated_at = datetime('now')
    ]], {
        input.match_id,
        input.puuid,
        input.note or "",
    })
    db:release()

    if exec_err then return {error = tostring(exec_err)} end
    return {ok = true}
end

local function get_match_notes(input)
    if not input or not input.puuid then return {} end

    local db, err = sql.get(DB_ID)
    if err then return {} end

    local rows, qerr = db:query(
        "SELECT match_id, note FROM match_notes WHERE puuid = ? AND note != ''",
        {input.puuid}
    )
    db:release()

    if qerr then return {notes = {}} end
    local map = {}
    if rows then
        for _, r in ipairs(rows) do
            map[r.match_id] = r.note
        end
    end
    return {notes = map}
end

--- Goals (#26).
local function save_goal(input)
    if not input or not input.puuid or not input.goal_type or not input.target_value then
        return {error = "puuid, goal_type, and target_value are required"}
    end

    local db, err = sql.get(DB_ID)
    if err then return {error = tostring(err)} end

    local _, exec_err = db:execute([[
        INSERT INTO player_goals (puuid, goal_type, target_value, current_value, created_at)
        VALUES (?, ?, ?, ?, datetime('now'))
    ]], {
        input.puuid,
        input.goal_type,
        input.target_value,
        input.current_value or "",
    })
    db:release()

    if exec_err then return {error = tostring(exec_err)} end
    return {ok = true}
end

local function get_goals(input)
    if not input or not input.puuid then return {goals = {}} end

    local db, err = sql.get(DB_ID)
    if err then return {goals = {}} end

    local rows, qerr = db:query(
        "SELECT * FROM player_goals WHERE puuid = ? ORDER BY completed ASC, created_at DESC",
        {input.puuid}
    )
    db:release()

    if qerr then return {goals = {}} end
    return {goals = rows or {}}
end

local function complete_goal(input)
    if not input or not input.id then
        return {error = "id is required"}
    end

    local db, err = sql.get(DB_ID)
    if err then return {error = tostring(err)} end

    db:execute(
        "UPDATE player_goals SET completed = 1, completed_at = datetime('now') WHERE id = ?",
        {input.id}
    )
    db:release()
    return {ok = true}
end

local function delete_goal(input)
    if not input or not input.id then
        return {error = "id is required"}
    end

    local db, err = sql.get(DB_ID)
    if err then return {error = tostring(err)} end

    db:execute("DELETE FROM player_goals WHERE id = ?", {input.id})
    db:release()
    return {ok = true}
end

return {
    init_schema = init_schema,
    get_player = get_player,
    save_player = save_player,
    get_ranked = get_ranked,
    save_ranked = save_ranked,
    get_mastery = get_mastery,
    save_mastery = save_mastery,
    get_matches = get_matches,
    save_match = save_match,
    list_tracked_players = list_tracked_players,
    save_recent_search = save_recent_search,
    get_recent_searches = get_recent_searches,
    save_match_participants = save_match_participants,
    get_match_participants = get_match_participants,
    check_existing_matches = check_existing_matches,
    save_challenges = save_challenges,
    get_challenges = get_challenges,
    save_ranked_history = save_ranked_history,
    get_ranked_history = get_ranked_history,
    get_duo_partners = get_duo_partners,
    get_winrate_history = get_winrate_history,
    save_ddragon_cache = save_ddragon_cache,
    get_ddragon_cache = get_ddragon_cache,
    save_favorite = save_favorite,
    remove_favorite = remove_favorite,
    get_favorites = get_favorites,
    is_favorite = is_favorite,
    save_match_note = save_match_note,
    get_match_notes = get_match_notes,
    save_goal = save_goal,
    get_goals = get_goals,
    complete_goal = complete_goal,
    delete_goal = delete_goal,
}
