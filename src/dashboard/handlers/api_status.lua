local http = require("http")
local json = require("json")
local funcs = require("funcs")

--- GET /api/status — Server status with incidents/maintenance
local function handler()
    local res = http.response()

    local status, err = funcs.new():call("app.lc:riot_api_get_status", {})
    if err then
        res:set_status(200)
        res:write_json({incidents = {}, maintenances = {}})
        return
    end

    local incidents = {}
    if status.incidents then
        for _, inc in ipairs(status.incidents) do
            local title = ""
            local content = ""
            if inc.titles and #inc.titles > 0 then
                title = inc.titles[1].content or ""
            end
            if inc.updates and #inc.updates > 0 then
                local latest = inc.updates[1]
                if latest.translations and #latest.translations > 0 then
                    content = latest.translations[1].content or ""
                end
            end
            table.insert(incidents, {
                id = inc.id,
                title = title,
                content = content,
                severity = inc.incident_severity or "info",
                created_at = inc.created_at,
            })
        end
    end

    local maintenances = {}
    if status.maintenances then
        for _, m in ipairs(status.maintenances) do
            local title = ""
            local content = ""
            if m.titles and #m.titles > 0 then
                title = m.titles[1].content or ""
            end
            if m.updates and #m.updates > 0 then
                local latest = m.updates[1]
                if latest.translations and #latest.translations > 0 then
                    content = latest.translations[1].content or ""
                end
            end
            table.insert(maintenances, {
                id = m.id,
                title = title,
                content = content,
                maintenance_status = m.maintenance_status,
                created_at = m.created_at,
            })
        end
    end

    res:set_status(200)
    res:write_json({
        name = status.name or "",
        incidents = incidents,
        maintenances = maintenances,
    })
end

return {handler = handler}
