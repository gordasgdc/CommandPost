--------------------------------------------------------------------------------
--------------------------------------------------------------------------------
--                   C  O  M  M  A  N  D  P  O  S  T                          --
--------------------------------------------------------------------------------
--------------------------------------------------------------------------------

--- === plugins.finalcutpro.timeline.commandsetactions ===
---
--- Adds Actions to the Console for triggering Final Cut Pro shortcuts as defined in the Command Set files.

--------------------------------------------------------------------------------
--
-- EXTENSIONS:
--
--------------------------------------------------------------------------------
local log				= require("hs.logger").new("commandsetactions")

local timer				= require("hs.timer")

local dialog			= require("cp.dialog")
local fcp				= require("cp.apple.finalcutpro")
local plist				= require("cp.plist")

--------------------------------------------------------------------------------
--
-- CONSTANTS:
--
--------------------------------------------------------------------------------
local GROUP 			= "fcpx"

--------------------------------------------------------------------------------
--
-- THE MODULE:
--
--------------------------------------------------------------------------------
local mod = {}

function mod.init()

	--------------------------------------------------------------------------------
	-- Add Action Handler:
	--------------------------------------------------------------------------------
	mod._handler = mod._actionmanager.addHandler(GROUP .. "_shortcuts", GROUP)
		:onChoices(function(choices)
			local fcpPath = fcp:getPath()
			local currentLanguage = fcp:currentLanguage()
			if fcpPath and currentLanguage then

				local namePath 			= fcpPath .. "/Contents/Resources/" .. currentLanguage .. ".lproj/NSProCommandNames.strings"
				local descriptionPath 	= fcpPath .. "/Contents/Resources/" .. currentLanguage .. ".lproj/NSProCommandDescriptions.strings"

				local nameData 			= plist.fileToTable(namePath)
				local descriptionData 	= plist.fileToTable(descriptionPath)

				if nameData and descriptionData then
					for id, name in pairs(nameData) do
						local subText = descriptionData[id] or i18n("commandEditorShortcut")
						choices
							:add(name)
							:subText(subText)
							:params(id)
							:id(id)
					end
				end
			end
		end)
		:onExecute(function(action)
			local result = fcp:performShortcut(action)
			if not result then
				dialog.displayMessage(i18n("shortcutCouldNotBeTriggered"), i18n("ok"))
			end
		end)
		:onActionId(function(action)
			return "fcpxShortcuts"
		end)

	--------------------------------------------------------------------------------
	-- Reset the handler choices when the Final Cut Pro language changes:
	--------------------------------------------------------------------------------
	fcp.currentLanguage:watch(function(value)
		mod._handler:reset()
		timer.doAfter(0.01, function() mod._handler.choices:update() end)
	end)

	return mod
end

--------------------------------------------------------------------------------
--
-- THE PLUGIN:
--
--------------------------------------------------------------------------------
local plugin = {
	id = "finalcutpro.timeline.commandsetactions",
	group = "finalcutpro",
	dependencies = {
		["core.action.manager"]					= "actionmanager",
	}
}

--------------------------------------------------------------------------------
-- INITIALISE PLUGIN:
--------------------------------------------------------------------------------
function plugin.init(deps)
	mod._actionmanager = deps.actionmanager
	return mod.init()
end

return plugin