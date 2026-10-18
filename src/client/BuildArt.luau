--!strict
-- A resto-mod as a 2x2 puzzle, as the web game's BuildArt (ui/Resto.tsx, crates.css .build-art):
-- the car in grey, with each piece you hold showing its quarter of the car in colour. Empty
-- quarters show the piece's icon (Body 🚗, Engine ⚙️, Wheels 🛞, Interior 💺); `fresh` glows the
-- piece just won; `done` shows the car whole.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Game = ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Game")
local data = require(Game.data) :: any
local resto = require(Game.resto) :: any
local Ui = require(script.Parent.Ui)
local Thumb = require(script.Parent.Thumb)

local BuildArt = {}

local SHADOW = Color3.fromHex("#546e7a")
local CYAN = Color3.fromHex("#80deea")

-- Draws the puzzle into `parent` at `size`. have: the piece indexes held (0-based, as
-- resto.piecesOf gives them). iconSize: the empty slots' icons (9 for the small chips).
function BuildArt.new(parent: Instance, model: string, have: { number }, size: UDim2, opts: { fresh: number?, done: boolean?, iconSize: number?, z: number?, LayoutOrder: number?, Position: UDim2?, AnchorPoint: Vector2? }?): Frame
	local o = opts or {} :: any
	local z = o.z or 1
	local d = data.carDef(model)
	local lit: { [number]: boolean } = {}
	for i = 0, resto.PIECE_COUNT - 1 do
		lit[i] = o.done == true or table.find(have, i) ~= nil
	end
	local art = Ui.new("Frame", { Name = "BuildArt", Size = size, Position = o.Position or UDim2.new(), AnchorPoint = o.AnchorPoint or Vector2.zero, LayoutOrder = o.LayoutOrder or 0, BackgroundTransparency = 1, ZIndex = z, Parent = parent })
	local grey = Thumb.new("Cars", model, UDim2.fromScale(1, 1), SHADOW)
	grey.ZIndex = z
	grey.Parent = art
	-- Each piece held: its quarter of the car in colour, clipped to that quarter.
	for i = 0, resto.PIECE_COUNT - 1 do
		if lit[i] then
			local col, row = i % 2, if i < 2 then 0 else 1
			local q = Ui.new("Frame", { Name = `Piece{i}`, Position = UDim2.fromScale(col * 0.5, row * 0.5), Size = UDim2.fromScale(0.5, 0.5), BackgroundTransparency = 1, ClipsDescendants = true, ZIndex = z, Parent = art })
			local real = Thumb.new("Cars", model, UDim2.fromScale(2, 2), Color3.fromHex(d.colors[1]))
			real.Position = UDim2.fromScale(-col, -row)
			real.ZIndex = z
			real.Parent = q
		end
	end
	-- The grid over it: dashed cyan slots (solid, faint once filled), a piece's icon in each gap.
	local grid = Ui.new("Frame", { Name = "Grid", Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1, ZIndex = z, Parent = art }, {
		Ui.new("UIGridLayout", { CellSize = UDim2.new(0.5, -1, 0.5, -1), CellPadding = UDim2.fromOffset(if o.done then 0 else 2, if o.done then 0 else 2), SortOrder = Enum.SortOrder.LayoutOrder }),
	})
	for i, p in resto.RESTO_PIECES do
		local k = i - 1
		local fresh = o.fresh == k and not o.done
		local cell = Ui.new("Frame", { LayoutOrder = i, BackgroundColor3 = Color3.fromHex("#26c6da"), BackgroundTransparency = if fresh then 0.7 else 1, ZIndex = z, Parent = grid }, {
			Ui.corner(5),
		})
		if o.done then
			continue
		end
		if fresh then
			Ui.stroke(2, CYAN).Parent = cell
		elseif lit[k] then
			Ui.stroke(1.5, Ui.WHITE, 0.82).Parent = cell
		else
			Ui.stroke(1.5, CYAN, 0.45).Parent = cell
			Ui.text({ Text = p.icon, TextSize = o.iconSize or 12, TextTransparency = 0.45, Size = UDim2.fromScale(1, 1), ZIndex = z, Parent = cell })
		end
	end
	return art
end

return BuildArt
