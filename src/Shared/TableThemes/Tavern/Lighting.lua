--[[
	TableThemes/Tavern/Lighting.lua
	The light of the Tavern: a little light from a window behind the player (the sun: it is what casts the shadows,
	so a lifted card and a standing Patron have one), a warm lamp over the felt, and the fire, lanterns and candles
	(they are props and carry their own light), with the grade on top. Colors are { r, g, b } out of 255 and positions are studs from the table's middle (x right, y up from the
	felt, z toward the player).

	service   properties of the Lighting service. ClockTime and GeographicLatitude aim the window light: here it comes
	          from behind the player's left shoulder, so what stands on the table is lit from the front.
	effects   one table per effect class; every key is a property of that class
	lights    lamps that are not props
	cards     how the faces of the cards take the light
	react     how the light answers a scoring thump and the payout
]]

return {
	service = {
		GlobalShadows = true,
		Brightness = 0.35,
		ClockTime = 13.5,
		GeographicLatitude = 50,
		Ambient = { 40, 30, 26 },
		OutdoorAmbient = { 24, 18, 16 },
		ColorShift_Top = { 255, 214, 170 },
		EnvironmentDiffuseScale = 0.05,
		EnvironmentSpecularScale = 0.15,
		ExposureCompensation = -1.0,
		ShadowSoftness = 0.35,
	},
	effects = {
		ColorCorrectionEffect = { Brightness = 0, Contrast = 0.12, Saturation = -0.12, TintColor = { 255, 244, 232 } },
		BloomEffect = { Intensity = 0.25, Size = 18, Threshold = 2.0 },
		DepthOfFieldEffect = { FarIntensity = 0.3, FocusDistance = 24, InFocusRadius = 30, NearIntensity = 0 },
		Atmosphere = { Density = 0.3, Offset = 0, Color = { 86, 62, 46 }, Decay = { 40, 26, 18 }, Glare = 0, Haze = 1.4 },
	},
	lights = {
		{ name = "Lantern", kind = "Spot", at = { 3, 30, 8 }, lookAt = { 3, 0, 2 }, color = { 255, 214, 160 },
			brightness = 3.4, range = 90, angle = 86, shadows = true },
		{ name = "PlayerCandle", kind = "Point", at = { 3, 9, 23 }, color = { 255, 200, 150 }, brightness = 1.3, range = 34 },
	},
	cards = { lightInfluence = 0.85, brightness = 1 }, -- how much of the room's light a card's face takes, and its own glow
	react = {
		flash = { 255, 232, 180 }, -- the lantern's color at the top of a payout flash
		thump = 0.5, -- how much brighter the lantern gets on a full strength thump
		flicker = 0.16, -- how far a candle's light wanders, as a share of its brightness
	},
}
