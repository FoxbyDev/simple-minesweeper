local Players = game:GetService("Players")
local ServerStorage = game:GetService("ServerStorage")
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local PhysicsService = game:GetService("PhysicsService")

local MS = require(ReplicatedStorage.Minesweeper)

local RequestRevealCellEvent = ReplicatedStorage.RequestRevealCell
local RequestFlagCellEvent = ReplicatedStorage.RequestFlagCell
local RevealCellEvent = ReplicatedStorage.RevealCell

-- get character height function :: from sircfenner
local function getAvatarHeight(model, humanoid)
	if humanoid.RigType ~= Enum.HumanoidRigType.R15 then
		return 5
	end

	local root = model.LowerTorso.Root

	local hip = model.LeftUpperLeg.LeftHip
	local knee = model.LeftLowerLeg.LeftKnee
	local ankle = model.LeftFoot.LeftAnkle

	local waist = model.UpperTorso.Waist
	local neck = model.Head.Neck

	local down = root.C1.y
		- root.C0.y
		+ hip.C1.y
		- hip.C0.y
		+ knee.C1.y
		- knee.C0.y
		+ ankle.C1.y
		- ankle.C0.y
		+ model.LeftFoot.Size.y * 0.5

	local up = root.C0.y - root.C1.y + waist.C0.y - waist.C1.y + neck.C0.y - neck.C1.y + model.Head.Size.y * 0.5

	return down + up
end

-- build collision groups
PhysicsService:CreateCollisionGroup("Board")
PhysicsService:CreateCollisionGroup("Raycast")
PhysicsService:CreateCollisionGroup("Players")

PhysicsService:CollisionGroupSetCollidable("Raycast", "Default", false)
PhysicsService:CollisionGroupSetCollidable("Raycast", "Players", false)
PhysicsService:CollisionGroupSetCollidable("Raycast", "Board", true)
PhysicsService:CollisionGroupSetCollidable("Players", "Players", false)

-- store data for the board sizes and scoring

local boardSizeMap = { 13, 14, 15, 16, 17, 18, 19, 20, 21, 22, 23 }

local scoreIndex = {
	[-2] = 5,
	[-1] = -10,
	[0] = 10,
	[1] = 1,
	[2] = 2,
	[3] = 4,
	[4] = 8,
	[5] = 10,
	[6] = 20,
	[7] = 25,
	[8] = 50,
}

-- state variables

local state = -1
local timeTarget = -1
local modifier = 0

local boardModel = nil
local boardData = nil
local boardCells = nil

local scores = {}
local modifierCount = 4
local modifierChance = 0.6

workspace:SetAttribute("state", -1)
workspace:SetAttribute("timeTarget", -1)

local lobbyModel = ServerStorage.Lobby:Clone()
lobbyModel.Parent = workspace

-- utility functions

local function resetGame()
	state = -1
	timeTarget = -1

	if boardModel ~= nil then
		boardModel:Destroy()
	end
end

local function isBoardComplete(model, data)
	if model == nil then
		return true
	end

	if data == nil then
		return false
	end

	local allNonBombsMined = true
	local allBombsFlagged = true
	local sizeX, sizeY = #data, #data[1]

	for i = 1, sizeX do
		for j = 1, sizeY do
			local id = data[i][j]

			-- if this is true then there are cells which are not bombs or mined/flagged tiles
			if id ~= -1 and id ~= -10 and id ~= -2 then
				allNonBombsMined = false
			end

			-- if this is true, there's a bomb that has not been flagged
			if id == -1 then
				allBombsFlagged = false
			end
		end
	end

	return allNonBombsMined or allBombsFlagged
end

local function incrementCombo(scoreList, id)
	if scoreList[id] == nil then
		return
	end

	local score = scoreList[id]
	local combo, comboCount = score.combo, score.comboCount

	if comboCount == combo then
		score.combo += 1
		score.comboCount = 0
		return
	end

	score.comboCount += 1
end

local function resetCombo(scoreList, id)
	if scoreList[id] == nil then
		return
	end

	local score = scoreList[id]

	score.combo = 1
	score.comboCount = 0
end

-- main loop

RunService.Heartbeat:Connect(function()
	local players = Players:GetPlayers()
	local now = workspace:GetServerTimeNow()
	local size = #players > #boardSizeMap and boardSizeMap[#boardSizeMap] or boardSizeMap[#players]

	if state > -1 and #players == 0 then
		resetGame()
	end

	-- If we are in the inactive lobby state and there is a player
	if state == -1 and #players > 0 then
		state = 0
		timeTarget = now + 31

		workspace:SetAttribute("state", state)
		workspace:SetAttribute("timeTarget", timeTarget)
		return
	end

	-- We need to start the game, so begin the cooldown
	if state == 0 and now > timeTarget then
		state = 1
		timeTarget = now + 4 + math.floor(size * 0.1)

		workspace:SetAttribute("state", state)
		workspace:SetAttribute("timeTarget", timeTarget)

		if math.random() < modifierChance then
			modifier = math.random(1, modifierCount)
		else
			modifier = 0
		end

		workspace:SetAttribute("modifier", modifier)

		if boardModel ~= nil then
			boardModel:Destroy()
		end

		boardModel, boardCells = MS.buildBoard(size, size)
		boardModel.Parent = workspace

		for i, v in pairs(players) do
			local char = v.Character
			local humanoid = char:FindFirstChild("Humanoid")

			if char == nil or humanoid == nil then
				continue
			end

			v:SetAttribute("playing", true)

			scores[v.UserId] = {
				value = 0,
				combo = 1,
				comboCount = 0,
			}

			if v:FindFirstChild("leaderstats") then
				v:FindFirstChild("leaderstats"):Destroy()
			end

			local stats = Instance.new("Folder")
			stats.Name = "leaderstats"

			local scoreStat = Instance.new("IntValue")
			scoreStat.Value = 0
			scoreStat.Name = "Score"
			scoreStat.Parent = stats

			stats.Parent = v

			humanoid.JumpHeight = 0
			humanoid.WalkSpeed = 0

			local height = getAvatarHeight(char, humanoid)
			local centre = boardModel:GetPivot()

			if #players > 1 then
				char:PivotTo(
					centre * CFrame.Angles(0, math.rad(360 * (i / #players)), 0) * CFrame.new(0, 0, -size * 0.3 * 5)
				)
			else
				char:PivotTo(centre * CFrame.new(0, 2 + height * 0.5, 0))
			end

			local root = char:FindFirstChild("HumanoidRootPart")

			if root == nil then
				continue
			end

			root.Anchored = true
		end

		return
	end

	-- Cooldown has ended, start the game
	if state == 1 and now > timeTarget then
		state = 2
		timeTarget = now + 1 + 60 + 20 * (#players - 1)

		workspace:SetAttribute("state", state)
		workspace:SetAttribute("timeTarget", timeTarget)

		for _, v in pairs(players) do
			if v:GetAttribute("playing") then
				local char = v.Character
				local humanoid = char:FindFirstChild("Humanoid")

				if char == nil or humanoid == nil then
					continue
				end

				if modifier == 4 then
					humanoid.WalkSpeed = 120
				else
					humanoid.WalkSpeed = 20
				end

				local root = char:FindFirstChild("HumanoidRootPart")

				if root == nil then
					continue
				end

				root.Anchored = false
			end
		end

		return
	end

	if state == 2 and (now > timeTarget or isBoardComplete(boardModel, boardData)) then
		state = 0
		timeTarget = now + 20

		workspace:SetAttribute("state", state)
		workspace:SetAttribute("timeTarget", timeTarget)

		-- find the winner

		local winner = nil
		local winnerScore = -math.huge

		for _, v in pairs(players) do
			if v:GetAttribute("playing") then
				local score = scores[v.UserId].value

				if score > winnerScore then
					winner = v.DisplayName
					winnerScore = score
				end
			end
		end

		if winner ~= nil then
			workspace:SetAttribute("winner", winner)
		end

		for i, v in pairs(players) do
			if v:GetAttribute("playing") then
				v:SetAttribute("playing", false)

				local char = v.Character
				local humanoid = char:FindFirstChild("Humanoid")

				if char == nil or humanoid == nil then
					continue
				end

				humanoid.JumpHeight = 7.2
				humanoid.WalkSpeed = 16

				local height = getAvatarHeight(char, humanoid)
				local centre = CFrame.new(0, 110, 0)

				if #players > 1 then
					char:PivotTo(centre * CFrame.Angles(0, math.rad(360 * (i / #players)), 0) * CFrame.new(0, 0, -10))
				else
					char:PivotTo(centre * CFrame.new(0, 5 + height * 0.5, 0))
				end
			end
		end

		boardCells = nil
		boardData = nil
		scores = {}

		return
	end
end)

-- process client requests

local actionId = 0

local function processRevealRequest(client, x, y, flag)
	if flag == nil then
		flag = 0
	end

	actionId += 1

	local now = workspace:GetServerTimeNow()

	local revealId = boardData[x][y]
	local scoreIncrement = 0

	if flag == -1 then
		scoreIncrement = -scoreIndex[-2]
	elseif flag == 1 then
		scoreIncrement = scoreIndex[-2]
	else
		scoreIncrement = scoreIndex[revealId]
	end

	local clientScore = scores[client.UserId]
	clientScore.value += (scoreIncrement * clientScore.combo)

	local leaderstats = client:FindFirstChild("leaderstats")

	if leaderstats ~= nil then
		local scoreStat = leaderstats:FindFirstChild("Score", true)

		if scoreStat ~= nil then
			scoreStat.Value = clientScore.value
		end
	end

	if revealId >= 0 then
		if flag == 0 or flag == 1 then
			incrementCombo(scores, client.UserId)
		elseif flag == -1 then
			resetCombo(scores, client.UserId)
		end
	elseif revealId == -1 then
		if flag == 0 then
			resetCombo(scores, client.UserId)
		else
			incrementCombo(scores, client.UserId)
		end
	end

	if flag == 1 then
		boardData[x][y] = -2
	else
		boardData[x][y] = -10
	end

	RevealCellEvent:FireAllClients({
		x = x,
		y = y,
		id = revealId,
		userId = client.userId,
		mode = 0,
		timeTarget = now,
		silent = false,
		flag = flag,
		actionId = actionId,
		scoreIncrement = scoreIncrement,
	})

	if revealId == 0 then
		-- We need to schedule the floodfill

		local neighbourList = {}

		local function floodfill(posX, posY, depth)
			if depth == nil then
				depth = 1
			end

			local neighbours = MS.getNeighbours(boardData, posX, posY)

			for i = 1, #neighbours do
				local pos = neighbours[i]
				local id = boardData[pos.x][pos.y]
				local neighbour = boardCells[pos.x][pos.y]

				if neighbour:GetAttribute("userMined") ~= nil then
					continue
				end

				neighbour:SetAttribute("userMined", client.UserId)
				neighbour:SetAttribute("mined", true)

				if id == 0 then
					floodfill(pos.x, pos.y, depth + 1)
				end

				table.insert(neighbourList, pos)
			end
		end

		floodfill(x, y)

		local origin = Vector2.new(x, y)

		for i = 1, #neighbourList do
			local pos = neighbourList[i]
			local distance = (Vector2.new(pos.x, pos.y) - origin).magnitude
			local id = boardData[pos.x][pos.y]

			boardData[pos.x][pos.y] = -10

			RevealCellEvent:FireAllClients({
				x = pos.x,
				y = pos.y,
				id = id,
				userId = client.UserId,
				mode = 1,
				timeTarget = now + 0.05 * distance,
				silent = true,
				flag = flag,
				actionId = actionId,
				scoreIncrement = 0,
			})
		end
	end
end

RequestFlagCellEvent.OnServerEvent:Connect(function(client, x, y)
	if state ~= 2 or boardCells == nil or not client:GetAttribute("playing") or modifier == 1 then
		return
	end

	local cell = boardCells[x][y]

	if cell:GetAttribute("userMined") then
		return
	end

	if boardData == nil then
		local multiplier = 1

		if modifier == 2 then
			multiplier = 1.5
		end

		boardData = MS.createBoardData(
			#boardCells,
			#boardCells,
			multiplier * 0.01 * math.random(15, 18) * #boardCells * #boardCells - 9,
			x,
			y
		)
	end

	if boardData[x][y] ~= -1 then
		cell:SetAttribute("mined", true)
	else
		cell:SetAttribute("flag", true)
	end

	cell:SetAttribute("userMined", client.UserId)

	if boardData[x][y] ~= -1 then
		processRevealRequest(client, x, y, -1)
	else
		processRevealRequest(client, x, y, 1)
	end
end)

RequestRevealCellEvent.OnServerEvent:Connect(function(client, x, y)
	if state ~= 2 or boardCells == nil or not client:GetAttribute("playing") then
		return
	end

	local cell = boardCells[x][y]

	if cell:GetAttribute("userMined") then
		return
	end

	if boardData == nil then
		local multiplier = 1

		if modifier == 2 then
			multiplier = 1.5
		end

		boardData = MS.createBoardData(
			#boardCells,
			#boardCells,
			multiplier * 0.01 * math.random(15, 18) * #boardCells * #boardCells - 9,
			x,
			y
		)
	end

	cell:SetAttribute("mined", true)
	cell:SetAttribute("userMined", client.UserId)

	processRevealRequest(client, x, y)
end)

-- player collision handling (from roblox wiki)

local previousCollisionGroups = {}

local function setCollisionGroup(object)
	if object:IsA("BasePart") then
		previousCollisionGroups[object] = object.CollisionGroupId
		PhysicsService:SetPartCollisionGroup(object, "Players")
	end
end

local function setCollisionGroupRecursive(object)
	setCollisionGroup(object)

	for _, child in ipairs(object:GetChildren()) do
		setCollisionGroupRecursive(child)
	end
end

local function resetCollisionGroup(object)
	local previousCollisionGroupId = previousCollisionGroups[object]
	if not previousCollisionGroupId then
		return
	end

	local previousCollisionGroupName = PhysicsService:GetCollisionGroupName(previousCollisionGroupId)
	if not previousCollisionGroupName then
		return
	end

	PhysicsService:SetPartCollisionGroup(object, previousCollisionGroupName)
	previousCollisionGroups[object] = nil
end

local function onCharacterAdded(character)
	setCollisionGroupRecursive(character)

	character.DescendantAdded:Connect(setCollisionGroup)
	character.DescendantRemoving:Connect(resetCollisionGroup)
end

local function onPlayerAdded(player)
	player.CharacterAdded:Connect(onCharacterAdded)
end

-- player added event

Players.PlayerAdded:Connect(function(client)
	onPlayerAdded(client)

	if state ~= 2 then
		return
	end

	if boardCells == nil then
		return
	end

	local sizeX, sizeY = #boardCells, #boardCells[1]

	for i = 1, sizeX do
		for j = 1, sizeY do
			local cell = boardCells[i][j]

			if cell:GetAttribute("userMined") ~= nil then
				RevealCellEvent:FireClient(
					client,
					i,
					j,
					boardData[i][j],
					cell:GetAttribute("userMined"),
					-1,
					workspace:GetServerTimeNow(),
					true,
					false
				)
			end
		end
	end
end)
