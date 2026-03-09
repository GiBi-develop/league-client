local http = require("http")
local json = require("json")
local contract = require("contract")

--- GET /api/player/{puuid}
--- Returns cached player data from database.
local function handler()
    local res = http.response()
    local req = http.request()

    local puuid = req:param("puuid")
    if not puuid or puuid == "" then
        res:set_status(400)
        res:write_json({error = "puuid parameter is required"})
        return
    end

    local storage, err = contract.open("app.lc.lib:player_storage")
    if err then
        res:set_status(500)
        res:write_json({error = "Internal error"})
        return
    end

    local player = storage:get_player({puuid = puuid})
    if not player then
        res:set_status(404)
        res:write_json({error = "Player not found in cache"})
        return
    end

    local ranked = storage:get_ranked({puuid = puuid})
    local mastery = storage:get_mastery({puuid = puuid, limit = 10})

    -- Match filtering params
    local match_params = {puuid = puuid, limit = tonumber(req:query("limit")) or 30}
    local champion = req:query("champion")
    if champion and champion ~= "" then match_params.champion_name = champion end
    local position = req:query("position")
    if position and position ~= "" then match_params.position = position end
    local queue = req:query("queue")
    if queue and queue ~= "" then match_params.queue_id = tonumber(queue) end
    local win_param = req:query("win")
    if win_param == "true" then match_params.win = true
    elseif win_param == "false" then match_params.win = false end

    local matches = storage:get_matches(match_params)

    res:set_status(200)
    res:write_json({
        player = player,
        ranked = ranked,
        mastery = mastery,
        matches = matches,
    })
end

return {handler = handler}
