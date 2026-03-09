local http = require("http")
local json = require("json")
local contract = require("contract")

--- GET /api/champion/{name}/builds — Aggregated rune+spell builds for a champion.
--- Query params: position, queue
local function handler()
    local res = http.response()
    local req = http.request()

    local champion_name = req:param("name")
    if not champion_name or champion_name == "" then
        res:set_status(400)
        res:write_json({error = "champion name is required"})
        return
    end

    local storage, serr = contract.open("app.lc.lib:player_storage")
    if serr then
        res:set_status(500)
        res:write_json({error = "storage unavailable"})
        return
    end

    local position = req:query("position")
    local queue = req:query("queue")

    local builds = storage:get_champion_builds({
        champion_name = champion_name,
        position = (position and position ~= "") and position or nil,
        queue_id = queue and tonumber(queue) or nil,
    })

    res:set_status(200)
    res:write_json(builds or {})
end

return {handler = handler}
