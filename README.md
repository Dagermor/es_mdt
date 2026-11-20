# es_mdt: emergency services for WHIP

One resource for police, sheriff, state police, rangers, EMS and the courts on a [WHIP](https://whipfx.net) FiveM server:

- **MDT** (`/mdt`, F6): dispatch, reports, warrants, BOLOs, fines as invoices, roadside tickets, impound, cases, evidence, weapons registry, firearm permits, a radar and plate reader, FTO, and personnel. EMS departments get their own side of the MDT (2.5.0): medical calls, patients, incident reports, medical bills, death records and stats.
- **Departments** (`/departments`): departments, logos, ranks, permissions, rosters, duty time, leave, certifications, and department health.
- **DOJ** (`/doj` tablet, `/court` portal): court cases, hearings, judge-signed warrants, verdicts and sentences, pleas, appeals, a clerk desk, the bar and attorneys, petitions, and records.

- **Court phone app** (2.3.0): the `/court` portal as a **Court** app on whip_phone.

Optional companion: **[whip_jobs](https://github.com/Dagermor/whip_jobs)** (the job pack; named es_jobs before its 0.5.0): stations and peds placed in game, duty and pay by rank, armory, fleet, lockers and uniforms, police actions with es_jail's cuffs, EMS down states and the hospital desk, the impound clerk, the courthouse desks, and player-owned businesses. It reads departments and ranks from es_mdt and sends calls to its dispatch.

Optional companion: **es_jail** (handcuffs, breaking out, lockpicking, searching, and Bolingbroke jail with prison jobs). It is included in this repository. Any other jail script also works through the [jail bridge](#jail-integration-for-developers).

> **Status: public test release (2.5.0).** There is no bail system: bail is off by default (`Config.Bail.enabled` in `es_mdt/doj/config.lua`). Read [What is tested](#what-is-tested) before using it on a live server.

## Screenshots

All screenshots use made-up test data.

| | |
|---|---|
| ![Dashboard](docs/images/01_mdt_dashboard.png) MDT dashboard | ![Person](docs/images/02_mdt_person.png) Person profile |
| ![Record](docs/images/02b_mdt_person_record.png) Criminal record | ![Report](docs/images/03_mdt_report.png) Report |
| ![Case](docs/images/06_mdt_case.png) Case with evidence | ![Report evidence](docs/images/06b_mdt_report_evidence.png) Evidence on a report |
| ![Officer](docs/images/05d_mdt_officer_profile.png) Officer profile | ![Jail](docs/images/08_mdt_jail_no_provider.png) Jail tab (no jail script: MDT record) |
| ![FTO](docs/images/07_mdt_fto_trainees.png) FTO trainees | ![FTO overview](docs/images/07b_mdt_fto_overview.png) FTO overview |
| ![FTO file](docs/images/07c_mdt_fto_file.png) Trainee file | ![DOR](docs/images/07d_mdt_fto_write_dor.png) Daily observation report |
| ![Health](docs/images/05_departments_health.png) Department health | ![Roster](docs/images/05b_departments_roster.png) Roster |
| ![Ranks](docs/images/05c_departments_ranks.png) Ranks and permissions | ![DOJ case](docs/images/04_doj_case.png) DOJ court case |
| ![Roadside ticket](docs/images/23_01_roadside_ticket.png) Roadside ticket (/ticket): people close by, penal-code charges | ![Sign prompt](docs/images/23_04_sign_prompt.png) The recipient signs or refuses (countdown) |
| ![Street impound](docs/images/23_06_street_impound.png) /mdtimpound: stolen and BOLO warnings, hold, photo preview, the bill | ![Impound lot](docs/images/23_10_mdt_impound_lot.png) MDT Impound lot: holds, what each owes |
| ![Ticket contest](docs/images/23_09_mdt_ticket_contest.png) A contested ticket: the officer's statement | ![DOJ contests](docs/images/23_16_doj_contests.png) DOJ tablet: Ticket contests (lapsing soon in red) |
| ![Portal impound](docs/images/23_21_portal_impound.png) /court: pay and get an impounded car back | ![Portal payments](docs/images/23_22_portal_payments.png) /court Payments: tickets as invoices with due dates |
| ![DOJ money](docs/images/04b_doj_money.png) DOJ fees and fines | ![Urgent announcement](docs/images/11_urgent_announcement.png) Urgent announcement |
| ![Close a call](docs/images/11_outcome_picker.png) Closing a call: pick the outcome | ![Call history](docs/images/11_history_badges.png) Call history with outcome badges |
| ![Critical call](docs/images/13_critical_card.png) A critical call (alarm until acknowledged) | ![Call board](docs/images/13_call_board.png) The quick call board (O) |
| ![Merged call](docs/images/13_merged_call.png) Repeat reports merged: ×3, 2 responding, details, a linked report | ![Search circle](docs/images/13_search_circle.png) A witness call's search circle on the live map |
| ![Preset alert](docs/images/13_preset_alert_card.png) A ready-made alert (store robbery) with suspect details | ![Alert sounds](docs/images/13_alert_sounds_popover.png) Alert volume and mute in the Aa popover |
| ![Admin settings](docs/images/14_whip_settings_mdt.png) Change the MDT live: /whip → Settings → MDT | ![Speeding settings](docs/images/14_whip_settings_speeding.png) Speeding alerts set up by the admin |
| ![Pause menu](docs/images/14_pause_settings_mdt.png) Each player's MDT size and alert sound in the pause menu | ![Store name](docs/images/14_store_name_card.png) Robbery calls name the store |
| ![Live map](docs/images/15_live_map.png) The Live map: every unit, live | ![Live map call](docs/images/15_live_map_call.png) A call on the Live map: Respond + GPS |
| ![Backup follows](docs/images/15_backup_follow_map.png) A backup call that follows the officer | ![Live map colour](docs/images/15_live_map_atlas.png) The colour map, the whole state |
| ![Department settings](docs/images/16_settings_dept_activity.png) Department activity, live in /whip → Settings → MDT | ![DOJ settings](docs/images/16_settings_doj_money.png) DOJ fees and sentences, live |
| ![In-car radar](docs/images/18_radar_incar_panel.png) The radar in a police vehicle (only there) | ![Radar remote](docs/images/18_radar_remote.png) The radar remote (F7) |
| ![Radar settings](docs/images/18_whip_settings_radar.png) The radar, live in /whip → Settings → MDT → Radar | ![Pause menu radar](docs/images/18_pause_settings_radar.png) Each player's radar settings in the pause menu |
| ![Backup banner](docs/images/20_dispatch_backup_banner.png) Backup asked on a call: the call is marked, no new call | ![Backup marker](docs/images/20_livemap_backup_marker.png) The officer who asked, followed on the Live map |
| ![Post-mortem on a case](docs/images/22_postmortem_card.png) whip_evidence 4.2.3 post-mortem on a case: body overview, cause of death, samples from the body, copy as text | ![Copy codes](docs/images/22_copy_toast.png) One tap (or A on a controller) copies serials, plates, treads and prints |
| ![whip_evidence 4.2 evidence](docs/images/21_case_evidence_new_kinds.png) whip_evidence 4.2 evidence on a case: shoe prints, tyre tracks, fibres, partly readable results | ![Forensics by rank level](docs/images/21_departments_rank_forensics_note.png) Ranks: forensics go by rank level in /whip (whip_evidence 4.1+) |
| ![Controller focus](docs/images/19_mdt_focus_ring.png) The MDT on a controller: focus ring and button hints | ![Controller Live map](docs/images/19_livemap_controller.png) The Live map on a controller: stick pans, triggers zoom |
| ![Controller call card](docs/images/19_call_card_and_panic_hold.png) Call card with pad buttons, and the panic hold ring | ![Controller settings](docs/images/19_whip_settings_controller.png) Controller support, live in /whip → Settings → MDT |

## Requirements

| Resource | Needed | What for |
|---|---|---|
| [whip_core](https://github.com/WHIPFX) (WHIP 1.0+) | **required** | players, characters, jobs, money, items, the UI kit |
| [oxmysql](https://github.com/overextended/oxmysql) | **required** | database |
| es_jail (in this repo) or another jail script | optional | serving sentences. Without one, sentences are recorded in the MDT and their time is counted there |
| whip_evidence (LeSiiN) | optional | forensics. Evidence is uploaded to MDT cases. See [docs/whip_evidence_integration.md](docs/whip_evidence_integration.md) |
| whip_gunny | optional | weapons registry (gun serials) |
| [whip_jobs](https://github.com/Dagermor/whip_jobs) (was es_jobs) | optional | the job pack: stations, duty, pay, uniforms, EMS, the courthouse desks. Start it after es_mdt. The MDT's EMS side reads treatments, bills and EMS stats from whip_jobs **0.6.0+**. Without it, the courthouse clerk window in `doj/config.lua` is used |
| whip_phone | optional | owner texts and the Court phone app |

## Install

1. Copy the `[es]` folder into your `resources` folder. If you don't want es_jail, delete `[es]/es_jail`.
2. Add these lines to `server.cfg` after `ensure whip_core`:

   ```cfg
   ensure es_mdt
   # optional, after es_mdt:
   # ensure whip_evidence_assets
   # ensure whip_evidence
   ensure es_jail

   add_ace group.admin es_departments.admin allow   # create/delete departments in /departments
   add_ace group.admin es_doj.admin allow          # DOJ staff tools (view-as); /dojtest needs DevTools on
   ```

3. Start the server. Database tables are created and migrated automatically; there is no SQL to import. Each start also checks every es_mdt table against the columns the code needs and adds any that are missing (see [Database](#database)). On the first start, five departments are seeded (LSPD, BCSO, SASP, SA Park Rangers and DOJ) with ranks, permissions and logos. Each department is a WHIP job.
4. In game, an admin opens `/departments`, hires the first members (or sets a department owner) and adjusts ranks.

### Upgrading from es_departments / es_doj / es_mdt 1.x

Since 2.0.0 these are one resource. Your data stays where it is: same tables, same jobs, same permissions.

1. Stop the server. Move the old `es_departments`, `es_doj` and `es_mdt` folders **out of** `resources` (two folders with the same name break the server).
2. Put the new `es_mdt` in their place. Update es_jail to 1.1.1 or newer.
3. In `server.cfg`, remove `ensure es_departments` and `ensure es_doj`. Put `ensure es_mdt` where `ensure es_departments` was, before whip_evidence.
4. Start the server. On first start es_mdt takes over the old migration records and one-time setup marks, so nothing runs twice. Look for `took over` in the console.

The old names keep working: `exports.es_departments:*`, `exports.es_doj:*`, the `es_departments.admin` and `es_doj.admin` aces, and every command.

## Commands and keys

| Command | Key | Who | What |
|---|---|---|---|
| `/mdt` | F6 | department members with `mdt_view` | the MDT |
| `/departments` | | department heads, staff | departments, ranks, rosters, health |
| `/doj` | (none, set in config) | DOJ, licensed attorneys, police (read only) | DOJ tablet |
| `/court` | | everyone | public court portal: cases, filings, petitions |
| `/911`, `/311` | | everyone | emergency / non-emergency call to dispatch (street and position added; routed to law / EMS) |
| `/ems` | | everyone | medical call to EMS (off by default: `Config.Dispatch.medical = 'ems'`) |
| `/panic` | END | on-duty officers | panic: P1 OFFICER DOWN at your position; works while downed or dead |
| `/backup` | (none) | officers on duty | request backup: on your call it joins that call (2.0.15), on no call it is its own call at your position |
| `/callboard` | O | units on duty | the quick call board: active calls, Respond / Waypoint / Leave / Ack alarm (2.0.7) |
| `/mdtvolume <0-100\|mute\|unmute>` | | everyone | your own dispatch alert volume (also in the **Aa** popover) (2.0.7) |
| `/ticket` | controller button (choose a slot) | officers with "write tickets" | roadside citation, parking ticket or warning (2.1.0) |
| `/mdtimpound` | controller button (choose a slot) | officers with "impound" | impound the car you stand by, or tow an abandoned one (2.1.0) |
| `/permit` | | everyone | firearm permit application |
| `/mdtscale <percent>` | | everyone | display size of the MDT, Departments and DOJ pages, e.g. `/mdtscale 120`, `/mdtscale reset` |
| radar keys | (none) | police in a vehicle | radar and plate reader (Settings → Key Bindings → FiveM) |
| `/ftotest`, `/dojtest` | | staff, **DevTools only** | solo test tools |
| es_jail: `/jail`, `/unjail`, `/jailtime` | X = struggle | police / inmates | jail (es_jail) |

Players can change every key under GTA Settings → Key Bindings → FiveM. **On a controller** see [Controller](#controller): LB + Y the MDT, LB + ▲ (hold) panic, LB + ◀ respond, LB + ▶ backup, LB + ▼ the call board.

**Display size.** Each player can make the MDT, Departments and DOJ pages smaller or larger with the **Aa** button in each page's header: a slider from 70% to 150% that resizes the pages as you drag, quick sizes, and a Reset. `/mdtscale <percent>` does the same from chat. The size is saved on the player's PC and used every time a page opens. The pages stay centred and on screen at every size. Server owners set the default and the range in `Config.UI` (`es_mdt/mdt/config.lua`).

## Changing settings live

New in 2.0.8. **Change live in `/whip` → Settings → MDT.** `config.lua` is the defaults. A value saved in the panel overrides it until you press **Reset** on that setting.

| Group | What is in it |
|---|---|
| Calls | 911/311 cooldown, shared routing, auto-close and the hard cap, the sweep interval, keeping closed calls (days), escalation, backup requests, panic cooldown |
| Alerts on screen | call cards (on/off, seconds, panic seconds, sound), sounds (engine, default volume), the critical alarm (repeat seconds, max repeats, stop when a unit responds), the call board, urgent-announcement hours |
| Repeat reports and search areas | merging (distance, window), search circles (radius, minimum, shrink), **robbery store names** (`places.radius`, extra places) |
| Automatic alerts | on-duty law exempt, search circles, per-minute cap, and for shots, vehicle theft, fights, explosions, a civilian down and **speeding**: on/off, chance, cooldown, priority and their own options |
| Records, fines and jail | off-duty read only, fine cap, unpaid-fine warrant days, warrant BOLOs, jail provider, record minutes per month, whip_evidence bridge |
| Backup and panic follow the officer | 2.0.9: on/off for backup and for panic, how often the position is read, how far they must move, how often responders' GPS moves, the responders' markers and the arrival distance |
| Radar | 2.0.11: the radar on/off, which department types and vehicle classes / models get it, the default unit and speed alert, range, beam width, plate camera range, how often it measures (moving and parked), plate re-check time, what counts as a hit (BOLO, stolen, owner warrant, unregistered: alert, amber or ignore), the hit alarm sound, whether auto-lock is allowed, how long plate hits are kept |
| Live map | 2.0.9: the tab on/off, whose units officers see (group, own department, all), calls, BOLO plates, speed, the refresh time, the map picture |
| Departments: activity | 2.0.10: the inactive day lines (yellow note, orange warning, red), the rank level that counts as a head (0 = each department's top rank), notes on a head's account, how often heads are checked and duty time is saved |
| Departments: leave (LOA) | 2.0.10: the longest leave, how far ahead it may start, the longest reason |
| Departments: training and certifications | 2.0.10: ride-alongs a trainee needs, the ride-along checklist, the certification expiry warning, FTOs needing a valid FTO certification (and which one) |
| Departments: logos | 2.0.10: the largest logo size and file |
| DOJ: access and warrants | 2.0.10: police read-only access to the DOJ tablet, off-duty read only, warrants needing a judge, warrant expiry, judges told of requests, hearing reminders, the name-change cooldown, the bar number prefix |
| DOJ: fees and sentences | 2.0.10: every DOJ fee, how long a business license lasts, when court fines are due, where court money goes, sentence caps (2.3.1: bail removed) |
| Display size | the MDT size range and the default |
| Commands and keys (restart) | `/mdt` and its key, the 911/311/medical commands, chat suggestions, panic, backup and call-board commands and keys, `/departments`, the DOJ tablet command and key, the DOJ portal command, the radar on / off and remote keys, DevTools. These need a restart. |

Everything except the last group applies when you press **Apply**, with no restart. A setting's options are hidden until it is switched on.

`/departments` keeps what belongs to each department: departments, colours, logos, ranks, permissions, rosters, hiring, each department's FTO program, and the health page.

![Commands and keys](docs/images/14_whip_settings_restart.png)

**Players: pause menu → Settings → Server Settings → MDT.** **MDT display size** (the same as **Aa** and `/mdtscale`), **Dispatch alert volume** and **Mute dispatch alerts**, saved on each player's PC. **Reset this tab** goes back to the server's defaults. Keys (MDT, panic, call board) are rebound in GTA Settings → Key Bindings → FiveM.

**Players: pause menu → Settings → Server Settings → Radar** (2.0.11). Turn the radar on when getting into a police vehicle, radar volume, mute, lock sound, beep over the speed alert, their own speed alert (it follows the server's until they pick one), speed unit, panel size and position. The same values as the remote (F7).

**Robbery calls name the store.** `StoreRobbery`, `BankRobbery` and `JewelryRobbery` are titled with the nearest known place, e.g. "24/7 Supermarket, Innocence Blvd", "Fleeca Bank, Legion Square" or "Vangelico Jewelry, Rockford Hills". About 60 places are built in (24/7, LTD, Rob's Liquor, Ammu-Nation, clothing stores, barbers, every Fleeca, Paleto, Pacific Standard, Vangelico). The name is picked in this order:

1. `data.storeName` (or `label`) passed by your robbery script.
2. Your script's store id or number (`data.store` / `storeId` / `id` / `shop` / `bankId`) mapped in `Config.Dispatch.places.ids`, to a built-in id (`'247_innocence'`, `'fleeca_legion'`, `'pacific'` …) or to a name.
3. The nearest built-in place within `places.radius` (40 m).
4. Otherwise "Store, <street>".

```lua
places = {
    radius = 40,
    ids = { [1] = '247_innocence', ['shop_7'] = 'Davis Liquor' },        -- your script's ids -> a place id or a name
    extra = { { id = 'my_store', kind = 'store', name = 'Corner Shop, Grove St', coords = vector3(100.0, -1800.0, 29.0) } },
},
```

**Speeding** (`Config.Dispatch.alerts.speeding`, off by default): `units` (`'mph'` or `'km/h'`), `limit` (80), `highwayLimit` (110 on roads named Fwy, Freeway, Hwy, Highway, Route or Interstate; 0 means one limit everywhere), `seconds` over the limit (4), `cooldown`, `chance` and `priority`. The alert reads e.g. "112 mph in a 80 zone", and the server checks the speed itself.

## Radar

The police radar and plate reader are part of es_mdt (no separate resource). They show **only in police vehicles**: the in-car panel and the remote (F7); there is no radar in the MDT (2.0.12). On duty in a radar department (`Config.Radar.lawTypeList`) and in a radar vehicle (`classList` / `models`), F5 turns it on or off.

- **Panel:** your speed, front and rear target and fast speeds, the plate each camera reads in red (hit), amber (note) or clear, and the locks. It flashes on a plate hit.
- **Remote (F7):** antennas on/off and Same / Opposite / Both, speed and plate locks, the speed alert, beep, auto-lock (if the admin allows it), the plate reader, mute, volume, size, drag to move, and this shift's hits with **Open in MDT**.
- **Plate hits** (BOLO, stolen, owner warrant) are logged on the server and move a BOLO's last-seen point. Kept `keepHitsDays` (30; 0 = forever), cleaned once an hour.

**Admins:** `/whip` → Settings → MDT → **Radar**. **Players:** pause menu → Settings → Server Settings → **Radar**.

| | |
|---|---|
| ![In-car radar](docs/images/18_radar_incar_panel.png) | ![Radar remote](docs/images/18_radar_remote.png) |
| ![Radar settings](docs/images/18_whip_settings_radar.png) | ![Pause menu radar](docs/images/18_pause_settings_radar.png) |

## Controller

es_mdt works with a gamepad (2.0.13), through WHIP's own pad system. On a controller the buttons below work in the world, and every es_mdt screen can be used without a mouse.

**In the world** (each is LB + a button, so nothing clashes with driving or combat; players can move them on the pause menu's **Controller** screen):

| Button | Does |
|---|---|
| LB + Y | open / close the MDT |
| LB + D-pad ▲, **hold 1.5 s** | **panic** (a red ring fills as you hold; works while downed or dead) |
| LB + D-pad ◀ | respond to the call card shown, with GPS. **Hold**: hide the card |
| LB + D-pad ▶ | request backup |
| LB + D-pad ▼ | the call board. **Hold** in a radar vehicle: the radar remote |
| (none by default) | radar on / off: a player can give it a button on the Controller screen |

**In the screens** (MDT, Live map, call board, radar remote, permit application, Departments, DOJ):

| Button | Does |
|---|---|
| D-pad / left stick | move the focus ring |
| A / ✕ | select. On a text box: WHIP's on-screen keyboard |
| B / ○ | back: closes a dialog, then the screen |
| LB / RB (L1 / R1) | previous / next tab or page |
| LT / RT (L2 / R2), right stick | scroll |
| X / □ | search (opens the keyboard) |
| Y / △ | jump to the tabs |
| Start / Options | close |

**Live map:** left stick pans, right stick or LT / RT zoom around the centre cross, A opens the pin nearest the cross, X fits everything, Y goes to your unit.

**Hints:** a bar at the bottom of each screen shows Xbox or PlayStation buttons on a pad and keys on a keyboard, switching by itself.

**Admins:** `/whip` → Settings → MDT → **Controller**: controller support, the MDT buttons, screen navigation, the on-screen keyboard, hints, and the hold times (`Config.Controller` in `mdt/config.lua`: `panicHoldMs` 1500, `dismissHoldMs` 600, `remoteHoldMs` 600). **Players:** pause menu → Settings → Server Settings → **Controller**: MDT controller support, stick speed, and button hints (Xbox, PlayStation or off).

The pad is read only while an es_mdt screen is open. With no screen open, es_mdt adds no per-frame work, only WHIP's own button checks.

| | |
|---|---|
| ![Focus ring](docs/images/19_mdt_focus_ring.png) | ![Dialog](docs/images/19_mdt_dialog_focus.png) |
| ![Call board](docs/images/19_call_board_controller.png) | ![Radar remote](docs/images/19_radar_remote_controller.png) |
| ![Departments](docs/images/19_departments_controller.png) | ![DOJ](docs/images/19_doj_controller.png) |
| ![PlayStation hints](docs/images/19_hints_playstation.png) | ![Pause menu](docs/images/19_pause_controller.png) |

## Live map

New in 2.0.9. **MDT → Live map** shows every on-duty unit and active call on an interactive map of the state.

![Live map](docs/images/15_live_map.png)

- **Units:** callsign, name, department colour, status, in a car or on foot, an arrow for the heading, and speed in a vehicle. Your own pin is marked. Click one for its status, heading, distance from you and its call, with **Waypoint**, **Follow** (keeps it centred) and **Profile**.
- **Calls:** priority colours (critical calls pulse), the search circle of witness calls, a dashed line from each responding unit, and BOLO plates where they were last read. Click one to **Respond + GPS**, set the **GPS** or **Open call**.
- **On the GTA minimap and pause map** (2.0.14): a witness call's search circle stays, in its priority colour, until the call closes. The call's dot goes after `Config.Dispatch.blip.seconds` (120 s); `blip.areas = false` takes the circle with it.
- **Moving around:** drag to pan; scroll, double-click or `+` / `−` to zoom; `0` fits everyone; arrow keys pan. Buttons on the right: zoom, centre on me, fit everyone, and a dark or a colour map (remembered on that PC).
- **Finding things:** search a callsign, name or call; filter departments with the chips at the top (with counts); the **Layers** menu turns units, calls, search areas, responding lines, BOLO plates and labels on or off. The side list has the units by department and the calls, critical first.
- **Live:** it refreshes every `Config.MapRefreshMs` (2.5 s), only while the tab is open and the MDT is on screen, and pins glide between updates.
- **Who sees what:** calls follow the Dispatch tab's routing (an officer sees the calls their MDT lists). Units follow `Config.LiveMap.units`: `'group'` (default: police, sheriff and state police see each other; EMS sees EMS), `'own'` (their department only) or `'all'`. Admins see everything. `enabled = false` hides the tab from officers (admins keep it).

```lua
Config.LiveMap = { enabled = true, units = 'group', calls = true, bolos = true, showSpeed = true, image = 'img/map.webp' }
```

### The map picture

`html/mdt/img/map.webp` (4096 px) and `map_2048.webp` (the same map at 2048 px, shown until you zoom in; 2.0.10) are GTA V's own map. They belong to Rockstar Games and are **not** covered by this resource's MIT license. They are here the same way WHIP's own map is: for use on FiveM servers under Rockstar's and FiveM's terms (see [`html/mdt/img/NOTICE.md`](%5Bes%5D/es_mdt/html/mdt/img/NOTICE.md)). If you would rather not ship them:

- set `Config.LiveMap.image` (or the setting in `/whip`) to your own 4096 × 4096 picture of the same layout, as a file in the resource (`'img/my_map.webp'`) or an `https://` link; or
- delete both files. The map shows a plain grid, and every unit and call is still in the right place. (A custom picture is always loaded at full size.)

## Backup and panic follow the officer

New in 2.0.9 (`Config.Dispatch.follow`, or `/whip` → Settings → MDT → *Backup and panic follow the officer*).

![Backup follows](docs/images/15_backup_follow_map.png)

- A `/backup` call (and a panic call, `panic = true`) **moves with the officer who asked**. The server reads their position every `seconds` (4) and, once they have moved `minMove` (10 m), moves the call's blip and its spot. Respond, GPS and the arrival check use where the officer is now, and the Live map shows it with a "live" tag.
- **Units on the call** get their GPS moved at most every `gpsSeconds` (10), and only when the officer is `gpsMove` (35 m) from where the route points. A unit that set its own waypoint somewhere else keeps it.
- **The officer who asked sees who is coming** (`responders = true`): a marker for each responding unit ("Responding · 1-A-12", `blip`), live, and a notice when a unit starts responding and when it arrives. A marker goes away when that unit is within `arriveDistance` (40 m) or On scene, or the call ends.
- It stops when the call is closed or auto-closed, or the officer goes off duty or leaves. The call stays where they were last, with a note. After a server restart, open calls stay where they were.

## Dispatch: routing, panic, backup and alerts

All of this is in `Config.Dispatch` and `Config.Panic` (`es_mdt/mdt/config.lua`).

- **Routing:** each call kind goes to groups of department types (`law` = police, sheriff, state; `ems` = ems). Only those groups' on-duty units get the card, sound, blip and the call in their Dispatch tab. A group with no department on your server is skipped, so a server with no EMS department sends 911 and medical calls to law. Set `shared = true` to let every group see every call in its Dispatch tab. DOJ gets no calls.
- **Calls from players:** `/911 <message>` and `/311 <message>` (and `/ems` when `medical = 'ems'`) add the street and position automatically, and each player can call once per `cooldownSec` (30 s). They show up in chat suggestions.
- **Units on a call:** the call card and the MDT list every unit on the call (callsign, name, status) and update live.
- **Panic:** the **END** key (rebind under GTA Settings → Key Bindings → FiveM; `Config.Panic.key`), `/panic`, or the MDT's red button. On-duty officers only, with a `cooldown` (15 s). It files a P1 **OFFICER DOWN** call at the officer's position for law and EMS. It works while the officer is downed, injured or dead: nothing checks health, ragdoll or death, and WHIP lets the call through (`whileDead`).
- **Request backup:** the button on your call in the MDT, or `/backup` (bindable). **On a call (2.0.15)** it joins that call: the call is marked "Backup requested" (who, when), goes up to P1 for a panic or P1 call (otherwise P2, never down), its units are alerted again (not you), the timeline says so, and a 🚨 marker follows you on their maps and the Live map while the call stays where it is. Units respond to the call itself. On **no call** it files its own backup call at your position, which follows you (2.0.9, see [above](#backup-and-panic-follow-the-officer)). The cooldown is 45 s. `Config.Dispatch.backup.merge = false` brings back the separate backup call.
- **Escalation:** a call nobody attached to goes up one priority every 5 minutes, up to P1. Panics are never escalated. The MDT updates quietly, with one soft re-alert to the units (`escalate.realert`).
- **Shots fired and vehicle theft:** automatic alerts from the game, each with its own `enabled`, `chance`, `cooldown` and `priority`. On-duty law, suppressed weapons and the Ammu-Nation ranges never trigger them, and repeat reports near an open call merge into it (×N reports and a note) rather than making a new call. Other scripts can file them directly with `exports.es_mdt:ShotsFired(coords)` and `exports.es_mdt:VehicleTheft(coords, plate, model)`.

## Dispatch: alerts, critical calls and the call board

New in 2.0.7. Everything is in `Config.Dispatch` (`es_mdt/mdt/config.lua`).

**Ready-made alerts for your scripts.** These are server exports, one line each. `data` is optional: `street`, `message`, `title`, `priority`, `critical`, `groups`, `witness`, `radius`, and suspect details (`plate`, `vehicle`, `color`, `weapon`, `suspect`, `direction`). Pass `player = source` and the server reads that player's position, car plate and colour, and the weapon in their hand.

```lua
exports.es_mdt:StoreRobbery(coords, { player = source })   -- titled e.g. '24/7 Supermarket, Innocence Blvd' (2.0.8: storeName / store id / nearest store)
exports.es_mdt:BankRobbery(coords, 'fleeca')            -- 'fleeca' | 'paleto' | 'pacific' (Paleto and Pacific are critical)
exports.es_mdt:JewelryRobbery(coords)
exports.es_mdt:HouseRobbery(coords, { suspect = 'Male, dark hoodie' })
exports.es_mdt:DrugSale(coords, { player = source })
exports.es_mdt:Explosion(coords)                        -- law and EMS
exports.es_mdt:Fight(coords)
exports.es_mdt:SuspiciousActivity(coords, { message = 'Someone trying car doors' })
exports.es_mdt:Carjacking(coords, { plate = '8ABC123', vehicle = 'Sultan', color = 'Blue', direction = 'North' })
exports.es_mdt:Alert('store', { coords = coords })       -- any preset by name, including your own
```

Each returns `callId, merged` (`merged` is true when the report went onto an open call) or `false, why`. Each preset in `Config.Dispatch.presets` sets the call's `kind`, `priority`, `title`, `icon`, `blip` and `groups`, and can be `critical`, a `witness` report (a search circle) or turned off (`enabled = false`). Add your own and call them with `Alert('<name>', data)`.

- **Critical, above P1:** the panic button and presets with `critical = true`. The card pulses with a CRITICAL badge, the blip flashes, and an alarm repeats every 4 s (up to 8 times) until the unit acknowledges it (Respond or Hide on the card, Ack on the board), a unit responds, or the call closes (`Config.Dispatch.critical`).
- **Alert sounds:** three tiers: routine, P1 and critical. Each player sets their own volume or mutes them in the **Aa** popover or with `/mdtvolume`, saved on their PC (`Config.Dispatch.sounds`).
- **Repeat reports:** a report of the same kind (and preset) within 150 m while the call is fresh goes onto the open call. The call shows **×3 reports**, gets a note, and its priority can only go up (`Config.Dispatch.merge`). Panic, backup and officer calls never merge. Plain `alert` calls without a preset (es_jail, `NotifyDispatch`) stay one call each unless the script passes `merge = true`.
- **"N responding"** on the card, in the MDT list and on the call's page.
- **Search circles:** witness reports show a circle, not a pin. The exact spot is inside it but never at its centre, and the circle shrinks with each repeat report (`Config.Dispatch.witness`). **The true position never leaves the server.** Players only get the circle. Arriving counts anywhere inside it.
- **Suspect details:** plate, vehicle, colour, direction, a description, and the weapon as a class with a threat grade (Melee 1, Handgun 2, SMG and Shotgun 3, Rifle 4, Machine gun, Sniper and Explosives 5). They're cleaned on the server, and the exact weapon is never sent.
- **Automatic alerts:** shots, vehicle theft, fights (melee with a witness), explosions (not steam, flames, flares or smoke), a civilian down for 20 s (sent to EMS, or law if there's no EMS), and speeding (off by default). Each has `enabled`, `chance`, `cooldown` and `priority`. On-duty law never sets them off. At most `perMinute` (6) **new** calls of one kind a minute; reports near an open call still merge.
- **The call board:** **O** (or `/callboard`, rebindable) with the MDT closed. It lists the active calls you can see, critical first, with their units, reports, search area and details. Buttons: **Respond** (attach and GPS), **Waypoint**, **GPS** and **Leave** for your call, and **Ack alarm**. It updates live and follows the display size. Press Esc or O to close it.
- **Links:** **＋ Link report / warrant / case** on a call's page, or `exports.es_mdt:LinkCall(callId, 'report' | 'warrant' | 'case', id)` (`nil` unlinks). Linked calls are kept forever (see [Call retention](#call-retention)).

**Opening a case's evidence locker from the MDT.** **Open locker** on a case closes the MDT and then opens the whip_evidence stash. WHIP won't open a stash over another screen. Stand at an evidence locker first; the MDT doesn't reopen by itself.

## Dispatch: closing calls, auto-close and announcements

**Closing a call.** The **Close call** button opens a picker: **Resolved**, **Handled on scene**, **Unfounded**, **No contact**, **Suspect gone** or **Other** (keys 1 to 6 pick one). A closing note is optional, except for **Other**, which needs one. The outcome, the note, who closed it and when are saved on the call. Each outcome has its own coloured badge in the Dispatch call list, on the call's page and in its timeline. Calls closed before 2.0.4, or closed by a script without an outcome, show **Closed**. Server owners can change the list, colours and icons in `Config.Dispatch.outcomes` (`note = 'required'` makes the note mandatory).

**Auto-close.** An active call is closed by itself once it is `Config.Dispatch.autoCloseMinutes` old (15 by default; 0 turns it off):

| The call | What happens |
|---|---|
| No unit on it | Closed at `autoCloseMinutes`. |
| A unit on it now | Left open: someone is working it. Set `autoCloseAttached = true` to close it too. Either way it is closed at `callTTLMin` (120 minutes), the hard cap. |
| A **panic** call with a unit on it | **Never** auto-closed. |

The outcome is **Auto-closed – no response** when no unit ever attached, or **Auto-closed (timeout)** when one did, even if they later left. Each has its own badge colour. Auto-close is **silent**: officers get no popup, sound, toast or notification. The call's blip and GPS route go, its call card leaves the queue, and the MDT's lists update quietly. Auto-closed calls are never deleted or hidden: they stay in the call history with their outcome and a note ("Closed automatically after 15 min").

**Blips and GPS.** When a call closes, by any path, its blip goes for everyone. Any player whose waypoint was set to that call (call card, **Set waypoint**, attaching, a partner, `/panicgps`) has it cleared, but only if the waypoint still points at the call. A waypoint they moved elsewhere stays. An officer who goes off duty, logs out or disconnects is taken off the calls they were on (with a note on each call), and their call blips, GPS route and call cards go.

**Announcements.** Posted from the Dashboard (**+ Post**, permission `announce`). Each one has a title, a message, an author and a time. Line breaks are kept, `**bold**` works, and lines starting with `- ` become a list. A live preview shows the result. The priority is **Normal**, **Important** (amber) or **Urgent** (red). An urgent announcement shows a red banner in the MDT and a red alert in game for everyone on duty in that department. An on-duty member who opens their MDT within `Config.Announcements.urgentFreshHours` (12) of an urgent announcement they have not seen also gets the banner, once.

## Configuration

Each part keeps its own config file:

| File | What is in it |
|---|---|
| `es_mdt/shared/suite.lua` | `EsSuite.DevTools`: staff test tools (`/dojtest`, `/ftotest`, MDT → Admin → Test data). **Off by default; keep it off on a live server.** |
| `es_mdt/departments/config.lua` | department types, the permission list, default ranks and their permissions, the first-start seed (`Config.Seed`), insignia, leave (LOA), FTO program, certifications, department health |
| `es_mdt/mdt/config.lua` | command and key, off-duty read only, fines, warrants and BOLOs, tablet props, firearm permits, weapons registry, unit statuses, report types and templates, penal code seed, dispatch (911/311 and call cards), display size (`Config.UI`), panic, mugshots, radar, cases, **jail bridge (`Config.Jail`)**, **whip_evidence bridge (`Config.WhipEvidence`)** |
| `es_mdt/doj/config.lua` | commands and key, who may view, warrants needing a judge, courthouse locations, case kinds and stages, hearings, filings, fees, bail switch (off), sentences, service, name changes, the bar, images |
| `es_jail/config.lua` | permissions, items, cuffs, breaking out, lockpicking, jail and prison, prison jobs, escape, test mode |

Every option is commented in its file. Most of `mdt/config.lua` can also be changed live in `/whip` → Settings → MDT (see [Changing settings live](#changing-settings-live)). The penal code, report templates, department ranks and permissions are seeded from config on first start. After that you manage them in game.

### Permissions

Permissions are WHIP job permissions on each department's ranks, and you switch them per rank in `/departments`. Examples: `mdt_view`, `medical_records`, `ems_reports`, `ems_deaths`, `ems_bills_waive` (EMS), `mdt_reports_write`, `warrants_request`, `warrants_issue`, `fines_issue`, `cases_create`, `cases_close`, `evidence_upload`, `bolo_manage`, `fto_train`, `personnel_manage`, `weapons_register`, `permits_manage`, `jail_cuff`, `jail_manage`, `doj_cases`, `doj_sign`, `doj_prosecute`, `doj_defend`, `doj_clerk`, `doj_bar` and `doj_seal`. The full list with descriptions is `Config.Permissions` in `departments/config.lua`.

## Jail integration for developers

The MDT (Process arrest → Send to jail) and the court (sentences) send prisoners through **one jail interface**, and any jail script can sit behind it.

`Config.Jail.provider` in `mdt/config.lua`:

| Value | Meaning |
|---|---|
| `'auto'` (default) | Uses the first jail found, in this order: a script that registered itself (the newest wins), then es_jail, then `Config.Jail.custom`, then none |
| `'es_jail'` | es_jail only |
| `'custom'` | `Config.Jail.custom` only |
| `'<resource>'` | the script that registered with that resource name |
| `'none'` | never jail; sentences are only recorded |

**With no jail script**, a sentence is still recorded in the MDT (table `es_mdt_jail_sentences`) and the event `es_mdt:jail:sent` fires. The Jail tab shows it, and the MDT counts the time itself: `Config.Jail.recordMinutesPerMonth` real minutes per month, 1 by default. An officer can release someone early from the Jail tab.

### Option 1: no code, use your script's exports

If your jail script has exports such as `JailPlayer(source, minutes, reason)`, describe them in `mdt/config.lua`:

```lua
Config.Jail = {
    provider = 'auto',
    custom = {
        resource = 'my_jail', label = 'My Jail',
        target = 'source',          -- what its exports take: 'source' (player must be online) or 'charId'
        timeUnit = 'minutes',       -- 'months' | 'minutes' | 'seconds'
        minutesPerMonth = 1,        -- one MDT month = this many minutes
        jail     = { export = 'JailPlayer',   args = { 'target', 'time', 'reason' } },
        release  = { export = 'UnjailPlayer', args = { 'target' } },      -- optional
        isJailed = { export = 'IsJailed',     args = { 'target' } },      -- optional
    },
}
```

The `args` names you can use are `target`, `charId`, `source`, `time` (in `timeUnit`), `months`, `minutes`, `seconds`, `reason`, `reportId`, `officerCharId` and `officerSource`.

### Option 2: register a provider from your jail script (server side)

```lua
-- in your jail resource, after es_mdt has started
exports.es_mdt:RegisterJailProvider({
    label = 'My Jail',
    -- required. info = { charId, source (nil if offline), months, reason, charges = { {code,title,count} }, reportId,
    --   courtCase, origin = 'mdt'|'court', byCharId, bySource }
    -- return true, or false + a reason the officer sees
    jail = function(info) return MyJail.put(info.source, info.months * 60, info.reason) end,
    release  = function(charId, info) return MyJail.free(charId) end,        -- optional: info = { byCharId, reason }
    isJailed = function(charId) return MyJail.isIn(charId), MyJail.secondsLeft(charId) end,   -- optional
    inmates  = function(recentDays) return MyJail.list() end,                 -- optional, rows for the Jail tab:
    -- { charId, status = 'serving'|'escaped'|'released', months, total, remaining (seconds), jailedAt, releasedAt, escapedAt, reason, online }
})
```

The provider is removed when your resource stops. `exports.es_mdt:UnregisterJailProvider()` removes it by hand, and `exports.es_mdt:GetJailProvider()` returns the name of the one in use.

### Tell the MDT what happened (server side)

```lua
-- someone was released (time served, a judge, an admin): closes the MDT record and serves "escape" warrants
exports.es_mdt:ReportJailRelease(charId, { reason = 'Time served', byCharId = nil })

-- someone escaped: the MDT record says so, an arrest warrant (+ BOLO) is issued and dispatch gets an alert
exports.es_mdt:ReportJailEscape(charId, {
    reason = 'Escaped from Bolingbroke', warrant = true, warrantDays = 7, bolo = true,
    alert = true, coords = GetEntityCoords(GetPlayerPed(src)), street = 'Bolingbroke Penitentiary', title = 'Prison break',
})
```

Prefer events? Use `TriggerEvent('es_mdt:jail:reportRelease', charId, info)` and `TriggerEvent('es_mdt:jail:reportEscape', charId, info)`. These are server events, which clients cannot send.

### Events es_mdt fires (server side)

| Event | Arguments |
|---|---|
| `es_mdt:jail:sent` | `info` (as above), `result = { ok, provider, why, recorded = true }`. Fires for every sentence, with or without a jail script |
| `es_mdt:jail:released` | `charId, { byCharId, reason, origin }` |
| `es_mdt:jail:escaped` | `charId, { reason, warrantId, origin }` |

### Calling the jail from other resources

`exports.es_mdt:JailSend(info)`, `exports.es_mdt:JailRelease(charId, byCharId, reason)` and `exports.es_mdt:JailIsJailed(charId)` all go through whichever provider is active.

## The EMS side of the MDT (2.5.0)

Members of an **EMS** department (type `ems` in `/departments`) open the same `/mdt`, with EMS tabs instead of police records. It is built for RP, so it stays short: no vitals, medical codes, prescriptions or insurance.

- **EMS dashboard:** the active medical calls (P1 first) with the units on each, **Attach & en route** in one press (sets the GPS), your status, the crew on duty, today's numbers, and the calls you still owe a report for.
- **Patients:** search by name, phone or ID. Shows the blood type (from the ID until a medic sets it), a short note (allergies, conditions), recent treatments and open bills from whip_jobs, incident reports, custody (in jail or cuffed, from es_jail) and a death record. EMS does not see police records.
- **Incident reports:** after a call, what happened, what was done (treated, revived, transported, refused care, pronounced dead) and a line of notes. The report is on the call (a call note too) and on the patient. The writer can edit it for 24 hours; supervisors always can.
- **Medical bills:** what patients owe (open, paid, waived). Supervisors waive a bill with a reason, and it is logged.
- **Death records:** a supervisor marks a character deceased (cause, place, time) and can link a whip_evidence post-mortem report that was uploaded to an MDT case. Police see it on the person. Undoing one keeps it, struck out.
- **Roster & stats:** calls, treatments, revives and reports per member over 7, 30 or 90 days, a top-3 podium and duty hours (for leaders). Ranks, hiring and duty use the same Department tab as the police.
- **What the police see:** a "Deceased" banner and a "Treated by EMS" tag on a person, and what EMS did on a call ("EMS: Revived, Transported"). Nothing more.
- Permissions (EMS ranks, `/departments`): `medical_records` and `ems_reports` from level 10; `ems_deaths` and `ems_bills_waive` from level 80 (supervisors). Existing EMS ranks get them once by level.
- Settings: `Config.EMS` in `mdt/config.lua` (blood types, the "what was done" list, how long reports are asked for and editable, how many days police see "treated").
- Fully controller friendly: LB/RB switch the tabs, A presses, B closes.

## Tickets, invoices, contests and impound (2.1.0)

- **Roadside tickets** (`/ticket`): citations, parking tickets and warnings for people and vehicles close by. Charges come from the penal code. The recipient signs or refuses; refusing, no answer or logging off files it unsigned. Both sides get a paper ticket item.
- **Every fine is an invoice**, due in 3 days. Pay in `/court` → Payments; the bank is charged on the due day. The unpaid-fine warrant counts from the due date.
- **Contests:** an unsigned ticket can be contested in `/court`, which pauses the deadline. The officer files a statement and a judge dismisses, reduces or upholds it. With no ruling in 5 days it is dismissed. Turn contests off (`Tickets.contests`) and tickets must simply be paid.
- **Impound** from the MDT vehicle page (a garaged car is taken now; a car that is out is marked until it is stored) or `/mdtimpound` on the street. Holds can be N days or until released; ending one early is a logged override. Storage is charged daily with a cap. There is a lot view, owners pay in `/court`, impounding closes the BOLO, and abandoned cars nobody owns are towed for an officer payout.
- **Texts** to owners and recipients via whip_phone, queued while they are offline, with a copy in `/court` → Notices.

Everything is in `/whip` → Settings → MDT (Tickets, Fines and invoices, Impound, Owner texts), and the permissions are in `/departments` → Ranks. Full guide, exports and events: [docs/tickets_impound.md](docs/tickets_impound.md).

## whip_evidence integration

With [whip_evidence](docs/whip_evidence_integration.md) installed, the MDT finds it by itself (`Config.WhipEvidence.enabled = 'auto'`). Set `Config.ApiResources = { 'es_mdt' }` in whip_evidence's config, and list your department job names in its `PoliceJobs` (do it again after each whip_evidence update: its config file comes with `ApiResources = {}`). Checked with whip_evidence **4.2.3** (es_mdt 2.0.17: post-mortem reports and copy buttons). The bridge provides:

- MDT case numbers as whip_evidence case IDs
- uploading bagged evidence and photos to a case
- lab results, the chain of custody and the timeline in the case
- closing and reopening the locker together with the MDT case
- whip_evidence 4.2's shoe prints, tyre tracks, glove fibres, cleaned spots and restored serials, with readable labels, and an amber chip on partly readable results (2.0.16)

**Who may do what (whip_evidence 4.1+):** whip_evidence checks a lowest rank level per action in `/whip` → Settings → Forensics → "Lowest rank level", the same for every police job, on duty only. Its defaults: scan and photos 1; collect, GSR, upload to a case, open lockers 20; dust, release scenes, run the lab, take items out of a locker 40; close cases 60. With the default ranks (Officer 30, Sergeant 60) Officers cannot run the lab, dust or take items out until you lower those levels. The old "Upload evidence to cases" and "Close evidence lockers" switches in `/departments` do nothing with 4.1+, so 2.0.16 hides them there.

The details are in [docs/whip_evidence_integration.md](docs/whip_evidence_integration.md).

## For developers: exports

`exports.es_mdt:*` (also available under `exports.es_departments:*` and `exports.es_doj:*`):

- **Departments:** `HasPerm(source, perm)`, `GetDepartments()`, `GetDepartment(id)`, `GetPlayerDepartments(source)`, `GetActiveDepartment(source)`, `GetRoster(id)`, `GetOnDuty(id)`, `IsStaff(source)`, `GetLogo(id)`, `GetDutySeconds(charId)`, `HasCert(charId, cert)`, …
- **MDT:** `AddCall(call)`, `NotifyDispatch(title, message, coords, priority, sourceLabel)`, `CloseCall(id, outcome)`, `TestCall(kind, priority)` (see [Dispatch API](#dispatch-api)), `ShotsFired(coords, opts)`, `VehicleTheft(coords, plate, model, opts)` (2.0.6), `Alert(name, data)`, `StoreRobbery`, `BankRobbery`, `JewelryRobbery`, `HouseRobbery`, `DrugSale`, `Explosion`, `Fight`, `SuspiciousActivity`, `Carjacking`, `LinkCall(callId, kind, id)` (2.0.7, see [Dispatch: alerts, critical calls and the call board](#dispatch-alerts-critical-calls-and-the-call-board)), `GetActiveWarrants(charId)`, `IssueWarrant(...)`, `EscapeWarrant(...)`, `ServeEscapeWarrants(charId)`, `HasActiveBolo(...)`, `CheckPlate(plate)`, `GetUnpaidFines(charId)`, `GetWeaponBySerial(serial)`, `GetPermitStatus(charId)`, `OpenTablet(source)`, `GetTickets(charId)`, `GetTicket(id)`, `GetInvoices(charId)`, `IsImpounded(vehicleId)`, `GetImpounds(charId)` (2.1.0, events in [docs/tickets_impound.md](docs/tickets_impound.md#8-hooks-for-other-scripts-server-side)), …
- **DOJ:** `GetCourtMarks(charId)`, `GetRecordSummary(charId)`, `WarrantsNeedJudge()`, …

## Dispatch API

Any resource can put a call on the MDT dispatch board. Units on duty get the popup, a blip, and the call in the Dispatch tab, the same as a 911 call. The exports are **server side**. Each returns the call id, or `false, why`.

### `exports.es_mdt:AddCall(call)`

```lua
local callId = exports.es_mdt:AddCall({
    kind     = 'alert',                 -- '911' | '311' | 'alert' | 'officer' | 'panic' | 'medical' | 'shots' | 'theft' | 'backup'  (anything else: 'alert')
                                        -- 2.0.7: also 'robbery' | 'drugs' | 'explosion' | 'fight' | 'suspicious' | 'down' | 'speeding'
    -- preset = 'store',                 -- 2.0.7, optional: fill what is not given from Config.Dispatch.presets
    -- groups = 'ems',                   -- 2.0.6, optional: who gets it ('law', 'ems' or { 'law', 'ems' }); default: Config.Dispatch.routing.kinds
    priority = 1,                       -- 1 (urgent) .. 3. Default: panic 1, 311 3, others 2
    title    = 'Alarm: Fleeca Hawick',  -- up to 120 characters. Default: the kind's name ('911 call', 'Alert', ...)
    message  = 'Silent alarm tripped',  -- up to 500
    street   = 'Hawick Ave',            -- up to 120
    coords   = GetEntityCoords(ped),    -- see the formats below; optional
    callerName = 'Bank system', callerPhone = '555-0100', callerCharId = nil,   -- optional
    blip = true, sprite = 280, color = 1, blipTime = 120,                        -- optional blip settings
    sourceLabel = 'bank_alarm',         -- optional, admins only (see below). Default: your resource's name
})
```

| Field | Also accepted as | Notes |
|---|---|---|
| `kind` | | `911`, `311`, `alert`, `officer`, `panic`, and since 2.0.6 `medical`, `shots`, `theft`, `backup`. Anything else becomes `alert`. The kind decides who gets the call (`Config.Dispatch.routing.kinds`). |
| `groups` | | 2.0.6: overrides the routing for this call: `'law'`, `'ems'` or `{ 'law', 'ems' }`. |
| `priority` | `prio` | 1 to 3, clamped. |
| `title` | | Up to 120 characters. With no title, the kind's name is used (`911 call`, `311 call`, `Panic`, `Officer call`, `Alert`). `name` is never used as the title. |
| `message` | `desc`, `description` | Up to 500 characters. |
| `street` | `location` | Up to 120 characters. |
| `coords` | `pos`, `position` | Optional. With no valid coords there is no blip. |
| `callerName` | `name`, `caller` | Up to 80 characters. |
| `callerPhone` | `phone` | Up to 20 characters. |
| `callerCharId` | `charId` | A number. |
| `blip` | | `false`: no map blip. |
| `sprite`, `color` | | Blip sprite and color. Default: `Config.Dispatch.blip`. |
| `blipTime` | | Seconds the blip stays, 5 to 1800. Default: `Config.Dispatch.blip.seconds`. |
| `deptId` | | Optional department id stored with the call. |
| `sourceLabel` | `source`, `from`, `resource` | A text label, up to 40 characters. With none, the name of the resource that called the export. **Admins only**: see below. |
| `preset` | | 2.0.7: a `Config.Dispatch.presets` name. Its kind, priority, title, message, icon, blip, groups, critical and witness fill what the call doesn't say. |
| `critical` | | 2.0.7: `true` for the critical tier (pulsing card, flashing blip, a repeating alarm). |
| `witness`, `radius` | | 2.0.7: `true` for a search circle of `radius` metres (20 to 1000; default `Config.Dispatch.witness.radius`) instead of the exact spot. |
| `details` | | 2.0.7: `{ plate, vehicle, color, weapon, grade, desc, dir }` shown on the card. Short strings; use the preset exports to have them cleaned for you. |
| `merge` | | 2.0.7: `false` means always a new call. `true` lets a plain `alert` merge into an open one with the same title. |

Strings are trimmed, control characters are removed (new lines and tabs are kept), and the lengths above are applied.

**Where a call came from is for admins only.** Officers never see which script filed a call: the source label is not sent to players, and it is not on the call card or in the MDT. Server admins see it in the server console (`[es_mdt] call #42 (alert, P1) filed by bank_alarm`) and in the `sourceLabel` column of `es_mdt_calls`. The 911/311 phone calls, the panic button and es_mdt's own calls have no label.

**Coordinate formats.** All of these work: `vector3(x, y, z)`, `vector4(x, y, z, h)` (the heading is ignored), `{ x = 1.0, y = 2.0, z = 3.0 }` and `{ 1.0, 2.0, 3.0 }`. `z` is optional. Coordinates that are not numbers, or that are outside the map (more than 20000 from the centre), are dropped.

### `exports.es_mdt:NotifyDispatch(title, message, coords, priority, sourceLabel, extra)`

The short form: an `alert` call.

```lua
exports.es_mdt:NotifyDispatch('Store robbery', '24/7 on Innocence Blvd', vector3(25.7, -1347.3, 29.5), 1)
```

`coords` and `priority` are optional (priority defaults to 2). The fifth argument is optional:

- a **string** is the admin-only source label, and an optional sixth argument is a table of any other `AddCall` fields: `NotifyDispatch('Store robbery', '…', coords, 1, 'my_robbery', { street = 'Innocence Blvd' })`
- a **table** is those other fields, as in 2.0.1: `NotifyDispatch('Store robbery', '…', coords, 1, { street = 'Innocence Blvd', kind = '911' })`

### `exports.es_mdt:CloseCall(callId, outcome, note)`

Closes an active call, the same as the MDT's Close call button: the units on it are freed, its map blip goes for everyone at once, every on-duty unit's call card shows it closed, and GPS routes to it are cleared. `outcome` is free text (up to 40 characters) and defaults to `Closed`. Returns `true`, or `false, why`.

**Blips.** A call's map blip is removed as soon as the call closes, however it closes: the Close call button, `CloseCall`, or auto-close (see [Dispatch: closing calls, auto-close and announcements](#dispatch-closing-calls-auto-close-and-announcements)). Closing a panic call also removes the PANIC blip. Otherwise the blip goes after its `blipTime`. Call and panic blips are only on the maps of officers on duty: going off duty takes them off, and coming on duty while a blip is still up adds it.

### Test calls: `/mdttestcall`

| Command | What |
|---|---|
| `/mdttestcall [kind] [priority]` | A test call, titled `TEST · <kind>`, near you (from the server console: at Legion Square). `kind` is `911`, `311`, `alert` (default), `officer` or `panic` (a panic test only files the call; it does not press anyone's panic button). |
| `/mdttestcall clear` | Closes and deletes every test call. |

For the server console and staff only (WHIP permission `es_mdt.departments.manage`, the `es_departments.admin` ace, or WHIP developer mode). Test calls are labeled `test` (admins only). `exports.es_mdt:TestCall(kind, priority)` does the same from a server script.

### From client scripts: the `es_mdt:server:externalCall` net event

A client script cannot call server exports. It can send:

```lua
TriggerServerEvent('es_mdt:server:externalCall', { title = 'Shots fired', message = 'Near the docks', coords = GetEntityCoords(PlayerPedId()), priority = 1 })
```

This event is guarded, because any player can send any net event:

- **Who:** a player on duty in a department, or a player whose WHIP job is listed in `Config.Dispatch.external.jobs`. Anyone else is refused.
- **Rate limit:** one call per player every `cooldownSec` (10 s), and at most `perMinute` (5) a minute.
- **No panics:** `kind = 'panic'` is refused (the panic button files panics). The allowed kinds are in `Config.Dispatch.external.kinds`.
- **The caller is the sender:** the caller's name, phone and character come from the server, never from the data. `sprite`, `color`, `blipTime` and `deptId` are ignored.
- **Clamped:** only `kind`, `priority`, `title`, `message`, `street`, `coords` and `blip` are read, with the limits above. With no valid coords, the sender's own position is used.
- **Source:** labeled `external:client` on the server (admins only, see above). Any label in the data is ignored.
- A refused call shows the player the reason. Every accepted call is printed in the server console.

```lua
-- mdt/config.lua
Config.Dispatch.external = {
    enabled     = true,     -- false: the event is not registered at all (server exports only)
    onDuty      = true,     -- players on duty in any department may send it
    jobs        = {},       -- and players in these WHIP jobs, e.g. { 'tow', 'security' }
    kinds       = { '911', '311', 'alert', 'officer' },
    cooldownSec = 10,
    perMinute   = 5,
}
```

For calls from members of the public (a store clerk, a bank alarm), use the server exports from your server script. The event is not for that.

## Database

es_mdt creates and updates its own tables, so there is no SQL to import. Each table's `CREATE TABLE` statement in the code is the source of truth for its columns and keys. On every start:

1. WHIP's `EnsureTable` creates any missing table and runs the table's migrations that haven't run yet. The migrations are recorded in `schema_migrations`.
2. **The schema self-check** (2.0.5, `server/schema.lua`) compares each table with its `CREATE TABLE` in `information_schema` and adds any missing column or key. It never drops, renames or changes anything that is already there, and it doesn't add foreign keys. So a database that missed a migration, for any reason, is completed at the next start.

Each column or key it adds is logged as `[es_mdt] schema: added missing column ...`. If it cannot add one, the server console shows a red **SCHEMA ERROR** block with the SQL to run by hand, and WHIP lists it as a start problem. About 20 seconds after start, `[es_mdt] schema check: 75 tables OK` confirms everything is in place.

### Call retention

Calls used to be kept forever. Since 2.0.7, **closed** calls older than `Config.Dispatch.keepClosedDays` (90) are deleted with their notes and unit rows. This runs about 90 seconds after start and then once a day, in batches of 500 with a short pause between them, so a big table doesn't stall the server. The console shows what was removed: `[es_mdt] call retention (90 days): removed 120 closed call(s), 410 note(s), 95 unit row(s)`. It never deletes an open call, or a call linked to a report, warrant or case (link one on the call's page or with `exports.es_mdt:LinkCall`). Set `keepClosedDays = 0` to keep every call.

## How it is built

2.0.0 merged three resources into one, and each part still runs on its own. Each part's Lua runs with its own globals (`shared/env.lua`): its own `Config` and helpers, while the exports are shared. Each part's page runs in its own frame of one NUI page (`html/index.html` and `html/shell.js`), so the MDT, Departments and the DOJ tablet can be open on top of each other.

## Performance

2.0.10 went through the cost of each part. With nobody on duty the MDT does next to nothing. On duty, the work that repeats is kept small:

- **Radar:** runs only in a radar vehicle, on duty; its scan rates are settings (`scanMs`, `parkedScanMs`) and it does nothing at all when turned off.
- **Client:** shots fired looks 4 times a second while a gun is in hand (no per-frame check) and skips on-duty law. The radar looks half as often while parked and sends to the screen only on a change. The Live map loads the 2048 px picture first, the 4096 px one only when zoomed in, lets both go when you leave the tab, and only the selected unit's or call's lines are animated.
- **Server:** who you are (department, permissions) is kept 30 s, the on-duty list 1 s, both dropped at once on any job, roster or department change. Followed backup and panic calls keep their units in memory. "Look again" updates go only to on-duty units and players with the MDT open. Small lookups are cleaned every 5 minutes.

## What is tested

- **Tested for 2.5.0:** an EMS sim against the real code (permissions by level, the 17 EMS calls, blood types, reports on calls, waiving bills, death records with a post-mortem, what police see, stats), whip_jobs 0.6.0 export sims, every earlier es_mdt and whip_jobs sim, luac on every file, and browser tests of every EMS tab and the police view (no JS errors). Started on a live server: the new tables and permissions.
- **Tested for 2.2.0 to 2.4.2:** Lua sims against the real code (whip_jobs / es_jobs server, client, EMS and DOJ sims; the post-mortem impact sim wev241; all earlier es_mdt sims), luac on every file, and browser tests: bail removed from the DOJ tablet and portal (10 checks), the Court phone app in a copy of the whip_phone page (29 checks), the DOJ station spots and New department locations (21 checks), and the post-mortem impact rows (7 checks), with no page errors. On the live server: the courthouse station, the clerk window, the public defender office, the judge's chambers and no bail anywhere were checked in game.

- **Running on a live server (as separate resources, before the merge):** MDT dispatch, reports, warrants, fines, cases, FTO, personnel, Departments, the whip_evidence bridge, es_jail.
- **Tested for 2.1.0:** in Lua tests against the real es_mdt code (tk210, 86 checks): invoices (due in 3 days, nothing charged at issue, the old behaviour when turned off); texts (the government number made once, phone_messages rows, a push only when online, the queue while offline, the portal copy, skipped without whip_phone); roadside tickets (penal-code prices, no felonies, the sign prompt only for the recipient, signed / refused / logged off / timed out, warnings with no fine, distance checks); contests (unsigned only, needs a reason, off when turned off, the deadline paused, reduce, uphold, lapse); impound (storage capped, holds, an override needs the permission and a reason, the owner pays only after a hold, a double payment is refused and refunded, the history kept). A database test on a scratch MariaDB database (fresh, an old 1.x shape and a 2.0.4 install) covers the new tables and the `002_invoices` migration. In browser tests (Chrome, 64 checks): the roadside ticket, parking and sign prompt, the paper, the street impound with its live photo preview, the tow, MDT Tickets, Impound lot, hold override, release and vehicle page, controller rings, the DOJ Ticket contests and ruling, and /court My tickets, contest, Impounded vehicles and Payments, with no page errors. All 24 earlier test files still pass. 2.1.1/2.1.2 add grant211 (10 checks: permission grants send only the added keys, so a rank holding an old unknown key still gets them, and a refused grant is retried).
- **Tested for 2.0.17:** against the real whip_evidence 4.2.3 code (read, not changed). In Lua tests against the real es_mdt code: the post-mortem report is cleaned up for the page (unknown wound types, body parts and ranges are dropped, counts are fixed and text is capped; positions and entity ids are not sent); the time of death is the exam time minus the age; a broken or missing report does not error; only report items carry one; photo body rows are passed and junk rows dropped. In browser tests (Chrome): the post-mortem card (figure with 3 marks that do not overlap and 1 fatal ring, the cause, the tiles, every row), samples grouped under the body with the jump to their item, and the real clipboard. Copying works by click (execCommand), through the Clipboard API fallback when execCommand is refused, by Enter on the keyboard and by A on a controller, with the "Copied" toast. Unreadable plates are not copy buttons. No page errors. All 22 earlier test files still pass.
- **Tested for 2.0.16:** against the real whip_evidence 4.2.2 code (read, not changed): every export, event, field and whip_core call it uses is present on the live server. In Lua tests against the real es_mdt code: "Open locker" shows whip_evidence's own reason and a clear "cancelled" text when its 1 s bar is cancelled, still refused off duty; `/departments` hides the two whip_evidence switches with 4.1+ (shown with 4.0 or without whip_evidence), and saving a rank keeps what they held (a forged tick is ignored). In browser tests: the case's Evidence locker card with shoe print, tyre track, fibre, cleaned spot and serial report entries (labels, icons, the amber "Partly readable" chip, no raw field names) and the rank editor note, with no page errors. All 21 earlier test files still pass.
- **Tested for 2.0.15:** in Lua tests against the real server code: backup on a call merges into it (no new call), the priority rules (never lowered, the urgent priority on a panic), who and when, the timeline note, the re-alert to the routed units only (never the asker, never EMS) with nothing private in it, the call keeping its spot and circle, the following marker (moves with the officer, not the call), responder markers as before, the cooldown, asking again, closing, the asker going off duty, backup with no call, and `merge = false`. The client re-alert (card, banner, P1 sound) is also covered. In browser tests: the Dispatch badge and banner (local time), the call card, the call board and the Live map marker with its line, with no page errors.
- **Tested for 2.0.14:** in Lua tests against the real server code: a witness call gets its own circle blip, sent to the same units as the call, at the circle centre (never the true spot) and in the priority colour. It stays after the call's dot times out, comes back on a duty change, shrinks and moves on a repeat report, goes on close and stays gone, and is not added for calls without a circle or with `blip.areas = false`. The other 19 test files still pass.
- **Tested for 2.0.13:** in Lua tests against WHIP's real pad code (`Whip.padScreen` and the pad actions): every action registered on its slot, the panic hold (released early, nothing; held, the panic; set to work over any screen, the death screen too), respond / hide and board / remote holds, the admin switches applied live (actions removed and added back), each player's on/off, stick speed and hints, the Controller settings in whip_core's real Settings and pause-menu code, the on-screen keyboard and its fallback, and no per-frame loops with no screen open. In browser tests with simulated pad input: the focus ring, D-pad and stick moves, A, B, LB / RB, LT / RT, X and Y, the keyboard on text boxes, dialogs, the Live map (pan, zoom, nearest pin), the call card and hold ring, the call board, the radar remote, the permit application, Departments and DOJ, with Xbox, PlayStation and keyboard hints, and no page errors. **Not yet tried on a real controller.**
- **Tested for 2.0.12:** in Lua tests: no Radar tab callbacks on the client or the server and nothing sent for one; the 19 radar settings in whip_core's real Settings code (the tab ones gone) and the 9 pause-menu rows through whip_core's real `player_prefs.lua`; the panel in a police car and hidden on foot, in another class and when turned off; auto-on (kept when the remote saves); scan rates and classes live; plate hits, sounds, mute, lock sound, the server's hit sound; the speed alert, auto-lock, units, position and size; the server's plate check, departments and on/off, and the hourly plate-hit clean-up. In browser tests: no Radar tab in the MDT, the in-car panel (readout, a hit, the corners, 140 %, km/h), the remote (Mute, auto-lock hidden when not allowed, dragging), and the Radar settings in whip_core's own panel and pause menu. All earlier tests still pass. On a live server: es_mdt 2.0.12 starts with the schema check and no errors. Not tested in game: the radar with real traffic and a real player.
- **Tested for 2.0.11:** in Lua tests against the real code: the 22 radar settings in whip_core's real Settings code (on the page, defaults from `config.lua`, applied live into the `Config.Radar` the radar holds, ranges, Reset, an older `config.lua` upgraded) and the 9 pause-menu rows through whip_core's real `player_prefs.lua` (get, set, Reset). On the client: the Radar tab's state on foot, in a police car and with the radar turned off, locks from the tab (refused on foot), auto-on when getting in (not after turning it off in the car, not when switched off), the scan rates and vehicle classes read live, plate reads sent to the tab only while it is open (newest first, a plate read again moves up, the server's limit, Clear), mute, the lock sound and the server's hit sound, the speed alert following the server until a player picks their own, auto-lock refused when not allowed, units, position and size. On the server: plate hits (newest first, Mine, a plate filter, the 200 cap, who read it without their character id), who may see them (law and staff; EMS, departments added live, the tab turned off), the plate check, the radar turned off, and the hourly clean-up (not in the first 5 minutes, once an hour, 0 = kept, days read live). In browser tests: the Radar tab (status, power, the readout painted in place, modes, the speed alert saved once, toggles, locks, Look up, BOLO filled in, Owner, the Live map pin, Plate hits with Everyone / Mine, Check a plate, Clear, on foot, turned off, hidden for non-law and when an admin hides it), and the Radar group and the pause-menu Radar tab rendered in whip_core's own UI. All the 2.0.3 to 2.0.10 tests still pass. On a live server: es_mdt 2.0.11 starts with the schema check and no errors. Not tested in game: the tab with a real radar and traffic, locks from the MDT, the pause-menu rows and auto-on with a real player, the sounds and mute, the plate-hit clean-up on the real database, and the settings changed live on a running server.
- **Tested for 2.0.10:** in Lua tests against the real server code: all 44 new settings (on the page, defaults from each part's `config.lua`, applied live into the tables the code holds, ranges, Reset), the context kept 30 s and dropped on clock on / off, rank, hire, fire, job and department changes and on leaving, the on-duty list kept 1 s with fresh tables each time and live statuses, dropped on every change, "look again" updates going only to on-duty units and players with the MDT open (and to everyone if the list cannot be read), the follow units kept in memory. On the client: shots fired by ammo while aiming or on the trigger (not on a reload or an inventory change), the cooldown, on-duty law skipped and asked again on a clock change, never asked with no gun in hand, the radar sending only on a change and slowing down when parked. In browser tests: the Live map opening on the 2048 px picture, swapping to 4096 px when zoomed in, letting it go on leaving, only the selected lines moving, and the new settings groups in whip_core's own panel. All the 2.0.3 to 2.0.9 tests still pass. Not tested in game: shots detection with real guns, the radar with real traffic, the Live map's memory use in the game's browser, and the settings changed live on a running server.
- **Tested for 2.0.9:** in Lua tests against the real server code: backup and panic calls follow the officer (the call, its blip and its spot move once they have moved far enough, units on it are told, nothing moves when they stand still), it stops on close, auto-close, off duty, leaving and with the setting off, the responders' markers (shown only to the officer who asked, not for their partner, removed on arrival, On scene, or the call ending), and the client side (the card and the arrival spot move, the GPS moves only when the route still points at the call and not too often, never after arriving). The Live map data: who sees which units (group, own, all, admins), calls by the Dispatch routing, speed, the picture setting (only a file in the resource or an https link). In browser tests: the Live map tab (pins, car and foot icons, heading, search circles, responding lines, details, Respond + GPS, GPS, waypoint, search, department filters, layers, the colour map, live updates only while open, the picture falling back to a grid), and the settings pages in whip_core's own panel. All the 2.0.3 to 2.0.8 tests still pass. On a live server: es_mdt 2.0.9 starts with the schema check and no errors. Not tested in game: the blips moving and the responders' markers with real players, the GPS moving, the notices, and how the map positions line up in game.
- **Tested for 2.0.8:** in Lua tests against whip_core's real settings code (`shared/settings.lua`, the pause-menu `player_prefs.lua`): the MDT page registers with nothing left off (about 100 settings), the defaults, the hidden sub-options, the restart rows, the type checks, values applied live into the tables the MDT holds, `/whip` Reset, and the three pause-menu rows (get, set, reset, admin default and range changes, a player's own choice kept). Also: the store names (built-in places, `storeName`, ids, the nearest place, extra places, the fallback, only the same store merging, the title on exports and the board), speeding (units, both limits, highway roads only by the road name, the peak cap, switched off live), and the client switches read live (backup, board, detectors, popup, alarm). The panel and the pause-menu page were rendered in whip_core's own UI with the real data, and all the 2.0.3 to 2.0.7 tests still pass. On a live server: es_mdt 2.0.8 starts with the schema check and no errors. Not tested in game: changing a setting in `/whip` and the pause menu with a real player, and the built-in store positions (from community maps, not checked in game).
- **Tested for 2.0.7:** in Lua tests: every preset and export (the bank choice and fallback, `Alert` both ways, an unknown preset, no coordinates), suspect details (plate and text cleaning, weapon names and signed hashes as classes and grades, the details the server reads from a player), the search circle (the centre 0.2 to 0.85 of the radius from the spot in 200 random draws, only the centre and radius sent, no height), merging (×N, the shrinking circle still holding the true spot, another kind or after the window is a new call, notes at most every 30 s, priority only up, panics and es_jail alerts never merge, `merge = false`), critical calls (panic, presets, `panic = false`), the automatic alerts (fights, a civilian down only when really down and only for civilians, sent to EMS; speeding off by default and checked against the server's own speed reading; explosions ignoring harmless, invisible and on-duty-law ones, with a cooldown; the per-minute cap while merges still work), the call board (only for units on duty, no phone, audience or source label), links (attached or high rank only, missing records refused, unlink), and retention (batches with pauses, the counts, open and linked calls kept with their notes, a call linked during a sweep kept whole, `0` keeps everything). On the client: the three sound tiers, the alarm repeating and stopping (Hide, a unit responding, the board's Ack, closing, `maxRepeats`), mute and volume (saved, `/mdtvolume`, reset), the merged card, the board (the key O, its screen and focus, Respond with GPS, live reloads at most once a second, not over another screen or the MDT), the panic message, and the locker (MDT closed first, the stash asked for only once no screen is open, one request for two presses, never reopening the MDT, a refusal shown). Against real MariaDB: the 2.0.7 columns and the closed-call index (used by the cleanup query), the circle stored and listed by the real SQL, merging and the real time window, links, and the cleanup's `DELETE … JOIN` guards. The schema test passed again with 2.0.7 (fresh, 1.x and broken 2.0.4 databases). In browser tests: the critical, merged and preset cards, the MDT list and call page (×3, N responding, details, links), the search circles on the live map, the call board, the link dialog, **Open locker** sending one request, the rate-limit retry, and the alert-sound controls. All the 2.0.3 to 2.0.6 tests still pass. On a live server: migration `005_dispatch207` and the schema check, the presets through the real exports (a critical Pacific Standard call, cleaned details), a witness call's circle with the true spot kept on the server, three fight reports merged into one call (×3, a smaller circle that still holds the spot), es_jail-style alerts kept separate, a critical panic test call, `LinkCall`, the per-minute cap, and retention on old test calls (removed, a linked one kept, real calls untouched). Not tested in game with a real player: the sounds and alarm themselves, the O key, the fight, explosion, down and speeding detection, and the locker stash opening after the MDT closes.
- **Tested for 2.0.6:** in Lua tests: routing for every call kind (including a server with no EMS department, and `shared`), the medical line, chat suggestions, the unit list, the panic key mapping (END, the old mapping kept) and pressing it while dead, at 0 health and ragdolled, the panic callback being `whileDead` with no death checks, the panic cooldown and on-duty rule, OFFICER DOWN going to law and EMS, backup (linking, priority, cooldown, while downed), escalation (never a panic, never past P1, never a call with a unit), and shots and theft alerts (toggles, chance, cooldowns, law and suppressed exemptions, area merging, the exports). In browser tests: the call card's unit list, escalated, officer-down and backup cards, and the MDT call page with units and Request backup. On a live server: the calls filed and routed, and the database migration. Not tested in game with a real player: the END key itself, pressing it while actually downed, and the game-side shots and theft detection.
- **Tested for 2.0.5:** the schema self-check against a real MariaDB database, using whip_core's own `EnsureTable` and migration code: a fresh database, an old 1.x database with rows in it, and a broken 2.0.4 fresh install all end up with every column and key of all 68 tables. The 2.0.4 errors were reproduced and then repaired. Extra columns, keys and rows were left untouched. A fix that fails gives a loud error and a start problem, and is repaired at the next start. A second start does nothing.
- **Tested for 2.0.4:** in Lua tests: the outcome list and its checks (Other needs a note), `everAttached`, auto-close for every case in the table above (with no notification of any kind sent), the off-duty clean-up and duty blips, announcement priority, and the client's GPS clean-up (a waypoint moved elsewhere stays, auto-close says nothing). In browser tests: the outcome picker, the badges, the announcement form and preview, and the urgent banner on open. On a live server: the database migrations, a test call closed with an outcome, and test calls auto-closed with a short timeout (outcomes, saved rows, no notification sent).
- **Tested for 2.0.3:** source labels (defaults, the `NotifyDispatch` forms, never sent to players), `/mdttestcall` and `TestCall`, and closing calls with their blips, in Lua tests; and on a live server, a test call from the console stored with its label, then closed and removed.
- **Tested for 2.0.2:** the display size in browser tests at 70%, 100% and 150% on 1920×1080 and 2560×1440: the pages fit and stay centred, and clicks, the search list, dialogs and the photo viewer line up; the slider, quick sizes, Reset, Esc and a saved size on reload; and `/mdtscale`.
- **Tested for 2.0.1:** the dispatch exports on a live server (calls filed through `NotifyDispatch` and the old `AddCall` form).
- **Tested for 2.0.0:** Lua syntax; every file loads in order with each part's globals kept apart and the old export names working; and browser tests of the one-page UI (every part opens, messages and clicks reach the right part, no JS errors).
- **Not yet tested on a live server:** the DOJ 1.1.0 features (attorneys and the bar, fees, appeals), firearm permits, the jail bridge with a third-party jail script, and a full fresh install in game (the empty-database schema is covered by the 2.0.5 database test).

Please report problems with your server log (F8 and the server console).

## License

MIT. See [LICENSE](LICENSE).
