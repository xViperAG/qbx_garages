fx_version 'cerulean'
game 'gta5'

name 'QBX Garage Script'
description 'Garage Script for QBox'
version '1.0.0'
author 'JDev'

modules { 'qbx_core:utils', 'qbx_core:playerdata' }

shared_scripts { '@ox_lib/init.lua', '@qbx_core/import.lua', 'config.lua', '@qbx_core/shared/locale.lua', 'locales/en.lua', 'locales/*.lua' }
client_scripts { 'client/main.lua' }
server_scripts { '@oxmysql/lib/MySQL.lua', 'server/main.lua' }

lua54 'yes'
