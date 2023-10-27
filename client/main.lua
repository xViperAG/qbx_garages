local PlayerData = {}
local PlayerGang = {}
local PlayerJob = {}
local CurrentHouseGarage = nil
local OutsideVehicles = {}
local CurrentGarage = nil
local GaragePoly = {}
local MenuItemId1 = nil
local MenuItemId2 = nil
local VehicleClassMap = {}
local GarageZones = {}

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
    local plyCoords = loc or GetEntityCoords(cache.ped, 0)
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
    local vehicles = GetVehicles()
    for _, v in pairs(vehicles) do
        if GetPlate(v) == plate then
            return v
        end
    end
    return nil
end

function RemoveRadialOptions()
    if MenuItemId1 then
        exports.qbx_radialmenu:RemoveOption(MenuItemId1)
        MenuItemId1 = nil
    end
    if MenuItemId2 then
        exports.qbx_radialmenu:RemoveOption(MenuItemId2)
        MenuItemId2 = nil
    end
end

local function ResetCurrentGarage()
    CurrentGarage = nil
end

-- Menus
local function PublicGarage(garageName, type)
    local garage = Config.Garages[garageName]
    local categories = garage.vehicleCategories
    local superCategory = GetSuperCategoryFromCategories(categories)
    lib.registerContext({
        id = 'qbx_publicVehicle_list',
        title = garage.label,
        options = {
            {
                title = Lang:t("menu.header.vehicles"),
                description = Lang:t("menu.text.vehicles"),
                event = "qb-garages:client:GarageMenu",
                args = {
                    garageId = garageName,
                    garage = garage,
                    categories = categories,
                    header =  Lang:t("menu.header."..garage.type.."_"..superCategory, {value = garage.label}),
                    superCategory = superCategory,
                    type = type
                }
            }
        }
    })
    lib.showContext('qbx_publicVehicle_list')
end

local function MenuHouseGarage()
    local superCategory = GetSuperCategoryFromCategories(Config.HouseGarageCategories)
    lib.registerContext({
        id = 'qbx_houseVehicle_list',
        title = Lang:t("menu.header.house_garage"),
        options = {
            {
                title = Lang:t("menu.text.vehicles"),
                description = Lang:t("menu.text.vehicles"),
                event = "qb-garages:client:GarageMenu",
                args = {
                    garageId = CurrentHouseGarage,
                    categories = Config.HouseGarageCategories,
                    header =  Config.HouseGarages[CurrentHouseGarage].label,
                    garage = Config.HouseGarages[CurrentHouseGarage],
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

    for _,i in pairs(tyreIndexes) do
        damage.tyres[i] = {
            burst = IsVehicleTyreBurst(vehicle, i, false) == 1,
            onRim = IsVehicleTyreBurst(vehicle, i, true) == 1,
            health = GetTyreHealth(vehicle, i)
        }
    end
    for i=0,7 do
        damage.windows[i] = {
            smashed = not IsVehicleWindowIntact(vehicle, i)
        }
    end
    for i=0,5 do
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
    local garage = Config.Garages[CurrentGarage]
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
    RemoveRadialOptions()
    if Config.SpawnVehiclesServerside then
        Wait(1000)
        TriggerServerEvent('qb-garages:server:parkVehicle', plate)
    end
end

local function GetVehicleCategoriesFromClass(class)
    return VehicleClassMap[class]
end

local function IsAuthorizedToAccessGarage(garageName)
    local garage = Config.Garages[garageName]

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
    local garage = garageName and Config.Garages[garageName] or (CurrentGarage and Config.Garages[CurrentGarage] or Config.HouseGarages[CurrentHouseGarage])
    if not garage then return false end
    local parkingDistance = garage.ParkingDistance and garage.ParkingDistance or Config.ParkingDistance
    local vehClass = GetVehicleClass(veh)
    local vehCategories = GetVehicleCategoriesFromClass(vehClass)

    if garage and garage.vehicleCategories and not TableContains(garage.vehicleCategories, vehCategories) then
        exports.qbx_core:Notify(Lang:t("error.not_correct_type"), "error", 4500)
        return false
    end

    local parkingSpots = garage.ParkingSpots and garage.ParkingSpots or {}
    if next(parkingSpots) then
        local _, closestDistance, closestLocation = GetClosestLocation(parkingSpots, vehLocation)
        if closestDistance >= parkingDistance then
            exports.qbx_core:Notify(Lang:t("error.too_far_away"), "error", 4500)
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

    if Config.FuelScript then
        totalFuel = exports[Config.FuelScript]:GetFuel(veh)
    else
        totalFuel = Entity(veh).state.fuel
    end

    local canPark, closestLocation = CanParkVehicle(veh, garageName, vehLocation)
    local closestVec3 = closestLocation and vector3(closestLocation.x,closestLocation.y, closestLocation.z) or nil
    if not canPark and not garageName.useVehicleSpawner then return end

    local properties = lib.getVehicleProperties(veh)

    if not properties then return end

    TriggerServerEvent('qb-garage:server:updateVehicle', 1, totalFuel, engineDamage, bodyDamage, properties, plate, garageName, Config.StoreParkinglotAccuratly and closestVec3 or nil)
    ExitAndDeleteVehicle(veh)
    if plate then
        OutsideVehicles[plate] = nil
        TriggerServerEvent('qb-garages:server:UpdateOutsideVehicles', OutsideVehicles)
    end
    exports.qbx_core:Notify(Lang:t("success.vehicle_parked"), "success", 4500)
end

function ParkVehicleSpawnerVehicle(veh, garageName, vehLocation, plate)
    local result = lib.callback.await("qb-garage:server:CheckSpawnedVehicle", false, plate)

    local canPark, _ = CanParkVehicle(veh, garageName, vehLocation)
    if result and canPark then
        TriggerServerEvent("qb-garage:server:UpdateSpawnedVehicle", plate, nil)
        ExitAndDeleteVehicle(veh)
    elseif not result then
        exports.qbx_core:Notify(Lang:t("error.not_owned"), "error", 3500)
    end
end

local function ParkVehicle(veh, garageName, vehLocation)
    local plate = GetPlate(veh)
    local garageName = garageName or (CurrentGarage or CurrentHouseGarage)
    local garage = Config.Garages[garageName]
    local garagetype = garage and garage.type or 'house'
    local gang = PlayerGang.name
    local job = PlayerJob.name
    local owned = lib.callback.await('qb-garage:server:checkOwnership', false, plate, garagetype, garageName, gang)

    if owned then
        ParkOwnedVehicle(veh, garageName, vehLocation, plate)
    elseif garage and garage.useVehicleSpawner and IsAuthorizedToAccessGarage(garageName) then
        ParkVehicleSpawnerVehicle(veh, vehLocation, vehLocation, plate)
    else
        exports.qbx_core:Notify(Lang:t("error.not_owned"), "error", 3500)
    end
end

local function AddRadialParkingOption()
    local veh, dist = GetClosestVehicle()
    if (veh and dist <= Config.VehicleParkDistance and Config.AllowParkingFromOutsideVehicle) or IsPedInAnyVehicle(cache.ped, false) then
	if MenuItemId1 then return end
        MenuItemId1 = exports.qbx_radialmenu:AddOption({
            id = 'put_up_vehicle',
            title = 'Park Vehicle',
            icon = 'square-parking',
            type = 'client',
            event = 'qb-garages:client:ParkVehicle',
            shouldClose = true
        }, MenuItemId1)
    end
	if not IsPedInAnyVehicle(cache.ped, false) then
		if MenuItemId2 then return end
		MenuItemId2 = exports.qbx_radialmenu:AddOption({
			id = 'open_garage_menu',
			title = 'Open Garage',
			icon = 'warehouse',
			type = 'client',
			event = 'qb-garages:client:OpenMenu',
			shouldClose = true
		}, MenuItemId2)
	end
end

local function AddRadialImpoundOption()
	if MenuItemId1 then return end
	MenuItemId1 = exports.qbx_radialmenu:AddOption({
        id = 'open_garage_menu',
        title = 'Open Impound Lot',
        icon = 'warehouse',
        type = 'client',
        event = 'qb-garages:client:OpenMenu',
        shouldClose = true
    }, MenuItemId1)
end

local function UpdateRadialMenu(garagename)
    CurrentGarage = garagename or CurrentGarage or nil
    local garage = Config.Garages[CurrentGarage]
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
    local coords = Config.HouseGarages[house].takeVehicle
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
            lib.showTextUI(Config.HouseParkingDrawText, { position = Config.DrawTextPosition })
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

local function JobMenuGarage(garageName)
    local playerJob = PlayerJob.name
    local garage = Config.Garages[garageName]
    local jobGarage = Config.JobVehicles[garage.jobGarageIdentifier]

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
                vehicleConfig = Config.VehicleSettings[data.configName]
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

local function GetFreeParkingSpots(parkingSpots)
    local freeParkingSpots = {}
    for _, parkingSpot in ipairs(parkingSpots) do
        local veh, distance = GetClosestVehicle(vector3(parkingSpot.x,parkingSpot.y, parkingSpot.z))
        if not veh or distance >= 1.5 then
            freeParkingSpots[#freeParkingSpots+1] = parkingSpot
        end
    end
    return freeParkingSpots
end

local function GetFreeSingleParkingSpot(freeParkingSpots, vehicle)
    local checkAt = nil
    if Config.StoreParkinglotAccuratly and Config.SpawnAtLastParkinglot and vehicle and vehicle.parkingspot then
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
            if Config.AllowSpawningFromAnywhere then
                location = GetFreeSingleParkingSpot(freeParkingSpots, vehicle)
                if location == nil then
                    qxports.qbx_core:Notify(Lang:t("error.all_occupied"), "error", 4500)
                return end
                heading = location.w
            else
                _, closestDistance, location = GetClosestLocation(Config.SpawnAtFreeParkingSpot and freeParkingSpots or parkingSpots)
                local plyCoords = GetEntityCoords(cache.ped, 0)
                local spot = vector3(location.x, location.y, location.z)
                if Config.SpawnAtLastParkinglot and vehicle and vehicle.parkingspot then
                    spot = vehicle.parkingspot
                end
                local dist = #(plyCoords - vector3(spot.x, spot.y, spot.z))
                if Config.SpawnAtLastParkinglot and dist >= spawnDistance then
                    exports.qbx_core:Notify(Lang:t("error.too_far_away"), "error", 4500)
                    return
                elseif closestDistance >= spawnDistance then
                    return exports.qbx_core:Notify(Lang:t("error.too_far_away"), "error", 4500)
                else
                    local veh, distance = GetClosestVehicle(vector3(location.x,location.y, location.z))
                    if veh and distance <= 1.5 then
                        return exports.qbx_core:Notify(Lang:t("error.occupied"), "error", 4500)
                    end
                    heading = location.w
                end
            end
        else
            local ped = GetEntityCoords(cache.ped)
            local pedheadin = GetEntityHeading(cache.ped)
            local forward = GetEntityForwardVector(cache.ped)
            local x, y, z = table.unpack(ped + forward * 3)
            location = vector3(x, y, z)
            if Config.VehicleHeading == 'forward' then
                heading = pedheadin
            elseif Config.VehicleHeading == 'driverside' then
                heading = pedheadin + 90
            elseif Config.VehicleHeading == 'hood' then
                heading = pedheadin + 180
            elseif Config.VehicleHeading == 'passengerside' then
                heading = pedheadin + 270
            end
        end
    end
    return location, heading
end

local function UpdateVehicleSpawnerSpawnedVehicle(veh, garage, heading, vehicleConf, cb)
    local plate = GetPlate(veh)
    if Config.FuelScript then
        exports[Config.FuelScript]:SetFuel(veh, 100)
    else
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

	if garage.WarpPlayerIntoVehicle or Config.WarpPlayerIntoVehicle and garage.WarpPlayerIntoVehicle == nil then
        TaskWarpPedIntoVehicle(cache.ped, veh, -1)
    end

    SetAsMissionEntity(veh)
    SetVehicleEngineOn(veh, true, false, true)
    if cb then cb(veh) end
end

local function SpawnVehicleSpawnerVehicle(vehicleModel, vehicleConfig, location, heading, cb)
    local garage = Config.Garages[CurrentGarage]
    local jobGrade = QBX.PlayerData.job.grade.level
    local netId = lib.callback.await('qb-garages:server:SpawnVehicleSpawnerVehicle', false, vehicleModel, location, garage.WarpPlayerIntoVehicle or Config.WarpPlayerIntoVehicle and garage.WarpPlayerIntoVehicle == nil)
    local veh = NetToVeh(netId)
    UpdateVehicleSpawnerSpawnedVehicle(veh, garage, heading, vehicleConfig, cb)
end

function UpdateSpawnedVehicle(spawnedVehicle, vehicleInfo, heading, garage, properties)
    local plate = GetPlate(spawnedVehicle)
    if garage.useVehicleSpawner then
        ClearMenu()
        if plate then
            OutsideVehicles[plate] = spawnedVehicle
            TriggerServerEvent('qb-garages:server:UpdateOutsideVehicles', OutsideVehicles)
        end
        if Config.FuelScript then
            exports[Config.FuelScript]:SetFuel(spawnedVehicle, 100)
        else
            Entity(spawnedVehicle).state.fuel = 100 -- Don't change this. Change it in the  Defaults to ox fuel if not set in the config
        end
        TriggerServerEvent("qb-garage:server:UpdateSpawnedVehicle", plate, true)
    else
        if plate then
            OutsideVehicles[plate] = spawnedVehicle
            TriggerServerEvent('qb-garages:server:UpdateOutsideVehicles', OutsideVehicles)
        end
        if Config.FuelScript then
            exports[Config.FuelScript]:SetFuel(spawnedVehicle, vehicleInfo.fuel)
        else
            Entity(spawnedVehicle).state.fuel = vehicleInfo.fuel -- Don't change this. Change it in the  Defaults to ox fuel if not set in the config
        end
        lib.setVehicleProperties(spawnedVehicle, properties or {})
        SetVehicleNumberPlateText(spawnedVehicle, vehicleInfo.plate)
        SetAsMissionEntity(spawnedVehicle)
        ApplyVehicleDamage(spawnedVehicle, vehicleInfo)
        TriggerServerEvent('qb-garage:server:updateVehicleState', 0, vehicleInfo.plate, vehicleInfo.garage)
        TriggerEvent("vehiclekeys:client:SetOwner", plate) -- There is really no other way to do this one since it's cliented...
    end
    SetEntityHeading(spawnedVehicle, heading)
    SetAsMissionEntity(spawnedVehicle)
    if Config.SpawnWithEngineRunning then
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
    if result == nil then
        return exports.qbx_core:Notify(Lang:t("error.no_vehicles"), "error", 5000)
    end

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
            v.state = Lang:t("status.out")
        elseif v.state == 1 then
            v.state = Lang:t("status.garaged")
        elseif v.state == 2 then
            v.state = Lang:t("status.impound")
        end

        if type == "depot" then
            MenuGarageOptions[#MenuGarageOptions + 1] = {
                title = Lang:t('menu.header.depot', {value = vname, value2 = v.depotprice }),
                description = Lang:t('menu.text.depot', {value = v.plate}),
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
                title = Lang:t('menu.header.garage', {value = vname, value2 = v.plate}),
                description = Lang:t('menu.text.garage', {
                    value = v.state
                }),
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
    local spawnDistance = garage.SpawnDistance and garage.SpawnDistance or Config.SpawnDistance
    local parkingSpots = garage.ParkingSpots or {}

    local location, heading = GetSpawnLocationAndHeading(garage, garageType, parkingSpots, vehicle, spawnDistance)
    if garage.useVehicleSpawner then
        SpawnVehicleSpawnerVehicle(vehicleModel, vehicleConfig, location, heading, cb)
    else
        local netId, properties = lib.callback.await('qb-garage:server:spawnvehicle', false, vehicle, location, garage.WarpPlayerIntoVehicle or Config.WarpPlayerIntoVehicle and garage.WarpPlayerIntoVehicle == nil)
        Wait(100)
            local veh = NetToVeh(netId)
            local veh = NetToVeh(netId)
            if not veh or not netId then
                print("ISSUE HERE: ", netId)
            end
        local veh = NetToVeh(netId)
            if not veh or not netId then
                print("ISSUE HERE: ", netId)
            end
        UpdateSpawnedVehicle(veh, vehicle, heading, garage, properties)
        if cb then cb(veh) end
    end
end)

RegisterNetEvent('qb-garages:client:OpenMenu', function()
    if CurrentGarage then
        local garage = Config.Garages[CurrentGarage]
        local garageType = garage.type
        if garageType == 'job' and garage.useVehicleSpawner then
            JobMenuGarage(CurrentGarage)
        else
            PublicGarage(CurrentGarage, garageType)
        end
    elseif CurrentHouseGarage then
        TriggerEvent('qb-garages:client:OpenHouseGarage')
    end
end)

RegisterNetEvent('qb-garages:client:ParkVehicle', function()
    local curVeh = GetVehiclePedIsIn(cache.ped)
    local canPark = true
    if Config.AllowParkingFromOutsideVehicle and curVeh == 0 then
		local closestVeh, dist = GetClosestVehicle()
		if dist <= Config.VehicleParkDistance then
            curVeh = closestVeh
		end
	else
		canPark = GetPedInVehicleSeat(curVeh, -1) == ped
    end
    Wait(200)
    if not curVeh or not DoesEntityExist(curVeh) then return end
    if curVeh ~= 0 and canPark then
        ParkVehicle(curVeh)
    end
end)

RegisterNetEvent('qb-garages:client:ParkLastVehicle', function(parkingName)
    local curVeh = GetLastDrivenVehicle(cache.ped)
    if not curVeh then
        return exports.qbx_core:Notify(Lang:t('error.no_vehicle'), "error", 4500)
    end

    local coords = GetEntityCoords(curVeh)
    ParkVehicle(curVeh, parkingName or CurrentGarage, coords)
end)

RegisterNetEvent('qb-garages:client:TakeOutDepot', function(data)
    local vehicle = data.vehicle
    -- check whether the vehicle is already spawned
    local vehExists = DoesEntityExist(OutsideVehicles[vehicle.plate]) or (not Config.SpawnVehiclesServerside and GetVehicleByPlate(vehicle.plate))
    if vehExists then
        return exports.qbx_core:Notify(Lang:t('error.not_impound'), "error", 5000)
    end

    local PlayerData = QBX.PlayerData
    if PlayerData?.money.cash <= vehicle.depotprice and PlayerData?.money.bank <= vehicle.depotprice then
        return exports.qbx_core:Notify(Lang:t('error.not_enough'), "error", 5000)
    end

    TriggerEvent("qb-garages:client:TakeOutGarage", data, function (veh)
        if veh then
            TriggerServerEvent("qb-garage:server:PayDepotPrice", data)
        end
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
        if Config.HouseGarages[house] and Config.HouseGarages[house].takeVehicle.x then
            RegisterHousePoly(house)
        end
    else
        RemoveHousePoly(house)
    end
end)

RegisterNetEvent('qb-garages:client:houseGarageConfig', function(garageConfig)
    for _,v in pairs(garageConfig) do
        v.vehicleCategories = Config.HouseGarageCategories
    end
    Config.HouseGarages = garageConfig
    HouseGarages = garageConfig
end)

RegisterNetEvent('qb-garages:client:addHouseGarage', function(house, garageInfo)
    garageInfo.vehicleCategories = Config.HouseGarageCategories
    Config.HouseGarages[house] = garageInfo
    HouseGarages[house] = garageInfo
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
    for _, garage in pairs(Config.Garages) do
        if garage.showBlip then
            local Garage = AddBlipForCoord(garage.blipcoords.x, garage.blipcoords.y, garage.blipcoords.z)
            local blipColor = garage.blipColor ~= nil and garage.blipColor or 3
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
    for garageName, garage in pairs(Config.Garages) do
        if (garage.type == 'public' or garage.type == 'depot' or garage.type == 'job' or garage.type == 'gang') then
            local zone = {}
            for _, value in pairs(garage.Zone.Shape) do
                zone[#zone+1] = vector3(value.x, value.y, garage.Zone['minZ']+1)
            end
            GarageZones[garageName] = lib.zones.poly({
                points = zone,
                thickness = garage.Zone.minZ - garage.Zone.maxZ,
                debug = false,
                onEnter = function()
                    if IsAuthorizedToAccessGarage(garageName) then
                        UpdateRadialMenu(garageName)
                        lib.showTextUI(Garages[CurrentGarage]['drawText'], { position = Config.DrawTextPosition })
                    end
                end,
                inside = function (self)
                    while self.insideZone do
                        Wait(2500)
                        if self.insideZone then
                            UpdateRadialMenu(garageName)
                        end
                    end
                end,
                onExit = function()
                    ResetCurrentGarage()
					RemoveRadialOptions()
                    lib.hideTextUI()
                end
            })
        end
    end
end)

CreateThread(function()
    local debug = false
    for _, garage in pairs(Config.Garages) do
        if garage.debug then
            debug = true
            break
        end
    end
    while debug do
        for _, garage in pairs(Config.Garages) do
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
    for category, classes  in pairs(Config.VehicleCategories) do
        for _, class  in pairs(classes) do
            VehicleClassMap[class] = VehicleClassMap[class] or {}
            VehicleClassMap[class][#VehicleClassMap[class]+1] = category
        end
    end
end)