local logger = require("logger")
local events = require("events")
local contract = require("contract")
local time = require("time")

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

                -- Emit new match event ONLY if it was actually inserted (not a duplicate)
                if result and result.inserted then
                    local duration_min = math.floor(game_duration / 60)
                    local duration_sec = game_duration % 60

                    -- Map queue_id to queue_type for LP diff lookup
                    local queue_type_map = {
                        [420] = "RANKED_SOLO_5x5",
                        [440] = "RANKED_FLEX_SR",
                    }
                    local queue_type = queue_type_map[info.queueId]
                    local lp_info = queue_type and lp_diffs[queue_type] or nil

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
                        discord_notify = data.discord_notify or false,
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
            end
        end
    end
end

return {main = main}
