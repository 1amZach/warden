-- lua5.4 test/run.lua
-- Runs the server side of warden against a fake FiveM server.

local passed, failed = 0, 0
local function check(name, cond)
    if cond then passed = passed + 1 else failed = failed + 1; print('FAIL ' .. name) end
end

-- Clock, events, timers ------------------------------------------------------

local clock = 0
function GetGameTimer() return clock end
local function advance(seconds) clock = clock + seconds * 1000 end

local handlers, cancelled = {}, false
function AddEventHandler(name, fn) handlers[name] = handlers[name] or {}; table.insert(handlers[name], fn) end
function RegisterNetEvent(name, fn) if fn then AddEventHandler(name, fn) end end
function CancelEvent() cancelled = true end
local triggered = {}
function TriggerEvent(name, ...) triggered[#triggered + 1] = { name = name, args = { ... } } end

local function fire(name, src, ...)
    cancelled = false
    source = src
    for _, fn in ipairs(handlers[name] or {}) do fn(...) end
    return cancelled
end

local timers = {}
function SetTimeout(_, fn) timers[#timers + 1] = fn end
local function runTimers() local t = timers; timers = {}; for _, fn in ipairs(t) do fn() end end
function CreateThread() end
function Wait() end

local client = {}
function TriggerClientEvent(name, target, ...) client[#client + 1] = { name = name, target = target, args = { ... } } end
local function lastClient(name)
    for i = #client, 1, -1 do if client[i].name == name then return client[i] end end
end

-- json stand-in: remembers the table behind each string it hands out.
local stored, n = {}, 0
json = {
    encode = function(t) n = n + 1; local k = 'json#' .. n; stored[k] = t; return k end,
    decode = function(s) return assert(stored[s], 'bad json') end,
}

-- Hashes ----------------------------------------------------------------------

function GetHashKey(s)
    local h = 0
    for c in s:lower():gmatch('.') do
        h = (h + c:byte()) & 0xFFFFFFFF
        h = (h + (h << 10)) & 0xFFFFFFFF
        h = h ~ (h >> 6)
    end
    h = (h + (h << 3)) & 0xFFFFFFFF
    h = h ~ (h >> 11)
    h = (h + (h << 15)) & 0xFFFFFFFF
    return h >= 0x80000000 and h - 0x100000000 or h -- signed, like the real native
end

local vec = {}
vec.__index = vec
vec.__sub = function(a, b) return setmetatable({ x = a.x - b.x, y = a.y - b.y, z = a.z - b.z }, vec) end
vec.__len = function(v) return math.sqrt(v.x ^ 2 + v.y ^ 2 + v.z ^ 2) end
local function v3(x, y, z) return setmetatable({ x = x, y = y, z = z }, vec) end

-- Players and entities --------------------------------------------------------

local players, entities, files, dropped, http = {}, {}, {}, {}, {}
local started = { warden = 'started' }

local function addPlayer(src, name, opts)
    opts = opts or {}
    players[src] = {
        name = name,
        ids = opts.ids or { 'license:' .. name:lower(), 'discord:1' .. src, 'ip:1.2.3.4' },
        tokens = opts.tokens or { 'token:' .. name:lower() },
        pos = v3(0, 0, 0), health = 200, max = 200, armour = 0, weapon = GetHashKey('WEAPON_UNARMED'),
        vehicle = 0, attached = 0, invincible = false, aces = opts.aces or {},
    }
    fire('playerJoining', src)
end

local function ped(src) return src + 1000 end
local function srcOf(p) return players[p - 1000] and p - 1000 end

function GetPlayerName(src) local p = players[tonumber(src)]; return p and p.name end
function GetPlayers() local out = {}; for src in pairs(players) do out[#out + 1] = tostring(src) end; return out end
function GetNumPlayerIdentifiers(src) return #players[tonumber(src)].ids end
function GetPlayerIdentifier(src, i) return players[tonumber(src)].ids[i + 1] end
function GetNumPlayerTokens(src) return #players[tonumber(src)].tokens end
function GetPlayerToken(src, i) return players[tonumber(src)].tokens[i + 1] end
function IsPlayerAceAllowed(src, ace) local p = players[tonumber(src)]; return p and p.aces[ace] or false end
function DropPlayer(src, reason) dropped[#dropped + 1] = { src = tonumber(src), reason = reason }; players[tonumber(src)] = nil end
function GetPlayerPed(src) return players[tonumber(src)] and ped(tonumber(src)) or 0 end
function GetPlayerInvincible(src) return players[tonumber(src)].invincible end

local function P(e) return players[srcOf(e) or -1] end
function GetEntityCoords(e) return (P(e) or entities[e]).pos end
function GetEntityHealth(e) return P(e).health end
function GetEntityMaxHealth(e) return P(e).max end
function GetPedArmour(e) return P(e).armour end
function GetSelectedPedWeapon(e) return P(e).weapon end
function RemoveWeaponFromPed(e) P(e).weapon = GetHashKey('WEAPON_UNARMED') end
function GetVehiclePedIsIn(e) return P(e).vehicle end
function GetEntityAttachedTo(e) return P(e).attached end
function IsPedAPlayer(e) return P(e) ~= nil end
function NetworkGetEntityFromNetworkId(id) return id end
function NetworkGetEntityOwner(e) return srcOf(e) or (entities[e] and entities[e].owner) end
function GetEntityPopulationType(e) return entities[e] and entities[e].pop or 0 end
function GetEntityModel(e) return entities[e].model end
function GetEntityType(e) return P(e) and 1 or entities[e].type end

function GetResourceState(name) return started[name] or 'missing' end
function GetCurrentResourceName() return 'warden' end
function GetConvar(name, fallback) return name == 'warden_webhook' and 'https://discord.test/hook' or fallback end
function LoadResourceFile(_, path) return files[path] end
function SaveResourceFile(_, path, data) files[path] = data end
function PerformHttpRequest(url, _, method, body, headers) http[#http + 1] = { url = url, body = body, headers = headers } end
function RegisterCommand(name, fn) _G['cmd_' .. name] = fn end
local logged = {}
function print(...) logged[#logged + 1] = table.concat({ ... }, ' ') end
local realPrint = _G.io.write

local registered, fivecord, screenshotData, capture = {}, {}, nil, {}
exports = setmetatable({}, {
    __call = function(_, name, fn) registered[name] = fn end,
    __index = function(_, res)
        if res == 'fivecord' then
            return {
                ban = function(_, src, reason, seconds, by) fivecord[#fivecord + 1] = { kind = 'ban', src = src, reason = reason, by = by }; return true end,
                log = function(_, kind, title, desc, color, image, clip) fivecord[#fivecord + 1] = { kind = 'log', title = title, desc = desc, image = image, clip = clip } end,
            }
        end
        if res == 'fivelog' then
            return { recent = function(_, src, n) return { { at = 1700000000, text = 'Al hit Bob_ 2 times' }, { at = 1700000005, text = 'Al killed Bob' } } end }
        end
        if res == 'fivecapture' then
            return {
                screenshot = function(_, src, opts, cb) capture[#capture + 1] = { 'screenshot', src }; cb(false, { data = 'data:image/jpeg;base64,/9j/CAP' }) end,
                record = function(_, src, seconds, opts, cb) capture[#capture + 1] = { 'record', src, seconds, opts.save }; cb(false, { file = '/srv/captures/clip.webm' }) end,
                upload = function(_, file, opts) capture[#capture + 1] = { 'upload', file, opts.webhook, opts.message } end,
            }
        end
        if res == 'screenshot-basic' then
            return { requestClientScreenshot = function(_, src, opts, cb) cb(false, screenshotData) end }
        end
    end,
})

-- Load ------------------------------------------------------------------------

for _, f in ipairs({ 'config.lua', 'server/core.lua', 'server/logs.lua', 'server/bans.lua', 'server/punish.lua',
    'server/events.lua', 'server/watch.lua', 'server/client.lua', 'server/commands.lua' }) do
    dofile(f)
end
local W = Warden
local function strikes(src, kind) return #(W.players[src] and W.players[src].strikes[kind] or {}) end
local function lastLog() return http[#http] and json.decode(http[#http].body) end
Config.screenshots = false

-- Tests -----------------------------------------------------------------------

do -- honeypot bans locally, kicks with the ban screen and saves
    addPlayer(1, 'Cheater')
    fire('esx:giveMoneyToPlayer', 1)
    check('honeypot drops player', dropped[#dropped].src == 1)
    check('ban screen shows id and appeal', dropped[#dropped].reason:find('Ban #1') and dropped[#dropped].reason:find('yourserver'))
    local p = triggered[#triggered]
    check('punished event carries name and license', p.name == 'warden:punished' and p.args[5] == 'Cheater' and p.args[6] == 'license:cheater')
    check('ban saved to bans.json', json.decode(files['bans.json']).bans[1].name == 'Cheater')
    check('ip not stored with the ban', not table.concat(W.bans.list[1].identifiers, ' '):find('ip:'))
    check('ban logged to webhook', lastLog().embeds[1].title:find('Ban #1'))
    check('detected event fired', triggered[#triggered - 1].name == 'warden:detected' and triggered[#triggered - 1].args[4] == 'ban')
end

do -- new account on the same PC is refused and remembered
    players[50] = { name = 'Fresh', ids = { 'license:fresh' }, tokens = { 'token:cheater' }, aces = {} }
    local reason
    local refused = fire('playerConnecting', 50, 'Fresh', function(r) reason = r end)
    check('evader refused', refused and reason:find('Ban #1'))
    check('new license added to the ban', table.concat(W.bans.list[1].identifiers, ' '):find('license:fresh'))
    check('evasion logged', lastLog().embeds[1].title == 'Ban evasion')

    players[51] = { name = 'Fresh2', ids = { 'license:fresh' }, tokens = { 'token:newpc' }, aces = {} }
    check('banned license on another pc refused', fire('playerConnecting', 51, 'Fresh2', function() end))

    players[52] = { name = 'Clean', ids = { 'license:clean' }, tokens = { 'token:clean' }, aces = {} }
    check('clean player let in', not fire('playerConnecting', 52, 'Clean', function() end))
    players[50], players[51], players[52] = nil, nil, nil
end

do -- blocked explosion: cancelled, logged once, then banned
    addPlayer(2, 'Boomer')
    check('blocked explosion cancelled', fire('explosionEvent', nil, 2, { explosionType = 36 }))
    check('first strike only logged', players[2] ~= nil and lastLog().embeds[1].description:find('Strike 1 of 2'))
    fire('explosionEvent', nil, 2, { explosionType = 36 })
    check('second strike bans', players[2] == nil)
end

do -- explosion spam and invisible explosions
    addPlayer(3, 'Spammy')
    local results = {}
    for i = 1, 7 do results[i] = fire('explosionEvent', nil, 3, { explosionType = 7 }) end
    check('six explosions allowed', not results[6])
    check('seventh cancelled', results[7] and strikes(3, 'explosionSpam') == 1)
    advance(11)
    check('limit resets after the window', not fire('explosionEvent', nil, 3, { explosionType = 7 }))
    check('invisible explosion cancelled', fire('explosionEvent', nil, 3, { explosionType = 2, isInvisible = true }))
end

do -- entities
    addPlayer(4, 'Spawner')
    entities[900] = { owner = 4, pop = 7, model = GetHashKey('hydra'), type = 2, pos = v3(0, 0, 0) }
    check('blocked model cancelled', fire('entityCreating', nil, 900))
    check('blocked model named in log', lastLog().embeds[1].description:find('hydra'))

    entities[901] = { owner = 4, pop = 7, model = GetHashKey('prop_bench_01a'), type = 3 }
    local hit
    for _ = 1, 61 do hit = fire('entityCreating', nil, 901) end
    check('object spam cancelled past the limit', hit and strikes(4, 'entitySpam') == 1)

    entities[902] = { owner = 4, pop = 2, model = GetHashKey('hydra'), type = 2 }
    check('ambient traffic ignored', not fire('entityCreating', nil, 902))

    for _ = 1, 15 do fire('entityCreating', nil, ped(4)) end
    check('player peds never count', strikes(4, 'entitySpam') == 1)
end

do -- weapon and task events aimed at other players
    addPlayer(5, 'Giver')
    addPlayer(6, 'Victim')
    check('giving yourself a weapon is fine', not fire('giveWeaponEvent', nil, 5, { pedId = ped(5) }))
    check('giving another player a weapon is cancelled', fire('giveWeaponEvent', nil, 5, { pedId = ped(6) }))
    check('target named', lastLog().embeds[1].description:find('Victim'))
    check('clearing an npc is fine', not fire('clearPedTasksEvent', nil, 5, { pedId = 777 }))
    check('clearing another player is cancelled', fire('clearPedTasksEvent', nil, 5, { pedId = ped(6), immediately = true }))
    check('remove all weapons cancelled', fire('removeAllWeaponsEvent', nil, 5, { pedId = ped(6) }))
end

do -- melee range
    addPlayer(7, 'Puncher')
    addPlayer(8, 'Far')
    players[8].pos = v3(30, 0, 0)
    check('melee from 30m cancelled', fire('weaponDamageEvent', nil, 7, { weaponType = W.u32(GetHashKey('WEAPON_UNARMED')), hitGlobalId = ped(8) }))
    players[8].pos = v3(1, 0, 0)
    check('melee up close fine', not fire('weaponDamageEvent', nil, 7, { weaponType = W.u32(GetHashKey('WEAPON_BAT')), hitGlobalId = ped(8) }))
    players[8].pos = v3(80, 0, 0)
    check('guns from range fine', not fire('weaponDamageEvent', nil, 7, { weaponType = W.u32(GetHashKey('WEAPON_PISTOL')), hitGlobalId = ped(8) }))
    check('blocked weapon damage cancelled', fire('weaponDamageEvent', nil, 7, { weaponType = W.u32(GetHashKey('WEAPON_RAILGUN')), hitGlobalId = ped(8) }))
end

do -- server-side scan
    addPlayer(9, 'Runner')
    W.watch()
    players[9].weapon = GetHashKey('WEAPON_MINIGUN')
    W.watch()
    check('blocked weapon taken away', players[9].weapon == GetHashKey('WEAPON_UNARMED'))
    check('blocked weapon strike', strikes(9, 'blockedWeapon') == 1)

    players[9].health = 400
    W.watch()
    check('health above max', strikes(9, 'health') == 1)
    players[9].health = 200

    players[9].pos = v3(5000, 0, 0)
    advance(1); W.watch()
    check('no movement checks during join grace', strikes(9, 'teleport') == 0)

    advance(30); W.watch()
    players[9].pos = v3(0, 0, 0)
    advance(1); W.watch()
    check('teleport logged', strikes(9, 'teleport') == 1 and players[9] ~= nil)

    for i = 1, 3 do players[9].pos = v3(i * 30, 0, 0); advance(1); W.watch() end
    check('fast on foot for 3s', strikes(9, 'speed') == 1)

    players[9].vehicle = 55
    for i = 4, 7 do players[9].pos = v3(i * 30, 0, 0); advance(1); W.watch() end
    check('fast in a car is fine', strikes(9, 'speed') == 1)
    players[9].vehicle = 0

    W.allow(9, 'teleport', 5)
    players[9].pos = v3(9000, 0, 0); advance(1); W.watch()
    check('allow() skips teleport checks', strikes(9, 'teleport') == 1)

    players[9].invincible = true
    for _ = 1, 31 do advance(1); W.watch() end
    check('invincible for 30s logged', strikes(9, 'invincible') == 1)
end

do -- heartbeat
    addPlayer(10, 'Quiet')
    fire('warden:ready', 10)
    local setup = lastClient('warden:setup')
    check('client gets settings on ready', setup.target == 10 and setup.args[1].godmodeSeconds == 20)
    check('disabled checks are off on the client', setup.args[2].vision == false and setup.args[2].godmode == true)

    W.heartbeat()
    local nonce = lastClient('warden:ping').args[1]
    fire('warden:pong', 10, nonce)
    check('right answer clears it', W.players[10].nonce == nil)

    W.heartbeat(); W.heartbeat(); W.heartbeat(); W.heartbeat()
    check('three missed checks kick', dropped[#dropped].src == 10 and dropped[#dropped].reason == Config.kickMessage)

    addPlayer(11, 'Never')
    advance(Config.heartbeat.grace + 1)
    W.heartbeat()
    check('client that never starts is kicked', dropped[#dropped].src == 11)

    addPlayer(12, 'Liar')
    fire('warden:ready', 12)
    W.heartbeat()
    fire('warden:pong', 12, 'nope')
    check('wrong answer kicks', dropped[#dropped].src == 12)
end

do -- client reports
    addPlayer(13, 'Injector')
    started.ox_lib = 'started'
    fire('warden:resources', 13, { 'ox_lib', 'warden' })
    check('known resources fine', players[13] ~= nil)
    fire('warden:resources', 13, { 'ox_lib', 'redengine' })
    check('unknown resource bans', players[13] == nil and W.bans.list[#W.bans.list].detail:find('redengine'))

    addPlayer(14, 'Flagger')
    fire('warden:flag', 14, 'honeypot', 'faked')
    check('client cannot send server-only detections', strikes(14, 'honeypot') == 0)
    fire('warden:flag', 14, 'freecam', 'Camera 400m away')
    check('client detections count', strikes(14, 'freecam') == 1)
    for _ = 1, 30 do fire('warden:flag', 14, 'freecam') end
    check('client flags are capped', strikes(14, 'freecam') <= 20)
end

do -- staff bypass
    addPlayer(15, 'Admin', { aces = { ['warden.bypass'] = true } })
    check('staff explosions not cancelled', not fire('explosionEvent', nil, 15, { explosionType = 36 }))
    fire('esx:giveMoneyToPlayer', 15)
    check('staff never punished', players[15] ~= nil)
end

do -- test mode logs what would have happened
    Config.testMode = true
    addPlayer(16, 'Tester')
    fire('qb-core:server:addMoney', 16)
    check('test mode does not ban', players[16] ~= nil)
    check('test mode says what it would do', lastLog().embeds[1].description:find('would have been a %*%*ban'))
    Config.testMode = false
end

do -- log throttling
    addPlayer(17, 'Noisy')
    local before = #http
    for _ = 1, 5 do fire('warden:flag', 17, 'freecam') end
    check('repeats within 10s folded', #http == before + 1)
    advance(11)
    fire('warden:flag', 17, 'freecam')
    check('folded count shown later', lastLog().embeds[1].description:find('4 more since the last log'))
end

do -- through fivecord, with a screenshot
    started.fivecord = 'started'
    started['screenshot-basic'] = 'started'
    Config.screenshots = true
    screenshotData = 'data:image/jpeg;base64,/9j/4AAQ'
    addPlayer(18, 'Linked')
    fire('admin:server:setGroup', 18)
    local b, l = fivecord[#fivecord - 1], fivecord[#fivecord]
    check('ban goes through fivecord', b.kind == 'ban' and b.src == 18 and b.by == 'warden' and b.reason:find('fake event'))
    check('log goes through fivecord with the screenshot', l.kind == 'log' and l.image == screenshotData)
    check('fivecord drops them, not warden', players[18] ~= nil)
    runTimers()
    check('fallback drop if fivecord did not', players[18] == nil)
    started.fivecord = nil

    addPlayer(19, 'Webhook')
    fire('admin:server:setGroup', 19)
    local req = http[#http]
    check('screenshot sent as multipart', req.headers['Content-Type']:find('multipart') and req.body:find('screenshot.jpg', 1, true))
    check('jpeg bytes decoded', req.body:find('\255\216\255\224', 1, true))
    Config.screenshots = false
end

do -- fivecapture: screenshot and clip
    started.fivecapture = 'started'
    started['screenshot-basic'] = nil
    Config.screenshots, Config.clip = true, 8
    started.fivecord = 'started'
    addPlayer(30, 'Clipped')
    fire('admin:server:setGroup', 30)
    local l = fivecord[#fivecord]
    check('screenshot comes from fivecapture', l.image == 'data:image/jpeg;base64,/9j/CAP')
    check('clip recorded for the configured seconds and saved', capture[2] and capture[2][1] == 'record' and capture[2][2] == 30 and capture[2][3] == 8 and capture[2][4] == true)
    check('fivecord log gets the clip file', l.clip == '/srv/captures/clip.webm')
    local p = triggered[#triggered]
    for i = #triggered, 1, -1 do if triggered[i].name == 'warden:punished' then p = triggered[i] break end end
    check('punished event carries the clip', p.args[8] == '/srv/captures/clip.webm')
    runTimers()
    started.fivecord = nil

    local n = #capture
    addPlayer(31, 'Hooked')
    fire('admin:server:setGroup', 31)
    local up = capture[#capture]
    check('without fivecord the clip goes to the webhook', up[1] == 'upload' and up[2] == '/srv/captures/clip.webm' and up[3] == 'https://discord.test/hook' and up[4]:find('Ban'))
    check('screenshot still in the webhook log', http[#http].body:find('screenshot.jpg', 1, true))

    Config.clip = 0
    n = #capture
    addPlayer(32, 'NoClip')
    fire('admin:server:setGroup', 32)
    check('clip 0 records nothing', capture[n + 1][1] == 'screenshot' and capture[n + 2] == nil)

    started.fivecapture = nil
    Config.screenshots = false
end

do -- base64
    check('base64 padding', W.unbase64('aGVsbG8=') == 'hello' and W.unbase64('aGk=') == 'hi' and W.unbase64('YWJj') == 'abc')
end

do -- commands and exports
    local id = W.bans.list[1].id
    cmd_warden(0, { 'unban', tostring(id) })
    check('unban from console', W.bans.list[1] == nil or W.bans.list[1].id ~= id)
    cmd_warden(0, { 'status' })
    check('status prints', logged[#logged]:find('players watched'))
    check('exports registered', registered.allow and registered.flag and registered.isBanned and registered.getStrikes)
    addPlayer(20, 'Exported')
    registered.flag(20, 'freecam', 'from another resource')
    check('getStrikes', registered.getStrikes(20).freecam == 1)
    check('isBanned', registered.isBanned('license:injector') and not registered.isBanned('license:nobody'))
    local list = registered.getBans()
    check('getBans newest first without tokens', list[1].id > list[#list].id and list[1].tokens == nil)
    check('unban export', registered.unban(list[1].id, 'panel') and not registered.unban(list[1].id))
end

do -- recent fivelog lines on a kick
    started.fivelog = 'started'
    addPlayer(21, 'Logged')
    W.punish(21, 'kick', 'noclip', 'Flying')
    local d = lastLog().embeds[1].description
    check('history in kick log', d:find('Just before', 1, true) and d:find('<t:1700000005:T> Al killed Bob', 1, true))
    check('history escaped', d:find('Bob\\_', 1, true))
    started.fivelog = nil
    Config.history = 0
    addPlayer(22, 'Plain')
    W.punish(22, 'kick', 'noclip', 'Flying')
    check('no history when off', not lastLog().embeds[1].description:find('Just before', 1, true))
end

realPrint(('%d passed, %d failed\n'):format(passed, failed))
os.exit(failed == 0 and 0 or 1)
