local W = Warden

function W.screenshot(src, cb)
    if not Config.screenshots or GetResourceState('screenshot-basic') ~= 'started' then return cb() end

    local done = false
    local function finish(image)
        if done then return end
        done = true
        cb(image)
    end

    SetTimeout(8000, finish)
    local ok = pcall(function()
        exports['screenshot-basic']:requestClientScreenshot(src, { encoding = 'jpg', quality = 0.8 }, function(err, data)
            finish(not err and type(data) == 'string' and data or nil)
        end)
    end)
    if not ok then finish() end
end

local function ban(src, ids, reason, detail)
    if W.fivecord() then
        local full = detail and ('%s (%s)'):format(reason, detail) or reason
        local ok, banned = pcall(function() return exports.fivecord:ban(src, full, Config.banLength, 'warden') end)
        if ok and banned then return 'fivecord' end
    end
    return W.bans.add(ids, reason, detail)
end

-- Kick or ban. The player is marked first so nothing else fires while the
-- screenshot comes back.
function W.punish(src, action, kind, detail)
    local p = W.player(src)
    if not p or p.gone then return end
    p.gone = true

    local ids = W.identity(src)
    local history = W.history(src) -- before they're dropped and fivelog forgets them
    local reason = 'Anticheat: ' .. (W.labels[kind] or kind)

    W.screenshot(src, function(image)
        local lines = { W.describe(src, ids) }
        if detail then lines[#lines + 1] = detail end
        if history then lines[#lines + 1] = history end
        local title

        if action == 'ban' then
            local b = ban(src, ids, reason, detail)
            if b == 'fivecord' then
                title = 'Banned through fivecord'
                -- fivecord drops them with its own ban screen. Make sure they go.
                SetTimeout(5000, function()
                    if GetPlayerName(src) then DropPlayer(src, reason) end
                end)
            else
                title = ('Ban #%d'):format(b.id)
                DropPlayer(src, W.banMessage(b))
            end
        else
            title = 'Kicked'
            DropPlayer(src, Config.kickMessage)
        end

        W.log(('%s · %s'):format(title, W.labels[kind] or kind), table.concat(lines, '\n'), W.colors[action], image)
        TriggerEvent('warden:punished', src, action, kind, detail, ids.name, ids.license, image)
        W.notifyStaff(('%s %s: %s'):format(ids.name, action == 'ban' and 'banned' or 'kicked', W.labels[kind] or kind))
    end)
end
