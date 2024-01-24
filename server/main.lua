lib.locale()

local OutsideVehicles = {}
local VehicleSpawnerVehicles = {}

local svConfig = require 'config.server'
local Garages = require 'config.shared'.Garages
local HouseGarages = require 'config.shared'.HouseGarages

local function TableContains (tab, val)
    if type(val) == "table" then
        for _, value in ipairs(tab) do
            if TableContains(val, value) then return true end
        end
        return false
    else
        for _, value in ipairs(tab) do
            if value == val then return true end
        end
    end
    return false
end


lib.callback.register("qb-garage:server:GetOutsideVehicle", function(source, plate)
    local pData = exports.qbx_core:GetPlayer(source)
    if not OutsideVehicles[plate] then return nil end
    local result = MySQL.query.await('SELECT * FROM player_vehicles WHERE citizenid = ? and plate = ?', {pData.PlayerData.citizenid, plate})
    return result[1]
end)

lib.callback.register("qb-garages:server:GetVehicleLocation", function(_, plate)
    local vehicles = GetAllVehicles()

    for _, vehicle in pairs(vehicles) do
        local pl = GetVehicleNumberPlateText(vehicle)
        if pl == plate then return GetEntityCoords(vehicle) end
    end

    local result = MySQL.Sync.fetchAll('SELECT * FROM player_vehicles WHERE plate = ?', {plate})

    local veh = result[1]
    if not veh then return nil end

    if svConfig.StoreParkinglotAccuratly and veh.parkingspot then
        local location = json.decode(veh.parkingspot)
        return vector3(location.x, location.y, location.z)
    end

    local garageName = veh and veh.garage
    local garage = Garages[garageName]

    if garage then
        if garage.blipcoords then return garage.blipcoords end
        if garage.Zone and garage.Zone.Shape and garage.Zone.Shape[1] then
            return vector3(garage.Zone.Shape[1].x, garage.Zone.Shape[1].y, garage.Zone.minZ)
        end
    end

    local result = MySQL.query.await('SELECT * FROM houselocations WHERE name = ?', {garageName})
    if result and result[1] then
        local coords = json.decode(result[1].garage)
        if coords then return vector3(coords.x, coords.y, coords.z) end

        return nil
    end

    return nil
end)

lib.callback.register("qb-garage:server:CheckSpawnedVehicle", function(_, plate)
    return VehicleSpawnerVehicles[plate]
end)

RegisterNetEvent("qb-garage:server:UpdateSpawnedVehicle", function(plate, value)
    VehicleSpawnerVehicles[plate] = value

    if svConfig.RenewedKeys then
        exports['Renewed-Vehiclekeys']:addKey(source, plate)
    else
        exports.qbx_vehiclekeys:GiveKeys(source, plate)
    end
end)

local function addVehicleItems(source, plate)
    local player = exports.qbx_core:GetPlayer(source)
    local invId, invLabel = 'trunk' .. plate, 'Job Trunk'

    exports.ox_inventory:RegisterStash(invId, invLabel, 10, 20000)

    Wait(500)

    for k, v in pairs(svConfig.TrunkItems) do
        if player.PlayerData.job.name == svConfig.TrunkItems[k] then
            exports.ox_inventory:AddItem(invId, v.name, v.amount)
        end
    end
end

lib.callback.register('qb-garages:server:SpawnVehicleSpawnerVehicle', function(source, model, coords, warp)
    local netId = qbx.spawnVehicle({
        model = model,
        spawnSource = coords,
        warp = warp
    })

    local plate = qbx.getVehiclePlate(netId)

    if svConfig.addVehicleItems then addVehicleItems(source, plate) end

    return netId
end)

lib.callback.register('qb-garage:server:spawnvehicle', function(source, vehInfo, coords, warp)
    local vehProps = {}
    local plate = vehInfo.plate

    local result = MySQL.query.await('SELECT mods FROM player_vehicles WHERE plate = ?', {plate})
    if result[1] then vehProps = json.decode(result[1].mods) end

    local netId = qbx.spawnVehicle({
        model = vehInfo.vehicle,
        spawnSource = coords,
        warp = warp,
        props = vehProps
    })

    local veh = NetworkGetEntityFromNetworkId(netId)
    if not veh or not NetworkGetNetworkIdFromEntity(veh) then
        print('Server:90 | ISSUE HERE', veh, NetworkGetNetworkIdFromEntity(veh))
    end

    local hasFakePlate = Config.BrazzersFakeplate and exports['brazzers-fakeplates']:getFakePlateFromPlate(plate)
    local netId = NetworkGetNetworkIdFromEntity(veh)
    OutsideVehicles[plate] = {netID = netId, entity = veh}

    SetVehicleNumberPlateText(veh, hasFakePlate)
    if svConfig.RenewedKeys then
        exports['Renewed-Vehiclekeys']:addKey(source, hasFakePlate or plate)
    else
        exports.qbx_vehiclekeys:GiveKeys(source, hasFakePlate or plate)
    end

    return netId, vehProps
end)

local function GetVehicles(citizenid, garageName, state, cb)
    local result = nil
    if not svConfig.GlobalParking then
        result = MySQL.Sync.fetchAll('SELECT * FROM player_vehicles WHERE citizenid = ? AND garage = ? AND state = ?', { citizenid, garageName, state })
    else
        result = MySQL.Sync.fetchAll('SELECT * FROM player_vehicles WHERE citizenid = ? AND state = ?', { citizenid, state })
    end
    return cb(result)
end

local function GetDepotVehicles(citizenid, state, garage, cb)
    local result = MySQL.Sync.fetchAll("SELECT * FROM player_vehicles WHERE citizenid = ? AND (state = ? OR garage = ? OR garage IS NULL or garage = '')", { citizenid, state, garage })
    return cb(result)
end

local function GetVehicleByPlate(plate)
    local vehicles = GetAllVehicles() -- Get all vehicles known to the server
    for _, vehicle in pairs(vehicles) do
        local pl = GetVehicleNumberPlateText(vehicle)
        if pl == plate then return vehicle end
    end
    return nil
end

lib.callback.register("qb-garage:server:GetGarageVehicles", function(source, garage, garageType, category)
    local pData = exports.qbx_core:GetPlayer(source)
    local playerGang = pData.PlayerData.gang.name;
    if garageType == "public" then        --Public garages give player cars in the garage only
        local vehs = GetVehicles(pData.PlayerData.citizenid, garage, 1, function(result)
            local vehs = {}
            if result[1] then
                for _, vehicle in pairs(result) do
                    if vehicle.parkingspot then
                        local spot = json.decode(vehicle.parkingspot)
                        if spot and spot.x then
                            vehicle.parkingspot = vector3(spot.x, spot.y, spot.z)
                        end
                    end
                    if vehicle.damage then
                        vehicle.damage = json.decode(vehicle.damage)
                    end
                    vehs[#vehs + 1] = vehicle
                end
                return vehs
            end
            return nil
        end)
        return vehs
    elseif garageType == "depot" then    --Depot give player cars that are not in garage only
        local tosend = GetDepotVehicles(pData.PlayerData.citizenid, 0, garage, function(result)
            local tosend = {}
            if result[1] then
                if type(category) == 'table' then
                    if TableContains(category, {'car'}) then
                        category = 'car'
                    elseif TableContains(category, {'plane', 'helicopter'}) then
                        category = 'air'
                    elseif TableContains(category, 'boat') then
                        category = 'sea'
                    end
                end
                for _, vehicle in pairs(result) do
                    if GetVehicleByPlate(vehicle.plate) or not exports.qbx_core:GetVehiclesByName()[vehicle.vehicle] then
                        goto skip
                    end
                    if vehicle.depotprice == 0 then
                        vehicle.depotprice = svConfig.DepotPrice
                    end

                    vehicle.parkingspot = nil
                    if vehicle.damage then
                        vehicle.damage = json.decode(vehicle.damage)
                    end

                    if category == "air" and ( exports.qbx_core:GetVehiclesByName()[vehicle.vehicle].category == "helicopters" or exports.qbx_core:GetVehiclesByName()[vehicle.vehicle].category == "planes" ) then
                        tosend[#tosend + 1] = vehicle
                    elseif category == "sea" and exports.qbx_core:GetVehiclesByName()[vehicle.vehicle].category == "boats" then
                        tosend[#tosend + 1] = vehicle
                    elseif category == "car" and exports.qbx_core:GetVehiclesByName()[vehicle.vehicle].category ~= "helicopters" and exports.qbx_core:GetVehiclesByName()[vehicle.vehicle].category ~= "planes" and exports.qbx_core:GetVehiclesByName()[vehicle.vehicle].category ~= "boats" then
                        tosend[#tosend + 1] = vehicle
                    end
                    ::skip::
                end
                return tosend
            else
                return nil
            end
        end)
        return tosend
    else --House give all cars in the garage, Job and Gang depend of config
        local shared = ''
        if not TableContains(svConfig.SharedJobGarages, garage) and not (svConfig.SharedHouseGarage and garageType == "house") and not ((svConfig.SharedGangGarages == true or (type(svConfig.SharedGangGarages) == "table" and svConfig.SharedGangGarages[playerGang])) and garageType == "gang") then
            shared = " AND citizenid = '" .. pData.PlayerData.citizenid .. "'"
        end

        local result = MySQL.query.await('SELECT * FROM player_vehicles WHERE garage = ? AND state = ?' .. shared, { garage, 1 })
        if result[1] then
            local vehs = {}
            for _, vehicle in pairs(result) do
                local spot = json.decode(vehicle.parkingspot)
                if vehicle.parkingspot then
                    vehicle.parkingspot = vector3(spot.x, spot.y, spot.z)
                end
                if vehicle.damage then
                    vehicle.damage = json.decode(vehicle.damage)
                end
                vehs[#vehs + 1] = vehicle
            end
            return vehs
        else
            return nil
        end
    end
end)

lib.callback.register("qb-garage:server:checkOwnership", function(source, plate, garageType, garage, gang)
    local src = source
    local pData = exports.qbx_core:GetPlayer(src)
    if garageType == "public" then        --Public garages only for player cars
        local addSQLForAllowParkingAnyonesVehicle = ""
        if not svConfig.AllowParkingAnyonesVehicle then
            addSQLForAllowParkingAnyonesVehicle = " AND citizenid = '"..pData.PlayerData.citizenid.."' "
        end

        local result = MySQL.query.await('SELECT * FROM player_vehicles WHERE plate = ? ' .. addSQLForAllowParkingAnyonesVehicle, {plate})
        local fakeplate = MySQL.query.await('SELECT * FROM player_vehicles WHERE fakeplate = ?', {plate})

        return result[1] and true or fakeplate[1] and true or false

    elseif garageType == "house" then     --House garages only for player cars that have keys of the house
        local result = MySQL.query.await('SELECT * FROM player_vehicles WHERE plate = ?', {plate})
        local fakeplate = MySQL.query.await('SELECT * FROM player_vehicles WHERE fakeplate = ?', {plate})

        return result[1] and true or fakeplate[1] and true or false
    elseif garageType == "gang" then        --Gang garages only for gang members cars (for sharing)
        local result = MySQL.query.await('SELECT * FROM player_vehicles WHERE plate = ?', {plate})
        local fakeplate = MySQL.query.await('SELECT * FROM player_vehicles WHERE fakeplate = ?', {plate})

        if result[1] then
            --Check if found owner is part of the gang
            return exports.qbx_core:GetPlayer(source).PlayerData.gang.name == gang
        else
            return fakeplate[1] and true or false
        end
    else --Job garages only for cars that are owned by someone (for sharing and service) or only by player depending of config
        local shared = ''

        if not TableContains(svConfig.SharedJobGarages, garage) then
            shared = " AND citizenid = '"..pData.PlayerData.citizenid.."'"
        end

        local result = MySQL.query.await('SELECT * FROM player_vehicles WHERE plate = ?'..shared, {plate})
        local fakeplate = MySQL.query.await('SELECT * FROM player_vehicles WHERE fakeplate = ?'..shared, {plate})

        return result?[1] and true or fakeplate[1] and true or false
    end
end)

lib.callback.register("qb-garage:server:GetVehicleProperties", function(source, plate)
    local properties = {}

    local hasFakePlate = svConfig.BrazzersFakeplate and exports['brazzers-fakeplates']:getFakePlateFromPlate(plate)
    if hasFakePlate then plate = hasFakePlate end

    local result = MySQL.query.await('SELECT mods FROM player_vehicles WHERE plate = ?', {plate})

    if result[1] then properties = json.decode(result[1].mods) end

    return properties
end)

RegisterNetEvent('qb-garage:server:updateVehicle', function(state, fuel, engine, body, properties, plate, garage, location, damage)
    local hasFakePlate = svConfig.BrazzersFakeplate and exports['brazzers-fakeplates']:getPlateFromFakePlate(plate)

    if hasFakePlate then plate = hasFakePlate end

    Wait(100)

    if location and type(location) == 'vector3' then
        MySQL.update('UPDATE player_vehicles SET state = ?, garage = ?, fuel = ?, engine = ?, body = ?, mods = ?, parkingspot = ? WHERE plate = ?',{state, garage, fuel, engine, body, json.encode(properties), json.encode(location), plate})
    else
        MySQL.update('UPDATE player_vehicles SET state = ?, garage = ?, fuel = ?, engine = ?, body = ?, mods = ? WHERE plate = ?', {state, garage, fuel, engine, body, json.encode(properties), plate})
    end
end)

RegisterNetEvent('qb-garage:server:updateVehicleState', function(state, plate, garage)
    local hasFakePlate = svConfig.BrazzersFakeplate and exports['brazzers-fakeplates']:getPlateFromFakePlate(plate)

    if hasFakePlate then plate = hasFakePlate end

    Wait(100)

    MySQL.update('UPDATE player_vehicles SET state = ?, garage = ?, depotprice = ? WHERE plate = ?',{state, garage, 0, plate})
end)

RegisterNetEvent('qb-garages:server:UpdateOutsideVehicles', function(Vehicles)
    local src = source
    local ply = exports.qbx_core:GetPlayer(src)
    local citizenId = ply.PlayerData.citizenid

    OutsideVehicles[citizenId] = Vehicles
end)

lib.callback.register("qb-garage:server:GetOutsideVehicles", function(source)
    local ply = exports.qbx_core:GetPlayer(source)
    local citizenId = ply.PlayerData.citizenid

    if OutsideVehicles[citizenId] and next(OutsideVehicles[citizenId]) then
        return OutsideVehicles[citizenId]
    else
        return {}
    end
end)

AddEventHandler('onResourceStart', function(resource)
    if resource == GetCurrentResourceName() then
        Wait(100)
        if svConfig.AutoRespawn then
            MySQL.update('UPDATE player_vehicles SET state = 1 WHERE state = 0', {})
        end
    end
end)

RegisterNetEvent('qb-garage:server:PayDepotPrice', function(data)
    local src = source
    local Player = exports.qbx_core:GetPlayer(src)
    local cashBalance = Player.PlayerData.money.cash
    local bankBalance = Player.PlayerData.money.bank
    local vehicle = data.vehicle

    local result = MySQL.query.await('SELECT * FROM player_vehicles WHERE plate = ?', {vehicle.plate})

    if result[1] then
        vehicle = result[1]
        local depotPrice = vehicle.depotprice ~= 0 and vehicle.depotprice or svConfig.DepotPrice
        if cashBalance >= depotPrice then
            Player.Functions.RemoveMoney("cash", depotPrice, "paid-depot")
        elseif bankBalance >= depotPrice then
            Player.Functions.RemoveMoney("bank", depotPrice, "paid-depot")
        else
            exports.qbx_core:Notify(src, locale("not_enough"), 'error')
        end
    end
end)

RegisterNetEvent('qb-garages:server:parkVehicle', function(source, plate)
    local src = source
    local vehicle = GetVehicleByPlate(plate)
    if vehicle then
        DeleteEntity(vehicle)

        if svConfig.RenewedKeys then
            exports.ox_inventory:RemoveItem(src, 'vehiclekey', 1, { plate = plate })
            exports['Renewed-Vehiclekeys']:removeKey(src, plate)
        end
    end
end)

-- External Calls
-- Call from qbx_vehiclesales

lib.callback.register('qb-garage:server:checkVehicleOwner', function(source, plate)
    local player = exports.qbx_core:GetPlayer(source)
    local result = MySQL.query.await('SELECT * FROM player_vehicles WHERE plate = ? AND citizenid = ?',{plate, player.PlayerData.citizenid})
    return result[1], result[1]?.balance
end)

--Call from qb-phone
lib.callback.register('qb-garage:server:GetPlayerVehicles', function(source)
    local Player = exports.qbx_core:GetPlayer(source)
    local Vehicles = {}

    local result = MySQL.query.await('SELECT * FROM player_vehicles WHERE citizenid = ?', {Player.PlayerData.citizenid})
    if not result[1] then return nil end

    for _, v in pairs(result) do
        local VehicleData = exports.qbx_core:GetVehiclesByName()[v.vehicle]
        if not VehicleData then goto continue end
        local VehicleGarage = locale("no_garage")
        if v.garage then
            if Garages[v.garage] then
                VehicleGarage = Garages[v.garage].label
            elseif HouseGarages[v.garage] then
                VehicleGarage = HouseGarages[v.garage].label
            end
        end

        if v.state == 0 then
            v.state = locale("out")
        elseif v.state == 1 then
            v.state = locale("garaged")
        elseif v.state == 2 then
            v.state = locale("impound")
        end

        local fullname
        if VehicleData["brand"] then
            fullname = VehicleData["brand"] .. " " .. VehicleData["name"]
        else
            fullname = VehicleData["name"]
        end
        local spot = json.decode(v.parkingspot)
        Vehicles[#Vehicles+1] = {
            fullname = fullname,
            brand = VehicleData["brand"],
            model = VehicleData["name"],
            plate = v.plate,
            garage = VehicleGarage,
            state = v.state,
            fuel = v.fuel,
            engine = v.engine,
            body = v.body,
            parkingspot = spot and vector3(spot.x, spot.y, spot.z) or nil,
            damage = json.decode(v.damage)
        }
        ::continue::
    end
    return Vehicles
end)

local function GetRandomPublicGarage()
    for garageName, garage in pairs(Garages)do
        if garage.type == 'public' then
            return garageName -- return the first garageName
        end
    end
end

-- Command to restore lost cars (garage: 'None' or something similar)
lib.addCommand("restorelostcars", {
    help = "Restores cars that were parked in a grage that no longer exists in the config or is invalid (name change or removed).",
    params = {
        {name = "destination_garage", help = "(Optional) Garage where the cars are being sent to.", optional = true}
    },
    restricted = svConfig.RestoreCommandPermissionLevel
}, function(source, args)
    local src = source
    if next(Garages) then
        local destinationGarage = args.destination_garage and args.destination_garage or GetRandomPublicGarage()
        if Garages[destinationGarage] == nil then
            exports.qbx_core:Notify(src, 'Invalid garage name provided', 'error', 4500)
            return
        end

        local invalidGarages = {}
        local result = MySQL.query('SELECT garage FROM player_vehicles')
        if result[1] then
            for _,v in ipairs(result) do
                if Garages[v.garage] == nil then
                    if v.garage then invalidGarages[v.garage] = true end
                end
            end
            for garage,_ in pairs(invalidGarages) do
                MySQL.update('UPDATE player_vehicles set garage = ? WHERE garage = ?',{destinationGarage, garage})
            end
            MySQL.update('UPDATE player_vehicles set garage = ? WHERE garage IS NULL OR garage = \'\'',{destinationGarage})
        end
    end
end)