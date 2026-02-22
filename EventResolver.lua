--[[
    EventResolver.lua - Dynamic Remote Event Name Resolver
    =====================================================
    Mendeteksi nama event yang sudah di-enkripsi dan memetakan ke nama aslinya.
    
    Game "Fish It" sekarang mengenkripsi nama remote event setiap session.
    Module ini mendeteksi mapping secara otomatis menggunakan beberapa metode:
    
    1. Hook Net Module (intercept Net:RemoteEvent / Net:RemoteFunction)
    2. GC Scan (scan garbage collector untuk referensi yang sudah ada)
    3. Script Constant Scan (scan script bytecode untuk string patterns)
    4. Children Brute-force (enumerate net folder children)
    
    PENGGUNAAN:
        local EventResolver = loadstring(game:HttpGet("URL"))()
        -- atau paste langsung di script
        
        EventResolver:Init()
        
        -- Akses event
        local fishCaught = EventResolver:GetRE("FishCaught")
        local chargeFishingRod = EventResolver:GetRF("ChargeFishingRod")
        
        -- Fire event
        fishCaught:FireServer(...)
        chargeFishingRod:InvokeServer(...)
]]

local EventResolver = {}
EventResolver.__index = EventResolver

-- ============================================================
-- KONFIGURASI: Daftar nama asli remote event/function
-- ============================================================
local KNOWN_REMOTE_EVENTS = {
    "FishCaught",
    "FishingMinigameChanged",
    "FishingStopped",
    "UpdateChargeState",
    "BaitSpawned",
    "SpawnTotem",
    "ReplicateTextEffect",
    "EquipToolFromHotbar",
    "FavoriteItem",
    "EquipItem",
    "ActivateEnchantingAltar",
    "ActivateSecondEnchantingAltar",
    "RollEnchant",
    "ClaimPirateChest",
    "ObtainedNewFishNotification",
}

local KNOWN_REMOTE_FUNCTIONS = {
    "ChargeFishingRod",
    "RequestFishingMinigameStarted",
    "CancelFishingInputs",
    "CatchFishCompleted",
    "UpdateAutoFishingState",
    "SellAllItems",
    "UpdateFishingRadar",
    "PurchaseWeatherEvent",
    "PurchaseCharm",
    "InitiateTrade",
}

-- ============================================================
-- INTERNAL STATE
-- ============================================================
local _initialized = false
local _netFolder = nil
local _netModule = nil

-- Mapping: originalName -> RemoteEvent/RemoteFunction instance
local _resolvedRE = {} -- RemoteEvents
local _resolvedRF = {} -- RemoteFunctions

-- Mapping: originalName -> encrypted child name
local _nameMap = {}

-- Log buffer
local _logs = {}

local function log(msg)
    local entry = "[EventResolver] " .. tostring(msg)
    table.insert(_logs, entry)
    print(entry)
end

local function logWarn(msg)
    local entry = "⚠️ [EventResolver] " .. tostring(msg)
    table.insert(_logs, entry)
    warn(entry)
end

-- ============================================================
-- UTILITAS
-- ============================================================

-- Cek apakah API exploit tersedia
local function hasAPI(name)
    return typeof(_G[name]) == "function" or typeof(getfenv()[name]) == "function"
end

local function safeCall(fn, ...)
    local ok, result = pcall(fn, ...)
    return ok, result
end

-- Dapatkan net folder
local function getNetFolder()
    if _netFolder then return _netFolder end
    
    local RS = game:GetService("ReplicatedStorage")
    
    -- Coba path standar
    local ok, folder = pcall(function()
        return RS:WaitForChild("Packages", 10)
            :WaitForChild("_Index", 5)
            :WaitForChild("sleitnick_net@0.2.0", 5)
            :WaitForChild("net", 5)
    end)
    
    if ok and folder then
        _netFolder = folder
        return folder
    end
    
    -- Fallback: cari dengan pattern yang berbeda (versi mungkin berubah)
    local ok2, folder2 = pcall(function()
        local packages = RS:WaitForChild("Packages", 10)
        local index = packages:WaitForChild("_Index", 5)
        
        for _, child in pairs(index:GetChildren()) do
            if child.Name:find("sleitnick_net") or child.Name:find("net@") then
                local netChild = child:FindFirstChild("net")
                if netChild then
                    return netChild
                end
            end
        end
        return nil
    end)
    
    if ok2 and folder2 then
        _netFolder = folder2
        return folder2
    end
    
    logWarn("Gagal menemukan net folder!")
    return nil
end

-- Dapatkan Net module
local function getNetModule()
    if _netModule then return _netModule end
    
    local RS = game:GetService("ReplicatedStorage")
    local ok, mod = pcall(function()
        return require(RS.Packages.Net)
    end)
    
    if ok and mod then
        _netModule = mod
        return mod
    end
    
    return nil
end

-- ============================================================
-- METODE 1: Hook Net Module
-- Intercept panggilan Net:RemoteEvent() dan Net:RemoteFunction()
-- untuk menangkap mapping original name -> encrypted remote
-- ============================================================
local function method1_HookNetModule()
    log("🔍 Metode 1: Hook Net Module...")
    
    local Net = getNetModule()
    if not Net then
        logWarn("Net module tidak ditemukan, skip Metode 1")
        return 0
    end
    
    local count = 0
    
    -- Hook RemoteEvent
    if Net.RemoteEvent then
        local originalRE = Net.RemoteEvent
        
        -- Coba panggil untuk setiap nama yang kita tahu
        for _, name in ipairs(KNOWN_REMOTE_EVENTS) do
            if not _resolvedRE[name] then
                local ok, remote = pcall(function()
                    return originalRE(Net, name)
                end)
                
                if ok and remote then
                    _resolvedRE[name] = remote
                    _nameMap["RE/" .. name] = remote.Name
                    count = count + 1
                    log("  ✅ RE/" .. name .. " -> " .. remote.Name)
                end
            end
        end
    end
    
    -- Hook RemoteFunction
    if Net.RemoteFunction then
        local originalRF = Net.RemoteFunction
        
        for _, name in ipairs(KNOWN_REMOTE_FUNCTIONS) do
            if not _resolvedRF[name] then
                local ok, remote = pcall(function()
                    return originalRF(Net, name)
                end)
                
                if ok and remote then
                    _resolvedRF[name] = remote
                    _nameMap["RF/" .. name] = remote.Name
                    count = count + 1
                    log("  ✅ RF/" .. name .. " -> " .. remote.Name)
                end
            end
        end
    end
    
    log("Metode 1 selesai: " .. count .. " events resolved")
    return count
end

-- ============================================================
-- METODE 2: GC Scan
-- Scan garbage collector untuk menemukan referensi remote
-- yang sudah dibuat oleh game scripts
-- ============================================================
local function method2_GCScan()
    log("🔍 Metode 2: GC Scan...")
    
    -- Cek apakah getgc tersedia (hanya di executor tertentu)
    local getgc_fn = getgc or (debug and debug.getgc)
    if not getgc_fn then
        logWarn("getgc() tidak tersedia, skip Metode 2")
        return 0
    end
    
    local count = 0
    local netFolder = getNetFolder()
    if not netFolder then return 0 end
    
    local ok, gc = pcall(getgc_fn, true)
    if not ok or not gc then
        logWarn("getgc() gagal, skip Metode 2")
        return 0
    end
    
    -- Scan semua table di GC
    for _, obj in pairs(gc) do
        if typeof(obj) == "table" then
            for key, value in pairs(obj) do
                if typeof(value) == "Instance" then
                    -- Cek apakah ini RemoteEvent atau RemoteFunction
                    local isRE = value:IsA("RemoteEvent")
                    local isRF = value:IsA("RemoteFunction")
                    
                    if (isRE or isRF) and value:IsDescendantOf(netFolder) then
                        -- Cek apakah key cocok dengan nama asli
                        if typeof(key) == "string" then
                            for _, knownName in ipairs(KNOWN_REMOTE_EVENTS) do
                                if key:find(knownName) and not _resolvedRE[knownName] then
                                    _resolvedRE[knownName] = value
                                    _nameMap["RE/" .. knownName] = value.Name
                                    count = count + 1
                                    log("  ✅ (GC) RE/" .. knownName .. " -> " .. value.Name)
                                end
                            end
                            for _, knownName in ipairs(KNOWN_REMOTE_FUNCTIONS) do
                                if key:find(knownName) and not _resolvedRF[knownName] then
                                    _resolvedRF[knownName] = value
                                    _nameMap["RF/" .. knownName] = value.Name
                                    count = count + 1
                                    log("  ✅ (GC) RF/" .. knownName .. " -> " .. value.Name)
                                end
                            end
                        end
                    end
                end
            end
        end
    end
    
    log("Metode 2 selesai: " .. count .. " events resolved")
    return count
end

-- ============================================================
-- METODE 3: Children Scan + Fallback Name Match
-- Jika nama masih menggunakan format lama (RF/xxx, RE/xxx),
-- langsung match. Jika sudah terenkripsi, coba match via class.
-- ============================================================
local function method3_ChildrenScan()
    log("🔍 Metode 3: Children Scan...")
    
    local netFolder = getNetFolder()
    if not netFolder then return 0 end
    
    local count = 0
    local children = netFolder:GetChildren()
    
    log("  Total children di net folder: " .. #children)
    
    -- FASE 1: Coba match dengan format lama (RF/xxx, RE/xxx)
    for _, child in pairs(children) do
        local name = child.Name
        
        -- Match format "RE/OriginalName"
        local reMatch = name:match("^RE/(.+)$")
        if reMatch then
            for _, knownName in ipairs(KNOWN_REMOTE_EVENTS) do
                if reMatch == knownName and not _resolvedRE[knownName] then
                    _resolvedRE[knownName] = child
                    _nameMap["RE/" .. knownName] = child.Name
                    count = count + 1
                    log("  ✅ (Direct) RE/" .. knownName)
                end
            end
        end
        
        -- Match format "RF/OriginalName"
        local rfMatch = name:match("^RF/(.+)$")
        if rfMatch then
            for _, knownName in ipairs(KNOWN_REMOTE_FUNCTIONS) do
                if rfMatch == knownName and not _resolvedRF[knownName] then
                    _resolvedRF[knownName] = child
                    _nameMap["RF/" .. knownName] = child.Name
                    count = count + 1
                    log("  ✅ (Direct) RF/" .. knownName)
                end
            end
        end
    end
    
    -- FASE 2: Log semua children yang belum ter-resolve (untuk debugging)
    if count == 0 then
        log("  ⚠️ Tidak ada match format lama. Children names:")
        for i, child in ipairs(children) do
            log("    [" .. i .. "] " .. child.ClassName .. ": " .. child.Name)
        end
    end
    
    log("Metode 3 selesai: " .. count .. " events resolved")
    return count
end

-- ============================================================
-- METODE 4: Upvalue Scan dari FishingController
-- Scan upvalues dari FishingController yang sudah di-require game
-- ============================================================
local function method4_UpvalueScan()
    log("🔍 Metode 4: Upvalue Scan dari FishingController...")
    
    local getupvalues_fn = getupvalues or (debug and debug.getupvalues)
    local getgc_fn = getgc or (debug and debug.getgc)
    
    if not getupvalues_fn or not getgc_fn then
        logWarn("getupvalues/getgc tidak tersedia, skip Metode 4")
        return 0
    end
    
    local count = 0
    local netFolder = getNetFolder()
    if not netFolder then return 0 end
    
    -- Coba temukan FishingController via require cache
    local ok, gc = pcall(getgc_fn, true)
    if not ok or not gc then return 0 end
    
    for _, obj in pairs(gc) do
        if typeof(obj) == "function" then
            local ok2, ups = pcall(getupvalues_fn, obj)
            if ok2 and ups then
                for _, upval in pairs(ups) do
                    if typeof(upval) == "Instance" and (upval:IsA("RemoteEvent") or upval:IsA("RemoteFunction")) then
                        if upval:IsDescendantOf(netFolder) then
                            -- Coba dapatkan info dari constant scan
                            local getinfo_fn = getinfo or (debug and debug.getinfo)
                            local getconstants_fn = getconstants or (debug and debug.getconstants)
                            
                            if getconstants_fn then
                                local ok3, constants = pcall(getconstants_fn, obj)
                                if ok3 and constants then
                                    for _, c in pairs(constants) do
                                        if typeof(c) == "string" then
                                            for _, knownName in ipairs(KNOWN_REMOTE_EVENTS) do
                                                if c == knownName and upval:IsA("RemoteEvent") and not _resolvedRE[knownName] then
                                                    _resolvedRE[knownName] = upval
                                                    _nameMap["RE/" .. knownName] = upval.Name
                                                    count = count + 1
                                                    log("  ✅ (Upvalue) RE/" .. knownName .. " -> " .. upval.Name)
                                                end
                                            end
                                            for _, knownName in ipairs(KNOWN_REMOTE_FUNCTIONS) do
                                                if c == knownName and upval:IsA("RemoteFunction") and not _resolvedRF[knownName] then
                                                    _resolvedRF[knownName] = upval
                                                    _nameMap["RF/" .. knownName] = upval.Name
                                                    count = count + 1
                                                    log("  ✅ (Upvalue) RF/" .. knownName .. " -> " .. upval.Name)
                                                end
                                            end
                                        end
                                    end
                                end
                            end
                        end
                    end
                end
            end
        end
    end
    
    log("Metode 4 selesai: " .. count .. " events resolved")
    return count
end

-- ============================================================
-- PUBLIC API
-- ============================================================

function EventResolver:Init()
    if _initialized then
        log("Sudah diinisialisasi, skip.")
        return true
    end
    
    log("========================================")
    log("🚀 Memulai Event Resolution...")
    log("========================================")
    
    local totalResolved = 0
    local totalExpected = #KNOWN_REMOTE_EVENTS + #KNOWN_REMOTE_FUNCTIONS
    
    -- Jalankan semua metode secara berurutan
    -- Metode 1 adalah yang paling reliable (hook Net module)
    totalResolved = totalResolved + method1_HookNetModule()
    
    -- Jika belum semua ter-resolve, coba metode lain
    if totalResolved < totalExpected then
        totalResolved = totalResolved + method3_ChildrenScan()
    end
    
    if totalResolved < totalExpected then
        totalResolved = totalResolved + method2_GCScan()
    end
    
    if totalResolved < totalExpected then
        totalResolved = totalResolved + method4_UpvalueScan()
    end
    
    log("========================================")
    log("📊 Hasil: " .. totalResolved .. "/" .. totalExpected .. " events resolved")
    log("========================================")
    
    -- Log yang belum ter-resolve
    for _, name in ipairs(KNOWN_REMOTE_EVENTS) do
        if not _resolvedRE[name] then
            logWarn("❌ BELUM RESOLVED: RE/" .. name)
        end
    end
    for _, name in ipairs(KNOWN_REMOTE_FUNCTIONS) do
        if not _resolvedRF[name] then
            logWarn("❌ BELUM RESOLVED: RF/" .. name)
        end
    end
    
    _initialized = true
    
    -- Simpan ke _G agar bisa diakses dari script lain
    _G.EventResolver = EventResolver
    _G.ResolvedNetEvents = {
        RE = _resolvedRE,
        RF = _resolvedRF,
        NameMap = _nameMap,
    }
    
    return totalResolved > 0
end

-- Dapatkan RemoteEvent berdasarkan nama asli
function EventResolver:GetRE(originalName)
    if _resolvedRE[originalName] then
        return _resolvedRE[originalName]
    end
    
    -- Lazy resolve: coba cari lagi
    if not _initialized then
        self:Init()
    end
    
    local result = _resolvedRE[originalName]
    if not result then
        logWarn("RE/" .. originalName .. " belum ter-resolve!")
    end
    return result
end

-- Dapatkan RemoteFunction berdasarkan nama asli
function EventResolver:GetRF(originalName)
    if _resolvedRF[originalName] then
        return _resolvedRF[originalName]
    end
    
    -- Lazy resolve
    if not _initialized then
        self:Init()
    end
    
    local result = _resolvedRF[originalName]
    if not result then
        logWarn("RF/" .. originalName .. " belum ter-resolve!")
    end
    return result
end

-- Dapatkan event dengan format "RE/xxx" atau "RF/xxx"
function EventResolver:Get(fullName)
    local prefix, name = fullName:match("^(R[EF])/(.+)$")
    if prefix == "RE" then
        return self:GetRE(name)
    elseif prefix == "RF" then
        return self:GetRF(name)
    end
    
    logWarn("Format tidak valid: " .. fullName .. " (gunakan RE/xxx atau RF/xxx)")
    return nil
end

-- Dapatkan semua mapping
function EventResolver:GetAllMappings()
    return {
        RE = _resolvedRE,
        RF = _resolvedRF,
        NameMap = _nameMap,
    }
end

-- Dapatkan net folder
function EventResolver:GetNetFolder()
    return getNetFolder()
end

-- Cek apakah sudah diinisialisasi
function EventResolver:IsInitialized()
    return _initialized
end

-- Dapatkan jumlah yang sudah ter-resolve
function EventResolver:GetResolvedCount()
    local reCount = 0
    local rfCount = 0
    for _ in pairs(_resolvedRE) do reCount = reCount + 1 end
    for _ in pairs(_resolvedRF) do rfCount = rfCount + 1 end
    return reCount + rfCount, reCount, rfCount
end

-- Dapatkan log
function EventResolver:GetLogs()
    return _logs
end

-- Reset (untuk re-init setelah reconnect)
function EventResolver:Reset()
    _initialized = false
    _netFolder = nil
    _netModule = nil
    _resolvedRE = {}
    _resolvedRF = {}
    _nameMap = {}
    _logs = {}
    log("🔄 EventResolver di-reset")
end

-- Print report
function EventResolver:PrintReport()
    print("\n" .. string.rep("=", 50))
    print("📋 EVENT RESOLVER REPORT")
    print(string.rep("=", 50))
    
    print("\n--- RemoteEvents ---")
    for _, name in ipairs(KNOWN_REMOTE_EVENTS) do
        local remote = _resolvedRE[name]
        if remote then
            print("  ✅ " .. name .. " -> " .. remote.Name .. " (" .. remote.ClassName .. ")")
        else
            print("  ❌ " .. name .. " -> NOT RESOLVED")
        end
    end
    
    print("\n--- RemoteFunctions ---")
    for _, name in ipairs(KNOWN_REMOTE_FUNCTIONS) do
        local remote = _resolvedRF[name]
        if remote then
            print("  ✅ " .. name .. " -> " .. remote.Name .. " (" .. remote.ClassName .. ")")
        else
            print("  ❌ " .. name .. " -> NOT RESOLVED")
        end
    end
    
    local total, re, rf = self:GetResolvedCount()
    local expected = #KNOWN_REMOTE_EVENTS + #KNOWN_REMOTE_FUNCTIONS
    print("\n📊 Total: " .. total .. "/" .. expected .. " (RE: " .. re .. ", RF: " .. rf .. ")")
    print(string.rep("=", 50) .. "\n")
end

return EventResolver
