-- ============================================
-- LYNX GUI LIBRARY v3.2 - IMPROVED EDITION
-- Orange Theme | Transparent | Smooth Performance
-- ============================================

local Library = {}
Library.flags = {}
Library.pages = {}
Library._navButtons = {}
Library._currentPage = nil
Library._gui = nil
Library._win = nil
Library._sidebar = nil
Library._contentBg = nil
Library._pageTitle = nil
Library._navContainer = nil
Library._connections = {}
Library._spawns = {}
Library._dropdownContainer = nil

-- ============================================
-- SERVICES (Cached)
-- ============================================
local Players = game:GetService("Players")
local CoreGui = game:GetService("CoreGui")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")
local RunService = game:GetService("RunService")
local HttpService = game:GetService("HttpService")

local localPlayer = Players.LocalPlayer
local isMobile = UserInputService.TouchEnabled and not UserInputService.KeyboardEnabled

-- ============================================
-- COLOR PALETTE (Orange Theme + Transparency)
-- ============================================
local colors = {
    primary = Color3.fromRGB(255, 140, 0),       -- Vibrant Orange
    primaryDark = Color3.fromRGB(230, 120, 0),   -- Darker Orange
    accent = Color3.fromRGB(255, 165, 0),        -- Light Orange
    success = Color3.fromRGB(50, 205, 50),       -- Green
    warning = Color3.fromRGB(255, 140, 0),       -- Orange
    error = Color3.fromRGB(255, 69, 0),          -- Red Orange
    
    bg1 = Color3.fromRGB(17, 17, 24),            -- Darkest (with transparency)
    bg2 = Color3.fromRGB(23, 23, 32),            -- Dark
    bg3 = Color3.fromRGB(31, 31, 43),            -- Medium
    bg4 = Color3.fromRGB(41, 41, 56),            -- Light
    
    text = Color3.fromRGB(255, 255, 255),        -- White
    textSub = Color3.fromRGB(220, 220, 220),     -- Light gray
    textMuted = Color3.fromRGB(160, 160, 160),   -- Muted
    
    border = Color3.fromRGB(255, 140, 0),        -- Orange border
    borderLight = Color3.fromRGB(255, 165, 0),   -- Light Orange border
}

-- Window Config
local windowSize = UDim2.new(0, 480, 0, 340)
local minWindowSize = Vector2.new(420, 300)
local maxWindowSize = Vector2.new(700, 550)
local sidebarWidth = 120

-- Animation speeds (optimized)
local tweenSpeed = 0.15
local tweenSpeedFast = 0.08

-- ============================================
-- UTILITY FUNCTIONS
-- ============================================
local function new(class, props)
    local inst = Instance.new(class)
    if props then
        for k, v in pairs(props) do
            if k ~= "Parent" then
                inst[k] = v
            end
        end
        if props.Parent then
            inst.Parent = props.Parent
        end
    end
    return inst
end

local function tween(obj, props, speed)
    local info = TweenInfo.new(speed or tweenSpeed, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
    local tw = TweenService:Create(obj, info, props)
    tw:Play()
    return tw
end

-- ============================================
-- CONNECTION MANAGER
-- ============================================
function Library:AddConnection(name, connection)
    if self._connections[name] then
        pcall(function() self._connections[name]:Disconnect() end)
    end
    self._connections[name] = connection
    return connection
end

function Library:AddSpawn(name, thread)
    if self._spawns[name] then
        pcall(function() task.cancel(self._spawns[name]) end)
    end
    self._spawns[name] = thread
    return thread
end

function Library:Cleanup()
    for _, conn in pairs(self._connections) do
        pcall(function() conn:Disconnect() end)
    end
    for _, thread in pairs(self._spawns) do
        pcall(function() task.cancel(thread) end)
    end
    table.clear(self._connections)
    table.clear(self._spawns)
end

-- ============================================
-- CONFIG SYSTEM
-- ============================================
local CONFIG_FOLDER = "LynxGUI_Configs"
local CONFIG_FILE = CONFIG_FOLDER .. "/lynx_config.json"
local CurrentConfig = {}
local DefaultConfig = {}
local isDirty = false
local saveScheduled = false
local CallbackRegistry = {}

local function DeepCopy(original)
    local copy = {}
    for k, v in pairs(original) do
        copy[k] = type(v) == "table" and DeepCopy(v) or v
    end
    return copy
end

local function MergeTables(target, source)
    for k, v in pairs(source) do
        if type(v) == "table" and type(target[k]) == "table" then
            MergeTables(target[k], v)
        else
            target[k] = v
        end
    end
end

local function EnsureFolderExists()
    if not isfolder(CONFIG_FOLDER) then makefolder(CONFIG_FOLDER) end
end

Library.ConfigSystem = {}

function Library.ConfigSystem.SetDefaults(defaults)
    DefaultConfig = DeepCopy(defaults)
end

function Library.ConfigSystem.Save()
    local success = pcall(function()
        EnsureFolderExists()
        writefile(CONFIG_FILE, HttpService:JSONEncode(CurrentConfig))
    end)
    return success
end

function Library.ConfigSystem.Load()
    EnsureFolderExists()
    CurrentConfig = DeepCopy(DefaultConfig)
    if isfile(CONFIG_FILE) then
        pcall(function()
            local loaded = HttpService:JSONDecode(readfile(CONFIG_FILE))
            MergeTables(CurrentConfig, loaded)
        end)
    end
    return CurrentConfig
end

function Library.ConfigSystem.Get(path, default)
    if not path then return default end
    local value = CurrentConfig
    for key in string.gmatch(path, "[^.]+") do
        if type(value) ~= "table" then return default end
        value = value[key]
    end
    return value ~= nil and value or default
end

function Library.ConfigSystem.Set(path, value)
    if not path then return end
    local keys = {}
    for key in string.gmatch(path, "[^.]+") do table.insert(keys, key) end
    local target = CurrentConfig
    for i = 1, #keys - 1 do
        if type(target[keys[i]]) ~= "table" then target[keys[i]] = {} end
        target = target[keys[i]]
    end
    target[keys[#keys]] = value
end

function Library.ConfigSystem.Reset()
    CurrentConfig = DeepCopy(DefaultConfig)
    Library.ConfigSystem.Save()
end

function Library.ConfigSystem.Delete()
    if isfile(CONFIG_FILE) then
        delfile(CONFIG_FILE)
    end
end

local function MarkDirty()
    if _G.AutoSaveEnabled == false then return end
    isDirty = true
    if saveScheduled then return end
    saveScheduled = true
    task.delay(2, function()
        if isDirty and _G.AutoSaveEnabled ~= false then 
            Library.ConfigSystem.Save() 
            isDirty = false
        end
        saveScheduled = false
    end)
end

local function RegisterCallback(configPath, callback, componentType, defaultValue)
    if configPath then
        table.insert(CallbackRegistry, {
            path = configPath, 
            callback = callback, 
            type = componentType, 
            default = defaultValue
        })
    end
end

local function ExecuteConfigCallbacks()
    for _, entry in ipairs(CallbackRegistry) do
        local value = Library.ConfigSystem.Get(entry.path, entry.default)
        if entry.callback then 
            pcall(entry.callback, value)
        end
    end
end

-- ============================================
-- GLOBAL BRIDGE
-- ============================================
_G.AutoSaveEnabled = true

function _G.GetConfigValue(key, default)
    return Library.ConfigSystem.Get(key, default)
end

function _G.SaveConfigValue(key, value)
    Library.ConfigSystem.Set(key, value)
    if _G.AutoSaveEnabled then
        MarkDirty()
    end
end

function _G.GetFullConfig()
    return CurrentConfig
end

-- ============================================
-- CREATE WINDOW (Transparent & Modern)
-- ============================================
function Library:CreateWindow(config)
    config = config or {}
    local name = config.Name or "LynxGUI"
    local title = config.Title or "LynX"
    local subtitle = config.Subtitle or ""
    
    -- Remove existing
    local existingGUI = CoreGui:FindFirstChild(name)
    if existingGUI then
        existingGUI:Destroy()
        task.wait(0.1)
    end
    
    -- Main ScreenGui
    self._gui = new("ScreenGui", {
        Name = name,
        Parent = CoreGui,
        IgnoreGuiInset = true,
        ResetOnSpawn = false,
        ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
        DisplayOrder = 2147483647
    })
    
    local function bringToFront()
        self._gui.DisplayOrder = 2147483647
    end
    
    -- Dropdown Container (for popup dropdowns)
    self._dropdownContainer = new("Frame", {
        Parent = self._gui,
        Size = UDim2.new(1, 0, 1, 0),
        BackgroundTransparency = 1,
        BorderSizePixel = 0,
        Visible = false,
        ZIndex = 300
    })
    
    -- Main Window (TRANSPARENT)
    self._win = new("Frame", {
        Parent = self._gui,
        Size = windowSize,
        Position = UDim2.new(0.5, -windowSize.X.Offset/2, 0.5, -windowSize.Y.Offset/2),
        BackgroundColor3 = colors.bg1,
        BackgroundTransparency = 0.15, -- TRANSPARENT
        BorderSizePixel = 0,
        ClipsDescendants = false,
        ZIndex = 10
    })
    new("UICorner", {Parent = self._win, CornerRadius = UDim.new(0, 12)})
    
    -- Glassmorphism effect
    local blur = new("ImageLabel", {
        Parent = self._win,
        Size = UDim2.new(1, 0, 1, 0),
        BackgroundTransparency = 1,
        Image = "rbxasset://textures/ui/GuiImagePlaceholder.png",
        ImageTransparency = 0.95,
        ScaleType = Enum.ScaleType.Tile,
        TileSize = UDim2.new(0, 100, 0, 100),
        ZIndex = 10
    })
    new("UICorner", {Parent = blur, CornerRadius = UDim.new(0, 12)})
    
    -- Orange glowing border
    new("UIStroke", {
        Parent = self._win,
        Color = colors.border,
        Thickness = 2,
        Transparency = 0.3
    })
    
    -- Header (40px)
    local header = new("Frame", {
        Parent = self._win,
        Size = UDim2.new(1, 0, 0, 40),
        BackgroundColor3 = colors.bg2,
        BackgroundTransparency = 0.3,
        BorderSizePixel = 0,
        ZIndex = 11
    })
    new("UICorner", {Parent = header, CornerRadius = UDim.new(0, 12)})
    
    -- Header gradient
    local headerGradient = new("UIGradient", {
        Parent = header,
        Color = ColorSequence.new{
            ColorSequenceKeypoint.new(0, colors.primary),
            ColorSequenceKeypoint.new(1, colors.primaryDark)
        },
        Transparency = NumberSequence.new{
            NumberSequenceKeypoint.new(0, 0.7),
            NumberSequenceKeypoint.new(1, 0.9)
        },
        Rotation = 45
    })
    
    -- Drag indicator (orange)
    local dragIndicator = new("Frame", {
        Parent = header,
        Size = UDim2.new(0, 36, 0, 4),
        Position = UDim2.new(0.5, -18, 0, 8),
        BackgroundColor3 = colors.primary,
        BorderSizePixel = 0,
        ZIndex = 12
    })
    new("UICorner", {Parent = dragIndicator, CornerRadius = UDim.new(1, 0)})
    
    -- Title
    new("TextLabel", {
        Parent = header,
        Text = title,
        Size = UDim2.new(0, 120, 1, 0),
        Position = UDim2.new(0, 14, 0, 0),
        BackgroundTransparency = 1,
        Font = Enum.Font.GothamBold,
        TextSize = 16,
        TextColor3 = colors.primary,
        TextXAlignment = Enum.TextXAlignment.Left,
        ZIndex = 12
    })
    
    -- Subtitle
    new("TextLabel", {
        Parent = header,
        Text = subtitle,
        Size = UDim2.new(0, 180, 1, 0),
        Position = UDim2.new(0, 135, 0, 0),
        BackgroundTransparency = 1,
        Font = Enum.Font.Gotham,
        TextSize = 11,
        TextColor3 = colors.textMuted,
        TextXAlignment = Enum.TextXAlignment.Left,
        ZIndex = 12
    })
    
    -- Minimize button
    local btnMin = new("TextButton", {
        Parent = header,
        Size = UDim2.new(0, 30, 0, 30),
        Position = UDim2.new(1, -35, 0.5, -15),
        BackgroundColor3 = colors.bg3,
        BackgroundTransparency = 0.4,
        BorderSizePixel = 0,
        Text = "─",
        Font = Enum.Font.GothamBold,
        TextSize = 18,
        TextColor3 = colors.primary,
        AutoButtonColor = false,
        ZIndex = 13
    })
    new("UICorner", {Parent = btnMin, CornerRadius = UDim.new(0, 8)})
    
    btnMin.MouseEnter:Connect(function()
        tween(btnMin, {BackgroundColor3 = colors.primary, BackgroundTransparency = 0}, tweenSpeedFast)
        tween(btnMin, {TextColor3 = colors.text}, tweenSpeedFast)
    end)
    btnMin.MouseLeave:Connect(function()
        tween(btnMin, {BackgroundColor3 = colors.bg3, BackgroundTransparency = 0.4}, tweenSpeedFast)
        tween(btnMin, {TextColor3 = colors.primary}, tweenSpeedFast)
    end)
    
    -- Sidebar (transparent)
    self._sidebar = new("Frame", {
        Parent = self._win,
        Size = UDim2.new(0, sidebarWidth, 1, -40),
        Position = UDim2.new(0, 0, 0, 40),
        BackgroundColor3 = colors.bg2,
        BackgroundTransparency = 0.4,
        BorderSizePixel = 0,
        ClipsDescendants = true,
        ZIndex = 11
    })
    
    -- Sidebar separator (orange)
    new("Frame", {
        Parent = self._sidebar,
        Size = UDim2.new(0, 2, 1, 0),
        Position = UDim2.new(1, -1, 0, 0),
        BackgroundColor3 = colors.primary,
        BackgroundTransparency = 0.5,
        BorderSizePixel = 0,
        ZIndex = 11
    })
    
    -- Nav container (scrollable)
    self._navContainer = new("ScrollingFrame", {
        Parent = self._sidebar,
        Size = UDim2.new(1, -8, 1, -10),
        Position = UDim2.new(0, 4, 0, 5),
        BackgroundTransparency = 1,
        BorderSizePixel = 0,
        ScrollBarThickness = 0,
        CanvasSize = UDim2.new(0, 0, 0, 0),
        AutomaticCanvasSize = Enum.AutomaticSize.Y,
        ScrollingDirection = Enum.ScrollingDirection.Y,
        ZIndex = 12
    })
    new("UIListLayout", {
        Parent = self._navContainer, 
        Padding = UDim.new(0, 4), 
        SortOrder = Enum.SortOrder.LayoutOrder
    })
    
    -- Content area
    self._contentBg = new("Frame", {
        Parent = self._win,
        Size = UDim2.new(1, -(sidebarWidth + 10), 1, -50),
        Position = UDim2.new(0, sidebarWidth + 5, 0, 45),
        BackgroundTransparency = 1,
        BorderSizePixel = 0,
        ClipsDescendants = true,
        ZIndex = 11
    })
    
    -- Top bar
    local topBar = new("Frame", {
        Parent = self._contentBg,
        Size = UDim2.new(1, -6, 0, 32),
        Position = UDim2.new(0, 3, 0, 2),
        BackgroundColor3 = colors.bg2,
        BackgroundTransparency = 0.3,
        BorderSizePixel = 0,
        ZIndex = 12
    })
    new("UICorner", {Parent = topBar, CornerRadius = UDim.new(0, 8)})
    new("UIStroke", {
        Parent = topBar,
        Color = colors.primary,
        Thickness = 1,
        Transparency = 0.7
    })
    
    self._pageTitle = new("TextLabel", {
        Parent = topBar,
        Text = "Dashboard",
        Size = UDim2.new(1, -20, 1, 0),
        Position = UDim2.new(0, 12, 0, 0),
        Font = Enum.Font.GothamBold,
        TextSize = 12,
        BackgroundTransparency = 1,
        TextColor3 = colors.primary,
        TextXAlignment = Enum.TextXAlignment.Left,
        ZIndex = 13
    })
    
    -- Resize handle
    local resizeHandle = new("TextButton", {
        Parent = self._win,
        Size = UDim2.new(0, 18, 0, 18),
        Position = UDim2.new(1, -18, 1, -18),
        BackgroundColor3 = colors.primary,
        BackgroundTransparency = 0.3,
        BorderSizePixel = 0,
        Text = "⋰",
        Font = Enum.Font.GothamBold,
        TextSize = 12,
        TextColor3 = colors.text,
        AutoButtonColor = false,
        ZIndex = 100
    })
    new("UICorner", {Parent = resizeHandle, CornerRadius = UDim.new(0, 6)})
    
    -- Minimize system
    local minimized = false
    local icon = nil
    local savedIconPos = UDim2.new(0, 20, 0, 100)
    
    local function createMinimizedIcon()
        if icon then return end
        icon = new("Frame", {
            Parent = self._gui,
            Size = UDim2.new(0, 52, 0, 52),
            Position = savedIconPos,
            BackgroundColor3 = colors.bg2,
            BackgroundTransparency = 0.2,
            BorderSizePixel = 0,
            ZIndex = 200
        })
        new("UICorner", {Parent = icon, CornerRadius = UDim.new(0, 12)})
        new("UIStroke", {
            Parent = icon,
            Color = colors.primary,
            Thickness = 3
        })
        
        new("TextLabel", {
            Parent = icon,
            Text = "L",
            Size = UDim2.new(1, 0, 1, 0),
            Font = Enum.Font.GothamBold,
            TextSize = 28,
            BackgroundTransparency = 1,
            TextColor3 = colors.primary,
            ZIndex = 201
        })
        
        local dragging, dragStart, startPos, dragMoved = false, nil, nil, false
        
        icon.InputBegan:Connect(function(input)
            if input.UserInputType == Enum.UserInputType.MouseButton1 or 
               input.UserInputType == Enum.UserInputType.Touch then
                dragging = true
                dragMoved = false
                dragStart = input.Position
                startPos = icon.Position
            end
        end)
        
        icon.InputChanged:Connect(function(input)
            if dragging and (input.UserInputType == Enum.UserInputType.MouseMovement or 
                           input.UserInputType == Enum.UserInputType.Touch) then
                local delta = input.Position - dragStart
                if math.sqrt(delta.X^2 + delta.Y^2) > 5 then 
                    dragMoved = true 
                end
                icon.Position = UDim2.new(
                    startPos.X.Scale, startPos.X.Offset + delta.X,
                    startPos.Y.Scale, startPos.Y.Offset + delta.Y
                )
            end
        end)
        
        icon.InputEnded:Connect(function(input)
            if input.UserInputType == Enum.UserInputType.MouseButton1 or 
               input.UserInputType == Enum.UserInputType.Touch then
                if dragging then
                    dragging = false
                    savedIconPos = icon.Position
                    if not dragMoved then
                        bringToFront()
                        tween(self._win, {
                            Size = windowSize,
                            Position = UDim2.new(0.5, -windowSize.X.Offset/2, 0.5, -windowSize.Y.Offset/2)
                        }, tweenSpeed)
                        self._win.Visible = true
                        icon:Destroy()
                        icon = nil
                        minimized = false
                    end
                end
            end
        end)
    end
    
    btnMin.MouseButton1Click:Connect(function()
        if not minimized then
            tween(self._win, {
                Size = UDim2.new(0, 0, 0, 0),
                Position = UDim2.new(0.5, 0, 0.5, 0)
            }, tweenSpeed)
            task.wait(tweenSpeed)
            self._win.Visible = false
            createMinimizedIcon()
            minimized = true
        end
    end)
    
    -- Dragging
    local dragging, dragStart, startPos = false, nil, nil
    
    header.InputBegan:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1 or 
           input.UserInputType == Enum.UserInputType.Touch then
            bringToFront()
            dragging = true
            dragStart = input.Position
            startPos = self._win.Position
        end
    end)
    
    -- Resizing
    local resizing, resizeStartPos, resizeStartSize = false, nil, nil
    
    resizeHandle.InputBegan:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1 or 
           input.UserInputType == Enum.UserInputType.Touch then
            resizing = true
            resizeStartPos = input.Position
            resizeStartSize = self._win.Size
        end
    end)
    
    self:AddConnection("inputChanged", UserInputService.InputChanged:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseMovement or 
           input.UserInputType == Enum.UserInputType.Touch then
            if dragging and startPos then
                local delta = input.Position - dragStart
                self._win.Position = UDim2.new(
                    startPos.X.Scale, startPos.X.Offset + delta.X,
                    startPos.Y.Scale, startPos.Y.Offset + delta.Y
                )
            end
            if resizing and resizeStartPos then
                local delta = input.Position - resizeStartPos
                local newW = math.clamp(
                    resizeStartSize.X.Offset + delta.X,
                    minWindowSize.X, maxWindowSize.X
                )
                local newH = math.clamp(
                    resizeStartSize.Y.Offset + delta.Y,
                    minWindowSize.Y, maxWindowSize.Y
                )
                self._win.Size = UDim2.new(0, newW, 0, newH)
            end
        end
    end))
    
    self:AddConnection("inputEnded", UserInputService.InputEnded:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1 or 
           input.UserInputType == Enum.UserInputType.Touch then
            dragging = false
            resizing = false
        end
    end))
    
    self._gui.Destroying:Connect(function()
        self:Cleanup()
    end)
    
    return self
end

-- ============================================
-- CREATE PAGE
-- ============================================
function Library:CreatePage(name, title, imageId, order)
    local page = new("Frame", {
        Parent = self._contentBg,
        Size = UDim2.new(1, -6, 1, -38),
        Position = UDim2.new(0, 3, 0, 36),
        BackgroundTransparency = 1,
        BorderSizePixel = 0,
        Visible = false,
        ClipsDescendants = true,
        ZIndex = 12
    })
    
    -- Scrollable content
    local contentContainer = new("ScrollingFrame", {
        Parent = page,
        Size = UDim2.new(1, 0, 1, 0),
        BackgroundTransparency = 1,
        BorderSizePixel = 0,
        ScrollBarThickness = 0,
        CanvasSize = UDim2.new(0, 0, 0, 0),
        AutomaticCanvasSize = Enum.AutomaticSize.Y,
        ScrollingDirection = Enum.ScrollingDirection.Y,
        ZIndex = 12
    })
    
    new("UIListLayout", {
        Parent = contentContainer, 
        Padding = UDim.new(0, 7), 
        SortOrder = Enum.SortOrder.LayoutOrder
    })
    new("UIPadding", {
        Parent = contentContainer,
        PaddingTop = UDim.new(0, 5),
        PaddingBottom = UDim.new(0, 5),
        PaddingRight = UDim.new(0, 5)
    })
    
    self.pages[name] = {frame = page, title = title, content = contentContainer}
    
    -- Nav button (32px - bigger)
    local btn = new("TextButton", {
        Parent = self._navContainer,
        Size = UDim2.new(1, 0, 0, 32),
        BackgroundColor3 = colors.bg3,
        BackgroundTransparency = 0.5,
        BorderSizePixel = 0,
        Text = "",
        AutoButtonColor = false,
        LayoutOrder = order or 999,
        ZIndex = 13
    })
    new("UICorner", {Parent = btn, CornerRadius = UDim.new(0, 8)})
    
    -- Active indicator (orange)
    local indicator = new("Frame", {
        Parent = btn,
        Size = UDim2.new(0, 3, 0, 18),
        Position = UDim2.new(0, 3, 0.5, -9),
        BackgroundColor3 = colors.primary,
        BorderSizePixel = 0,
        Visible = false,
        ZIndex = 14
    })
    new("UICorner", {Parent = indicator, CornerRadius = UDim.new(1, 0)})
    
    -- Icon
    local icon = new("ImageLabel", {
        Parent = btn,
        Image = imageId or "",
        Size = UDim2.new(0, 16, 0, 16),
        Position = UDim2.new(0, 10, 0.5, -8),
        BackgroundTransparency = 1,
        ImageColor3 = colors.textMuted,
        ZIndex = 14,
        Name = "Icon"
    })
    
    -- Label
    local label = new("TextLabel", {
        Parent = btn,
        Text = name,
        Size = UDim2.new(1, -35, 1, 0),
        Position = UDim2.new(0, 30, 0, 0),
        BackgroundTransparency = 1,
        Font = Enum.Font.GothamBold,
        TextSize = 10,
        TextColor3 = colors.textMuted,
        TextXAlignment = Enum.TextXAlignment.Left,
        TextTruncate = Enum.TextTruncate.AtEnd,
        ZIndex = 14,
        Name = "Label"
    })
    
    self._navButtons[name] = {
        btn = btn, 
        indicator = indicator, 
        icon = icon,
        label = label,
        page = page, 
        title = title
    }
    
    -- Hover effects
    btn.MouseEnter:Connect(function()
        if self._currentPage ~= name then
            tween(btn, {BackgroundTransparency = 0.2}, tweenSpeedFast)
        end
    end)
    
    btn.MouseLeave:Connect(function()
        if self._currentPage ~= name then
            tween(btn, {BackgroundTransparency = 0.5}, tweenSpeedFast)
        end
    end)
    
    btn.MouseButton1Click:Connect(function()
        self:_switchPage(name)
    end)
    
    return contentContainer
end

-- ============================================
-- SET FIRST PAGE
-- ============================================
function Library:SetFirstPage(name)
    self:_switchPage(name)
end

-- ============================================
-- PAGE SWITCHING
-- ============================================
function Library:_switchPage(pageName)
    if self._currentPage == pageName then return end
    
    for _, pageData in pairs(self.pages) do
        pageData.frame.Visible = false
    end
    
    for name, data in pairs(self._navButtons) do
        local isActive = name == pageName
        
        tween(data.btn, {
            BackgroundTransparency = isActive and 0 or 0.5
        }, tweenSpeedFast)
        
        if isActive then
            tween(data.btn, {BackgroundColor3 = colors.primary}, tweenSpeedFast)
        else
            tween(data.btn, {BackgroundColor3 = colors.bg3}, tweenSpeedFast)
        end
        
        tween(data.icon, {
            ImageColor3 = isActive and colors.text or colors.textMuted
        }, tweenSpeedFast)
        
        tween(data.label, {
            TextColor3 = isActive and colors.text or colors.textMuted
        }, tweenSpeedFast)
        
        data.indicator.Visible = isActive
    end
    
    if self.pages[pageName] then
        self.pages[pageName].frame.Visible = true
        if self._pageTitle then
            self._pageTitle.Text = self.pages[pageName].title or pageName
        end
    end
    self._currentPage = pageName
end

-- ============================================
-- CREATE CATEGORY
-- ============================================
function Library:CreateCategory(parent, title)
    local categoryFrame = new("Frame", {
        Parent = parent,
        Size = UDim2.new(1, 0, 0, 36),
        BackgroundColor3 = colors.bg2,
        BackgroundTransparency = 0.3,
        BorderSizePixel = 0,
        AutomaticSize = Enum.AutomaticSize.Y,
        ZIndex = 13
    })
    new("UICorner", {Parent = categoryFrame, CornerRadius = UDim.new(0, 8)})
    new("UIStroke", {
        Parent = categoryFrame,
        Color = colors.primary,
        Thickness = 1,
        Transparency = 0.7
    })
    
    local header = new("TextButton", {
        Parent = categoryFrame,
        Size = UDim2.new(1, 0, 0, 36),
        BackgroundTransparency = 1,
        Text = "",
        AutoButtonColor = false,
        ZIndex = 14
    })
    
    new("TextLabel", {
        Parent = header,
        Text = title,
        Size = UDim2.new(1, -45, 1, 0),
        Position = UDim2.new(0, 12, 0, 0),
        BackgroundTransparency = 1,
        Font = Enum.Font.GothamBold,
        TextSize = 11,
        TextColor3 = colors.primary,
        TextXAlignment = Enum.TextXAlignment.Left,
        ZIndex = 15
    })
    
    local arrow = new("TextLabel", {
        Parent = header,
        Text = "▼",
        Size = UDim2.new(0, 24, 1, 0),
        Position = UDim2.new(1, -30, 0, 0),
        BackgroundTransparency = 1,
        Font = Enum.Font.GothamBold,
        TextSize = 10,
        TextColor3 = colors.primary,
        ZIndex = 15
    })
    
    local contentContainer = new("Frame", {
        Parent = categoryFrame,
        Size = UDim2.new(1, -14, 0, 0),
        Position = UDim2.new(0, 7, 0, 38),
        BackgroundTransparency = 1,
        Visible = false,
        AutomaticSize = Enum.AutomaticSize.Y,
        ZIndex = 14
    })
    new("UIListLayout", {
        Parent = contentContainer, 
        Padding = UDim.new(0, 6), 
        SortOrder = Enum.SortOrder.LayoutOrder
    })
    new("UIPadding", {
        Parent = contentContainer, 
        PaddingBottom = UDim.new(0, 8)
    })
    
    local isOpen = false
    header.MouseButton1Click:Connect(function()
        isOpen = not isOpen
        contentContainer.Visible = isOpen
        tween(arrow, {Rotation = isOpen and 180 or 0}, tweenSpeedFast)
        tween(categoryFrame, {
            BackgroundColor3 = isOpen and colors.bg3 or colors.bg2,
            BackgroundTransparency = isOpen and 0.2 or 0.3
        }, tweenSpeedFast)
    end)
    
    return contentContainer
end

-- ============================================
-- CREATE TOGGLE
-- ============================================
function Library:CreateToggle(parent, label, configPath, callback, disableSave, defaultValue)
    local frame = new("Frame", {
        Parent = parent, 
        Size = UDim2.new(1, 0, 0, 30), 
        BackgroundTransparency = 1, 
        ZIndex = 14
    })
    
    new("TextLabel", {
        Parent = frame,
        Text = label,
        Size = UDim2.new(1, -50, 1, 0),
        BackgroundTransparency = 1,
        TextColor3 = colors.text,
        TextXAlignment = Enum.TextXAlignment.Left,
        Font = Enum.Font.GothamMedium,
        TextSize = 10,
        ZIndex = 15
    })
    
    local toggleBg = new("Frame", {
        Parent = frame,
        Size = UDim2.new(0, 38, 0, 20),
        Position = UDim2.new(1, -38, 0.5, -10),
        BackgroundColor3 = colors.bg4,
        BorderSizePixel = 0,
        ZIndex = 15
    })
    new("UICorner", {Parent = toggleBg, CornerRadius = UDim.new(1, 0)})
    
    local toggleCircle = new("Frame", {
        Parent = toggleBg,
        Size = UDim2.new(0, 16, 0, 16),
        Position = UDim2.new(0, 2, 0.5, -8),
        BackgroundColor3 = colors.textMuted,
        BorderSizePixel = 0,
        ZIndex = 16
    })
    new("UICorner", {Parent = toggleCircle, CornerRadius = UDim.new(1, 0)})
    
    local btn = new("TextButton", {
        Parent = toggleBg, 
        Size = UDim2.new(1, 0, 1, 0), 
        BackgroundTransparency = 1, 
        Text = "", 
        ZIndex = 17
    })
    
    local on = defaultValue or false
    if configPath and not disableSave then
        on = Library.ConfigSystem.Get(configPath, on)
    end
    
    local function updateVisual()
        tween(toggleBg, {
            BackgroundColor3 = on and colors.primary or colors.bg4
        }, tweenSpeedFast)
        
        tween(toggleCircle, {
            Position = on and UDim2.new(1, -18, 0.5, -8) or UDim2.new(0, 2, 0.5, -8),
            BackgroundColor3 = on and colors.text or colors.textMuted
        }, tweenSpeedFast)
    end
    updateVisual()
    
    btn.MouseButton1Click:Connect(function()
        on = not on
        updateVisual()
        if configPath and not disableSave then
            Library.ConfigSystem.Set(configPath, on)
            MarkDirty()
        end
        if callback then 
            pcall(callback, on)
        end
    end)
    
    if configPath and not disableSave then
        RegisterCallback(configPath, callback, "toggle", defaultValue or false)
    end
    
    self.flags[configPath or label] = on
    return frame
end

-- ============================================
-- CREATE DROPDOWN (Full Height Popup)
-- ============================================
function Library:CreateDropdown(parent, title, imageId, items, configPath, onSelect, uniqueId, defaultValue)
    local dropdownFrame = new("Frame", {
        Parent = parent,
        Size = UDim2.new(1, 0, 0, 40),
        BackgroundColor3 = colors.bg3,
        BackgroundTransparency = 0.3,
        BorderSizePixel = 0,
        ZIndex = 14,
        Name = uniqueId or "Dropdown"
    })
    new("UICorner", {Parent = dropdownFrame, CornerRadius = UDim.new(0, 8)})
    new("UIStroke", {
        Parent = dropdownFrame,
        Color = colors.primary,
        Thickness = 1,
        Transparency = 0.7
    })
    
    local header = new("TextButton", {
        Parent = dropdownFrame,
        Size = UDim2.new(1, -10, 0, 36),
        Position = UDim2.new(0, 5, 0, 2),
        BackgroundTransparency = 1,
        Text = "",
        AutoButtonColor = false,
        ZIndex = 15
    })
    
    -- Icon (optional)
    if imageId then
        new("ImageLabel", {
            Parent = header,
            Image = imageId,
            Size = UDim2.new(0, 16, 0, 16),
            Position = UDim2.new(0, 0, 0.5, -8),
            BackgroundTransparency = 1,
            ImageColor3 = colors.primary,
            ZIndex = 16
        })
    end
    
    -- Title
    new("TextLabel", {
        Parent = header,
        Text = title or "Dropdown",
        Size = UDim2.new(1, -65, 0, 14),
        Position = UDim2.new(0, imageId and 20 or 0, 0, 4),
        BackgroundTransparency = 1,
        Font = Enum.Font.GothamBold,
        TextSize = 11,
        TextColor3 = colors.primary,
        TextXAlignment = Enum.TextXAlignment.Left,
        ZIndex = 16
    })
    
    local initialSelected = configPath and Library.ConfigSystem.Get(configPath, defaultValue) or defaultValue
    local selectedItem = initialSelected
    
    -- Status label (BIGGER FONT)
    local statusLabel = new("TextLabel", {
        Parent = header,
        Text = selectedItem or "None",
        Size = UDim2.new(1, -65, 0, 12),
        Position = UDim2.new(0, imageId and 20 or 0, 0, 20),
        BackgroundTransparency = 1,
        Font = Enum.Font.Gotham,
        TextSize = 10, -- INCREASED from 8 to 10
        TextColor3 = colors.textMuted,
        TextXAlignment = Enum.TextXAlignment.Left,
        TextTruncate = Enum.TextTruncate.AtEnd,
        ZIndex = 16
    })
    
    -- Arrow
    local arrow = new("TextLabel", {
        Parent = header,
        Text = "▼",
        Size = UDim2.new(0, 24, 1, 0),
        Position = UDim2.new(1, -24, 0, 0),
        BackgroundTransparency = 1,
        Font = Enum.Font.GothamBold,
        TextSize = 10,
        TextColor3 = colors.primary,
        ZIndex = 16
    })
    
    local isOpen = false
    local popupFrame = nil
    
    local function closeDropdown()
        if popupFrame then
            tween(popupFrame, {
                Size = UDim2.new(0, popupFrame.Size.X.Offset, 0, 0)
            }, tweenSpeedFast)
            task.wait(tweenSpeedFast)
            popupFrame:Destroy()
            popupFrame = nil
        end
        isOpen = false
        self._dropdownContainer.Visible = false
        tween(arrow, {Rotation = 0}, tweenSpeedFast)
    end
    
    local function createPopup()
        if popupFrame then closeDropdown() return end
        
        self._dropdownContainer.Visible = true
        
        -- Get absolute position
        local absPos = dropdownFrame.AbsolutePosition
        local absSize = dropdownFrame.AbsoluteSize
        
        -- FULL HEIGHT DROPDOWN (matches window height)
        local windowHeight = self._win.AbsoluteSize.Y
        local maxHeight = windowHeight - absPos.Y - absSize.Y - 50 -- Leave space at bottom
        
        -- Popup container
        popupFrame = new("Frame", {
            Parent = self._dropdownContainer,
            Size = UDim2.new(0, absSize.X, 0, 0),
            Position = UDim2.new(0, absPos.X, 0, absPos.Y + absSize.Y + 4),
            BackgroundColor3 = colors.bg2,
            BackgroundTransparency = 0.1,
            BorderSizePixel = 0,
            ZIndex = 301
        })
        new("UICorner", {Parent = popupFrame, CornerRadius = UDim.new(0, 8)})
        new("UIStroke", {
            Parent = popupFrame,
            Color = colors.primary,
            Thickness = 2,
            Transparency = 0.3
        })
        
        -- Search box (BIGGER FONT)
        local searchBox = new("TextBox", {
            Parent = popupFrame,
            Size = UDim2.new(1, -10, 0, 26),
            Position = UDim2.new(0, 5, 0, 5),
            BackgroundColor3 = colors.bg4,
            BackgroundTransparency = 0.3,
            BorderSizePixel = 0,
            Text = "",
            PlaceholderText = "Search...",
            Font = Enum.Font.Gotham,
            TextSize = 10, -- INCREASED from 8 to 10
            TextColor3 = colors.text,
            PlaceholderColor3 = colors.textMuted,
            ZIndex = 302
        })
        new("UICorner", {Parent = searchBox, CornerRadius = UDim.new(0, 6)})
        new("UIPadding", {Parent = searchBox, PaddingLeft = UDim.new(0, 8)})
        
        -- List container (FULL HEIGHT)
        local listContainer = new("ScrollingFrame", {
            Parent = popupFrame,
            Size = UDim2.new(1, -10, 0, 0),
            Position = UDim2.new(0, 5, 0, 36),
            BackgroundTransparency = 1,
            BorderSizePixel = 0,
            ScrollBarThickness = 4,
            ScrollBarImageColor3 = colors.primary,
            CanvasSize = UDim2.new(0, 0, 0, 0),
            AutomaticCanvasSize = Enum.AutomaticSize.Y,
            ScrollingDirection = Enum.ScrollingDirection.Y,
            ZIndex = 302
        })
        new("UIListLayout", {Parent = listContainer, Padding = UDim.new(0, 4)})
        new("UIPadding", {Parent = listContainer, PaddingBottom = UDim.new(0, 5)})
        
        local function createItems(filter)
            for _, child in pairs(listContainer:GetChildren()) do
                if child:IsA("TextButton") then child:Destroy() end
            end
            
            local count = 0
            for _, itemName in ipairs(items) do
                if not filter or string.find(itemName:lower(), filter:lower(), 1, true) then
                    count = count + 1
                    local itemBtn = new("TextButton", {
                        Parent = listContainer,
                        Size = UDim2.new(1, 0, 0, 28), -- TALLER items
                        BackgroundColor3 = colors.bg4,
                        BackgroundTransparency = 0.4,
                        BorderSizePixel = 0,
                        Text = "",
                        AutoButtonColor = false,
                        ZIndex = 303
                    })
                    new("UICorner", {Parent = itemBtn, CornerRadius = UDim.new(0, 6)})
                    
                    local itemLabel = new("TextLabel", {
                        Parent = itemBtn,
                        Text = itemName,
                        Size = UDim2.new(1, -14, 1, 0),
                        Position = UDim2.new(0, 8, 0, 0),
                        BackgroundTransparency = 1,
                        Font = Enum.Font.GothamMedium,
                        TextSize = 10, -- INCREASED from 8 to 10
                        TextColor3 = selectedItem == itemName and colors.primary or colors.text,
                        TextXAlignment = Enum.TextXAlignment.Left,
                        TextTruncate = Enum.TextTruncate.AtEnd,
                        ZIndex = 304
                    })
                    
                    itemBtn.MouseEnter:Connect(function()
                        tween(itemBtn, {BackgroundColor3 = colors.primary, BackgroundTransparency = 0.2}, tweenSpeedFast)
                        tween(itemLabel, {TextColor3 = colors.text}, tweenSpeedFast)
                    end)
                    
                    itemBtn.MouseLeave:Connect(function()
                        tween(itemBtn, {BackgroundColor3 = colors.bg4, BackgroundTransparency = 0.4}, tweenSpeedFast)
                        tween(itemLabel, {
                            TextColor3 = selectedItem == itemName and colors.primary or colors.text
                        }, tweenSpeedFast)
                    end)
                    
                    itemBtn.MouseButton1Click:Connect(function()
                        selectedItem = itemName
                        statusLabel.Text = itemName
                        tween(statusLabel, {TextColor3 = colors.success}, tweenSpeedFast)
                        
                        if configPath then 
                            Library.ConfigSystem.Set(configPath, itemName) 
                            MarkDirty() 
                        end
                        if onSelect then 
                            pcall(onSelect, itemName)
                        end
                        
                        task.wait(0.1)
                        closeDropdown()
                    end)
                end
            end
            
            -- FULL HEIGHT calculation
            local itemHeight = 32 -- 28 + 4 padding
            local actualHeight = math.min(count * itemHeight, maxHeight - 45)
            listContainer.Size = UDim2.new(1, -10, 0, actualHeight)
            
            -- Animate popup open
            local finalHeight = actualHeight + 41
            tween(popupFrame, {
                Size = UDim2.new(0, absSize.X, 0, finalHeight)
            }, tweenSpeedFast)
        end
        
        createItems(nil)
        
        searchBox:GetPropertyChangedSignal("Text"):Connect(function()
            createItems(searchBox.Text)
        end)
        
        isOpen = true
        tween(arrow, {Rotation = 180}, tweenSpeedFast)
    end
    
    header.MouseButton1Click:Connect(function()
        if isOpen then
            closeDropdown()
        else
            createPopup()
        end
    end)
    
    -- Close on click outside
    self._dropdownContainer.InputBegan:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1 then
            closeDropdown()
        end
    end)
    
    if configPath then 
        RegisterCallback(configPath, onSelect, "dropdown", defaultValue) 
    end
    
    local dropdownObj = {
        Frame = dropdownFrame,
        Refresh = function(self, newItems)
            items = newItems
            if isOpen then 
                closeDropdown()
            end
        end
    }
    
    if uniqueId then
        self.flags[uniqueId] = dropdownObj
    end
    
    return dropdownFrame
end

-- ============================================
-- CREATE MULTI DROPDOWN (Full Height Popup)
-- ============================================
function Library:CreateMultiDropdown(parent, title, imageId, items, configPath, onSelect, uniqueId, defaultValues)
    local dropdownFrame = new("Frame", {
        Parent = parent,
        Size = UDim2.new(1, 0, 0, 40),
        BackgroundColor3 = colors.bg3,
        BackgroundTransparency = 0.3,
        BorderSizePixel = 0,
        ZIndex = 14,
        Name = uniqueId or "MultiDropdown"
    })
    new("UICorner", {Parent = dropdownFrame, CornerRadius = UDim.new(0, 8)})
    new("UIStroke", {
        Parent = dropdownFrame,
        Color = colors.primary,
        Thickness = 1,
        Transparency = 0.7
    })
    
    local header = new("TextButton", {
        Parent = dropdownFrame,
        Size = UDim2.new(1, -10, 0, 36),
        Position = UDim2.new(0, 5, 0, 2),
        BackgroundTransparency = 1,
        Text = "",
        AutoButtonColor = false,
        ZIndex = 15
    })
    
    if imageId then
        new("ImageLabel", {
            Parent = header,
            Image = imageId,
            Size = UDim2.new(0, 16, 0, 16),
            Position = UDim2.new(0, 0, 0.5, -8),
            BackgroundTransparency = 1,
            ImageColor3 = colors.primary,
            ZIndex = 16
        })
    end
    
    new("TextLabel", {
        Parent = header,
        Text = title or "Multi Select",
        Size = UDim2.new(1, -65, 0, 14),
        Position = UDim2.new(0, imageId and 20 or 0, 0, 4),
        BackgroundTransparency = 1,
        Font = Enum.Font.GothamBold,
        TextSize = 11,
        TextColor3 = colors.primary,
        TextXAlignment = Enum.TextXAlignment.Left,
        ZIndex = 16
    })
    
    local selectedItems = {}
    if configPath then
        local saved = Library.ConfigSystem.Get(configPath, defaultValues or {})
        if type(saved) == "table" then
            for _, item in ipairs(saved) do 
                selectedItems[item] = true 
            end
        end
    elseif defaultValues then
        for _, item in ipairs(defaultValues) do 
            selectedItems[item] = true 
        end
    end
    
    local statusLabel = new("TextLabel", {
        Parent = header,
        Text = "0 Selected",
        Size = UDim2.new(1, -65, 0, 12),
        Position = UDim2.new(0, imageId and 20 or 0, 0, 20),
        BackgroundTransparency = 1,
        Font = Enum.Font.Gotham,
        TextSize = 10, -- INCREASED
        TextColor3 = colors.textMuted,
        TextXAlignment = Enum.TextXAlignment.Left,
        ZIndex = 16
    })
    
    local function updateStatus()
        local count = 0
        for _ in pairs(selectedItems) do count = count + 1 end
        if count == 0 then
            statusLabel.Text = "None"
            tween(statusLabel, {TextColor3 = colors.textMuted}, tweenSpeedFast)
        else
            statusLabel.Text = count .. " Selected"
            tween(statusLabel, {TextColor3 = colors.success}, tweenSpeedFast)
        end
    end
    updateStatus()
    
    local arrow = new("TextLabel", {
        Parent = header,
        Text = "▼",
        Size = UDim2.new(0, 24, 1, 0),
        Position = UDim2.new(1, -24, 0, 0),
        BackgroundTransparency = 1,
        Font = Enum.Font.GothamBold,
        TextSize = 10,
        TextColor3 = colors.primary,
        ZIndex = 16
    })
    
    local isOpen = false
    local popupFrame = nil
    
    local function closeDropdown()
        if popupFrame then
            tween(popupFrame, {
                Size = UDim2.new(0, popupFrame.Size.X.Offset, 0, 0)
            }, tweenSpeedFast)
            task.wait(tweenSpeedFast)
            popupFrame:Destroy()
            popupFrame = nil
        end
        isOpen = false
        self._dropdownContainer.Visible = false
        tween(arrow, {Rotation = 0}, tweenSpeedFast)
    end
    
    local function createPopup()
        if popupFrame then closeDropdown() return end
        
        self._dropdownContainer.Visible = true
        
        local absPos = dropdownFrame.AbsolutePosition
        local absSize = dropdownFrame.AbsoluteSize
        
        -- FULL HEIGHT
        local windowHeight = self._win.AbsoluteSize.Y
        local maxHeight = windowHeight - absPos.Y - absSize.Y - 50
        
        popupFrame = new("Frame", {
            Parent = self._dropdownContainer,
            Size = UDim2.new(0, absSize.X, 0, 0),
            Position = UDim2.new(0, absPos.X, 0, absPos.Y + absSize.Y + 4),
            BackgroundColor3 = colors.bg2,
            BackgroundTransparency = 0.1,
            BorderSizePixel = 0,
            ZIndex = 301
        })
        new("UICorner", {Parent = popupFrame, CornerRadius = UDim.new(0, 8)})
        new("UIStroke", {
            Parent = popupFrame,
            Color = colors.primary,
            Thickness = 2,
            Transparency = 0.3
        })
        
        local searchBox = new("TextBox", {
            Parent = popupFrame,
            Size = UDim2.new(1, -10, 0, 26),
            Position = UDim2.new(0, 5, 0, 5),
            BackgroundColor3 = colors.bg4,
            BackgroundTransparency = 0.3,
            BorderSizePixel = 0,
            Text = "",
            PlaceholderText = "Search...",
            Font = Enum.Font.Gotham,
            TextSize = 10,
            TextColor3 = colors.text,
            PlaceholderColor3 = colors.textMuted,
            ZIndex = 302
        })
        new("UICorner", {Parent = searchBox, CornerRadius = UDim.new(0, 6)})
        new("UIPadding", {Parent = searchBox, PaddingLeft = UDim.new(0, 8)})
        
        local listContainer = new("ScrollingFrame", {
            Parent = popupFrame,
            Size = UDim2.new(1, -10, 0, 0),
            Position = UDim2.new(0, 5, 0, 36),
            BackgroundTransparency = 1,
            BorderSizePixel = 0,
            ScrollBarThickness = 4,
            ScrollBarImageColor3 = colors.primary,
            CanvasSize = UDim2.new(0, 0, 0, 0),
            AutomaticCanvasSize = Enum.AutomaticSize.Y,
            ScrollingDirection = Enum.ScrollingDirection.Y,
            ZIndex = 302
        })
        new("UIListLayout", {Parent = listContainer, Padding = UDim.new(0, 4)})
        new("UIPadding", {Parent = listContainer, PaddingBottom = UDim.new(0, 5)})
        
        local function createItems(filter)
            for _, child in pairs(listContainer:GetChildren()) do
                if child:IsA("TextButton") then child:Destroy() end
            end
            
            local count = 0
            for _, itemName in ipairs(items) do
                if not filter or string.find(itemName:lower(), filter:lower(), 1, true) then
                    count = count + 1
                    local isSelected = selectedItems[itemName]
                    
                    local itemBtn = new("TextButton", {
                        Parent = listContainer,
                        Size = UDim2.new(1, 0, 0, 28),
                        BackgroundColor3 = colors.bg4,
                        BackgroundTransparency = 0.4,
                        BorderSizePixel = 0,
                        Text = "",
                        AutoButtonColor = false,
                        ZIndex = 303
                    })
                    new("UICorner", {Parent = itemBtn, CornerRadius = UDim.new(0, 6)})
                    
                    -- Checkbox
                    local box = new("Frame", {
                        Parent = itemBtn,
                        Size = UDim2.new(0, 14, 0, 14),
                        Position = UDim2.new(0, 8, 0.5, -7),
                        BackgroundColor3 = isSelected and colors.primary or colors.bg2,
                        BorderSizePixel = 0,
                        ZIndex = 304
                    })
                    new("UICorner", {Parent = box, CornerRadius = UDim.new(0, 4)})
                    
                    if isSelected then
                        new("ImageLabel", {
                            Parent = box,
                            BackgroundTransparency = 1,
                            Image = "rbxassetid://6031094667",
                            Size = UDim2.new(0, 10, 0, 10),
                            Position = UDim2.new(0.5, -5, 0.5, -5),
                            ImageColor3 = colors.text,
                            ZIndex = 305
                        })
                    end
                    
                    local itemLabel = new("TextLabel", {
                        Parent = itemBtn,
                        Text = itemName,
                        Size = UDim2.new(1, -32, 1, 0),
                        Position = UDim2.new(0, 26, 0, 0),
                        BackgroundTransparency = 1,
                        Font = Enum.Font.GothamMedium,
                        TextSize = 10,
                        TextColor3 = isSelected and colors.text or colors.textSub,
                        TextXAlignment = Enum.TextXAlignment.Left,
                        TextTruncate = Enum.TextTruncate.AtEnd,
                        ZIndex = 304
                    })
                    
                    itemBtn.MouseEnter:Connect(function()
                        tween(itemBtn, {BackgroundColor3 = colors.primary, BackgroundTransparency = 0.2}, tweenSpeedFast)
                    end)
                    
                    itemBtn.MouseLeave:Connect(function()
                        tween(itemBtn, {BackgroundColor3 = colors.bg4, BackgroundTransparency = 0.4}, tweenSpeedFast)
                    end)
                    
                    itemBtn.MouseButton1Click:Connect(function()
                        if selectedItems[itemName] then
                            selectedItems[itemName] = nil
                        else
                            selectedItems[itemName] = true
                        end
                        
                        updateStatus()
                        
                        local list = {}
                        for item in pairs(selectedItems) do 
                            table.insert(list, item) 
                        end
                        
                        if configPath then 
                            Library.ConfigSystem.Set(configPath, list) 
                            MarkDirty() 
                        end
                        if onSelect then 
                            pcall(onSelect, list)
                        end
                        
                        createItems(searchBox.Text)
                    end)
                end
            end
            
            local itemHeight = 32
            local actualHeight = math.min(count * itemHeight, maxHeight - 45)
            listContainer.Size = UDim2.new(1, -10, 0, actualHeight)
            
            local finalHeight = actualHeight + 41
            tween(popupFrame, {
                Size = UDim2.new(0, absSize.X, 0, finalHeight)
            }, tweenSpeedFast)
        end
        
        createItems(nil)
        
        searchBox:GetPropertyChangedSignal("Text"):Connect(function()
            createItems(searchBox.Text)
        end)
        
        isOpen = true
        tween(arrow, {Rotation = 180}, tweenSpeedFast)
    end
    
    header.MouseButton1Click:Connect(function()
        if isOpen then
            closeDropdown()
        else
            createPopup()
        end
    end)
    
    self._dropdownContainer.InputBegan:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1 then
            closeDropdown()
        end
    end)
    
    local dropdownObj = {
        Frame = dropdownFrame,
        Refresh = function(self, newItems)
            items = newItems
            if isOpen then 
                closeDropdown()
            end
        end
    }
    
    if uniqueId then
        self.flags[uniqueId] = dropdownObj
    end
    
    return dropdownFrame
end

-- ============================================
-- CREATE INPUT
-- ============================================
function Library:CreateInput(parent, label, configPath, defaultValue, callback)
    local frame = new("Frame", {
        Parent = parent, 
        Size = UDim2.new(1, 0, 0, 32), 
        BackgroundTransparency = 1, 
        ZIndex = 14
    })
    
    new("TextLabel", {
        Parent = frame,
        Text = label,
        Size = UDim2.new(0.5, 0, 1, 0),
        BackgroundTransparency = 1,
        TextColor3 = colors.text,
        TextXAlignment = Enum.TextXAlignment.Left,
        Font = Enum.Font.GothamMedium,
        TextSize = 10,
        ZIndex = 15
    })
    
    local inputBg = new("Frame", {
        Parent = frame,
        Size = UDim2.new(0.48, 0, 0, 28),
        Position = UDim2.new(0.52, 0, 0.5, -14),
        BackgroundColor3 = colors.bg4,
        BackgroundTransparency = 0.3,
        BorderSizePixel = 0,
        ZIndex = 15
    })
    new("UICorner", {Parent = inputBg, CornerRadius = UDim.new(0, 6)})
    new("UIStroke", {
        Parent = inputBg,
        Color = colors.primary,
        Thickness = 1,
        Transparency = 0.8
    })
    
    local initialValue = Library.ConfigSystem.Get(configPath, defaultValue)
    local inputBox = new("TextBox", {
        Parent = inputBg,
        Size = UDim2.new(1, -12, 1, 0),
        Position = UDim2.new(0, 6, 0, 0),
        BackgroundTransparency = 1,
        Text = tostring(initialValue),
        PlaceholderText = "...",
        Font = Enum.Font.Gotham,
        TextSize = 10,
        TextColor3 = colors.text,
        PlaceholderColor3 = colors.textMuted,
        TextXAlignment = Enum.TextXAlignment.Center,
        ClearTextOnFocus = false,
        ZIndex = 16
    })
    
    inputBox.Focused:Connect(function()
        tween(inputBg, {BackgroundColor3 = colors.primary, BackgroundTransparency = 0.7}, tweenSpeedFast)
    end)
    
    inputBox.FocusLost:Connect(function()
        tween(inputBg, {BackgroundColor3 = colors.bg4, BackgroundTransparency = 0.3}, tweenSpeedFast)
        
        local rawValue = inputBox.Text
        local value = tonumber(rawValue) or rawValue
        
        if configPath then
            Library.ConfigSystem.Set(configPath, value)
            MarkDirty()
        end
        if callback then 
            pcall(callback, value)
        end
    end)
    
    RegisterCallback(configPath, callback, "input", defaultValue)
    return frame
end

-- ============================================
-- CREATE BUTTON
-- ============================================
function Library:CreateButton(parent, label, callback)
    local btnFrame = new("Frame", {
        Parent = parent,
        Size = UDim2.new(1, 0, 0, 32),
        BackgroundColor3 = colors.primary,
        BackgroundTransparency = 0.2,
        BorderSizePixel = 0,
        ZIndex = 14
    })
    new("UICorner", {Parent = btnFrame, CornerRadius = UDim.new(0, 8)})
    new("UIStroke", {
        Parent = btnFrame,
        Color = colors.primary,
        Thickness = 2,
        Transparency = 0
    })
    
    local button = new("TextButton", {
        Parent = btnFrame,
        Size = UDim2.new(1, 0, 1, 0),
        BackgroundTransparency = 1,
        Text = label,
        Font = Enum.Font.GothamBold,
        TextSize = 11,
        TextColor3 = colors.text,
        AutoButtonColor = false,
        ZIndex = 15
    })
    
    button.MouseEnter:Connect(function()
        tween(btnFrame, {BackgroundColor3 = colors.primaryDark, BackgroundTransparency = 0}, tweenSpeedFast)
    end)
    
    button.MouseLeave:Connect(function()
        tween(btnFrame, {BackgroundColor3 = colors.primary, BackgroundTransparency = 0.2}, tweenSpeedFast)
    end)
    
    button.MouseButton1Click:Connect(function()
        tween(btnFrame, {Size = UDim2.new(1, 0, 0, 30)}, 0.06)
        task.wait(0.06)
        tween(btnFrame, {Size = UDim2.new(1, 0, 0, 32)}, 0.06)
        pcall(callback)
    end)
    
    return btnFrame
end

-- ============================================
-- CREATE TEXTBOX
-- ============================================
function Library:CreateTextBox(parent, label, placeholder, configPath, defaultValue, callback)
    local container = new("Frame", {
        Parent = parent,
        Size = UDim2.new(1, 0, 0, 52),
        BackgroundTransparency = 1,
        BorderSizePixel = 0,
        ZIndex = 14
    })
    
    new("TextLabel", {
        Parent = container,
        Size = UDim2.new(1, 0, 0, 16),
        Position = UDim2.new(0, 0, 0, 0),
        BackgroundTransparency = 1,
        Text = label,
        Font = Enum.Font.GothamBold,
        TextSize = 10,
        TextColor3 = colors.primary,
        TextXAlignment = Enum.TextXAlignment.Left,
        ZIndex = 15
    })
    
    local initialValue = configPath and Library.ConfigSystem.Get(configPath, defaultValue) or (defaultValue or "")
    
    local textBox = new("TextBox", {
        Parent = container,
        Size = UDim2.new(1, 0, 0, 32),
        Position = UDim2.new(0, 0, 0, 18),
        BackgroundColor3 = colors.bg4,
        BackgroundTransparency = 0.3,
        BorderSizePixel = 0,
        Text = tostring(initialValue),
        PlaceholderText = placeholder or "",
        Font = Enum.Font.Gotham,
        TextSize = 10,
        TextColor3 = colors.text,
        PlaceholderColor3 = colors.textMuted,
        TextXAlignment = Enum.TextXAlignment.Left,
        TextTruncate = Enum.TextTruncate.AtEnd,
        ClearTextOnFocus = false,
        ZIndex = 15
    })
    new("UICorner", {Parent = textBox, CornerRadius = UDim.new(0, 6)})
    new("UIStroke", {
        Parent = textBox,
        Color = colors.primary,
        Thickness = 1,
        Transparency = 0.7
    })
    new("UIPadding", {
        Parent = textBox, 
        PaddingLeft = UDim.new(0, 10), 
        PaddingRight = UDim.new(0, 10)
    })
    
    textBox.Focused:Connect(function()
        tween(textBox, {BackgroundColor3 = colors.bg3, BackgroundTransparency = 0.2}, tweenSpeedFast)
    end)
    
    local lastValue = initialValue
    textBox.FocusLost:Connect(function()
        tween(textBox, {BackgroundColor3 = colors.bg4, BackgroundTransparency = 0.3}, tweenSpeedFast)
        
        local value = textBox.Text
        if value ~= lastValue then
            lastValue = value
            if configPath then
                Library.ConfigSystem.Set(configPath, value)
                MarkDirty()
            end
            if callback then 
                pcall(callback, value)
            end
        end
    end)
    
    if configPath then 
        RegisterCallback(configPath, callback, "input", defaultValue) 
    end
    
    return {
        Container = container, 
        TextBox = textBox, 
        SetValue = function(v) 
            textBox.Text = tostring(v) 
            lastValue = tostring(v) 
        end
    }
end

-- ============================================
-- INITIALIZE
-- ============================================
function Library:Initialize()
    ExecuteConfigCallbacks()
    
    Players.PlayerRemoving:Connect(function(plr)
        if plr == localPlayer then
            Library.ConfigSystem.Save()
        end
    end)
end

function Library:LoadConfig(data)
    if type(data) ~= "table" then return end
    CurrentConfig = data
    ExecuteConfigCallbacks()
    Library.ConfigSystem.Save()
end

-- ============================================
-- NOTIFICATION SYSTEM
-- ============================================
function Library:MakeNotify(config)
    config = config or {}
    local title = config.Title or "Notification"
    local desc = config.Description or ""
    local content = config.Content or ""
    local color = config.Color or colors.primary
    local delay = config.Delay or 3
    
    if not self._gui then return end
    
    local notif = new("Frame", {
        Parent = self._gui,
        Size = UDim2.new(0, 280, 0, 0),
        Position = UDim2.new(1, -290, 1, -10),
        BackgroundColor3 = colors.bg2,
        BackgroundTransparency = 0.1,
        BorderSizePixel = 0,
        ZIndex = 250
    })
    new("UICorner", {Parent = notif, CornerRadius = UDim.new(0, 10)})
    new("UIStroke", {
        Parent = notif,
        Color = color,
        Thickness = 2
    })
    
    local accent = new("Frame", {
        Parent = notif,
        Size = UDim2.new(0, 4, 1, -8),
        Position = UDim2.new(0, 4, 0, 4),
        BackgroundColor3 = color,
        BorderSizePixel = 0,
        ZIndex = 251
    })
    new("UICorner", {Parent = accent, CornerRadius = UDim.new(1, 0)})
    
    new("TextLabel", {
        Parent = notif,
        Text = title,
        Size = UDim2.new(1, -20, 0, 18),
        Position = UDim2.new(0, 14, 0, 8),
        BackgroundTransparency = 1,
        Font = Enum.Font.GothamBold,
        TextSize = 11,
        TextColor3 = color,
        TextXAlignment = Enum.TextXAlignment.Left,
        ZIndex = 251
    })
    
    new("TextLabel", {
        Parent = notif,
        Text = desc,
        Size = UDim2.new(1, -20, 0, 14),
        Position = UDim2.new(0, 14, 0, 26),
        BackgroundTransparency = 1,
        Font = Enum.Font.Gotham,
        TextSize = 10,
        TextColor3 = colors.text,
        TextXAlignment = Enum.TextXAlignment.Left,
        ZIndex = 251
    })
    
    if content ~= "" then
        new("TextLabel", {
            Parent = notif,
            Text = content,
            Size = UDim2.new(1, -20, 0, 24),
            Position = UDim2.new(0, 14, 0, 42),
            BackgroundTransparency = 1,
            Font = Enum.Font.Gotham,
            TextSize = 9,
            TextColor3 = colors.textSub,
            TextXAlignment = Enum.TextXAlignment.Left,
            TextWrapped = true,
            ZIndex = 251
        })
    end
    
    local finalHeight = content ~= "" and 72 or 48
    tween(notif, {Size = UDim2.new(0, 280, 0, finalHeight)}, tweenSpeed)
    
    task.delay(delay, function()
        if notif and notif.Parent then
            tween(notif, {
                Size = UDim2.new(0, 280, 0, 0),
                Position = UDim2.new(1, -290, 1, -10)
            }, tweenSpeed)
            task.wait(tweenSpeed)
            notif:Destroy()
        end
    end)
end

-- ============================================
-- LYNX API COMPATIBILITY
-- ============================================
function Library:Window(config)
    config = config or {}
    
    Library.ConfigSystem.Load()
    
    self:CreateWindow({
        Name = "LynxGui",
        Title = config.Title or "LynX",
        Subtitle = config.Footer or ""
    })
    
    local WindowObject = {}
    WindowObject._library = self
    WindowObject._tabs = {}
    WindowObject._tabOrder = 0
    WindowObject._initialized = false
    
    task.delay(0.5, function()
        if not WindowObject._initialized then
            WindowObject._initialized = true
            Library:Initialize()
        end
    end)
    
    function WindowObject:AddTab(tabConfig)
        tabConfig = tabConfig or {}
        local tabName = tabConfig.Name or "Tab"
        local tabIcon = tabConfig.Icon or ""
        
        local iconMap = {
            ["player"] = "rbxassetid://12120698352",
            ["web"] = "rbxassetid://137601480983962",
            ["bag"] = "rbxassetid://8601111810",
            ["shop"] = "rbxassetid://4985385964",
            ["cart"] = "rbxassetid://128874923961846",
            ["plug"] = "rbxassetid://137601480983962",
            ["settings"] = "rbxassetid://70386228443175",
            ["loop"] = "rbxassetid://122032243989747",
            ["gps"] = "rbxassetid://78381660144034",
            ["compas"] = "rbxassetid://125300760963399",
            ["gamepad"] = "rbxassetid://84173963561612",
            ["boss"] = "rbxassetid://13132186360",
            ["scroll"] = "rbxassetid://114127804740858",
            ["menu"] = "rbxassetid://6340513838",
            ["crosshair"] = "rbxassetid://12614416478",
            ["user"] = "rbxassetid://108483430622128",
            ["stat"] = "rbxassetid://12094445329",
            ["eyes"] = "rbxassetid://14321059114",
            ["sword"] = "rbxassetid://82472368671405",
            ["discord"] = "rbxassetid://94434236999817",
            ["star"] = "rbxassetid://107005941750079",
            ["skeleton"] = "rbxassetid://17313330026",
            ["payment"] = "rbxassetid://18747025078",
            ["scan"] = "rbxassetid://109869955247116",
            ["alert"] = "rbxassetid://73186275216515",
            ["question"] = "rbxassetid://17510196486",
            ["idea"] = "rbxassetid://16833255748",
            ["strom"] = "rbxassetid://13321880293",
            ["water"] = "rbxassetid://100076212630732",
            ["dcs"] = "rbxassetid://15310731934",
            ["start"] = "rbxassetid://108886429866687",
            ["next"] = "rbxassetid://12662718374",
            ["rod"] = "rbxassetid://103247953194129",
            ["fish"] = "rbxassetid://97167558235554",
            ["send"] = "rbxassetid://122775063389583",
            ["home"] = "rbxassetid://86450224791749",
        }
        
        local iconId = iconMap[tabIcon:lower()] or ""
        self._library._tabOrder = (self._library._tabOrder or 0) + 1
        
        local page = self._library:CreatePage(tabName, tabName, iconId, self._library._tabOrder)
        
        local TabObject = {}
        TabObject._page = page
        TabObject._library = self._library
        TabObject._sections = {}
        
        function TabObject:AddSection(sectionTitle, isOpen)
            sectionTitle = sectionTitle or "Section"
            
            local category = self._library:CreateCategory(self._page, sectionTitle)
            
            local SectionObject = {}
            SectionObject._container = category
            SectionObject._library = self._library
            SectionObject._layoutOrder = 0
            
            local function getNextLayoutOrder()
                SectionObject._layoutOrder = SectionObject._layoutOrder + 1
                return SectionObject._layoutOrder
            end
            
            function SectionObject:AddToggle(toggleConfig)
                toggleConfig = toggleConfig or {}
                local title = toggleConfig.Title or "Toggle"
                local default = toggleConfig.Default or false
                local callback = toggleConfig.Callback
                local noSave = toggleConfig.NoSave or false
                local configPath = noSave and nil or ("Toggles." .. title:gsub("%s+", "_"))
                
                local frame = self._library:CreateToggle(
                    self._container, title, configPath, callback, noSave, default
                )
                if frame then frame.LayoutOrder = getNextLayoutOrder() end
                
                return {
                    _value = default,
                    SetValue = function(self, val)
                        self._value = val
                        if callback then pcall(callback, val) end
                    end,
                    GetValue = function(self)
                        return self._value
                    end
                }
            end
            
            function SectionObject:AddDropdown(dropdownConfig)
                dropdownConfig = dropdownConfig or {}
                local title = dropdownConfig.Title or "Dropdown"
                local options = dropdownConfig.Options or {}
                local default = dropdownConfig.Default
                local callback = dropdownConfig.Callback
                local noSave = dropdownConfig.NoSave or false
                local isMulti = dropdownConfig.Multi or false
                local configPath = noSave and nil or (
                    (isMulti and "MultiDropdowns." or "Dropdowns.") .. title:gsub("%s+", "_")
                )
                local uniqueId = title:gsub("%s+", "_")
                
                if isMulti then
                    local frame = self._library:CreateMultiDropdown(
                        self._container, title, nil, options, configPath, callback, uniqueId
                    )
                    if frame then frame.LayoutOrder = getNextLayoutOrder() end
                    
                    return {
                        _options = options,
                        SetOptions = function(self, newOptions)
                            self._options = newOptions
                            local flagObj = Library.flags[uniqueId]
                            if flagObj and flagObj.Refresh then
                                flagObj:Refresh(newOptions)
                            end
                        end
                    }
                end
                
                if default and configPath then
                    local current = Library.ConfigSystem.Get(configPath, nil)
                    if current == nil then
                        Library.ConfigSystem.Set(configPath, default)
                    end
                end
                
                local frame = self._library:CreateDropdown(
                    self._container, title, nil, options, configPath, callback, uniqueId, default
                )
                if frame then frame.LayoutOrder = getNextLayoutOrder() end
                
                return {
                    _options = options,
                    SetOptions = function(self, newOptions)
                        self._options = newOptions
                        local flagObj = Library.flags[uniqueId]
                        if flagObj and flagObj.Refresh then
                            flagObj:Refresh(newOptions)
                        end
                    end,
                    GetOptions = function(self)
                        return self._options
                    end
                }
            end
            
            function SectionObject:AddMultiDropdown(dropdownConfig)
                dropdownConfig = dropdownConfig or {}
                local title = dropdownConfig.Title or "Multi Select"
                local options = dropdownConfig.Options or {}
                local default = dropdownConfig.Default or {}
                local callback = dropdownConfig.Callback
                local noSave = dropdownConfig.NoSave or false
                local configPath = noSave and nil or ("MultiDropdowns." .. title:gsub("%s+", "_"))
                local uniqueId = title:gsub("%s+", "_")
                
                local frame = self._library:CreateMultiDropdown(
                    self._container, title, nil, options, configPath, callback, uniqueId, default
                )
                if frame then frame.LayoutOrder = getNextLayoutOrder() end
                
                return {
                    _options = options,
                    SetOptions = function(self, newOptions)
                        self._options = newOptions
                        local flagObj = Library.flags[uniqueId]
                        if flagObj and flagObj.Refresh then
                            flagObj:Refresh(newOptions)
                        end
                    end
                }
            end
            
            function SectionObject:AddInput(inputConfig)
                inputConfig = inputConfig or {}
                local title = inputConfig.Title or "Input"
                local default = inputConfig.Default or ""
                local placeholder = inputConfig.Placeholder or ""
                local callback = inputConfig.Callback
                local noSave = inputConfig.NoSave or false
                local configPath = noSave and nil or ("Inputs." .. title:gsub("%s+", "_"))
                
                if placeholder ~= "" then
                    local textBoxObj = self._library:CreateTextBox(
                        self._container, title, placeholder, configPath, default, callback
                    )
                    if textBoxObj and textBoxObj.Container then 
                        textBoxObj.Container.LayoutOrder = getNextLayoutOrder() 
                    end
                    return {
                        SetValue = function(self, val)
                            if textBoxObj and textBoxObj.SetValue then
                                textBoxObj.SetValue(val)
                            end
                        end,
                        GetValue = function(self)
                            if textBoxObj and textBoxObj.TextBox then
                                return textBoxObj.TextBox.Text
                            end
                            return default
                        end
                    }
                else
                    local frame = self._library:CreateInput(
                        self._container, title, configPath, default, callback
                    )
                    if frame then frame.LayoutOrder = getNextLayoutOrder() end
                    return {
                        SetValue = function(self, val)
                        end
                    }
                end
            end
            
            function SectionObject:AddButton(buttonConfig)
                buttonConfig = buttonConfig or {}
                local title = buttonConfig.Title or "Button"
                local callback = buttonConfig.Callback or function() end
                
                local frame = self._library:CreateButton(self._container, title, callback)
                if frame then frame.LayoutOrder = getNextLayoutOrder() end
            end
            
            function SectionObject:AddParagraph(paragraphConfig)
                paragraphConfig = paragraphConfig or {}
                local title = paragraphConfig.Title or ""
                local content = paragraphConfig.Content or ""
                
                local frame = new("Frame", {
                    Parent = self._container,
                    Size = UDim2.new(1, 0, 0, 42),
                    BackgroundTransparency = 1,
                    ZIndex = 14,
                    LayoutOrder = getNextLayoutOrder()
                })
                
                new("TextLabel", {
                    Parent = frame,
                    Text = title,
                    Size = UDim2.new(1, 0, 0, 16),
                    Position = UDim2.new(0, 0, 0, 0),
                    BackgroundTransparency = 1,
                    Font = Enum.Font.GothamBold,
                    TextSize = 10,
                    TextColor3 = colors.primary,
                    TextXAlignment = Enum.TextXAlignment.Left,
                    ZIndex = 15
                })
                
                new("TextLabel", {
                    Parent = frame,
                    Text = content,
                    Size = UDim2.new(1, 0, 0, 22),
                    Position = UDim2.new(0, 0, 0, 18),
                    BackgroundTransparency = 1,
                    Font = Enum.Font.Gotham,
                    TextSize = 9,
                    TextColor3 = colors.textSub,
                    TextXAlignment = Enum.TextXAlignment.Left,
                    TextWrapped = true,
                    ZIndex = 15
                })
            end
            
            table.insert(self._sections, SectionObject)
            return SectionObject
        end
        
        if self._library._tabOrder == 1 then
            self._library:SetFirstPage(tabName)
        end
        
        table.insert(self._tabs, TabObject)
        return TabObject
    end
    
    return WindowObject
end

Library.Window = Library.Window

-- ============================================
-- RETURN LIBRARY
-- ============================================
return Library
