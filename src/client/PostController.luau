-- Daftar Pos Ranger buat client (cuma tampilan; semua aturan dicek RangerService di server):
-- * Semua pos dari ReplicatedStorage.PosList (nomor, zona, nama, posisi), tetap ada walau Model pos belum ke-stream.
-- * Pos yang udah ditemukan dari attribute "FoundPosts" (Pos 1 = Basecamp selalu terbuka).
-- * Banner "Pos N ditemukan!" pas server kirim Notify "PostFound".
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Config"))
local FxController = require(script.Parent.FxController)

local BASECAMP = 1

local player = Players.LocalPlayer

local PostController = {}

export type Post = {
	number: number,
	zone: number,
	label: string,
	position: Vector3,
}

local posts: { [number]: Post } = {}
local changedCallbacks: { () -> () } = {}

local function fireChanged()
	for _, callback in changedCallbacks do
		task.spawn(callback)
	end
end

local function readEntry(entry: Instance)
	local number = tonumber(entry.Name)
	local zone = entry:GetAttribute("Zone")
	local position = entry:GetAttribute("Position")
	if not number or type(zone) ~= "number" or typeof(position) ~= "Vector3" then
		return
	end
	local label = entry:GetAttribute("Label")
	posts[number] = {
		number = number,
		zone = zone,
		label = if type(label) == "string" then label else ("Pos " .. number),
		position = position,
	}
	fireChanged()
end

-- ===== API publik =====
function PostController.get(number: number): Post?
	return posts[number]
end

-- Semua pos, urut nomor
function PostController.list(): { Post }
	local result = {}
	for _, post in posts do
		table.insert(result, post)
	end
	table.sort(result, function(a, b)
		return a.number < b.number
	end)
	return result
end

-- "Pos 2 · Hutan Lumut"
function PostController.title(post: Post): string
	return string.format("Pos %d · %s", post.number, post.label)
end

function PostController.isFound(number: number): boolean
	if number == BASECAMP then
		return true
	end
	local raw = player:GetAttribute("FoundPosts")
	if type(raw) ~= "string" then
		return false
	end
	for _, part in string.split(raw, ",") do
		if tonumber(part) == number then
			return true
		end
	end
	return false
end

-- Pos yang udah ditemukan & paling dekat dari `position`, atau nil
function PostController.nearestFound(position: Vector3): Post?
	local best: Post?, bestDistance = nil, math.huge
	for number, post in posts do
		local distance = (post.position - position).Magnitude
		if distance < bestDistance and PostController.isFound(number) then
			best, bestDistance = post, distance
		end
	end
	return best
end

-- callback() tiap daftar pos atau pos yang ditemukan berubah
function PostController.onChanged(callback: () -> ())
	table.insert(changedCallbacks, callback)
end

function PostController.start()
	player:GetAttributeChangedSignal("FoundPosts"):Connect(fireChanged)

	task.spawn(function()
		local folder = ReplicatedStorage:WaitForChild("PosList")
		for _, entry in folder:GetChildren() do
			readEntry(entry)
		end
		folder.ChildAdded:Connect(readEntry)
	end)

	ReplicatedStorage:WaitForChild("Remotes"):WaitForChild("Notify").OnClientEvent:Connect(function(kind: string, data)
		if kind ~= "PostFound" then
			return
		end
		local post = posts[data]
		FxController.banner({
			title = string.format("Pos %d ditemukan!", data),
			subtitle = if post then post.label else "Pos Ranger baru",
			body = "Sekarang kamu bisa setor di sini, dan teleport ke sini dari Menu Pos mana pun.",
			sound = "PostFound",
			confetti = 20,
			seconds = Config.Posts.BannerSeconds,
		})
	end)
end

return PostController
