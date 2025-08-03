fx_version 'cerulean'
game 'gta5'
lua54 'yes'

author 'SimpleDevelopments'
description 'Advanced car lock script for fivem!'
version '1.0'

shared_script 'config.lua'

ui_page 'nui/index.html'

files {
    'nui/index.html',
    'nui/css/style.css',
    'nui/js/script.js',
    'nui/sounds/lock.ogg',
    'nui/sounds/unlock.ogg'
}

client_script 'client/client.lua'
server_script 'server/server.lua'