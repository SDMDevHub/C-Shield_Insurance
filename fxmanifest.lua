fx_version 'cerulean'
game {'gta5'}

decription 'CShield Is Script for insurance of the car'
author 'SDMDevHub'

client_scripts {
    'client.lua'
}
ui_page 'html/index.html'

files {
    'version',
    'html/index.html'
}

server_scripts {
    '@oxmysql/lib/MySQL.lua',
    'server.lua'
}
dependencies {
    'es_extended',
    'oxmysql'
}