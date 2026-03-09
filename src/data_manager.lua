local logger = require("logger")
local events = require("events")
local contract = require("contract")
local time = require("time")
local funcs = require("funcs")

--- Tier weight for rank goal comparison (higher = better rank).
local function tier_weight(tier)
    if not tier then return 0 end
    local t = string.upper(tier)
    if t == "IRON" then return 0
    elseif t == "BRONZE" then return 4
    elseif t == "SILVER" then return 8
    elseif t == "GOLD" then return 12
    elseif t == "PLATINUM" then return 16
    elseif t == "EMERALD" then return 20
    elseif t == "DIAMOND" then return 24
    elseif t == "MASTER" then return 28
    elseif t == "GRANDMASTER" then return 29
    elseif t == "CHALLENGER" then return 30
    end
    return 0
end

--- Rank division weight (I=3, II=2, III=1, IV=0).
local function rank_weight(rank)
    if rank == "I" then return 3
    elseif rank == "II" then return 2
    elseif rank == "III" then return 1
    end
    return 0
end

--- Convert tier+rank+lp to absolute LP value for comparison.
local function lp_absolute(tier, rank, lp)
    return tier_weight(tier) * 100 + rank_weight(rank) * 100 + (lp or 0)
end

--- Parse a rank target string like "Gold I", "PLATINUM", "Diamond IV".
--- Returns tier (uppercase), rank (uppercase or nil).
local function parse_rank_target(target)
    local upper = string.upper(target or "")
    local tiers = {"CHALLENGER","GRANDMASTER","MASTER","DIAMOND","EMERALD","PLATINUM","GOLD","SILVER","BRONZE","IRON"}
    local found_tier = nil
    for _, t in ipairs(tiers) do
        if string.find(upper, t, 1, true) then
            found_tier = t
            break
        end
    end
    if not found_tier then return nil, nil end
    if string.find(upper, " I", 1, true) and not string.find(upper, " II", 1, true) and not string.find(upper, " III", 1, true) and not string.find(upper, " IV", 1, true) then
        return found_tier, "I"
    elseif string.find(upper, "IV", 1, true) then
        return found_tier, "IV"
    elseif string.find(upper, "III", 1, true) then
        return found_tier, "III"
    elseif string.find(upper, "II", 1, true) then
        return found_tier, "II"
    end
    return found_tier, nil
end

--- Parse timeline data and save early-game stats + objectives + skill order.
local function parse_and_save_timeline(storage, match_id, puuid, region, participant_id, team_id)
    local timeline, terr = funcs.new():call("app.lc:riot_api_get_match_timeline", {
        match_id = match_id,
        region = region,
    })

    if terr or not timeline or not timeline.info or not timeline.info.frames then
        return
    end

    local frames = timeline.info.frames
    local cs_at_10 = 0
    local cs_at_15 = 0
    local gold_at_10 = 0
    local gold_at_15 = 0
    local gold_diff_at_10 = 0
    local gold_diff_at_15 = 0
    local xp_diff_at_10 = 0
    local first_blood_time = 0

    -- Find our participant ID from timeline participants
    local my_pid = nil
    local my_team = team_id or 100
    if timeline.info.participants then
        for _, tp in ipairs(timeline.info.participants) do
            if tp.puuid == puuid then
                my_pid = tp.participantId
                break
            end
        end
    end

    if not my_pid then return end

    -- Find lane opponent (same position, other team)
    local opp_pid = nil
    -- Simple heuristic: opponent is my_pid + 5 or my_pid - 5
    if my_pid <= 5 then opp_pid = my_pid + 5
    else opp_pid = my_pid - 5 end

    for _, frame in ipairs(frames) do
        local ts_min = (frame.timestamp or 0) / 60000

        if frame.participantFrames then
            local my_frame = frame.participantFrames[tostring(my_pid)]
            local opp_frame = frame.participantFrames[tostring(opp_pid)]

            if my_frame then
                local my_cs = (tonumber(my_frame.minionsKilled) or 0) + (tonumber(my_frame.jungleMinionsKilled) or 0)
                local my_gold = tonumber(my_frame.totalGold) or 0
                local my_xp = tonumber(my_frame.xp) or 0

                local opp_gold = opp_frame and (tonumber(opp_frame.totalGold) or 0) or 0
                local opp_xp = opp_frame and (tonumber(opp_frame.xp) or 0) or 0

                if ts_min >= 10 and cs_at_10 == 0 then
                    cs_at_10 = my_cs
                    gold_at_10 = my_gold
                    gold_diff_at_10 = my_gold - opp_gold
                    xp_diff_at_10 = my_xp - opp_xp
                end
                if ts_min >= 15 and cs_at_15 == 0 then
                    cs_at_15 = my_cs
                    gold_at_15 = my_gold
                    gold_diff_at_15 = my_gold - opp_gold
                end
            end
        end

        -- Track first blood time
        if frame.events and first_blood_time == 0 then
            for _, evt in ipairs(frame.events) do
                if evt.type == "CHAMPION_KILL" then
                    if (tonumber(evt.killerId) or 0) == my_pid or (tonumber(evt.victimId) or 0) == my_pid then
                        first_blood_time = math.floor((evt.timestamp or 0) / 1000)
                        break
                    end
                end
            end
        end
    end

    -- Save timeline stats
    storage:save_timeline_stats({
        match_id = match_id,
        puuid = puuid,
        cs_at_10 = cs_at_10,
        cs_at_15 = cs_at_15,
        gold_at_10 = gold_at_10,
        gold_at_15 = gold_at_15,
        gold_diff_at_10 = gold_diff_at_10,
        gold_diff_at_15 = gold_diff_at_15,
        xp_diff_at_10 = xp_diff_at_10,
        first_blood_time = first_blood_time,
    })

    logger:debug("Timeline stats saved", {match_id = match_id})
end

--- Opens the player storage contract.
local function open_storage()
    local svc, err = contract.open("app.lc.lib:player_storage")
    if err then
        error("Failed to open player_storage contract: " .. tostring(err))
    end
    return svc
end

--- Extract participant data for a specific PUUID from match data.
local function extract_participant(match_data, puuid)
    if not match_data or not match_data.info or not match_data.info.participants then
        return nil
    end

    for _, p in ipairs(match_data.info.participants) do
        if p.puuid == puuid then
            return p
        end
    end
    return nil
end

--- Extract rune/perk info from participant data.
local function extract_perks(participant)
    local keystone = 0
    local primary_style = 0
    local sub_style = 0

    if participant.perks and participant.perks.styles then
        for _, style in ipairs(participant.perks.styles) do
            if style.description == "primaryStyle" then
                primary_style = style.style or 0
                if style.selections and #style.selections > 0 then
                    keystone = style.selections[1].perk or 0
                end
            elseif style.description == "subStyle" then
                sub_style = style.style or 0
            end
        end
    end

    return keystone, primary_style, sub_style
end

--- Build full participant data for DB storage from raw API participant.
local function build_participant_data(p)
    local p_cs = (p.totalMinionsKilled or 0) + (p.neutralMinionsKilled or 0)
    local p_items = {}
    for idx = 0, 6 do
        if p["item" .. idx] and p["item" .. idx] > 0 then
            table.insert(p_items, p["item" .. idx])
        end
    end

    local keystone, primary_style, sub_style = extract_perks(p)

    local challenges = p.challenges or {}

    return {
        puuid = p.puuid,
        team_id = p.teamId,
        champion_id = p.championId,
        champion_name = p.championName,
        summoner_name = p.riotIdGameName or p.summonerName or "Unknown",
        tag_line = p.riotIdTagline or "",
        kills = p.kills or 0,
        deaths = p.deaths or 0,
        assists = p.assists or 0,
        cs = p_cs,
        total_damage = p.totalDamageDealtToChampions or 0,
        gold_earned = p.goldEarned or 0,
        vision_score = p.visionScore or 0,
        position = p.teamPosition or "",
        win = p.win,
        items = p_items,
        summoner1 = p.summoner1Id or 0,
        summoner2 = p.summoner2Id or 0,
        double_kills = p.doubleKills or 0,
        triple_kills = p.tripleKills or 0,
        quadra_kills = p.quadraKills or 0,
        penta_kills = p.pentaKills or 0,
        physical_damage = p.physicalDamageDealtToChampions or 0,
        magic_damage = p.magicDamageDealtToChampions or 0,
        true_damage = p.trueDamageDealtToChampions or 0,
        damage_taken = p.totalDamageTaken or 0,
        wards_placed = p.wardsPlaced or 0,
        wards_killed = p.wardsKilled or 0,
        control_wards = p.detectorWardsPlaced or 0,
        kill_participation = challenges.killParticipation or 0,
        damage_share = challenges.teamDamagePercentage or 0,
        perks_keystone = keystone,
        perks_primary_style = primary_style,
        perks_sub_style = sub_style,
        champ_level = p.champLevel or 0,
    }
end

--- Handle a player.data_fetched event.
local function handle_data_fetched(storage, data)
    local puuid = data.puuid
    if not puuid then
        logger:warn("data_fetched event missing puuid")
        return
    end

    -- Get previous ranked data for comparison
    local prev_ranked = storage:get_ranked({puuid = puuid})

    -- Save player profile
    if data.summoner then
        local _, err = storage:save_player({
            puuid = puuid,
            game_name = data.game_name,
            tag_line = data.tag_line,
            summoner_id = data.summoner.id,
            summoner_level = data.summoner.summonerLevel,
            profile_icon_id = data.summoner.profileIconId,
            revision_date = data.summoner.revisionDate,
            platform = data.platform,
            region = data.region,
            total_mastery_score = data.mastery_score,
        })
        if err then
            logger:error("Failed to save player", {puuid = puuid, error = tostring(err)})
        end
    end

    -- Save ranked data and detect changes; collect LP diffs for match events
    local lp_diffs = {} -- queue_type -> {lp_diff, new_tier, new_rank, new_lp}
    if data.ranked then
        for _, entry in ipairs(data.ranked) do
            -- Find previous rank for this queue
            local old_tier = nil
            local old_rank = nil
            local old_lp = nil
            if prev_ranked and type(prev_ranked) == "table" then
                for _, prev in ipairs(prev_ranked) do
                    if prev.queue_type == entry.queueType then
                        old_tier = prev.tier
                        old_rank = prev.rank
                        old_lp = prev.league_points
                        break
                    end
                end
            end

            -- Track LP diff for this queue
            if old_lp then
                local diff = (entry.leaguePoints or 0) - old_lp
                if diff ~= 0 then
                    lp_diffs[entry.queueType] = {
                        lp_diff = diff,
                        new_tier = entry.tier,
                        new_rank = entry.rank,
                        new_lp = entry.leaguePoints,
                    }
                end
            end

            local _, err = storage:save_ranked({
                puuid = puuid,
                queue_type = entry.queueType,
                tier = entry.tier,
                rank = entry.rank,
                league_points = entry.leaguePoints,
                wins = entry.wins,
                losses = entry.losses,
                hot_streak = entry.hotStreak,
                veteran = entry.veteran,
                fresh_blood = entry.freshBlood,
            })
            if err then
                logger:error("Failed to save ranked", {puuid = puuid, error = tostring(err)})
            end

            -- Record LP history
            storage:save_ranked_history({
                puuid = puuid,
                queue_type = entry.queueType,
                tier = entry.tier,
                rank = entry.rank,
                league_points = entry.leaguePoints,
                wins = entry.wins,
                losses = entry.losses,
            })

            -- Detect rank change
            if old_tier and (old_tier ~= entry.tier or old_rank ~= entry.rank or old_lp ~= entry.leaguePoints) then
                logger:info("RANK CHANGED", {
                    player = data.player_name,
                    queue = entry.queueType,
                    old = old_tier .. " " .. old_rank .. " " .. tostring(old_lp) .. "LP",
                    new = entry.tier .. " " .. entry.rank .. " " .. tostring(entry.leaguePoints) .. "LP",
                })

                events.send("league_client", "player.rank_changed", "/players/" .. data.player_id, {
                    player_id = data.player_id,
                    player_name = data.player_name,
                    puuid = puuid,
                    queue_type = entry.queueType,
                    old_tier = old_tier,
                    old_rank = old_rank,
                    old_lp = old_lp,
                    new_tier = entry.tier,
                    new_rank = entry.rank,
                    new_lp = entry.leaguePoints,
                    wins = entry.wins,
                    losses = entry.losses,
                    discord_notify = data.discord_notify or false,
                })
            end
        end
    end

    -- Check rank goals for completion
    if data.ranked then
        local goals_result = storage:get_goals({puuid = puuid})
        local goals = goals_result and goals_result.goals or {}
        for _, goal in ipairs(goals) do
            if goal.completed == 0 and goal.goal_type == "rank" then
                local target_tier, target_rank = parse_rank_target(goal.target_value)
                if target_tier then
                    local target_abs = lp_absolute(target_tier, target_rank or "I", 0)
                    for _, entry in ipairs(data.ranked) do
                        local curr_abs = lp_absolute(entry.tier, entry.rank, tonumber(entry.leaguePoints) or 0)
                        if curr_abs >= target_abs then
                            storage:complete_goal({id = goal.id})
                            local queue_name = entry.queueType == "RANKED_SOLO_5x5" and "Solo/Duo"
                                or entry.queueType == "RANKED_FLEX_SR" and "Flex"
                                or entry.queueType or "Ranked"
                            logger:info("GOAL ACHIEVED", {
                                player = data.player_name,
                                goal = goal.target_value,
                                queue = queue_name,
                                current = entry.tier .. " " .. entry.rank,
                            })
                            events.send("league_client", "player.goal_achieved", "/players/" .. data.player_id, {
                                player_id = data.player_id,
                                player_name = data.player_name,
                                puuid = puuid,
                                goal_type = goal.goal_type,
                                target_value = goal.target_value,
                                queue_type = entry.queueType,
                                current_tier = entry.tier,
                                current_rank = entry.rank,
                                current_lp = entry.leaguePoints,
                                discord_notify = data.discord_notify or false,
                            })
                            break
                        end
                    end
                end
            end
        end
    end

    -- Save mastery data
    if data.mastery then
        for _, entry in ipairs(data.mastery) do
            local _, err = storage:save_mastery({
                puuid = puuid,
                champion_id = entry.championId,
                champion_level = entry.championLevel,
                champion_points = entry.championPoints,
            })
            if err then
                logger:error("Failed to save mastery", {puuid = puuid, error = tostring(err)})
            end
        end
    end

    -- Save match data
    if data.matches then
        for _, match_data in ipairs(data.matches) do
            local participant = extract_participant(match_data, puuid)
            if participant and match_data.metadata then
                local match_id = match_data.metadata.matchId
                local info = match_data.info or {}

                -- Collect items
                local items = {}
                for i = 0, 6 do
                    local item_key = "item" .. i
                    if participant[item_key] and participant[item_key] > 0 then
                        table.insert(items, participant[item_key])
                    end
                end

                local cs = (participant.totalMinionsKilled or 0) + (participant.neutralMinionsKilled or 0)
                local game_duration = info.gameDuration or 0
                local cs_per_min = 0
                if game_duration > 0 then
                    cs_per_min = math.floor(cs / (game_duration / 60) * 10) / 10
                end

                local challenges = participant.challenges or {}
                local keystone, primary_style, sub_style = extract_perks(participant)

                local result, err = storage:save_match({
                    match_id = match_id,
                    puuid = puuid,
                    champion_id = participant.championId,
                    champion_name = participant.championName,
                    kills = participant.kills,
                    deaths = participant.deaths,
                    assists = participant.assists,
                    cs = cs,
                    vision_score = participant.visionScore,
                    total_damage = participant.totalDamageDealtToChampions,
                    gold_earned = participant.goldEarned,
                    win = participant.win,
                    game_duration = game_duration,
                    game_mode = info.gameMode,
                    queue_id = info.queueId,
                    position = participant.teamPosition,
                    items = items,
                    game_creation = info.gameCreation,
                    summoner1 = participant.summoner1Id,
                    summoner2 = participant.summoner2Id,
                    cs_per_min = cs_per_min,
                    double_kills = participant.doubleKills,
                    triple_kills = participant.tripleKills,
                    quadra_kills = participant.quadraKills,
                    penta_kills = participant.pentaKills,
                    physical_damage = participant.physicalDamageDealtToChampions,
                    magic_damage = participant.magicDamageDealtToChampions,
                    true_damage = participant.trueDamageDealtToChampions,
                    damage_taken = participant.totalDamageTaken,
                    wards_placed = participant.wardsPlaced,
                    wards_killed = participant.wardsKilled,
                    control_wards = participant.detectorWardsPlaced,
                    kill_participation = challenges.killParticipation,
                    damage_share = challenges.teamDamagePercentage,
                    gold_per_min = challenges.goldPerMinute,
                    damage_per_min = challenges.damagePerMinute,
                    perks_primary_style = primary_style,
                    perks_sub_style = sub_style,
                    perks_keystone = keystone,
                    champ_level = participant.champLevel,
                    gold_spent = participant.goldSpent,
                    game_ended_surrender = participant.gameEndedInSurrender,
                    first_blood = participant.firstBloodKill,
                })

                -- Save all 10 participants for this match
                if result and result.inserted and info.participants then
                    local all_participants = {}
                    for _, p in ipairs(info.participants) do
                        table.insert(all_participants, build_participant_data(p))
                    end
                    storage:save_match_participants({
                        match_id = match_id,
                        participants = all_participants,
                    })
                end

                -- Save personal records (#11)
                if result and result.inserted then
                    local game_dur = game_duration
                    local cs_pm = cs_per_min
                    storage:save_record({puuid = puuid, record_type = "most_kills", value = participant.kills or 0, match_id = match_id, champion_name = participant.championName})
                    storage:save_record({puuid = puuid, record_type = "most_assists", value = participant.assists or 0, match_id = match_id, champion_name = participant.championName})
                    storage:save_record({puuid = puuid, record_type = "most_cs", value = cs, match_id = match_id, champion_name = participant.championName})
                    storage:save_record({puuid = puuid, record_type = "most_damage", value = participant.totalDamageDealtToChampions or 0, match_id = match_id, champion_name = participant.championName})
                    storage:save_record({puuid = puuid, record_type = "most_gold", value = participant.goldEarned or 0, match_id = match_id, champion_name = participant.championName})
                    storage:save_record({puuid = puuid, record_type = "best_kda", value = (participant.kills or 0) + (participant.assists or 0) - (participant.deaths or 0), match_id = match_id, champion_name = participant.championName})
                    storage:save_record({puuid = puuid, record_type = "most_vision", value = participant.visionScore or 0, match_id = match_id, champion_name = participant.championName})
                    storage:save_record({puuid = puuid, record_type = "best_cs_per_min", value = cs_pm, match_id = match_id, champion_name = participant.championName})
                    storage:save_record({puuid = puuid, record_type = "lowest_deaths", value = participant.deaths or 0, match_id = match_id, champion_name = participant.championName})
                    if (participant.pentaKills or 0) > 0 then
                        storage:save_record({puuid = puuid, record_type = "penta_kills", value = participant.pentaKills, match_id = match_id, champion_name = participant.championName})
                    end
                end

                -- Fetch and parse timeline for newly inserted matches (#Wave6)
                if result and result.inserted and game_duration >= 600 then
                    -- Only fetch timeline for games > 10 min (skip remakes/surrenders)
                    pcall(function()
                        parse_and_save_timeline(
                            storage, match_id, puuid,
                            data.region or "EUROPE",
                            participant.participantId,
                            participant.teamId
                        )
                    end)
                    time.sleep("300ms") -- Rate limit protection
                end

                -- Compute performance score for this match
                local perf = {score = 0, grade = "D"}
                if result and result.inserted then
                    perf = storage:compute_performance_score({
                        kills = participant.kills or 0,
                        deaths = participant.deaths or 0,
                        assists = participant.assists or 0,
                        cs_per_min = cs_per_min,
                        vision_score = participant.visionScore or 0,
                        damage_share = (challenges.teamDamagePercentage or 0),
                        kill_participation = (challenges.killParticipation or 0),
                        game_duration = game_duration,
                        win = participant.win,
                    })
                end

                -- Emit new match event ONLY if it was actually inserted (not a duplicate)
                -- and only for recent games (< 24h old) to avoid flooding on first backfill
                local game_age_ms = os.time() * 1000 - (info.gameCreation or 0)
                local is_recent_game = game_age_ms < 24 * 3600 * 1000
                if result and result.inserted and is_recent_game then
                    local duration_min = math.floor(game_duration / 60)
                    local duration_sec = game_duration % 60

                    -- Map queue_id to queue_type for LP diff lookup
                    local queue_type = nil
                    if info.queueId == 420 then queue_type = "RANKED_SOLO_5x5"
                    elseif info.queueId == 440 then queue_type = "RANKED_FLEX_SR"
                    end
                    local lp_info = queue_type and lp_diffs[queue_type] or nil

                    -- Store LP change per match (#Wave4)
                    if lp_info and lp_info.lp_diff then
                        storage:update_match_lp({
                            match_id = match_id,
                            puuid = puuid,
                            lp_change = lp_info.lp_diff,
                        })
                    end

                    events.send("league_client", "player.match_new", "/players/" .. data.player_id, {
                        player_id = data.player_id,
                        player_name = data.player_name,
                        puuid = puuid,
                        match_id = match_id,
                        champion_name = participant.championName,
                        kills = participant.kills,
                        deaths = participant.deaths,
                        assists = participant.assists,
                        cs = cs,
                        cs_per_min = cs_per_min,
                        vision_score = participant.visionScore,
                        total_damage = participant.totalDamageDealtToChampions,
                        gold_earned = participant.goldEarned,
                        win = participant.win,
                        game_duration = string.format("%d:%02d", duration_min, duration_sec),
                        game_mode = info.gameMode,
                        position = participant.teamPosition,
                        queue_id = info.queueId,
                        lp_diff = lp_info and lp_info.lp_diff or nil,
                        penta_kills = participant.pentaKills,
                        game_creation = info.gameCreation,
                        performance_score = perf.score or 0,
                        performance_grade = perf.grade or "D",
                        discord_notify = data.discord_notify or false,
                        discord_webhook_url = data.discord_webhook_url,
                    })
                end

                if err then
                    logger:error("Failed to save match", {match_id = match_id, error = tostring(err)})
                end
            end
        end
    end
end

--- Data Manager main loop.
--- Subscribes to league_client events, handles data persistence.
local function main()
    logger:info("Data manager started", {pid = process.pid()})

    -- Initialize DB schema via contract
    local storage = open_storage()
    local schema_result, schema_err = storage:init_schema()
    if schema_err then
        logger:error("Failed to init schema", {error = tostring(schema_err)})
        return 1
    end
    logger:info("DB schema initialized")

    -- Subscribe to all league_client events
    local sub, err = events.subscribe("league_client")
    if err then
        logger:error("Failed to subscribe to events", {error = tostring(err)})
        return 1
    end

    local ch = sub:channel()
    local evts = process.events()

    while true do
        local r = channel.select {
            ch:case_receive(),
            evts:case_receive(),
        }

        if r.channel == evts then
            if r.value.kind == process.event.CANCEL then
                sub:close()
                logger:info("Data manager stopping")
                return 0
            end
        else
            local evt = r.value
            if evt.kind == "player.data_fetched" then
                handle_data_fetched(storage, evt.data)
                -- When full fetch completes, player is no longer in game
                if evt.data.puuid then
                    storage:set_player_ingame({puuid = evt.data.puuid, in_game = false, game_id = nil})
                end
            elseif evt.kind == "player.game_started" then
                if evt.data.puuid then
                    storage:set_player_ingame({
                        puuid = evt.data.puuid,
                        in_game = true,
                        game_id = tostring(evt.data.game_id or ""),
                    })
                end
            end
        end
    end
end

return {main = main}
