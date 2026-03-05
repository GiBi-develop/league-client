local http = require("http")
local json = require("json")
local contract = require("contract")

--- GET /api/favorites — list all favorites
--- POST /api/favorites — add a favorite
--- DELETE /api/favorites — remove a favorite
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
        local result = storage:get_favorites()
        res:set_status(200)
        res:write_json({favorites = (result and result.favorites) or {}})

    elseif method == "POST" then
        local body = req:body()
        if not body or body == "" then
            res:set_status(400)
            res:write_json({error = "Body is required"})
            return
        end
        local ok, data = pcall(json.decode, body)
        if not ok or not data.puuid then
            res:set_status(400)
            res:write_json({error = "puuid is required"})
            return
        end
        storage:save_favorite({
            puuid = data.puuid,
            game_name = data.game_name or "",
            tag_line = data.tag_line or "",
            platform = data.platform or "EUW1",
            region = data.region or "EUROPE",
            note = data.note or "",
        })
        res:set_status(200)
        res:write_json({ok = true})

    elseif method == "DELETE" then
        local puuid = req:query("puuid")
        if not puuid or puuid == "" then
            res:set_status(400)
            res:write_json({error = "puuid query parameter is required"})
            return
        end
        storage:remove_favorite({puuid = puuid})
        res:set_status(200)
        res:write_json({ok = true})
    else
        res:set_status(405)
        res:write_json({error = "Method not allowed"})
    end
end

return {handler = handler}
