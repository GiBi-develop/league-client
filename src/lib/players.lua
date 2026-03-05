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
        INSERT INTO player_ranked (puuid, queue_type, tier, rank, league_points, wins, losses, updated_at)
        VALUES (?, ?, ?, ?, ?, ?, ?, datetime('now'))
        ON CONFLICT(puuid, queue_type) DO UPDATE SET
            tier = excluded.tier,
            rank = excluded.rank,
            league_points = excluded.league_points,
            wins = excluded.wins,
            losses = excluded.losses,
            updated_at = datetime('now')
    ]], {
        input.puuid,
        input.queue_type,
        input.tier,
        input.rank,
        input.league_points or 0,
        input.wins or 0,
        input.losses or 0,
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
             game_mode, queue_id, position, items, game_creation)
        VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
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
}
