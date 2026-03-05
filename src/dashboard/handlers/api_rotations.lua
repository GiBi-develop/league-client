local http = require("http")
local json = require("json")
local funcs = require("funcs")

--- GET /api/rotations — Free champion rotation
local function handler()
    local res = http.response()

    -- Get champion rotations from Riot API
    local rotations, err = funcs.new():call("app.lc:riot_api_get_champion_rotations", {})
    if err then
        res:set_status(502)
        res:write_json({error = "Failed to get rotations: " .. tostring(err)})
        return
    end

    -- Get DDragon champion data for enrichment
    local dd_data, _ = funcs.new():call("app.lc:ddragon_get_champions", {})
    local dd_version = (dd_data and dd_data.version) or "14.5.1"
    local champions = (dd_data and dd_data.champions) or {}

    -- champions map is already keyed by numeric champion ID (as string)
    -- Enrich free rotation
    local free_champions = {}
    if rotations and rotations.freeChampionIds then
        for _, cid in ipairs(rotations.freeChampionIds) do
            local c = champions[tostring(cid)]
            table.insert(free_champions, {
                champion_id = cid,
                name = c and c.name or ("Champion " .. cid),
                id = c and c.id or nil,
                image = c and c.image or nil,
                title = c and c.title or nil,
            })
        end
        table.sort(free_champions, function(a, b) return a.name < b.name end)
    end

    -- Enrich new player rotation
    local new_player_champions = {}
    if rotations and rotations.freeChampionIdsForNewPlayers then
        for _, cid in ipairs(rotations.freeChampionIdsForNewPlayers) do
            local c = champions[tostring(cid)]
            table.insert(new_player_champions, {
                champion_id = cid,
                name = c and c.name or ("Champion " .. cid),
                id = c and c.id or nil,
                image = c and c.image or nil,
            })
        end
        table.sort(new_player_champions, function(a, b) return a.name < b.name end)
    end

    res:set_status(200)
    res:write_json({
        free_champions = free_champions,
        new_player_champions = new_player_champions,
        max_new_player_level = rotations and rotations.maxNewPlayerLevel or 0,
        dd_version = dd_version,
    })
end

return {handler = handler}
