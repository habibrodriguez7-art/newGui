-- ============================================
-- LYNX GUI LIBRARY v3.0 - IMPROVED
-- Pure UI Library - Returns Library Object
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

-- ============================================
-- SERVICES (Cached once)
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
-- COLOR PALETTE (CONSISTENT & IMPROVED)
-- ============================================
local colors = {
    primary = Color3.fromRGB(255, 140, 0),
    secondary = Color3.fromRGB(147, 112, 219),
    accent = Color3.fromRGB(186, 85, 211),
    success = Color3.fromRGB(34, 197, 94),
    bg1 = Color3.fromRGB(18, 18, 18),
    bg2 = Color3.fromRGB(28, 28, 28),
    bg3 = Color3.fromRGB(38, 38, 38),
    bg4 = Color3.fromRGB(48, 48, 48),
    text = Color3.fromRGB(255, 255, 255),
    textDim = Color3.fromRGB(200, 200, 200),
    textDimmer = Color3.fromRGB(150, 150, 150),
    border = Color3.fromRGB(55, 55, 55),
}

-- Window Config (More compact)
local windowSize = UDim2.new(0, 420, 0, 280)
local minWindowSize = Vector2.new(380, 250)
local maxWindowSize = Vector2.new(800, 600)
local sidebarWidth = 120

-- Font Sizes (Consistent & Larger)
local fontSize = {
    title = 16,
    subtitle = 12,
    header = 13,
    normal = 11,
    small = 10,
}

-- ============================================
-- INSTANCE CREATOR UTILITY
-- ============================================
local function new(class, props)
    local inst = Instance.new(class)
    if props then
        for k, v in pairs(props) do
            inst[k] = v
        end
    end
    return inst
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
    for name, conn in pairs(self._connections) do
        pcall(function() conn:Disconnect() end)
    end
    for name, thread in pairs(self._spawns) do
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
            local success = Library.ConfigSystem.Save() 
            isDirty = false
        end
        saveScheduled = false
    end)
end

local function RegisterCallback(configPath, callback, componentType, defaultValue)
    if configPath then
        table.insert(CallbackRegistry, {path = configPath, callback = callback, type = componentType, default = defaultValue})
    end
end

local function ExecuteConfigCallbacks()
    for _, entry in ipairs(CallbackRegistry) do
        local value = Library.ConfigSystem.Get(entry.path, entry.default)
        if entry.callback then entry.callback(value) end
    end
end

-- ============================================
-- GLOBAL BRIDGE (For Module compatibility)
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
-- CREATE WINDOW
-- ============================================
function Library:CreateWindow(config)
    config = config or {}
    local name = config.Name or "LynxGUI"
    local title = config.Title or "LynX"
    local subtitle = config.Subtitle or ""
    
    local existingGUI = CoreGui:FindFirstChild(name)
    if existingGUI then
        existingGUI:Destroy()
        task.wait(0.1)
    end
    
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
    
    -- Main Window
    self._win = new("Frame", {
        Parent = self._gui,
        Size = windowSize,
        Position = UDim2.new(0.5, -windowSize.X.Offset/2, 0.5, -windowSize.Y.Offset/2),
        BackgroundColor3 = colors.bg1,
        BackgroundTransparency = 0.05,
        BorderSizePixel = 0,
        ClipsDescendants = false,
        ZIndex = 3
    })
    new("UICorner", {Parent = self._win, CornerRadius = UDim.new(0, 10)})
    
    -- Sidebar
    self._sidebar = new("Frame", {
        Parent = self._win,
        Size = UDim2.new(0, sidebarWidth, 1, -42),
        Position = UDim2.new(0, 0, 0, 42),
        BackgroundTransparency = 1,
        BorderSizePixel = 0,
        ClipsDescendants = true,
        ZIndex = 4
    })
    
    -- Sidebar Separator
    local sidebarLine = new("Frame", {
        Parent = self._sidebar,
        Size = UDim2.new(0, 1, 1, 0),
        Position = UDim2.new(1, 0, 0, 0),
        BackgroundColor3 = colors.border,
        BackgroundTransparency = 0.3,
        BorderSizePixel = 0,
        ZIndex = 4
    })
    
    -- Header
    local scriptHeader = new("Frame", {
        Parent = self._win,
        Size = UDim2.new(1, 0, 0, 42),
        Position = UDim2.new(0, 0, 0, 0),
        BackgroundTransparency = 1,
        BorderSizePixel = 0,
        ZIndex = 5
    })
    
    -- Header Bottom Border
    local headerLine = new("Frame", {
        Parent = scriptHeader,
        Size = UDim2.new(1, 0, 0, 1),
        Position = UDim2.new(0, 0, 1, 0),
        BackgroundColor3 = colors.border,
        BackgroundTransparency = 0.3,
        BorderSizePixel = 0,
        ZIndex = 5
    })
    
    -- Drag Handle
    local headerDragHandle = new("Frame", {
        Parent = scriptHeader,
        Size = UDim2.new(0, 35, 0, 3),
        Position = UDim2.new(0.5, -17, 0, 6),
        BackgroundColor3 = colors.primary,
        BackgroundTransparency = 0.2,
        BorderSizePixel = 0,
        ZIndex = 6
    })
    new("UICorner", {Parent = headerDragHandle, CornerRadius = UDim.new(1, 0)})
    
    -- Title
    new("TextLabel", {
        Parent = scriptHeader,
        Text = title,
        Size = UDim2.new(0, 80, 1, 0),
        Position = UDim2.new(0, 12, 0, 0),
        BackgroundTransparency = 1,
        Font = Enum.Font.GothamBold,
        TextSize = fontSize.title,
        TextColor3 = colors.primary,
        TextXAlignment = Enum.TextXAlignment.Left,
        ZIndex = 6
    })
    
    new("ImageLabel", {
        Parent = scriptHeader,
        Image = "rbxassetid://104332967321169",
        Size = UDim2.new(0, 18, 0, 18),
        Position = UDim2.new(0, 60, 0.5, -9),
        BackgroundTransparency = 1,
        ImageColor3 = colors.primary,
        ZIndex = 6
    })
    
    local separator = new("Frame", {
        Parent = scriptHeader,
        Size = UDim2.new(0, 2, 0, 22),
        Position = UDim2.new(0, 100, 0.5, -11),
        BackgroundColor3 = colors.primary,
        BackgroundTransparency = 0.2,
        BorderSizePixel = 0,
        ZIndex = 6
    })
    new("UICorner", {Parent = separator, CornerRadius = UDim.new(1, 0)})
    
    new("TextLabel", {
        Parent = scriptHeader,
        Text = subtitle,
        Size = UDim2.new(0, 200, 1, 0),
        Position = UDim2.new(0, 125, 0, 0),
        BackgroundTransparency = 1,
        Font = Enum.Font.GothamBold,
        TextSize = fontSize.small,
        TextColor3 = colors.textDim,
        TextXAlignment = Enum.TextXAlignment.Left,
        ZIndex = 6
    })
    
    -- Minimize Button
    local btnMinHeader = new("TextButton", {
        Parent = scriptHeader,
        Size = UDim2.new(0, 28, 0, 28),
        Position = UDim2.new(1, -35, 0.5, -14),
        BackgroundColor3 = colors.bg3,
        BackgroundTransparency = 0.3,
        BorderSizePixel = 0,
        Text = "─",
        Font = Enum.Font.GothamBold,
        TextSize = fontSize.subtitle,
        TextColor3 = colors.textDim,
        AutoButtonColor = false,
        ZIndex = 7
    })
    new("UICorner", {Parent = btnMinHeader, CornerRadius = UDim.new(0, 7)})
    
    -- Navigation Container
    self._navContainer = new("ScrollingFrame", {
        Parent = self._sidebar,
        Size = UDim2.new(1, -10, 1, -10),
        Position = UDim2.new(0, 5, 0, 5),
        BackgroundTransparency = 1,
        BorderSizePixel = 0,
        ScrollBarThickness = 0,
        CanvasSize = UDim2.new(0, 0, 0, 0),
        AutomaticCanvasSize = Enum.AutomaticSize.Y,
        ScrollingDirection = Enum.ScrollingDirection.Y,
        ClipsDescendants = true,
        ZIndex = 5
    })
    new("UIListLayout", {Parent = self._navContainer, Padding = UDim.new(0, 5), SortOrder = Enum.SortOrder.LayoutOrder})
    
    -- Content Area
    self._contentBg = new("Frame", {
        Parent = self._win,
        Size = UDim2.new(1, -(sidebarWidth + 8), 1, -48),
        Position = UDim2.new(0, sidebarWidth + 4, 0, 44),
        BackgroundTransparency = 1,
        BorderSizePixel = 0,
        ClipsDescendants = true,
        ZIndex = 4
    })
    
    -- Top Bar
    local topBar = new("Frame", {
        Parent = self._contentBg,
        Size = UDim2.new(1, -6, 0, 30),
        Position = UDim2.new(0, 3, 0, 3),
        BackgroundColor3 = colors.bg2,
        BackgroundTransparency = 0.4,
        BorderSizePixel = 0,
        ZIndex = 5
    })
    new("UICorner", {Parent = topBar, CornerRadius = UDim.new(0, 7)})
    
    self._pageTitle = new("TextLabel", {
        Parent = topBar,
        Text = "Dashboard",
        Size = UDim2.new(1, -16, 1, 0),
        Position = UDim2.new(0, 10, 0, 0),
        Font = Enum.Font.GothamBold,
        TextSize = fontSize.header,
        BackgroundTransparency = 1,
        TextColor3 = colors.text,
        TextXAlignment = Enum.TextXAlignment.Left,
        ZIndex = 6
    })
    
    -- Resize Handle
    local resizeHandle = new("TextButton", {
        Parent = self._win,
        Size = UDim2.new(0, 16, 0, 16),
        Position = UDim2.new(1, -16, 1, -16),
        BackgroundColor3 = colors.bg3,
        BackgroundTransparency = 0,
        BorderSizePixel = 0,
        Text = "⋰",
        Font = Enum.Font.GothamBold,
        TextSize = fontSize.small,
        TextColor3 = colors.textDim,
        AutoButtonColor = false,
        ZIndex = 100
    })
    new("UICorner", {Parent = resizeHandle, CornerRadius = UDim.new(0, 5)})
    
    -- Minimize System
    local minimized = false
    local icon = nil
    local savedIconPos = UDim2.new(0, 20, 0, 100)
    
    local function createMinimizedIcon()
        if icon then return end
        icon = new("ImageLabel", {
            Parent = self._gui,
            Size = UDim2.new(0, 50, 0, 50),
            Position = savedIconPos,
            BackgroundColor3 = colors.bg2,
            BackgroundTransparency = 0,
            BorderSizePixel = 0,
            Image = "rbxassetid://118176705805619",
            ScaleType = Enum.ScaleType.Fit,
            ZIndex = 50
        })
        new("UICorner", {Parent = icon, CornerRadius = UDim.new(0, 10)})
        
        local logoText = new("TextLabel", {
            Parent = icon,
            Text = "L",
            Size = UDim2.new(1, 0, 1, 0),
            Font = Enum.Font.GothamBold,
            TextSize = 28,
            BackgroundTransparency = 1,
            TextColor3 = colors.primary,
            Visible = icon.Image == "",
            ZIndex = 51
        })
        
        local dragging, dragStart, startPos, dragMoved = false, nil, nil, false
        
        icon.InputBegan:Connect(function(input)
            if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
                dragging, dragMoved, dragStart, startPos = true, false, input.Position, icon.Position
            end
        end)
        
        icon.InputChanged:Connect(function(input)
            if dragging and (input.UserInputType == Enum.UserInputType.MouseMovement or input.UserInputType == Enum.UserInputType.Touch) then
                local delta = input.Position - dragStart
                if math.sqrt(delta.X^2 + delta.Y^2) > 5 then dragMoved = true end
                icon.Position = UDim2.new(startPos.X.Scale, startPos.X.Offset + delta.X, startPos.Y.Scale, startPos.Y.Offset + delta.Y)
            end
        end)
        
        icon.InputEnded:Connect(function(input)
            if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
                if dragging then
                    dragging = false
                    savedIconPos = icon.Position
                    if not dragMoved then
                        bringToFront()
                        self._win.Visible = true
                        self._win.Size = windowSize
                        self._win.Position = UDim2.new(0.5, -windowSize.X.Offset/2, 0.5, -windowSize.Y.Offset/2)
                        icon:Destroy()
                        icon = nil
                        minimized = false
                    end
                end
            end
        end)
    end
    
    self:AddConnection("minimizeBtn", btnMinHeader.MouseButton1Click:Connect(function()
        if not minimized then
            self._win.Size = UDim2.new(0, 0, 0, 0)
            self._win.Position = UDim2.new(0.5, 0, 0.5, 0)
            self._win.Visible = false
            createMinimizedIcon()
            minimized = true
        end
    end))
    
    -- Dragging System
    local dragging, dragStart, startPos = false, nil, nil
    
    scriptHeader.InputBegan:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
            bringToFront()
            dragging, dragStart, startPos = true, input.Position, self._win.Position
        end
    end)
    
    -- Resizing System
    local resizing = false
    local resizeStartPos, resizeStartSize = nil, nil
    
    resizeHandle.InputBegan:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
            resizing, resizeStartPos, resizeStartSize = true, input.Position, self._win.Size
        end
    end)
    
    self:AddConnection("inputChanged", UserInputService.InputChanged:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseMovement or input.UserInputType == Enum.UserInputType.Touch then
            if dragging and startPos then
                local delta = input.Position - dragStart
                self._win.Position = UDim2.new(startPos.X.Scale, startPos.X.Offset + delta.X, startPos.Y.Scale, startPos.Y.Offset + delta.Y)
            end
            if resizing and resizeStartPos then
                local delta = input.Position - resizeStartPos
                local newWidth = math.clamp(resizeStartSize.X.Offset + delta.X, minWindowSize.X, maxWindowSize.X)
                local newHeight = math.clamp(resizeStartSize.Y.Offset + delta.Y, minWindowSize.Y, maxWindowSize.Y)
                self._win.Size = UDim2.new(0, newWidth, 0, newHeight)
            end
        end
    end))
    
    self:AddConnection("inputEnded", UserInputService.InputEnded:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
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
        Size = UDim2.new(1, -12, 1, -38),
        Position = UDim2.new(0, 6, 0, 36),
        BackgroundTransparency = 1,
        BorderSizePixel = 0,
        Visible = false,
        ClipsDescendants = true,
        ZIndex = 5
    })
    
    local contentContainer = new("ScrollingFrame", {
        Parent = page,
        Size = UDim2.new(1, 0, 1, 0),
        BackgroundTransparency = 1,
        BorderSizePixel = 0,
        ScrollBarThickness = 0,
        CanvasSize = UDim2.new(0, 0, 0, 0),
        AutomaticCanvasSize = Enum.AutomaticSize.Y,
        ScrollingDirection = Enum.ScrollingDirection.Y,
        ClipsDescendants = true,
        ZIndex = 5
    })
    
    new("UIListLayout", {Parent = contentContainer, Padding = UDim.new(0, 5), SortOrder = Enum.SortOrder.LayoutOrder})
    new("UIPadding", {Parent = contentContainer, PaddingTop = UDim.new(0, 3), PaddingBottom = UDim.new(0, 3), PaddingRight = UDim.new(0, 5)})
    
    self.pages[name] = {frame = page, title = title, content = contentContainer}
    
    -- Nav Button
    local btn = new("TextButton", {
        Parent = self._navContainer,
        Size = UDim2.new(1, 0, 0, 30),
        BackgroundColor3 = colors.bg2,
        BackgroundTransparency = 1,
        BorderSizePixel = 0,
        Text = "",
        AutoButtonColor = false,
        LayoutOrder = order or 999,
        ZIndex = 6
    })
    new("UICorner", {Parent = btn, CornerRadius = UDim.new(0, 7)})
    
    local indicator = new("Frame", {
        Parent = btn,
        Size = UDim2.new(0, 3, 0, 18),
        Position = UDim2.new(0, 0, 0.5, -9),
        BackgroundColor3 = colors.primary,
        BorderSizePixel = 0,
        Visible = false,
        ZIndex = 7
    })
    new("UICorner", {Parent = indicator, CornerRadius = UDim.new(1, 0)})
    
    new("ImageLabel", {
        Parent = btn,
        Image = imageId or "",
        Size = UDim2.new(0, 15, 0, 15),
        Position = UDim2.new(0, 8, 0.5, -7),
        BackgroundTransparency = 1,
        ImageColor3 = colors.textDim,
        ZIndex = 7,
        Name = "Icon"
    })
    
    new("TextLabel", {
        Parent = btn,
        Text = name,
        Size = UDim2.new(1, -35, 1, 0),
        Position = UDim2.new(0, 30, 0, 0),
        BackgroundTransparency = 1,
        Font = Enum.Font.GothamBold,
        TextSize = fontSize.small,
        TextColor3 = colors.textDim,
        TextXAlignment = Enum.TextXAlignment.Left,
        ZIndex = 7,
        Name = "Label"
    })
    
    self._navButtons[name] = {btn = btn, indicator = indicator, page = page, title = title}
    
    btn.MouseButton1Click:Connect(function()
        self:_switchPage(name)
    end)
    
    return contentContainer
end

-- ============================================
-- SET FIRST PAGE
-- ============================================
function Library:SetFirstPage(name, title)
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
        data.btn.BackgroundColor3 = isActive and colors.bg2 or colors.bg2
        data.btn.BackgroundTransparency = isActive and 0.3 or 1
        local icon = data.btn:FindFirstChild("Icon")
        if icon then
            icon.ImageColor3 = isActive and colors.primary or colors.textDim
        end
        local label = data.btn:FindFirstChild("Label")
        if label then
            label.TextColor3 = isActive and colors.text or colors.textDim
        end
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
        Size = UDim2.new(1, 0, 0, 34),
        BackgroundColor3 = colors.bg2,
        BackgroundTransparency = 0.4,
        BorderSizePixel = 0,
        AutomaticSize = Enum.AutomaticSize.Y,
        ZIndex = 6
    })
    new("UICorner", {Parent = categoryFrame, CornerRadius = UDim.new(0, 8)})
    
    local header = new("TextButton", {
        Parent = categoryFrame,
        Size = UDim2.new(1, 0, 0, 34),
        BackgroundTransparency = 1,
        Text = "",
        AutoButtonColor = false,
        ZIndex = 7
    })
    
    new("TextLabel", {
        Parent = header,
        Text = title,
        Size = UDim2.new(1, -40, 1, 0),
        Position = UDim2.new(0, 10, 0, 0),
        BackgroundTransparency = 1,
        Font = Enum.Font.GothamBold,
        TextSize = fontSize.normal,
        TextColor3 = colors.text,
        TextXAlignment = Enum.TextXAlignment.Left,
        ZIndex = 8
    })
    
    local arrow = new("TextLabel", {
        Parent = header,
        Text = "▼",
        Size = UDim2.new(0, 20, 1, 0),
        Position = UDim2.new(1, -25, 0, 0),
        BackgroundTransparency = 1,
        Font = Enum.Font.GothamBold,
        TextSize = fontSize.small,
        TextColor3 = colors.primary,
        ZIndex = 8
    })
    
    local contentContainer = new("Frame", {
        Parent = categoryFrame,
        Size = UDim2.new(1, -14, 0, 0),
        Position = UDim2.new(0, 7, 0, 36),
        BackgroundTransparency = 1,
        Visible = false,
        AutomaticSize = Enum.AutomaticSize.Y,
        ZIndex = 7
    })
    new("UIListLayout", {Parent = contentContainer, Padding = UDim.new(0, 5), SortOrder = Enum.SortOrder.LayoutOrder})
    new("UIPadding", {Parent = contentContainer, PaddingBottom = UDim.new(0, 7)})
    
    local isOpen = false
    header.MouseButton1Click:Connect(function()
        isOpen = not isOpen
        contentContainer.Visible = isOpen
        arrow.Rotation = isOpen and 180 or 0
        categoryFrame.BackgroundTransparency = isOpen and 0.3 or 0.4
    end)
    
    return contentContainer
end

-- ============================================
-- CREATE TOGGLE (Compact)
-- ============================================
function Library:CreateToggle(parent, label, configPath, callback, disableSave, defaultValue)
    local frame = new("Frame", {Parent = parent, Size = UDim2.new(1, 0, 0, 28), BackgroundTransparency = 1, ZIndex = 7})
    
    new("TextLabel", {
        Parent = frame,
        Text = label,
        Size = UDim2.new(1, -45, 1, 0),
        BackgroundTransparency = 1,
        TextColor3 = colors.text,
        TextXAlignment = Enum.TextXAlignment.Left,
        Font = Enum.Font.GothamBold,
        TextSize = fontSize.small,
        ZIndex = 8
    })
    
    local toggleBg = new("Frame", {
        Parent = frame,
        Size = UDim2.new(0, 34, 0, 18),
        Position = UDim2.new(1, -34, 0.5, -9),
        BackgroundColor3 = colors.bg3,
        BorderSizePixel = 0,
        ZIndex = 8
    })
    new("UICorner", {Parent = toggleBg, CornerRadius = UDim.new(1, 0)})
    
    local toggleCircle = new("Frame", {
        Parent = toggleBg,
        Size = UDim2.new(0, 14, 0, 14),
        Position = UDim2.new(0, 2, 0.5, -7),
        BackgroundColor3 = colors.textDim,
        BorderSizePixel = 0,
        ZIndex = 9
    })
    new("UICorner", {Parent = toggleCircle, CornerRadius = UDim.new(1, 0)})
    
    local btn = new("TextButton", {Parent = toggleBg, Size = UDim2.new(1, 0, 1, 0), BackgroundTransparency = 1, Text = "", ZIndex = 10})
    
    local on = defaultValue or false
    if configPath and not disableSave then
        on = Library.ConfigSystem.Get(configPath, on)
    end
    
    local function updateVisual()
        toggleBg.BackgroundColor3 = on and colors.primary or colors.bg3
        toggleCircle.Position = on and UDim2.new(1, -16, 0.5, -7) or UDim2.new(0, 2, 0.5, -7)
        toggleCircle.BackgroundColor3 = on and colors.text or colors.textDim
    end
    updateVisual()
    
    btn.MouseButton1Click:Connect(function()
        on = not on
        updateVisual()
        if configPath and not disableSave then
            Library.ConfigSystem.Set(configPath, on)
            MarkDirty()
        end
        if callback then callback(on) end
    end)
    
    if configPath and not disableSave then
        RegisterCallback(configPath, callback, "toggle", defaultValue or false)
    end
    
    self.flags[configPath or label] = on
    return frame
end

-- ============================================
-- DROPDOWN SYSTEM (Overlay Panel like ContohLib)
-- ============================================
Library._dropdownOverlay = nil
Library._dropdownPanel = nil
Library._dropdownFolder = nil
Library._dropdownPageLayout = nil
Library._dropdownCount = 0

function Library:_initDropdownSystem()
    if self._dropdownOverlay then return end
    
    -- Create overlay blur background
    self._dropdownOverlay = new("Frame", {
        Parent = self._win,
        Size = UDim2.new(1, 0, 1, -42),
        Position = UDim2.new(0, 0, 0, 42),
        BackgroundColor3 = Color3.fromRGB(0, 0, 0),
        BackgroundTransparency = 1,
        BorderSizePixel = 0,
        ClipsDescendants = true,
        Visible = false,
        ZIndex = 150,
        Name = "DropdownOverlay"
    })
    
    -- Close button (transparent, covers whole overlay)
    local closeOverlay = new("TextButton", {
        Parent = self._dropdownOverlay,
        Size = UDim2.new(1, 0, 1, 0),
        BackgroundColor3 = Color3.fromRGB(255, 255, 255),
        BackgroundTransparency = 0.999,
        BorderSizePixel = 0,
        Text = "",
        ZIndex = 151
    })
    
    -- Dropdown panel (slides in from right)
    self._dropdownPanel = new("Frame", {
        Parent = self._dropdownOverlay,
        AnchorPoint = Vector2.new(1, 0.5),
        Size = UDim2.new(0, 160, 1, -16),
        Position = UDim2.new(1, 172, 0.5, 0),
        BackgroundColor3 = colors.bg1,
        BorderSizePixel = 0,
        ClipsDescendants = true,
        ZIndex = 152,
        Name = "DropdownPanel"
    })
    new("UICorner", {Parent = self._dropdownPanel, CornerRadius = UDim.new(0, 3)})
    
    local panelStroke = new("UIStroke", {
        Parent = self._dropdownPanel,
        Color = colors.primary,
        Thickness = 2.5,
        Transparency = 0.8
    })
    
    -- Inner container
    local panelInner = new("Frame", {
        Parent = self._dropdownPanel,
        AnchorPoint = Vector2.new(0.5, 0.5),
        Size = UDim2.new(1, 1, 1, 1),
        Position = UDim2.new(0.5, 0, 0.5, 0),
        BackgroundColor3 = colors.bg1,
        BackgroundTransparency = 0.7,
        BorderSizePixel = 0,
        ZIndex = 153,
        Name = "PanelInner"
    })
    
    -- Dropdown folder (holds all dropdown pages)
    self._dropdownFolder = new("Folder", {
        Parent = panelInner,
        Name = "DropdownFolder"
    })
    
    -- Page layout for dropdown pages
    self._dropdownPageLayout = new("UIPageLayout", {
        Parent = self._dropdownFolder,
        EasingDirection = Enum.EasingDirection.InOut,
        EasingStyle = Enum.EasingStyle.Quad,
        TweenTime = 0.01,
        SortOrder = Enum.SortOrder.LayoutOrder,
        FillDirection = Enum.FillDirection.Vertical,
        Name = "DropdownPageLayout"
    })
    
    -- Close overlay action
    closeOverlay.Activated:Connect(function()
        if self._dropdownOverlay.Visible then
            self._dropdownOverlay.BackgroundTransparency = 0.999
            self._dropdownPanel.Position = UDim2.new(1, 172, 0.5, 0)
            self._dropdownOverlay.Visible = false
        end
    end)
end

function Library:_showDropdown(layoutOrder)
    self:_initDropdownSystem()
    
    if not self._dropdownOverlay.Visible then
        self._dropdownOverlay.Visible = true
        self._dropdownPageLayout:JumpToIndex(layoutOrder)
        self._dropdownOverlay.BackgroundTransparency = 1
        self._dropdownPanel.Position = UDim2.new(1, -11, 0.5, 0)
    end
end

function Library:_hideDropdown()
    if self._dropdownOverlay and self._dropdownOverlay.Visible then
        self._dropdownOverlay.BackgroundTransparency = 0.999
        self._dropdownPanel.Position = UDim2.new(1, 172, 0.5, 0)
        self._dropdownOverlay.Visible = false
    end
end

-- ============================================
-- CREATE DROPDOWN (Overlay Panel Style like ContohLib)
-- ============================================
function Library:CreateDropdown(parent, title, imageId, items, configPath, onSelect, uniqueId, defaultValue)
    self:_initDropdownSystem()
    
    local dropdownLayoutOrder = self._dropdownCount
    self._dropdownCount = self._dropdownCount + 1
    
    local dropdownFrame = new("Frame", {
        Parent = parent,
        Size = UDim2.new(1, 0, 0, 28),
        BackgroundTransparency = 1,
        BorderSizePixel = 0,
        ZIndex = 7,
        Name = uniqueId or "Dropdown"
    })
    
    local dropdownButton = new("TextButton", {
        Parent = dropdownFrame,
        Text = "",
        BackgroundTransparency = 1,
        Size = UDim2.new(1, 0, 1, 0),
        ZIndex = 8
    })
    
    local dropdownTitle = new("TextLabel", {
        Parent = dropdownFrame,
        Font = Enum.Font.GothamBold,
        Text = title or "Dropdown",
        TextColor3 = colors.text,
        TextSize = fontSize.small,
        TextXAlignment = Enum.TextXAlignment.Left,
        BackgroundTransparency = 1,
        Position = UDim2.new(0, 0, 0, 0),
        Size = UDim2.new(0.5, 0, 1, 0),
        ZIndex = 8
    })
    
    local selectFrame = new("Frame", {
        Parent = dropdownFrame,
        AnchorPoint = Vector2.new(1, 0.5),
        BackgroundColor3 = colors.bg3,
        BackgroundTransparency = 0.3,
        Position = UDim2.new(1, 0, 0.5, 0),
        Size = UDim2.new(0.48, 0, 0, 22),
        LayoutOrder = dropdownLayoutOrder,
        ZIndex = 8
    })
    new("UICorner", {Parent = selectFrame, CornerRadius = UDim.new(0, 6)})
    
    local optionLabel = new("TextLabel", {
        Parent = selectFrame,
        Font = Enum.Font.GothamBold,
        Text = "Select Option",
        TextColor3 = colors.textDim,
        TextSize = fontSize.small,
        TextXAlignment = Enum.TextXAlignment.Left,
        TextTruncate = Enum.TextTruncate.AtEnd,
        AnchorPoint = Vector2.new(0, 0.5),
        BackgroundTransparency = 1,
        Position = UDim2.new(0, 8, 0.5, 0),
        Size = UDim2.new(1, -24, 1, 0),
        ZIndex = 9
    })
    
    local optionImg = new("ImageLabel", {
        Parent = selectFrame,
        Image = "rbxassetid://6031091004",
        ImageColor3 = colors.textDim,
        AnchorPoint = Vector2.new(1, 0.5),
        BackgroundTransparency = 1,
        Position = UDim2.new(1, -4, 0.5, 0),
        Size = UDim2.new(0, 12, 0, 12),
        ZIndex = 9
    })
    
    -- Create dropdown container in folder
    local dropdownContainer = new("Frame", {
        Parent = self._dropdownFolder,
        Size = UDim2.new(1, 0, 1, 0),
        BackgroundTransparency = 1,
        LayoutOrder = dropdownLayoutOrder
    })
    
    local searchBox = new("TextBox", {
        Parent = dropdownContainer,
        PlaceholderText = "Search...",
        Font = Enum.Font.GothamBold,
        Text = "",
        TextSize = fontSize.small,
        TextColor3 = colors.text,
        PlaceholderColor3 = colors.textDimmer,
        BackgroundColor3 = colors.bg3,
        BackgroundTransparency = 0.3,
        BorderSizePixel = 0,
        Size = UDim2.new(1, -8, 0, 24),
        Position = UDim2.new(0, 4, 0, 4),
        ClearTextOnFocus = false,
        ZIndex = 154
    })
    new("UICorner", {Parent = searchBox, CornerRadius = UDim.new(0, 6)})
    new("UIPadding", {Parent = searchBox, PaddingLeft = UDim.new(0, 8)})
    
    local scrollSelect = new("ScrollingFrame", {
        Parent = dropdownContainer,
        Size = UDim2.new(1, -8, 1, -36),
        Position = UDim2.new(0, 4, 0, 32),
        ScrollBarImageTransparency = 0.5,
        ScrollBarImageColor3 = colors.border,
        BorderSizePixel = 0,
        BackgroundTransparency = 1,
        ScrollBarThickness = 3,
        CanvasSize = UDim2.new(0, 0, 0, 0),
        ZIndex = 154
    })
    
    local listLayout = new("UIListLayout", {
        Parent = scrollSelect,
        Padding = UDim.new(0, 3),
        SortOrder = Enum.SortOrder.LayoutOrder
    })
    
    listLayout:GetPropertyChangedSignal("AbsoluteContentSize"):Connect(function()
        scrollSelect.CanvasSize = UDim2.new(0, 0, 0, listLayout.AbsoluteContentSize.Y)
    end)
    
    -- Load saved value
    local configKey = configPath and configPath:gsub("%.", "_") or ("Dropdown_" .. (title or "Dropdown"))
    local savedValue = configPath and Library.ConfigSystem.Get(configPath, defaultValue) or defaultValue
    
    local DropdownFunc = { Value = savedValue, Options = items }
    
    function DropdownFunc:Clear()
        for _, child in scrollSelect:GetChildren() do
            if child.Name == "Option" then
                child:Destroy()
            end
        end
        DropdownFunc.Value = nil
        DropdownFunc.Options = {}
        optionLabel.Text = "Select Option"
    end
    
    function DropdownFunc:AddOption(option)
        local label, value
        if typeof(option) == "table" and option.Label and option.Value ~= nil then
            label = tostring(option.Label)
            value = option.Value
        else
            label = tostring(option)
            value = option
        end
        
        local optionFrame = new("Frame", {
            Parent = scrollSelect,
            BackgroundColor3 = colors.bg3,
            BackgroundTransparency = 0.5,
            Size = UDim2.new(1, 0, 0, 26),
            Name = "Option",
            ZIndex = 155
        })
        new("UICorner", {Parent = optionFrame, CornerRadius = UDim.new(0, 4)})
        
        local optionButton = new("TextButton", {
            Parent = optionFrame,
            BackgroundTransparency = 1,
            Size = UDim2.new(1, 0, 1, 0),
            Text = "",
            ZIndex = 156
        })
        
        local optText = new("TextLabel", {
            Parent = optionFrame,
            Font = Enum.Font.GothamBold,
            Text = label,
            TextSize = fontSize.small,
            TextColor3 = colors.text,
            Position = UDim2.new(0, 8, 0, 0),
            Size = UDim2.new(1, -16, 1, 0),
            BackgroundTransparency = 1,
            TextXAlignment = Enum.TextXAlignment.Left,
            TextTruncate = Enum.TextTruncate.AtEnd,
            Name = "OptionText",
            ZIndex = 156
        })
        
        optionFrame:SetAttribute("RealValue", value)
        
        local chooseFrame = new("Frame", {
            Parent = optionFrame,
            AnchorPoint = Vector2.new(0, 0.5),
            BackgroundColor3 = colors.primary,
            Position = UDim2.new(0, 2, 0.5, 0),
            Size = UDim2.new(0, 0, 0, 0),
            Name = "ChooseFrame",
            ZIndex = 156
        })
        new("UIStroke", {Parent = chooseFrame, Color = colors.primary, Thickness = 1.6, Transparency = 0.999})
        new("UICorner", {Parent = chooseFrame})
        
        optionButton.Activated:Connect(function()
            DropdownFunc.Value = value
            DropdownFunc:Set(DropdownFunc.Value)
        end)
    end
    
    function DropdownFunc:Set(Value)
        DropdownFunc.Value = Value
        
        if configPath then
            Library.ConfigSystem.Set(configPath, Value)
            MarkDirty()
        end
        
        local texts = {}
        for _, opt in scrollSelect:GetChildren() do
            if opt.Name == "Option" and opt:FindFirstChild("OptionText") then
                local v = opt:GetAttribute("RealValue")
                local selected = (DropdownFunc.Value == v)
                
                if selected then
                    opt.ChooseFrame.Size = UDim2.new(0, 1, 0, 12)
                    opt.ChooseFrame.UIStroke.Transparency = 0
                    opt.BackgroundTransparency = 0.935
                    table.insert(texts, opt.OptionText.Text)
                else
                    opt.ChooseFrame.Size = UDim2.new(0, 0, 0, 0)
                    opt.ChooseFrame.UIStroke.Transparency = 0.999
                    opt.BackgroundTransparency = 0.999
                end
            end
        end
        
        optionLabel.Text = (#texts == 0) and "Select Option" or table.concat(texts, ", ")
        
        if onSelect then
            local str = (DropdownFunc.Value ~= nil) and tostring(DropdownFunc.Value) or ""
            onSelect(str)
        end
    end
    
    function DropdownFunc:SetValue(val)
        self:Set(val)
    end
    
    function DropdownFunc:GetValue()
        return self.Value
    end
    
    function DropdownFunc:SetValues(newList, selecting)
        newList = newList or {}
        selecting = selecting or nil
        DropdownFunc:Clear()
        
        for _, opt in ipairs(newList) do
            DropdownFunc:AddOption(opt)
        end
        DropdownFunc.Options = newList
        DropdownFunc:Set(selecting)
    end
    
    function DropdownFunc:Refresh(newList)
        self:SetValues(newList, nil)
    end
    
    -- Search functionality
    searchBox:GetPropertyChangedSignal("Text"):Connect(function()
        local query = string.lower(searchBox.Text)
        for _, option in pairs(scrollSelect:GetChildren()) do
            if option.Name == "Option" and option:FindFirstChild("OptionText") then
                local text = string.lower(option.OptionText.Text)
                option.Visible = query == "" or string.find(text, query, 1, true)
            end
        end
        scrollSelect.CanvasSize = UDim2.new(0, 0, 0, listLayout.AbsoluteContentSize.Y)
    end)
    
    -- Open dropdown
    dropdownButton.Activated:Connect(function()
        self:_showDropdown(dropdownLayoutOrder)
    end)
    
    -- Initialize options
    DropdownFunc:SetValues(items, savedValue)
    
    if configPath then RegisterCallback(configPath, onSelect, "dropdown", defaultValue) end
    
    if uniqueId then
        self.flags[uniqueId] = DropdownFunc
    end
    
    return dropdownFrame
end

-- ============================================
-- CREATE MULTI DROPDOWN (Overlay Panel Style like ContohLib)
-- ============================================
function Library:CreateMultiDropdown(parent, title, imageId, items, configPath, onSelect, uniqueId, defaultValues)
    self:_initDropdownSystem()
    
    local dropdownLayoutOrder = self._dropdownCount
    self._dropdownCount = self._dropdownCount + 1
    
    local dropdownFrame = new("Frame", {
        Parent = parent,
        Size = UDim2.new(1, 0, 0, 28),
        BackgroundTransparency = 1,
        BorderSizePixel = 0,
        ZIndex = 7,
        Name = uniqueId or "MultiDropdown"
    })
    
    local dropdownButton = new("TextButton", {
        Parent = dropdownFrame,
        Text = "",
        BackgroundTransparency = 1,
        Size = UDim2.new(1, 0, 1, 0),
        ZIndex = 8
    })
    
    local dropdownTitle = new("TextLabel", {
        Parent = dropdownFrame,
        Font = Enum.Font.GothamBold,
        Text = title or "Multi Select",
        TextColor3 = colors.text,
        TextSize = fontSize.small,
        TextXAlignment = Enum.TextXAlignment.Left,
        BackgroundTransparency = 1,
        Position = UDim2.new(0, 0, 0, 0),
        Size = UDim2.new(0.5, 0, 1, 0),
        ZIndex = 8
    })
    
    local selectFrame = new("Frame", {
        Parent = dropdownFrame,
        AnchorPoint = Vector2.new(1, 0.5),
        BackgroundColor3 = colors.bg3,
        BackgroundTransparency = 0.3,
        Position = UDim2.new(1, 0, 0.5, 0),
        Size = UDim2.new(0.48, 0, 0, 22),
        LayoutOrder = dropdownLayoutOrder,
        ZIndex = 8
    })
    new("UICorner", {Parent = selectFrame, CornerRadius = UDim.new(0, 6)})
    
    local optionLabel = new("TextLabel", {
        Parent = selectFrame,
        Font = Enum.Font.GothamBold,
        Text = "Select Options",
        TextColor3 = colors.textDim,
        TextSize = fontSize.small,
        TextXAlignment = Enum.TextXAlignment.Left,
        TextTruncate = Enum.TextTruncate.AtEnd,
        AnchorPoint = Vector2.new(0, 0.5),
        BackgroundTransparency = 1,
        Position = UDim2.new(0, 8, 0.5, 0),
        Size = UDim2.new(1, -24, 1, 0),
        ZIndex = 9
    })
    
    local optionImg = new("ImageLabel", {
        Parent = selectFrame,
        Image = "rbxassetid://6031091004",
        ImageColor3 = colors.textDim,
        AnchorPoint = Vector2.new(1, 0.5),
        BackgroundTransparency = 1,
        Position = UDim2.new(1, -4, 0.5, 0),
        Size = UDim2.new(0, 12, 0, 12),
        ZIndex = 9
    })
    
    -- Create dropdown container in folder
    local dropdownContainer = new("Frame", {
        Parent = self._dropdownFolder,
        Size = UDim2.new(1, 0, 1, 0),
        BackgroundTransparency = 1,
        LayoutOrder = dropdownLayoutOrder
    })
    
    local searchBox = new("TextBox", {
        Parent = dropdownContainer,
        PlaceholderText = "Search...",
        Font = Enum.Font.GothamBold,
        Text = "",
        TextSize = fontSize.small,
        TextColor3 = colors.text,
        PlaceholderColor3 = colors.textDimmer,
        BackgroundColor3 = colors.bg3,
        BackgroundTransparency = 0.3,
        BorderSizePixel = 0,
        Size = UDim2.new(1, -8, 0, 24),
        Position = UDim2.new(0, 4, 0, 4),
        ClearTextOnFocus = false,
        ZIndex = 154
    })
    new("UICorner", {Parent = searchBox, CornerRadius = UDim.new(0, 6)})
    new("UIPadding", {Parent = searchBox, PaddingLeft = UDim.new(0, 8)})
    
    local scrollSelect = new("ScrollingFrame", {
        Parent = dropdownContainer,
        Size = UDim2.new(1, -8, 1, -36),
        Position = UDim2.new(0, 4, 0, 32),
        ScrollBarImageTransparency = 0.5,
        ScrollBarImageColor3 = colors.border,
        BorderSizePixel = 0,
        BackgroundTransparency = 1,
        ScrollBarThickness = 3,
        CanvasSize = UDim2.new(0, 0, 0, 0),
        ZIndex = 154
    })
    
    local listLayout = new("UIListLayout", {
        Parent = scrollSelect,
        Padding = UDim.new(0, 3),
        SortOrder = Enum.SortOrder.LayoutOrder
    })
    
    listLayout:GetPropertyChangedSignal("AbsoluteContentSize"):Connect(function()
        scrollSelect.CanvasSize = UDim2.new(0, 0, 0, listLayout.AbsoluteContentSize.Y)
    end)
    
    -- Load saved values
    local configKey = configPath and configPath:gsub("%.", "_") or ("MultiDropdown_" .. (title or "MultiDropdown"))
    local savedValues = configPath and Library.ConfigSystem.Get(configPath, defaultValues or {}) or (defaultValues or {})
    if type(savedValues) ~= "table" then savedValues = {} end
    
    local DropdownFunc = { Value = savedValues, Options = items }
    
    function DropdownFunc:Clear()
        for _, child in scrollSelect:GetChildren() do
            if child.Name == "Option" then
                child:Destroy()
            end
        end
        DropdownFunc.Value = {}
        DropdownFunc.Options = {}
        optionLabel.Text = "Select Options"
    end
    
    function DropdownFunc:AddOption(option)
        local label, value
        if typeof(option) == "table" and option.Label and option.Value ~= nil then
            label = tostring(option.Label)
            value = option.Value
        else
            label = tostring(option)
            value = option
        end
        
        local optionFrame = new("Frame", {
            Parent = scrollSelect,
            BackgroundColor3 = colors.bg3,
            BackgroundTransparency = 0.5,
            Size = UDim2.new(1, 0, 0, 26),
            Name = "Option",
            ZIndex = 155
        })
        new("UICorner", {Parent = optionFrame, CornerRadius = UDim.new(0, 4)})
        
        local optionButton = new("TextButton", {
            Parent = optionFrame,
            BackgroundTransparency = 1,
            Size = UDim2.new(1, 0, 1, 0),
            Text = "",
            ZIndex = 156
        })
        
        local optText = new("TextLabel", {
            Parent = optionFrame,
            Font = Enum.Font.GothamBold,
            Text = label,
            TextSize = fontSize.small,
            TextColor3 = colors.text,
            Position = UDim2.new(0, 8, 0, 0),
            Size = UDim2.new(1, -16, 1, 0),
            BackgroundTransparency = 1,
            TextXAlignment = Enum.TextXAlignment.Left,
            TextTruncate = Enum.TextTruncate.AtEnd,
            Name = "OptionText",
            ZIndex = 156
        })
        
        optionFrame:SetAttribute("RealValue", value)
        
        local chooseFrame = new("Frame", {
            Parent = optionFrame,
            AnchorPoint = Vector2.new(0, 0.5),
            BackgroundColor3 = colors.primary,
            Position = UDim2.new(0, 2, 0.5, 0),
            Size = UDim2.new(0, 0, 0, 0),
            Name = "ChooseFrame",
            ZIndex = 156
        })
        new("UIStroke", {Parent = chooseFrame, Color = colors.primary, Thickness = 1.6, Transparency = 0.999})
        new("UICorner", {Parent = chooseFrame})
        
        optionButton.Activated:Connect(function()
            if not table.find(DropdownFunc.Value, value) then
                table.insert(DropdownFunc.Value, value)
            else
                for i, v in pairs(DropdownFunc.Value) do
                    if v == value then
                        table.remove(DropdownFunc.Value, i)
                        break
                    end
                end
            end
            DropdownFunc:Set(DropdownFunc.Value)
        end)
    end
    
    function DropdownFunc:Set(Value)
        if type(Value) ~= "table" then Value = {} end
        DropdownFunc.Value = Value
        
        if configPath then
            Library.ConfigSystem.Set(configPath, Value)
            MarkDirty()
        end
        
        local texts = {}
        for _, opt in scrollSelect:GetChildren() do
            if opt.Name == "Option" and opt:FindFirstChild("OptionText") then
                local v = opt:GetAttribute("RealValue")
                local selected = table.find(DropdownFunc.Value, v)
                
                if selected then
                    opt.ChooseFrame.Size = UDim2.new(0, 1, 0, 12)
                    opt.ChooseFrame.UIStroke.Transparency = 0
                    opt.BackgroundTransparency = 0.935
                    table.insert(texts, opt.OptionText.Text)
                else
                    opt.ChooseFrame.Size = UDim2.new(0, 0, 0, 0)
                    opt.ChooseFrame.UIStroke.Transparency = 0.999
                    opt.BackgroundTransparency = 0.999
                end
            end
        end
        
        optionLabel.Text = (#texts == 0) and "Select Options" or table.concat(texts, ", ")
        
        if onSelect then
            onSelect(DropdownFunc.Value)
        end
    end
    
    function DropdownFunc:SetValue(val)
        self:Set(val)
    end
    
    function DropdownFunc:GetValue()
        return self.Value
    end
    
    function DropdownFunc:SetValues(newList, selecting)
        newList = newList or {}
        selecting = selecting or {}
        if type(selecting) ~= "table" then selecting = {} end
        DropdownFunc:Clear()
        
        for _, opt in ipairs(newList) do
            DropdownFunc:AddOption(opt)
        end
        DropdownFunc.Options = newList
        DropdownFunc:Set(selecting)
    end
    
    function DropdownFunc:Refresh(newList)
        self:SetValues(newList, {})
    end
    
    -- Search functionality
    searchBox:GetPropertyChangedSignal("Text"):Connect(function()
        local query = string.lower(searchBox.Text)
        for _, option in pairs(scrollSelect:GetChildren()) do
            if option.Name == "Option" and option:FindFirstChild("OptionText") then
                local text = string.lower(option.OptionText.Text)
                option.Visible = query == "" or string.find(text, query, 1, true)
            end
        end
        scrollSelect.CanvasSize = UDim2.new(0, 0, 0, listLayout.AbsoluteContentSize.Y)
    end)
    
    -- Open dropdown
    dropdownButton.Activated:Connect(function()
        self:_showDropdown(dropdownLayoutOrder)
    end)
    
    -- Initialize options
    DropdownFunc:SetValues(items, savedValues)
    
    if uniqueId then
        self.flags[uniqueId] = DropdownFunc
    end
    
    return dropdownFrame
end

-- ============================================
-- CREATE INPUT
-- ============================================
function Library:CreateInput(parent, label, configPath, defaultValue, callback)
    local frame = new("Frame", {Parent = parent, Size = UDim2.new(1, 0, 0, 28), BackgroundTransparency = 1, ZIndex = 7})
    
    new("TextLabel", {
        Parent = frame,
        Text = label,
        Size = UDim2.new(0.52, 0, 1, 0),
        BackgroundTransparency = 1,
        TextColor3 = colors.text,
        TextXAlignment = Enum.TextXAlignment.Left,
        Font = Enum.Font.GothamBold,
        TextSize = fontSize.small,
        ZIndex = 8
    })
    
    local inputBg = new("Frame", {
        Parent = frame,
        Size = UDim2.new(0.45, 0, 0, 26),
        Position = UDim2.new(0.55, 0, 0.5, -13),
        BackgroundColor3 = colors.bg3,
        BackgroundTransparency = 0.3,
        BorderSizePixel = 0,
        ZIndex = 8
    })
    new("UICorner", {Parent = inputBg, CornerRadius = UDim.new(0, 6)})
    
    local initialValue = Library.ConfigSystem.Get(configPath, defaultValue)
    local inputBox = new("TextBox", {
        Parent = inputBg,
        Size = UDim2.new(1, -10, 1, 0),
        Position = UDim2.new(0, 5, 0, 0),
        BackgroundTransparency = 1,
        Text = tostring(initialValue),
        PlaceholderText = "0.00",
        Font = Enum.Font.GothamBold,
        TextSize = fontSize.small,
        TextColor3 = colors.text,
        PlaceholderColor3 = colors.textDimmer,
        TextXAlignment = Enum.TextXAlignment.Center,
        ClearTextOnFocus = false,
        ZIndex = 9
    })
    
    local function resolveValue(text)
        local num = tonumber(text)
        return num or text
    end

    inputBox.FocusLost:Connect(function()
        local rawValue = inputBox.Text
        local value = resolveValue(rawValue)
        
        if configPath then
            Library.ConfigSystem.Set(configPath, value)
            MarkDirty()
        end
        if callback then callback(value) end
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
        Size = UDim2.new(1, 0, 0, 30),
        BackgroundColor3 = colors.primary,
        BackgroundTransparency = 0.15,
        BorderSizePixel = 0,
        ZIndex = 8
    })
    new("UICorner", {Parent = btnFrame, CornerRadius = UDim.new(0, 7)})
    
    local button = new("TextButton", {
        Parent = btnFrame,
        Size = UDim2.new(1, 0, 1, 0),
        BackgroundTransparency = 1,
        Text = label,
        Font = Enum.Font.GothamBold,
        TextSize = fontSize.normal,
        TextColor3 = colors.text,
        AutoButtonColor = false,
        ZIndex = 9
    })
    
    button.MouseButton1Click:Connect(function() pcall(callback) end)
    return btnFrame
end

-- ============================================
-- CREATE TEXTBOX
-- ============================================
function Library:CreateTextBox(parent, label, placeholder, configPath, defaultValue, callback)
    local container = new("Frame", {
        Parent = parent,
        Size = UDim2.new(1, 0, 0, 50),
        BackgroundTransparency = 1,
        BorderSizePixel = 0,
        ZIndex = 7
    })
    
    new("TextLabel", {
        Parent = container,
        Size = UDim2.new(1, 0, 0, 14),
        Position = UDim2.new(0, 0, 0, 0),
        BackgroundTransparency = 1,
        Text = label,
        Font = Enum.Font.GothamBold,
        TextSize = fontSize.small,
        TextColor3 = colors.text,
        TextXAlignment = Enum.TextXAlignment.Left,
        ZIndex = 8
    })
    
    local initialValue = configPath and Library.ConfigSystem.Get(configPath, defaultValue) or (defaultValue or "")
    
    local textBox = new("TextBox", {
        Parent = container,
        Size = UDim2.new(1, 0, 0, 30),
        Position = UDim2.new(0, 0, 0, 18),
        BackgroundColor3 = colors.bg3,
        BackgroundTransparency = 0.3,
        BorderSizePixel = 0,
        Text = tostring(initialValue),
        PlaceholderText = placeholder or "",
        Font = Enum.Font.Gotham,
        TextSize = fontSize.small,
        TextColor3 = colors.text,
        PlaceholderColor3 = colors.textDimmer,
        TextXAlignment = Enum.TextXAlignment.Left,
        TextTruncate = Enum.TextTruncate.AtEnd,
        ClipsDescendants = true,
        ClearTextOnFocus = false,
        ZIndex = 8
    })
    new("UICorner", {Parent = textBox, CornerRadius = UDim.new(0, 7)})
    new("UIPadding", {Parent = textBox, PaddingLeft = UDim.new(0, 8), PaddingRight = UDim.new(0, 8)})
    
    local lastValue = initialValue
    textBox.FocusLost:Connect(function()
        local value = textBox.Text
        if value ~= lastValue then
            lastValue = value
            if configPath then
                Library.ConfigSystem.Set(configPath, value)
                MarkDirty()
            end
            if callback then callback(value) end
        end
    end)
    
    if configPath then RegisterCallback(configPath, callback, "input", defaultValue) end
    
    return {Container = container, TextBox = textBox, SetValue = function(v) textBox.Text = tostring(v) lastValue = tostring(v) end}
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
        Size = UDim2.new(0, 270, 0, 65),
        Position = UDim2.new(1, -280, 1, -75),
        BackgroundColor3 = colors.bg2,
        BackgroundTransparency = 0.05,
        BorderSizePixel = 0,
        ZIndex = 200
    })
    new("UICorner", {Parent = notif, CornerRadius = UDim.new(0, 8)})
    
    local accent = new("Frame", {
        Parent = notif,
        Size = UDim2.new(0, 3, 1, -8),
        Position = UDim2.new(0, 4, 0, 4),
        BackgroundColor3 = color,
        BorderSizePixel = 0,
        ZIndex = 201
    })
    new("UICorner", {Parent = accent, CornerRadius = UDim.new(1, 0)})
    
    new("TextLabel", {
        Parent = notif,
        Text = title,
        Size = UDim2.new(1, -18, 0, 16),
        Position = UDim2.new(0, 12, 0, 5),
        BackgroundTransparency = 1,
        Font = Enum.Font.GothamBold,
        TextSize = fontSize.normal,
        TextColor3 = color,
        TextXAlignment = Enum.TextXAlignment.Left,
        ZIndex = 201
    })
    
    new("TextLabel", {
        Parent = notif,
        Text = desc,
        Size = UDim2.new(1, -18, 0, 12),
        Position = UDim2.new(0, 12, 0, 22),
        BackgroundTransparency = 1,
        Font = Enum.Font.GothamBold,
        TextSize = fontSize.small,
        TextColor3 = colors.text,
        TextXAlignment = Enum.TextXAlignment.Left,
        ZIndex = 201
    })
    
    new("TextLabel", {
        Parent = notif,
        Text = content,
        Size = UDim2.new(1, -18, 0, 22),
        Position = UDim2.new(0, 12, 0, 36),
        BackgroundTransparency = 1,
        Font = Enum.Font.Gotham,
        TextSize = fontSize.small,
        TextColor3 = colors.textDim,
        TextXAlignment = Enum.TextXAlignment.Left,
        TextWrapped = true,
        ZIndex = 201
    })
    
    task.delay(delay, function()
        if notif and notif.Parent then
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
        
        local iconId = ""
        if tabIcon and tabIcon ~= "" then
            iconId = iconMap[tabIcon:lower()] or ""
        end
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
                
                local frame = self._library:CreateToggle(self._container, title, configPath, callback, noSave, default)
                if frame then frame.LayoutOrder = getNextLayoutOrder() end
                
                local toggleObj = {
                    _value = default,
                    SetValue = function(self, val)
                        self._value = val
                        if callback then callback(val) end
                    end,
                    GetValue = function(self)
                        return self._value
                    end
                }
                return toggleObj
            end
            
            function SectionObject:AddDropdown(dropdownConfig)
                dropdownConfig = dropdownConfig or {}
                local title = dropdownConfig.Title or "Dropdown"
                local options = dropdownConfig.Options or {}
                local default = dropdownConfig.Default
                local callback = dropdownConfig.Callback
                local noSave = dropdownConfig.NoSave or false
                local isMulti = dropdownConfig.Multi or false
                local configPath = noSave and nil or ((isMulti and "MultiDropdowns." or "Dropdowns.") .. title:gsub("%s+", "_"))
                local uniqueId = title:gsub("%s+", "_")
                
                if isMulti then
                    local frame = self._library:CreateMultiDropdown(self._container, title, nil, options, configPath, callback, uniqueId)
                    if frame then frame.LayoutOrder = getNextLayoutOrder() end
                    
                    local dropdownObj = {
                        _options = options,
                        SetOptions = function(self, newOptions)
                            self._options = newOptions
                            local flagObj = Library.flags[uniqueId]
                            if flagObj and flagObj.Refresh then
                                flagObj:Refresh(newOptions)
                            end
                        end
                    }
                    return dropdownObj
                end
                
                if default and configPath then
                    local current = Library.ConfigSystem.Get(configPath, nil)
                    if current == nil then
                        Library.ConfigSystem.Set(configPath, default)
                    end
                end
                
                local frame = self._library:CreateDropdown(self._container, title, nil, options, configPath, callback, uniqueId, default)
                if frame then frame.LayoutOrder = getNextLayoutOrder() end
                
                local dropdownObj = {
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
                return dropdownObj
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
                
                local frame = self._library:CreateMultiDropdown(self._container, title, nil, options, configPath, callback, uniqueId, default)
                if frame then frame.LayoutOrder = getNextLayoutOrder() end
                
                local dropdownObj = {
                    _options = options,
                    SetOptions = function(self, newOptions)
                        self._options = newOptions
                        local flagObj = Library.flags[uniqueId]
                        if flagObj and flagObj.Refresh then
                            flagObj:Refresh(newOptions)
                        end
                    end
                }
                return dropdownObj
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
                    local textBoxObj = self._library:CreateTextBox(self._container, title, placeholder, configPath, default, callback)
                    if textBoxObj and textBoxObj.Container then textBoxObj.Container.LayoutOrder = getNextLayoutOrder() end
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
                    local frame = self._library:CreateInput(self._container, title, configPath, default, callback)
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
                    Size = UDim2.new(1, 0, 0, 0),
                    AutomaticSize = Enum.AutomaticSize.Y,
                    BackgroundTransparency = 1,
                    ZIndex = 7,
                    LayoutOrder = getNextLayoutOrder()
                })
                
                local titleLabel = new("TextLabel", {
                    Parent = frame,
                    Name = "TitleLabel",
                    Text = title,
                    Size = UDim2.new(1, 0, 0, 14),
                    Position = UDim2.new(0, 0, 0, 0),
                    BackgroundTransparency = 1,
                    Font = Enum.Font.GothamBold,
                    TextSize = fontSize.small,
                    TextColor3 = colors.text,
                    TextXAlignment = Enum.TextXAlignment.Left,
                    ZIndex = 8
                })
                
                local contentLabel = new("TextLabel", {
                    Parent = frame,
                    Name = "ContentLabel",
                    Text = content,
                    Size = UDim2.new(1, 0, 0, 0),
                    AutomaticSize = Enum.AutomaticSize.Y,
                    Position = UDim2.new(0, 0, 0, 16),
                    BackgroundTransparency = 1,
                    Font = Enum.Font.Gotham,
                    TextSize = fontSize.small,
                    TextColor3 = colors.textDim,
                    TextXAlignment = Enum.TextXAlignment.Left,
                    TextWrapped = true,
                    ZIndex = 8
                })
                
                -- Return object with update methods for real-time updates
                local paragraphObj = {
                    _frame = frame,
                    _titleLabel = titleLabel,
                    _contentLabel = contentLabel,
                    
                    SetTitle = function(self, newTitle)
                        if self._titleLabel then
                            self._titleLabel.Text = newTitle or ""
                        end
                    end,
                    
                    SetContent = function(self, newContent)
                        if self._contentLabel then
                            self._contentLabel.Text = newContent or ""
                        end
                    end,
                    
                    GetTitle = function(self)
                        return self._titleLabel and self._titleLabel.Text or ""
                    end,
                    
                    GetContent = function(self)
                        return self._contentLabel and self._contentLabel.Text or ""
                    end
                }
                
                return paragraphObj
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

return Library
