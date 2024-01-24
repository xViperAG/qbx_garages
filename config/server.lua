return {
    BrazzersFakeplate = false,
    RenewedKeys = false, -- EXPERIMENTAL --
    StoreParkinglotAccuratly = true,  -- store the last parking lot in the DB, if set to true, make sure to apply / run patch1.sql, I recommend applying the tracking snippet for qb-phone from the ReadMe to the phone so you can track the vehicle to the exact parking lot

    addVehicleItems = false,

    TrunkItems = {
        police = {
            { name = 'stormram', amount = 1 },
            { name = 'heavyarmor', amount = 3 },
            { name = 'ammo-pistol', amount = 50 },
        },
        ambulance = {
            { name = 'WEAPON_FIREEXTINGUISHER', amount = 1 },
            { name = 'bandages', amount = 5 }
        }
    },

    SharedHouseGarage = true,

    --Config.SharedGangGarages = false -- Allow shared gang garages, if false, the player can only access their own vehicles
    -- for specific gangs, use this:
    SharedGangGarages = {
        vagos = true, -- Allow shared gang garages, if false, the player can only access their own vehicles
        gsf = true, -- Allow shared gang garages, if false, the player can only access their own vehicles
    },

    AllowParkingAnyonesVehicle = false, -- Allow anyones vehicle to be stored in the garage, if false, only vehicles you own can be stored in the garage (supports only public garages)
    GlobalParking = false, -- if true, you can access your cars from any garage, if false, you can only access your cars from the garage you stored them in
    AutoRespawn = true, --True == auto respawn cars that are outside into your garage on script restart, false == does not put them into your garage and players have to go to the impound

    TrackVehicleByPlateCommand = 'trackvehicle',
    EnableTrackVehicleByPlateCommand = true,
    TrackVehicleByPlateCommandPermissionLevel = 'group.admin',

    -- '/restorelostcars <destination_garage>' allows you to restore cars that have been parked in garages which no longer exist in the config (garage renamed or removed). The restored cars get sent to the destination garage or if left empty to a random garage in the list.
    -- NOTE: This may also send helis and boats to said garaga so choose wisely
    RestoreCommandPermissionLevel = 'group.admin', -- sets the permission level for the above mentioned command

    SharedJobGarages = { -- define the job garages which are shared
        'pdgarage',
    }
}