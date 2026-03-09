local http = require("http")
local json = require("json")
local funcs = require("funcs")
local env = require("env")
local contract = require("contract")

--- GET /api/live-game/{puuid}/briefing — Pre-game briefing with opponent weakness profiles (#1).
local function handler()
    local res = http.response()
    local req = http.request()

    local puuid = req:param("puuid")
    if not puuid or puuid == "" then
        res:set_status(400)
        res:write_json({error = "puuid required"})
        return
    end

    local platform = req:query("platform") or env.get("RIOT_PLATFORM") or "EUW1"

    -- Get active game
    local active_game, ag_err = funcs.new():call("app.lc:riot_api_get_active_game", {
        puuid = puuid,
        platform = platform,
    })

    if ag_err or not active_game or not active_game.gameId then
        res:set_status(404)
        res:write_json({error = "Player is not in game"})
        return
    end

    -- Find the player's team
    local my_team = 100
    local participants = active_game.participants or {}
    for _, p in ipairs(participants) do
        if p.puuid == puuid then
            my_team = p.teamId or 100
            break
        end
    end

    -- Get storage for cached data
    local storage, _ = contract.open("app.lc.lib:player_storage")

    -- Build briefing for each opponent (other team)
    local opponents = {}
    local allies = {}
    for _, p in ipairs(participants) do
        if p.teamId ~= my_team then
            table.insert(opponents, p)
        else
            table.insert(allies, p)
        end
    end

    -- For each opponent, try to get cached data or fetch ranked
    local briefings = {}
    for _, opp in ipairs(opponents) do
        local brief = {
            puuid = opp.puuid,
            summoner_name = opp.riotIdGameName or opp.summonerName or "Unknown",
            champion_name = opp.championName or "Unknown",
            champion_id = opp.championId,
            team_position = opp.teamPosition or "",
            summoner1 = opp.spell1Id or 0,
            summoner2 = opp.spell2Id or 0,
        }

        -- Try to get cached stats
        if storage and opp.puuid then
            local matches = storage:get_matches({puuid = opp.puuid, limit = 20})
            if matches and #matches > 0 then
                local wins = 0
                local total_deaths = 0
                local total_vision = 0
                local total_cs_min = 0
                local champ_games = 0
                local champ_wins = 0
                local streak = 0
                local streak_type = ""
                local game_count = #matches

                for mi, m in ipairs(matches) do
                    if m.win == 1 then wins = wins + 1 end
                    total_deaths = total_deaths + (tonumber(m.deaths) or 0)
                    total_vision = total_vision + (tonumber(m.vision_score) or 0)
                    total_cs_min = total_cs_min + (tonumber(m.cs_per_min) or 0)

                    -- Champion-specific stats
                    if m.champion_name == opp.championName then
                        champ_games = champ_games + 1
                        if m.win == 1 then champ_wins = champ_wins + 1 end
                    end

                    -- Current streak
                    if mi == 1 then
                        streak_type = m.win == 1 and "W" or "L"
                        streak = 1
                    elseif (m.win == 1 and streak_type == "W") or (m.win ~= 1 and streak_type == "L") then
                        streak = streak + 1
                    end
                end

                brief.recent_wr = math.floor(wins / game_count * 100 + 0.5)
                brief.avg_deaths = math.floor(total_deaths / game_count * 10 + 0.5) / 10
                brief.avg_vision = math.floor(total_vision / game_count * 10 + 0.5) / 10
                brief.avg_cs_min = math.floor(total_cs_min / game_count * 10 + 0.5) / 10
                brief.champion_games = champ_games
                brief.champion_wr = champ_games > 0 and math.floor(champ_wins / champ_games * 100 + 0.5) or nil
                brief.streak = streak_type == "W" and streak or -streak

                -- Build weakness list
                local weaknesses = {}
                if brief.avg_deaths > 6 then
                    table.insert(weaknesses, "Dies often (avg " .. brief.avg_deaths .. " deaths)")
                end
                if brief.avg_vision < 12 then
                    table.insert(weaknesses, "Low vision (avg " .. brief.avg_vision .. " score)")
                end
                if brief.avg_cs_min < 5 and opp.teamPosition ~= "UTILITY" then
                    table.insert(weaknesses, "Poor CS (" .. brief.avg_cs_min .. "/min)")
                end
                if streak_type == "L" and streak >= 3 then
                    table.insert(weaknesses, "On " .. streak .. "-game losing streak (tilted?)")
                end
                if champ_games > 0 and champ_games < 3 then
                    table.insert(weaknesses, "Inexperienced on " .. (opp.championName or "champ") .. " (" .. champ_games .. " games)")
                end
                if brief.recent_wr and brief.recent_wr < 45 then
                    table.insert(weaknesses, "Low recent WR (" .. brief.recent_wr .. "%)")
                end

                -- Strengths
                local strengths = {}
                if champ_games >= 10 and (brief.champion_wr or 0) >= 55 then
                    table.insert(strengths, (opp.championName or "Champ") .. " main (" .. brief.champion_wr .. "% WR, " .. champ_games .. " games)")
                end
                if streak_type == "W" and streak >= 3 then
                    table.insert(strengths, "On " .. streak .. "-game win streak")
                end
                if brief.avg_deaths < 3 then
                    table.insert(strengths, "Very safe player (avg " .. brief.avg_deaths .. " deaths)")
                end

                brief.weaknesses = weaknesses
                brief.strengths = strengths
            end

            -- Get ranked data
            local ranked = storage:get_ranked({puuid = opp.puuid})
            if ranked then
                for _, r in ipairs(ranked) do
                    if r.queue_type == "RANKED_SOLO_5x5" then
                        brief.tier = r.tier
                        brief.rank = r.rank
                        brief.lp = r.league_points
                        break
                    end
                end
            end
        end

        table.insert(briefings, brief)
    end

    res:set_status(200)
    res:write_json({
        game_id = active_game.gameId,
        game_mode = active_game.gameMode,
        queue_id = active_game.gameQueueConfigId,
        game_length = active_game.gameLength or 0,
        opponents = briefings,
    })
end

return {handler = handler}
