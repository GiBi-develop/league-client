local http = require("http")
local json = require("json")
local contract = require("contract")

--- GET /api/champions — Global champion statistics aggregated from stored match data.
--- Query params: queue (queue_id), position, min_games, limit
local function handler()
    local res = http.response()
    local req = http.request()

    local storage, serr = contract.open("app.lc.lib:player_storage")
    if serr then
        res:set_status(500)
        res:write_json({error = "storage unavailable"})
        return
    end

    local queue = req:query("queue")
    local position = req:query("position")
    local min_games = tonumber(req:query("min_games")) or 5
    local limit = tonumber(req:query("limit")) or 50

    local stats = storage:get_champion_global_stats({
        queue_id = queue and tonumber(queue) or nil,
        position = (position and position ~= "") and position or nil,
        min_games = min_games,
        limit = limit,
    })

    res:set_status(200)
    res:write_json({champions = stats or {}})
end

return {handler = handler}
