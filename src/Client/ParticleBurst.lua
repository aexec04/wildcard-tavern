--[[
	Client/ParticleBurst.lua
	SCORING JUICE: a lightweight 2D "particle burst" -- small colored dot
	Frames that fly outward from a point and fade out, then clean
	themselves up. Roblox's real ParticleEmitter is a 3D world Instance
	(it lives on a BasePart or a world-space Attachment) and doesn't work
	parented to 2D ScreenGui content, so this fakes the same "impact"
	feeling with plain Frames + TweenService instead -- the standard
	approach for GUI-only feedback like this.

	Built for Client/ScorePopup.lua's chip/mult/xmult reveal sequence (see
	the "AI Implementation Prompt" Ahmed pasted in -- "particle bursts
	proportional to the size of the payout"), but generic enough to reuse
	anywhere else that wants a quick celebratory pop (a rare Pack pull, a
	big Tips payout, etc.) later.

	deps fields:
		screenGui -- ScreenGui, parent for every particle (so bursts always
		             render above whatever UI triggered them, regardless of
		             that UI's own ZIndex)
		tweenTo   -- function(instance, props, duration, easingStyle?, easingDirection?)

	Returns:
		{
			burst = function(screenPosition, color, count, options?),
			-- screenPosition: UDim2 in ScreenGui space (e.g. an
			--   AbsolutePosition + AbsoluteSize/2 midpoint -- see
			--   ScorePopup.lua's burstFromLabel helper).
			-- color: Color3, every particle in this burst shares one color
			--   (call burst() again for a multi-color effect).
			-- count: how many particles to spawn.
			-- options: { size = number?, spread = number?, duration = number? }
		}
]]

return function(deps)
	local screenGui = deps.screenGui
	local tweenTo = deps.tweenTo

	local function burst(screenPosition, color, count, options)
		options = options or {}
		local size = options.size or 8
		local spread = options.spread or 70
		local duration = options.duration or 0.45

		for _ = 1, count do
			local particle = Instance.new("Frame")
			particle.Name = "JuiceParticle"
			particle.AnchorPoint = Vector2.new(0.5, 0.5)
			particle.Position = screenPosition
			particle.Size = UDim2.fromOffset(size, size)
			particle.BackgroundColor3 = color
			particle.BorderSizePixel = 0
			particle.ZIndex = 30 -- above the score popup (25) and everything else on screen
			particle.Parent = screenGui

			local corner = Instance.new("UICorner")
			corner.CornerRadius = UDim.new(1, 0) -- round it into a dot
			corner.Parent = particle

			-- Random direction + distance so a burst never looks like a
			-- perfect uniform ring -- 50%-100% of `spread`, not a fixed radius.
			local angle = math.random() * math.pi * 2
			local distance = spread * (0.5 + math.random() * 0.5)
			local offset = UDim2.fromOffset(math.cos(angle) * distance, math.sin(angle) * distance)

			tweenTo(particle, {
				Position = screenPosition + offset,
				BackgroundTransparency = 1,
				Size = UDim2.fromOffset(1, 1),
			}, duration, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)

			task.delay(duration, function()
				particle:Destroy()
			end)
		end
	end

	return {
		burst = burst,
	}
end
