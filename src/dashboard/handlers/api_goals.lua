local http = require("http")
local json = require("json")
local contract = require("contract")

--- GET /api/goals?puuid=... — get goals
--- POST /api/goals — create a goal
--- PUT /api/goals/complete — mark goal as completed
--- DELETE /api/goals?id=... — delete a goal
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
        local result = storage:get_goals({puuid = puuid})
        res:set_status(200)
        res:write_json({goals = (result and result.goals) or {}})

    elseif method == "POST" then
        local body = req:body()
        if not body or body == "" then
            res:set_status(400)
            res:write_json({error = "Body is required"})
            return
        end
        local ok, data = pcall(json.decode, body)
        if not ok or not data.puuid or not data.goal_type or not data.target_value then
            res:set_status(400)
            res:write_json({error = "puuid, goal_type, and target_value are required"})
            return
        end
        storage:save_goal({
            puuid = data.puuid,
            goal_type = data.goal_type,
            target_value = data.target_value,
            current_value = data.current_value or "",
        })
        res:set_status(200)
        res:write_json({ok = true})

    elseif method == "PUT" then
        local body = req:body()
        if not body or body == "" then
            res:set_status(400)
            res:write_json({error = "Body is required"})
            return
        end
        local ok, data = pcall(json.decode, body)
        if not ok or not data.id then
            res:set_status(400)
            res:write_json({error = "id is required"})
            return
        end
        storage:complete_goal({id = data.id})
        res:set_status(200)
        res:write_json({ok = true})

    elseif method == "DELETE" then
        local id = req:query("id")
        if not id or id == "" then
            res:set_status(400)
            res:write_json({error = "id is required"})
            return
        end
        storage:delete_goal({id = tonumber(id)})
        res:set_status(200)
        res:write_json({ok = true})
    else
        res:set_status(405)
        res:write_json({error = "Method not allowed"})
    end
end

return {handler = handler}
