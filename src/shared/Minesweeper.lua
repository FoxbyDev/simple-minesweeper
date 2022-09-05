local ReplicatedStorage = game:GetService("ReplicatedStorage")
local PhysicsService = game:GetService("PhysicsService")

local BoardInstance = ReplicatedStorage.BoardInstance

local ColorConfig = {
	[1] = Color3.fromHex("#32A3FF"),
	[2] = Color3.fromHex("#47CA3C"),
	[3] = Color3.fromHex("#FF3232"),
	[4] = Color3.fromHex("#A332FF"),
	[5] = Color3.fromHex("#FF6932"),
	[6] = Color3.fromHex("#32B7FF"),
	[7] = Color3.fromHex("#FFD932"),
	[8] = Color3.fromHex("#FF32A3"),
}

local ImageIndex = {
	"rbxassetid://10779415955",
	"rbxassetid://10779416242",
	"rbxassetid://10779416437",
	"rbxassetid://10779430981",
}

local function printBoardData(boardData)
	local out = "\n"
	local sizeX = #boardData
	local sizeY = #boardData[1]

	for j = 1, sizeY do
		for i = 1, sizeX do
			local id = boardData[i][j]

			out = out .. " " .. (id >= 0 and id or "X")
		end

		if j < sizeY then
			out = out .. "\n"
		end
	end

	print(out)
end

local function cloneBoardData(boardData)
	local clone = {}

	for i = 1, #boardData do
		clone[i] = {}
		for j = 1, #boardData[i] do
			clone[i][j] = boardData[i][j]
		end
	end

	return clone
end

local function placeBombBoardData(boardData, bombX, bombY)
	local clone = cloneBoardData(boardData)

	for i = 1, #clone do
		if math.abs(i - bombX) > 1 then
			continue
		end

		for j = 1, #clone[i] do
			if math.abs(j - bombY) > 1 then
				continue
			end

			if i == bombX and j == bombY then
				clone[i][j] = -1
			elseif clone[i][j] >= 0 then
				clone[i][j] += 1
			end
		end
	end

	return clone
end

local function xyFromIndex(sizeX, index)
	return 1 + (index % sizeX), 1 + math.floor(index / sizeX)
end

local function createBoardData(sizeX, sizeY, bombCount, startX, startY)
	local board = {}

	for i = 1, sizeX do
		board[i] = {}
		for j = 1, sizeY do
			board[i][j] = 0
		end
	end

	local maxBombs = sizeX * sizeY
	local bombsLeft = math.min(bombCount, maxBombs)
	local bombPositions = {}

	for i = 1, maxBombs do
		local x, y = xyFromIndex(sizeX, i - 1)

		if math.abs(x - startX) <= 1 and math.abs(y - startY) <= 1 then
			continue
		end

		table.insert(bombPositions, i - 1)
	end

	while bombsLeft > 0 and #bombPositions > 0 do
		local bombPositionIndex = math.random(1, #bombPositions)
		local index = bombPositions[bombPositionIndex]
		local bombX, bombY = xyFromIndex(sizeX, index)

		board = placeBombBoardData(board, bombX, bombY)

		bombsLeft -= 1
		table.remove(bombPositions, bombPositionIndex)
	end

	return board
end

local function revealCell(cell, id, userId, mode, clientId)
	if mode == nil then
		mode = 0
	end

	local clientOwned = userId == clientId

	local displayUI = cell:FindFirstChild("DisplayUI")
	displayUI.Enabled = true

	local hoverBox = cell:FindFirstChild("HoverBox")
	hoverBox.Visible = false

	local revealParticle = cell:FindFirstChild("RevealParticle", true)

	if id > -2 then
		cell.Color = Color3.fromHex("#9d824c")
		cell.CFrame = cell.CFrame * CFrame.new(0, -0.8, 0)
	end

	if id > 0 then
		-- Display number

		local numberLabel = displayUI:FindFirstChild("NumberLabel")
		numberLabel.Text = id
		numberLabel.TextColor3 = ColorConfig[id]
		numberLabel.Visible = true

		-- Particle effect

		revealParticle.Color = ColorSequence.new({
			ColorSequenceKeypoint.new(0, ColorConfig[id]),
			ColorSequenceKeypoint.new(0.3, ColorConfig[id]),
			ColorSequenceKeypoint.new(1, Color3.fromRGB(255, 200, 0)),
		})

		if mode == 1 then
			revealParticle:Emit(3)
		elseif mode == 0 then
			revealParticle:Emit(10)
		end
	end

	if id == 0 then
		revealParticle.Color = ColorSequence.new({
			ColorSequenceKeypoint.new(0, Color3.new(1, 1, 1)),
			ColorSequenceKeypoint.new(0.3, Color3.new(1, 1, 1)),
			ColorSequenceKeypoint.new(1, Color3.fromRGB(255, 200, 0)),
		})

		revealParticle:Emit(2)
	end

	if id < 0 then
		-- Display bomb or flag

		local displayImage = displayUI:FindFirstChild("DisplayImage")

		if id == -1 then
			if clientOwned then
				displayImage.Image = ImageIndex[1]
			else
				displayImage.Image = ImageIndex[2]
			end

			cell:FindFirstChild("ExplodeParticle", true):Emit(25)
		elseif id == -2 then
			if clientOwned then
				displayImage.Image = ImageIndex[3]
			else
				displayImage.Image = ImageIndex[4]
			end

			revealParticle.Color = ColorSequence.new({
				ColorSequenceKeypoint.new(0, Color3.fromRGB(217, 180, 105)),
				ColorSequenceKeypoint.new(0.3, Color3.fromRGB(217, 180, 105)),
				ColorSequenceKeypoint.new(1, Color3.fromRGB(255, 255, 255)),
			})

			revealParticle:Emit(8)
		end

		displayImage.Visible = true
	end
end

local function getNeighbours(boardData, x, y)
	local sizeX, sizeY = #boardData, #boardData[1]
	local neighbours = {}

	for i = 1, sizeX do
		if math.abs(x - i) > 1 then
			continue
		end

		for j = 1, sizeY do
			if math.abs(y - j) > 1 then
				continue
			end

			table.insert(neighbours, { x = i, y = j })
		end
	end

	return neighbours
end

local function createCell()
	return BoardInstance.BoardCell:Clone()
end

local function invisiblePart(cf, size)
	local part = Instance.new("Part")
	part.Transparency = 1
	part.Size = size
	part.CFrame = cf
	part.Anchored = true
	return part
end

local function buildBoard(sizeX, sizeY)
	local boardCells = {}

	local board = Instance.new("Model")
	board.Name = "Board"

	local centre = CFrame.new(2.5, 20, 2.5)
	local startCF = centre * CFrame.new(-sizeX * 5 * 0.5, 0, -sizeY * 5 * 0.5)

	for i = 1, sizeX do
		boardCells[i] = {}
		for j = 1, sizeY do
			local cell = createCell()
			cell.CFrame = startCF * CFrame.new((i - 1) * 5, 0, (j - 1) * 5)

			cell:SetAttribute("x", i)
			cell:SetAttribute("y", j)
			cell:SetAttribute("mined", false)
			cell:SetAttribute("flag", false)

			PhysicsService:SetPartCollisionGroup(cell, "Board")

			cell.Parent = board

			boardCells[i][j] = cell
		end
	end

	local wall0 =
		invisiblePart(centre * CFrame.new(-sizeX * 5 * 0.5 - 3.5, 10, -2.5), Vector3.new(2, 20, 2 + sizeY * 5))
	wall0.Parent = board

	local wall1 = invisiblePart(centre * CFrame.new(sizeX * 5 * 0.5 - 1.5, 10, -2.5), Vector3.new(2, 20, 2 + sizeY * 5))
	wall1.Parent = board

	local wall2 =
		invisiblePart(centre * CFrame.new(-2.5, 10, -sizeY * 5 * 0.5 - 3.5), Vector3.new(2 + sizeX * 5, 20, 2))
	wall2.Parent = board

	local wall3 = invisiblePart(centre * CFrame.new(-2.5, 10, sizeY * 5 * 0.5 - 1.5), Vector3.new(2 + sizeX * 5, 20, 2))
	wall3.Parent = board

	local floor = invisiblePart(centre * CFrame.new(-2.5, 0, -2.5), Vector3.new(sizeX * 5, 1, sizeY * 5))
	floor.Parent = board

	return board, boardCells
end

return {
	printBoardData = printBoardData,
	cloneBoardData = cloneBoardData,
	placeBombBoardData = placeBombBoardData,
	createBoardData = createBoardData,
	createCell = createCell,
	buildBoard = buildBoard,
	revealCell = revealCell,
	getNeighbours = getNeighbours,
}
