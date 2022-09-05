local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local SoundService = game:GetService("SoundService")

-- TODO:
-- disable player resetting

local MS = require(ReplicatedStorage.Minesweeper)

local RequestRevealCellEvent = ReplicatedStorage.RequestRevealCell
local RequestFlagCellEvent = ReplicatedStorage.RequestFlagCell
local RevealCellEvent = ReplicatedStorage.RevealCell

local client = Players.LocalPlayer
local PlayerGUI = client.PlayerGui

local modifierMap = {
	[0] = "NONE",
	[1] = "FLAGLESS",
	[2] = "BOMB PARTY",
	[3] = "SHORT SIGHTED",
	[4] = "ZOOMIES",
}

local modifierColorMap = {
	[0] = "#8f8f8f",
	[1] = "#e51b25",
	[2] = "#ffa202",
	[3] = "#1ca4b0",
	[4] = "#0cb309",
}

local soundIndex = {
	reveal = {
		[0] = "rbxassetid://10788055346",
		[1] = "rbxassetid://10780001434",
		[2] = "rbxassetid://10780001505",
		[3] = "rbxassetid://10780001909",
		[4] = "rbxassetid://10780001707",
		[5] = "rbxassetid://10780001988",
		[6] = "rbxassetid://10780001799",
		[7] = "rbxassetid://10780001799",
		[8] = "rbxassetid://10780001799",
	},
	flag = "rbxassetid://10780002080",
	wrongFlag = "rbxassetid://10788373408",
	explode = "rbxassetid://10780001573",
}

local soundLibrary = {}

-- Creating sounds

for k, v0 in pairs(soundIndex) do
	if k == "reveal" then
		soundLibrary.reveal = {}

		for idx, v1 in pairs(v0) do
			local sound = Instance.new("Sound")
			sound.SoundId = v1
			soundLibrary.reveal[idx] = sound
		end
	else
		local sound = Instance.new("Sound")
		sound.SoundId = v0
		sound.Parent = PlayerGUI
		soundLibrary[k] = sound
	end
end

-- Creating UI

local topMenu = ReplicatedStorage.TopMenu:Clone()
topMenu.Parent = PlayerGUI

local bottomMenu = ReplicatedStorage.BottomMenu:Clone()
bottomMenu.Parent = PlayerGUI

local comboItem = bottomMenu:FindFirstChild("Combo", true):Clone()
bottomMenu:FindFirstChild("Combo", true):Destroy()

local function formatTime(t)
	t = math.max(t, 0)

	if t >= 60 then
		return string.format("%01i:%02i", t / 60, t % 60)
	end

	return string.format("%01i", t % 60)
end

local function renderCombo(combo, count, timeNow)
	local container = bottomMenu:FindFirstChild("ComboDisplay", true)
	local layout = bottomMenu:FindFirstChild("ComboUILayout", true)

	layout.CellSize = UDim2.new(1 / combo, -math.floor(0.5 + ((combo * 5) / combo)), 1, 0)

	for _, v in pairs(container:GetChildren()) do
		if v.Name == "Combo" then
			v:Destroy()
		end
	end

	for i = 1, combo do
		local item = comboItem:Clone()

		if count > 0 then
			count -= 1

			if combo == 1 then
				item.BackgroundColor3 = Color3.fromHSV(0, 0.7843137254, 1)
			else
				item.BackgroundColor3 =
					Color3.fromHSV(((i - 1) / (combo - 1)) * (math.min(combo, 20) / 20), 0.7843137254, 1)
			end
		else
			item.BackgroundColor3 = Color3.fromHex("#c3c3c3")
		end

		item.LayoutOrder = i
		item.Parent = container
	end

	local comboLabel = bottomMenu:FindFirstChild("ComboLabel", true)

	if comboLabel ~= nil then
		comboLabel.Text = "x" .. combo
		comboLabel.TextColor3 = Color3.fromHSV((timeNow % 2) / 2, math.min(0.7843, (combo - 1) / 10), 1)
	end
end

local function getBoardCell(x, y)
	local boardModel = workspace:FindFirstChild("Board")

	if boardModel == nil then
		return nil
	end

	for _, v in pairs(boardModel:GetChildren()) do
		if v:GetAttribute("x") == x and v:GetAttribute("y") == y then
			return v
		end
	end

	return nil
end

local function clearSelections()
	local boardModel = workspace:FindFirstChild("Board")

	if boardModel == nil then
		return nil
	end

	for _, v in pairs(boardModel:GetChildren()) do
		if v:FindFirstChild("HoverBox", true) then
			v:FindFirstChild("HoverBox", true).Visible = false
		end
	end

	return nil
end

local lastState = -1
local lastHitX
local lastHitY

local maxZoom = 40
local minZoom = -10
local cameraZoomCurrent = 10
local cameraZoomVelocity = 0
local cameraZoomTarget = 10

local combo = 1
local comboCount = 0
local scoreTarget = 0
local currentScore = 0
local scoreVelocity = 0
local scoreDelta = 0

local touchDevice = false

local revealQueue = {}
local processedActions = {}

local function incrementCombo()
	if comboCount == combo then
		combo += 1
		comboCount = 0
		return
	end

	comboCount += 1
end

local function findHitTarget()
	local camera = workspace.CurrentCamera
	local mousePosition = UserInputService:GetMouseLocation()
	local direction = camera:ViewportPointToRay(mousePosition.x, mousePosition.y).Direction.Unit

	local params = RaycastParams.new()
	params.CollisionGroup = "Raycast"
	params.FilterDescendantsInstances = { workspace:FindFirstChild("Board") }
	params.FilterType = Enum.RaycastFilterType.Whitelist

	local hit = workspace:Raycast(camera.CFrame.p, direction * 150, params)

	if hit then
		local cell = hit.Instance
		return cell, cell:GetAttribute("x"), cell:GetAttribute("y")
	end

	return nil, nil
end

local function updateSelection()
	if workspace:FindFirstChild("Board") == nil then
		return
	end

	local cell, hitX, hitY = findHitTarget()

	if cell ~= nil and cell:GetAttribute("userMined") == nil then
		-- print("hit", hitX, hitY, lastHitX, lastHitY)

		if hitX ~= lastHitX or hitY ~= lastHitY then
			clearSelections()

			local box = cell:FindFirstChild("HoverBox")

			if box ~= nil then
				box.Visible = true
			end
		end

		lastHitX = hitX
		lastHitY = hitY

		return hitX, hitY
	else
		clearSelections()

		lastHitX = nil
		lastHitY = nil

		return nil, nil
	end
end

local function hasProcessed(id)
	for i = 1, #processedActions do
		if processedActions[i] == id then
			return true
		end
	end

	return false
end

local function interpolate(current, goal, velocity, frequency, deltaTime)
	local q = math.exp(-frequency * deltaTime)
	local w = deltaTime * q

	local c0 = q + w * frequency
	local c2 = q - w * frequency
	local c3 = w * frequency * frequency

	local o = current - goal

	return o * c0 + velocity * w + goal, velocity * c2 - o * c3
end

local function renderScore(current, target, velocity, delta, deltaTime)
	local cur, vel = interpolate(current, target, velocity, 10, deltaTime)
	local scoreLabel = bottomMenu:FindFirstChild("ScoreLabel", true)
	local recentAdd = bottomMenu:FindFirstChild("RecentAdd", true)
	local score = math.floor(0.5 + cur)

	if scoreLabel ~= nil then
		scoreLabel.Text = score
	end

	if recentAdd ~= nil then
		if score == target or delta == 0 then
			recentAdd.Visible = false
		else
			recentAdd.Visible = true
		end

		local newDelta = target - score

		if delta > 0 then
			recentAdd.Text = '<stroke color="#000000" joins="round" thickness="1.75" transparency="0">+'
				.. newDelta
				.. ' <font color="#ffffff">['
				.. delta
				.. "]</font></stroke>"
		else
			recentAdd.Text = '<stroke color="#000000" joins="round" thickness="1.75" transparency="0">'
				.. newDelta
				.. ' <font color="#ffffff">['
				.. delta
				.. "]</font></stroke>"
		end

		recentAdd.Position = UDim2.fromOffset(scoreLabel.TextBounds.X + 5, 0)
	end

	return cur, vel
end

RunService.Heartbeat:Connect(function(deltaTime)
	local state = workspace:GetAttribute("state")
	local timeTarget = workspace:GetAttribute("timeTarget")
	local modifier = workspace:GetAttribute("modifier")
	local now = workspace:GetServerTimeNow()

	local camera = workspace.CurrentCamera

	local stateMessage = topMenu:FindFirstChild("Message", true)
	local timeText = topMenu:FindFirstChild("TimeText", true)
	local timeStroke = timeText:FindFirstChild("UIStroke", true)

	timeText.Text = formatTime(timeTarget - now)

	if state ~= lastState then
		if state < 2 then
			clearSelections()
		end

		local modifierText = topMenu:FindFirstChild("ModifierMessage", true)

		if state == 0 and workspace:GetAttribute("winner") then
			local winText = topMenu:FindFirstChild("WinText")

			if winText ~= nil then
				winText.Text = '<stroke color="#000000" thickness="3"><font color="#ffffff">'
					.. workspace:GetAttribute("winner")
					.. "</font> won the game!</stroke>"

				winText:TweenPosition(
					UDim2.new(0.5, 0, 0, 100),
					Enum.EasingDirection.Out,
					Enum.EasingStyle.Back,
					0.5,
					true
				)
			end

			if modifierText ~= nil then
				modifierText.Visible = false
			end
		end

		if state == 1 then
			combo = 1
			comboCount = 0

			scoreTarget = 0
			currentScore = 0
			scoreVelocity = 0
			scoreDelta = 0

			cameraZoomCurrent = 10
			cameraZoomVelocity = 0
			cameraZoomTarget = 10

			lastHitX = nil
			lastHitY = nil

			revealQueue = {}

			local winText = topMenu:FindFirstChild("WinText")

			if winText ~= nil then
				winText:TweenPosition(
					UDim2.new(0.5, 0, 0, -100),
					Enum.EasingDirection.In,
					Enum.EasingStyle.Back,
					0.5,
					true
				)
			end

			if modifierText ~= nil then
				modifierText.Text = '<stroke color="#ffffff" thickness="2">MODIFIER: <font color="'
					.. modifierColorMap[modifier]
					.. '">'
					.. modifierMap[modifier]
					.. "</font></stroke>"
				modifierText.Visible = true
			end
		end

		if state < 2 then
			bottomMenu
				:FindFirstChild("ComboFrame", true)
				:TweenPosition(UDim2.fromScale(0.5, 1.1), Enum.EasingDirection.In, Enum.EasingStyle.Sine, 0.5, true)
		elseif state == 2 and client:GetAttribute("playing") then
			renderCombo(combo, comboCount, now)
			bottomMenu
				:FindFirstChild("ComboFrame", true)
				:TweenPosition(UDim2.fromScale(0.5, 0.9), Enum.EasingDirection.Out, Enum.EasingStyle.Sine, 0.5, true)
		elseif state > 2 then
			clearSelections()

			lastHitX = nil
			lastHitY = nil
		end
	end

	local character = client.Character

	if character ~= nil and character.PrimaryPart ~= nil then
		local pos = character.PrimaryPart.CFrame

		if state >= 1 then
			camera.CameraType = Enum.CameraType.Scriptable

			if modifier == 3 then
				camera.CFrame = CFrame.new(pos.x, pos.y + 15, pos.z, 0, -1, 0, 0, 0, 1, -1, 0, 0)
			else
				cameraZoomCurrent, cameraZoomVelocity =
					interpolate(cameraZoomCurrent, cameraZoomTarget, cameraZoomVelocity, 10, deltaTime)

				camera.CFrame = CFrame.new(pos.x, pos.y + 25 + cameraZoomCurrent, pos.z, 0, -1, 0, 0, 0, 1, -1, 0, 0)
			end
		else
			camera.CameraType = Enum.CameraType.Custom
		end
	end

	if workspace:FindFirstChild("Board") then
		local i = 1
		local clientActions = {}

		while #revealQueue > 0 do
			if i > #revealQueue then
				break
			end

			local item = revealQueue[i]
			local cell = getBoardCell(item.x, item.y)

			if cell == nil then
				table.remove(revealQueue, i)
				continue
			end

			if now > item.timeTarget then
				table.remove(revealQueue, i)

				if item.userId == client.userId and clientActions[item.actionId] == nil then
					clientActions[item.actionId] = item
				end

				if item.flag == 1 then
					MS.revealCell(cell, -2, item.userId, item.mode, client.UserId)
				else
					MS.revealCell(cell, item.id, item.userId, item.mode, client.UserId)
				end
			else
				i += 1
			end
		end

		for actionId, action in pairs(clientActions) do
			if hasProcessed(actionId) then
				continue
			end

			table.insert(processedActions, actionId)

			local revealId = action.id
			local flagState = action.flag
			local silent = action.silent

			scoreDelta = action.scoreIncrement
			scoreTarget += (scoreDelta * combo)

			if revealId >= 0 then
				if not silent then
					if flagState == 0 then
						incrementCombo()
						SoundService:PlayLocalSound(soundLibrary.reveal[revealId])
					elseif flagState == 1 then
						incrementCombo()
						SoundService:PlayLocalSound(soundLibrary.flag)
					elseif flagState == -1 then
						combo = 1
						comboCount = 0
						SoundService:PlayLocalSound(soundLibrary.wrongFlag)
					end
				end
			elseif revealId == -1 then
				if not silent then
					if flagState == 0 then
						combo = 1
						comboCount = 0
						SoundService:PlayLocalSound(soundLibrary.explode)
					else
						incrementCombo()
						SoundService:PlayLocalSound(soundLibrary.flag)
					end
				end
			end
		end

		if state == 2 and client:GetAttribute("playing") then
			if not touchDevice then
				updateSelection()
			elseif lastHitX ~= nil or lastHitY ~= nil then
				clearSelections()

				lastHitX = nil
				lastHitY = nil
			end
		end
	end

	if state == 0 then
		stateMessage.Text = "LOBBY"
		timeText.TextSize = 50
		timeStroke.Thickness = 5
	elseif state == 1 then
		stateMessage.Text = "GAME STARTS IN"
		timeText.TextSize = 50
		timeStroke.Thickness = 5
	elseif state == 2 then
		stateMessage.Text = "IN GAME"
		timeText.TextSize = 30
		timeStroke.Thickness = 4

		renderCombo(combo, comboCount, now)
		currentScore, scoreVelocity = renderScore(currentScore, scoreTarget, scoreVelocity, scoreDelta, deltaTime)
	end

	lastState = state
end)

local downX = nil
local downY = nil

UserInputService.InputBegan:Connect(function(input, gameProcessed)
	if gameProcessed then
		return
	end

	local userInput = input.UserInputType

	if userInput == Enum.UserInputType.MouseMovement then
		touchDevice = false
	elseif userInput == Enum.UserInputType.MouseButton1 or userInput == Enum.UserInputType.MouseButton2 then
		touchDevice = false

		local _, hitX, hitY = findHitTarget()

		downX = hitX
		downY = hitY
	elseif userInput == Enum.UserInputType.Touch then
		touchDevice = true
	end
end)

UserInputService.InputChanged:Connect(function(input, gameProcessed)
	if gameProcessed then
		return
	end

	local userInput = input.UserInputType

	if userInput == Enum.UserInputType.MouseMovement then
		touchDevice = false
	elseif userInput == Enum.UserInputType.Touch then
		touchDevice = true
	elseif userInput == Enum.UserInputType.MouseWheel then
		touchDevice = false
		cameraZoomTarget = math.max(math.min(cameraZoomTarget - input.Position.z * 5, maxZoom), minZoom)
	end
end)

UserInputService.InputEnded:Connect(function(input)
	local userInput = input.UserInputType

	if userInput == Enum.UserInputType.MouseMovement then
		touchDevice = false
	elseif userInput == Enum.UserInputType.MouseButton1 or userInput == Enum.UserInputType.MouseButton2 then
		touchDevice = false

		if workspace:GetAttribute("state") ~= 2 then
			return
		end

		local _, hitX, hitY = findHitTarget()

		if downX == hitX and downY == hitY and hitX ~= nil and hitY ~= nil then
			if userInput == Enum.UserInputType.MouseButton1 then
				RequestRevealCellEvent:FireServer(hitX, hitY)
			elseif userInput == Enum.UserInputType.MouseButton2 then
				RequestFlagCellEvent:FireServer(hitX, hitY)
			end
		end

		downX = nil
		downY = nil
	elseif userInput == Enum.UserInputType.Touch then
		touchDevice = true
	end
end)

UserInputService.TouchTap:Connect(function(_, gameProcessed)
	touchDevice = true

	if gameProcessed then
		return
	end

	local cell, hitX, hitY = findHitTarget()

	if cell == nil then
		return
	end

	RequestRevealCellEvent:FireServer(hitX, hitY)
end)

UserInputService.TouchLongPress:Connect(function(_, _, gameProcessed)
	touchDevice = true

	if gameProcessed then
		return
	end

	local cell, hitX, hitY = findHitTarget()

	if cell == nil then
		return
	end

	RequestFlagCellEvent:FireServer(hitX, hitY)
end)

UserInputService.TouchPinch:Connect(function(_, scale)
	touchDevice = true

	cameraZoomTarget = math.max(math.min(cameraZoomCurrent / scale, maxZoom), minZoom)
end)

RevealCellEvent.OnClientEvent:Connect(function(revealAction)
	table.insert(revealQueue, revealAction)
end)
