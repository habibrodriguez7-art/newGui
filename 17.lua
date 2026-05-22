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
Library._saveThread = nil
Library._initialized = false

-- ── Config state (declared early so Cleanup can safely reference them) ──
local CONFIG_FOLDER    = "LynxGUI_Configs"
local CONFIG_FILE      = CONFIG_FOLDER .. "/lynx_config.json"
local CurrentConfig    = {}
local DefaultConfig    = {}
local isDirty          = false
local CallbackRegistry = {}  -- keyed by configPath for O(1) lookup

local Players         = game:GetService("Players")
local CoreGui         = game:GetService("CoreGui")
local TweenService    = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")
local RunService      = game:GetService("RunService")
local HttpService     = game:GetService("HttpService")
local localPlayer     = Players.LocalPlayer
local colors = {
    primary = Color3.fromRGB(255, 140, 0),
    secondary = Color3.fromRGB(147, 112, 219),
    accent = Color3.fromRGB(186, 85, 211),
    success = Color3.fromRGB(34, 197, 94),
    -- Warm zinc / “zinc orange” — abu gelap dengan undertone oranye (bukan kebiruan)
    bg1 = Color3.fromRGB(14, 12, 11),
    bg2 = Color3.fromRGB(26, 23, 21),
    bg3 = Color3.fromRGB(40, 35, 31),
    bg4 = Color3.fromRGB(56, 48, 42),
    text = Color3.fromRGB(252, 249, 246),
    textDim = Color3.fromRGB(214, 206, 198),
    textDimmer = Color3.fromRGB(168, 158, 148),
    border = Color3.fromRGB(62, 54, 48),
}
local windowSize = UDim2.new(0, 420, 0, 280)
local minWindowSize = Vector2.new(380, 250)
local maxWindowSize = Vector2.new(800, 600)
local sidebarWidth = 120
local headerHeight = 34
local topBarHeight = 28
local sectionHeaderHeight = 30
local panelTransparency = 0.1
local sectionTransparency = 0.30
local fontSize = {
    title = 15,
    subtitle = 11,
    header = 12,
    normal = 11,
    small = 10,
}
local function formatRichText(text)
    if type(text) ~= "string" or text == "" then
        return ""
    end
    return (text:gsub('<font color="rgb%s*%(%s*(%d+)%s*,%s*(%d+)%s*,%s*(%d+)%s*%)">', function(r, g, b)
        r = math.clamp(math.floor(tonumber(r) or 0), 0, 255)
        g = math.clamp(math.floor(tonumber(g) or 0), 0, 255)
        b = math.clamp(math.floor(tonumber(b) or 0), 0, 255)
        return string.format('<font color="#%02X%02X%02X">', r, g, b)
    end))
end
local function new(class, props)
    local inst = Instance.new(class)
    if props then
        local fontVal = props.Font
        local fontFaceVal = props.FontFace
        for k, v in pairs(props) do
            if k ~= "Font" and k ~= "FontFace" then
                inst[k] = v
            end
        end
        if fontVal then inst.Font = fontVal end
        if fontFaceVal then inst.FontFace = fontFaceVal end
    end
    if (class == "TextLabel" or class == "TextButton" or class == "TextBox") and not props then
        inst.Font = Enum.Font.Gotham
    elseif (class == "TextLabel" or class == "TextButton" or class == "TextBox") and props then
        if props.Font == nil and props.FontFace == nil then
            inst.Font = Enum.Font.Gotham
        end
    end
    return inst
end
function Library:AddConnection(name, connection)
    if self._connections[name] then
        pcall(function() self._connections[name]:Disconnect() end)
    end
    self._connections[name] = connection
    return connection
end
-- FIX: Cleanup sekarang aman karena isDirty & CallbackRegistry sudah dideklarasikan di atas
function Library:Cleanup()
    if isDirty then
        pcall(function() Library.ConfigSystem.Save() end)
        isDirty = false
    end
    if self._connections then
        for _, conn in pairs(self._connections) do
            pcall(function() conn:Disconnect() end)
        end
        table.clear(self._connections)
    end
    if self._saveThread then
        pcall(function() task.cancel(self._saveThread) end)
        self._saveThread = nil
    end
    if CallbackRegistry then
        -- CallbackRegistry sekarang dictionary, clear semua entry
        for k in pairs(CallbackRegistry) do
            CallbackRegistry[k] = nil
        end
    end
    if self.flags then table.clear(self.flags) end
    if self.pages then table.clear(self.pages) end
    if self._navButtons then table.clear(self._navButtons) end
    self._dropdownOverlay = nil
    self._dropdownPanel = nil
    self._dropdownFolder = nil
    self._dropdownPageLayout = nil
    self._dropdownCount = 0
    if self._activeNotifs then
        for _, notif in ipairs(self._activeNotifs) do
            pcall(function()
                if notif and notif.Parent then notif:Destroy() end
            end)
        end
        table.clear(self._activeNotifs)
    end
    self._currentPage = nil
    self._initialized = false
end
-- (config state sudah dideklarasikan di atas, sebelum Cleanup)
local function DeepCopy(original, _seen)
    _seen = _seen or {}
    if type(original) ~= "table" then return original end
    if _seen[original] then return _seen[original] end
    local copy = {}
    _seen[original] = copy
    for k, v in pairs(original) do
        copy[DeepCopy(k, _seen)] = DeepCopy(v, _seen)
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
    -- FIX: return true/false yang akurat, encode dulu baru tulis
    local ok, err = pcall(function()
        EnsureFolderExists()
        local encoded = HttpService:JSONEncode(CurrentConfig)
        writefile(CONFIG_FILE, encoded)
    end)
    return ok
end
function Library.ConfigSystem.Load()
    EnsureFolderExists()
    -- FIX: selalu mulai dari copy DefaultConfig yang bersih
    CurrentConfig = DeepCopy(DefaultConfig)
    if isfile(CONFIG_FILE) then
        local ok, err = pcall(function()
            local raw = readfile(CONFIG_FILE)
            if not raw or raw == "" then return end
            local loaded = HttpService:JSONDecode(raw)
            if type(loaded) == "table" then
                MergeTables(CurrentConfig, loaded)
            end
        end)
        -- Jika file corrupt, hapus dan mulai fresh (tidak crash)
        if not ok then
            pcall(function() delfile(CONFIG_FILE) end)
            CurrentConfig = DeepCopy(DefaultConfig)
        end
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
-- FIX: MarkDirty — debounce 2 detik, tidak ada race condition
local function MarkDirty()
    if _G.AutoSaveEnabled == false then return end
    isDirty = true
    if Library._saveThread then
        pcall(function() task.cancel(Library._saveThread) end)
        Library._saveThread = nil
    end
    Library._saveThread = task.delay(2, function()
        if not isDirty then
            Library._saveThread = nil
            return
        end
        local ok = pcall(function() Library.ConfigSystem.Save() end)
        isDirty = false
        Library._saveThread = nil
    end)
end
-- FIX: CallbackRegistry sekarang dictionary keyed by configPath → O(1) lookup & update
local function RegisterCallback(configPath, callback, componentType, defaultValue, updateVisualFn)
    if not configPath then return end
    CallbackRegistry[configPath] = {
        path         = configPath,
        callback     = callback,
        type         = componentType,
        default      = defaultValue,
        updateVisual = updateVisualFn,
    }
end

local function ExecuteConfigCallbacks()
    for _, entry in pairs(CallbackRegistry) do
        local value = Library.ConfigSystem.Get(entry.path, entry.default)
        if entry.updateVisual then pcall(entry.updateVisual, value) end
        if entry.callback     then pcall(entry.callback,     value) end
    end
end
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
function Library:CreateWindow(config)
    config = config or {}
    local name = config.Name or "LynxGUI"
    local title = config.Title or "LynX"
    local subtitle = config.Subtitle or ""
    table.clear(CallbackRegistry)
    table.clear(self.flags)
    table.clear(self.pages)
    table.clear(self._navButtons)
    self._currentPage = nil
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
    self._win = new("Frame", {
        Parent = self._gui,
        Size = windowSize,
        Position = UDim2.new(0.5, -windowSize.X.Offset/2, 0.5, -windowSize.Y.Offset/2),
        BackgroundColor3 = colors.bg1,
        BackgroundTransparency = panelTransparency,
        BorderSizePixel = 0,
        ClipsDescendants = false,
        ZIndex = 3
    })
    new("UICorner", {Parent = self._win, CornerRadius = UDim.new(0, 7)})
    self._sidebar = new("Frame", {
        Parent = self._win,
        Size = UDim2.new(0, sidebarWidth, 1, -headerHeight),
        Position = UDim2.new(0, 0, 0, headerHeight),
        BackgroundTransparency = 1,
        BorderSizePixel = 0,
        ClipsDescendants = true,
        ZIndex = 4
    })
    local sidebarLine = new("Frame", {
        Parent = self._sidebar,
        Size = UDim2.new(0, 1, 1, 0),
        Position = UDim2.new(1, 0, 0, 0),
        BackgroundColor3 = colors.border,
        BackgroundTransparency = 0.42,
        BorderSizePixel = 0,
        ZIndex = 4
    })
    local scriptHeader = new("TextButton", {
        Parent = self._win,
        Size = UDim2.new(1, 0, 0, headerHeight),
        Position = UDim2.new(0, 0, 0, 0),
        BackgroundTransparency = 1,
        BorderSizePixel = 0,
        Text = "",
        AutoButtonColor = false,
        ZIndex = 5
    })
    local headerLine = new("Frame", {
        Parent = scriptHeader,
        Size = UDim2.new(1, -20, 0, 1),
        Position = UDim2.new(0, 10, 1, -1),
        BackgroundColor3 = colors.border,
        BackgroundTransparency = 0.62,
        BorderSizePixel = 0,
        ZIndex = 5
    })
    local headerDragHandle = new("Frame", {
        Parent = scriptHeader,
        Size = UDim2.new(0, 28, 0, 2),
        Position = UDim2.new(0.5, -14, 0, 4),
        BackgroundColor3 = colors.primary,
        BackgroundTransparency = 0.35,
        BorderSizePixel = 0,
        ZIndex = 6
    })
    new("UICorner", {Parent = headerDragHandle, CornerRadius = UDim.new(0, 2)})
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
        Size = UDim2.new(0, 16, 0, 16),
        Position = UDim2.new(0, 58, 0.5, -8),
        BackgroundTransparency = 1,
        ImageColor3 = colors.primary,
        ZIndex = 6
    })
    -- Separator: mulai tepat setelah icon (58 + 16 + 8 = 82px), tinggi sama dengan icon (16px)
    local separator = new("Frame", {
        Parent = scriptHeader,
        Size = UDim2.new(0, 1, 0, 16),
        Position = UDim2.new(0, 82, 0.5, -8),
        BackgroundColor3 = colors.border,
        BackgroundTransparency = 0.2,
        BorderSizePixel = 0,
        ZIndex = 6
    })
    new("UICorner", {Parent = separator, CornerRadius = UDim.new(0, 2)})
    new("TextLabel", {
        Parent = scriptHeader,
        Text = subtitle,
        Size = UDim2.new(0, 200, 1, 0),
        Position = UDim2.new(0, 96, 0, 0),  -- 82 + 1 + 13 padding = 96
        BackgroundTransparency = 1,
        Font = Enum.Font.GothamBold,
        TextSize = fontSize.small,
        TextColor3 = colors.textDim,
        TextXAlignment = Enum.TextXAlignment.Left,
        ZIndex = 6
    })
    local btnMinHeader = new("TextButton", {
        Parent = scriptHeader,
        Size = UDim2.new(0, 24, 0, 24),
        Position = UDim2.new(1, -30, 0.5, -12),
        BackgroundColor3 = colors.bg2,
        BackgroundTransparency = panelTransparency,
        BorderSizePixel = 0,
        Text = "",
        AutoButtonColor = false,
        ZIndex = 7
    })
    new("UICorner", {Parent = btnMinHeader, CornerRadius = UDim.new(0, 4)})
    local btnMinStroke = new("UIStroke", {
        Parent = btnMinHeader,
        Color = colors.border,
        Thickness = 1,
        Transparency = 0.55
    })
    local minLine = new("Frame", {
        Parent = btnMinHeader,
        Size = UDim2.new(0, 10, 0, 2),
        Position = UDim2.new(0.5, -5, 0.5, -1),
        BackgroundColor3 = colors.textDim,
        BorderSizePixel = 0,
        ZIndex = 8
    })
    new("UICorner", {Parent = minLine, CornerRadius = UDim.new(1, 0)})
    local function setMinimizeHover(hovering)
        btnMinHeader.BackgroundColor3 = hovering and colors.bg3 or colors.bg2
        btnMinHeader.BackgroundTransparency = hovering and 0.05 or panelTransparency
        minLine.BackgroundColor3 = hovering and colors.primary or colors.textDim
        btnMinStroke.Color = hovering and colors.primary or colors.border
        btnMinStroke.Transparency = hovering and 0.25 or 0.55
    end
    self:AddConnection("minimizeHoverIn", btnMinHeader.MouseEnter:Connect(function()
        setMinimizeHover(true)
    end))
    self:AddConnection("minimizeHoverOut", btnMinHeader.MouseLeave:Connect(function()
        setMinimizeHover(false)
    end))
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
    new("UIListLayout", {Parent = self._navContainer, Padding = UDim.new(0, 4), SortOrder = Enum.SortOrder.LayoutOrder})
    self._contentBg = new("Frame", {
        Parent = self._win,
        Size = UDim2.new(1, -(sidebarWidth + 6), 1, -(headerHeight + 3)),
        Position = UDim2.new(0, sidebarWidth + 3, 0, headerHeight + 1),
        BackgroundTransparency = 1,
        BorderSizePixel = 0,
        ClipsDescendants = true,
        ZIndex = 4
    })
    local topBar = new("Frame", {
        Parent = self._contentBg,
        Size = UDim2.new(1, -4, 0, topBarHeight),
        Position = UDim2.new(0, 2, 0, 2),
        BackgroundTransparency = 1,
        BorderSizePixel = 0,
        ZIndex = 5
    })
    local pageTitleAccent = new("Frame", {
        Parent = topBar,
        Size = UDim2.new(0, 3, 0, 16),
        Position = UDim2.new(0, 0, 0.5, -8),
        BackgroundColor3 = colors.primary,
        BackgroundTransparency = 0,
        BorderSizePixel = 0,
        ZIndex = 6
    })
    new("UICorner", {Parent = pageTitleAccent, CornerRadius = UDim.new(1, 0)})
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
        TextYAlignment = Enum.TextYAlignment.Center,
        ZIndex = 6
    })
    new("Frame", {
        Parent = topBar,
        Size = UDim2.new(1, -10, 0, 1),
        Position = UDim2.new(0, 5, 1, -1),
        BackgroundColor3 = colors.border,
        BackgroundTransparency = 0.7,
        BorderSizePixel = 0,
        ZIndex = 5
    })
    local resizeHandle = new("TextButton", {
        Parent = self._win,
        Size = UDim2.new(0, 18, 0, 18),
        Position = UDim2.new(1, 0, 1, 0),
        AnchorPoint = Vector2.new(1, 1),
        BackgroundTransparency = 1,
        BorderSizePixel = 0,
        Text = "",
        AutoButtonColor = false,
        ZIndex = 100
    })
    local function addResizeGripLine(offsetX, offsetY, length)
        local line = new("Frame", {
            Parent = resizeHandle,
            AnchorPoint = Vector2.new(1, 1),
            Position = UDim2.new(1, offsetX, 1, offsetY),
            Size = UDim2.new(0, length, 0, 2),
            Rotation = -45,
            BackgroundColor3 = colors.textDim,
            BackgroundTransparency = 0.35,
            BorderSizePixel = 0,
            ZIndex = 101
        })
        new("UICorner", {Parent = line, CornerRadius = UDim.new(1, 0)})
    end
    addResizeGripLine(-3, -3, 6)
    addResizeGripLine(-7, -3, 6)
    addResizeGripLine(-3, -7, 6)
    local minimized = false
    local icon = nil
    local savedIconPos = UDim2.new(0, 20, 0, 100)
    local savedWinPos = self._win.Position
    local savedWinSize = self._win.Size
    local minimizedIconSize = 40
    local function createMinimizedIcon()
        if icon then return end
        icon = new("ImageButton", {
            Parent = self._gui,
            Size = UDim2.new(0, minimizedIconSize, 0, minimizedIconSize),
            Position = savedIconPos,
            BackgroundColor3 = colors.bg2,
            BackgroundTransparency = 0,
            BorderSizePixel = 0,
            Image = "rbxassetid://118176705805619",
            ScaleType = Enum.ScaleType.Fit,
            AutoButtonColor = false,
            Active = true,
            ZIndex = 50
        })
        new("UICorner", {Parent = icon, CornerRadius = UDim.new(0, 6)})
        new("TextLabel", {
            Parent = icon,
            Text = "L",
            Size = UDim2.new(1, 0, 1, 0),
            Font = Enum.Font.GothamBold,
            TextSize = 22,
            BackgroundTransparency = 1,
            TextColor3 = colors.primary,
            Visible = icon.Image == "",
            ZIndex = 51
        })
        local iconConns = {}
        local iconDragging = false
        local iconDragStart = nil
        local iconStartPos = nil
        local iconDragMoved = false
        local dragThreshold = 6
        local function disconnectIconConns()
            for i = #iconConns, 1, -1 do
                local c = iconConns[i]
                iconConns[i] = nil
                pcall(function() c:Disconnect() end)
            end
        end
        local function restoreFromIcon()
            if not icon then return end
            bringToFront()
            self._win.Visible = true
            self._win.Size = savedWinSize
            self._win.Position = savedWinPos
            disconnectIconConns()
            icon:Destroy()
            icon = nil
            minimized = false
        end
        iconConns[#iconConns + 1] = icon.InputBegan:Connect(function(input)
            if iconDragging then return end
            if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
                iconDragging = true
                iconDragMoved = false
                iconDragStart = input.Position
                iconStartPos = icon.Position
            end
        end)
        iconConns[#iconConns + 1] = UserInputService.InputChanged:Connect(function(input)
            if not iconDragging or not icon or not icon.Parent or not iconStartPos or not iconDragStart then return end
            if input.UserInputType == Enum.UserInputType.MouseMovement or input.UserInputType == Enum.UserInputType.Touch then
                local delta = input.Position - iconDragStart
                if delta.Magnitude > dragThreshold then
                    iconDragMoved = true
                end
                icon.Position = UDim2.new(
                    iconStartPos.X.Scale, iconStartPos.X.Offset + delta.X,
                    iconStartPos.Y.Scale, iconStartPos.Y.Offset + delta.Y
                )
            end
        end)
        iconConns[#iconConns + 1] = UserInputService.InputEnded:Connect(function(input)
            if not iconDragging then return end
            if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
                iconDragging = false
                if icon and icon.Parent then
                    savedIconPos = icon.Position
                    if not iconDragMoved then
                        restoreFromIcon()
                    end
                end
            end
        end)
        icon.Destroying:Connect(disconnectIconConns)
    end
    self:AddConnection("minimizeBtn", btnMinHeader.MouseButton1Click:Connect(function()
        if not minimized then
            savedWinPos = self._win.Position
            savedWinSize = self._win.Size
            self._win.Size = UDim2.new(0, 0, 0, 0)
            self._win.Position = UDim2.new(0.5, 0, 0.5, 0)
            self._win.Visible = false
            createMinimizedIcon()
            minimized = true
        end
    end))
    local dragging, dragStart, startPos = false, nil, nil
    self:AddConnection("headerDragStart", scriptHeader.InputBegan:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
            bringToFront()
            dragging, dragStart, startPos = true, input.Position, self._win.Position
        end
    end))
    local resizing = false
    local resizeStartPos, resizeStartSize = nil, nil
    self:AddConnection("resizeDragStart", resizeHandle.InputBegan:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
            resizing, resizeStartPos, resizeStartSize = true, input.Position, self._win.Size
        end
    end))
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
function Library:CreatePage(name, title, imageId, order)
    local page = new("Frame", {
        Parent = self._contentBg,
        Size = UDim2.new(1, -12, 1, -(topBarHeight + 10)),
        Position = UDim2.new(0, 6, 0, topBarHeight + 6),
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
    new("UIListLayout", {Parent = contentContainer, Padding = UDim.new(0, 3), SortOrder = Enum.SortOrder.LayoutOrder})
    new("UIPadding", {Parent = contentContainer, PaddingTop = UDim.new(0, 2), PaddingBottom = UDim.new(0, 2), PaddingRight = UDim.new(0, 4)})
    self.pages[name] = {frame = page, title = title, content = contentContainer}
    local btn = new("TextButton", {
        Parent = self._navContainer,
        Size = UDim2.new(1, 0, 0, 28),
        BackgroundColor3 = colors.bg2,
        BackgroundTransparency = 1,
        BorderSizePixel = 0,
        Text = "",
        AutoButtonColor = false,
        LayoutOrder = order or 999,
        ZIndex = 6
    })
    new("UICorner", {Parent = btn, CornerRadius = UDim.new(0, 5)})
    local indicator = new("Frame", {
        Parent = btn,
        Size = UDim2.new(0, 3, 0, 16),
        Position = UDim2.new(0, 0, 0.5, -8),
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
        Position = UDim2.new(0, 28, 0, 0),
        BackgroundTransparency = 1,
        Font = Enum.Font.GothamBold,
        TextSize = fontSize.normal,
        TextColor3 = colors.textDim,
        TextXAlignment = Enum.TextXAlignment.Left,
        ZIndex = 7,
        Name = "Label"
    })
    self._navButtons[name] = {btn = btn, indicator = indicator, page = page, title = title}
    self:AddConnection("navBtn_" .. name, btn.MouseButton1Click:Connect(function()
        self:_switchPage(name)
    end))
    return contentContainer
end
function Library:SetFirstPage(name, title)
    self:_switchPage(name)
end
function Library:_switchPage(pageName)
    if self._currentPage == pageName then return end
    for _, pageData in pairs(self.pages) do
        pageData.frame.Visible = false
    end
    for name, data in pairs(self._navButtons) do
        local isActive = name == pageName
        -- Active: bg4 solid (paling terang di sidebar), inactive: transparan penuh
        data.btn.BackgroundColor3 = isActive and colors.bg4 or colors.bg2
        data.btn.BackgroundTransparency = isActive and 0 or 1
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
function Library:CreateCategory(parent, title, startOpen)
    startOpen = startOpen == true
    local categoryFrame = new("Frame", {
        Parent = parent,
        Size = UDim2.new(1, 0, 0, sectionHeaderHeight),
        BackgroundColor3 = colors.bg2,
        BackgroundTransparency = sectionTransparency,
        BorderSizePixel = 0,
        AutomaticSize = Enum.AutomaticSize.Y,
        ClipsDescendants = true,
        ZIndex = 6
    })
    new("UICorner", {Parent = categoryFrame, CornerRadius = UDim.new(0, 4)})
    new("UIListLayout", {
        Parent = categoryFrame,
        Padding = UDim.new(0, 0),
        SortOrder = Enum.SortOrder.LayoutOrder
    })
    local header = new("TextButton", {
        Parent = categoryFrame,
        Size = UDim2.new(1, 0, 0, sectionHeaderHeight),
        LayoutOrder = 1,
        BackgroundTransparency = 1,
        Text = "",
        AutoButtonColor = false,
        ZIndex = 7
    })
    new("TextLabel", {
        Parent = header,
        Text = title,
        Size = UDim2.new(1, -32, 1, 0),
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
        Size = UDim2.new(0, 18, 1, 0),
        Position = UDim2.new(1, -24, 0, 0),
        BackgroundTransparency = 1,
        Font = Enum.Font.GothamBold,
        TextSize = fontSize.small,
        TextColor3 = colors.primary,
        ZIndex = 8
    })
    local contentContainer = new("Frame", {
        Parent = categoryFrame,
        Size = UDim2.new(1, 0, 0, 0),
        LayoutOrder = 2,
        BackgroundTransparency = 1,
        Visible = startOpen,
        AutomaticSize = Enum.AutomaticSize.Y,
        ZIndex = 7
    })
    new("UIPadding", {
        Parent = contentContainer,
        PaddingLeft = UDim.new(0, 10),
        PaddingRight = UDim.new(0, 10),
        PaddingBottom = UDim.new(0, 6)
    })
    new("UIListLayout", {Parent = contentContainer, Padding = UDim.new(0, 3), SortOrder = Enum.SortOrder.LayoutOrder})
    local isOpen = startOpen
    arrow.Rotation = startOpen and 180 or 0
    -- Pakai connection langsung tanpa AddConnection agar tidak ada key collision antar category
    header.MouseButton1Click:Connect(function()
        isOpen = not isOpen
        contentContainer.Visible = isOpen
        arrow.Rotation = isOpen and 180 or 0
    end)
    return contentContainer
end
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
    self:AddConnection("toggle_" .. label .. tostring(btn), btn.MouseButton1Click:Connect(function()
        on = not on
        updateVisual()
        if configPath and not disableSave then
            Library.ConfigSystem.Set(configPath, on)
            MarkDirty()
        end
        self.flags[configPath or label] = on
        if callback then callback(on) end
    end))
    if configPath and not disableSave then
        RegisterCallback(configPath, callback, "toggle", defaultValue or false, function(val)
            on = val
            updateVisual()
            self.flags[configPath or label] = on
        end)
    end
    self.flags[configPath or label] = on
    local toggleController = {
        frame = frame,
        set = function(val)
            on = val
            updateVisual()
            if configPath and not disableSave then
                Library.ConfigSystem.Set(configPath, on)
                MarkDirty()
            end
            Library.flags[configPath or label] = on
        end,
        get = function() return on end
    }
    return toggleController
end
Library._dropdownOverlay = nil
Library._dropdownPanel = nil
Library._dropdownFolder = nil
Library._dropdownPageLayout = nil
Library._dropdownCount = 0
function Library:_initDropdownSystem()
    if self._dropdownOverlay then return end
    self._dropdownOverlay = new("Frame", {
        Parent = self._win,
        Size = UDim2.new(1, 0, 1, -headerHeight),
        Position = UDim2.new(0, 0, 0, headerHeight),
        BackgroundColor3 = colors.bg1,
        BackgroundTransparency = 1,
        BorderSizePixel = 0,
        ClipsDescendants = true,
        Visible = false,
        ZIndex = 150,
        Name = "DropdownOverlay"
    })
    local closeOverlay = new("TextButton", {
        Parent = self._dropdownOverlay,
        Size = UDim2.new(1, 0, 1, 0),
        BackgroundColor3 = Color3.fromRGB(255, 255, 255),
        BackgroundTransparency = 0.999,
        BorderSizePixel = 0,
        Text = "",
        ZIndex = 151
    })
    self._dropdownPanel = new("Frame", {
        Parent = self._dropdownOverlay,
        AnchorPoint = Vector2.new(1, 0.5),
        Size = UDim2.new(0, 160, 1, -16),
        Position = UDim2.new(1, 172, 0.5, 0),
        BackgroundColor3 = colors.bg2,
        BackgroundTransparency = sectionTransparency,
        BorderSizePixel = 0,
        ClipsDescendants = true,
        ZIndex = 152,
        Name = "DropdownPanel"
    })
    new("UICorner", {Parent = self._dropdownPanel, CornerRadius = UDim.new(0, 6)})
    new("UIStroke", {
        Parent = self._dropdownPanel,
        Color = colors.border,
        Thickness = 1,
        Transparency = 0.45
    })
    local panelInner = new("Frame", {
        Parent = self._dropdownPanel,
        AnchorPoint = Vector2.new(0.5, 0.5),
        Size = UDim2.new(1, -2, 1, -2),
        Position = UDim2.new(0.5, 0, 0.5, 0),
        BackgroundColor3 = colors.bg2,
        BackgroundTransparency = sectionTransparency,
        BorderSizePixel = 0,
        ZIndex = 153,
        Name = "PanelInner"
    })
    new("UICorner", {Parent = panelInner, CornerRadius = UDim.new(0, 5)})
    self._dropdownFolder = new("Folder", {
        Parent = panelInner,
        Name = "DropdownFolder"
    })
    self._dropdownPageLayout = new("UIPageLayout", {
        Parent = self._dropdownFolder,
        EasingDirection = Enum.EasingDirection.InOut,
        EasingStyle = Enum.EasingStyle.Quad,
        TweenTime = 0.01,
        SortOrder = Enum.SortOrder.LayoutOrder,
        FillDirection = Enum.FillDirection.Vertical,
        Name = "DropdownPageLayout"
    })
    self:AddConnection("dropdownOverlayClose", closeOverlay.Activated:Connect(function()
        if self._dropdownOverlay.Visible then
            self._dropdownOverlay.BackgroundTransparency = 0.999
            self._dropdownPanel.Position = UDim2.new(1, 172, 0.5, 0)
            self._dropdownOverlay.Visible = false
        end
    end))
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
        BackgroundColor3 = colors.bg2,
        BackgroundTransparency = sectionTransparency,
        Position = UDim2.new(1, 0, 0.5, 0),
        Size = UDim2.new(0.48, 0, 0, 22),
        LayoutOrder = dropdownLayoutOrder,
        ZIndex = 8
    })
    new("UICorner", {Parent = selectFrame, CornerRadius = UDim.new(0, 4)})
    new("UIStroke", {Parent = selectFrame, Color = colors.border, Thickness = 1, Transparency = 0.5})
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
        ImageColor3 = colors.primary,
        AnchorPoint = Vector2.new(1, 0.5),
        BackgroundTransparency = 1,
        Position = UDim2.new(1, -6, 0.5, 0),
        Size = UDim2.new(0, 11, 0, 11),
        ZIndex = 9
    })
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
        BackgroundColor3 = colors.bg2,
        BackgroundTransparency = sectionTransparency,
        BorderSizePixel = 0,
        Size = UDim2.new(1, -8, 0, 24),
        Position = UDim2.new(0, 4, 0, 4),
        ClearTextOnFocus = false,
        ZIndex = 154
    })
    new("UICorner", {Parent = searchBox, CornerRadius = UDim.new(0, 4)})
    new("UIStroke", {Parent = searchBox, Color = colors.border, Thickness = 1, Transparency = 0.5})
    new("UIPadding", {Parent = searchBox, PaddingLeft = UDim.new(0, 8)})
    local scrollSelect = new("ScrollingFrame", {
        Parent = dropdownContainer,
        Size = UDim2.new(1, -8, 1, -36),
        Position = UDim2.new(0, 4, 0, 32),
        ScrollBarImageTransparency = 0.35,
        ScrollBarImageColor3 = colors.primary,
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
    self:AddConnection("dropdownLayout_" .. dropdownLayoutOrder, listLayout:GetPropertyChangedSignal("AbsoluteContentSize"):Connect(function()
        scrollSelect.CanvasSize = UDim2.new(0, 0, 0, listLayout.AbsoluteContentSize.Y)
    end))
    local savedValue = configPath and Library.ConfigSystem.Get(configPath, defaultValue) or defaultValue
    local DropdownFunc = { Value = savedValue, Options = items }
    local optionFrameCache = {}
    local optionConns = {}
    local searchThread = nil
    local buildThread = nil
    local isBuilt = false
    local function disconnectOptionConns()
        for i = #optionConns, 1, -1 do
            local c = optionConns[i]
            optionConns[i] = nil
            pcall(function() c:Disconnect() end)
        end
    end
    local function clearOptionFrames()
        if buildThread then
            pcall(function() task.cancel(buildThread) end)
            buildThread = nil
        end
        disconnectOptionConns()
        for _, child in scrollSelect:GetChildren() do
            if child.Name == "Option" then
                child:Destroy()
            end
        end
        table.clear(optionFrameCache)
        isBuilt = false
    end
    local function refreshSelectionVisuals()
        local texts = {}
        for _, entry in ipairs(optionFrameCache) do
            local opt = entry.frame
            if opt and opt.Parent then
                local v = opt:GetAttribute("RealValue")
                local selected = (DropdownFunc.Value == v)
                if selected then
                    opt.ChooseFrame.Size = UDim2.new(0, 3, 0, 16)
                    opt.ChooseFrame.UIStroke.Transparency = 0.35
                    opt.BackgroundColor3 = colors.bg3
                    opt.BackgroundTransparency = panelTransparency
                    opt.OptionText.TextColor3 = colors.text
                    table.insert(texts, opt.OptionText.Text)
                else
                    opt.ChooseFrame.Size = UDim2.new(0, 0, 0, 0)
                    opt.ChooseFrame.UIStroke.Transparency = 1
                    opt.BackgroundColor3 = colors.bg2
                    opt.BackgroundTransparency = 0.5
                    opt.OptionText.TextColor3 = colors.textDim
                end
            end
        end
        optionLabel.Text = (#texts == 0) and "Select Option" or table.concat(texts, ", ")
    end
    local function ensureBuilt()
        if isBuilt then return end
        clearOptionFrames()
        local list = DropdownFunc.Options or {}
        buildThread = task.spawn(function()
            local chunk = 50
            for i, opt in ipairs(list) do
                DropdownFunc:AddOption(opt)
                if i % chunk == 0 then
                    task.wait()
                end
            end
            isBuilt = true
            buildThread = nil
            refreshSelectionVisuals()
        end)
    end
    function DropdownFunc:Clear()
        clearOptionFrames()
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
            BackgroundColor3 = colors.bg2,
            BackgroundTransparency = 0.5,
            Size = UDim2.new(1, 0, 0, 26),
            Name = "Option",
            ZIndex = 155
        })
        new("UICorner", {Parent = optionFrame, CornerRadius = UDim.new(0, 3)})
        new("UIStroke", {Parent = optionFrame, Color = colors.border, Thickness = 1, Transparency = 0.65})
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
        new("UICorner", {Parent = chooseFrame, CornerRadius = UDim.new(0, 3)})
        local conn = optionButton.Activated:Connect(function()
            DropdownFunc.Value = value
            DropdownFunc:Set(DropdownFunc.Value)
        end)
        table.insert(optionConns, conn)
        table.insert(optionFrameCache, {frame = optionFrame, lowerLabel = string.lower(label)})
    end
    function DropdownFunc:Set(Value)
        DropdownFunc.Value = Value
        if configPath then
            Library.ConfigSystem.Set(configPath, Value)
            MarkDirty()
        end
        if isBuilt then
            refreshSelectionVisuals()
        else
            optionLabel.Text = (DropdownFunc.Value ~= nil) and tostring(DropdownFunc.Value) or "Select Option"
        end
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
        clearOptionFrames()
        DropdownFunc.Options = newList
        DropdownFunc:Set(selecting)
    end
    function DropdownFunc:Refresh(newList)
        self:SetValues(newList, nil)
    end
    self:AddConnection("searchBox_" .. dropdownLayoutOrder, searchBox:GetPropertyChangedSignal("Text"):Connect(function()
        ensureBuilt()
        if searchThread then
            pcall(function() task.cancel(searchThread) end)
            searchThread = nil
        end
        local query = string.lower(searchBox.Text)
        searchThread = task.delay(0.08, function()
            searchThread = nil
            for _, entry in ipairs(optionFrameCache) do
                if entry.frame and entry.frame.Parent then
                    entry.frame.Visible = query == "" or string.find(entry.lowerLabel, query, 1, true) ~= nil
                end
            end
        end)
    end))
    self:AddConnection("dropdownOpen_" .. dropdownLayoutOrder, dropdownButton.Activated:Connect(function()
        ensureBuilt()
        self:_showDropdown(dropdownLayoutOrder)
    end))
    DropdownFunc:SetValues(items, savedValue)
    if configPath then
        RegisterCallback(configPath, onSelect, "dropdown", defaultValue, function(val)
            DropdownFunc.Value = val
            if isBuilt then
                refreshSelectionVisuals()
            else
                optionLabel.Text = (val ~= nil) and tostring(val) or "Select Option"
            end
        end)
    end
    if uniqueId then
        self.flags[uniqueId] = DropdownFunc
    end
    return dropdownFrame
end

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
        BackgroundColor3 = colors.bg2,
        BackgroundTransparency = sectionTransparency,
        Position = UDim2.new(1, 0, 0.5, 0),
        Size = UDim2.new(0.48, 0, 0, 22),
        LayoutOrder = dropdownLayoutOrder,
        ZIndex = 8
    })
    new("UICorner", {Parent = selectFrame, CornerRadius = UDim.new(0, 4)})
    new("UIStroke", {Parent = selectFrame, Color = colors.border, Thickness = 1, Transparency = 0.5})
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
        ImageColor3 = colors.primary,
        AnchorPoint = Vector2.new(1, 0.5),
        BackgroundTransparency = 1,
        Position = UDim2.new(1, -6, 0.5, 0),
        Size = UDim2.new(0, 11, 0, 11),
        ZIndex = 9
    })
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
        BackgroundColor3 = colors.bg2,
        BackgroundTransparency = sectionTransparency,
        BorderSizePixel = 0,
        Size = UDim2.new(1, -8, 0, 24),
        Position = UDim2.new(0, 4, 0, 4),
        ClearTextOnFocus = false,
        ZIndex = 154
    })
    new("UICorner", {Parent = searchBox, CornerRadius = UDim.new(0, 4)})
    new("UIStroke", {Parent = searchBox, Color = colors.border, Thickness = 1, Transparency = 0.5})
    new("UIPadding", {Parent = searchBox, PaddingLeft = UDim.new(0, 8)})
    local scrollSelect = new("ScrollingFrame", {
        Parent = dropdownContainer,
        Size = UDim2.new(1, -8, 1, -36),
        Position = UDim2.new(0, 4, 0, 32),
        ScrollBarImageTransparency = 0.35,
        ScrollBarImageColor3 = colors.primary,
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
    self:AddConnection("multiDropdownLayout_" .. dropdownLayoutOrder, listLayout:GetPropertyChangedSignal("AbsoluteContentSize"):Connect(function()
        scrollSelect.CanvasSize = UDim2.new(0, 0, 0, listLayout.AbsoluteContentSize.Y)
    end))
    local savedValues = configPath and Library.ConfigSystem.Get(configPath, defaultValues or {}) or (defaultValues or {})
    if type(savedValues) ~= "table" then savedValues = {} end
    local DropdownFunc = { Value = savedValues, Options = items }
    local optionFrameCache = {}
    local optionConns = {}
    local searchThread = nil
    local buildThread = nil
    local isBuilt = false
    local function disconnectOptionConns()
        for i = #optionConns, 1, -1 do
            local c = optionConns[i]
            optionConns[i] = nil
            pcall(function() c:Disconnect() end)
        end
    end
    local function clearOptionFrames()
        if buildThread then
            pcall(function() task.cancel(buildThread) end)
            buildThread = nil
        end
        disconnectOptionConns()
        for _, child in scrollSelect:GetChildren() do
            if child.Name == "Option" then
                child:Destroy()
            end
        end
        table.clear(optionFrameCache)
        isBuilt = false
    end
    local function refreshSelectionVisuals()
        local texts = {}
        for _, entry in ipairs(optionFrameCache) do
            local opt = entry.frame
            if opt and opt.Parent then
                local v = opt:GetAttribute("RealValue")
                local selected = table.find(DropdownFunc.Value, v)
                if selected then
                    opt.ChooseFrame.Size = UDim2.new(0, 3, 0, 16)
                    opt.ChooseFrame.UIStroke.Transparency = 0.35
                    opt.BackgroundColor3 = colors.bg3
                    opt.BackgroundTransparency = panelTransparency
                    opt.OptionText.TextColor3 = colors.text
                    table.insert(texts, opt.OptionText.Text)
                else
                    opt.ChooseFrame.Size = UDim2.new(0, 0, 0, 0)
                    opt.ChooseFrame.UIStroke.Transparency = 1
                    opt.BackgroundColor3 = colors.bg2
                    opt.BackgroundTransparency = 0.5
                    opt.OptionText.TextColor3 = colors.textDim
                end
            end
        end
        optionLabel.Text = (#texts == 0) and "Select Options" or table.concat(texts, ", ")
    end
    local function ensureBuilt()
        if isBuilt then return end
        clearOptionFrames()
        local list = DropdownFunc.Options or {}
        buildThread = task.spawn(function()
            local chunk = 50
            for i, opt in ipairs(list) do
                DropdownFunc:AddOption(opt)
                if i % chunk == 0 then
                    task.wait()
                end
            end
            isBuilt = true
            buildThread = nil
            refreshSelectionVisuals()
        end)
    end
    function DropdownFunc:Clear()
        clearOptionFrames()
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
            BackgroundColor3 = colors.bg2,
            BackgroundTransparency = 0.5,
            Size = UDim2.new(1, 0, 0, 26),
            Name = "Option",
            ZIndex = 155
        })
        new("UICorner", {Parent = optionFrame, CornerRadius = UDim.new(0, 3)})
        new("UIStroke", {Parent = optionFrame, Color = colors.border, Thickness = 1, Transparency = 0.65})
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
        new("UICorner", {Parent = chooseFrame, CornerRadius = UDim.new(0, 3)})
        local conn = optionButton.Activated:Connect(function()
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
        table.insert(optionConns, conn)
        table.insert(optionFrameCache, {frame = optionFrame, lowerLabel = string.lower(label)})
    end
    function DropdownFunc:Set(Value)
        if type(Value) ~= "table" then Value = {} end
        DropdownFunc.Value = Value
        if configPath then
            Library.ConfigSystem.Set(configPath, Value)
            MarkDirty()
        end
        if isBuilt then
            refreshSelectionVisuals()
        else
            optionLabel.Text = (#DropdownFunc.Value == 0) and "Select Options" or table.concat(DropdownFunc.Value, ", ")
        end
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
        clearOptionFrames()
        DropdownFunc.Options = newList
        DropdownFunc:Set(selecting)
    end
    function DropdownFunc:Refresh(newList)
        self:SetValues(newList, {})
    end
    self:AddConnection("multiSearchBox_" .. dropdownLayoutOrder, searchBox:GetPropertyChangedSignal("Text"):Connect(function()
        ensureBuilt()
        if searchThread then
            pcall(function() task.cancel(searchThread) end)
            searchThread = nil
        end
        local query = string.lower(searchBox.Text)
        searchThread = task.delay(0.08, function()
            searchThread = nil
            for _, entry in ipairs(optionFrameCache) do
                if entry.frame and entry.frame.Parent then
                    entry.frame.Visible = query == "" or string.find(entry.lowerLabel, query, 1, true) ~= nil
                end
            end
        end)
    end))
    self:AddConnection("multiDropdownOpen_" .. dropdownLayoutOrder, dropdownButton.Activated:Connect(function()
        ensureBuilt()
        self:_showDropdown(dropdownLayoutOrder)
    end))
    DropdownFunc:SetValues(items, savedValues)
    if configPath then
        RegisterCallback(configPath, onSelect, "multidropdown", defaultValues or {}, function(val)
            if type(val) ~= "table" then val = {} end
            DropdownFunc.Value = val
            if isBuilt then
                refreshSelectionVisuals()
            else
                optionLabel.Text = (#val == 0) and "Select Options" or table.concat(val, ", ")
            end
        end)
    end
    if uniqueId then
        self.flags[uniqueId] = DropdownFunc
    end
    return dropdownFrame
end
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
        Size = UDim2.new(0.45, 0, 0, 24),
        Position = UDim2.new(0.55, 0, 0.5, -12),
        BackgroundColor3 = colors.bg3,
        BackgroundTransparency = panelTransparency,
        BorderSizePixel = 0,
        ZIndex = 8
    })
    new("UICorner", {Parent = inputBg, CornerRadius = UDim.new(0, 4)})
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
    self:AddConnection("input_" .. label .. tostring(inputBox), inputBox.FocusLost:Connect(function()
        local rawValue = inputBox.Text
        local value = resolveValue(rawValue)
        if configPath then
            Library.ConfigSystem.Set(configPath, value)
            MarkDirty()
        end
        if callback then callback(value) end
    end))
    RegisterCallback(configPath, callback, "input", defaultValue, function(val)
        inputBox.Text = tostring(val ~= nil and val or defaultValue or "")
    end)
    if callback then
        local resolved = resolveValue(tostring(initialValue))
        callback(resolved)
    end
    return frame
end
function Library:CreateButton(parent, label, callback)
    local btnFrame = new("Frame", {
        Parent = parent,
        Size = UDim2.new(1, 0, 0, 28),
        BackgroundColor3 = colors.primary,
        BackgroundTransparency = panelTransparency,
        BorderSizePixel = 0,
        ZIndex = 8
    })
    new("UICorner", {Parent = btnFrame, CornerRadius = UDim.new(0, 5)})
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
    local activeTween = nil
    local clicking = false
    self:AddConnection("btn_" .. label .. tostring(button), button.MouseButton1Click:Connect(function()
        if clicking then return end
        clicking = true
        if activeTween then
            activeTween:Cancel()
            activeTween = nil
        end
        local tweenIn = TweenService:Create(btnFrame, TweenInfo.new(0.08, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
            BackgroundTransparency = 0,
            Size = UDim2.new(1, -4, 0, 26)
        })
        activeTween = tweenIn
        tweenIn:Play()
        tweenIn.Completed:Wait()
        pcall(callback)
        local tweenOut = TweenService:Create(btnFrame, TweenInfo.new(0.15, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
            BackgroundTransparency = panelTransparency,
            Size = UDim2.new(1, 0, 0, 28)
        })
        activeTween = tweenOut
        tweenOut:Play()
        tweenOut.Completed:Wait()
        activeTween = nil
        clicking = false
    end))
    return btnFrame
end
function Library:CreateTextBox(parent, label, placeholder, configPath, defaultValue, callback)
    local container = new("Frame", {
        Parent = parent,
        Size = UDim2.new(1, 0, 0, 48),
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
        Size = UDim2.new(1, 0, 0, 28),
        Position = UDim2.new(0, 0, 0, 18),
        BackgroundColor3 = colors.bg3,
        BackgroundTransparency = panelTransparency,
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
    new("UICorner", {Parent = textBox, CornerRadius = UDim.new(0, 5)})
    new("UIPadding", {Parent = textBox, PaddingLeft = UDim.new(0, 8), PaddingRight = UDim.new(0, 8)})
    local lastValue = initialValue
    self:AddConnection("textbox_" .. label .. tostring(textBox), textBox.FocusLost:Connect(function()
        local value = textBox.Text
        if value ~= lastValue then
            lastValue = value
            if configPath then
                Library.ConfigSystem.Set(configPath, value)
                MarkDirty()
            end
            if callback then callback(value) end
        end
    end))
    if configPath then
        RegisterCallback(configPath, callback, "input", defaultValue, function(val)
            local v = tostring(val ~= nil and val or defaultValue or "")
            textBox.Text = v
            lastValue = v
        end)
    end
    if callback then
        local resolved = tostring(initialValue)
        callback(resolved)
    end
    return {Container = container, TextBox = textBox, SetValue = function(v) textBox.Text = tostring(v) lastValue = tostring(v) end}
end
function Library:Initialize()
    if self._initialized then return end
    self._initialized = true

    -- Jalankan semua callback untuk load nilai tersimpan ke UI
    ExecuteConfigCallbacks()

    -- FIX: buat config tab setelah semua callback dijalankan
    if self._pendingWindowObj then
        pcall(function()
            self:_createConfigTab(self._pendingWindowObj)
        end)
        self._pendingWindowObj = nil
    end

    -- Auto-save saat player leaving (pastikan config tidak hilang)
    self:AddConnection("playerRemoving", Players.PlayerRemoving:Connect(function(plr)
        if plr == localPlayer then
            -- Simpan langsung tanpa debounce saat keluar
            if Library._saveThread then
                pcall(function() task.cancel(Library._saveThread) end)
                Library._saveThread = nil
            end
            isDirty = false
            pcall(function() Library.ConfigSystem.Save() end)
        end
    end))
end
function Library:LoadConfig(data)
    if type(data) ~= "table" then return end
    CurrentConfig = data
    ExecuteConfigCallbacks()
    Library.ConfigSystem.Save()
end
function Library:MakeNotify(config)
    config = config or {}
    local title   = config.Title or "Notification"
    local desc    = config.Description or ""
    local content = config.Content or ""
    local color   = config.Color or colors.primary
    local delay   = config.Delay or 3
    if not self._gui then return end
    self._activeNotifs = self._activeNotifs or {}

    -- Bergantian: hapus semua notif lama, tampilkan yang baru
    for i = #self._activeNotifs, 1, -1 do
        local old = self._activeNotifs[i]
        table.remove(self._activeNotifs, i)
        pcall(function()
            if old and old.Parent then old:Destroy() end
        end)
    end
    local notif = new("Frame", {
        Parent = self._gui,
        Size = UDim2.new(0, 270, 0, 65),
        Position = UDim2.new(1, -280, 1, -75),
        BackgroundColor3 = colors.bg2,
        BackgroundTransparency = panelTransparency,
        BorderSizePixel = 0,
        ZIndex = 200
    })
    table.insert(self._activeNotifs, notif)
    new("UICorner", {Parent = notif, CornerRadius = UDim.new(0, 6)})
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
        pcall(function()
            if notif and notif.Parent then
                notif:Destroy()
            end
        end)
    end)
    notif.Destroying:Connect(function()
        if not self._activeNotifs then return end
        for i = #self._activeNotifs, 1, -1 do
            if self._activeNotifs[i] == notif then
                table.remove(self._activeNotifs, i)
            end
        end
    end)
end

function Library:_createConfigTab(WindowObject)
    local configTab = WindowObject:AddTab({ Name = "Config", Icon = "loop" })
    local autoSaveSection = configTab:AddSection("Auto Save")
    autoSaveSection:AddToggle({
        Title    = "Auto Save Config",
        Default  = true,
        NoSave   = true,
        Callback = function(val)
            _G.AutoSaveEnabled = val
            self:MakeNotify({
                Title       = "Auto Save",
                Description = val and "Auto Save diaktifkan" or "Auto Save dinonaktifkan",
                Delay       = 2,
            })
        end,
    })

    local mgmtSection = configTab:AddSection("Config Management")
    mgmtSection:AddButton({
        Title    = "Save Config Now",
        Callback = function()
            local ok = Library.ConfigSystem.Save()
            self:MakeNotify({
                Title       = "Config",
                Description = ok and "Config berhasil disimpan!" or "Gagal menyimpan config.",
                Color       = ok and colors.success or Color3.fromRGB(220, 50, 50),
                Delay       = 2,
            })
        end,
    })

    local resetConfirm = false
    local resetThread  = nil
    local resetBtnFrame
    resetBtnFrame = self:CreateButton(mgmtSection._container, "Reset to Default", function()
        if not resetConfirm then
            resetConfirm = true
            local btn = resetBtnFrame:FindFirstChildWhichIsA("TextButton")
            if btn then btn.Text = "Klik lagi untuk konfirmasi!" end
            resetBtnFrame.BackgroundColor3 = Color3.fromRGB(255, 100, 0)
            if resetThread then task.cancel(resetThread) end
            resetThread = task.delay(3, function()
                resetConfirm = false
                local b = resetBtnFrame:FindFirstChildWhichIsA("TextButton")
                if b then b.Text = "Reset to Default" end
                resetBtnFrame.BackgroundColor3 = colors.primary
            end)
        else
            if resetThread then task.cancel(resetThread) end
            resetConfirm = false
            local btn = resetBtnFrame:FindFirstChildWhichIsA("TextButton")
            if btn then btn.Text = "Reset to Default" end
            resetBtnFrame.BackgroundColor3 = colors.primary
            Library.ConfigSystem.Reset()
            ExecuteConfigCallbacks()
            self:MakeNotify({
                Title       = "Config",
                Description = "Semua settingan direset ke default!",
                Color       = Color3.fromRGB(220, 50, 50),
                Delay       = 3,
            })
        end
    end)
    mgmtSection:AddParagraph({
        Title   = "⚠️ Perhatian",
        Content = "Setelah melakukan Reset to Default, beberapa settingan seperti Toggle dan nilai Input akan langsung ter-update di UI.\n\n"
               .. "Namun untuk settingan yang mempengaruhi karakter, kecepatan, atau fitur aktif lainnya — kamu perlu Rejoin / Respawn agar perubahan berlaku sepenuhnya.\n\n"
               .. "File config disimpan otomatis setiap 2 detik jika Auto Save aktif. Pastikan Auto Save ON sebelum keluar game agar settinganmu tidak hilang.",
    })
    local deleteConfirm = false
    local deleteThread  = nil
    local deleteBtnFrame
    deleteBtnFrame = self:CreateButton(mgmtSection._container, "Delete Config File", function()
        if not deleteConfirm then
            deleteConfirm = true
            local btn = deleteBtnFrame:FindFirstChildWhichIsA("TextButton")
            if btn then btn.Text = "Klik lagi untuk konfirmasi!" end
            deleteBtnFrame.BackgroundColor3 = Color3.fromRGB(200, 30, 30)
            if deleteThread then task.cancel(deleteThread) end
            deleteThread = task.delay(3, function()
                deleteConfirm = false
                local b = deleteBtnFrame:FindFirstChildWhichIsA("TextButton")
                if b then b.Text = "Delete Config File" end
                deleteBtnFrame.BackgroundColor3 = colors.primary
            end)
        else
            if deleteThread then task.cancel(deleteThread) end
            deleteConfirm = false
            local btn = deleteBtnFrame:FindFirstChildWhichIsA("TextButton")
            if btn then btn.Text = "Delete Config File" end
            deleteBtnFrame.BackgroundColor3 = colors.primary
            Library.ConfigSystem.Delete()
            self:MakeNotify({
                Title       = "Config",
                Description = "File config telah dihapus.",
                Color       = Color3.fromRGB(220, 50, 50),
                Delay       = 2,
            })
        end
    end)
end

function Library:Window(config)
    config = config or {}
    self:CreateWindow({
        Name     = "LynxGui",
        Title    = config.Title or "LynX",
        Subtitle = config.Footer or ""
    })
    -- FIX: Load config SEBELUM WindowObject dibuat agar nilai tersimpan
    -- sudah ada di CurrentConfig saat komponen-komponen dibuat
    Library.ConfigSystem.Load()
    local WindowObject = {}
    WindowObject._library = self
    WindowObject._tabs    = {}
    WindowObject._tabOrder = 0
    Library._initialized = false
    Library._pendingWindowObj = WindowObject

    -- FIX: ganti RunService.Heartbeat polling (boros) dengan task.delay sederhana
    task.delay(0.5, function()
        if not Library._initialized then
            Library:Initialize()
        end
    end)
    function WindowObject:AddTab(tabConfig)
        tabConfig = tabConfig or {}
        local tabName = tabConfig.Name or "Tab"
        local tabIcon = tabConfig.Icon or ""
        local iconMap = {
            ["player"]    = "rbxassetid://12120698352",
            ["web"]       = "rbxassetid://137601480983962",
            ["bag"]       = "rbxassetid://8601111810",
            ["shop"]      = "rbxassetid://4985385964",
            ["cart"]      = "rbxassetid://128874923961846",
            ["plug"]      = "rbxassetid://137601480983962",
            ["settings"]  = "rbxassetid://70386228443175",
            ["loop"]      = "rbxassetid://122032243989747",
            ["gps"]       = "rbxassetid://78381660144034",
            ["compas"]    = "rbxassetid://125300760963399",
            ["gamepad"]   = "rbxassetid://84173963561612",
            ["boss"]      = "rbxassetid://13132186360",
            ["scroll"]    = "rbxassetid://114127804740858",
            ["menu"]      = "rbxassetid://6340513838",
            ["crosshair"] = "rbxassetid://12614416478",
            ["user"]      = "rbxassetid://108483430622128",
            ["stat"]      = "rbxassetid://12094445329",
            ["eyes"]      = "rbxassetid://14321059114",
            ["sword"]     = "rbxassetid://82472368671405",
            ["discord"]   = "rbxassetid://94434236999817",
            ["star"]      = "rbxassetid://107005941750079",
            ["skeleton"]  = "rbxassetid://17313330026",
            ["payment"]   = "rbxassetid://18747025078",
            ["scan"]      = "rbxassetid://109869955247116",
            ["alert"]     = "rbxassetid://73186275216515",
            ["question"]  = "rbxassetid://17510196486",
            ["idea"]      = "rbxassetid://16833255748",
            ["strom"]     = "rbxassetid://13321880293",
            ["water"]     = "rbxassetid://100076212630732",
            ["dcs"]       = "rbxassetid://15310731934",
            ["start"]     = "rbxassetid://108886429866687",
            ["next"]      = "rbxassetid://12662718374",
            ["rod"]       = "rbxassetid://103247953194129",
            ["fish"]      = "rbxassetid://97167558235554",
            ["send"]      = "rbxassetid://122775063389583",
            ["home"]      = "rbxassetid://86450224791749",
        }
        local iconId = ""
        if tabIcon and tabIcon ~= "" then
            iconId = iconMap[tabIcon:lower()] or ""
        end
        self._tabOrder = (self._tabOrder or 0) + 1
        local page = self._library:CreatePage(tabName, tabName, iconId, self._tabOrder)
        local TabObject = {}
        TabObject._page      = page
        TabObject._library   = self._library
        TabObject._sections  = {}
        function TabObject:AddSection(sectionTitle, isOpen)
            sectionTitle = sectionTitle or "Section"
            local category = self._library:CreateCategory(self._page, sectionTitle, isOpen)
            local SectionObject = {}
            SectionObject._container  = category
            SectionObject._library    = self._library
            SectionObject._layoutOrder = 0
            local function getNextLayoutOrder()
                SectionObject._layoutOrder = SectionObject._layoutOrder + 1
                return SectionObject._layoutOrder
            end
            function SectionObject:AddToggle(toggleConfig)
                toggleConfig = toggleConfig or {}
                local title      = toggleConfig.Title or "Toggle"
                local default    = toggleConfig.Default or false
                local callback   = toggleConfig.Callback
                local noSave     = toggleConfig.NoSave or false
                local configPath = noSave and nil or ("Toggles." .. title:gsub("%s+", "_"))
                local toggleObj = { _value = default }
                local wrappedCallback = function(val)
                    toggleObj._value = val
                    if callback then callback(val) end
                end
                local toggleResult = self._library:CreateToggle(self._container, title, configPath, wrappedCallback, noSave, default)
                local frame = toggleResult and toggleResult.frame or toggleResult
                if frame then frame.LayoutOrder = getNextLayoutOrder() end
                function toggleObj:SetValue(val)
                    self._value = val
                    if toggleResult and toggleResult.set then
                        toggleResult.set(val)
                    end
                    if callback then callback(val) end
                end
                function toggleObj:GetValue()
                    return self._value
                end
                return toggleObj
            end
            function SectionObject:AddDropdown(dropdownConfig)
                dropdownConfig = dropdownConfig or {}
                local title      = dropdownConfig.Title or "Dropdown"
                local options    = dropdownConfig.Options or {}
                local default    = dropdownConfig.Default
                local callback   = dropdownConfig.Callback
                local noSave     = dropdownConfig.NoSave or false
                local isMulti    = dropdownConfig.Multi or false
                local configPath = noSave and nil or ((isMulti and "MultiDropdowns." or "Dropdowns.") .. title:gsub("%s+", "_"))
                local uniqueId   = title:gsub("%s+", "_")
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
                local title      = dropdownConfig.Title or "Multi Select"
                local options    = dropdownConfig.Options or {}
                local default    = dropdownConfig.Default or {}
                local callback   = dropdownConfig.Callback
                local noSave     = dropdownConfig.NoSave or false
                local configPath = noSave and nil or ("MultiDropdowns." .. title:gsub("%s+", "_"))
                local uniqueId   = title:gsub("%s+", "_")
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
                local title       = inputConfig.Title or "Input"
                local default     = inputConfig.Default or ""
                local placeholder = inputConfig.Placeholder or ""
                local callback    = inputConfig.Callback
                local noSave      = inputConfig.NoSave or false
                local configPath  = noSave and nil or ("Inputs." .. title:gsub("%s+", "_"))
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
                        SetValue = function(self, val) end
                    }
                end
            end
            function SectionObject:AddButton(buttonConfig)
                buttonConfig = buttonConfig or {}
                local title    = buttonConfig.Title or "Button"
                local callback = buttonConfig.Callback or function() end
                local frame = self._library:CreateButton(self._container, title, callback)
                if frame then frame.LayoutOrder = getNextLayoutOrder() end
                return frame
            end
            function SectionObject:AddParagraph(paragraphConfig)
                paragraphConfig = paragraphConfig or {}
                local title   = formatRichText(paragraphConfig.Title or "")
                local content = formatRichText(paragraphConfig.Content or "")
                local useRich = paragraphConfig.RichText ~= false
                local frame = new("Frame", {
                    Parent = self._container,
                    Size = UDim2.new(1, 0, 0, 0),
                    BackgroundTransparency = 1,
                    ZIndex = 7,
                    LayoutOrder = getNextLayoutOrder()
                })
                new("UIListLayout", {
                    Parent = frame,
                    Padding = UDim.new(0, 3),
                    SortOrder = Enum.SortOrder.LayoutOrder
                })
                local titleLabel = new("TextLabel", {
                    Parent = frame,
                    Name = "TitleLabel",
                    LayoutOrder = 1,
                    Text = title,
                    Size = UDim2.new(1, 0, 0, 0),
                    BackgroundTransparency = 1,
                    Font = Enum.Font.GothamBold,
                    TextSize = fontSize.small,
                    TextColor3 = colors.text,
                    TextXAlignment = Enum.TextXAlignment.Left,
                    TextYAlignment = Enum.TextYAlignment.Top,
                    TextWrapped = true,
                    RichText = useRich,
                    Visible = title ~= "",
                    ZIndex = 8
                })
                local contentLabel = new("TextLabel", {
                    Parent = frame,
                    Name = "ContentLabel",
                    LayoutOrder = 2,
                    Text = content,
                    Size = UDim2.new(1, 0, 0, 0),
                    BackgroundTransparency = 1,
                    Font = Enum.Font.Gotham,
                    TextSize = fontSize.small,
                    TextColor3 = colors.textDim,
                    TextXAlignment = Enum.TextXAlignment.Left,
                    TextYAlignment = Enum.TextYAlignment.Top,
                    TextWrapped = true,
                    RichText = useRich,
                    ZIndex = 8
                })
                local function reflowParagraph()
                    local totalHeight = 0
                    if titleLabel and titleLabel.Parent and titleLabel.Visible then
                        local h = titleLabel.TextBounds.Y
                        titleLabel.Size = UDim2.new(1, 0, 0, h)
                        totalHeight = totalHeight + h + 3 -- padding
                    end
                    if contentLabel and contentLabel.Parent and contentLabel.Visible then
                        local h = contentLabel.TextBounds.Y
                        contentLabel.Size = UDim2.new(1, 0, 0, h)
                        totalHeight = totalHeight + h
                    end
                    if frame and frame.Parent then
                        frame.Size = UDim2.new(1, 0, 0, totalHeight)
                    end
                end
                frame:GetPropertyChangedSignal("AbsoluteSize"):Connect(reflowParagraph)
                if titleLabel then titleLabel:GetPropertyChangedSignal("TextBounds"):Connect(reflowParagraph) end
                if contentLabel then contentLabel:GetPropertyChangedSignal("TextBounds"):Connect(reflowParagraph) end
                task.defer(reflowParagraph)
                local paragraphObj = {
                    _frame        = frame,
                    _titleLabel   = titleLabel,
                    _contentLabel = contentLabel,
                    SetTitle = function(self, newTitle)
                        if self._titleLabel then
                            newTitle = formatRichText(newTitle or "")
                            self._titleLabel.Text = newTitle
                            self._titleLabel.Visible = newTitle ~= ""
                            reflowParagraph()
                        end
                    end,
                    SetContent = function(self, newContent)
                        if self._contentLabel then
                            self._contentLabel.Text = formatRichText(newContent or "")
                            reflowParagraph()
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
        if self._tabOrder == 1 then
            self._library:SetFirstPage(tabName)
        end
        table.insert(self._tabs, TabObject)
        return TabObject
    end
    return WindowObject
end
return Library
