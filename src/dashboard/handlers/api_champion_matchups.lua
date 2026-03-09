local http = require("http")
local json = require("json")
local contract = require("contract")

--- GET /api/player/{puuid}/matchups — Champion matchup win rates.
--- Query params: champion, position, min_games
local function handler()
    local res = http.response()
    local req = http.request()

    local puuid = req:param("puuid")
    if not puuid or puuid == "" then
        res:set_status(400)
        res:write_json({error = "puuid is required"})
        return
    end

    local storage, serr = contract.open("app.lc.lib:player_storage")
    if serr then
        res:set_status(500)
        res:write_json({error = "storage unavailable"})
        return
    end

    local champion = req:query("champion")
    local position = req:query("position")
    local min_games = tonumber(req:query("min_games")) or 2

    local matchups = storage:get_champion_matchups({
        puuid = puuid,
        champion_name = (champion and champion ~= "") and champion or nil,
        position = (position and position ~= "") and position or nil,
        min_games = min_games,
    })

    res:set_status(200)
    res:write_json({matchups = matchups or {}})
end

return {handler = handler}
