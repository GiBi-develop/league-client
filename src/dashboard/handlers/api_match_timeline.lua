local http = require("http")
local json = require("json")
local funcs = require("funcs")

--- GET /api/match/{matchId}/timeline
local function handler()
    local res = http.response()
    local req = http.request()

    local match_id = req:param("matchId")
    if not match_id or match_id == "" then
        res:set_status(400)
        res:write_json({error = "matchId is required"})
        return
    end

    local timeline, err = funcs.new():call("app.lc:riot_api_get_match_timeline", {
        match_id = match_id,
    })

    if err then
        if err == "not_found" then
            res:set_status(404)
            res:write_json({error = "Timeline not found"})
        elseif err == "rate_limited" then
            res:set_status(429)
            res:write_json({error = "Rate limited, try again later"})
        else
            res:set_status(502)
            res:write_json({error = "API error: " .. tostring(err)})
        end
        return
    end

    if not timeline or not timeline.info or not timeline.info.frames then
        res:set_status(404)
        res:write_json({error = "No timeline data"})
        return
    end

    -- Extract key events from frames
    local events = {}
    local participant_map = {}

    -- Build participant ID -> champion/puuid map
    if timeline.info.participants then
        for _, p in ipairs(timeline.info.participants) do
            participant_map[p.participantId] = {
                puuid = p.puuid,
                participant_id = p.participantId,
            }
        end
    end

    -- Extract gold data per frame for gold difference graph
    local gold_frames = {}

    for _, frame in ipairs(timeline.info.frames) do
        -- Gold per participant from participantFrames
        if frame.participantFrames then
            local blue_gold = 0
            local red_gold = 0
            for pid_str, pf in pairs(frame.participantFrames) do
                local pid = tonumber(pid_str)
                if pid and pf.totalGold then
                    if pid <= 5 then
                        blue_gold = blue_gold + pf.totalGold
                    else
                        red_gold = red_gold + pf.totalGold
                    end
                end
            end
            table.insert(gold_frames, {
                timestamp = frame.timestamp,
                blue_gold = blue_gold,
                red_gold = red_gold,
            })
        end

        if frame.events then
            for _, evt in ipairs(frame.events) do
                local kind = evt.type
                -- Champion kills
                if kind == "CHAMPION_KILL" then
                    table.insert(events, {
                        type = "kill",
                        timestamp = evt.timestamp,
                        killer_id = evt.killerId,
                        victim_id = evt.victimId,
                        assists = evt.assistingParticipantIds or {},
                        x = evt.position and evt.position.x,
                        y = evt.position and evt.position.y,
                    })
                -- Objectives (Dragon, Baron, Herald)
                elseif kind == "ELITE_MONSTER_KILL" then
                    table.insert(events, {
                        type = "objective",
                        timestamp = evt.timestamp,
                        monster = evt.monsterType,
                        monster_sub = evt.monsterSubType,
                        killer_id = evt.killerId,
                        team_id = evt.killerTeamId,
                    })
                -- Tower kills
                elseif kind == "BUILDING_KILL" then
                    table.insert(events, {
                        type = "building",
                        timestamp = evt.timestamp,
                        building = evt.buildingType,
                        lane = evt.laneType,
                        tower = evt.towerType,
                        team_id = evt.teamId,
                        killer_id = evt.killerId,
                    })
                end
            end
        end
    end

    res:set_status(200)
    res:write_json({
        events = events,
        participants = participant_map,
        frame_interval = timeline.info.frameInterval,
        gold_frames = gold_frames,
    })
end

return {handler = handler}
