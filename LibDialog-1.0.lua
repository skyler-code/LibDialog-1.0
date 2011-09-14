-----------------------------------------------------------------------
-- Upvalued Lua API.
-----------------------------------------------------------------------
local _G = getfenv(0)

-- Functions
local error = _G.error
local pairs = _G.pairs

-- Libraries
local table = _G.table

-----------------------------------------------------------------------
-- Library namespace.
-----------------------------------------------------------------------
local LibStub = _G.LibStub
local MAJOR = "LibDialog-1.0"

_G.assert(LibStub, MAJOR .. " requires LibStub")

local MINOR = 1 -- Should be manually increased
local lib, oldminor = LibStub:NewLibrary(MAJOR, MINOR)

if not lib then
    return
end -- No upgrade needed

local dialog_prototype = _G.CreateFrame("Frame", nil, _G.UIParent)
local dialog_meta = {
    __index = dialog_prototype
}

-----------------------------------------------------------------------
-- Migrations.
-----------------------------------------------------------------------
lib.delegates = lib.delegates or {}
lib.active_dialogs = lib.active_dialogs or {}

lib.dialog_heap = lib.dialog_heap or {}
lib.button_heap = lib.button_heap or {}

-----------------------------------------------------------------------
-- Constants.
-----------------------------------------------------------------------
local active_dialogs = lib.active_dialogs
local dialog_heap = lib.dialog_heap
local button_heap = lib.button_heap

local METHOD_USAGE_FORMAT = MAJOR .. ":%s() - %s."

local DEFAULT_DIALOG_WIDTH = 320
local DEFAULT_DIALOG_HEIGHT = 72

local DEFAULT_DIALOG_TEXT_WIDTH = 290

local DEFAULT_DIALOG_BACKDROP = {
    bgFile = [[Interface\DialogFrame\UI-DialogBox-Background]],
    edgeFile = [[Interface\DialogFrame\UI-DialogBox-Border]],
    tile = true,
    tileSize = 32,
    edgeSize = 32,
    insets = {
        left = 11,
        right = 12,
        top = 12,
        bottom = 11,
    },
}

-----------------------------------------------------------------------
-- Upvalues.
-----------------------------------------------------------------------
local _ReleaseDialog

-----------------------------------------------------------------------
-- Helper functions.
-----------------------------------------------------------------------
local function _Dialog_OnShow(dialog)
    local delegate = dialog.delegate

    _G.PlaySound("igMainMenuOpen")

    if delegate.OnShow then
        delegate.OnShow(dialog, dialog.data)
    end
end

local function _Dialog_OnHide(dialog)
    local delegate = dialog.delegate

    _G.PlaySound("igMainMenuClose")

    if delegate.OnHide then
        delegate.OnHide(dialog, dialog.data)
    end
    _ReleaseDialog(dialog)
end

local function _AcquireDialog()
    local dialog = table.remove(dialog_heap)

    if not dialog then
        dialog = _G.setmetatable(_G.CreateFrame("Frame", ("%s_Dialog%d"):format(MAJOR, #active_dialogs + 1), _G.UIParent), dialog_meta)

        local close_button = _G.CreateFrame("Button", nil, dialog, "UIPanelCloseButton")
        close_button:SetPoint("TOPRIGHT", -3, -3)

        dialog.close_button = close_button

        local text = dialog:CreateFontString(nil, nil, "GameFontHighlight")
        text:SetWidth(DEFAULT_DIALOG_TEXT_WIDTH)
        text:SetPoint("TOP", 0, -16)

        dialog.text = text
    end
    dialog:Reset()
    return dialog
end

local function _RefreshDialogAnchors()
    for index = 1, #active_dialogs do
        local current_dialog = active_dialogs[index]
        current_dialog:ClearAllPoints()

        if index == 1 then
            local default_dialog = _G.StaticPopup_DisplayedFrames[#_G.StaticPopup_DisplayedFrames]

            if default_dialog then
                current_dialog:SetPoint("TOP", default_dialog, "BOTTOM", 0, 0)
            else
                current_dialog:SetPoint("TOP", _G.UIParent, "TOP", 0, -135)
            end
        else
            current_dialog:SetPoint("TOP", active_dialogs[index - 1], "BOTTOM", 0, 0)
        end
    end
end

-- Upvalued at top of file.
function _ReleaseDialog(dialog)
    -- If the dialog is already in the heap, terminate.
    for index = 1, #dialog_heap do
        if dialog_heap[index] == dialog then
            return
        end
    end
    dialog:Hide()
    dialog.delegate = nil

    local remove_index
    for index = 1, #active_dialogs do
        if active_dialogs[index] == dialog then
            remove_index = index
        end
    end

    if remove_index then
        table.remove(active_dialogs, remove_index):ClearAllPoints()
    end
    table.insert(dialog_heap, dialog)

    _RefreshDialogAnchors()
end

if not lib.hooked_set_up_position then
    _G.hooksecurefunc("StaticPopup_SetUpPosition", function()
        _RefreshDialogAnchors()
    end)
    lib.hooked_set_up_position = true
end

if not lib.hooked_escape_pressed then
    local dialogs_to_release = {}

    _G.hooksecurefunc("StaticPopup_EscapePressed", function()
        local active_dialogs = lib.active_dialogs

        table.wipe(dialogs_to_release)

        for index = 1, #active_dialogs do
            local dialog = active_dialogs[index]
            dialogs_to_release[dialog] = true
        end

        for dialog in pairs(dialogs_to_release) do
            local delegate = dialog.delegate

            if delegate.OnCancel and not delegate.cancel_ignores_escape then
                delegate.OnCancel(dialog)
            end
            _ReleaseDialog(dialog)
        end
    end)
    lib.hooked_escape_pressed = true
end

local function _BuildDialog(delegate, ...)
    local data = ...
    local dialog_text = delegate.Text(data)

    if not dialog_text or dialog_text == "" then
        error("Dialog text required.", 3)
    end
    local dialog = _AcquireDialog()
    dialog.delegate = delegate
    dialog.data = data
    dialog.text:SetText(dialog_text)

    return dialog
end

-----------------------------------------------------------------------
-- Library methods.
-----------------------------------------------------------------------
function lib:Register(delegate_name, delegate)
    if _G.type(delegate_name) ~= "string" or delegate_name == "" then
        error(METHOD_USAGE_FORMAT:format("Register", "delegate_name must be a non-empty string"), 2)
    end

    if _G.type(delegate) ~= "table" then
        error(METHOD_USAGE_FORMAT:format("Register", "delegate must be a table"), 2)
    end
    self.delegates[delegate_name] = delegate
end

function lib:Spawn(reference, ...)
    local reference_type = _G.type(reference)

    if reference == "" or (reference_type ~= "string" and reference_type ~= "table") then
        error(METHOD_USAGE_FORMAT:format("Spawn", "reference must be a delegate table or a non-empty string"), 2)
    end
    local dialog

    if reference_type == "string" then
        if not self.delegates[reference] then
            error(METHOD_USAGE_FORMAT:format("Spawn", ("\"%s\" does not match a registered delegate"):format(reference)), 2)
        end
        dialog = _BuildDialog(self.delegates[reference], ...)
    else
        dialog = _BuildDialog(reference, ...)
    end

    if not dialog then
        return
    end

    -- Anchor to the bottom of existing dialogs. If none exist, check to see if there are visible default StaticPopupDialogs and anchor to that instead; else, anchor to UIParent.
    if #active_dialogs > 0 then
        dialog:SetPoint("TOP", active_dialogs[#active_dialogs], "BOTTOM", 0, 0)
    else
        local default_dialog = _G.StaticPopup_DisplayedFrames[#_G.StaticPopup_DisplayedFrames]

        if default_dialog then
            dialog:SetPoint("TOP", default_dialog, "BOTTOM", 0, 0)
        else
            dialog:SetPoint("TOP", _G.UIParent, "TOP", 0, -135)
        end
    end
    active_dialogs[#active_dialogs + 1] = dialog
    dialog:Show()
end

-----------------------------------------------------------------------
-- Dialog methods.
-----------------------------------------------------------------------
function dialog_prototype:Reset()
    self:SetWidth(DEFAULT_DIALOG_WIDTH)
    self:SetHeight(DEFAULT_DIALOG_HEIGHT)
    self:SetBackdrop(DEFAULT_DIALOG_BACKDROP)

    self:SetToplevel(true)
    self:EnableKeyboard(true)
    self:EnableMouse(true)
    self:SetFrameStrata("DIALOG")

    self:SetScript("OnShow", _Dialog_OnShow)
    self:SetScript("OnHide", _Dialog_OnHide)
end
