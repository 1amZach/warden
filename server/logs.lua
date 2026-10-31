local W = Warden

local colors = { log = 0xF5A524, kick = 0xF97316, ban = 0xE5484D }

local lookup = {}
for i, c in ipairs({ ('ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/'):byte(1, -1) }) do
    lookup[c] = i - 1
end

local function unbase64(data)
    data = data:gsub('[^%w%+/]', '')
    local out = {}
    for i = 1, #data, 4 do
        local a, b, c, d = data:byte(i, i + 3)
        local n = (lookup[a] << 18) | ((lookup[b] or 0) << 12) | ((c and lookup[c] or 0) << 6) | (d and lookup[d] or 0)
        out[#out + 1] = string.char(n >> 16 & 255, n >> 8 & 255, n & 255):sub(1, d and 3 or c and 2 or 1)
    end
    return table.concat(out)
end
W.unbase64 = unbase64

local function webhook(embed, image)
    local url = GetConvar('warden_webhook', '')
    if url == '' then return end

    local payload = { username = 'warden', embeds = { embed }, allowed_mentions = { parse = {} } }
    if not image then
        return PerformHttpRequest(url, function() end, 'POST', json.encode(payload), { ['Content-Type'] = 'application/json' })
    end

    embed.image = { url = 'attachment://screenshot.jpg' }
    local boundary = ('warden%d'):format(math.random(1e8, 9e8))
    local body = table.concat({
        '--' .. boundary,
        'Content-Disposition: form-data; name="payload_json"',
        'Content-Type: application/json',
        '',
        json.encode(payload),
        '--' .. boundary,
        'Content-Disposition: form-data; name="files[0]"; filename="screenshot.jpg"',
        'Content-Type: image/jpeg',
        '',
        unbase64(image:match(',(.+)$') or image),
        '--' .. boundary .. '--',
        '',
    }, '\r\n')
    PerformHttpRequest(url, function() end, 'POST', body, { ['Content-Type'] = 'multipart/form-data; boundary=' .. boundary })
end

-- The clip goes up as its own message right after the log, so it plays in
-- Discord. fivecapture does the upload.
local function postClip(title, clip)
    local url = GetConvar('warden_webhook', '')
    if url == '' or GetResourceState('fivecapture') ~= 'started' then return end
    pcall(function() exports.fivecapture:upload(clip, { webhook = url, message = 'Clip: ' .. title }) end)
end

-- One log line. `image` is a screenshot as a data URI, `clip` the path of a
-- video saved by fivecapture.
function W.log(title, description, color, image, clip)
    print(('^3[warden]^7 %s: %s'):format(title, (description:gsub('%*', ''))))
    if clip then print(('^3[warden]^7 clip saved: %s'):format(clip)) end

    if W.fivecord() then
        local ok = pcall(function() exports.fivecord:log('anticheat', title, description, color, image, clip) end)
        if ok then return end
    end
    webhook({ title = title, description = description, color = color, timestamp = os.date('!%Y-%m-%dT%H:%M:%SZ') }, image)
    if clip then postClip(title, clip) end
end

function W.describe(src, ids)
    ids = ids or W.identity(src)
    local discord = ids.discord and (' · <@%s>'):format(ids.discord:sub(9)) or ''
    return ('**%s** (id %d)%s\n`%s`'):format(ids.name, src, discord, ids.license or ids.identifiers[1] or 'no license')
end

-- What the player did just before, from fivelog.
function W.history(src)
    if (Config.history or 0) <= 0 or GetResourceState('fivelog') ~= 'started' then return end
    local ok, list = pcall(function() return exports.fivelog:recent(src, Config.history) end)
    if not ok or type(list) ~= 'table' or #list == 0 then return end
    local out = { '**Just before**' }
    for _, e in ipairs(list) do
        local text = tostring(e.text):gsub('[*_`~|]', '\\%0')
        out[#out + 1] = ('<t:%d:T> %s'):format(tonumber(e.at) or 0, text:sub(1, 150))
    end
    return table.concat(out, '\n')
end

local function notifyStaff(text)
    for _, id in ipairs(GetPlayers()) do
        if IsPlayerAceAllowed(id, Config.notifyAce) then
            TriggerClientEvent('chat:addMessage', id, { color = { 245, 165, 36 }, args = { 'warden', text } })
        end
    end
end

-- A detection that didn't lead to a kick or ban. Repeats are folded together
-- so a spamming cheat can't flood the log channel.
function W.report(src, kind, detail, count, needed, wouldHave)
    local p = W.player(src)
    local key, t = kind, W.now()
    local last = p.logged[key]
    if last and t - last.at < 10 then
        last.skipped = last.skipped + 1
        return
    end

    local skipped = last and last.skipped or 0
    p.logged[key] = { at = t, skipped = 0 }

    local label = W.labels[kind] or kind
    local lines = { W.describe(src) }
    if detail then lines[#lines + 1] = detail end
    if needed > 1 then lines[#lines + 1] = ('Strike %d of %d'):format(count, needed) end
    if skipped > 0 then lines[#lines + 1] = ('%d more since the last log'):format(skipped) end
    if wouldHave then lines[#lines + 1] = ('Test mode: would have been a **%s**'):format(wouldHave) end

    W.log(label, table.concat(lines, '\n'), colors.log)
    notifyStaff(('%s (%d): %s'):format(GetPlayerName(src) or src, src, label))
end

W.colors = colors
W.notifyStaff = notifyStaff
