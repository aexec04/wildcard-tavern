--[[
	Shared/Engine/LedgerArt.lua
	Maps ledger_ui id -> rbxassetid for the Tavern Ledger book (Client/LedgerBook.lua). Empty until the Studio session
	resolves the Decal ids in art-wip/ledger_ui to Image ids and records them (generate_patron_art.py -c ledger_ui
	record-image). The book builds a full code-drawn fallback for every key, so it looks right with this table empty and
	lights up piece by piece as ids are added.

	Keys: ledger_desk, ledger_book_open, ledger_bookmark_ribbon, ledger_wax_seal_gold, ledger_wax_seal_red,
	ledger_chalkboard, ledger_photo_frame, ledger_stamp_win, ledger_stamp_loss, ledger_quill_inkwell,
	ledger_paper_note, ledger_coffee_ring
]]

return {
}
