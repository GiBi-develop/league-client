local http = require("http")
local json = require("json")
local funcs = require("funcs")
local env = require("env")
local contract = require("contract")

--- GET /api/search?name=GameName&tag=TagLine
--- Searches for a player by Riot ID, fetches live data from API.
local function handler()
    local res = http.response()
    local req = http.request()

    local game_name = req:query("name")
    local tag_line = req:query("tag")

    if not game_name or game_name == "" or not tag_line or tag_line == "" then
        res:set_status(400)
        res:write_json({error = "name and tag query parameters are required"})
        return
    end

    -- Get account
    local account, err = funcs.new():call("app.lc:riot_api_get_account", {
        game_name = game_name,
        tag_line = tag_line,
    })

    if err then
        if err == "not_found" then
            res:set_status(404)
            res:write_json({error = "Player not found: " .. game_name .. "#" .. tag_line})
        elseif err == "rate_limited" then
            res:set_status(429)
            res:write_json({error = "Rate limited, try again later"})
        else
            res:set_status(502)
            res:write_json({error = "API error: " .. tostring(err)})
        end
        return
    end

    local puuid = account.puuid

    -- Get summoner
    local summoner, _ = funcs.new():call("app.lc:riot_api_get_summoner", {puuid = puuid})

    -- Get ranked
    local ranked, _ = funcs.new():call("app.lc:riot_api_get_ranked", {puuid = puuid})

    -- Get mastery top 10
    local mastery, _ = funcs.new():call("app.lc:riot_api_get_mastery", {puuid = puuid, count = 10})

    -- Get DDragon champions data for name/icon resolution
    local dd_data, _ = funcs.new():call("app.lc:ddragon_get_champions", {})
    local dd_version = (dd_data and dd_data.version) or "14.5.1"
    local champions = (dd_data and dd_data.champions) or {}

    -- Enrich mastery with champion names and icons
    local enriched_mastery = {}
    if mastery then
        for _, m in ipairs(mastery) do
            local champ = champions[tostring(m.championId)]
            table.insert(enriched_mastery, {
                championId = m.championId,
                championLevel = m.championLevel,
                championPoints = m.championPoints,
                championPointsSinceLastLevel = m.championPointsSinceLastLevel,
                championPointsUntilNextLevel = m.championPointsUntilNextLevel,
                tokensEarned = m.tokensEarned,
                lastPlayTime = m.lastPlayTime,
                chestGranted = m.chestGranted,
                champion_name = champ and champ.name or ("Champion " .. m.championId),
                champion_id_str = champ and champ.id or nil,
                champion_image = champ and champ.image or nil,
                champion_title = champ and champ.title or nil,
            })
        end
    end

    -- Get recent match IDs
    local match_ids, _ = funcs.new():call("app.lc:riot_api_get_matches", {puuid = puuid, count = 5})

    -- Fetch full match details
    local matches = {}
    if match_ids then
        for _, mid in ipairs(match_ids) do
            local match_data, merr = funcs.new():call("app.lc:riot_api_get_match", {match_id = mid})
            if match_data and not merr then
                local participant = nil
                if match_data.info and match_data.info.participants then
                    for _, p in ipairs(match_data.info.participants) do
                        if p.puuid == puuid then
                            participant = p
                            break
                        end
                    end
                end

                if participant then
                    local info = match_data.info or {}
                    local cs = (participant.totalMinionsKilled or 0) + (participant.neutralMinionsKilled or 0)
                    local game_duration = info.gameDuration or 0
                    local cs_per_min = 0
                    if game_duration > 0 then
                        cs_per_min = math.floor(cs / (game_duration / 60) * 10) / 10
                    end
                    local duration_min = math.floor(game_duration / 60)
                    local duration_sec = game_duration % 60

                    -- Resolve champion image
                    local champ = champions[tostring(participant.championId)]
                    local champ_image = champ and champ.image or nil

                    table.insert(matches, {
                        match_id = mid,
                        champion_name = participant.championName,
                        champion_image = champ_image,
                        kills = participant.kills or 0,
                        deaths = participant.deaths or 0,
                        assists = participant.assists or 0,
                        cs = cs,
                        cs_per_min = cs_per_min,
                        vision_score = participant.visionScore or 0,
                        total_damage = participant.totalDamageDealtToChampions or 0,
                        gold_earned = participant.goldEarned or 0,
                        win = participant.win,
                        game_duration = string.format("%d:%02d", duration_min, duration_sec),
                        game_mode = info.gameMode,
                        position = participant.teamPosition or "",
                        queue_id = info.queueId,
                    })
                end
            end
        end
    end

    local profile_icon_url = nil
    if summoner and summoner.profileIconId then
        profile_icon_url = "https://ddragon.leagueoflegends.com/cdn/" .. dd_version
            .. "/img/profileicon/" .. tostring(summoner.profileIconId) .. ".png"
    end

    -- Save recent search to DB
    local storage, serr = contract.open("app.lc.lib:player_storage")
    if not serr and storage then
        storage:save_recent_search({
            puuid = puuid,
            game_name = account.gameName or game_name,
            tag_line = account.tagLine or tag_line,
            summoner_level = summoner and summoner.summonerLevel,
            profile_icon_id = summoner and summoner.profileIconId,
            platform = env.get("RIOT_PLATFORM") or "EUW1",
        })
    end

    res:set_status(200)
    res:write_json({
        account = {
            puuid = puuid,
            game_name = account.gameName,
            tag_line = account.tagLine,
        },
        summoner = summoner and {
            level = summoner.summonerLevel,
            profile_icon_id = summoner.profileIconId,
            profile_icon_url = profile_icon_url,
        } or nil,
        ranked = ranked,
        mastery = enriched_mastery,
        matches = matches,
        dd_version = dd_version,
    })
end

return {handler = handler}
