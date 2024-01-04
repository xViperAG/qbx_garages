fx_version 'cerulean'
game 'gta5'

name 'QBX_Garages'
description 'Garage Script for QBox'
version '1.0.0'
author 'JDev / xViperAG'

shared_scripts { '@ox_lib/init.lua', '@qbx_core/modules/utils.lua', 'compat/config.lua' }
client_scripts { '@qbx_core/modules/playerdata.lua', 'client/main.lua' }
server_scripts { '@oxmysql/lib/MySQL.lua', 'server/main.lua' }
files { 'config/*.lua', 'locales/*.json' }

lua54 'yes'
