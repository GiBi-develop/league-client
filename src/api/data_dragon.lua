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
--- Returns: champion data map
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
            image = DDRAGON_BASE .. "/cdn/" .. version .. "/img/champion/" .. key .. ".png",
        }
    end

    return {version = version, champions = champions}
end

return {
    get_latest_version = get_latest_version,
    get_champions = get_champions,
}
