local http = require("http")
local json = require("json")
local contract = require("contract")

--- POST /api/match-notes — save a match note
--- GET /api/match-notes?puuid=... — get all match notes for a player
local function handler()
    local res = http.response()
    local req = http.request()
    local method = req:method()

    local storage, serr = contract.open("app.lc.lib:player_storage")
    if serr then
        res:set_status(500)
        res:write_json({error = "Storage unavailable"})
        return
    end

    if method == "GET" then
        local puuid = req:query("puuid")
        if not puuid or puuid == "" then
            res:set_status(400)
            res:write_json({error = "puuid is required"})
            return
        end
        local result = storage:get_match_notes({puuid = puuid})
        res:set_status(200)
        res:write_json({notes = (result and result.notes) or {}})

    elseif method == "POST" then
        local body = req:body()
        if not body or body == "" then
            res:set_status(400)
            res:write_json({error = "Body is required"})
            return
        end
        local ok, data = pcall(json.decode, body)
        if not ok or not data.match_id or not data.puuid then
            res:set_status(400)
            res:write_json({error = "match_id and puuid are required"})
            return
        end
        storage:save_match_note({
            match_id = data.match_id,
            puuid = data.puuid,
            note = data.note or "",
        })
        res:set_status(200)
        res:write_json({ok = true})
    else
        res:set_status(405)
        res:write_json({error = "Method not allowed"})
    end
end

return {handler = handler}
