function init()
	connect(g_game, {
		onGameStart = online,
		onGameEnd = offline
	})

	if not Options.loadData("/settings/clientoptions.json") then
		Options.createDefaultSettings()
	end

	if not Options.array then
		g_logger.error("Failed to load clientoptions.json")
		return true
	end

	Options.profiles = Options.array["profiles"]
	
	-- Force insert monk
	if Options.profiles then
		if not Options.array["hotkeyOptions"]["hotkeySets"]["Monk"] then
			Options.array["hotkeyOptions"]["hotkeySets"]["Monk"] = Options.getDefaultProfile("Monk")
			table.insert(Options.profiles, "Monk")
		end
	end

	Options.pinnedCharacters = Options.array["pinnedCharacters"]
	Options.hotkeySets = Options.array["hotkeyOptions"]["hotkeySets"]
	Options.currentHotkeySetName = Options.array["hotkeyOptions"]["currentHotkeySetName"]
	Options.currentHotkeySet = Options.array["hotkeyOptions"]["hotkeySets"][Options.currentHotkeySetName]

	if not Options.profiles then
		Options.profiles = {}
		for index, k in pairs(Options.hotkeySets) do
			table.insert(Options.profiles, index)
		end
	end

	if not Options.currentHotkeySet then
		Options.array["hotkeyOptions"]["currentHotkeySetName"] = Options.profiles[1]
		Options.currentHotkeySetName = Options.profiles[1]
		Options.currentHotkeySet = Options.array["hotkeyOptions"]["hotkeySets"][Options.profiles[1]]
	end

	Options.actionBarOptions = Options.currentHotkeySet["actionBarOptions"]
	Options.actionBarMappings = Options.actionBarOptions["mappings"]

	Options.clientOptions = Options.array["options"]
	if type(Options.clientOptions) ~= "table" then
		Options.clientOptions = {}
		Options.array["options"] = Options.clientOptions
	end

	-- Bottom bar
	for i = 1, 3 do
		local show = Options.clientOptions["actionBarShowBottom" .. i]
		local locked = Options.clientOptions["actionBarBottomLocked"]
		Options.actionBar[#Options.actionBar + 1] = {isVisible = show, isLocked = locked}
	end

	-- Left bar
	for i = 1, 3 do
		local show = Options.clientOptions["actionBarShowLeft" .. i]
		local locked = Options.clientOptions["actionBarLeftLocked"]
		Options.actionBar[#Options.actionBar + 1] = {isVisible = show, isLocked = locked}
	end

	-- Right bar
	for i = 1, 3 do
		local show = Options.clientOptions["actionBarShowRight" .. i]
		local locked = Options.clientOptions["actionBarRightLocked"]
		Options.actionBar[#Options.actionBar + 1] = {isVisible = show, isLocked = locked}
	end

	-- load common
	Options.chatOptions = Options.array["chatOptions"]
	Options.isChatOnEnabled = Options.chatOptions["chatModeOn"]

	Options.validateAssignedHotkeys()
end

function terminate()
  disconnect(g_game, {
    onGameStart = online,
    onGameEnd = offline
  })
end

function getGeneralHotkeyCombo(saveKey)
	if not Options.currentHotkeySet then
		return nil
	end

	local chatType = "chatOff"
	if modules.game_console and modules.game_console.isChatEnabled and modules.game_console.isChatEnabled() then
		chatType = "chatOn"
	elseif Options.isChatOnEnabled then
		chatType = "chatOn"
	end

	local hotkeys = Options.currentHotkeySet[chatType]
	if type(hotkeys) ~= "table" then
		return nil
	end

	local primaryKey = saveKey .. "_1"
	local secondaryKey = saveKey .. "_2"
	local secondaryCombo = nil

	for _, data in pairs(hotkeys) do
		local action = data["actionsetting"] and data["actionsetting"]["action"]
		if action == saveKey or action == primaryKey then
			return data["keysequence"]
		end

		if action == secondaryKey and not secondaryCombo then
			secondaryCombo = data["keysequence"]
		end
	end

	return secondaryCombo
end

local function getEmptyOptionsTab()
	return {
		onClick = function()
		end
	}, {
		recursiveGetChildById = function()
			return nil
		end
	}
end

function getOptionsTab(id)
	if id == "controls" or id == "general" or id == "actionbarhotkeys" or id == "customhotkeys" or
		id == "interface" or id == "hud" or id == "voip" or id == "console" or id == "serverlog" or
		id == "gamewindow" or id == "actionbars" or id == "graphics" or id == "effects" or
		id == "misc" or id == "gameplay" or id == "help" then
		return getEmptyOptionsTab()
	end

	return nil, nil
end

function online()
	local benchmark = g_clock.millis()
	-- create character dir
	local player = g_game.getLocalPlayer()
	if not g_resources.directoryExists("/characterdata/".. player:getId() .."/") then
		g_resources.makeDir("/characterdata/".. player:getId() .."/")
	end
	Options.applyCharacterHotkeyProfile(player)
	consoleln("Options loaded in " .. (g_clock.millis() - benchmark) / 1000 .. " seconds.")
end

function offline()
	Options.saveData()
end

function Options.createDefaultSettings()
	if not g_resources.directoryExists("/settings/") then
		g_resources.makeDir("/settings/")
	end

	Options.loadData("/data/json/default-options.json")
end

function Options.getDefaultProfile(name)
	local file = "/data/json/default-options.json"
	if g_resources.fileExists(file) then
		local status, result = pcall(function()
			return json.decode(g_resources.readFileContents(file))
		end)

		if not status then
			return false
		end
		return result["hotkeyOptions"]["hotkeySets"][name]
	end
end

-- json handlers
function Options.loadData(file)
	if g_resources.fileExists(file) then
		local status, result = pcall(function()
			return json.decode(g_resources.readFileContents(file))
		end)

		if not status then
			return false
		end

		Options.array = result
		return true
	end
	return false
end

function Options.saveData()
	Options.validateOpenChannels()
	local file = "/settings/clientoptions.json"
	local status, result = pcall(function() return json.encode(Options.array) end)
	if not status then
		return onError("Error while saving general options settings. Data won't be saved. Details: " .. result)
	end

	if result:len() > 100 * 1024 * 1024 then
	  return onError("Something went wrong, file is above 100MB, won't be saved")
	end

	g_resources.writeFileContents(file, result)
end

local function normalizeProfilePart(value, fallback)
	value = tostring(value or fallback or ""):gsub("[%c%z]", ""):gsub("^%s+", ""):gsub("%s+$", "")
	if value == "" then
		value = tostring(fallback or "Unknown")
	end
	return value
end

function Options.getCharacterHotkeyProfileName(player)
	player = player or g_game.getLocalPlayer()
	if not player then
		return nil
	end

	local name = normalizeProfilePart(player:getName(), "Character")
	local vocationName = "None"
	if player.getVocationName then
		vocationName = normalizeProfilePart(player:getVocationName(), "None")
	elseif player.getVocation then
		vocationName = normalizeProfilePart(g_game.getVocationNameBase(player:getVocation()), "None")
	end

	return string.format("%s - %s", name, vocationName)
end

function Options.ensureHotkeyProfile(profileName, sourceProfile)
	if not profileName or not Options.array or not Options.array["hotkeyOptions"] then
		return false
	end

	Options.array["hotkeyOptions"]["hotkeySets"] = Options.array["hotkeyOptions"]["hotkeySets"] or {}
	Options.hotkeySets = Options.array["hotkeyOptions"]["hotkeySets"]
	Options.profiles = Options.profiles or Options.array["profiles"] or {}
	Options.array["profiles"] = Options.profiles

	if Options.hotkeySets[profileName] then
		if not table.find(Options.profiles, profileName) then
			table.insert(Options.profiles, profileName)
		end
		return true
	end

	local template = sourceProfile and Options.hotkeySets[sourceProfile] or nil
	if not template then
		local player = g_game.getLocalPlayer()
		local vocationName = player and player.getVocationName and player:getVocationName() or nil
		template = vocationName and Options.hotkeySets[vocationName] or nil
		if not template and player and player.getVocation and g_game.getVocationNameBase then
			template = Options.hotkeySets[g_game.getVocationNameBase(player:getVocation())]
		end
	end
	if not template then
		template = Options.currentHotkeySet or Options.getDummyProfile()
	end
	if not template then
		return false
	end

	Options.hotkeySets[profileName] = table.recursivecopy(template)
	table.insert(Options.profiles, profileName)
	return true
end

function Options.applyCharacterHotkeyProfile(player)
	if not Options.array or not Options.array["hotkeyOptions"] or not Options.array["hotkeyOptions"]["hotkeySets"] then
		return false
	end

	local profileName = Options.getCharacterHotkeyProfileName(player)
	if not profileName then
		return false
	end

	if not Options.ensureHotkeyProfile(profileName) then
		return false
	end

	if Options.currentHotkeySetName ~= profileName then
		Options.changeHotkeyProfile(profileName)
	end

	if KeyBinds and KeyBinds.setupAndReset then
		local chatType = Options.isChatOnEnabled and "chatOn" or "chatOff"
		KeyBinds:setupAndReset(Options.currentHotkeySetName, chatType)
	end

	Options.saveData()
	return true
end

function Options.getDummyProfile()
	local file = "/data/json/default-options.json"
	if g_resources.fileExists(file) then
		local status, result = pcall(function()
			return json.decode(g_resources.readFileContents(file))
		end)

		if not status then
			return false
		end
		return result["DummyProfile"]
	end
end

function Options.getDefaultSideButtons()
	local file = "/data/json/default-options.json"
	if g_resources.fileExists(file) then
		local status, result = pcall(function()
			return json.decode(g_resources.readFileContents(file))
		end)

		if not status then
			return false
		end
		return result["controlButtonsOptions"]
	end
end

local replace = {
	["Ins"] = "Insert",
	["Del"] = "Delete",
	["PgUp"] = "PageUp",
	["PgDown"] = "PageDown",
	["Num+1"] = "N1",
	["Num+2"] = "N2",
	["Num+3"] = "N3",
	["Num+4"] = "N4",
	["Num+5"] = "N5",
	["Num+6"] = "N6",
	["Num+7"] = "N7",
	["Num+8"] = "N8",
	["Num+9"] = "N9",
	["Num+0"] = "N0",
	["Return"] = "Enter",
	["Alt+Return"] = "Alt+Enter",
	["Shift+Return"] = "Shift+Enter",
	["Ctrl+Return"] = "Ctrl+Enter",
	["Alt+PgUp"] = "Alt+PageUp",
	["Alt+PgDown"] = "Alt+PageDown"
}

function Options.validateAssignedHotkeys()
	for _, j in pairs(Options.array["hotkeyOptions"]["hotkeySets"]) do
		for _, k in pairs(j) do

			local lastAction = ""
			local showMapFound = false
			for i, l in pairs(k) do
				if l["actionsetting"] and l["actionsetting"]["action"] then
					local action = l["actionsetting"]["action"]
					if lastAction == l["actionsetting"]["action"] then
						l["secondary"] = true
					end

					if action == "ChatModeTemporaryOn" then
						l["actionsetting"]["action"] = "ChatModeTemporaryOnEnter"
					end

					lastAction = action
				end

				if replace[l["keysequence"]] then
					l["keysequence"] = replace[l["keysequence"]]
				end

				if l["actionsetting"] and l["actionsetting"]["action"] and l["actionsetting"]["action"] == "MinimapShow" then
					showMapFound = true
				end

				if i == #k and not showMapFound then
					k[#k + 1] = {
						["actionsetting"] = { ["action"] = "MinimapShow" },
						["keysequence"] = "Alt+M"
					}
				end
			end
		end
	end
end
