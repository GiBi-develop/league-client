local http_client = require("http_client")
local json = require("json")

local DDRAGON_BASE = "https://ddragon.leagueoflegends.com"

--- Get the latest Data Dragon version.
--- Returns: version string (e.g. "14.5.1")
local function get_latest_version()
    local resp, err = http_client.get(DDRAGON_BASE .. "/api/versions.json", {
        timeout = "10s",
        headers = {["User-Agent"] = "wippy-league-client/1.0"},
    })

    if err then return nil, "HTTP request failed: " .. tostring(err) end
    if resp.status_code ~= 200 then
        return nil, "Data Dragon returned " .. resp.status_code
    end

    local versions = json.decode(resp.body)
    if not versions or #versions == 0 then
        return nil, "No versions found"
    end

    return {version = versions[1]}
end

--- Get all champions data.
--- Input: {version? = "14.5.1", lang? = "en_US"}
--- Returns: champion data map keyed by numeric champion ID (as string)
local function get_champions(meta)
    local version = meta and meta.version
    if not version then
        local v, err = get_latest_version()
        if err then return nil, err end
        version = v.version
    end

    local lang = (meta and meta.lang) or "en_US"
    local url = DDRAGON_BASE .. "/cdn/" .. version .. "/data/" .. lang .. "/champion.json"

    local resp, err = http_client.get(url, {
        timeout = "15s",
        headers = {["User-Agent"] = "wippy-league-client/1.0"},
    })

    if err then return nil, "HTTP request failed: " .. tostring(err) end
    if resp.status_code ~= 200 then
        return nil, "Data Dragon returned " .. resp.status_code
    end

    local data = json.decode(resp.body)
    if not data or not data.data then
        return nil, "Invalid champion data format"
    end

    -- Build champion ID -> name mapping
    local champions = {}
    for key, champ in pairs(data.data) do
        champions[tostring(champ.key)] = {
            id = key,
            name = champ.name,
            title = champ.title,
            key = champ.key,
            image = DDRAGON_BASE .. "/cdn/" .. version .. "/img/champion/" .. key .. ".png",
        }
    end

    return {version = version, champions = champions}
end

--- Get all items data.
--- Input: {version? = "14.5.1", lang? = "en_US"}
--- Returns: {version, items} where items is keyed by item ID string
local function get_items(meta)
    local version = meta and meta.version
    if not version then
        local v, err = get_latest_version()
        if err then return nil, err end
        version = v.version
    end

    local lang = (meta and meta.lang) or "en_US"
    local url = DDRAGON_BASE .. "/cdn/" .. version .. "/data/" .. lang .. "/item.json"

    local resp, err = http_client.get(url, {
        timeout = "15s",
        headers = {["User-Agent"] = "wippy-league-client/1.0"},
    })

    if err then return nil, "HTTP request failed: " .. tostring(err) end
    if resp.status_code ~= 200 then
        return nil, "Data Dragon returned " .. resp.status_code
    end

    local data = json.decode(resp.body)
    if not data or not data.data then
        return nil, "Invalid item data format"
    end

    local items = {}
    for id, item in pairs(data.data) do
        items[id] = {
            name = item.name,
            description = item.plaintext or "",
            gold_total = item.gold and item.gold.total or 0,
            gold_sell = item.gold and item.gold.sell or 0,
            image = DDRAGON_BASE .. "/cdn/" .. version .. "/img/item/" .. id .. ".png",
        }
    end

    return {version = version, items = items}
end

--- Get runes (reforged) data.
--- Input: {version? = "14.5.1", lang? = "en_US"}
--- Returns: {version, runes} where runes is keyed by rune ID
local function get_runes(meta)
    local version = meta and meta.version
    if not version then
        local v, err = get_latest_version()
        if err then return nil, err end
        version = v.version
    end

    local lang = (meta and meta.lang) or "en_US"
    local url = DDRAGON_BASE .. "/cdn/" .. version .. "/data/" .. lang .. "/runesReforged.json"

    local resp, err = http_client.get(url, {
        timeout = "15s",
        headers = {["User-Agent"] = "wippy-league-client/1.0"},
    })

    if err then return nil, "HTTP request failed: " .. tostring(err) end
    if resp.status_code ~= 200 then
        return nil, "Data Dragon returned " .. resp.status_code
    end

    local data = json.decode(resp.body)
    if not data then
        return nil, "Invalid rune data format"
    end

    -- Build rune ID -> data map (includes styles and individual runes)
    local runes = {}
    for _, tree in ipairs(data) do
        -- Rune tree (e.g. Precision, Domination)
        runes[tostring(tree.id)] = {
            name = tree.name,
            icon = DDRAGON_BASE .. "/cdn/img/" .. tree.icon,
            is_tree = true,
        }

        -- Individual runes in each slot
        if tree.slots then
            for _, slot in ipairs(tree.slots) do
                if slot.runes then
                    for _, rune in ipairs(slot.runes) do
                        runes[tostring(rune.id)] = {
                            name = rune.name,
                            icon = DDRAGON_BASE .. "/cdn/img/" .. rune.icon,
                            short_desc = rune.shortDesc or "",
                            long_desc = rune.longDesc or "",
                            tree_id = tree.id,
                            tree_name = tree.name,
                        }
                    end
                end
            end
        end
    end

    return {version = version, runes = runes}
end

return {
    get_latest_version = get_latest_version,
    get_champions = get_champions,
    get_items = get_items,
    get_runes = get_runes,
}
