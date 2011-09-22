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
lib.queued_delegates = lib.queues_delegates or {}
lib.delegate_queue = lib.delegate_queue or {}

lib.active_dialogs = lib.active_dialogs or {}
lib.active_buttons = lib.active_buttons or {}
lib.active_checkboxes = lib.active_checkboxes or {}
lib.active_editboxes = lib.active_editboxes or {}

lib.dialog_heap = lib.dialog_heap or {}
lib.button_heap = lib.button_heap or {}
lib.checkbox_heap = lib.checkbox_heap or {}
lib.editbox_heap = lib.editbox_heap or {}

-----------------------------------------------------------------------
-- Constants.
-----------------------------------------------------------------------
local delegates = lib.delegates
local queued_delegates = lib.queued_delegates
local delegate_queue = lib.delegate_queue

local active_dialogs = lib.active_dialogs
local active_buttons = lib.active_buttons
local active_checkboxes = lib.active_checkboxes
local active_editboxes = lib.active_editboxes

local dialog_heap = lib.dialog_heap
local button_heap = lib.button_heap
local checkbox_heap = lib.checkbox_heap
local editbox_heap = lib.editbox_heap

local METHOD_USAGE_FORMAT = MAJOR .. ":%s() - %s."

local DEFAULT_DIALOG_WIDTH = 320
local DEFAULT_DIALOG_HEIGHT = 72

local DEFAULT_EDITBOX_WIDTH = 130
local DEFAULT_EDITBOX_HEIGHT = 32

local DEFAULT_CHECKBOX_SIZE = 32

local DEFAULT_DIALOG_TEXT_WIDTH = 290

local MAX_DIALOGS = 4
local MAX_BUTTONS = 3

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

-----------------------------------------------------------------------
-- Helper functions.
-----------------------------------------------------------------------
local function _ProcessQueue()
    if #active_dialogs == MAX_DIALOGS then
        return
    end
    local delegate = table.remove(delegate_queue)

    if not delegate then
        return
    end
    local data = queued_delegates[delegate]
    queued_delegates[delegate] = nil

    if data == "" then
        data = nil
    end
    return lib:Spawn(delegate, data)
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

local function _RecycleWidget(widget, actives, heap)
    local remove_index

    for index = 1, #actives do
        if actives[index] == widget then
            remove_index = index
        end
    end

    if remove_index then
        table.remove(actives, remove_index):ClearAllPoints()
    end
    table.insert(heap, widget)
end

local function _ReleaseCheckBox(checkbox)
    checkbox:Hide()
    _RecycleWidget(checkbox, active_checkboxes, checkbox_heap)
    checkbox:SetParent(nil)
end

local function _ReleaseEditBox(editbox)
    editbox:Hide()
    _RecycleWidget(editbox, active_editboxes, editbox_heap)
    editbox:SetParent(nil)
end

local function _ReleaseDialog(dialog)
    dialog.delegate = nil
    dialog.data = nil

    if dialog.editbox then
        _ReleaseEditBox(dialog.editbox)
        dialog.editbox = nil
    end

    if dialog.checkbox then
        _ReleaseCheckBox(dialog.checkbox)
        dialog.checkbox = nil
    end
    _RecycleWidget(dialog, active_dialogs, dialog_heap)
    _RefreshDialogAnchors()
end

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

if not lib.hooked_onhide then
    _G.hooksecurefunc("StaticPopup_OnHide", function()
        _RefreshDialogAnchors()

        if #delegate_queue > 0 then
            local delegate
            repeat
                delegate = _ProcessQueue()
            until not delegate
        end
    end)
    lib.hooked_onhide = true
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
        table.wipe(dialogs_to_release)

        for index = 1, #active_dialogs do
            local dialog = active_dialogs[index]

            if dialog.delegate.hide_on_escape then
                dialogs_to_release[dialog] = true
            end
        end

        for dialog in pairs(dialogs_to_release) do
            local delegate = dialog.delegate

            if delegate.OnCancel and not delegate.cancel_ignores_escape then
                delegate.OnCancel(dialog)
            end
            dialog:Hide()
        end

        if #delegate_queue > 0 then
            local delegate
            repeat
                delegate = _ProcessQueue()
            until not delegate
        end
    end)
    lib.hooked_escape_pressed = true
end

local function CheckBox_OnClick(checkbox, mouse_button, down)
    local dialog = checkbox:GetParent()
    local on_click = dialog.delegate.checkbox.on_click

    if on_click then
        on_click(checkbox, mouse_button, down, dialog.data)
    end
end

local function _AcquireCheckBox(parent)
    local checkbox = table.remove(checkbox_heap)

    if not checkbox then
        checkbox = _G.CreateFrame("CheckButton", ("%s_CheckBox%d"):format(MAJOR, #active_checkboxes + 1), _G.UIParent, "UICheckButtonTemplate")
        checkbox:SetScript("OnClick", CheckBox_OnClick)
    end
    active_checkboxes[#active_checkboxes + 1] = checkbox

    checkbox.text:SetText(parent.delegate.checkbox.label or "")
    checkbox:SetParent(parent)
    checkbox:SetPoint("BOTTOMLEFT", 10, 10)
    checkbox:Show()
    return checkbox
end

local function EditBox_OnEnterPressed(editbox)
    if not editbox.autoCompleteParams or not _G.AutoCompleteEditBox_OnEnterPressed(editbox) then
        local dialog = editbox:GetParent()
        local on_enter_pressed = dialog.delegate.editbox.on_enter_pressed

        if on_enter_pressed then
            on_enter_pressed(editbox, dialog.data)
        end
    end
end

local function EditBox_OnEscapePressed(editbox)
    local dialog = editbox:GetParent()
    local on_escape_pressed = dialog.delegate.editbox.on_escape_pressed

    if on_escape_pressed then
        on_escape_pressed(editbox, dialog.data)
    end
end

local function EditBox_OnTextChanged(editbox, user_input)
    if not editbox.autoCompleteParams or not _G.AutoCompleteEditBox_OnTextChanged(editbox, user_input) then
        local dialog = editbox:GetParent()
        local on_text_changed = dialog.delegate.editbox.on_text_changed

        if on_text_changed then
            on_text_changed(editbox, dialog.data)
        end
    end
end

local function _AcquireEditBox(parent)
    local editbox = table.remove(editbox_heap)

    if not editbox then
        local editbox_name = ("%s_EditBox%d"):format(MAJOR, #active_editboxes + 1)

        editbox = _G.CreateFrame("EditBox", editbox_name, _G.UIParent, "AutoCompleteEditBoxTemplate")
        editbox:SetWidth(130)
        editbox:SetHeight(32)
        editbox:SetFontObject("ChatFontNormal")

        local left = editbox:CreateTexture(("%sLeft"):format(editbox_name), "BACKGROUND")
        left:SetTexture([[Interface\ChatFrame\UI-ChatInputBorder-Left2]])
        left:SetWidth(32)
        left:SetHeight(32)
        left:SetPoint("LEFT", -10, 0)

        local right = editbox:CreateTexture(("%sRight"):format(editbox_name), "BACKGROUND")
        right:SetTexture([[Interface\ChatFrame\UI-ChatInputBorder-Right2]])
        right:SetWidth(32)
        right:SetHeight(32)
        right:SetPoint("RIGHT", 10, 0)

        local mid = editbox:CreateTexture(("%sMid"):format(editbox_name), "BACKGROUND")
        mid:SetTexture([[Interface\ChatFrame\UI-ChatInputBorder-Mid2]])
        mid:SetHeight(32)
        mid:SetPoint("TOPLEFT", left, "TOPRIGHT", 0, 0)
        mid:SetPoint("TOPRIGHT", right, "TOPLEFT", 0, 0)

        editbox:SetScript("OnEnterPressed", EditBox_OnEnterPressed)
        editbox:SetScript("OnEscapePressed", EditBox_OnEscapePressed)
        editbox:SetScript("OnTextChanged", EditBox_OnTextChanged)
    end
    active_editboxes[#active_editboxes + 1] = editbox

    editbox.addHighlightedText = true

    editbox:SetParent(parent)
    editbox:SetWidth(parent.delegate.editbox.width or DEFAULT_EDITBOX_WIDTH)
    editbox:SetPoint("TOP", parent.text, "BOTTOM", 0, -8)

    editbox:SetAutoFocus(parent.delegate.editbox.auto_focus)
    editbox:SetMaxLetters(parent.delegate.editbox.max_letters or 0)
    editbox:SetMaxBytes(parent.delegate.editbox.max_bytes or 0)
    editbox:SetText(parent.delegate.editbox.text or "")

    editbox:Show()
    return editbox
end

local function Button_OnClick(button, mouse_button, down)
    local dialog = button:GetParent()
    local on_click = dialog.delegate.buttons[button:GetID()].on_click

    if on_click then
        on_click(button, mouse_button, down, dialog.data)
    end
end

local function _AcquireButton(parent, index)
    local button = table.remove(button_heap)

    if not button then
        local button_name = ("%s_Button%d"):format(MAJOR, #active_buttons + 1)
        button = _G.CreateFrame("Button", button_name, _G.UIParent)
        button:SetWidth(128)
        button:SetHeight(21)

        button:SetNormalTexture([[Interface\Buttons\UI-DialogBox-Button-Up]])
        button:GetNormalTexture():SetTexCoord(0, 1, 0, 0.71875)

        button:SetPushedTexture([[Interface\Buttons\UI-DialogBox-Button-Down]])
        button:GetPushedTexture():SetTexCoord(0, 1, 0, 0.71875)

        button:SetDisabledTexture([[Interface\Buttons\UI-DialogBox-Button-Disabled]])
        button:GetDisabledTexture():SetTexCoord(0, 1, 0, 0.71875)

        button:SetHighlightTexture([[Interface\Buttons\UI-DialogBox-Button-Highlight]], "ADD")
        button:GetHighlightTexture():SetTexCoord(0, 1, 0, 0.71875)

        button:SetScript("OnClick", Button_OnClick)
    end
    active_buttons[#active_buttons + 1] = button

    button:SetText(parent.delegate.buttons[index].text or "")
    button:SetParent(parent)
    button:SetID(index)

    if index == 1 then
    elseif index == 2 then
    elseif index == 3 then
    end
    button:Show()
    return button
end

local function _BuildDialog(delegate, ...)
    local data = ...
    local dialog_text = delegate.text

    if not dialog_text or dialog_text == "" then
        error("Dialog text required.", 3)
    end

    if #active_dialogs == MAX_DIALOGS then
        if not queued_delegates[delegate] then
            delegate_queue[#delegate_queue + 1] = delegate
            queued_delegates[delegate] = data or ""
        end
        return
    end
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
    dialog.delegate = delegate
    dialog.data = data
    dialog.text:SetText(dialog_text)

    if delegate.buttons then
        dialog.buttons = {}

        for index = 1, MAX_BUTTONS do
            local button = delegate.buttons[index]

            if not button then
                break
            end

            if button.text and button.on_click then
                table.insert(dialog.buttons, _AcquireButton(dialog, index))
            end
        end
    end

    if delegate.editbox then
        dialog.editbox = _AcquireEditBox(dialog)
    end

    if delegate.checkbox then
        dialog.checkbox = _AcquireCheckBox(dialog)
    end
    dialog:Resize()
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
    local delegate = dialog.delegate

    if delegate.sound then
        _G.PlaySound(delegate.sound)
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
    return dialog
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

function dialog_prototype:Resize()
    local delegate = self.delegate
    local width = delegate.width or DEFAULT_DIALOG_WIDTH
    local height = delegate.height or DEFAULT_DIALOG_HEIGHT

    -- Static size ignores widgets for resizing purposes.
    if delegate.static_size then
        if width > 0 then
            self:SetWidth(width)
        end

        if height > 0 then
            self:SetHeight(height)
        end
        return
    end
    height = 32 + self.text:GetHeight()

    if self.buttons then
        height = height + 8 + self.buttons[1]:GetHeight()
    end

    if self.editbox then
        height = height + self.editbox:GetHeight()
    end

    if self.checkbox then
        height = height + self.checkbox:GetHeight()
    end

    if #self.buttons == MAX_BUTTONS then
        width = 440
    elseif delegate.editbox.width and delegate.editbox.width > 260 then
        width = width + (delegate.editbox.width - 260)
    end

    if width > 0 then
        self:SetWidth(width)
    end

    if height > 0 then
        self:SetHeight(height)
    end
end
