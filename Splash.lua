-- TauntMaster Forever: welcome / "What's new" splash screen.
-- Shows once after each update (and on first install), unless turned off.
-- /tm news opens it anytime.

local ADDON, ns = ...
local TM = ns.TM

local WIDTH, HEIGHT = 720, 620
local BANNER_H = 130
local MAX_NEWS = 6
local LOGO = "Interface\\AddOns\\TauntMasterForever\\Media\\logo"

local splash

function TM:CurrentNewsVersion()
    return self.NEWS and self.NEWS[1] and self.NEWS[1].version
end

local ORANGE, GOLD, BLUE, GREY, RED = "|cffff9a2a", "|cffffd100", "|cff8fd3ff", "|cffbbbbbb", "|cffff5a4a"

local function BuildText()
    local lines = {}
    local function add(s) lines[#lines + 1] = s end
    local top = TM.NEWS and TM.NEWS[1]
    if top then
        add(GOLD .. "v" .. top.version .. "|r " .. GREY .. "(" .. top.date .. ")|r")
        add(" ")
    end

    add(ORANGE .. "# Quick start|r")
    add("- |cffffffffClick a bar|r to taunt that player's target")
    add("- |cffffffffRight-click|r the bar header for Lock / Settings")
    add("- " .. RED .. "Red X|r = that player has no enemy targeted")
    add("- " .. BLUE .. "/tm|r  open options      " .. BLUE .. "/tm toggle|r  show / hide bars")
    add("- " .. BLUE .. "/tm check|r  check your spells      " .. BLUE .. "/tm news|r  show this window again")
    add(" ")

    add(ORANGE .. "# What's new|r")
    local count = 0
    for _, entry in ipairs(TM.NEWS or {}) do
        for _, item in ipairs(entry.items) do
            if count >= MAX_NEWS then break end
            add("- " .. GOLD .. "v" .. entry.version .. "|r  " .. item)
            count = count + 1
        end
        if count >= MAX_NEWS then break end
    end
    add(" ")

    add(ORANGE .. "# Support|r")
    add("Found a bug? Report it on GitHub (link on the CurseForge page).")
    add("Enjoying the addon? Tips on Ko-fi keep it updated: ko-fi.com/tauntmasterforever")
    return table.concat(lines, "\n")
end

local function Build()
    splash = CreateFrame("Frame", "TauntMasterForeverSplash", UIParent)
    splash:SetSize(WIDTH, HEIGHT)
    splash:SetPoint("CENTER", 0, 40)
    splash:SetFrameStrata("DIALOG")
    splash:SetToplevel(true)
    splash:SetClampedToScreen(true)
    splash:SetMovable(true)
    splash:EnableMouse(true)
    splash:RegisterForDrag("LeftButton")
    splash:SetScript("OnDragStart", splash.StartMoving)
    splash:SetScript("OnDragStop", splash.StopMovingOrSizing)
    splash:Hide()
    table.insert(UISpecialFrames, "TauntMasterForeverSplash") -- Escape closes it

    -- Gold border + dark body
    local border = splash:CreateTexture(nil, "BACKGROUND", nil, -8)
    border:SetAllPoints()
    border:SetColorTexture(0.42, 0.35, 0.23, 1)
    local body = splash:CreateTexture(nil, "BACKGROUND", nil, -7)
    body:SetPoint("TOPLEFT", 2, -2)
    body:SetPoint("BOTTOMRIGHT", -2, 2)
    body:SetColorTexture(0.05, 0.04, 0.035, 0.97)

    -- Banner
    local banner = splash:CreateTexture(nil, "BORDER")
    banner:SetPoint("TOPLEFT", 2, -2)
    banner:SetPoint("TOPRIGHT", -2, -2)
    banner:SetHeight(BANNER_H)
    banner:SetColorTexture(1, 1, 1, 1)
    local ok = CreateColor and pcall(banner.SetGradient, banner, "HORIZONTAL",
        CreateColor(0.55, 0.11, 0.07, 1), CreateColor(0.10, 0.02, 0.02, 1))
    if not ok then banner:SetColorTexture(0.35, 0.07, 0.05, 1) end
    local line = splash:CreateTexture(nil, "ARTWORK")
    line:SetPoint("TOPLEFT", banner, "BOTTOMLEFT")
    line:SetPoint("TOPRIGHT", banner, "BOTTOMRIGHT")
    line:SetHeight(2)
    line:SetColorTexture(0.42, 0.35, 0.23, 1)

    local logo = splash:CreateTexture(nil, "ARTWORK")
    logo:SetSize(108, 108)
    logo:SetPoint("TOPLEFT", 18, -13)
    logo:SetTexture(LOGO)

    local title = splash:CreateFontString(nil, "OVERLAY", "GameFontNormalHuge")
    title:SetPoint("TOPLEFT", logo, "TOPRIGHT", 18, -14)
    local font, _, flags = title:GetFont()
    title:SetFont(font, 34, "THICKOUTLINE")
    title:SetTextColor(0.95, 0.9, 0.77)
    title:SetText("TauntMaster Forever")

    local sub = splash:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    sub:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 2, -8)
    sub:SetTextColor(1, 0.7, 0.28)
    sub:SetText("One-click tanking for WoW: Forever")

    local close = CreateFrame("Button", nil, splash, "UIPanelCloseButton")
    close:SetPoint("TOPRIGHT", -2, -2)

    -- Scrolling text
    local scroll = CreateFrame("ScrollFrame", "TauntMasterForeverSplashScroll", splash, "UIPanelScrollFrameTemplate")
    scroll:SetPoint("TOPLEFT", 22, -(BANNER_H + 16))
    scroll:SetPoint("BOTTOMRIGHT", -32, 48)
    local content = CreateFrame("Frame", nil, scroll)
    content:SetSize(WIDTH - 60, 10)
    scroll:SetScrollChild(content)
    local text = content:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    text:SetPoint("TOPLEFT")
    text:SetWidth(WIDTH - 60)
    text:SetJustifyH("LEFT")
    text:SetSpacing(3)
    splash.text, splash.content = text, content

    -- Footer
    local sep = splash:CreateTexture(nil, "ARTWORK")
    sep:SetPoint("BOTTOMLEFT", 2, 40)
    sep:SetPoint("BOTTOMRIGHT", -2, 40)
    sep:SetHeight(1)
    sep:SetColorTexture(0.29, 0.25, 0.16, 1)

    local cb = CreateFrame("CheckButton", nil, splash, "UICheckButtonTemplate")
    cb:SetSize(24, 24)
    cb:SetPoint("BOTTOMLEFT", 14, 9)
    local cbText = splash:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    cbText:SetPoint("LEFT", cb, "RIGHT", 2, 0)
    cbText:SetText("Show this after each update")
    cb:SetScript("OnClick", function(self) TM.db.showSplash = self:GetChecked() and true or false end)
    splash.check = cb

    local done = CreateFrame("Button", nil, splash, "UIPanelButtonTemplate")
    done:SetSize(100, 22)
    done:SetPoint("BOTTOMRIGHT", -14, 10)
    done:SetText("Close")
    done:SetScript("OnClick", function() splash:Hide() end)

    local notes = splash:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    notes:SetPoint("RIGHT", done, "LEFT", -12, 0)
    notes:SetText("Full release notes on CurseForge")

    TM._splash = splash
end

function TM:ShowSplash()
    if not splash then Build() end
    splash.text:SetText(BuildText())
    splash.content:SetHeight((splash.text:GetStringHeight() or 0) + 10)
    splash.check:SetChecked(self.db.showSplash)
    self.db.lastSeenVersion = self:CurrentNewsVersion()
    splash:Show()
    splash:Raise()
end

function TM:ToggleSplash()
    if splash and splash:IsShown() then splash:Hide() else self:ShowSplash() end
end

-- On login: show once per new version (and on first install), a few seconds in
function TM:MaybeShowSplash()
    local current = self:CurrentNewsVersion()
    if not current or not self.db.showSplash or self.db.lastSeenVersion == current then return end
    if C_Timer and C_Timer.After then
        C_Timer.After(4, function() TM:ShowSplash() end)
    else
        self:ShowSplash()
    end
end
