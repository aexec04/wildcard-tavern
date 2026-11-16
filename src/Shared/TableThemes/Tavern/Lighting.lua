--[[
	TableThemes/Tavern/Lighting.lua
	The light of the Tavern table: late light from a high window (the sun: it is what casts the shadows, so a lifted
	card has one), a warm lantern over the felt, candles (they are props and carry their own light) and the grade on
	top. Colors are { r, g, b } out of 255 and positions are studs from the table's middle (x right, y up from the
	felt, z toward the player).

	service   properties of the Lighting service. ClockTime and GeographicLatitude aim the window light: here it comes
	          from the far left, so shadows fall toward the player and to the right, where a lifted card shows them.
	effects   one table per effect class; every key is a property of that class
	lights    lamps that are not props
	cards     how the faces of the cards take the light
	react     how the light answers a scoring thump and the payout
]]

return {
	service = {
		GlobalShadows = true,
		Brightness = 0.85,
		ClockTime = 13.5,
		GeographicLatitude = 0,
		Ambient = { 52, 42, 36 },
		OutdoorAmbient = { 30, 26, 24 },
		ColorShift_Top = { 255, 214, 170 },
		EnvironmentDiffuseScale = 0.05,
		EnvironmentSpecularScale = 0.15,
		ExposureCompensation = -0.25,
		ShadowSoftness = 0.35,
	},
	effects = {
		ColorCorrectionEffect = { Brightness = 0, Contrast = 0.1, Saturation = -0.05, TintColor = { 255, 244, 232 } },
		BloomEffect = { Intensity = 0.3, Size = 20, Threshold = 1.8 },
		DepthOfFieldEffect = { FarIntensity = 0.15, FocusDistance = 27, InFocusRadius = 18, NearIntensity = 0 },
		Atmosphere = { Density = 0.3, Offset = 0, Color = { 86, 62, 46 }, Decay = { 40, 26, 18 }, Glare = 0, Haze = 1.4 },
	},
	lights = {
		{ name = "Lantern", kind = "Spot", at = { 2.5, 20, 4 }, lookAt = { 2.5, 0, 0 }, color = { 255, 214, 160 },
			brightness = 3.0, range = 60, angle = 70, shadows = true },
	},
	cards = { lightInfluence = 0.85, brightness = 1 }, -- how much of the room's light a card's face takes, and its own glow
	react = {
		flash = { 255, 232, 180 }, -- the lantern's color at the top of a payout flash
		thump = 0.5, -- how much brighter the lantern gets on a full strength thump
		flicker = 0.16, -- how far a candle's light wanders, as a share of its brightness
	},
}
