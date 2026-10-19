--!nocheck
-- Tests for server/CrewChat: a channel per crew in this server, with its members in it.

local CrewChat = require("../src/server/CrewChat")

local function expectEq(a, b, what)
	if a ~= b then
		error(`{what}: expected {tostring(b)}, got {tostring(a)}`, 2)
	end
end

-- A stand-in TextChannel: its users, and whether it's gone.
local function channel(name)
	local ch = { Name = name, users = {}, gone = false }
	function ch:AddUserAsync(userId)
		local source = { userId = userId }
		function source.Destroy()
			ch.users[userId] = nil
		end
		ch.users[userId] = true
		return source, true
	end
	function ch:Destroy()
		ch.gone = true
	end
	return ch
end

return function(test)
	test("crew chat: a channel per crew, made and dropped as members come and go", function()
		local made = {}
		local cc = CrewChat.new({
			parent = {},
			newChannel = function(name)
				local ch = channel(name)
				table.insert(made, ch)
				return ch
			end,
		})
		cc:set(1, "a", "NITE")
		cc:set(2, "a", "NITE")
		expectEq(#made, 1, "one channel for the crew")
		expectEq(made[1].Name, "Crew NITE", "named after the tag")
		expectEq(made[1].users[1] and made[1].users[2], true, "both in it")
		cc:set(1, "a", "NITE")
		expectEq(#made, 1, "nothing new when nothing changed")
		cc:set(2, "a", "NR")
		expectEq(made[1].Name, "Crew NR", "a new tag renames the tab")
		cc:set(1, "b", "HK")
		expectEq(made[1].users[1], nil, "out of the old crew's")
		expectEq(made[2].users[1], true, "into the new one")
		cc:set(2, nil)
		expectEq(made[1].gone, true, "the empty channel goes")
		cc:forget(1)
		expectEq(made[2].gone, true, "and when the last one leaves the server")
	end)
end
