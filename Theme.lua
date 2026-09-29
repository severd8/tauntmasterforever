-- TauntMaster Forever: shared look for every window and widget.
-- Flat dark panels, gold text, red accents. Loaded before Options.lua and Splash.lua.

local _, ns = ...
local T = {}
ns.Theme = T

T.NAME = "TauntMaster Forever"
T.LOGO = "Interface\\AddOns\\TauntMasterForever\\Media\\logo"

local C = {
    win     = { 0.07, 0.063, 0.063, 0.98 },
    side    = { 0.047, 0.04, 0.04, 1 },
    card    = { 0.10, 0.086, 0.078, 1 },
    field   = { 0.055, 0.047, 0.043, 1 },
    line    = { 0.17, 0.14, 0.10, 1 },
    edge    = { 0.35, 0.29, 0.19, 1 },
    fieldEdge = { 0.29, 0.24, 0.16, 1 },
    red     = { 0.48, 0.11, 0.06, 1 },
    redHi   = { 0.62, 0.16, 0.08, 1 },
    btnEdge = { 0.72, 0.53, 0.23, 1 },
    offTrack = { 0.23, 0.20, 0.19, 1 },
    onTrack = { 0.55, 0.14, 0.08, 1 },
    gold    = { 1, 0.82, 0, 1 },
    grey    = { 0.54, 0.50, 0.47, 1 },
    orange  = { 0.91, 0.63, 0.25 },
    muted   = { 0.81, 0.77, 0.68 },
}

local function Fill(frame, color, layer, sub)
    local t = frame:CreateTexture(nil, layer or "BACKGROUND", nil, sub or -8)
    t:SetAllPoints()
    t:SetColorTexture(unpack(color))
    return t
end

local function Border(frame, color)
    local edges = {}
    for _, side in ipairs({ "TOP", "BOTTOM", "LEFT", "RIGHT" }) do
        local t = frame:CreateTexture(nil, "BORDER")
        t:SetColorTexture(unpack(color))
        if side == "TOP" or side == "BOTTOM" then
            t:SetPoint(side .. "LEFT"); t:SetPoint(side .. "RIGHT"); t:SetHeight(1)
        else
            t:SetPoint("TOP" .. side); t:SetPoint("BOTTOM" .. side); t:SetWidth(1)
        end
        edges[#edges + 1] = t
    end
    return edges
end

local function Text(parent, text, template, color, size)
    local fs = parent:CreateFontString(nil, "OVERLAY", template or "GameFontHighlight")
    if size then
        local font, _, flags = fs:GetFont()
        if font then fs:SetFont(font, size, flags) end
    end
    if color then fs:SetTextColor(color[1], color[2], color[3]) end
    fs:SetJustifyH("LEFT")
    fs:SetText(text or "")
    return fs
end

-- Flat red button with gold text
local function FlatButton(parent, text, width, height)
    local b = CreateFrame("Button", nil, parent)
    b:SetSize(width or 100, height or 22)
    b.bg = Fill(b, C.red)
    Border(b, C.btnEdge)
    local fs = Text(b, "", "GameFontNormal")
    fs:SetPoint("CENTER")
    fs:SetJustifyH("CENTER")
    b:SetFontString(fs)
    b:SetText(text)
    b:SetScript("OnEnter", function(self) self.bg:SetColorTexture(unpack(C.redHi)) end)
    b:SetScript("OnLeave", function(self) self.bg:SetColorTexture(unpack(C.red)) end)
    return b
end


-- Red gradient used by window headers and banners
function T.HeaderGradient(tex)
    tex:SetColorTexture(1, 1, 1, 1)
    local ok = CreateColor and pcall(tex.SetGradient, tex, "HORIZONTAL",
        CreateColor(0.35, 0.075, 0.047, 1), CreateColor(0.11, 0.03, 0.024, 1))
    if not ok then tex:SetColorTexture(0.25, 0.06, 0.04, 1) end
end

-- On/off switch widget. b:SetOn(bool) paints it; b:IsOn() reads it.
function T.SwitchWidget(parent)
    local b = CreateFrame("Button", nil, parent)
    b:SetSize(30, 16)
    b.isSwitch = true
    local track = b:CreateTexture(nil, "BACKGROUND")
    track:SetAllPoints()
    local knob = b:CreateTexture(nil, "ARTWORK")
    knob:SetSize(12, 12)
    function b:SetOn(on)
        self.on = on and true or false
        track:SetColorTexture(unpack(self.on and C.onTrack or C.offTrack))
        knob:SetColorTexture(unpack(self.on and C.gold or C.grey))
        knob:ClearAllPoints()
        knob:SetPoint("LEFT", self, "LEFT", self.on and 16 or 2, 0)
    end
    function b:IsOn() return self.on end
    b:SetOn(false)
    return b
end

T.C, T.Fill, T.Border, T.Text, T.FlatButton = C, Fill, Border, Text, FlatButton
