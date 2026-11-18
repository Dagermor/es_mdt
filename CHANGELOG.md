# Changelog

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
