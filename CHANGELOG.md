# Changelog

## es_mdt 2.0.17 (2026-11-19)

**Post-mortem reports on the MDT case, and one-tap copy for every code.** Made for whip_evidence 4.2.3 (LeSiiN), which adds a post-mortem report item to the body exam.

- **Post-mortem card:** when the report item is uploaded to a case, the case's Evidence locker card opens with a "Post-mortem findings" panel, like the body menu in game.
  - A **body overview**: a front figure with every hit drawn on its body part. Legend: a filled red dot is a bullet still inside, a red ring is a shot that went through, an orange slash is a stab or cut, a yellow diamond is blunt force, and a purple square is any other wound. A dashed yellow ring marks the fatal one. The hit parts are tinted.
  - The **cause of death** in a red box, then three tiles: hits, bullets inside, and the time of death in each officer's own clock (exam time minus how long the body had been dead).
  - Rows: wounds in total and per body part, shot from (under 2 m, 2–10 m or over 10 m), bullets inside and through, defence wounds, a weapon in hand, the body moved after death, and what was secured at the scene (photo, blood, GSR). Below that: examined by, when and where.
  - **From this body:** bags taken from the same body (bullets, blood) are listed under it, with their codes. Tapping one jumps to its item, and those items carry a red "Body L1" tag.
  - **Copy report as text** puts whip_evidence's full report text on the clipboard, ready to paste into an MDT report.
- **Copy buttons** (a small copy icon) on codes: weapon serials, ballistics, prints, blood types, sole patterns, tread patterns, fibre codes, readable plates from crime scene photos, each item's ref and the case number. One click (or **A** on a controller, Enter on a keyboard) copies, a "Copied serial number: …" toast confirms it, and the button flashes green. This works in FiveM's in-game browser (hidden text box + copy command), with the browser clipboard as a fallback.
- **Crime scene photos** list the bodies in frame (whip_evidence 4.2.3): "L1 Body · Gunshot ×3 · 4 m".
- The report item is not shown twice: its item tile keeps a short "Cause of death" chip and leaves the long findings text to the panel.
- The server passes only what the page draws: known wound types, body parts and ranges, with lengths capped. It never sends positions or entity ids.
- Docs: [docs/whip_evidence_integration.md](docs/whip_evidence_integration.md) section 11 covers 4.2.3.

## es_mdt 2.0.16 (2026-11-19)

**Ready for whip_evidence 4.2.2** (LeSiiN). Its API is unchanged, so 2.0.15 already works with it. This release tidies up what changed around it.

- **New evidence in the case's Evidence locker card and on report chips:** shoe prints 👟, tyre tracks 🛞, glove fibres 🧤, cleaned spots (bleach) 🧴 and restored serial-number lab reports 🔢, each with its own icon and colour.
  - Readable labels for the new lab results: Sole pattern, Shoe size, Tread pattern, Tyre, Glove fibres, Cleaner and Ground.
  - A **partly readable** result (whip_evidence's `quality`, with `?` for unreadable characters) gets an amber "⚠ Quality · Partly readable" chip.
  - Any field whip_evidence adds later shows with a readable label ("Some field") instead of its raw key.
- **Open locker** from the MDT: whip_evidence 4.1+ runs a 1 s "Opening locker" bar at the locker. If the officer moves and the bar is cancelled, the MDT now says "Opening the locker was cancelled. Stand still at the evidence locker and try again" instead of "Go to an evidence locker first". whip_evidence's own reasons (not at a locker, rank level too low) are shown as they are.
- **/departments:** whip_evidence 4.1+ decides who may do what by **rank level** in `/whip` → Settings → Forensics → "Lowest rank level", no longer by job permissions. With such a version on the server, the "Upload evidence to cases (whip_evidence)" and "Close evidence lockers (whip_evidence)" switches are hidden from the rank editor (what they held is kept), and a note points to `/whip` → Forensics. With whip_evidence 4.0 they show as before.
- Docs: [docs/whip_evidence_integration.md](docs/whip_evidence_integration.md) section 10 covers 4.2.2: the rank-level defaults, the controller buttons it shares with the MDT (the MDT's panic, respond and backup keep them), and the two config lines to set again after an update.

## es_mdt 2.0.15 (2026-11-19)

**Backup on a call now joins that call instead of making a new one.**

- **Asked by an officer attached to a call** (the MDT's Request backup, `/backup` or the controller): no new call.
  - The call is marked **🚨 Backup requested**, with who asked (callsign, name, department) and when, in each player's own clock. This shows as a banner in the call's details and on the call card, and as a badge in the Dispatch list, on the call board and on the Live map.
  - It goes up to the backup priority (`backup.priority`, or `urgentPriority` on a panic or P1 call) and never down. At P1 its map blip flashes, and its search circle takes the new colour.
  - Every unit the call is routed to gets it again, with the card and sound, **except the officer who asked**.
  - A timeline note: "Backup requested by 1-A-21 Kara Vance (LSPD) · P2 → P1".
  - A **🚨 Backup marker follows the officer who asked**, on the GTA minimap and pause map and on the Live map, with a dashed line to the call. The call keeps its own location and search circle. The asking officer still sees a marker for each responding unit, as before. The marker stops when they go off duty or leave, and goes when the call closes.
  - **Respond** attaches to the call itself.
  - Asking again (after the cooldown, which is kept) refreshes the banner ("asked 2×") and alerts the units again.
- **Backup with no call** is still its own backup call that follows the officer, as before.
- `/whip` → Settings → MDT: **"Backup on a call joins that call (no new call)"** (`Config.Dispatch.backup.merge`, on by default; off = the 2.0.6 separate backup call). The marker's look is `backup.marker`.
- After a restart, the banner of active calls comes back from their timeline. The follow marker comes back only when backup is asked again.
- Performance: nothing new runs on the client. The marker is moved by the server's existing 4 s follow check, only while a backup is being followed.
- The "Changed by …, <time>" line under a setting in `/whip` → Settings is drawn by whip_core (its date is formatted in whip_core's server code), so es_mdt cannot change its time zone.

## es_mdt 2.0.14 (2026-11-19)

**Fix: a witness call's search circle now shows on the GTA minimap and pause map for as long as the call is active**, not only on the MDT's Live map.

- **What was wrong:** the circle was part of the call's map blip, and that blip comes down after `Config.Dispatch.blip.seconds` (120 s). A shots-fired call's 120 m circle was gone from the minimap and pause map after 2 minutes, while the Live map kept showing it until the call closed.
- **Now:** the circle is its own map blip (circle only, no icon), in the call's priority colour: P1 red, P2 orange, P3 blue. Only the on-duty units the call is routed to see it, and it follows clock-on and clock-off like the call blip. It moves and shrinks when repeat reports narrow the area, and takes the new colour when the call escalates. It goes when the call is closed or auto-closed, and comes back for active calls after a restart or `ensure es_mdt`. The call's dot and name still go after `blip.seconds`, as before.
- `Config.Dispatch.blip.areas = false` goes back to the old behaviour (the circle leaves with the dot).
- Performance: nothing new runs on the client. It is one blip per circle call, sent only when the call is filed or changes.

## es_mdt 2.0.13 (2026-11-18)

**Controller support everywhere in es_mdt.** On a gamepad, officers can open the MDT, panic, respond, call backup and use the call board and radar remote. Every es_mdt screen also works with the pad: the MDT, Live map, call board, radar remote, permit application, Departments and DOJ. See [Controller](README.md#controller).

- **Buttons in the world** use WHIP's own pad system (`RegisterPadAction`, the slots left free on a WHIP server). Every press is LB + a button, so nothing clashes with driving or combat:

  | Button | Does | Notes |
  |---|---|---|
  | LB + Y | open / close the MDT | |
  | LB + D-pad ▲ (**hold 1.5 s**) | **panic** | a red ring fills as you hold, so it can't go off by accident; works while downed or dead and inside screens |
  | LB + D-pad ◀ | respond to the call card shown (+ GPS) | **hold** 0.6 s: hide the card |
  | LB + D-pad ▶ | request backup | |
  | LB + D-pad ▼ | the call board | **hold** 0.6 s in a radar vehicle: the radar remote |
  | (none) | radar on / off | a player can put it on any button on the pause menu's Controller screen, in a vehicle only |

  Players can move any of them on the pause menu's **Controller** screen (whip_core). Keyboard keys are unchanged.
- **Screens on a pad:** a blue focus ring on the selected item. D-pad or left stick moves it, **A** selects, **B** goes back or closes (dialogs first), **LB / RB** switch tabs (MDT pages, the permit form's photo tabs, Department tabs, DOJ pages), **LT / RT** or the right stick scroll, **X** search (opens the keyboard), **Y** jumps to the tab list, and **Start** closes. The mouse cursor hides while the pad is in use and comes back with the mouse.
- **Text boxes:** **A** on a text box opens WHIP's on-screen keyboard (`OpenKeyboard`, with GTA's keyboard as a fallback). Its title is the field's label, it is limited to the field's length (number pad for numbers), and Enter follows (a search runs).
- **Live map on a pad:** the left stick pans, the right stick or LT / RT zoom about the centre cross, **A** opens the pin nearest the cross, **X** fits everything, and **Y** goes to your unit.
- **Hints:** a bar at the bottom of each screen shows the buttons (Xbox or PlayStation pictures) on a pad and the keys on a keyboard. It switches by itself when you change device. The call card and call board show the pad buttons too ("LB + ◀ Respond + GPS", "hold Hide").
- **`/whip` → Settings → MDT → Controller** (live, 8 settings): controller support on/off; the MDT buttons, screen navigation, the on-screen keyboard and hints each on/off; and the hold times for panic (1.5 s), hiding a card (0.6 s) and the radar remote (0.6 s).
- **Pause menu → Settings → Server Settings → Controller** (each player, kept on their PC, next to WHIP's own cursor speed): MDT controller support on/off, stick speed (25–300%), and button hints (Xbox, PlayStation or off).
- **Performance (the 2.0.10 rules kept):** nothing runs per frame when no es_mdt screen is open. The pad is only read while a screen is open (WHIP's `padScreen`), and stick moves are sent at most 20 times a second, only while the stick moves. A hold runs a 50 ms check only between press and release. The buttons in the world are WHIP's own checks, with nothing added.
- **Fix:** the call board no longer comes back on screen if you close it within 2.6 s of pressing Respond / Leave (the "Responding" note's timer redrew it).
- `mdt/config.lua` gains `Config.Controller`. An older `config.lua` without it gets the defaults.

## es_mdt 2.0.12 (2026-11-18)

**The radar is back to in-vehicle only: no Radar tab in the MDT.** It stays part of es_mdt (one resource), as the in-car panel and the F7 remote, with its `/whip` settings and each player's pause-menu settings from 2.0.11.

- **Removed:** the MDT's Radar tab, its "Radar tab in the MDT" setting, the tab's plate-hit list and list sizes (`mdtTab`, `historyLimit`, `recentReads`), the plate reads sent to the tab, and the Live map pin it used. `html/mdt/radartab.js` / `radartab.css` are gone.
- **Kept from 2.0.11:**
  - **`/whip` → Settings → MDT → Radar** (19 settings, live): radar on/off, which departments and vehicle classes / models get it, the default unit and speed alert, range, beam, plate camera range, scan rates, plate re-check time, hit levels, the hit alarm, auto-lock allowed, and how long plate hits are kept (30 days, cleaned hourly).
  - **Pause menu → Settings → Server Settings → Radar:** auto-on in a police vehicle, volume, mute, lock sound, beep, own speed alert, units, panel size and position.
  - Plate hits still go to the server's plate-hit log and move a BOLO's last-seen point, as before.
- **Fix:** a save from the remote no longer resets choices it does not send (e.g. auto-on set in the pause menu).
- The radar is only in es_mdt: no other radar resource is needed or started.

## es_mdt 2.0.11 (2026-11-18)

**The police radar and plate reader are now a Radar tab in the MDT, with an admin Radar group in `/whip` → Settings → MDT and each player's own radar settings in the pause menu.** See [Radar](README.md#radar) (the tab was removed again in 2.0.12).

- **Radar tab in the MDT** (police, sheriff and state police, plus staff; an admin can hide it):
  - **Status at a glance:** *Live*, *Off*, *Not in a police vehicle* or *Go on duty to use it*, and one switch to turn the radar on or off.
  - **Live readout:** your speed, and each antenna's target and fast speeds. An antenna glows red over your speed alert. Each camera shows its plate in red (hit), amber (note) or "✓ Clear". It is the same readout the in-car panel gets, sent only when something changed, so the tab costs nothing extra.
  - **Controls:** each antenna on or off and Same / Opposite / Both. Lock or unlock speed and plate, clear all locks, the speed alert (− / + / slider), beep, auto-lock, plate reader and mute.
  - **Read this shift:** every plate your reader read (newest first, on your own PC, 25 by default) with its hit or note, model and owner, which antenna and when. Each has **Look up** (Vehicles), **⚑ BOLO** (form filled with the plate and model), **Owner** (their profile) and **⌖ Map**.
  - **Map** opens the Live map on a pin where the plate was read, with Waypoint, Vehicle and Remove the pin. Without the Live map it sets a waypoint instead.
  - **Plate hits:** every BOLO, stolen and warrant read on the server, from any officer, with who read it, when and where. *Everyone* or *Mine*.
  - **Check a plate:** type any plate for its owner, model and hits, with the same buttons.
  - The tab tells the game when it is open; plate reads are only sent while it is.
- **Radar group in `/whip` → Settings → MDT** (live on Apply, **Reset** goes back to `config.lua`):
  - Radar on or off for the whole server, the Radar tab on or off.
  - Which department types and vehicle classes (and extra models) get it.
  - The default speed unit and speed alert.
  - Range, beam width, plate camera range, how often it measures (moving and parked), and how soon a plate is checked again.
  - What counts as a hit for a BOLO, stolen car, owner with a warrant and unregistered car: *Alert*, *Amber only* or *Ignore*.
  - Plate-hit alarm sound, whether players may use auto-lock, how long plate hits are kept (30 days by default, 0 = forever, cleaned hourly), how many show in the tab, and how many reads each officer's tab remembers.
  - **Commands and keys (restart)** gains the radar on / off and remote keys.
- **Each player's own radar settings** in the pause menu → Settings → Server Settings → **Radar** (kept on their PC, the same values as the remote and the tab):
  - Turn the radar on when getting into a police vehicle.
  - Volume, mute, lock sound, and beep over the speed alert.
  - Their own speed alert. Until they pick one, it follows the server's.
  - Speed unit (the server's, mph or km/h).
  - Panel size (60–160 %) and position: a corner, or wherever they dragged it.
- **Remote (F7):** gains Mute and hides auto-lock when an admin turned it off.
- **Upgrading:** an older `config.lua` (`lawTypes` / `classes` maps, `hits = false`) still works. The new keys fill in with their defaults.

## es_mdt 2.0.10 (2026-11-18)

**The simple department and DOJ settings move into `/whip` → Settings → MDT, changed live. Plus a performance pass: less work every frame, fewer lookups and smaller network updates.** See [Changing settings live](README.md#changing-settings-live) and [Performance](README.md#performance).

- **Six new groups in `/whip` → Settings → MDT** (live on Apply; `config.lua` stays the defaults and **Reset** goes back to it):
  - **Departments: activity:** the inactive yellow / orange / red day lines, the rank level that counts as a department head (0 = each department's top rank), notes on a head's account, how often heads are checked and duty time is saved.
  - **Departments: leave (LOA):** the longest leave, how far ahead it may start, the longest reason.
  - **Departments: training and certifications:** ride-alongs a trainee needs, the ride-along checklist (comma-separated), the certification expiry warning, and whether FTOs also need a valid FTO certification (and which one).
  - **Departments: logos:** the largest logo size and file.
  - **DOJ: access and warrants:** police read-only access to the DOJ tablet, off-duty read only, warrants needing a judge, warrant expiry, judges notified of requests, hearing reminders, the name-change cooldown, the bar number prefix.
  - **DOJ: fees, bail and sentences:** every fee (filing, name change, business license and how long it lasts, expungement, appeal, record copy), when court fines are due, where court money goes, bail limits and the bond percentage, and the sentence caps.
  - **Commands and keys (restart)** gains `/departments`, the DOJ tablet command and key, and the DOJ portal command.
  - **`/departments` keeps** what belongs to each department: departments, colours, logos, ranks, permissions, rosters, hiring, each department's FTO program and its health page, which now says where the day lines are set.
- **Performance:**
  - **Shots fired** no longer checks every frame while a gun is in hand. It looks 4 times a second and spots a shot from the gun's ammo going down while aiming or pulling the trigger (a reload is not a shot). On-duty law is skipped on the client too, asked once a minute and again on any clock on or off. The server still makes the final call.
  - **Who you are in the MDT** (department, permissions) is kept 30 s instead of 3, and dropped at once when your job changes (clock on / off, hire, fire, rank) or a job or department is edited.
  - **The on-duty list** behind the Units tab, the Live map, dispatch and the call board is kept 1 s and dropped at once on any clock, roster or department change. Statuses still show at once.
  - **Live map:** opens on a 2048 px picture (209 KB, a quarter of the memory) and loads the 4096 px one only when you zoom in past the city view. Both are let go when you leave the tab. Responding lines are still; only the selected unit's or call's lines move. It opens a little further out (the city around you).
  - **Radar:** looks half as often while parked, sends the readout to the screen only when something on it changed, and forgets plates read more than 10 minutes ago.
  - **Backup / panic follow** keeps the units on the call in memory instead of reading them from the database every 4 s.
  - **"Look again" updates** (a status, a warrant, a BOLO) go only to on-duty units and players with the MDT open, not to every player on the server.
  - **The 5-minute clean-up** now also clears old repeat-report notes, explosion cool-downs, per-kind alert counts and the routing of calls that are closed.
- **Fixes:** the certification warning window is read live (it was read once at start). An unset `Health.headLevel` means each department's top rank.

## es_mdt 2.0.9 (2026-11-18)

**Backup and panic calls follow the officer who asked, with a marker for each unit coming. Plus a new Live map tab: every unit and call on an interactive GTA map, updated live.** See [Live map](README.md#live-map) and [Backup and panic follow the officer](README.md#backup-and-panic-follow-the-officer).

- **Backup and panic calls follow the officer** (`Config.Dispatch.follow`, or `/whip` → Settings → MDT → *Backup and panic follow the officer*):
  - The server reads the officer's position itself every 4 s (`seconds`). Once they have moved 10 m (`minMove`), it moves the call's blip and its spot, so Respond, GPS and the arrival check all use where the officer is now.
  - Units on the call get their GPS moved too, at most every 10 s (`gpsSeconds`), and only once the officer is 35 m (`gpsMove`) from where the route points. A waypoint a unit set somewhere else is never touched.
  - The officer who asked sees a marker on their map for each unit coming ("Responding · 1-A-12"), live. A marker goes away when that unit is 40 m away (`arriveDistance`) or On scene, or when the call ends. They get a notice when a unit starts responding and when it arrives.
  - Following stops when the call closes or auto-closes, or the officer goes off duty or leaves. The call then stays where they were last, with a note on it.
  - Backup and panic can each be switched on or off. Calls followed when the server restarts stay where they were.
- **Live map tab in the MDT** (`Config.LiveMap`, or `/whip` → Settings → MDT → *Live map*):
  - Every on-duty unit: callsign, name, department colour, status, in a car or on foot, heading, and speed in a vehicle. Your own pin is marked.
  - Active calls in priority colours, critical calls pulsing, witness calls' search circles, a dashed line from each responding unit to its call, and where BOLO plates were last read.
  - Drag to pan, scroll or double-click to zoom, keys `+` `−` `0` and the arrows. Pins glide between updates. Buttons: zoom, centre on me, fit everyone, and a dark or a colour map.
  - Click a unit for its details (status, moving, heading, distance from you, its call) with Waypoint, Follow on the map and Profile. Click a call to see it with Respond + GPS, GPS and Open call.
  - A side list of units by department and calls (critical first), search, department filters with counts, and a Layers menu (units, calls, search areas, responding lines, BOLO plates, labels).
  - It refreshes every 2.5 s (`Config.MapRefreshMs`), only while the tab is open and the MDT is on screen.
  - Who sees what: calls follow the Dispatch tab's routing. Units: `units = 'group'` (their dispatch group: police, sheriff and state police together; EMS), `'own'` (their department) or `'all'`. Admins see everything. The tab can be switched off for officers.
  - The map picture: see [the map picture](README.md#the-map-picture). Point `Config.LiveMap.image` at your own picture, or delete the file to get a plain grid. The map still works without it.
  - It replaces the old map in the Active units tab, whose button now opens the Live map.

## es_mdt 2.0.8 (2026-11-18)

**Change the MDT live from WHIP's admin panel, set your own MDT size and alert sound from the pause menu, robbery calls named by the store, and speeding alerts the admin sets up.** See [Changing settings live](README.md#changing-settings-live).

- **Admin panel: `/whip` → Settings → MDT.**
  - About 100 settings in seven groups: Calls, Alerts on screen, Repeat reports and search areas, Automatic alerts, Records, fines and jail, Display size, and Commands and keys (restart).
  - Changes apply as soon as you press Apply, with no restart. This covers dispatch (cooldowns, routing, auto-close, the hard cap, retention, the critical alarm, sounds, merging, search circles, every automatic alert), the panic cooldown, the display size range and default, the jail provider, record minutes per month, off-duty read only, the fine cap, unpaid-fine warrants, warrant BOLOs, the map refresh, urgent-announcement hours and the whip_evidence bridge.
  - Sub-options are hidden until their switch is on.
  - Commands, keys, the 911/311/medical command names, chat suggestions and DevTools are under **Commands and keys (restart)** and take effect after a restart.
  - `config.lua` is still the defaults. A value saved in the panel overrides it, and **Reset** goes back to it.
  - Under the hood, values that used to be read once at start (detectors, the backup and call-board switches, the popup timer, the alarm repeat, the sweep interval) are now read each time.
- **Pause menu: Settings → Server Settings → MDT** (each player, saved on their PC):
  - **MDT display size** (the same setting as the **Aa** button and `/mdtscale`), **Dispatch alert volume** and **Mute dispatch alerts**.
  - **Reset this tab** goes back to the server's defaults.
  - The help text says where keys are rebound: GTA Settings → Key Bindings → FiveM.
- **Robbery calls name the store:**
  - `StoreRobbery`, `BankRobbery` and `JewelryRobbery` are titled with the nearest known place, e.g. **"24/7 Supermarket, Innocence Blvd"**, **"Fleeca Bank, Legion Square"**, **"Pacific Standard Bank, Vinewood Blvd"** or **"Vangelico Jewelry, Rockford Hills"**. This shows on the card, in the MDT and on the call board.
  - There are about 60 built-in places: 24/7, LTD, Rob's Liquor, Ammu-Nation, clothing stores, barbers, every Fleeca, Paleto, Pacific Standard and Vangelico.
  - Name lookup order: `data.storeName` / `label` from your script, then the script's store id mapped in `Config.Dispatch.places.ids`, then the nearest place within `places.radius` (40 m). If none match, the title is "Store, <street>".
  - Add or rename places in `Config.Dispatch.places.extra` or in the panel. Only reports at the same store merge now.
- **Speeding alerts set up by the admin** (`Config.Dispatch.alerts.speeding`, or the panel):
  - Settings: on/off, **units (mph or km/h)**, **limit** (80), **highway limit** (110, on roads named Fwy, Freeway, Hwy, Highway, Route or Interstate; 0 means one limit everywhere), **seconds over the limit** (4), cooldown, chance and priority.
  - The alert reads e.g. **"112 mph in a 80 zone"**. The server still checks the speed itself.

## es_mdt 2.0.7 (2026-11-18)

**Dispatch: ready-made alerts, a critical tier, merged repeat reports, search circles, suspect details, more automatic alerts, a quick call board, and call retention. Also fixes the evidence locker and the panic message.** See [Dispatch: alerts, critical calls and the call board](README.md#dispatch-alerts-critical-calls-and-the-call-board).

- **Ready-made alerts for other scripts** (server exports, set in `Config.Dispatch.presets`):
  - `StoreRobbery`, `BankRobbery` (Fleeca, Paleto or Pacific), `JewelryRobbery`, `HouseRobbery`, `DrugSale`, `Explosion`, `Fight`, `SuspiciousActivity` and `Carjacking`, plus `Alert(name, data)` for any preset, including ones you add.
  - Each preset sets the call kind, priority, title, icon, blip and who gets it. Pass `player = source` and the server reads that player's position, car (plate and colour) and weapon itself.
  - New call kinds: `robbery`, `drugs`, `explosion`, `fight`, `suspicious`, `down` and `speeding`.
- **Critical tier, above P1** (`Config.Dispatch.critical`):
  - Critical calls are the panic button (OFFICER DOWN) and presets with `critical = true` (Paleto and Pacific Standard by default). Escalation never makes a call critical.
  - The card pulses and shows a CRITICAL badge, and the blip flashes.
  - The alarm repeats every 4 s, up to 8 times, until the unit acknowledges it (Respond or Hide on the card, Ack on the call board), a unit responds, or the call closes.
- **Alert sounds:**
  - Three tiers: routine, P1 and critical.
  - Each player sets their own volume, or mutes them, in the **Aa** popover or with `/mdtvolume <0-100|mute|unmute>`. The setting is saved on their PC.
  - Sounds play in the page (`Config.Dispatch.sounds.engine = 'nui'`, the default). `'game'` uses GTA's sounds; mute still works there, volume doesn't.
- **Repeat reports merge** (`Config.Dispatch.merge`):
  - A report of the same kind (and preset) within 150 m while the call is fresh (3 min since its last report) goes onto the open call. The call shows **×3 reports**, gets a note, and its priority can only go up.
  - Panic, backup and officer calls never merge. Plain `alert` calls without a preset (es_jail's, `NotifyDispatch`) stay one call each, unless the script passes `merge = true`. Any call can pass `merge = false`.
- **"N responding"** on the card, in the MDT list and in the call's page.
- **Search circle for witness reports** (`Config.Dispatch.witness`):
  - Automatic alerts and witness presets show a circle (120 m) on the map, the blip and the board instead of a pin. The exact spot is inside it, but never at its centre.
  - Each repeat report shrinks the circle (×0.75, down to 40 m) and it still contains the spot.
  - **The true position never leaves the server.** Players get only the circle's centre and radius. Arriving counts anywhere inside the circle.
- **Suspect details:** plate, vehicle, colour, direction, a short description, and the weapon as a class with a threat grade (Melee 1 to Explosives 5). Everything is cleaned server side, and the exact weapon is never sent.
- **More automatic alerts** (`Config.Dispatch.alerts`):
  - **Fights:** melee hits with a witness nearby.
  - **Explosions:** from the game's explosion event; harmless types like steam, flames, flares and smoke don't count.
  - **A civilian down:** after 20 s, sent to EMS (or law if there's no EMS); the server checks they really are down.
  - **Speeding:** off by default; the server checks the speed itself.
  - Each alert has its own toggle, chance, cooldown and priority. On-duty law never sets them off.
  - At most `perMinute` (6) new calls of one kind a minute, server wide. Reports near an open call still merge.
- **Quick call board** (key **O**, or `/callboard`; rebindable):
  - A compact overlay with the active calls you can see (critical first) and their units, reports, search area and details.
  - Buttons: **Respond** (attach and GPS), **Waypoint**, **GPS** and **Leave** for your own call, and **Ack alarm**. It updates live and follows the display size. Press Esc or O to close it.
- **Call retention** (`Config.Dispatch.keepClosedDays = 90`; 0 keeps every call):
  - **Closed** calls older than that are deleted with their notes and unit rows, at start and once a day, in batches of 500 with a pause between them. The console logs the counts: `[es_mdt] call retention (90 days): removed N closed call(s), …`.
  - Open calls are never deleted, and neither are calls linked to a report, warrant or case. Link one with **＋ Link report / warrant / case** on the call's page or `exports.es_mdt:LinkCall(callId, 'report', id)`.
  - Before this, calls were kept forever.
- **Fix: Open locker from a case in the MDT.**
  - whip_core doesn't open an inventory or stash while another screen (the MDT) is open. The server said "opened" but the stash never showed, and pressing again hit the rate limit ("Rate limited").
  - Now the button closes the MDT, waits until no screen is open, then asks for the locker once. The stash opens and the MDT stays closed. A second press while that's under way does nothing, and a refusal (not at a locker, no access) is a notice.
  - The MDT page also retries a request that hit WHIP's rate limit (twice, under a second), so a burst of normal clicks doesn't show "Rate limited". The locker's and the case page's own limits were loosened a little.
- **Fix: the panic message** is now a short green notice, "Panic sent · units alerted". It was a red, cut-off "OFFICER DOWN sent. Units on duty have your lo…".
- **Database:**
  - New `es_mdt_calls` columns: `preset`, `critical`, `reports`, `lastReportAt`, `fx`, `fy`, `radius`, `details`, `reportId`, `warrantId`, `caseId`, plus the key `idx_es_call_closed (status, closedAt)`.
  - Migration `005_dispatch207` adds them on existing servers; fresh installs get them in the table. The schema self-check covers them.
- **Unchanged:** close outcomes, silent auto-close, escalation, backup, the unit list, the panic key (END, also while downed), GPS and blip clean-up, admin-only source labels, the external event, `/911` and `/311`, and es_jail's alerts.

## es_mdt 2.0.6 (2026-11-18)

**Dispatch: routing, a live unit list, officer-down panic key, request backup, escalation, and shots-fired and vehicle-theft alerts.** See [Dispatch: routing, panic, backup and alerts](README.md#dispatch-routing-panic-backup-and-alerts).

Already in 2.0.5 and kept: `/911` and `/311` with street and position added automatically and a per-player cooldown; `/panic` for on-duty officers with a cooldown, which the server already accepted from downed players; the units on a call; close outcomes, silent auto-close, blip and GPS cleanup, and admin-only source labels.

- **Routing (`Config.Dispatch.routing`):**
  - Calls go to groups of department types: `law` (police, sheriff, state) and `ems`. 911 goes to law and EMS; 311, shots, theft and officer calls go to law; medical calls go to EMS; officer down goes to law and EMS.
  - Only those groups' on-duty units get the card, sound and blip, and see the call in the Dispatch tab. A group with no department on the server is skipped, so with no EMS department 911 and medical calls go to law. `fallback` covers calls that reach no group.
  - `shared = true` lets every group see every call in its Dispatch tab.
  - DOJ gets no calls. Staff see everything. Calls from before 2.0.6 are still shown to everyone.
- **Medical line:** `Config.Dispatch.medical = 'ems'` adds `/ems <what happened>`, routed to EMS. It's off by default. Other scripts can file `AddCall({ kind = 'medical' })`.
- **Chat suggestions** for `/911`, `/311`, `/panic`, `/backup` (and `/ems`) in whip_chat or stock chat (`chatSuggestions`).
- **Live unit list:** the call card and the MDT show each unit on a call as callsign, name and status, and update as units attach or leave.
- **Panic / officer down:**
  - It now has a key by default, **END**, on a new key mapping (`mdt_panic_key`, rebindable under GTA Settings → Key Bindings → FiveM). F9 was not used because whip_core binds it for the Systems and Director editors. Players who bound a key to the old `/panic` mapping keep it.
  - It works while the officer is downed, injured or dead: there's no health, ragdoll or death check on the client or the server, and the server callback is `whileDead`.
  - It's still on duty only, with a cooldown (`Config.Panic.cooldown`, 15 s).
  - It files a P1 **OFFICER DOWN · <callsign> <name>** call at the officer's position for law and EMS (`Config.Panic.title`).
- **Request backup:** an attached officer can press **Request backup** on the call in the MDT, or use `/backup` (bindable, unbound by default). It files a backup call at their position, linked to their call and sent where that call went. It's P1 when the call is a panic or P1, otherwise `priority` (P2), with a cooldown (45 s). It also works while downed.
- **Escalation:** a call nobody attached to goes up one priority every `escalate.minutes` (5), stopping at `top` (P1). A panic is never escalated. The MDT updates quietly, and `realert = true` gives the units one soft tone and the card again.
- **Shots-fired and vehicle-theft alerts (`Config.Dispatch.alerts`):**
  - Each has its own toggle, chance (how often a witness calls it in), cooldown and priority.
  - On-duty law never sets them off. Suppressed weapons and harmless weapons (stun gun, extinguisher and so on) don't count, and Ammu-Nation ranges are quiet zones.
  - A second report near an active call adds a note to it, not a new call.
  - New exports for other scripts: `exports.es_mdt:ShotsFired(coords, opts)` and `VehicleTheft(coords, plate, model, opts)`.
- **Database:** `es_mdt_calls.audience`, `parentId`, `escalations`, `escalatedAt`. They're added by migration `004_dispatch206` on existing servers and created with the table on fresh installs. The 2.0.5 schema self-check covers them too.
- **Unchanged:** close outcomes, silent auto-close (it never re-alerts, and runs before escalation), blip and GPS cleanup, admin-only source labels, `AddCall` / `NotifyDispatch` / `CloseCall` / `TestCall`, and es_jail's alerts.

## es_mdt 2.0.5 (2026-11-18)

**Database fix and a startup schema self-check.** Fixes `Unknown column 'kind'` (MDT dashboard, warrants) and `Unknown column 'origin'` (issuing a weapon license) on servers that installed 2.0.x on an empty database.

- **The cause:** when WHIP's `EnsureTable` creates a table, it records all of that table's migrations as done without running them, because it expects the CREATE statement to already have every column. Some es_mdt CREATE statements were missing columns that only a migration added: `es_mdt_warrants` (`caseId`, `kind`, `scope`, `judgeCharId`, `judgeName`, `judgeNote`, `decidedAt`, key `idx_es_war_case`), `es_mdt_weapon_licenses` (`origin`) and `es_mdt_reports` (`caseId`, key `idx_es_rep_case`). So a fresh install never got them, and the migrations never ran later. Servers that upgraded from 1.x got them through the migrations and were not affected.
- **Fixed:** every CREATE statement now has every column and key its migrations add. The migrations stay, for older databases.
- **Safeguard: schema self-check on every start.** Every es_mdt table (MDT, Departments, DOJ and jail; 68 tables) now goes through `EsSchema.ensure` (`server/schema.lua`). Each table's CREATE statement is its single source of truth for columns and keys. On every start, after the migrations, es_mdt compares that list with the live database (`information_schema`) and adds any missing column or key. It never drops, renames or changes an existing column, key or row, and it doesn't add foreign keys or primary keys. Missing columns no longer depend on a migration marker in `schema_migrations`: a skipped or wrongly recorded migration is caught at the next start.
  - Each fix is logged: `[es_mdt] schema: added missing column `es_mdt_warrants`.`kind``.
  - A fix that fails prints a red **SCHEMA ERROR** block in the server console with the exact SQL to run by hand, and is reported as a WHIP start problem. It never fails silently. About 20 seconds after start, one line sums it up: `[es_mdt] schema check: 68 tables OK`, or the list of problems.
  - If a migration fails but the table still ends up with every column and key, es_mdt logs it and carries on. whip_core retries the migration at the next start.
- **Upgrading:** nothing to do. Start the server: a database with missing columns is repaired on the first start, and the console lists what was added.
- **Tested** against a real MariaDB database with whip_core's own migration code: a fresh database, an old 1.x database with data in it, a broken 2.0.4 fresh install (the reported errors reproduced, then repaired), extra columns and keys left untouched, and a fix that fails (loud error, the other fixes still made, repaired at the next start).

## es_mdt 2.0.4 (2026-11-18)

**Call outcomes, silent auto-close, GPS cleanup, announcement priority.** See [Dispatch: closing calls, auto-close and announcements](README.md#dispatch-closing-calls-auto-close-and-announcements).

- **Close outcomes:** closing a call opens a picker: Resolved, Handled on scene, Unfounded, No contact, Suspect gone, Other (keys 1 to 6). Other needs a note. The server checks the outcome against `Config.Dispatch.outcomes`, which now takes `{ label, color, icon, note }` (plain strings still work). The outcome, note, closer and time are saved on the call. Each outcome has its own coloured badge in the call list, on the call page and in its timeline. Calls closed before 2.0.4 with no outcome read **Closed**.
- **Auto-close:** `Config.Dispatch.autoCloseMinutes` (15; 0 = off) replaces the old 2-hour expiry, and a sweep runs every `sweepSeconds` (60). Calls with a unit on them are left open unless `autoCloseAttached = true`. `callTTLMin` (120) stays as the hard cap for those. Panic calls with a unit on them are never auto-closed. The outcome is `Auto-closed – no response` (nobody ever attached) or `Auto-closed (timeout)` (someone did, even if they left), each with its own badge. Auto-close is **silent**: no popup, sound, toast or notification. The call stays in the history with a note. Fixes `callTTLMin = 0` closing every call instead of none.
- **GPS and blip cleanup:** when a call closes by any path, everyone's waypoint that still points at it is cleared (call card, Set waypoint, attach, partner, `/panicgps`). A waypoint moved elsewhere stays. Officers who go off duty, log out or disconnect are taken off their calls (with a timeline note), and their call blips, route and cards go. Call and panic blips follow the on-duty list.
- **Announcements:** priority Normal, Important or Urgent; cards with a coloured accent; line breaks, `**bold**` and `- ` lists in the message; author, department and time on each card; a live preview when posting. Urgent: a red banner in the MDT, a red in-game alert for everyone on duty, and the banner once for on-duty members who open the MDT within `Config.Announcements.urgentFreshHours` (12).
- `/mdttestcall clear` removes test calls silently.
- **Database:** `es_mdt_calls.everAttached` and `es_mdt_announcements.level`, added by migrations `003_call_close` and `002_ann_level` on existing servers (old calls with units get `everAttached = 1`; closed calls with no outcome get `Closed`), and created with the tables on fresh installs.
- **Unchanged:** 911/311, panic, officer calls, es_jail's alerts and the dispatch exports. The source label stays admin-only.

## es_mdt 2.0.3 (2026-11-18)

**Dispatch API: test calls, blip cleanup on close, admin-only source logging.**

- **Test calls:** `/mdttestcall [kind] [priority]` files a call titled `TEST · <kind>` near you (from the console: at Legion Square). `/mdttestcall clear` closes and deletes every test call. For the server console and staff only (`es_mdt.departments.manage`). New export `TestCall(kind, priority)`.
- **Blips go when a call closes:** the map blip is removed for everyone as soon as a call closes, from the Close call button, the new `CloseCall` export, or the automatic expiry. Closing a panic call also removes its PANIC blip and the officer's panic flag. Every close path now goes through one function.
- **New export `CloseCall(callId, outcome, note)`.**
- **Source labels, admins only:** `AddCall` takes `sourceLabel` (or `source`, `from`, `resource`, up to 40 characters), defaulting to the calling resource. `NotifyDispatch` takes it as an optional 5th string argument, followed by an optional 6th `extra` table. A 5th table argument is still `extra`, as in 2.0.1. `es_mdt:server:externalCall` calls are labeled `external:client` by the server, and labels sent by the client are ignored. The label is printed in the server console and stored in the new `es_mdt_calls.sourceLabel` column. It is never sent to players or shown in the MDT.
- **Database:** a new `sourceLabel` column on `es_mdt_calls`, added by migration `002_source_label` on existing servers and created with the table on fresh installs.
- **Unchanged:** 911/311, panic, officer calls and es_jail's prison break alert. Titles and caller names stay separate.

## es_mdt 2.0.2 (2026-11-17)

**Display size.** Players can make the MDT, Departments and DOJ pages smaller or larger.

- An **Aa** button in each page's header opens a display size popover: a slider from 70% to 150% in 5% steps that resizes the pages as you drag, quick sizes (Small, Default, Large, Larger), and Reset.
- `/mdtscale <percent>` sets it from chat (`/mdtscale 120`, `/mdtscale reset`; `/mdtscale` alone shows the size).
- Each player's size is saved on their PC (client KVP) and used every time a page opens.
- `Config.UI` in `mdt/config.lua`: `defaultScale` (1.0), `minScale` (0.7) and `maxScale` (1.5).
- Each page is scaled as a whole, so it stays centred and on screen. Clicks, menus, dialogs and the photo viewer line up at any size. The dispatch call cards and the radar display are drawn by the MDT page, so they follow the same size.

## es_mdt 2.0.1 (2026-11-17)

**Dispatch API.** Any resource can put a call on the dispatch board. See [Dispatch API](README.md#dispatch-api).

- `exports.es_mdt:AddCall(call)` accepts more field names (`prio`, `desc`/`description`, `location`, `pos`/`position`, `name`/`caller`, `phone`, `charId`) and coordinates as `vector3`, `vector4`, `{x,y,z}` or `{1,2,3}`. It also takes optional blip settings (`blip`, `sprite`, `color`, `blipTime`). Bad coordinates are dropped instead of failing the call.
- A call with no title is named after its kind (`911 call`, `Alert`, ...). A caller's `name` is never used as the title.
- New `exports.es_mdt:NotifyDispatch(title, message, coords, priority)`: the short form, an `alert` call.
- New net event `es_mdt:server:externalCall` for client scripts. Only players on duty, or in the jobs in `Config.Dispatch.external.jobs`, may send it. It is rate limited (one call per 10 s, five a minute), refuses panics, clamps every field, and the caller is always the sender. Set `Config.Dispatch.external.enabled = false` to turn it off.
- Existing callers (911/311, panic, officer calls, es_jail's prison break alert) work unchanged.

## es_mdt 2.0.0 (2026-11-17)

**One resource.** es_departments 1.9.1, es_doj 1.1.0 and es_mdt 1.11.3 are now one resource, named es_mdt.

- Old export names keep working: `exports.es_departments:*` and `exports.es_doj:*` are answered by es_mdt. The manifest also `provide`s both names.
- All tables, data, jobs, permissions, aces (`es_departments.admin`, `es_doj.admin`) and commands are unchanged.
- On first start es_mdt takes over the old resources' migration records and one-time setup marks.
- No `provide 'es_departments'`/`'es_doj'` in the manifest: FiveM would report those names as running, and whip_core would keep the jobs with them. es_mdt takes over the department jobs by itself on its first start.
- The WHIP permission `es_departments.manage` is now `es_mdt.departments.manage` (whip_core wants the resource's prefix).
- One NUI page: each part runs in its own frame, and NUI callbacks are prefixed per part (`dept_*`, `doj_*`).

**Jail bridge: any jail script.**

- `Config.Jail.provider = 'auto' | 'es_jail' | 'custom' | 'none' | '<resource>'`.
- `Config.Jail.custom` reaches a jail script through its exports with no code.
- For jail scripts: `exports.es_mdt:RegisterJailProvider`, `ReportJailRelease` and `ReportJailEscape`, plus events.
- With no jail script, sentences are recorded in `es_mdt_jail_sentences`, counted down in the MDT and shown in the Jail tab. `es_mdt:jail:sent` fires.
- The court's sentences go through the same bridge.

**Test tools.** The test tools are now behind `EsSuite.DevTools` in `shared/suite.lua`, off by default: `/dojtest`, `/ftotest` and MDT → Admin → Test data.

**es_jail 1.1.1:** depends on es_mdt and finds the departments inside it.

## Before 2.0.0 (separate resources)

- **es_mdt 1.11.3:** whip_evidence timeline entries and correct custody times.
- **es_mdt 1.11.2:** whip_evidence page calls fixed ("Unknown call"), and per-event timeline logs.
- **es_mdt 1.11.1:** whip_evidence photo ids; es_evidence parts hidden when it is off.
- **es_mdt 1.11.0:** optional whip_evidence bridge.
- **es_departments 1.9.1:** Health page colors.
- **es_departments 1.9.0:** `evidence_upload` and `evidence_case_close` permissions.
- **es_doj 1.1.0:** attorneys and the bar, fees, bail, appeals, and petitions.
