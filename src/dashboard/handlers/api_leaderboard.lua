local http = require("http")
local json = require("json")
local funcs = require("funcs")
local contract = require("contract")

local CACHE_TTL_HOURS = 1

--- GET /api/leaderboard?queue=RANKED_SOLO_5x5&platform=EUW1&tier=challenger (#15)
--- Returns top players from Challenger/Grandmaster/Master leagues.
local function handler()
    local res = http.response()
    local req = http.request()

    local queue = req:query("queue") or "RANKED_SOLO_5x5"
    local platform = req:query("platform") or ""
    local tier = req:query("tier") or "challenger"

    local cache_key = "leaderboard_" .. tier .. "_" .. queue .. "_" .. platform

    -- Try cache
    local data = nil
    local storage, serr = contract.open("app.lc.lib:player_storage")
    if not serr and storage then
        local cached = storage:get_ddragon_cache({cache_key = cache_key, ttl_hours = CACHE_TTL_HOURS})
        if cached and cached.data then
            local ok, parsed = pcall(json.decode, cached.data)
            if ok then data = parsed end
        end
    end

    if not data then
        local func_name = "app.lc:riot_api_get_challenger_league"
        if tier == "grandmaster" then
            func_name = "app.lc:riot_api_get_grandmaster_league"
        elseif tier == "master" then
            func_name = "app.lc:riot_api_get_master_league"
        end

        local fresh, err = funcs.new():call(func_name, {
            queue = queue,
            platform = platform ~= "" and platform or nil,
        })
        if err then
            res:set_status(502)
            res:write_json({error = "Failed to get leaderboard: " .. tostring(err)})
            return
        end
        data = fresh or {}
        if not serr and storage then
            storage:save_ddragon_cache({
                cache_key = cache_key,
                data = json.encode(data),
            })
        end
    end

    -- Extract and sort entries by LP (top 50)
    local raw_entries = data and data.entries
    local entries = {}
    if raw_entries then
        for _, e in ipairs(raw_entries) do
            table.insert(entries, e)
        end
    end
    table.sort(entries, function(a, b)
        return (a.leaguePoints or 0) > (b.leaguePoints or 0)
    end)

    local top50 = {}
    for i, e in ipairs(entries) do
        if i > 50 then break end
        table.insert(top50, {
            rank = i,
            summoner_name = e.summonerName,
            summoner_id = e.summonerId,
            lp = e.leaguePoints,
            wins = e.wins,
            losses = e.losses,
            hot_streak = e.hotStreak,
            veteran = e.veteran,
        })
    end

    res:set_status(200)
    res:write_json({
        tier = string.upper(tier),
        queue = queue,
        name = data and data.name or "",
        total = #entries,
        entries = top50,
    })
end

return {handler = handler}
