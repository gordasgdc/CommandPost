--------------------------------------------------------------------------------
--------------------------------------------------------------------------------
--                H A C K S     S H O R T C U T S     P L U G I N             --
--------------------------------------------------------------------------------
--------------------------------------------------------------------------------

--- === plugins.finalcutpro.hacks.shortcuts ===
---
--- Plugin that allows the user to customise the CommandPost shortcuts
--- via the Final Cut Pro Command Editor.

--------------------------------------------------------------------------------
--
-- EXTENSIONS:
--
--------------------------------------------------------------------------------
local log			= require("hs.logger").new("shortcuts")
local inspect		= require("hs.inspect")

local fs			= require("hs.fs")

local commands		= require("cp.commands")
local config		= require("cp.config")
local dialog		= require("cp.dialog")
local fcp			= require("cp.apple.finalcutpro")
local tools			= require("cp.tools")
local prop			= require("cp.prop")

local v				= require("semver")

--------------------------------------------------------------------------------
--
-- CONSTANTS:
--
--------------------------------------------------------------------------------
local PRIORITY 		= 5
local CP_SHORTCUT   = "cpOpenCommandEditor"

local COMMANDS_FILE			= "NSProCommands.plist"
local COMMAND_GROUPS_FILE	= "NSProCommandGroups.plist"

local FCP_RESOURCES_PATH		= "/Contents/Resources/"

--------------------------------------------------------------------------------
--
-- THE MODULE:
--
--------------------------------------------------------------------------------
local mod = {}

-- Returns the path to the specified resource inside FCPX, or `nil` if it cannot be found.
local function resourcePath(resourceName)
	local fcpPath = fcp:getPath()
	if fcpPath then
		return fs.pathToAbsolute(fcpPath .. FCP_RESOURCES_PATH .. tostring(resourceName))
	else
		return nil
	end
end

-- Returns the path to the most recent version of the specified file inside the plugin, or `nil` if it can't be found.
local function hacksPath(resourceName)
	assert(type(resourceName) == "string", "Expected argument #1 to be a string")
	if mod.commandSetsPath and fcp:isInstalled() then
		local ver = v(fcp:getVersion())
		local path = nil
		local target = string.format("%s/%s/%s", mod.commandSetsPath, ver, resourceName)
		return fs.pathToAbsolute(target)
	else
		return nil
	end
end

local function hacksOriginalPath(resourceName)
	assert(type(resourceName) == "string", "Expected argument #1 to be a string")
	return hacksPath("original/"..resourceName)
end

local function hacksModifiedPath(resourceName)
	assert(type(resourceName) == "string", "Expected argument #1 to be a string")
	return hacksPath("modified/"..resourceName)
end

-- Returns `true` if the files at the specified paths are the same.
local function filesMatch(path1, path2)
	if path1 and path2 then
		local attr1, attr2 = fs.attributes(path1), fs.attributes(path2)
		return attr1			and		attr2
		   and attr1.size		==		attr2.size
		   and attr1.mode		==		attr2.mode
   else
	   return false
   end
end

-- copyHacksFiles(batch, sourcePath) -> nil
-- Function
-- Adds commands to copy Hacks Shortcuts files into FCPX.
--
-- Parameters:
-- * `batch`		- The table of batch commands to be executed.
-- * `sourcePath`	- A function that will return the absolute source path to copy from.
local function copyHacksFiles(batch, sourcePath)
	
	local copy = "cp -f '%s' '%s'"
	local mkdir = "mkdir '%s'"

	table.insert(batch, copy:format( sourcePath(COMMAND_GROUPS_FILE), resourcePath(COMMAND_GROUPS_FILE) ) )
	table.insert(batch, copy:format( sourcePath(COMMANDS_FILE), resourcePath(COMMAND_GROUPS_FILE) ) )

	local finalCutProLanguages = fcp:getSupportedLanguages()

	for _, whichLanguage in ipairs(finalCutProLanguages) do
		local langPath = whichLanguage .. ".lproj/"
		local whichDirectory = resourcePath(langPath)
		if not tools.doesDirectoryExist(whichDirectory) then
			table.insert(batch, mkdir:format(whichDirectory))
		end

		table.insert(batch, copy:format(sourcePath(langPath .. "Default.commandset"), resourcePath(langPath .. "Default.commandset")))
		table.insert(batch, copy:format(sourcePath(langPath .. "NSProCommandDescriptions.strings"), resourcePath(langPath .. "NSProCommandDescriptions.strings")))
		table.insert(batch, copy:format(sourcePath(langPath .. "NSProCommandNames.strings"), resourcePath(langPath .. "NSProCommandNames.strings")))
	end	
end

--------------------------------------------------------------------------------
-- ENABLE HACKS SHORTCUTS:
--------------------------------------------------------------------------------
local function updateHacksShortcuts(install)

	log.df("Updating Hacks Shortcuts...")

	if not mod.supported() then
		dialog.displayMessage("No supported versions of Final Cut Pro were detected.")
		return false
	end

	local batch = {}

	--------------------------------------------------------------------------------
	-- Always copy the originals back into FCPX, just in case the user has
	-- previously removed them or used an old version of CommandPost or FCPX Hacks:
	--------------------------------------------------------------------------------
	
	copyHacksFiles(batch, hacksOriginalPath)

	--------------------------------------------------------------------------------
	-- Only then do we copy the 'modified' files...
	--------------------------------------------------------------------------------
	if install then
		copyHackFiles(batch, hacksModifiedPath)
	end
	
	--------------------------------------------------------------------------------
	-- Execute the instructions.
	--------------------------------------------------------------------------------
	local result = tools.executeWithAdministratorPrivileges(batch, false)

	if result == false then
		-- Cancel button pressed:
		return false
	end

	if type(result) == "string" then
		log.ef("The following error(s) occurred: %s", result)
		return false
	end

	-- Success!
	return true

end

--------------------------------------------------------------------------------
-- UPDATE FINAL CUT PRO COMMANDS:
-- Switches to or from having CommandPost commands editible inside FCPX.
--------------------------------------------------------------------------------
local function updateFCPXCommands(enable, silently)
	
	if not silently then
		--------------------------------------------------------------------------------
		-- Check if the user really wants to do this
		--------------------------------------------------------------------------------
		local prompt = enable and i18n("hacksEnabling") or i18n("hacksDisabling")

		local running = fcp:isRunning()
		if running then
			prompt = prompt .. " " .. i18n("hacksShortcutAdminPassword")
		else
			prompt = prompt .. " " .. i18n("hacksShortcutsRestart")
		end
	
		prompt = prompt .. " " .. i18n("doYouWantToContinue")
	
		if not dialog.displayYesNoQuestion(prompt) then
			return false
		end
	end

	--------------------------------------------------------------------------------
	-- Let's do it!
	--------------------------------------------------------------------------------
	if not updateHacksShortcuts(enable) then
		return false
	end

	--------------------------------------------------------------------------------
	-- Restart Final Cut Pro:
	--------------------------------------------------------------------------------
	if running and not fcp:restart() then
		--------------------------------------------------------------------------------
		-- Failed to restart Final Cut Pro:
		--------------------------------------------------------------------------------
		dialog.displayErrorMessage(i18n("failedToRestart"))
	end

	return true
end

--------------------------------------------------------------------------------
-- APPLY SHORTCUTS:
--------------------------------------------------------------------------------
local function applyShortcuts(commands, commandSet)
	commands:deleteShortcuts()
	if commandSet ~= nil then
		for id, cmd in pairs(commands:getAll()) do
			local shortcuts = fcp:getCommandShortcuts(id)
			if shortcuts ~= nil then
				cmd:setShortcuts(shortcuts)
			end
		end
		return true
	else
		return false
	end
end

--------------------------------------------------------------------------------
-- APPLY COMMAND SET SHORTCUTS:
--------------------------------------------------------------------------------
local function applyCommandSetShortcuts()
	local commandSet = fcp:getActiveCommandSet(true)

	log.df("Applying FCPX Shortcuts to global commands...")
	applyShortcuts(mod.globalCmds, commandSet)
	log.df("Applying FCPX Shortcuts to FCPX commands...")
	applyShortcuts(mod.fcpxCmds, commandSet)

	mod.globalCmds:watch({
		add		= function(cmd) applyCommandShortcut(cmd, fcp:getActiveCommandSet()) end,
	})
	mod.fcpxCmds:watch({
		add		= function(cmd) applyCommandShortcut(cmd, fcp:getActiveCommandSet()) end,
	})
end

--- plugins.finalcutpro.hacks.shortcuts.supported <cp.prop: boolean; read-only>
--- Constant
--- A property that returns `true` if the a supported version of FCPX is installed.
mod.supported = prop(function()
	return hacksModifiedPath("") ~= nil
end)

--- plugins.finalcutpro.hacks.shortcuts.installed <cp.prop: boolean; read-only>
--- Constant
--- A property that returns `true` if the FCPX Hacks Shortcuts are currently installed in FCPX.
mod.installed = prop(function()
	return filesMatch(resourcePath(COMMAND_GROUPS_FILE), hacksModifiedPath(COMMAND_GROUPS_FILE))
end)

--- plugins.finalcutpro.hacks.shortcuts.uninstalled <cp.prop: boolean; read-only>
--- Constant
--- A property that returns `true` if the FCPX Hacks Shortcuts are currently installed in FCPX.
mod.uninstalled = prop(function()
	return not mod.supported() or filesMatch(resourcePath(COMMAND_GROUPS_FILE), hacksOriginalPath(COMMAND_GROUPS_FILE))
end)

--- plugins.finalcutpro.hacks.shortcuts.uninstalled <cp.prop: boolean; read-only>
--- Constant
--- A property that returns `true` if the shortcuts are neither original or installed correctly.
mod.outdated = mod.supported:AND(mod.installed:NOT()):AND(mod.uninstalled:NOT()):watch(function(outdated)
	if outdated then
		-- TODO: Prompt the user to chose to either update or reset the shortcuts.
		log.wf("The Hacks Shortcuts are outdated.")
	end
end)

--- plugins.finalcutpro.hacks.shortcuts.uninstall(silently) -> none
--- Function
--- Uninstalls the Hacks Shortcuts, if they have been installed
---
--- Parameters:
---  * `silently`	- (optional) If `true`, the user will not be prompted first.
---
--- Returns:
---  * `true` if successful.
---
--- Notes:
---  * Used by Trash Preferences menubar command.
function mod.uninstall(silently)
	return updateFCPXCommands(false, silently)
end

--- plugins.finalcutpro.hacks.shortcuts.install(silently) -> none
--- Function
--- Installs the Hacks Shortcuts.
---
--- Parameters:
---  * `silently`	- (optional) If `true`, the user will not be prompted first.
---
--- Returns:
---  * `true` if successful.
function mod.install(silently)
	return updateFCPXCommands(true, silently)
end

--- plugins.finalcutpro.hacks.shortcuts.editCommands() -> none
--- Function
--- Launch the Final Cut Pro Command Editor
---
--- Parameters:
---  * None
---
--- Returns:
---  * None
function mod.editCommands()
	fcp:launch()
	fcp:commandEditor():show()
end

--- plugins.finalcutpro.hacks.shortcuts.update() -> none
--- Function
--- Read shortcut keys from the Final Cut Pro Preferences.
---
--- Parameters:
---  * None
---
--- Returns:
---  * None
function mod.update()
	if mod.installed:update() then
		log.df("Applying FCPX Command Editor Shortcuts")
		applyCommandSetShortcuts()
	end
end

--- plugins.finalcutpro.hacks.shortcuts.init() -> none
--- Function
--- Initialises the module.
---
--- Parameters:
---  * None
---
--- Returns:
---  * None
function mod.init()
	log.df("Initialising shortcuts...")
	--------------------------------------------------------------------------------
	-- Check if we need to update the Final Cut Pro Shortcut Files:
	--------------------------------------------------------------------------------

	mod.update()
end

--------------------------------------------------------------------------------
--
-- THE PLUGIN:
--
--------------------------------------------------------------------------------
local plugin = {
	id				= "finalcutpro.hacks.shortcuts",
	group			= "finalcutpro",
	dependencies	= {
		["core.menu.top"] 									= "top",
		["core.menu.helpandsupport"] 						= "helpandsupport",
		["core.commands.global"]							= "globalCmds",
		["finalcutpro.commands"]							= "fcpxCmds",
		["core.preferences.panels.shortcuts"]				= "shortcuts",
		["finalcutpro.preferences.panels.finalcutpro"]		= "prefs",
		["core.welcome.manager"] 							= "welcome",
	}
}

--------------------------------------------------------------------------------
-- INITIALISE PLUGIN:
--------------------------------------------------------------------------------
function plugin.init(deps, env)

	mod.globalCmds 	= deps.globalCmds
	mod.fcpxCmds	= deps.fcpxCmds
	mod.shortcuts	= deps.shortcuts

	mod.commandSetsPath = env:pathToAbsolute("/commandsets/")

	local welcome = deps.welcome

	--------------------------------------------------------------------------------
	-- ENABLE INTERFACE:
	--------------------------------------------------------------------------------
	welcome.enableInterfaceCallback:new("hacksshortcuts", function()

		--------------------------------------------------------------------------------
		-- Initialise Hacks Shortcuts:
		--------------------------------------------------------------------------------
		mod.init()

		--------------------------------------------------------------------------------
		-- Enable Commands:
		--------------------------------------------------------------------------------
		local allGroups = commands.groupIds()
		for i, v in ipairs(allGroups) do
			commands.group(v):enable()
		end

	end)

	--------------------------------------------------------------------------------
	-- DISABLE INTERFACE:
	--------------------------------------------------------------------------------
	welcome.disableInterfaceCallback:new("hacksshortcuts", function()

		--------------------------------------------------------------------------------
		-- Disable Commands:
		--------------------------------------------------------------------------------
		--log.df("Disable Commands")
		local allGroups = commands.groupIds()
		for i, v in ipairs(allGroups) do
			commands.group(v):disable()
		end

	end)

	--------------------------------------------------------------------------------
	-- Add the menu item to the top section:
	--------------------------------------------------------------------------------
	deps.top:addItem(PRIORITY, function()
		if fcp:isInstalled()  then
			return { title = i18n("openCommandEditor"), fn = mod.editCommands, disabled = not fcp:isRunning() }
		end
	end)

	--------------------------------------------------------------------------------
	-- Add Commands:
	--------------------------------------------------------------------------------
	deps.fcpxCmds:add("cpOpenCommandEditor")
		:titled(i18n("openCommandEditor"))
		:whenActivated(mod.editCommands)

	--------------------------------------------------------------------------------
	-- Add Preferences:
	--------------------------------------------------------------------------------
	if deps.prefs.panel then
		deps.prefs.panel:addHeading(50, i18n("keyboardShortcuts"))

		:addCheckbox(51,
			{
				label		= i18n("enableHacksShortcuts"),
				onchange	= function(_,params)
					mod.enabled(params.checked)
				end,
				checked=mod.enabled
			}
		)
	end

	return mod

end

return plugin