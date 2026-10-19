--!strict
-- Crew chat (the web game's 'crew:<id>' chat room, supabase/migrations/0048_chat.sql): a channel in
-- Roblox's own chat for each crew, holding its members who are in this server. Roblox filters
-- every message and only lets in players it allows to chat, so nothing here sees or sends text.
-- The chat window shows a tab per channel (ChannelTabsConfiguration), named after the crew's tag.
--
-- Unlike the web game's room it reaches only crewmates in the same server: Roblox's chat doesn't
-- cross servers.

local CrewChat = {}
CrewChat.__index = CrewChat

export type Mods = {
	-- Where the channels go (TextChatService), and how a channel is made.
	parent: any,
	newChannel: (name: string) -> any,
}

export type CrewChat = typeof(setmetatable(
	{} :: {
		mods: Mods,
		-- Each crew's channel, by crew id.
		channels: { [string]: any },
		-- The crew each player is in the channel of.
		member: { [number]: string },
		-- Each player's place in their channel (AddUserAsync's TextSource).
		sources: { [number]: any },
	},
	CrewChat
))

function CrewChat.new(mods: Mods): CrewChat
	return setmetatable({ mods = mods, channels = {}, member = {}, sources = {} }, CrewChat)
end

-- The channel's name in the chat window's tabs.
function CrewChat.name(tag: string?): string
	return `Crew {tag or ""}`
end

function CrewChat._leave(self: CrewChat, userId: number)
	local id = self.member[userId]
	if not id then
		return
	end
	self.member[userId] = nil
	local ch = self.channels[id]
	if ch then
		local source = self.sources[userId]
		if source then
			pcall(source.Destroy, source)
		end
		self.sources[userId] = nil
		-- The last one out of this server: no empty channel left behind.
		local empty = true
		for _, other in self.member do
			if other == id then
				empty = false
				break
			end
		end
		if empty then
			ch:Destroy()
			self.channels[id] = nil
		end
	end
end

-- Puts a player in their crew's channel (crewId, tag), or takes them out (nil). Yields.
function CrewChat.set(self: CrewChat, userId: number, crewId: string?, tag: string?)
	if self.member[userId] == crewId then
		local ch = crewId and self.channels[crewId]
		-- (A renamed tag: the tab follows.)
		if ch and ch.Name ~= CrewChat.name(tag) then
			ch.Name = CrewChat.name(tag)
		end
		return
	end
	self:_leave(userId)
	if not crewId then
		return
	end
	local ch = self.channels[crewId]
	if not ch then
		ch = self.mods.newChannel(CrewChat.name(tag))
		ch.Parent = self.mods.parent
		self.channels[crewId] = ch
	end
	self.member[userId] = crewId
	local ok, source = pcall(ch.AddUserAsync, ch, userId)
	self.sources[userId] = if ok then source else nil
end

-- A player left the server.
function CrewChat.forget(self: CrewChat, userId: number)
	self:_leave(userId)
end

return CrewChat
