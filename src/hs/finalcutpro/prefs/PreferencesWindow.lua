local log							= require("hs.logger").new("PrefsDlg")
local inspect						= require("hs.inspect")

local axutils						= require("hs.finalcutpro.axutils")
local just							= require("hs.just")

local PlaybackPanel					= require("hs.finalcutpro.prefs.PlaybackPanel")
local ImportPanel					= require("hs.finalcutpro.prefs.ImportPanel")

local PreferencesWindow = {}

PreferencesWindow.GROUP						= "_NS:9"

function PreferencesWindow:new(app)
	o = {_app = app}
	setmetatable(o, self)
	self.__index = self
	return o
end

function PreferencesWindow:app()
	return self._app
end

function PreferencesWindow:UI()
		local windowsUI = self:app():windowsUI()
		return windowsUI and self:_findWindowUI(windowsUI)
end

function PreferencesWindow:_findWindowUI(windows)
	for i,w in ipairs(windows) do
		if w:attributeValue("AXSubrole") == "AXDialog"
		and not w:attributeValue("AXModal")
		and w:attributeValue("AXTitle") ~= ""
		then
			-- Is a dialog and is not modal (Media Import is modal) and the title is not blank
			-- TODO: This also matches the Command Editor window...
			return w
		end
	end
	return nil
end


-- Returns the UI for the AXToolbar containing this panel's buttons
function PreferencesWindow:toolbarUI()
	local ax = self:UI()
	return ax and axutils.childWith(ax, "AXRole", "AXToolbar") or nil
end

-- Returns the UI for the AXGroup containing this panel's elements
function PreferencesWindow:groupUI()
	local ax = self:UI()
	local group = ax and axutils.childWith(ax, "AXIdentifier", PreferencesWindow.GROUP)
	-- The group conains another single group that contains the actual checkboxes, etc.
	return group and #group == 1 and group[1]
end


function PreferencesWindow:playbackPanel()
	if not self._playbackPanel then
		self._playbackPanel = PlaybackPanel:new(self)
	end
	return self._playbackPanel
end

function PreferencesWindow:importPanel()
	if not self._importPanel then
		self._importPanel = ImportPanel:new(self)
	end
	return self._importPanel
end

function PreferencesWindow:isShowing()
	return self:UI() ~= nil
end

--- Ensures the PreferencesWindow is showing
function PreferencesWindow:show()
	if not self:isShowing() then
		-- open the window
		if self:app():menuBar():select("Final Cut Pro", "Preferences…") then
			local ui = just.doUntil(function() return self:UI() end)
			return ui ~= nil
		end
	end
	return true
end

function PreferencesWindow:hide()
	local ax = self:UI()
	if ax then
		local closeBtn = axutils.childWith(ax, "AXSubrole", "AXCloseButton")
		if closeBtn then
			closeBtn:doPress()
			return true
		end
	end
	return false
end

return PreferencesWindow