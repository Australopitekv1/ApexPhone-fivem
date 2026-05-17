fx_version 'cerulean'
game 'gta5'

name 'ApexPhone'
description 'Advanced FiveM Phone System — QBCore/ESX compatible'
version '3.0.0'
author 'ApexDev'
url 'https://github.com/apex/apexphone'

lua54 'yes'

shared_scripts {
    '@qb-core/shared/locale.lua',
    'config.lua',
}

client_scripts {
    'client.lua',
}

server_scripts {
    '@oxmysql/lib/MySQL.lua',
    'server.lua',
}

ui_page 'html/index.html'

files {
    'html/index.html',
    'html/style.css',
    'html/app.js',
    'html/assets/icons/*.png',
    'html/assets/icons/*.svg',
    'html/assets/sounds/*.ogg',
    'html/assets/sounds/*.mp3',
    'html/assets/fonts/*.ttf',
    'html/assets/fonts/*.woff2',
}

dependencies {
    'qb-core',
    'oxmysql',
}

-- Optional integrations — gracefully degraded if absent
-- 'pma-voice'
-- 'qb-inventory'
-- 'ps-inventory'
-- 'ox_inventory'
