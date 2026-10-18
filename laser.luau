-- Connected Discord-GitHub

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")

-- Laser config
local MAX_REFLECTIONS = 6
local MAX_DISTANCE = 300
local SURFACE_OFFSET = 0.01		-- Push laser away from surface so it doesnt get stuck

-- Laser styling
local BEAM_THICKNESS = 0.2
local BEAM_COLOR = Color3.fromRGB(255, 60, 60)

-- Relay colors
local POWERED_COLOR = Color3.fromRGB(0, 255, 0)
local OFF_COLOR = Color3.fromRGB(91, 93, 105)

local emitterPart = CollectionService:GetTagged("emitter")[1]	-- Emits laser
local mirrorParts = CollectionService:GetTagged("mirror")		-- Reflects
local relayParts = CollectionService:GetTagged("relay")			-- Collects laser
local obstacleParts = CollectionService:GetTagged("obstacle")	-- Blocks laser

local mirrorLookup = {}
for _, mirrorPart in mirrorParts do
	mirrorLookup[mirrorPart] = true
end

local relayLookup = {}
for _, relayPart in relayParts do
	relayLookup[relayPart] = true
end


-- Folder holds beam parts
local beamFolder = Instance.new("Folder")
beamFolder.Name = "LaserBeams"
beamFolder.Parent = workspace

local raycastParameters = RaycastParams.new()
raycastParameters.FilterType = Enum.RaycastFilterType.Include
raycastParameters.IgnoreWater = true

local function updateRaycastFilter(leavingPlayer: Player?)
	local raycastFilterInstances = {}	-- Rebuilt from scratch each time so entries never pile up

	for _, partList in { mirrorParts, relayParts, obstacleParts } do	-- Only detect mirrors, relays, obstacles (ignore beam parts)
		for _, part in partList do
			table.insert(raycastFilterInstances, part)
		end
	end

	for _, player in Players:GetPlayers() do
		if player ~= leavingPlayer and player.Character then
			table.insert(raycastFilterInstances, player.Character)	-- Characters block the laser
		end
	end

	raycastParameters.FilterDescendantsInstances = raycastFilterInstances
end

local function drawBeamSegment(startPosition: Vector3, endPosition: Vector3)
	local segmentLength = (endPosition - startPosition).Magnitude	-- distance between raycast start and end

	if segmentLength < 0.001 then	-- return if beam is too short
		return
	end

	-- Create beam part
	local beamPart = Instance.new("Part")
	beamPart.Anchored = true
	beamPart.CanCollide = false
	beamPart.CanQuery = false
	beamPart.CanTouch = false
	beamPart.CastShadow = false
	beamPart.Material = Enum.Material.Neon
	beamPart.Color = BEAM_COLOR
	beamPart.Size = Vector3.new(BEAM_THICKNESS, BEAM_THICKNESS, segmentLength)		-- Size using calculated length and const beam width
	beamPart.CFrame = CFrame.lookAt((startPosition + endPosition) / 2, endPosition)	-- Place at midpoint of start and end position
	beamPart.Parent = beamFolder	-- Parent to the beam folder
end

local function traceLaser(): BasePart?
	local origin = emitterPart.CFrame * Vector3.new(0, 0, -emitterPart.Size.Z / 2 - SURFACE_OFFSET)	-- new laser's origin is from side of emitter not center so it doesnt get stuck
	local direction = emitterPart.CFrame.LookVector		-- get emitter facing direction
	local remainingDistance = MAX_DISTANCE		-- new beam so remaining distance is the same as max

	for reflectionIndex = 0, MAX_REFLECTIONS do		-- For each reflection...

		if remainingDistance <= SURFACE_OFFSET then	-- Stop laser if it reaches max distance
			break
		end

		local result = workspace:Raycast(origin, direction * remainingDistance, raycastParameters)	-- Cast ray for remaining distance
		if not result then		-- if ray hits nothing...
			drawBeamSegment(origin, origin + direction * remainingDistance)	-- cast beam with remaining distance...
			break -- ... and break beam
		end

		drawBeamSegment(origin, result.Position)	-- If ray hits draw beam from origin to raycast hit

		local hitPart = result.Instance		-- Get part ray hit
		if relayLookup[hitPart] then	-- If hit part is a relay...
			return hitPart				-- Return it
		end

		if not mirrorLookup[hitPart] or reflectionIndex == MAX_REFLECTIONS then	-- If hit part is not a mirror (obstacle or player) or max reflections reached...
			break	-- Break beam
		end

		-- Must be a mirror
		local surfaceNormal = result.Normal		-- Get mirror normal

		if math.abs(surfaceNormal:Dot(hitPart.CFrame.LookVector)) < 0.99 then	-- If laser hit mirror on the side edge
			break	-- break because the side edge shouldnt be reflective
		end

		direction = (direction - 2 * direction:Dot(surfaceNormal) * surfaceNormal).Unit	-- mirror vector reflection formula
		remainingDistance -= result.Distance + SURFACE_OFFSET	-- Subtract ray distance and offset from remaining distance
		origin = result.Position + direction * SURFACE_OFFSET	-- Set origin to the reflected position pushed slightly forward by offset
	end

	return nil
end

local function updateLaser()
	beamFolder:ClearAllChildren()		-- delete old beam parts

	local poweredRelay = traceLaser()	-- create new beam and return a relay if it hits one

	for _, relayPart in relayParts do	-- look thru existing relays
		relayPart.Color = if relayPart == poweredRelay then POWERED_COLOR else OFF_COLOR	-- powered relay is green, others are off
	end
end

local function watchPlayer(player: Player)	
	player.CharacterAdded:Connect(updateRaycastFilter)	-- update laser filter when a character spawns so it blocks the laser raycast too
	player.CharacterRemoving:Connect(function()	-- begin when character starts leaving
		task.defer(updateRaycastFilter, player)	-- defer raycast filter update until the character is gone
	end)
end

Players.PlayerAdded:Connect(watchPlayer)
for _, player in Players:GetPlayers() do
	watchPlayer(player)		-- when player connects check if character is loaded and update raycast filter
end

updateRaycastFilter()	-- init raycast filter
RunService.RenderStepped:Connect(updateLaser) -- update laser every frame