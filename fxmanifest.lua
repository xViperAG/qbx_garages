fx_version 'cerulean'
game 'gta5'

name 'QBX_Garages'
description 'Garage Script for QBox'
version '1.0.0'
author 'JDev / xViperAG'

shared_scripts { '@ox_lib/init.lua', '@qbx_core/modules/utils.lua', 'config.lua', '@qbx_core/shared/locale.lua', 'locales/en.lua', 'locales/*.lua' }
client_scripts { '@qbx_core/modules/playerdata', 'client/main.lua' }
server_scripts { '@oxmysql/lib/MySQL.lua', 'server/main.lua' }

lua54 'yes'
