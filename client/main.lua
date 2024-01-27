lib.locale()

local PlayerGang, PlayerJob = {}, {}
local CurrentHouseGarage, CurrentGarage = nil, nil
local OutsideVehicles = {}
local GaragePoly, GarageZones = {}, {}
local MenuItemId1, MenuItemId2 = nil, nil
local VehicleClassMap = {}

local config = require 'config.client'
local Garages = require 'config.shared'.Garages
local HouseGarages = require 'config.shared'.HouseGarages
local UpdateRadial = false
local ParkingUpdated = false

-- helper functions
local function TableContains(tab, val)
    if type(val) == "table" then -- checks if atleast one the values in val is contained in tab
        for _, value in ipairs(tab) do
            if TableContains(val, value) then
                return true
            end
        end
        return false
    else
        for _, value in ipairs(tab) do
            if value == val then
                return true
            end
        end
    end
    return false
end

function TrackVehicleByPlate(plate)
    local coords = lib.callback.await('qb-garages:server:GetVehicleLocation', false, plate)
    SetNewWaypoint(coords.x, coords.y)
end

exports("TrackVehicleByPlate", TrackVehicleByPlate)

local function IsStringNilOrEmpty(s)
    return s == nil or s == ''
end

local function GetSuperCategoryFromCategories(categories)
    local superCategory = 'car'
    if TableContains(categories, {'car'}) then
        superCategory = 'car'
    elseif TableContains(categories, {'plane', 'helicopter'}) then
        superCategory = 'air'
    elseif TableContains(categories, 'boat') then
        superCategory = 'sea'
    end
    return superCategory
end

local function GetClosestLocation(locations, loc)
    local closestDistance = -1
    local closestIndex = -1
    local closestLocation = nil
    local plyCoords = loc or GetEntityCoords(cache.ped)
    for i, v in ipairs(locations) do
        local location = vector3(v.x, v.y, v.z)
        local distance = #(plyCoords - location)
        if (closestDistance == -1 or closestDistance > distance) then
            closestDistance = distance
            closestIndex = i
            closestLocation = v
        end
    end
    return closestIndex, closestDistance, closestLocation
end

function SetAsMissionEntity(vehicle)
    SetVehicleHasBeenOwnedByPlayer(vehicle, true)
    SetEntityAsMissionEntity(vehicle, true, true)
    SetVehicleIsStolen(vehicle, false)
    SetVehicleIsWanted(vehicle, false)
    SetVehRadioStation(vehicle, 'OFF')
    local id = NetworkGetNetworkIdFromEntity(vehicle)
    SetNetworkIdCanMigrate(id, true)
end

function GetVehicleByPlate(plate)
    local vehicles = GetGamePool('CVehicle')
    for _, v in pairs(vehicles) do
        if qbx.getVehiclePlate(v) == plate then
            return v
        end
    end
    return nil
end

function RemoveRadialOptions()
    lib.removeRadialItem('park_vehicle')
    lib.removeRadialItem('open_garage')
    lib.removeRadialItem('open_impound')
end

local function ResetCurrentGarage()
    CurrentGarage = nil
end

-- Menus
local function PublicGarage(garageName, type)
    local garage = Garages[garageName]
    local categories = garage.vehicleCategories
    local superCategory = GetSuperCategoryFromCategories(categories)

    local options = {
        {
            title = locale("header_vehicles"),
            description = locale("text_vehicles"),
            event = "qb-garages:client:GarageMenu",
            args = {
                garageId = garageName,
                garage = garage,
                categories = categories,
                header =  locale(garage.type.."_"..superCategory, garage.label),
                superCategory = superCategory,
                type = type
            }
        }
    }

    if PlayerJob.type == 'leo' and GetResourceState('xt-pdextras') == 'started' then
        options[#options + 1] = {
            title = locale('raid_garage'),
            description = locale('raid_description'),
            icon = 'fas fa-magnifying-glass',
            event = 'xt-pdextras:client:raidGarage',
            args = {
                garage = garage,
                garageId = garageName,
                categories = categories,
                superCategory = superCategory,
                type = type,
            }
        }
    end

    lib.registerContext({
        id = 'qbx_publicVehicle_list',
        title = garage.label,
        options = options
    })
    lib.showContext('qbx_publicVehicle_list')
end

local function MenuHouseGarage()
    local superCategory = GetSuperCategoryFromCategories(config.HouseGarageCategories)
    lib.registerContext({
        id = 'qbx_houseVehicle_list',
        title = locale("house_garage"),
        options = {
            {
                title = locale("header_vehicles"),
                description = locale("text_vehicles_desc"),
                event = "qb-garages:client:GarageMenu",
                args = {
                    garageId = CurrentHouseGarage,
                    categories = config.HouseGarageCategories,
                    header =  HouseGarages[CurrentHouseGarage].label,
                    garage = HouseGarages[CurrentHouseGarage],
                    superCategory = superCategory,
                    type = 'house'
                }
            }
        }
    })
    lib.showContext('qbx_houseVehicle_list')
end

local function ClearMenu()
	lib.hideContext()
end

-- Functions

local function ApplyVehicleDamage(currentVehicle, veh)
	local engine = veh.engine + 0.0
	local body = veh.body + 0.0
    local damage = veh.damage
    if damage then
        if damage.tyres then
            for k, tyre in pairs(damage.tyres) do
                if tyre.onRim then
                    SetVehicleTyreBurst(currentVehicle, tonumber(k), tyre.onRim, 1000.0)
                elseif tyre.burst then
                    SetVehicleTyreBurst(currentVehicle, tonumber(k), tyre.onRim, 990.0)
                end
            end
        end

        if damage.windows then
            for k, window in pairs(damage.windows) do
                if window.smashed then
                    SmashVehicleWindow(currentVehicle, tonumber(k))
                end
            end
        end

        if damage.doors then
            for k, door in pairs(damage.doors) do
                if door.damaged then
                    SetVehicleDoorBroken(currentVehicle, tonumber(k), true)
                end
            end
        end
    end

    SetVehicleEngineHealth(currentVehicle, engine)
    SetVehicleBodyHealth(currentVehicle, body)
end

local function GetCarDamage(vehicle)
    local damage = {
        windows = {},
        tyres = {},
        doors = {}
    }

    local tyreIndexes = { 0, 1, 2, 3, 4, 5, 45, 47 }

    for _, i in pairs(tyreIndexes) do
        damage.tyres[i] = {
            burst = IsVehicleTyreBurst(vehicle, i, false) == 1,
            onRim = IsVehicleTyreBurst(vehicle, i, true) == 1,
            health = GetTyreHealth(vehicle, i)
        }
    end

    for i = 0, 7 do
        damage.windows[i] = {
            smashed = not IsVehicleWindowIntact(vehicle, i)
        }
    end

    for i = 0, 5 do
        damage.doors[i] = {
            damaged = IsVehicleDoorDamaged(vehicle, i)
        }
    end

    return damage
end

local function Round(num, numDecimalPlaces)
    return tonumber(string.format("%." .. (numDecimalPlaces or 0) .. "f", num))
end

local function ExitAndDeleteVehicle(vehicle)
    local garage = Garages[CurrentGarage]
    local exitLocation = nil
    if garage and garage.ExitWarpLocations and next(garage.ExitWarpLocations) then
        _, _, exitLocation = GetClosestLocation(garage.ExitWarpLocations)
    end
    for i = -1, 5, 1 do
        local ped = GetPedInVehicleSeat(vehicle, i)
        if ped then
            TaskLeaveVehicle(ped, vehicle, 0)
            if exitLocation then
                SetEntityCoords(ped, exitLocation.x, exitLocation.y, exitLocation.z)
            end
        end
    end
    SetVehicleDoorsLocked(vehicle, 2)
    local plate = GetVehicleNumberPlateText(vehicle)
    Wait(1500)
    DeleteVehicle(vehicle)
    lib.removeRadialItem('park_vehicle')
    Wait(1000)
    TriggerServerEvent('qb-garages:server:parkVehicle', plate)
end

local function GetVehicleCategoriesFromClass(class)
    return VehicleClassMap[class]
end

local function IsAuthorizedToAccessGarage(garageName)
    local garage = Garages[garageName]

    if not garage then return false end

    if garage.type == 'job' then
        if type(garage.job) == "string" and not IsStringNilOrEmpty(garage.job) then
            return PlayerJob.name == garage.job
        elseif type(garage.job) == "table" then
            return TableContains(garage.job, PlayerJob.name)
        else
            exports.qbx_core:Notify('job not defined on garage', 'error', 7500)
            return false
        end
    elseif garage.type == 'gang' then
        if type(garage.gang) == "string" and  not IsStringNilOrEmpty(garage.gang) then
            return garage.gang == PlayerGang.name
        elseif type(garage.gang) == "table" then
            return TableContains(garage.gang, PlayerGang.name)
        else
            exports.qbx_core:Notify('gang not defined on garage', 'error', 7500)
            return false
        end
    end
    return true
end

local function CanParkVehicle(veh, garageName, vehLocation)
    local garage = garageName and Garages[garageName] or (CurrentGarage and Garages[CurrentGarage] or HouseGarages[CurrentHouseGarage])
    if not garage then return false end
    local parkingDistance = garage.ParkingDistance and garage.ParkingDistance or config.ParkingDistance
    local vehClass = GetVehicleClass(veh)
    local vehCategories = GetVehicleCategoriesFromClass(vehClass)

    if garage and garage.vehicleCategories and not TableContains(garage.vehicleCategories, vehCategories) then
        exports.qbx_core:Notify(locale("not_correct_type"), "error", 4500)
        return false
    end

    local parkingSpots = garage.ParkingSpots and garage.ParkingSpots or {}
    if next(parkingSpots) then
        local _, closestDistance, closestLocation = GetClosestLocation(parkingSpots, vehLocation)
        if closestDistance >= parkingDistance then
            exports.qbx_core:Notify(locale("too_far_away"), "error", 4500)
            return false
        else
            return true, closestLocation
        end
    else
        return true
    end
end

local function ParkOwnedVehicle(veh, garageName, vehLocation, plate)
    local bodyDamage = math.ceil(GetVehicleBodyHealth(veh))
    local engineDamage = math.ceil(GetVehicleEngineHealth(veh))

    local totalFuel = 0

    if config.FuelScript then
        totalFuel = exports[config.FuelScript]:GetFuel(veh)
    elseif config.FuelScript == '' then
        totalFuel = Entity(veh).state.fuel
    end

    local canPark, closestLocation = CanParkVehicle(veh, garageName, vehLocation)
    local closestVec3 = closestLocation and vector3(closestLocation.x,closestLocation.y, closestLocation.z) or nil
    if not canPark and not garageName.useVehicleSpawner then return end

    local properties = lib.getVehicleProperties(veh)

    if not properties then return end

    TriggerServerEvent('qb-garage:server:updateVehicle', 1, totalFuel, engineDamage, bodyDamage, properties, plate, garageName, config.StoreParkinglotAccuratly and closestVec3 or nil)
    ExitAndDeleteVehicle(veh)
    if plate then
        OutsideVehicles[plate] = nil
        TriggerServerEvent('qb-garages:server:UpdateOutsideVehicles', OutsideVehicles)
    end
    exports.qbx_core:Notify(locale("vehicle_parked"), "success", 4500)
end

function ParkVehicleSpawnerVehicle(veh, garageName, vehLocation, plate)
    local result = lib.callback.await("qb-garage:server:CheckSpawnedVehicle", false, plate)

    local canPark, _ = CanParkVehicle(veh, garageName, vehLocation)
    if result and canPark then
        TriggerServerEvent("qb-garage:server:UpdateSpawnedVehicle", plate, nil)
        ExitAndDeleteVehicle(veh)
    elseif not result then
        exports.qbx_core:Notify(locale("not_owned"), "error", 3500)
    end
end

local function ParkVehicle(veh, garageName, vehLocation)
    local plate = qbx.getVehiclePlate(veh)
    local garageName = garageName or (CurrentGarage or CurrentHouseGarage)
    local garage = Garages[garageName]
    local garagetype = garage and garage.type or 'house'
    local gang = PlayerGang.name
    local job = PlayerJob.name
    local owned = lib.callback.await('qb-garage:server:checkOwnership', false, plate, garagetype, garageName, gang)

    if owned then
        ParkOwnedVehicle(veh, garageName, vehLocation, plate)
    elseif garage and garage.useVehicleSpawner and IsAuthorizedToAccessGarage(garageName) then
        ParkVehicleSpawnerVehicle(veh, vehLocation, vehLocation, plate)
    else
        exports.qbx_core:Notify(locale("not_owned"), "error", 3500)
    end
end

local function JobMenuGarage(garageName)
    local playerJob = PlayerJob.name
    local garage = Garages[garageName]
    local jobGarage = nil

if type(garage.jobGarageIdentifier) ~= "table" then
        jobGarage = config.JobVehicles[garage.jobGarageIdentifier]
    else
        local identifiers = garage.jobGarageIdentifier
        for _, v in ipairs(identifiers) do
            local g = config.JobVehicles[v]
            if g and g.job == playerJob then
                jobGarage = g
            end
        end
    end

    if not jobGarage then
        if garage.jobGarageIdentifier then
            exports.qbx_core:Notify(string.format('Job garage with id %s not configured.', garage.jobGarageIdentifier), 'error', 5000)
        else
            exports.qbx_core:Notify(string.format("'jobGarageIdentifier' not defined on job garage %s ", garageName), 'error', 5000)
        end
        return
    end

    local vehicleMenu = {}

    local vehicles = jobGarage.vehicles[QBX.PlayerData.job.grade.level]
    for index, data in pairs(vehicles) do
        local model = index
        local label = data
        local vehicleConfig = nil
        local addVehicle = true

        if type(data) == "table" then
            local vehicleJob = data.job
            if vehicleJob then
                if type(vehicleJob) == "table" and not TableContains(vehicleJob, playerJob) then
                    addVehicle = false
                elseif playerJob ~= vehicleJob then
                    addVehicle = false
                end
            end

            if addVehicle then
                label = data.label
                model = data.model
                vehicleConfig = config.VehicleSettings[data.configName]
            end
        end

        if addVehicle then
            vehicleMenu[#vehicleMenu+1] = {
                title = label,
                description = "",
                event = "qb-garages:client:TakeOutGarage",
                args = {
                    vehicleModel = model,
                    garage = garage,
                    vehicleConfig = vehicleConfig
                }
            }
        end
    end
    lib.registerContext({
        id = 'qbx_jobVehicle_Menu',
        title = jobGarage.label,
        hasSearch = true,
        options = vehicleMenu
    })
    lib.showContext('qbx_jobVehicle_Menu')
end

local function ParkVehicleRadial()
    local curVeh = GetVehiclePedIsIn(cache.ped)
    local canPark = true
    if config.AllowParkingFromOutsideVehicle and curVeh == 0 then
		local closestVeh = lib.getClosestVehicle(GetEntityCoords(cache.ped), config.VehicleParkDistance)
		if closestVeh then curVeh = closestVeh end
	else
		canPark = GetPedInVehicleSeat(curVeh, -1) == cache.ped
    end
    Wait(200)
    if not curVeh or not DoesEntityExist(curVeh) then return end
    if curVeh ~= 0 and canPark then
        ParkVehicle(curVeh)
    end
end

local function OpenGarageMenu()
    if CurrentGarage then
        local garage = Garages[CurrentGarage]
        local garageType = garage.type
        if garageType == 'job' and garage.useVehicleSpawner then
            JobMenuGarage(CurrentGarage)
        else
            PublicGarage(CurrentGarage, garageType)
        end
    elseif CurrentHouseGarage then
        TriggerEvent('qb-garages:client:OpenHouseGarage')
    end
end

local function AddRadialParkingOption()
    local veh = lib.getClosestVehicle(GetEntityCoords(cache.ped), config.VehicleParkDistance)
    if veh and config.AllowParkingFromOutsideVehicle or cache.vehicle then
        lib.addRadialItem({
            id = 'park_vehicle',
            icon = 'square-parking',
            label = locale('park_vehicle'),
            onSelect = function()
                ParkVehicleRadial()
            end,
        })
    end
	if not cache.vehicle then
        lib.addRadialItem({
            id = 'open_garage',
            icon = 'warehouse',
            label = locale('open_garage'),
            onSelect = function()
                OpenGarageMenu()
            end
        })
	end
end

local function AddRadialImpoundOption()
    lib.addRadialItem({
        id = 'open_impound',
        icon = 'warehouse',
        label = locale('open_impound'),
        onSelect = function()
            OpenGarageMenu()
        end,
    })
end

local function UpdateRadialMenu(garagename)
    CurrentGarage = garagename or CurrentGarage or nil
    local garage = Garages[CurrentGarage]
    if CurrentGarage and garage then
        if garage.type == 'job' and (type(garage) == "table" or not IsStringNilOrEmpty(garage.job)) then
            if IsAuthorizedToAccessGarage(CurrentGarage) then
                AddRadialParkingOption()
            end
        elseif garage.type == 'gang' and not IsStringNilOrEmpty(garage.gang) then
            if PlayerGang.name == garage.gang then
                AddRadialParkingOption()
            end
        elseif garage.type == 'depot' then
            AddRadialImpoundOption()
        elseif IsAuthorizedToAccessGarage(CurrentGarage) then
            AddRadialParkingOption()
        end
    elseif CurrentHouseGarage then
        AddRadialParkingOption()
    else
        RemoveRadialOptions()
    end
end

local function RegisterHousePoly(house)
    if GaragePoly[house] then return end
    local coords = HouseGarages[house].takeVehicle
    if not coords or not coords.x then return end
    local pos = vector3(coords.x, coords.y, coords.z)
    GaragePoly[house] = lib.zones.box({
        coords = pos,
        size = vec3(7.5, 7.5, 5),
        rotation = coords.h or coords.w,
        debug = false,
        onEnter = function()
            CurrentHouseGarage = house
            UpdateRadialMenu()
            lib.showTextUI(Config.HouseParkingDrawText, { position = config.DrawTextPosition })
        end,
        onExit = function()
            lib.hideTextUI()
            RemoveRadialOptions()
            CurrentHouseGarage = nil
        end
    })
end

local function RemoveHousePoly(house)
    if not GaragePoly[house] then return end
    GaragePoly[house]:remove()
    GaragePoly[house] = nil
end

local function GetFreeParkingSpots(parkingSpots)
    local freeParkingSpots = {}
    for _, parkingSpot in ipairs(parkingSpots) do
        local veh = lib.getClosestVehicle(vector3(parkingSpot.x,parkingSpot.y, parkingSpot.z), 1.5, false)
        if not veh then freeParkingSpots[#freeParkingSpots+1] = parkingSpot end
    end
    return freeParkingSpots
end

local function GetFreeSingleParkingSpot(freeParkingSpots, vehicle)
    local checkAt = nil
    if config.StoreParkinglotAccuratly and config.SpawnAtLastParkinglot and vehicle and vehicle.parkingspot then
        checkAt = vector3(vehicle.parkingspot.x, vehicle.parkingspot.y, vehicle.parkingspot.z) or nil
    end
    local _, _, location = GetClosestLocation(freeParkingSpots, checkAt)
    return location
end

local function GetSpawnLocationAndHeading(garage, garageType, parkingSpots, vehicle, spawnDistance)
    local location
    local heading
    local closestDistance = -1

    if garageType == "house" then
        location = garage.takeVehicle
        heading = garage.takeVehicle.w -- yes its 'h' not 'w'...
    else
        if next(parkingSpots) then
            local freeParkingSpots = GetFreeParkingSpots(parkingSpots)
            if config.AllowSpawningFromAnywhere then
                location = GetFreeSingleParkingSpot(freeParkingSpots, vehicle)
                if location == nil then
                    exports.qbx_core:Notify(locale("all_occupied"), "error", 4500)
                return end
                heading = location.w
            else
                _, closestDistance, location = GetClosestLocation(Config.SpawnAtFreeParkingSpot and freeParkingSpots or parkingSpots)
                local plyCoords = GetEntityCoords(cache.ped, 0)
                local spot = vector3(location.x, location.y, location.z)
                if config.SpawnAtLastParkinglot and vehicle and vehicle.parkingspot then
                    spot = vehicle.parkingspot
                end
                local dist = #(plyCoords - vector3(spot.x, spot.y, spot.z))
                if config.SpawnAtLastParkinglot and dist >= spawnDistance then
                    exports.qbx_core:Notify(locale("too_far_away"), "error", 4500)
                    return
                elseif closestDistance >= spawnDistance then
                    return exports.qbx_core:Notify(locale("too_far_away"), "error", 4500)
                else
                    local veh = lib.getClosestVehicle(vector3(location.x,location.y, location.z), 1.5, false)

                    if veh then return exports.qbx_core:Notify(locale("occupied"), "error", 4500) end

                    heading = location.w
                end
            end
        else
            local ped = GetEntityCoords(cache.ped)
            local pedheadin = GetEntityHeading(cache.ped)
            local forward = GetEntityForwardVector(cache.ped)
            local x, y, z = table.unpack(ped + forward * 3)
            location = vector3(x, y, z)
            if config.VehicleHeading == 'forward' then
                heading = pedheadin
            elseif config.VehicleHeading == 'driverside' then
                heading = pedheadin + 90
            elseif config.VehicleHeading == 'hood' then
                heading = pedheadin + 180
            elseif config.VehicleHeading == 'passengerside' then
                heading = pedheadin + 270
            end
        end
    end
    return location, heading
end

local function UpdateVehicleSpawnerSpawnedVehicle(veh, garage, heading, vehicleConf, cb)
    local plate = GetPlate(veh)
    if config.FuelScript then
        exports[config.FuelScript]:SetFuel(veh, 100)
    elseif config.FuelScript == '' then
        Entity(veh).state.fuel = 100 -- Don't change this. Change it in the  Defaults to ox fuel if not set in the config
    end
    TriggerServerEvent("qb-garage:server:UpdateSpawnedVehicle", plate, true)

    ClearMenu()
    SetEntityHeading(veh, heading)

    if vehicleConf then
        if vehicleConf.extras then
            SetVehicleExtras(veh, vehicleConf.extras)
        end
        if vehicleConf.livery then
            SetVehicleLivery(veh, vehicleConf.livery)
        end
    end

	if garage.WarpPlayerIntoVehicle or config.WarpPlayerIntoVehicle and garage.WarpPlayerIntoVehicle == nil then
        TaskWarpPedIntoVehicle(cache.ped, veh, -1)
    end

    SetAsMissionEntity(veh)
    SetVehicleEngineOn(veh, true, false, true)
    if cb then cb(veh) end
end

local function SpawnVehicleSpawnerVehicle(vehicleModel, vehicleConfig, location, heading, cb)
    local garage = Garages[CurrentGarage]
    local jobGrade = QBX.PlayerData.job.grade.level
    local netId = lib.callback.await('qb-garages:server:SpawnVehicleSpawnerVehicle', false, vehicleModel, location, garage.WarpPlayerIntoVehicle or config.WarpPlayerIntoVehicle and garage.WarpPlayerIntoVehicle == nil, CurrentGarage)
    local veh = NetToVeh(netId)
    UpdateVehicleSpawnerSpawnedVehicle(veh, garage, heading, vehicleConfig, cb)
end

function UpdateSpawnedVehicle(spawnedVehicle, vehicleInfo, heading, garage)
    local plate = qbx.getVehiclePlate(spawnedVehicle)
    if garage.useVehicleSpawner then
        ClearMenu()
        if plate then
            OutsideVehicles[plate] = spawnedVehicle
            TriggerServerEvent('qb-garages:server:UpdateOutsideVehicles', OutsideVehicles)
        end
        if config.FuelScript then
            exports[config.FuelScript]:SetFuel(spawnedVehicle, 100)
        elseif config.FuelScript == '' then
            Entity(spawnedVehicle).state.fuel = 100 -- Don't change this. Change it in the  Defaults to ox fuel if not set in the config
        end
        TriggerServerEvent("qb-garage:server:UpdateSpawnedVehicle", plate, true)
    else
        if plate then
            OutsideVehicles[plate] = spawnedVehicle
            TriggerServerEvent('qb-garages:server:UpdateOutsideVehicles', OutsideVehicles)
        end
        if config.FuelScript then
            exports[config.FuelScript]:SetFuel(spawnedVehicle, vehicleInfo.fuel)
        elseif config.FuelScript == '' then
            Entity(spawnedVehicle).state.fuel = vehicleInfo.fuel -- Don't change this. Change it in the  Defaults to ox fuel if not set in the config
        end
        SetAsMissionEntity(spawnedVehicle)
        ApplyVehicleDamage(spawnedVehicle, vehicleInfo)
        TriggerServerEvent('qb-garage:server:updateVehicleState', 0, vehicleInfo.plate, vehicleInfo.garage)
        TriggerEvent("vehiclekeys:client:SetOwner", plate) -- There is really no other way to do this one since it's cliented...
    end
    SetEntityHeading(spawnedVehicle, heading)
    SetAsMissionEntity(spawnedVehicle)
    if config.SpawnWithEngineRunning then
        SetVehicleEngineOn(spawnedVehicle, true, false, true)
    end
end

-- Events

RegisterNetEvent("qb-garages:client:GarageMenu", function(data)
    local garagetype = data.type
    local garageId = data.garageId
    local garage = data.garage
    local header = data.header
    local superCategory = data.superCategory

    local result = lib.callback.await("qb-garage:server:GetGarageVehicles", false, garageId, garagetype, superCategory)
    if result == nil then return exports.qbx_core:Notify(locale("no_vehicles"), "error", 5000) end

    MenuGarageOptions = {}
    result = result and result or {}
    for k, v in pairs(result) do
        local enginePercent = Round(v.engine / 10, 0)
        local bodyPercent = Round(v.body / 10, 0)
        local currentFuel = v.fuel
        local vehData = exports.qbx_core:GetVehiclesByName()[v.vehicle]
        local vname = 'Vehicle does not exist'
        if vehData then
            local vehCategories = GetVehicleCategoriesFromClass(GetVehicleClassFromName(v.vehicle))
            if garage and garage.vehicleCategories and not TableContains(garage.vehicleCategories, vehCategories) then
                goto skipVehicle
            end
            vname = vehData.name
        end

        if v.state == 0 then
            v.state = locale("out")
        elseif v.state == 1 then
            v.state = locale("garaged")
        elseif v.state == 2 then
            v.state = locale("impound")
        end

        if type == "depot" then
            MenuGarageOptions[#MenuGarageOptions + 1] = {
                title = locale('header_depot', vname, v.depotprice ),
                description = locale('text_depot', v.plate),
                icon = "fas fa-car-side",
                arrow = true,
                colorScheme = 'red',
                progress = currentFuel,
                metadata = {
                    { label = 'Engine', value = enginePercent, progress = enginePercent },
                    { label = 'Body', value = bodyPercent, progress = bodyPercent },
                },
                event = "qb-garages:client:TakeOutDepot",
                args = {
                    vehicle = v,
                    vehicleModel = v.vehicle,
                    type = type,
                    garage = garage,
                }
            }
        else
            MenuGarageOptions[#MenuGarageOptions + 1] = {
                title = locale('header_garage', vname, v.plate),
                description = locale('text_garage', v.state ),
                icon = "fas fa-car-side",
                arrow = true,
                colorScheme = 'red',
                progress = currentFuel,
                metadata = {
                    { label = 'Engine', value = enginePercent, progress = enginePercent },
                    { label = 'Body', value = bodyPercent, progress = bodyPercent },
                },
                event = "qb-garages:client:TakeOutGarage",
                args = {
                    vehicle = v,
                    vehicleModel = v.vehicle,
                    type = type,
                    garage = garage,
                    superCategory = superCategory,
                }
            }
        end
        ::skipVehicle::
    end
    lib.registerContext({id = 'context_garage_carinfo', title = header, hasSearch = true, options = MenuGarageOptions})
    lib.showContext('context_garage_carinfo')
end)

RegisterNetEvent('qb-garages:client:TakeOutGarage', function(data, cb)
    local garageType = data.type
    local vehicleModel = data.vehicleModel
    local vehicleConfig = data.vehicleConfig
    local vehicle = data.vehicle
    local garage = data.garage
    local spawnDistance = garage.SpawnDistance and garage.SpawnDistance or config.SpawnDistance
    local parkingSpots = garage.ParkingSpots or {}

    local location, heading = GetSpawnLocationAndHeading(garage, garageType, parkingSpots, vehicle, spawnDistance)

    -- if not location and not heading then return end (This was added into qb-garages, seems to be that it's finicky.)

    if garage.useVehicleSpawner then
        SpawnVehicleSpawnerVehicle(vehicleModel, vehicleConfig, location, heading, cb)
    else
        local netId = lib.callback.await('qb-garage:server:spawnvehicle', false, vehicle, location, garage.WarpPlayerIntoVehicle or Config.WarpPlayerIntoVehicle and garage.WarpPlayerIntoVehicle == nil)
        Wait(100)
        local veh = NetToVeh(netId)
        if not veh or not netId then
            print("ISSUE HERE: ", netId)
        end
        UpdateSpawnedVehicle(veh, vehicle, heading, garage)
        if cb then cb(veh) end
    end
end)

RegisterNetEvent('qb-garages:client:ParkLastVehicle', function(parkingName)
    local curVeh = GetLastDrivenVehicle(cache.ped)

    if not curVeh then return exports.qbx_core:Notify(locale('no_vehicle'), "error", 4500) end

    local coords = GetEntityCoords(curVeh)
    ParkVehicle(curVeh, parkingName or CurrentGarage, coords)
end)

RegisterNetEvent('qb-garages:client:TakeOutDepot', function(data)
    local vehicle = data.vehicle
    -- check whether the vehicle is already spawned
    local vehExists = DoesEntityExist(OutsideVehicles[vehicle.plate]) or GetVehicleByPlate(vehicle.plate)

    if vehExists then return exports.qbx_core:Notify(locale('not_impound'), "error", 5000) end
    if QBX.PlayerData?.money.cash <= vehicle.depotprice and QBX.PlayerData?.money.bank <= vehicle.depotprice then return exports.qbx_core:Notify(locale('not_enough'), "error", 5000) end

    TriggerEvent("qb-garages:client:TakeOutGarage", data, function (veh)
        if veh then TriggerServerEvent("qb-garage:server:PayDepotPrice", data) end
    end)
end)

RegisterNetEvent('qb-garages:client:TrackVehicleByPlate', function(plate)
    TrackVehicleByPlate(plate)
end)

RegisterNetEvent('qb-garages:client:OpenHouseGarage', function()
    MenuHouseGarage()
end)

RegisterNetEvent('qb-garages:client:setHouseGarage', function(house, hasKey)
    if hasKey then
        if HouseGarages[house] and HouseGarages[house].takeVehicle.x then
            RegisterHousePoly(house)
        end
    else
        RemoveHousePoly(house)
    end
end)

RegisterNetEvent('qb-garages:client:houseGarageConfig', function(garageConfig)
    for _,v in pairs(garageConfig) do
        v.vehicleCategories = config.HouseGarageCategories
    end
    HouseGarages = garageConfig
end)

RegisterNetEvent('qb-garages:client:addHouseGarage', function(house, garageInfo)
    garageInfo.vehicleCategories = config.HouseGarageCategories
    HouseGarages[house] = garageInfo
end)

RegisterNetEvent('qb-garages:client:removeHouseGarage', function(house)
    RemoveHousePoly(house)
end)

AddEventHandler('QBCore:Client:OnPlayerLoaded', function()
    if not QBX.PlayerData then return end
    PlayerGang = QBX.PlayerData.gang
    PlayerJob = QBX.PlayerData.job
    local outsideVehicles = lib.callback.await('qb-garage:server:GetOutsideVehicles', false)
    OutsideVehicles = outsideVehicles
end)

AddEventHandler('onResourceStart', function(resourceName)
    if resourceName == GetCurrentResourceName() and QBX.PlayerData ~= {} then
        if not QBX.PlayerData then return end
        PlayerGang = QBX.PlayerData.gang
        PlayerJob = QBX.PlayerData.job
    end
end)

AddEventHandler('onResourceStop', function(resource)
    if resource == GetCurrentResourceName() then
        RemoveRadialOptions()
        for k, _ in pairs(GarageZones) do
            exports.ox_target:removeZone(k)
        end
    end
end)

RegisterNetEvent('QBCore:Client:OnGangUpdate', function(gang)
    PlayerGang = gang
end)

RegisterNetEvent('QBCore:Client:OnJobUpdate', function(job)
    PlayerJob = job
end)

-- Threads

CreateThread(function()
    for _, garage in pairs(Garages) do
        if garage.showBlip then
            local Garage = AddBlipForCoord(garage.blipcoords.x, garage.blipcoords.y, garage.blipcoords.z)
            local blipColor = garage.blipColor or 3
            SetBlipSprite(Garage, garage.blipNumber)
            SetBlipDisplay(Garage, 4)
            SetBlipScale(Garage, 0.60)
            SetBlipCategory(Garage, 10)
            SetBlipAsShortRange(Garage, true)
            SetBlipColour(Garage, blipColor)
            BeginTextCommandSetBlipName("STRING")
            AddTextComponentSubstringPlayerName(Config.GarageNameAsBlipName and garage.label or garage.blipName)
            EndTextCommandSetBlipName(Garage)
        end
    end
end)

CreateThread(function()
    for garageName, garage in pairs(Garages) do
        if (garage.type == 'public' or garage.type == 'depot' or garage.type == 'job' or garage.type == 'gang') then
            local zone = {}
            for _, value in pairs(garage.Zone.Shape) do
                zone[#zone+1] = vector3(value.x, value.y, value.z)
            end
            GarageZones[garageName] = lib.zones.poly({
                points = zone,
                thickness = garage.Zone.Thickness,
                debug = false,
                onEnter = function()
                    if config.Debug then print('is in garage') end

                    if IsAuthorizedToAccessGarage(garageName) then
                        UpdateRadialMenu(garageName)
                        lib.showTextUI(Garages[CurrentGarage].drawText, { position = config.DrawTextPosition })
                    end
                    UpdateRadial = false
                end,
                inside = function (self)
                    while self.insideZone do
                        Wait(2500)
                        if self.insideZone then
                            local ClosestVehicle = lib.getClosestVehicle(GetEntityCoords(cache.ped), config.VehicleParkDistance)
                            if UpdateRadial then
                                UpdateRadialMenu(garageName)
                                UpdateRadial = false
                            else
                                if ClosestVehicle and not ParkingUpdated then
                                    UpdateRadial = true
                                    ParkingUpdated = true
                                else
                                    if ParkingUpdated and not ClosestVehicle then
                                        ParkingUpdated = false
                                        lib.removeRadialItem('park_vehicle')
                                    end
                                end
                            end
                        end
                    end
                end,
                onExit = function()
                    ResetCurrentGarage()
					RemoveRadialOptions()
                    lib.hideTextUI()
                    UpdateRadial = true
                end
            })
        end
    end
end)

CreateThread(function()
    local debug = false
    for _, garage in pairs(Garages) do
        if garage.debug then
            debug = true
            break
        end
    end
    while debug do
        for _, garage in pairs(Garages) do
            local parkingSpots = garage.ParkingSpots and garage.ParkingSpots or {}
            if next(parkingSpots) and garage.debug then
                for _, location in pairs(parkingSpots) do
                    DrawMarker(2, location.x, location.y, location.z + 0.98, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.4, 0.4, 0.2, 255, 255, 255, 255, 0, 0, 0, 1, 0, 0, 0)
                end
            end
        end
        Wait(0)
    end
end)

CreateThread(function()
    for category, classes  in pairs(config.VehicleCategories) do
        for _, class  in pairs(classes) do
            VehicleClassMap[class] = VehicleClassMap[class] or {}
            VehicleClassMap[class][#VehicleClassMap[class]+1] = category
        end
    end
end)

AddEventHandler('baseevents:enteredVehicle', function(vehicle)
    UpdateRadial = true
end)

AddEventHandler('baseevents:leftVehicle', function(vehicle)
    UpdateRadial = true
end)
