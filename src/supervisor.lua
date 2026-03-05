local logger = require("logger")
local registry = require("registry")
local time = require("time")

--- Spawn a monitored fetcher and register it in the watchers table.
local function spawn_fetcher(watchers, entry)
    local interval = entry.meta.fetch_interval or "10m"

    logger:info("Spawning fetcher", {
        player = entry.id,
        name = entry.meta.game_name .. "#" .. entry.meta.tag_line,
        interval = interval,
    })

    local pid = process.spawn_monitored(
        "app.lc:fetcher",
        "app.lc:processes",
        entry.id,
        entry.meta,
        interval
    )

    watchers[pid] = {
        entry_id = entry.id,
        meta = entry.meta,
        interval = interval,
    }
end

--- Supervisor: discovers tracked player entries from registry,
--- spawns a monitored Fetcher process for each one.
local function main()
    logger:info("League client supervisor started", {pid = process.pid()})

    -- Discover all tracked player entries
    local entries, err = registry.find({["meta.type"] = "player"})
    if err then
        logger:error("Failed to discover players", {error = tostring(err)})
        return 1
    end

    logger:info("Discovered tracked players", {count = #entries})

    local watchers = {} -- pid -> {entry_id, meta, interval}

    -- Spawn a monitored fetcher per player
    for _, entry in ipairs(entries) do
        spawn_fetcher(watchers, entry)
    end

    -- Supervision loop
    local evts = process.events()

    while true do
        local event = evts:receive()

        if event.kind == process.event.CANCEL then
            logger:info("Supervisor shutting down")
            return 0
        end

        if event.kind == process.event.EXIT then
            local info = watchers[event.from]
            if info then
                watchers[event.from] = nil

                if event.result.error then
                    logger:warn("Fetcher crashed, restarting after backoff", {
                        player = info.entry_id,
                        name = info.meta.game_name .. "#" .. info.meta.tag_line,
                        error = event.result.error,
                    })

                    time.sleep("5s")

                    spawn_fetcher(watchers, {
                        id = info.entry_id,
                        meta = info.meta,
                    })
                else
                    logger:info("Fetcher exited cleanly", {
                        player = info.entry_id,
                        name = info.meta.game_name .. "#" .. info.meta.tag_line,
                    })
                end
            end
        end
    end
end

return {main = main}
