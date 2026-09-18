-- gf_loadtest.lua — proves an injected T9 Lua chunk loads into the LUI VM and can modify the pause
-- menu. Compiled to T9 bytecode by tools/lui/lj2t9.py, injected into the luafile pool by
-- tools/lui/luapool.py, and loaded either by luiload() from a CSC or by a lua-loader DLL hook
-- (docs/notes/pause-menu.md, lui-source.md). String literals beginning with '#' compile to xhash
-- constants (so LUI.createMenu["#StartMenu_Main"] indexes the same key stock does); every other
-- string stays plain text.
--
-- On load (top-level code runs when the chunk is loaded) it wraps StartMenu_Main's constructor to add
-- one bright label. If "GUNFIGHT MENU LOADED" shows when the ESC menu opens, the chunk loaded and ran.
-- pcall-guarded and orig-first, so a failure leaves the stock pause menu intact.

if LUI and LUI.createMenu and LUI.createMenu["#StartMenu_Main"] then
	local orig = LUI.createMenu["#StartMenu_Main"]

	LUI.createMenu["#StartMenu_Main"] = function(controller, model)
		local menu = orig(controller, model)

		pcall(function()
			local label = LUI.UIText.new(0.5, 0.5, -600, 600, 0, 0, 150, 280)
			label:setPriority(100)
			label:setRGB(1, 0.82, 0.1)
			label:setText("GUNFIGHT MENU LOADED")
			label:setFontHeight(64)
			label:setTTF("default")
			menu:addElement(label)
			menu.gf_loadtest_label = label
		end)

		return menu
	end
end
