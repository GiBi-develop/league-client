local http = require("http")
local json = require("json")
local funcs = require("funcs")
local contract = require("contract")

local CLASH_CACHE_KEY = "clash_tournaments"
local CLASH_TTL_HOURS = 1

--- GET /api/clash?puuid=...&platform=...  (#14)
--- Returns upcoming/active Clash tournaments + player's team if puuid given.
local function handler()
    local res = http.response()
    local req = http.request()

    local puuid = req:query("puuid")
    local platform = req:query("platform")

    -- Try cache for tournament list
    local tournaments = nil
    local storage, serr = contract.open("app.lc.lib:player_storage")
    if not serr and storage then
        local cached = storage:get_ddragon_cache({cache_key = CLASH_CACHE_KEY, ttl_hours = CLASH_TTL_HOURS})
        if cached and cached.data then
            local ok, parsed = pcall(json.decode, cached.data)
            if ok then tournaments = parsed end
        end
    end

    if not tournaments then
        local fresh, err = funcs.new():call("app.lc:riot_api_get_clash_tournaments", {
            platform = platform,
        })
        if err then
            res:set_status(502)
            res:write_json({error = "Failed to get clash tournaments: " .. tostring(err)})
            return
        end
        tournaments = fresh or {}
        if not serr and storage then
            storage:save_ddragon_cache({
                cache_key = CLASH_CACHE_KEY,
                data = json.encode(tournaments),
            })
        end
    end

    -- Get player's team if puuid provided
    local player_teams = nil
    if puuid and puuid ~= "" then
        local teams, err = funcs.new():call("app.lc:riot_api_get_clash_players", {
            puuid = puuid,
            platform = platform,
        })
        if not err then
            player_teams = teams
        end
    end

    res:set_status(200)
    res:write_json({
        tournaments = tournaments,
        player_teams = player_teams,
    })
end

return {handler = handler}
