local W = Warden

local function capturing() return GetResourceState('fivecapture') == 'started' end

-- Calls back once with whatever came, or with nothing after `wait` ms.
local function once(wait, cb)
    local done = false
    local function finish(...)
        if done then return end
        done = true
        cb(...)
    end
    SetTimeout(wait, finish)
    return finish
end

function W.screenshot(src, cb)
    if not Config.screenshots then return cb() end
    local finish = once(8000, cb)
    local ok = pcall(function()
        if capturing() then
            exports.fivecapture:screenshot(src, { encoding = 'jpg', quality = 0.8 }, function(err, r)
                finish(not err and r and r.data or nil)
            end)
        elseif GetResourceState('screenshot-basic') == 'started' then
            exports['screenshot-basic']:requestClientScreenshot(src, { encoding = 'jpg', quality = 0.8 }, function(err, data)
                finish(not err and type(data) == 'string' and data or nil)
            end)
        else
            finish()
        end
    end)
    if not ok then finish() end
end

-- A video of the player's screen, saved by fivecapture. Calls back with its
-- file path, or nothing.
function W.clip(src, cb)
    local seconds = Config.clip or 0
    if seconds <= 0 or not capturing() then return cb() end
    local finish = once((seconds + 30) * 1000, cb)
    local ok = pcall(function()
        exports.fivecapture:record(src, seconds, { save = true }, function(err, r)
            finish(not err and r and r.file or nil)
        end)
    end)
    if not ok then finish() end
end

-- Screenshot and clip together, so the clip doesn't add the screenshot's wait.
function W.evidence(src, cb)
    local image, clip, left = nil, nil, 2
    local function one()
        left = left - 1
        if left == 0 then cb(image, clip) end
    end
    W.screenshot(src, function(i) image = i; one() end)
    W.clip(src, function(c) clip = c; one() end)
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

    W.evidence(src, function(image, clip)
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

        W.log(('%s · %s'):format(title, W.labels[kind] or kind), table.concat(lines, '\n'), W.colors[action], image, clip)
        TriggerEvent('warden:punished', src, action, kind, detail, ids.name, ids.license, image, clip)
        W.notifyStaff(('%s %s: %s'):format(ids.name, action == 'ban' and 'banned' or 'kicked', W.labels[kind] or kind))
    end)
end
