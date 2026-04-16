## [0.1.0-beta] - Initial beta release

- Exports your current transmog appearance (per slot, with weapon illusions and paired appearances where applicable) to a compact string for sharing with StyleBound.gg, using JSON plus LibDeflate compression.
- Imports pasted strings: decodes and validates the outfit format, resolves which appearances you already own in your collection, and shows a slot-by-slot preview in a draggable dialog.
- Main panel (`/stylebound` or `/sb`) with tabs for copy-ready export, paste-to-decode import, saved outfits, and screenshot/selfie helpers; position is remembered between sessions.
- Minimap button (LibDataBroker / LibDBIcon): left-click toggles the main panel; right-click is reserved for a future settings panel.
- Outfit library: save the current look, list/search/rename/delete, organize into folders, and browse everything in the Outfit Browser; outfits can be promoted into Blizzard Custom Sets from the wardrobe collection UI when within the in-game cap.
- Screenshot mode hides the UI and nameplates for clean shots, tracks captured files, and prints the matching export string when you finish; auto-shoot captures three preset camera angles automatically.
- Selfie integration: when the S.E.L.F.I.E. Camera toy buff is active, the addon tracks screenshots and prints the export string on exit (with name-hiding for cleaner shots).
- `/sb copy` inspects your targeted player (in range) and opens the same import preview populated from their visible transmog.
