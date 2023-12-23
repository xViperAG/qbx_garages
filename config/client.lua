--[[ 
    Job Vehicles Configuration
    Every job-specific garage is identified by a unique jobGarageIdentifier.
    
    For each garage:
    - `label` provides a descriptive name for the garage.
    - `vehicles` is a grade-based list of vehicles available for that grade.
    For each vehicle:
    - `model` is the internal name of the vehicle.
    - `label` is the display name for the vehicle.
    - `configName` (optional) is a unique configuration identifier.
    - `job` (optional) restricts the vehicle to a specific job if multiple have access to this garage. If omitted, it's available for all jobs that have access to this sepecific garage.
    - with multi job restriction:  {"police", "swat"} --> If, for instance, 'ambulance' had access to this garage too, they wouldn't see this vehicle, only police and swat (in this example). 
    ---- NOTE: If you want the same vehicle with different liveries, create two entries with distinct configurations.    

    -- set useVehicleSpawner = true for each garage that has type job and should use the vehicle spawner instead of personal vehicles
]]

return {
    SpawnWithEngineRunning = true,
    AllowParkingFromOutsideVehicle = true, -- Allow parking from outside the vehicle, if false, you have to be inside the vehicle to park it
    VehicleParkDistance = 2.0, -- Distance from the player to the vehicle to park it, radial option will dissapear beyond this distance

    -- Only relevant if AllowSpawningFromAnywhere = false
    SpawnAtFreeParkingSpot = true, -- Will spawn at the closest free parking spot if you walk up to a occupied parking spot (basically you have to walk up close to a parking lot but it does not matter if there is a vehicle blocking the spawn as it will spawn at the closest free parking spot)
    SpawnAtLastParkinglot = false, -- spawn the vehicle at the last parked location if StoreParkinglotAccuratly = true, if set to true, make sure to apply / run patch1.sql
    AllowSpawningFromAnywhere = true, -- if set to true, the car can be spawned from anywhere inside the zone on the closest parking lot, if set to false you will have to walk up to a parking lot 

    GarageNameAsBlipName = true, -- if set to true, the blips name will match the garage name

    -- Change the below to the following options: Renewed-Fuel / cdn-fuel / LegacyFuel / ps-fuel / lj-fuel or leave blank for ox_fuel
    FuelScript = 'Renewed-Fuel',

    WarpPlayerIntoVehicle = false, -- True == Will Warp Player Into their vehicle after pulling it out of garage. False It will spawn on the parking lot / in front of them  (Global, can be overriden by each garage)

    HouseParkingDrawText = 'Parking', -- text when driving on to the HOUSE parking lot
    DrawTextPosition = 'left-center', -- location of drawtext: left, top, right

    ParkingDistance = 2.0, -- Distance to the parking lot when trying to park the vehicle  (Global, can be overriden by each garage)
    SpawnDistance = 4.5, -- The maximum distance you can be from a parking spot, to spawn a car (Global, can be overriden by each garage)

    DepotPrice = 60.0, -- The price to take out a despawned vehicle from impound.

    JobVehicles = {
        ['pd1'] = { -- jobGarageIdentifier
            label = "Police Vehicles",
            job = 'police',
            -- Grade 0

            -- !! IMPORTANT !! - READ THIS
            -- you can either define the configName, model and label like this and use the vehicle settings below to define extras and liveries for your vehicles
            -- this way you can define a single config and can reuse it for any vehicle you want or you can just use the old way without configuring extras and liveries

            vehicles = {
                [0] = {},
                [1] = {
                    -- [1] = { label = "Some Vehicle", model = "yourmodel", job = {"police", "ambulance"} }, -- example
                    -- [2] = { label = "Another Vehicle", model = "anothermodel", configName = "myUniqueNameForThisCarConfiguration3", job = {"police", "swat"} },
                },
            }
        },
        ['pdhelicopter'] = {
            label = 'Police Helicopters',
            job = 'police',
            vehicles = {
                [0] = { ["as350"] = "Police AS350" },
                [1] = { ["as350"] = "Police AS350" },
                [2] = { ["as350"] = "Police AS350" },
                [3] = { ["as350"] = "Police AS350" },
                [4] = { ["as350"] = "Police AS350" },
                [5] = { ["as350"] = "Police AS350" },
                [6] = { ["as350"] = "Police AS350" },
                [7] = { ["as350"] = "Police AS350" },
            }
        }
    },

    VehicleSettings = {
        ['myUniqueNameForThisCarConfiguration'] = { -- configName
            -- ['model'] = 'police2', -- You can either define the model and grades here, or use the configName in the jobVehicles config
            -- ['jobGrades'] = {0},
            ["livery"] = 1,
            ["extras"] = {
                ["1"] = true, -- on/off
                ["2"] = true,
                ["3"] = true,
                ["4"] = true,
                ["5"] = true,
                ["6"] = true,
                ["7"] = true,
                ["8"] = true,
                ["9"] = true,
                ["10"] = true,
                ["11"] = true,
                ["12"] = true,
                ["13"] = true,
            },
        },
    },

    -- THESE VEHICLE CATEGORIES ARE NOT RELATED TO THE ONES IN shared/vehicles.lua
    -- Here you can define which category contains which vehicle class. These categories can then be used in the garage config
    -- All vehicle classes can be found here: https://docs.fivem.net/natives/?_0x29439776AAA00A62
    VehicleCategories = {
        ['car'] = { 0, 1, 2, 3, 4, 5, 6, 7, 9, 10, 11, 12 },
        ['motorcycle'] = { 8 },
        ['other'] = { 13 }, -- cycles: 13 - you can move cycles to cars if you want and have anything else like military vehicles in this category
        ['boat'] = { 14 },
        ['helicopter'] = { 15 },
        ['plane'] = { 16 },
        ['service'] = { 17 },
        ['emergency'] = { 18 },
        ['military'] = { 19 },
        ['commercial'] = { 20 },
        -- you can also create new / delete or update categories, and use them below in the config.
    },

    HouseGarageCategories = {'car', 'motorcycle', 'other'}, -- Which categories are allowed to be parked at a house garage

    VehicleHeading = 'driverside' -- only used when NO parking spots are defined in the garage config
    --[[^^^^^^^^
        'forward' = will face the sameway as the ped
        'driverside' = will put the driver door closets to the ped
        'hood' = will face the hood towards ped
        'passengerside' = will put the passenger door closets to the ped
    ]]
}