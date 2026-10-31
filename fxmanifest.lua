fx_version 'cerulean'
game 'gta5'
lua54 'yes'

name 'warden'
description 'Server-side anticheat: game event checks, entity and explosion limits, honeypots, heartbeat and client checks'
version '1.0.2'
author 'IamZach'
discord 'https://discord.gg/agn'
repository 'https://github.com/1amZach/warden'

server_scripts {
    'config.lua',
    'server/core.lua',
    'server/logs.lua',
    'server/bans.lua',
    'server/punish.lua',
    'server/events.lua',
    'server/watch.lua',
    'server/client.lua',
    'server/commands.lua',
}

client_script 'client/main.lua'
