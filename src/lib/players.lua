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

    -- Add total mastery score column to players
    pcall(function() db:execute("ALTER TABLE players ADD COLUMN total_mastery_score INTEGER DEFAULT 0") end)
    -- Add in_game status column to players
    pcall(function() db:execute("ALTER TABLE players ADD COLUMN in_game INTEGER DEFAULT 0") end)
    pcall(function() db:execute("ALTER TABLE players ADD COLUMN current_game_id TEXT") end)

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
    -- LP change per match (#Wave4)
    pcall(function() db:execute("ALTER TABLE matches ADD COLUMN lp_change INTEGER") end)
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

    -- API metrics table (Wave 1: #18 API Health Monitor)
    db:execute([[
        CREATE TABLE IF NOT EXISTS api_metrics (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            endpoint TEXT NOT NULL,
            status_code INTEGER DEFAULT 200,
            response_time_ms INTEGER DEFAULT 0,
            cached INTEGER DEFAULT 0,
            created_at TEXT NOT NULL DEFAULT (datetime('now'))
        )
    ]])

    db:execute([[
        CREATE INDEX IF NOT EXISTS idx_api_metrics_created
        ON api_metrics(created_at DESC)
    ]])

    -- Match timeline stats table (Wave 3: #7)
    db:execute([[
        CREATE TABLE IF NOT EXISTS match_timeline_stats (
            match_id TEXT NOT NULL,
            puuid TEXT NOT NULL,
            cs_at_10 INTEGER DEFAULT 0,
            cs_at_15 INTEGER DEFAULT 0,
            gold_at_10 INTEGER DEFAULT 0,
            gold_at_15 INTEGER DEFAULT 0,
            gold_diff_at_10 INTEGER DEFAULT 0,
            gold_diff_at_15 INTEGER DEFAULT 0,
            xp_diff_at_10 INTEGER DEFAULT 0,
            first_blood_time INTEGER DEFAULT 0,
            PRIMARY KEY (match_id, puuid)
        )
    ]])

    -- Personal records table (Wave 2: #11)
    db:execute([[
        CREATE TABLE IF NOT EXISTS player_records (
            puuid TEXT NOT NULL,
            record_type TEXT NOT NULL,
            value REAL NOT NULL,
            match_id TEXT,
            champion_name TEXT,
            achieved_at TEXT NOT NULL DEFAULT (datetime('now')),
            PRIMARY KEY (puuid, record_type)
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
        INSERT INTO players (puuid, game_name, tag_line, summoner_id, summoner_level, profile_icon_id, revision_date, platform, region, total_mastery_score, updated_at)
        VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, datetime('now'))
        ON CONFLICT(puuid) DO UPDATE SET
            game_name = excluded.game_name,
            tag_line = excluded.tag_line,
            summoner_id = excluded.summoner_id,
            summoner_level = excluded.summoner_level,
            profile_icon_id = excluded.profile_icon_id,
            revision_date = excluded.revision_date,
            platform = excluded.platform,
            region = excluded.region,
            total_mastery_score = COALESCE(excluded.total_mastery_score, total_mastery_score),
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
        input.total_mastery_score,
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

    -- Build dynamic WHERE with optional filters
    local where = "puuid = ?"
    local params = {input.puuid}

    if input.champion_name and input.champion_name ~= "" then
        where = where .. " AND champion_name = ?"
        table.insert(params, input.champion_name)
    end
    if input.position and input.position ~= "" then
        where = where .. " AND position = ?"
        table.insert(params, input.position)
    end
    if input.queue_id then
        where = where .. " AND queue_id = ?"
        table.insert(params, tonumber(input.queue_id) or 0)
    end
    if input.win ~= nil then
        where = where .. " AND win = ?"
        table.insert(params, input.win and 1 or 0)
    end
    if input.date_from and input.date_from ~= "" then
        -- date_from as ISO date string "2026-01-01"
        where = where .. " AND game_creation >= ?"
        -- Convert date string to epoch ms (approximate)
        table.insert(params, input.date_from_ms or 0)
    end

    table.insert(params, limit)

    local rows, qerr = db:query(
        "SELECT * FROM matches WHERE " .. where .. " ORDER BY game_creation DESC LIMIT ?",
        params
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

--- List managed players (#18).
local function list_managed_players()
    local db, err = sql.get(DB_ID)
    if err then return {} end

    local rows = db:query("SELECT * FROM managed_players ORDER BY created_at DESC")
    db:release()
    return rows or {}
end

--- Add a managed player (#18).
local function add_managed_player(input)
    if not input or not input.game_name or not input.tag_line then
        return {error = "game_name and tag_line are required"}
    end
    local db, err = sql.get(DB_ID)
    if err then return {error = tostring(err)} end

    local rows, qerr = db:query([[
        INSERT INTO managed_players
            (game_name, tag_line, platform, region, fetch_interval, ranked_interval,
             discord_notify, discord_webhook_url, active)
        VALUES (?, ?, ?, ?, ?, ?, ?, ?, 1)
        ON CONFLICT(game_name, tag_line) DO UPDATE SET
            platform = excluded.platform,
            region = excluded.region,
            fetch_interval = excluded.fetch_interval,
            ranked_interval = excluded.ranked_interval,
            discord_notify = excluded.discord_notify,
            discord_webhook_url = excluded.discord_webhook_url,
            active = 1
        RETURNING id
    ]], {
        input.game_name,
        input.tag_line,
        input.platform or "EUW1",
        input.region or "EUROPE",
        input.fetch_interval or "10m",
        input.ranked_interval or "2m",
        (input.discord_notify and 1 or 0),
        input.discord_webhook_url or "",
    })

    db:release()
    if qerr then return {error = tostring(qerr)} end
    local id = rows and rows[1] and rows[1].id or nil
    return {ok = true, id = id}
end

--- Remove a managed player (#18).
local function remove_managed_player(input)
    if not input or not input.id then return {error = "id is required"} end
    local db, err = sql.get(DB_ID)
    if err then return {error = tostring(err)} end

    db:execute("UPDATE managed_players SET active = 0 WHERE id = ?", {input.id})
    db:release()
    return {ok = true}
end

--- Get notification preferences (#13).
local function get_notification_prefs(input)
    if not input or not input.puuid then return nil end
    local db, err = sql.get(DB_ID)
    if err then return nil end

    local rows = db:query([[
        SELECT * FROM notification_prefs WHERE puuid = ?
    ]], {input.puuid})

    db:release()
    if not rows or #rows == 0 then
        -- Return defaults
        return {
            puuid = input.puuid,
            notify_rank_change = 1,
            notify_match_end = 1,
            notify_game_start = 1,
            notify_goal = 1,
            notify_weekly_digest = 1,
        }
    end
    return rows[1]
end

--- Save notification preferences (#13).
local function save_notification_prefs(input)
    if not input or not input.puuid then return {error = "puuid is required"} end
    local db, err = sql.get(DB_ID)
    if err then return {error = tostring(err)} end

    local function bool_to_int(v) return (v == true or v == 1) and 1 or 0 end

    db:execute([[
        INSERT INTO notification_prefs
            (puuid, notify_rank_change, notify_match_end, notify_game_start, notify_goal, notify_weekly_digest, updated_at)
        VALUES (?, ?, ?, ?, ?, ?, datetime('now'))
        ON CONFLICT(puuid) DO UPDATE SET
            notify_rank_change = excluded.notify_rank_change,
            notify_match_end = excluded.notify_match_end,
            notify_game_start = excluded.notify_game_start,
            notify_goal = excluded.notify_goal,
            notify_weekly_digest = excluded.notify_weekly_digest,
            updated_at = datetime('now')
    ]], {
        input.puuid,
        bool_to_int(input.notify_rank_change),
        bool_to_int(input.notify_match_end),
        bool_to_int(input.notify_game_start),
        bool_to_int(input.notify_goal),
        bool_to_int(input.notify_weekly_digest),
    })

    db:release()
    return {ok = true}
end

--- Enqueue a failed notification for retry (#11).
local function enqueue_notification(input)
    if not input or not input.webhook_url or not input.payload then return {error = "missing fields"} end
    local db, err = sql.get(DB_ID)
    if err then return {error = tostring(err)} end

    db:execute([[
        INSERT INTO notification_queue (webhook_url, payload, attempts, next_attempt_at)
        VALUES (?, ?, 0, datetime('now', '+30 seconds'))
    ]], {input.webhook_url, input.payload})

    db:release()
    return {ok = true}
end

--- Get pending notifications due for retry.
local function get_pending_notifications(input)
    local limit = (input and input.limit) or 10
    local db, err = sql.get(DB_ID)
    if err then return {} end

    local rows = db:query([[
        SELECT id, webhook_url, payload, attempts
        FROM notification_queue
        WHERE next_attempt_at <= datetime('now')
        ORDER BY next_attempt_at ASC
        LIMIT ?
    ]], {limit})

    db:release()
    return rows or {}
end

--- Mark a notification as delivered (delete) or schedule next retry.
local function update_notification_attempt(input)
    if not input or not input.id then return {error = "id is required"} end
    local db, err = sql.get(DB_ID)
    if err then return {error = tostring(err)} end

    local attempts = input.attempts or 1
    if input.success or attempts >= 5 then
        db:execute("DELETE FROM notification_queue WHERE id = ?", {input.id})
    else
        -- Exponential backoff in seconds: 120, 600, 1800, 3600, 7200
        local delay_secs = 120
        if attempts == 2 then delay_secs = 600
        elseif attempts == 3 then delay_secs = 1800
        elseif attempts == 4 then delay_secs = 3600
        end
        local next_attempt = os.date("!%Y-%m-%dT%H:%M:%SZ", os.time() + delay_secs)
        db:execute([[
            UPDATE notification_queue SET attempts = ?, next_attempt_at = ?
            WHERE id = ?
        ]], {attempts, next_attempt, input.id})
    end

    db:release()
    return {ok = true}
end

--- Set player in-game status.
local function set_player_ingame(input)
    if not input or not input.puuid then return {error = "puuid is required"} end
    local db, err = sql.get(DB_ID)
    if err then return {error = tostring(err)} end

    local in_game = input.in_game and 1 or 0
    db:execute([[
        UPDATE players SET in_game = ?, current_game_id = ?, updated_at = datetime('now')
        WHERE puuid = ?
    ]], {in_game, input.game_id, input.puuid})

    -- Managed tracked players (#18) — dynamically added/removed via admin API
    db:execute([[
        CREATE TABLE IF NOT EXISTS managed_players (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            game_name TEXT NOT NULL,
            tag_line TEXT NOT NULL,
            platform TEXT DEFAULT 'EUW1',
            region TEXT DEFAULT 'EUROPE',
            fetch_interval TEXT DEFAULT '10m',
            ranked_interval TEXT DEFAULT '2m',
            discord_notify INTEGER DEFAULT 0,
            discord_webhook_url TEXT DEFAULT '',
            active INTEGER DEFAULT 1,
            created_at TEXT NOT NULL DEFAULT (datetime('now')),
            UNIQUE(game_name, tag_line)
        )
    ]])

    -- Notification preferences (#13)
    db:execute([[
        CREATE TABLE IF NOT EXISTS notification_prefs (
            puuid TEXT PRIMARY KEY,
            notify_rank_change INTEGER DEFAULT 1,
            notify_match_end INTEGER DEFAULT 1,
            notify_game_start INTEGER DEFAULT 1,
            notify_goal INTEGER DEFAULT 1,
            notify_weekly_digest INTEGER DEFAULT 1,
            updated_at TEXT NOT NULL DEFAULT (datetime('now'))
        )
    ]])

    -- Notification retry queue (#11)
    db:execute([[
        CREATE TABLE IF NOT EXISTS notification_queue (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            webhook_url TEXT NOT NULL,
            payload TEXT NOT NULL,
            attempts INTEGER DEFAULT 0,
            next_attempt_at TEXT NOT NULL DEFAULT (datetime('now')),
            created_at TEXT NOT NULL DEFAULT (datetime('now'))
        )
    ]])

    db:release()
    return {ok = true}
end

--- Get today's match stats for a player.
local function get_today_stats(input)
    if not input or not input.puuid then
        return {games = 0, wins = 0, losses = 0, top_champion = nil}
    end
    local db, err = sql.get(DB_ID)
    if err then return {games = 0, wins = 0, losses = 0, top_champion = nil} end

    local rows = db:query([[
        SELECT champion_name, win, kills, deaths, assists
        FROM matches
        WHERE puuid = ?
          AND date(game_creation / 1000, 'unixepoch') = date('now')
    ]], {input.puuid})

    db:release()

    local games = 0
    local wins = 0
    local champs = {}
    local total_kills = 0
    local total_deaths = 0
    local total_assists = 0

    if rows then
        for _, r in ipairs(rows) do
            games = games + 1
            if (r.win or 0) == 1 then wins = wins + 1 end
            local c = r.champion_name or "Unknown"
            champs[c] = (champs[c] or 0) + 1
            total_kills = total_kills + (r.kills or 0)
            total_deaths = total_deaths + (r.deaths or 0)
            total_assists = total_assists + (r.assists or 0)
        end
    end

    local top_champion = nil
    local top_count = 0
    for c, n in pairs(champs) do
        if n > top_count then
            top_count = n
            top_champion = c
        end
    end

    return {
        games = games,
        wins = wins,
        losses = games - wins,
        top_champion = top_champion,
        total_kills = total_kills,
        total_deaths = total_deaths,
        total_assists = total_assists,
    }
end

--- Get peak LP (best-ever rank) per queue from ranked_history.
local function get_peak_lp(input)
    if not input or not input.puuid then return {} end
    local db, err = sql.get(DB_ID)
    if err then return {} end

    local rows = db:query([[
        SELECT queue_type, tier, rank, league_points
        FROM ranked_history
        WHERE puuid = ?
    ]], {input.puuid})

    db:release()

    if not rows then return {} end

    local function tw(t)
        if t == "IRON" then return 0
        elseif t == "BRONZE" then return 4
        elseif t == "SILVER" then return 8
        elseif t == "GOLD" then return 12
        elseif t == "PLATINUM" then return 16
        elseif t == "EMERALD" then return 20
        elseif t == "DIAMOND" then return 24
        else return 28 end
    end
    local function rw(r)
        if r == "IV" then return 0
        elseif r == "III" then return 1
        elseif r == "II" then return 2
        else return 3 end
    end

    local peaks = {}
    for _, row in ipairs(rows) do
        local score = tw(row.tier or "") * 100 + rw(row.rank or "") * 100 + (row.league_points or 0)
        local qt = row.queue_type or "UNKNOWN"
        if not peaks[qt] or score > peaks[qt].score then
            peaks[qt] = {score = score, tier = row.tier, rank = row.rank, lp = row.league_points}
        end
    end

    local result = {}
    for qt, p in pairs(peaks) do
        table.insert(result, {
            queue_type = qt,
            tier = p.tier,
            rank = p.rank,
            lp = p.lp,
        })
    end
    return result
end

--- Get average stats from recent matches (for daily tip).
local function get_recent_avg_stats(input)
    if not input or not input.puuid then return nil end
    local db, err = sql.get(DB_ID)
    if err then return nil end

    local limit = input.limit or 20
    local rows = db:query([[
        SELECT AVG(kills) as avg_k, AVG(deaths) as avg_d, AVG(assists) as avg_a,
               AVG(cs_per_min) as avg_cs_min, AVG(vision_score) as avg_vision,
               AVG(CASE WHEN win = 1 THEN 1.0 ELSE 0.0 END) * 100 as avg_wr
        FROM (
            SELECT kills, deaths, assists, cs_per_min, vision_score, win
            FROM matches
            WHERE puuid = ?
            ORDER BY game_creation DESC
            LIMIT ?
        )
    ]], {input.puuid, limit})

    db:release()

    if not rows or #rows == 0 then return nil end
    return rows[1]
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

--- Get top-N enemy champions with worst personal WR (min 3 games faced).
local function get_personal_enemies(input)
    if not input or not input.puuid then return {} end
    local min_games = (input and input.min_games) or 3
    local limit = (input and input.limit) or 5
    local db, err = sql.get(DB_ID)
    if err then return {} end

    local rows, qerr = db:query([[
        SELECT
            mp.champion_name as enemy_champion,
            COUNT(DISTINCT mp.match_id) as games,
            SUM(CASE WHEN m.win = 0 THEN 1 ELSE 0 END) as losses,
            SUM(CASE WHEN m.win = 1 THEN 1 ELSE 0 END) as wins,
            ROUND(100.0 * SUM(CASE WHEN m.win = 1 THEN 1 ELSE 0 END) / COUNT(*)) as win_rate
        FROM match_participants mp
        JOIN matches m ON mp.match_id = m.match_id
        JOIN match_participants self_mp
            ON self_mp.match_id = mp.match_id AND self_mp.puuid = ?
        WHERE m.puuid = ?
          AND mp.puuid != ?
          AND mp.team_id != self_mp.team_id
          AND mp.champion_name IS NOT NULL
          AND mp.champion_name != ''
        GROUP BY mp.champion_name
        HAVING COUNT(DISTINCT mp.match_id) >= ?
        ORDER BY win_rate ASC, COUNT(DISTINCT mp.match_id) DESC
        LIMIT ?
    ]], {input.puuid, input.puuid, input.puuid, min_games, limit})

    db:release()
    if qerr then return {} end
    return rows or {}
end

--- Compute a performance score (0-100) for a match.
--- Uses KDA ratio, CS/min, vision, damage share, kill participation.
local function compute_performance_score(input)
    if not input then return {score = 0} end

    local k = tonumber(input.kills) or 0
    local d = tonumber(input.deaths) or 0
    local a = tonumber(input.assists) or 0
    local cs_min = tonumber(input.cs_per_min) or 0
    local vision = tonumber(input.vision_score) or 0
    local dmg_share = tonumber(input.damage_share) or 0
    local kp = tonumber(input.kill_participation) or 0
    local duration_min = (tonumber(input.game_duration) or 0) / 60
    local win = input.win and 1 or 0

    -- KDA score (0-25): >5 KDA = 25, <1 = 5
    local kda = d > 0 and ((k + a) / d) or (k + a)
    local kda_score = math.min(25, math.max(0, kda * 5))

    -- CS score (0-20): >8 CS/min = 20, <3 = 0
    local cs_score = math.min(20, math.max(0, (cs_min - 3) * 4))

    -- Vision score (0-15): >1.5 per min = 15
    local vis_per_min = duration_min > 0 and (vision / duration_min) or 0
    local vis_score = math.min(15, math.max(0, vis_per_min * 10))

    -- Damage share score (0-15): >30% = 15
    local dmg_score = math.min(15, math.max(0, dmg_share * 50))

    -- Kill participation score (0-15): >70% = 15
    local kp_score = math.min(15, math.max(0, kp * 20))

    -- Win bonus (0-10)
    local win_bonus = win * 10

    local total = math.floor(kda_score + cs_score + vis_score + dmg_score + kp_score + win_bonus + 0.5)
    total = math.min(100, math.max(0, total))

    local grade = "D"
    if total >= 90 then grade = "S+"
    elseif total >= 80 then grade = "S"
    elseif total >= 70 then grade = "A"
    elseif total >= 60 then grade = "B"
    elseif total >= 45 then grade = "C"
    end

    return {score = total, grade = grade}
end

--- Save match timeline stats (parsed from timeline API).
local function save_timeline_stats(input)
    if not input or not input.match_id or not input.puuid then
        return {error = "match_id and puuid required"}
    end

    local db, err = sql.get(DB_ID)
    if err then return {error = tostring(err)} end

    db:execute([[
        INSERT OR REPLACE INTO match_timeline_stats
        (match_id, puuid, cs_at_10, cs_at_15, gold_at_10, gold_at_15, gold_diff_at_10, gold_diff_at_15, xp_diff_at_10, first_blood_time)
        VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
    ]], {
        input.match_id, input.puuid,
        input.cs_at_10 or 0, input.cs_at_15 or 0,
        input.gold_at_10 or 0, input.gold_at_15 or 0,
        input.gold_diff_at_10 or 0, input.gold_diff_at_15 or 0,
        input.xp_diff_at_10 or 0, input.first_blood_time or 0,
    })

    db:release()
    return {ok = true}
end

--- Get timeline stats for a player's matches.
local function get_timeline_stats(input)
    if not input or not input.puuid then return {} end

    local db, err = sql.get(DB_ID)
    if err then return {} end

    local limit = input.limit or 20
    local rows, qerr = db:query([[
        SELECT t.* FROM match_timeline_stats t
        JOIN matches m ON t.match_id = m.match_id AND t.puuid = m.puuid
        WHERE t.puuid = ?
        ORDER BY m.game_creation DESC
        LIMIT ?
    ]], {input.puuid, limit})

    db:release()
    if qerr then return {} end
    return rows or {}
end

--- Save an API metric entry.
local function save_api_metric(input)
    local db, err = sql.get(DB_ID)
    if err then return {error = tostring(err)} end

    db:execute([[
        INSERT INTO api_metrics (endpoint, status_code, response_time_ms, cached)
        VALUES (?, ?, ?, ?)
    ]], {
        input.endpoint or "unknown",
        input.status_code or 200,
        input.response_time_ms or 0,
        input.cached and 1 or 0,
    })

    -- Cleanup: keep only last 24h of metrics
    db:execute([[
        DELETE FROM api_metrics WHERE created_at < datetime('now', '-1 day')
    ]])

    db:release()
    return {ok = true}
end

--- Get API metrics summary for the last hour.
local function get_api_metrics_summary(input)
    local db, err = sql.get(DB_ID)
    if err then return {error = tostring(err)} end

    local rows, qerr = db:query([[
        SELECT
            COUNT(*) as total_calls,
            SUM(CASE WHEN status_code >= 200 AND status_code < 300 THEN 1 ELSE 0 END) as success,
            SUM(CASE WHEN status_code == 429 THEN 1 ELSE 0 END) as rate_limited,
            SUM(CASE WHEN status_code >= 400 THEN 1 ELSE 0 END) as errors,
            SUM(CASE WHEN cached = 1 THEN 1 ELSE 0 END) as cache_hits,
            COALESCE(AVG(response_time_ms), 0) as avg_response_ms
        FROM api_metrics
        WHERE created_at >= datetime('now', '-1 hour')
    ]])

    db:release()
    if qerr or not rows or #rows == 0 then
        return {total_calls = 0, success = 0, rate_limited = 0, errors = 0, cache_hits = 0, avg_response_ms = 0}
    end
    return rows[1]
end

--- Get data freshness for all tracked players.
local function get_player_freshness(input)
    local db, err = sql.get(DB_ID)
    if err then return {} end

    local rows, qerr = db:query([[
        SELECT
            p.puuid, p.game_name, p.tag_line, p.platform, p.updated_at,
            CAST((julianday('now') - julianday(p.updated_at)) * 24 * 60 AS INTEGER) as minutes_ago,
            p.in_game
        FROM players p
        ORDER BY p.updated_at DESC
    ]])

    db:release()
    if qerr then return {} end
    return rows or {}
end

--- Save or update a personal record if the new value beats the current one.
local function save_record(input)
    if not input or not input.puuid or not input.record_type then
        return {error = "puuid and record_type required"}
    end

    local db, err = sql.get(DB_ID)
    if err then return {error = tostring(err)} end

    local value = tonumber(input.value) or 0
    local higher_is_better = true
    if input.record_type == "lowest_deaths" or input.record_type == "shortest_game" then
        higher_is_better = false
    end

    -- Check if existing record
    local rows, _ = db:query(
        "SELECT value FROM player_records WHERE puuid = ? AND record_type = ?",
        {input.puuid, input.record_type}
    )

    local should_insert = true
    if rows and #rows > 0 then
        local old_val = tonumber(rows[1].value) or 0
        if higher_is_better then
            should_insert = value > old_val
        else
            should_insert = value < old_val
        end
    end

    if should_insert then
        db:execute([[
            INSERT INTO player_records (puuid, record_type, value, match_id, champion_name, achieved_at)
            VALUES (?, ?, ?, ?, ?, datetime('now'))
            ON CONFLICT(puuid, record_type) DO UPDATE SET
                value = excluded.value,
                match_id = excluded.match_id,
                champion_name = excluded.champion_name,
                achieved_at = excluded.achieved_at
        ]], {input.puuid, input.record_type, value, input.match_id or "", input.champion_name or ""})
    end

    db:release()
    return {ok = true, updated = should_insert}
end

--- Get all personal records for a player.
local function get_records(input)
    if not input or not input.puuid then return {records = {}} end

    local db, err = sql.get(DB_ID)
    if err then return {records = {}} end

    local rows, qerr = db:query(
        "SELECT * FROM player_records WHERE puuid = ? ORDER BY record_type",
        {input.puuid}
    )

    db:release()
    if qerr then return {records = {}} end
    return {records = rows or {}}
end

--- Get season history: aggregate ranked data by season boundaries.
local function get_season_history(input)
    if not input or not input.puuid then return {} end

    local db, err = sql.get(DB_ID)
    if err then return {} end

    -- Get peak rank per "season" (approximated by year quarters from ranked_history)
    -- Season boundaries: ~Jan, ~May, ~Sep (Riot season splits)
    local rows, qerr = db:query([[
        SELECT
            CASE
                WHEN CAST(strftime('%m', recorded_at) AS INTEGER) <= 4 THEN strftime('%Y', recorded_at) || ' Split 1'
                WHEN CAST(strftime('%m', recorded_at) AS INTEGER) <= 8 THEN strftime('%Y', recorded_at) || ' Split 2'
                ELSE strftime('%Y', recorded_at) || ' Split 3'
            END as season,
            queue_type,
            MAX(
                CASE tier
                    WHEN 'CHALLENGER' THEN 3000
                    WHEN 'GRANDMASTER' THEN 2900
                    WHEN 'MASTER' THEN 2800
                    WHEN 'DIAMOND' THEN 2400
                    WHEN 'EMERALD' THEN 2000
                    WHEN 'PLATINUM' THEN 1600
                    WHEN 'GOLD' THEN 1200
                    WHEN 'SILVER' THEN 800
                    WHEN 'BRONZE' THEN 400
                    ELSE 0
                END +
                CASE rank
                    WHEN 'I' THEN 300
                    WHEN 'II' THEN 200
                    WHEN 'III' THEN 100
                    ELSE 0
                END +
                league_points
            ) as peak_lp_abs,
            -- Get the tier/rank at peak LP
            tier as peak_tier,
            rank as peak_rank,
            MAX(league_points) as peak_lp,
            MAX(wins + losses) as total_games
        FROM ranked_history
        WHERE puuid = ?
        GROUP BY season, queue_type
        ORDER BY season DESC, queue_type
    ]], {input.puuid})

    db:release()
    if qerr then return {} end
    return rows or {}
end

--- Generate a template-based match recap text.
local function get_match_recap(input)
    if not input or not input.match_id or not input.puuid then
        return {recap = ""}
    end

    local db, err = sql.get(DB_ID)
    if err then return {recap = ""} end

    local rows, qerr = db:query(
        "SELECT * FROM matches WHERE match_id = ? AND puuid = ? LIMIT 1",
        {input.match_id, input.puuid}
    )

    db:release()
    if qerr or not rows or #rows == 0 then return {recap = ""} end

    local m = rows[1]
    local parts = {}

    -- Champion and result
    local result_str = (m.win == 1) and "Victory" or "Defeat"
    table.insert(parts, (m.champion_name or "Unknown") .. " — " .. result_str .. ".")

    -- KDA assessment
    local k = tonumber(m.kills) or 0
    local d = tonumber(m.deaths) or 0
    local a = tonumber(m.assists) or 0
    local kda_ratio = d > 0 and ((k + a) / d) or (k + a)
    if kda_ratio >= 5 then
        table.insert(parts, "Dominant performance with " .. k .. "/" .. d .. "/" .. a .. " KDA (" .. string.format("%.1f", kda_ratio) .. ").")
    elseif kda_ratio >= 3 then
        table.insert(parts, "Strong " .. k .. "/" .. d .. "/" .. a .. " KDA (" .. string.format("%.1f", kda_ratio) .. ").")
    elseif kda_ratio >= 1.5 then
        table.insert(parts, "Decent " .. k .. "/" .. d .. "/" .. a .. " (" .. string.format("%.1f", kda_ratio) .. " KDA).")
    else
        table.insert(parts, "Rough game: " .. k .. "/" .. d .. "/" .. a .. " (" .. string.format("%.1f", kda_ratio) .. " KDA).")
    end

    -- CS analysis
    local cs_min = tonumber(m.cs_per_min) or 0
    if cs_min >= 8 then
        table.insert(parts, "Excellent farming at " .. string.format("%.1f", cs_min) .. " CS/min.")
    elseif cs_min >= 6 then
        table.insert(parts, "Solid " .. string.format("%.1f", cs_min) .. " CS/min.")
    elseif cs_min > 0 and cs_min < 5 then
        table.insert(parts, "Low CS (" .. string.format("%.1f", cs_min) .. "/min) — focus on last-hitting.")
    end

    -- Vision
    local vision = tonumber(m.vision_score) or 0
    local duration_min = (tonumber(m.game_duration) or 0) / 60
    if duration_min > 0 then
        local vis_per_min = vision / duration_min
        if vis_per_min < 0.5 and (m.position ~= "BOTTOM" or m.position ~= "UTILITY") then
            table.insert(parts, "Low vision score (" .. vision .. ") — buy more Control Wards.")
        elseif vis_per_min >= 1.5 then
            table.insert(parts, "Great vision control (" .. vision .. " score).")
        end
    end

    -- Multi-kills
    local penta = tonumber(m.penta_kills) or 0
    local quadra = tonumber(m.quadra_kills) or 0
    local triple = tonumber(m.triple_kills) or 0
    if penta > 0 then
        table.insert(parts, "PENTAKILL!")
    elseif quadra > 0 then
        table.insert(parts, "Quadra Kill achieved!")
    elseif triple > 0 then
        table.insert(parts, "Triple Kill!")
    end

    -- Damage
    local dmg = tonumber(m.total_damage) or 0
    local dmg_share = tonumber(m.damage_share) or 0
    if dmg_share > 0.3 then
        table.insert(parts, "Carried damage (" .. string.format("%.0f%%", dmg_share * 100) .. " of team).")
    end

    -- Duration
    if duration_min > 0 then
        table.insert(parts, string.format("Game lasted %d:%02d.", math.floor(duration_min), (tonumber(m.game_duration) or 0) % 60))
    end

    return {recap = table.concat(parts, " ")}
end

--- Get role distribution (games + WR per position).
local function get_role_distribution(input)
    if not input or not input.puuid then return {} end

    local db, err = sql.get(DB_ID)
    if err then return {} end

    local queue_filter = ""
    local params = {input.puuid}
    if input.queue_id then
        queue_filter = " AND queue_id = ?"
        table.insert(params, tonumber(input.queue_id) or 0)
    end

    local rows, qerr = db:query([[
        SELECT position,
               COUNT(*) as games,
               SUM(CASE WHEN win = 1 THEN 1 ELSE 0 END) as wins,
               ROUND(100.0 * SUM(CASE WHEN win = 1 THEN 1 ELSE 0 END) / COUNT(*), 1) as winrate
        FROM matches
        WHERE puuid = ? AND position != '' AND position IS NOT NULL]] .. queue_filter .. [[
        GROUP BY position
        ORDER BY games DESC
    ]], params)

    db:release()
    if qerr then return {} end
    return rows or {}
end

--- Get damage composition profile (avg % physical/magic/true).
local function get_damage_profile(input)
    if not input or not input.puuid then return {} end

    local db, err = sql.get(DB_ID)
    if err then return {} end

    local limit = input.limit or 50
    local rows, qerr = db:query([[
        SELECT
            ROUND(AVG(CASE WHEN total_damage > 0 THEN 100.0 * physical_damage / total_damage ELSE 0 END), 1) as avg_physical_pct,
            ROUND(AVG(CASE WHEN total_damage > 0 THEN 100.0 * magic_damage / total_damage ELSE 0 END), 1) as avg_magic_pct,
            ROUND(AVG(CASE WHEN total_damage > 0 THEN 100.0 * true_damage / total_damage ELSE 0 END), 1) as avg_true_pct,
            ROUND(AVG(total_damage)) as avg_damage_dealt,
            ROUND(AVG(damage_taken)) as avg_damage_taken,
            ROUND(AVG(damage_share), 3) as avg_damage_share
        FROM (SELECT * FROM matches WHERE puuid = ? ORDER BY game_creation DESC LIMIT ?)
    ]], {input.puuid, limit})

    db:release()
    if qerr or not rows or #rows == 0 then return {} end
    return rows[1]
end

--- Get game duration win rate analysis (buckets).
local function get_duration_analysis(input)
    if not input or not input.puuid then return {} end

    local db, err = sql.get(DB_ID)
    if err then return {} end

    local rows, qerr = db:query([[
        SELECT
            CASE
                WHEN game_duration < 1200 THEN '<20min'
                WHEN game_duration < 1500 THEN '20-25min'
                WHEN game_duration < 1800 THEN '25-30min'
                WHEN game_duration < 2100 THEN '30-35min'
                ELSE '35+min'
            END as bucket,
            COUNT(*) as games,
            SUM(CASE WHEN win = 1 THEN 1 ELSE 0 END) as wins,
            ROUND(100.0 * SUM(CASE WHEN win = 1 THEN 1 ELSE 0 END) / COUNT(*), 1) as winrate
        FROM matches
        WHERE puuid = ? AND game_duration > 0
        GROUP BY bucket
        ORDER BY MIN(game_duration)
    ]], {input.puuid})

    db:release()
    if qerr then return {} end
    return rows or {}
end

--- Get win rate by hour of day and day of week.
local function get_time_analysis(input)
    if not input or not input.puuid then return {} end

    local db, err = sql.get(DB_ID)
    if err then return {} end

    local by_hour, h_err = db:query([[
        SELECT
            CAST(strftime('%H', game_creation / 1000, 'unixepoch') AS INTEGER) as hour,
            COUNT(*) as games,
            SUM(CASE WHEN win = 1 THEN 1 ELSE 0 END) as wins,
            ROUND(100.0 * SUM(CASE WHEN win = 1 THEN 1 ELSE 0 END) / COUNT(*), 1) as winrate
        FROM matches
        WHERE puuid = ? AND game_creation > 0
        GROUP BY hour
        ORDER BY hour
    ]], {input.puuid})

    local by_weekday, w_err = db:query([[
        SELECT
            CAST(strftime('%w', game_creation / 1000, 'unixepoch') AS INTEGER) as weekday,
            COUNT(*) as games,
            SUM(CASE WHEN win = 1 THEN 1 ELSE 0 END) as wins,
            ROUND(100.0 * SUM(CASE WHEN win = 1 THEN 1 ELSE 0 END) / COUNT(*), 1) as winrate
        FROM matches
        WHERE puuid = ? AND game_creation > 0
        GROUP BY weekday
        ORDER BY weekday
    ]], {input.puuid})

    db:release()

    local hours = (not h_err and by_hour) or {}
    local days = (not w_err and by_weekday) or {}

    -- Find best/worst hour
    local best_hour = nil
    local worst_hour = nil
    local best_wr = -1
    local worst_wr = 101
    for _, h in ipairs(hours) do
        local g = tonumber(h.games) or 0
        local wr = tonumber(h.winrate) or 50
        if g >= 3 then
            if wr > best_wr then best_wr = wr; best_hour = h.hour end
            if wr < worst_wr then worst_wr = wr; worst_hour = h.hour end
        end
    end

    return {
        by_hour = hours,
        by_weekday = days,
        best_hour = best_hour,
        worst_hour = worst_hour,
    }
end

--- Get surrender and remake stats.
local function get_surrender_stats(input)
    if not input or not input.puuid then return {} end

    local db, err = sql.get(DB_ID)
    if err then return {} end

    local rows, qerr = db:query([[
        SELECT
            COUNT(*) as total_games,
            SUM(CASE WHEN game_ended_surrender = 1 THEN 1 ELSE 0 END) as surrenders,
            ROUND(100.0 * SUM(CASE WHEN game_ended_surrender = 1 THEN 1 ELSE 0 END) / MAX(COUNT(*), 1), 1) as surrender_rate,
            SUM(CASE WHEN game_duration < 300 AND game_duration > 0 THEN 1 ELSE 0 END) as remakes,
            SUM(CASE WHEN first_blood = 1 THEN 1 ELSE 0 END) as first_bloods,
            ROUND(100.0 * SUM(CASE WHEN first_blood = 1 THEN 1 ELSE 0 END) / MAX(COUNT(*), 1), 1) as first_blood_rate
        FROM matches
        WHERE puuid = ?
    ]], {input.puuid})

    db:release()
    if qerr or not rows or #rows == 0 then return {} end
    return rows[1]
end

--- Get multi-queue breakdown (stats per queue type).
local function get_queue_breakdown(input)
    if not input or not input.puuid then return {} end

    local db, err = sql.get(DB_ID)
    if err then return {} end

    local rows, qerr = db:query([[
        SELECT
            queue_id,
            COUNT(*) as games,
            SUM(CASE WHEN win = 1 THEN 1 ELSE 0 END) as wins,
            ROUND(100.0 * SUM(CASE WHEN win = 1 THEN 1 ELSE 0 END) / COUNT(*), 1) as winrate,
            ROUND(AVG(CAST(kills AS REAL)), 1) as avg_kills,
            ROUND(AVG(CAST(deaths AS REAL)), 1) as avg_deaths,
            ROUND(AVG(CAST(assists AS REAL)), 1) as avg_assists,
            ROUND(AVG(cs_per_min), 1) as avg_cs_min,
            ROUND(AVG(CAST(total_damage AS REAL))) as avg_damage
        FROM matches
        WHERE puuid = ?
        GROUP BY queue_id
        ORDER BY games DESC
    ]], {input.puuid})

    db:release()
    if qerr then return {} end

    -- Add human-readable queue names
    for _, row in ipairs(rows or {}) do
        local qid = tonumber(row.queue_id) or 0
        if qid == 420 then row.queue_name = "Solo/Duo"
        elseif qid == 440 then row.queue_name = "Flex"
        elseif qid == 450 then row.queue_name = "ARAM"
        elseif qid == 1700 then row.queue_name = "Arena"
        elseif qid == 490 then row.queue_name = "Quick Play"
        elseif qid == 400 then row.queue_name = "Normal Draft"
        elseif qid == 430 then row.queue_name = "Normal Blind"
        elseif qid == 900 then row.queue_name = "ARURF"
        else row.queue_name = "Other (" .. tostring(qid) .. ")"
        end
    end

    return rows or {}
end

--- Get summoner spell analysis (spell combos with WR).
local function get_spell_analysis(input)
    if not input or not input.puuid then return {} end

    local db, err = sql.get(DB_ID)
    if err then return {} end

    local champion_filter = ""
    local params = {input.puuid}
    if input.champion_name and input.champion_name ~= "" then
        champion_filter = " AND champion_name = ?"
        table.insert(params, input.champion_name)
    end

    local rows, qerr = db:query([[
        SELECT
            summoner1, summoner2,
            COUNT(*) as games,
            SUM(CASE WHEN win = 1 THEN 1 ELSE 0 END) as wins,
            ROUND(100.0 * SUM(CASE WHEN win = 1 THEN 1 ELSE 0 END) / COUNT(*), 1) as winrate
        FROM matches
        WHERE puuid = ? AND summoner1 > 0 AND summoner2 > 0]] .. champion_filter .. [[
        GROUP BY summoner1, summoner2
        HAVING COUNT(*) >= 2
        ORDER BY games DESC
        LIMIT 10
    ]], params)

    db:release()
    if qerr then return {} end

    -- Map spell IDs to names
    for _, row in ipairs(rows or {}) do
        local function spell_name(id)
            local sid = tonumber(id) or 0
            if sid == 4 then return "Flash"
            elseif sid == 14 then return "Ignite"
            elseif sid == 12 then return "Teleport"
            elseif sid == 6 then return "Ghost"
            elseif sid == 7 then return "Heal"
            elseif sid == 3 then return "Exhaust"
            elseif sid == 11 then return "Smite"
            elseif sid == 21 then return "Barrier"
            elseif sid == 1 then return "Cleanse"
            else return tostring(sid)
            end
        end
        row.spell1_name = spell_name(row.summoner1)
        row.spell2_name = spell_name(row.summoner2)
    end

    return rows or {}
end

--- Get champion matchups for a specific player+champion combination.
local function get_champion_matchups(input)
    if not input or not input.puuid then return {} end

    local db, err = sql.get(DB_ID)
    if err then return {} end

    local champion_filter = ""
    local params = {input.puuid}
    if input.champion_name and input.champion_name ~= "" then
        champion_filter = " AND m.champion_name = ?"
        table.insert(params, input.champion_name)
    end
    local position_filter = ""
    if input.position and input.position ~= "" then
        position_filter = " AND m.position = ?"
        table.insert(params, input.position)
    end
    local min_games = input.min_games or 2

    local rows, qerr = db:query([[
        SELECT
            mp.champion_name as enemy_champion,
            COUNT(*) as games,
            SUM(CASE WHEN m.win = 1 THEN 1 ELSE 0 END) as wins,
            ROUND(100.0 * SUM(CASE WHEN m.win = 1 THEN 1 ELSE 0 END) / COUNT(*), 1) as winrate,
            ROUND(AVG(CAST(m.kills AS REAL)), 1) as avg_kills,
            ROUND(AVG(CAST(m.deaths AS REAL)), 1) as avg_deaths,
            ROUND(AVG(CAST(m.assists AS REAL)), 1) as avg_assists
        FROM matches m
        JOIN match_participants mp ON m.match_id = mp.match_id
            AND mp.team_id != (SELECT team_id FROM match_participants WHERE match_id = m.match_id AND puuid = m.puuid LIMIT 1)
            AND mp.position = m.position
        WHERE m.puuid = ? AND m.position != '']] .. champion_filter .. position_filter .. [[
        GROUP BY mp.champion_name
        HAVING COUNT(*) >= ]] .. tostring(min_games) .. [[
        ORDER BY games DESC
        LIMIT 20
    ]], params)

    db:release()
    if qerr then return {} end
    return rows or {}
end

--- Get global champion stats aggregated from all stored match data.
local function get_champion_global_stats(input)
    local db, err = sql.get(DB_ID)
    if err then return {} end

    local where_parts = {}
    local params = {}
    if input and input.queue_id then
        table.insert(where_parts, "m.queue_id = ?")
        table.insert(params, tonumber(input.queue_id) or 0)
    end
    if input and input.position and input.position ~= "" then
        table.insert(where_parts, "mp.position = ?")
        table.insert(params, input.position)
    end

    local where_clause = ""
    if #where_parts > 0 then
        where_clause = " WHERE " .. table.concat(where_parts, " AND ")
    end

    local min_games = (input and input.min_games) or 5

    local rows, qerr = db:query([[
        SELECT
            mp.champion_name,
            COUNT(*) as games,
            SUM(CASE WHEN mp.win = 1 THEN 1 ELSE 0 END) as wins,
            ROUND(100.0 * SUM(CASE WHEN mp.win = 1 THEN 1 ELSE 0 END) / COUNT(*), 1) as winrate,
            ROUND(AVG(CAST(mp.kills AS REAL)), 1) as avg_kills,
            ROUND(AVG(CAST(mp.deaths AS REAL)), 1) as avg_deaths,
            ROUND(AVG(CAST(mp.assists AS REAL)), 1) as avg_assists,
            ROUND(AVG(CAST(mp.cs AS REAL)), 0) as avg_cs,
            ROUND(AVG(CAST(mp.gold_earned AS REAL)), 0) as avg_gold,
            ROUND(AVG(CAST(mp.total_damage AS REAL)), 0) as avg_damage
        FROM match_participants mp
        JOIN matches m ON mp.match_id = m.match_id]] .. where_clause .. [[
        GROUP BY mp.champion_name
        HAVING COUNT(*) >= ]] .. tostring(min_games) .. [[
        ORDER BY games DESC
        LIMIT ]] .. tostring((input and input.limit) or 50) .. [[
    ]], params)

    db:release()
    if qerr then return {} end
    return rows or {}
end

--- Get vision trend over recent matches.
local function get_vision_trend(input)
    if not input or not input.puuid then return {} end

    local db, err = sql.get(DB_ID)
    if err then return {} end

    local limit = input.limit or 20
    local rows, qerr = db:query([[
        SELECT
            match_id, champion_name, game_duration, vision_score,
            wards_placed, wards_killed, control_wards,
            CASE WHEN game_duration > 0
                THEN ROUND(CAST(vision_score AS REAL) / (game_duration / 60.0), 2)
                ELSE 0
            END as vision_per_min,
            win
        FROM matches
        WHERE puuid = ? AND game_duration > 0
        ORDER BY game_creation DESC
        LIMIT ?
    ]], {input.puuid, limit})

    db:release()
    if qerr then return {} end
    return rows or {}
end

--- Get peer comparison percentiles (vs other tracked players in same tier).
local function get_peer_percentiles(input)
    if not input or not input.puuid then return {} end

    local db, err = sql.get(DB_ID)
    if err then return {} end

    -- Get player's tier
    local tier_rows, _ = db:query(
        "SELECT tier FROM player_ranked WHERE puuid = ? AND queue_type = 'RANKED_SOLO_5x5' LIMIT 1",
        {input.puuid}
    )
    local tier = (tier_rows and #tier_rows > 0) and tier_rows[1].tier or nil

    -- Get player's averages
    local player_stats, _ = db:query([[
        SELECT
            AVG(cs_per_min) as avg_cs_min,
            AVG(CAST(vision_score AS REAL)) as avg_vision,
            AVG(CASE WHEN deaths > 0 THEN CAST(kills + assists AS REAL) / deaths ELSE kills + assists END) as avg_kda,
            AVG(CAST(total_damage AS REAL)) as avg_damage,
            AVG(kill_participation) as avg_kp
        FROM (SELECT * FROM matches WHERE puuid = ? ORDER BY game_creation DESC LIMIT 30)
    ]], {input.puuid})

    if not player_stats or #player_stats == 0 then
        db:release()
        return {}
    end

    local ps = player_stats[1]

    -- Count all tracked players with stats
    local all_players, _ = db:query([[
        SELECT
            p.puuid,
            AVG(m.cs_per_min) as avg_cs_min,
            AVG(CAST(m.vision_score AS REAL)) as avg_vision,
            AVG(CASE WHEN m.deaths > 0 THEN CAST(m.kills + m.assists AS REAL) / m.deaths ELSE m.kills + m.assists END) as avg_kda,
            AVG(CAST(m.total_damage AS REAL)) as avg_damage,
            AVG(m.kill_participation) as avg_kp
        FROM players p
        JOIN matches m ON p.puuid = m.puuid
        GROUP BY p.puuid
        HAVING COUNT(m.match_id) >= 5
    ]])

    db:release()

    if not all_players or #all_players < 2 then return {} end

    local function percentile(field)
        local my_val = tonumber(ps[field]) or 0
        local below = 0
        local total = #all_players
        for _, p in ipairs(all_players) do
            if (tonumber(p[field]) or 0) < my_val then below = below + 1 end
        end
        return math.floor(below / total * 100 + 0.5)
    end

    return {
        cs_per_min = percentile("avg_cs_min"),
        vision = percentile("avg_vision"),
        kda = percentile("avg_kda"),
        damage = percentile("avg_damage"),
        kill_participation = percentile("avg_kp"),
        sample_size = #all_players,
        tier = tier,
    }
end

--- Get champion build data (top rune+item combos from stored matches).
local function get_champion_builds(input)
    if not input or not input.champion_name then return {} end

    local db, err = sql.get(DB_ID)
    if err then return {} end

    local where_extra = ""
    local params = {input.champion_name}
    if input.position and input.position ~= "" then
        where_extra = " AND position = ?"
        table.insert(params, input.position)
    end
    if input.queue_id then
        where_extra = where_extra .. " AND queue_id = ?"
        table.insert(params, tonumber(input.queue_id) or 0)
    end

    -- Top rune pages (keystone + primary + sub)
    local runes, _ = db:query([[
        SELECT
            perks_keystone, perks_primary_style, perks_sub_style,
            COUNT(*) as games,
            SUM(CASE WHEN win = 1 THEN 1 ELSE 0 END) as wins,
            ROUND(100.0 * SUM(CASE WHEN win = 1 THEN 1 ELSE 0 END) / COUNT(*), 1) as winrate
        FROM matches
        WHERE champion_name = ? AND perks_keystone > 0]] .. where_extra .. [[
        GROUP BY perks_keystone, perks_primary_style, perks_sub_style
        HAVING COUNT(*) >= 2
        ORDER BY games DESC
        LIMIT 5
    ]], params)

    -- Top spell combos
    local params2 = {input.champion_name}
    if input.position and input.position ~= "" then table.insert(params2, input.position) end
    if input.queue_id then table.insert(params2, tonumber(input.queue_id) or 0) end

    local spells, _ = db:query([[
        SELECT
            summoner1, summoner2,
            COUNT(*) as games,
            SUM(CASE WHEN win = 1 THEN 1 ELSE 0 END) as wins,
            ROUND(100.0 * SUM(CASE WHEN win = 1 THEN 1 ELSE 0 END) / COUNT(*), 1) as winrate
        FROM matches
        WHERE champion_name = ? AND summoner1 > 0 AND summoner2 > 0]] .. where_extra .. [[
        GROUP BY summoner1, summoner2
        HAVING COUNT(*) >= 2
        ORDER BY games DESC
        LIMIT 3
    ]], params2)

    db:release()

    return {
        runes = runes or {},
        spells = spells or {},
    }
end

--- Get objective control stats for a player (dragons, barons, heralds from match data).
local function get_objective_stats(input)
    if not input or not input.puuid then return {} end

    local db, err = sql.get(DB_ID)
    if err then return {} end

    local rows, qerr = db:query([[
        SELECT
            COUNT(*) as total_games,
            ROUND(AVG(CAST(dragon_takedowns AS REAL)), 1) as avg_dragons,
            ROUND(AVG(CAST(baron_takedowns AS REAL)), 1) as avg_barons,
            ROUND(AVG(CAST(rift_herald_takedowns AS REAL)), 1) as avg_heralds,
            ROUND(AVG(CAST(turret_takedowns AS REAL)), 1) as avg_turrets,
            ROUND(AVG(CAST(turret_plates AS REAL)), 1) as avg_plates,
            SUM(CASE WHEN dragon_takedowns > 0 THEN 1 ELSE 0 END) as games_with_dragons,
            SUM(CASE WHEN baron_takedowns > 0 THEN 1 ELSE 0 END) as games_with_barons,
            SUM(CASE WHEN first_blood = 1 THEN 1 ELSE 0 END) as first_bloods,
            SUM(CASE WHEN first_blood = 1 AND win = 1 THEN 1 ELSE 0 END) as first_blood_wins
        FROM matches
        WHERE puuid = ? AND game_duration > 300
    ]], {input.puuid})

    db:release()
    if qerr or not rows or #rows == 0 then return {} end
    return rows[1]
end

--- Get early game averages from timeline stats.
local function get_early_game_stats(input)
    if not input or not input.puuid then return {} end

    local db, err = sql.get(DB_ID)
    if err then return {} end

    local limit = input.limit or 20
    local rows, qerr = db:query([[
        SELECT
            ROUND(AVG(CAST(cs_at_10 AS REAL)), 1) as avg_cs_at_10,
            ROUND(AVG(CAST(cs_at_15 AS REAL)), 1) as avg_cs_at_15,
            ROUND(AVG(CAST(gold_at_10 AS REAL)), 0) as avg_gold_at_10,
            ROUND(AVG(CAST(gold_at_15 AS REAL)), 0) as avg_gold_at_15,
            ROUND(AVG(CAST(gold_diff_at_10 AS REAL)), 0) as avg_gold_diff_at_10,
            ROUND(AVG(CAST(gold_diff_at_15 AS REAL)), 0) as avg_gold_diff_at_15,
            ROUND(AVG(CAST(xp_diff_at_10 AS REAL)), 0) as avg_xp_diff_at_10,
            COUNT(CASE WHEN first_blood_time > 0 THEN 1 END) as first_blood_games,
            COUNT(*) as total_games,
            ROUND(AVG(CAST(first_blood_time AS REAL)), 0) as avg_first_blood_time
        FROM match_timeline_stats t
        JOIN matches m ON t.match_id = m.match_id AND t.puuid = m.puuid
        WHERE t.puuid = ?
        ORDER BY m.game_creation DESC
        LIMIT ?
    ]], {input.puuid, limit})

    db:release()
    if qerr or not rows or #rows == 0 then return {} end
    return rows[1]
end

--- Compute tilt probability score (0-100) from recent matches.
local function get_tilt_score(input)
    if not input or not input.puuid then return {score = 0} end

    local db, err = sql.get(DB_ID)
    if err then return {score = 0} end

    local rows, qerr = db:query([[
        SELECT win, kills, deaths, assists, cs_per_min, game_creation
        FROM matches
        WHERE puuid = ?
        ORDER BY game_creation DESC
        LIMIT 10
    ]], {input.puuid})

    db:release()
    if qerr or not rows or #rows == 0 then return {score = 0} end

    local score = 50

    -- Losing streak factor
    local streak = 0
    for _, m in ipairs(rows) do
        if (tonumber(m.win) or 0) == 0 then streak = streak + 1 else break end
    end
    score = score + streak * 8

    -- Rising deaths (recent 5 vs older 5)
    if #rows >= 6 then
        local rc = math.min(5, #rows)
        local oc = math.min(5, #rows - rc)
        local rd, od = 0, 0
        for i = 1, rc do rd = rd + (tonumber(rows[i].deaths) or 0) end
        for i = rc + 1, rc + oc do od = od + (tonumber(rows[i].deaths) or 0) end
        if oc > 0 then
            local ra, oa = rd / rc, od / oc
            if ra > oa + 1 then score = score + math.floor((ra - oa) * 5) end
        end
    end

    -- Falling CS
    if #rows >= 6 then
        local rc = math.min(5, #rows)
        local oc = math.min(5, #rows - rc)
        local rcs, ocs = 0, 0
        for i = 1, rc do rcs = rcs + (tonumber(rows[i].cs_per_min) or 0) end
        for i = rc + 1, rc + oc do ocs = ocs + (tonumber(rows[i].cs_per_min) or 0) end
        if oc > 0 then
            local ra, oa = rcs / rc, ocs / oc
            if oa > ra + 0.5 then score = score + math.floor((oa - ra) * 5) end
        end
    end

    -- Recent WR factor
    local wins = 0
    for _, m in ipairs(rows) do
        if (tonumber(m.win) or 0) == 1 then wins = wins + 1 end
    end
    local wr = wins / #rows * 100
    if wr < 30 then score = score + 15
    elseif wr < 40 then score = score + 8
    elseif wr > 70 then score = score - 15
    elseif wr > 60 then score = score - 8
    end

    if score < 0 then score = 0 end
    if score > 100 then score = 100 end

    return {
        score = score,
        streak = streak,
        recent_wr = math.floor(wr + 0.5),
        recent_games = #rows,
    }
end

--- Search players by name for autocomplete.
local function search_players(input)
    if not input or not input.query or input.query == "" then return {} end

    local db, err = sql.get(DB_ID)
    if err then return {} end

    local q = "%" .. tostring(input.query) .. "%"
    local limit = input.limit or 10

    local rows, qerr = db:query([[
        SELECT puuid, game_name, tag_line, profile_icon_id, summoner_level, platform
        FROM players
        WHERE game_name LIKE ?
        ORDER BY updated_at DESC
        LIMIT ?
    ]], {q, limit})

    db:release()
    if qerr then return {} end
    return rows or {}
end

--- Update lp_change for a match after it's been saved.
local function update_match_lp(input)
    if not input or not input.match_id or not input.puuid then return {ok = false} end

    local db, err = sql.get(DB_ID)
    if err then return {ok = false} end

    db:execute(
        "UPDATE matches SET lp_change = ? WHERE match_id = ? AND puuid = ?",
        {input.lp_change or 0, input.match_id, input.puuid}
    )

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
    get_today_stats = get_today_stats,
    get_peak_lp = get_peak_lp,
    get_recent_avg_stats = get_recent_avg_stats,
    set_player_ingame = set_player_ingame,
    enqueue_notification = enqueue_notification,
    get_pending_notifications = get_pending_notifications,
    update_notification_attempt = update_notification_attempt,
    get_notification_prefs = get_notification_prefs,
    save_notification_prefs = save_notification_prefs,
    list_managed_players = list_managed_players,
    add_managed_player = add_managed_player,
    remove_managed_player = remove_managed_player,
    get_personal_enemies = get_personal_enemies,
    save_api_metric = save_api_metric,
    get_api_metrics_summary = get_api_metrics_summary,
    get_player_freshness = get_player_freshness,
    save_record = save_record,
    get_records = get_records,
    get_season_history = get_season_history,
    get_match_recap = get_match_recap,
    compute_performance_score = compute_performance_score,
    save_timeline_stats = save_timeline_stats,
    get_timeline_stats = get_timeline_stats,
    get_role_distribution = get_role_distribution,
    get_damage_profile = get_damage_profile,
    get_duration_analysis = get_duration_analysis,
    get_time_analysis = get_time_analysis,
    get_surrender_stats = get_surrender_stats,
    get_queue_breakdown = get_queue_breakdown,
    get_spell_analysis = get_spell_analysis,
    update_match_lp = update_match_lp,
    get_champion_matchups = get_champion_matchups,
    get_champion_global_stats = get_champion_global_stats,
    get_vision_trend = get_vision_trend,
    get_peer_percentiles = get_peer_percentiles,
    get_early_game_stats = get_early_game_stats,
    get_champion_builds = get_champion_builds,
    get_objective_stats = get_objective_stats,
    get_tilt_score = get_tilt_score,
    search_players = search_players,
}
