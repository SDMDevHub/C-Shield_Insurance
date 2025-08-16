-- ================================
-- SISTEMA ASSICURAZIONE AUTO ESX
-- ================================

-- CLIENT SIDE (client.lua)
-- ================================

ESX = nil
local PlayerData = {}
local isInsuranceMenuOpen = false
local currentVehicle = nil

Citizen.CreateThread(function()
    while ESX == nil do
        TriggerEvent('esx:getSharedObject', function(obj) ESX = obj end)
        Citizen.Wait(0)
    end
    
    while ESX.GetPlayerData().job == nil do
        Citizen.Wait(10)
    end
    PlayerData = ESX.GetPlayerData()
end)

-- Comando per aprire menu assicurazione
RegisterCommand('assicurazione', function()
    if IsPedInAnyVehicle(PlayerPedId(), false) then
        currentVehicle = GetVehiclePedIsIn(PlayerPedId(), false)
        local plate = GetVehicleNumberPlateText(currentVehicle)
        TriggerServerEvent('insurance:checkVehicleInsurance', plate)
    else
        ESX.ShowNotification('~r~Devi essere in un veicolo!')
    end
end)

-- Aprire menu quando si entra in un veicolo
Citizen.CreateThread(function()
    while true do
        Citizen.Wait(1000)
        local ped = PlayerPedId()
        
        if IsPedInAnyVehicle(ped, false) then
            local vehicle = GetVehiclePedIsIn(ped, false)
            local plate = GetVehicleNumberPlateText(vehicle)
            
            -- Controllo automatico assicurazione ogni minuto
            TriggerServerEvent('insurance:checkInsuranceStatus', plate)
        end
    end
end)

-- Gestione danni veicolo
Citizen.CreateThread(function()
    while true do
        Citizen.Wait(5000) -- Controllo ogni 5 secondi
        local ped = PlayerPedId()
        
        if IsPedInAnyVehicle(ped, false) then
            local vehicle = GetVehiclePedIsIn(ped, false)
            local plate = GetVehicleNumberPlateText(vehicle)
            local engineHealth = GetVehicleEngineHealth(vehicle)
            local bodyHealth = GetVehicleBodyHealth(vehicle)
            
            -- Se il veicolo è danneggiato significativamente
            if engineHealth < 800 or bodyHealth < 800 then
                local damageLevel = math.floor((2000 - (engineHealth + bodyHealth)) / 20)
                TriggerServerEvent('insurance:reportDamage', plate, damageLevel)
            end
        end
    end
end)

-- Event handlers
RegisterNetEvent('insurance:openMenu')
AddEventHandler('insurance:openMenu', function(vehicleData, insuranceData)
    if not isInsuranceMenuOpen then
        isInsuranceMenuOpen = true
        SetNuiFocus(true, true)
        
        SendNUIMessage({
            type = 'openInsurance',
            vehicle = vehicleData,
            insurance = insuranceData
        })
    end
end)

RegisterNetEvent('insurance:closeMenu')
AddEventHandler('insurance:closeMenu', function()
    isInsuranceMenuOpen = false
    SetNuiFocus(false, false)
    SendNUIMessage({type = 'closeInsurance'})
end)

RegisterNetEvent('insurance:updateStatus')
AddEventHandler('insurance:updateStatus', function(message, type)
    ESX.ShowNotification(message)
end)

-- NUI Callbacks
RegisterNUICallback('closeMenu', function(data, cb)
    TriggerEvent('insurance:closeMenu')
    cb('ok')
end)

RegisterNUICallback('buyInsurance', function(data, cb)
    local plate = GetVehicleNumberPlateText(currentVehicle)
    TriggerServerEvent('insurance:buyInsurance', plate, data.type, data.duration)
    cb('ok')
end)

RegisterNUICallback('claimInsurance', function(data, cb)
    local plate = GetVehicleNumberPlateText(currentVehicle)
    TriggerServerEvent('insurance:claimDamage', plate)
    cb('ok')
end)

RegisterNUICallback('renewInsurance', function(data, cb)
    local plate = GetVehicleNumberPlateText(currentVehicle)
    TriggerServerEvent('insurance:renewInsurance', plate, data.duration)
    cb('ok')
end)

-- ================================
-- SERVER SIDE (server.lua)
-- ================================

ESX = nil
TriggerEvent('esx:getSharedObject', function(obj) ESX = obj end)

-- Configurazione assicurazioni
local InsuranceConfig = {
    types = {
        basic = {
            name = "Assicurazione Base",
            coverage = 0.5, -- 50% copertura danni
            price_per_day = 50,
            max_claims = 2
        },
        premium = {
            name = "Assicurazione Premium",
            coverage = 0.8, -- 80% copertura danni
            price_per_day = 100,
            max_claims = 5
        },
        full = {
            name = "Assicurazione Completa",
            coverage = 1.0, -- 100% copertura danni
            price_per_day = 150,
            max_claims = 999
        }
    },
    repair_costs = {
        low = 500,    -- Danni lievi
        medium = 1500, -- Danni medi
        high = 3000   -- Danni gravi
    }
}

-- Event Handlers
RegisterServerEvent('insurance:checkVehicleInsurance')
AddEventHandler('insurance:checkVehicleInsurance', function(plate)
    local xPlayer = ESX.GetPlayerFromId(source)
    
    MySQL.Async.fetchAll('SELECT * FROM vehicle_insurance WHERE plate = @plate', {
        ['@plate'] = plate
    }, function(result)
        
        MySQL.Async.fetchAll('SELECT * FROM owned_vehicles WHERE plate = @plate AND owner = @owner', {
            ['@plate'] = plate,
            ['@owner'] = xPlayer.identifier
        }, function(vehicleResult)
            
            if vehicleResult[1] then
                local vehicleData = {
                    plate = plate,
                    model = vehicleResult[1].vehicle,
                    owner = vehicleResult[1].owner
                }
                
                local insuranceData = result[1] or {active = false}
                
                -- Controllo se assicurazione è scaduta
                if insuranceData.active and insuranceData.expires_at then
                    local currentTime = os.time()
                    local expiryTime = tonumber(insuranceData.expires_at)
                    
                    if currentTime > expiryTime then
                        -- Assicurazione scaduta
                        MySQL.Async.execute('UPDATE vehicle_insurance SET active = 0 WHERE plate = @plate', {
                            ['@plate'] = plate
                        })
                        insuranceData.active = false
                        insuranceData.expired = true
                    end
                end
                
                TriggerClientEvent('insurance:openMenu', source, vehicleData, insuranceData)
            else
                TriggerClientEvent('insurance:updateStatus', source, '~r~Non sei il proprietario di questo veicolo!', 'error')
            end
        end)
    end)
end)

RegisterServerEvent('insurance:buyInsurance')
AddEventHandler('insurance:buyInsurance', function(plate, insuranceType, duration)
    local xPlayer = ESX.GetPlayerFromId(source)
    local config = InsuranceConfig.types[insuranceType]
    
    if not config then
        TriggerClientEvent('insurance:updateStatus', source, '~r~Tipo di assicurazione non valido!', 'error')
        return
    end
    
    local totalCost = config.price_per_day * duration
    
    if xPlayer.getMoney() >= totalCost then
        xPlayer.removeMoney(totalCost)
        
        local expiryTime = os.time() + (duration * 24 * 60 * 60) -- giorni in secondi
        
        MySQL.Async.execute('INSERT INTO vehicle_insurance (plate, owner, type, active, claims_used, expires_at, purchased_at) VALUES (@plate, @owner, @type, 1, 0, @expires, @purchased) ON DUPLICATE KEY UPDATE type = @type, active = 1, claims_used = 0, expires_at = @expires, purchased_at = @purchased', {
            ['@plate'] = plate,
            ['@owner'] = xPlayer.identifier,
            ['@type'] = insuranceType,
            ['@expires'] = expiryTime,
            ['@purchased'] = os.time()
        })
        
        TriggerClientEvent('insurance:updateStatus', source, '~g~Assicurazione acquistata con successo! Costo: $' .. totalCost, 'success')
        TriggerClientEvent('insurance:closeMenu', source)
        
        -- Log transazione
        TriggerEvent('insurance:logTransaction', xPlayer.identifier, plate, 'purchase', totalCost, insuranceType, duration)
    else
        TriggerClientEvent('insurance:updateStatus', source, '~r~Non hai abbastanza soldi! Costo: $' .. totalCost, 'error')
    end
end)

RegisterServerEvent('insurance:claimDamage')
AddEventHandler('insurance:claimDamage', function(plate)
    local xPlayer = ESX.GetPlayerFromId(source)
    
    MySQL.Async.fetchAll('SELECT * FROM vehicle_insurance WHERE plate = @plate AND owner = @owner AND active = 1', {
        ['@plate'] = plate,
        ['@owner'] = xPlayer.identifier
    }, function(result)
        
        if result[1] then
            local insurance = result[1]
            local config = InsuranceConfig.types[insurance.type]
            
            -- Controllo se può ancora fare claims
            if insurance.claims_used >= config.max_claims then
                TriggerClientEvent('insurance:updateStatus', source, '~r~Hai esaurito i sinistri disponibili!', 'error')
                return
            end
            
            -- Controllo se assicurazione è scaduta
            if os.time() > tonumber(insurance.expires_at) then
                TriggerClientEvent('insurance:updateStatus', source, '~r~Assicurazione scaduta!', 'error')
                return
            end
            
            -- Calcolo danno e rimborso
            local vehicle = GetVehiclePedIsIn(GetPlayerPed(source), false)
            local engineHealth = GetVehicleEngineHealth(vehicle)
            local bodyHealth = GetVehicleBodyHealth(vehicle)
            local totalHealth = engineHealth + bodyHealth
            
            local damageLevel = 'low'
            if totalHealth < 1200 then
                damageLevel = 'high'
            elseif totalHealth < 1600 then
                damageLevel = 'medium'
            end
            
            local repairCost = InsuranceConfig.repair_costs[damageLevel]
            local reimbursement = math.floor(repairCost * config.coverage)
            
            -- Dare rimborso
            xPlayer.addMoney(reimbursement)
            
            -- Riparare veicolo
            SetVehicleEngineHealth(vehicle, 1000.0)
            SetVehicleBodyHealth(vehicle, 1000.0)
            SetVehicleFixed(vehicle)
            
            -- Aggiornare claims utilizzati
            MySQL.Async.execute('UPDATE vehicle_insurance SET claims_used = claims_used + 1 WHERE plate = @plate', {
                ['@plate'] = plate
            })
            
            TriggerClientEvent('insurance:updateStatus', source, '~g~Sinistro elaborato! Rimborso: $' .. reimbursement .. ' | Claims rimasti: ' .. (config.max_claims - insurance.claims_used - 1), 'success')
            TriggerClientEvent('insurance:closeMenu', source)
            
            -- Log sinistro
            TriggerEvent('insurance:logClaim', xPlayer.identifier, plate, damageLevel, reimbursement)
        else
            TriggerClientEvent('insurance:updateStatus', source, '~r~Nessuna assicurazione attiva trovata!', 'error')
        end
    end)
end)

RegisterServerEvent('insurance:renewInsurance')
AddEventHandler('insurance:renewInsurance', function(plate, duration)
    local xPlayer = ESX.GetPlayerFromId(source)
    
    MySQL.Async.fetchAll('SELECT * FROM vehicle_insurance WHERE plate = @plate AND owner = @owner', {
        ['@plate'] = plate,
        ['@owner'] = xPlayer.identifier
    }, function(result)
        
        if result[1] then
            local insurance = result[1]
            local config = InsuranceConfig.types[insurance.type]
            local renewCost = config.price_per_day * duration
            
            if xPlayer.getMoney() >= renewCost then
                xPlayer.removeMoney(renewCost)
                
                local currentExpiry = tonumber(insurance.expires_at)
                local newExpiry = math.max(currentExpiry, os.time()) + (duration * 24 * 60 * 60)
                
                MySQL.Async.execute('UPDATE vehicle_insurance SET active = 1, expires_at = @expires WHERE plate = @plate', {
                    ['@plate'] = plate,
                    ['@expires'] = newExpiry
                })
                
                TriggerClientEvent('insurance:updateStatus', source, '~g~Assicurazione rinnovata! Costo: $' .. renewCost, 'success')
                TriggerClientEvent('insurance:closeMenu', source)
            else
                TriggerClientEvent('insurance:updateStatus', source, '~r~Non hai abbastanza soldi per il rinnovo! Costo: $' .. renewCost, 'error')
            end
        else
            TriggerClientEvent('insurance:updateStatus', source, '~r~Nessuna assicurazione trovata!', 'error')
        end
    end)
end)

-- Sistema di controllo automatico scadenze
Citizen.CreateThread(function()
    while true do
        Citizen.Wait(300000) -- Controllo ogni 5 minuti
        
        MySQL.Async.fetchAll('SELECT * FROM vehicle_insurance WHERE active = 1', {}, function(results)
            for _, insurance in pairs(results) do
                if os.time() > tonumber(insurance.expires_at) then
                    MySQL.Async.execute('UPDATE vehicle_insurance SET active = 0 WHERE id = @id', {
                        ['@id'] = insurance.id
                    })
                    
                    -- Notifica al giocatore se online
                    local xPlayer = ESX.GetPlayerFromIdentifier(insurance.owner)
                    if xPlayer then
                        TriggerClientEvent('insurance:updateStatus', xPlayer.source, '~y~La tua assicurazione per il veicolo ' .. insurance.plate .. ' è scaduta!', 'warning')
                    end
                end
            end
        end)
    end
end)

-- Event per log (opzionale)
RegisterServerEvent('insurance:logTransaction')
AddEventHandler('insurance:logTransaction', function(identifier, plate, action, amount, type, duration)
    -- Qui puoi aggiungere logging su database o file
    print('[INSURANCE LOG] ' .. identifier .. ' - ' .. action .. ' - Plate: ' .. plate .. ' - Amount: $' .. amount)
end)

RegisterServerEvent('insurance:logClaim')
AddEventHandler('insurance:logClaim', function(identifier, plate, damageLevel, reimbursement)
    print('[INSURANCE CLAIM] ' .. identifier .. ' - Plate: ' .. plate .. ' - Damage: ' .. damageLevel .. ' - Reimbursement: $' .. reimbursement)
end)