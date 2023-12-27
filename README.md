# qbx_garages


**ATTENTION: THIS SCRIPT USES THE LATEST VERSION OF THE [RADIALMENU](https://github.com/Qbox-project/qbx_radialmenu) AND [QBX-CORE](https://github.com/Qbox-project/qbx_core)**

This is a qb-garages script that uses the radialmenu to retrieve and park vehicles.
Almost everything is fully customizable to the last bit!

**For screenshots scroll down**

## Dependencies
 - [qbx_radialmenu](https://github.com/Qbox-project/qbx_radialmenu)
 - [qbx_core](https://github.com/Qbox-project/qbx_core)

## Installation

Drag 'n Drop replace for qbx_garages.

- Delete qbx_garages.
- Drag the downloaded qbx_garages folder into the [qbx] folder.
- If you want to use the latest features, apply patch1.sql to your DB

## IMPORTANT CHANGE!!!

- Remove `@qbx_garages/config.lua` and add the respective `local Garages = require '@qbx_garages.config.shared'.Garages` and `local HouseGarages = require '@qbx_garages.config.shared'.HouseGarages` to whichever client or server script you are needing.

**OR**

- Change `@qbx_garages/config.lua` to `@qbx_garages/compat/shared.lua` in the fxmanifest.lua

## Features

* Public Garages
* House Garages
* Gang Garages
* Job Garages
* Depot Garages
* Blips and names
* Custom DrawText
* Water Garages
* Aircraft Garages
* Added Fake Plate Check

## Screenshots

( Note: Add New Images )

## Config Example

```
Everything that says optional can be omitted.
 -- GARAGE CONFIGURATION EXAMPLE :
    ['somegarage'] = {
        ['Zone'] = {
            ['Shape'] = { -- Create a polyzone by using '/pzcreate poly', '/pzadd' and '/pzfinish' or '/pzcancel' to cancel it. the newly created polyzone will be in txData/QBCoreFramework_******.base/polyzone_created_zones.txt
            vector2(-1030.4713134766, -3016.3388671875),
            vector2(-970.09686279296, -2914.7397460938),
            vector2(-948.322265625, -2927.9030761718),
            vector2(-950.47174072266, -2941.6584472656),
            vector2(-949.04180908204, -2953.9467773438),
            vector2(-940.78369140625, -2957.2941894532),
            vector2(-943.88732910156, -2964.5512695312),
            vector2(-897.61529541016, -2990.0505371094),
            vector2(-930.01025390625, -3046.0695800782),
            vector2(-942.36407470704, -3044.7858886718),
            vector2(-952.97467041016, -3056.5122070312),
            vector2(-957.11712646484, -3057.0900878906)
            },
            ['minZ'] = 12.5,  -- min height of the parking zone, cannot be the same as maxZ, and must be smaller than maxZ
            ['maxZ'] = 20.0,  -- max height of the parking zone
            -- VERY IMPORTANT: Make sure the parking zone is high enough - higher than the tallest vehicle and LOW ENOUGH / touches the ground (turn on debug to see)
        },
        label = 'Hangar', -- label displayed on phone
        type = 'public', -- 'public', 'job', 'depot' or 'gang'
        showBlip = true, -- optional, when not defined, defaults to false
        blipName = 'Police', -- otional
        blipNumber = 90, -- optional, numbers can be found here: https://docs.fivem.net/docs/game-references/blips/
        blipColor = 69, -- optional, defaults to 3 (Blue), numbers can be found here: https://docs.fivem.net/docs/game-references/blips/
        blipcoords = vector3(-972.66, -3005.4, 13.32), -- blip coordinates
        job = 'police', -- optional, everyone can use it when not defined
        vehicleCategories = {'helicopter', 'plane'}, -- categories defined in VehicleCategories
        drawText = 'Hangar', -- the drawtext text, shown when entering the polyzone of that garage
        ParkingDistance = 10.0 -- Optional ParkingDistance, to override the global ParkingDistance
        SpawnDistance = 5.0 -- Optional SpawnDistance, to override the global SpawnDistance
        debug = false -- Optional, will show the polyzone and the parking spots, helpful when creating new garages. If too many garages are set to debug, it will not show all parking lots
        ExitWarpLocations: { -- Optional, Used for e.g. Boat parking, to teleport the player out of the boat to the closest location defined in the list. 
            vector3(-807.15, -1496.86, 1.6),
            vector3(-800.17, -1494.87, 1.6),
            vector3(-792.92, -1492.18, 1.6),
            vector3(-787.58, -1508.59, 1.6),
            vector3(-794.89, -1511.16, 1.6),
            vector3(-800.21, -1513.05, 1.6),
        } 
    },
```

### parking vehicle using target
```
local garageName = 'pdgarage'
    exports.ox_target:addBoxZone({
        name = garageName
        coords = vector3(469.51, -992.35, 26.27),
        size = vec3(0.2, 0.2, 1.5),
        rotation = 0,
        debug = true,
        options = {
            {
                icon = 'parking',
                label = 'Park Vehicle',
                onSelect = function()
                    TriggerEvent('qb-garages:client:ParkLastVehicle', garageName)
                end,
                canInteract = function(_, distance)
                    return distance <= 2.5
                end
            },
        },
    })
```

### New Phone Tracking Using Export
Replace:

```
RegisterNUICallback('track-vehicle', function(data, cb)
    local veh = data.veh
    if findVehFromPlateAndLocate(veh.plate) then
        QBCore.Functions.Notify("Your vehicle has been marked", "success")
    else
        QBCore.Functions.Notify("This vehicle cannot be located", "error")
    end
    cb("ok")
end)
```

With:

```
RegisterNUICallback('track-vehicle', function(data, cb)
    local veh = data.veh
    if veh.state == 'In' then
        exports['qb-garages']:TrackVehicleByPlate(veh.plate)
        TriggerEvent('qb-phone:client:CustomNotification',
            "GARAGE",
            "GPS Marker Set!",
            "fas fa-car",
            "#e84118",
            5000
        )
        cb("ok")
    elseif veh.state == 'Out' then
        exports['qb-garages']:TrackVehicleByPlate(veh.plate)
        TriggerEvent('qb-phone:client:CustomNotification',
            "GARAGE",
            "GPS Marker Set!",
            "fas fa-car",
            "#e84118",
            5000
        )
        cb("ok")
    else
        TriggerEvent('qb-phone:client:CustomNotification',
            "GARAGE",
            "This vehicle cannot be located",
            "fas fa-car",
            "#e84118",
            5000
        )
        cb("ok")
    end
end)
```

## Credits

* [ARSSANTO](https://github.com/ARSSANTO) - For making code style suggestions and helping me improve the performance.
* [JustLazzy](https://github.com/JustLazzy) - I used part of his qb-garages script.
* [bamablood94](https://github.com/bamablood94) - I used part of his qb-garages script.
* [QBCore Devs](https://github.com/qbcore-framework/) - For making an awesome framework and enabling me to do this.
* QBCore Community - Thank you so much for everyone who's been testing this!
* [JDev](https://github.com/JonasDev17) - Maintaining the resource and handing the reigns to me

# Issues, Suggestions & Support
* This resource is still in development. All help with improving the resource is encouraged and appreciated
* Please use the [GitHub](https://github.com/xViperAG) issues system to report issues or make suggestions
* When making suggestions, please keep `[Suggestion]` in the title to make it clear that it is a suggestion, or join the Discord
* Discord: https://discord.gg/3CXrkvQVds