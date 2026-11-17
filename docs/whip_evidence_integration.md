> Written for whip_evidence's author while building the bridge (es_mdt 1.11). Since es_mdt 2.0.0 es_departments is part of es_mdt; `exports.es_departments:*` still works.

# es_mdt ⇄ whip_evidence integration

es_mdt **1.11.0** includes an optional bridge to `whip_evidence`. It needs es_departments **1.9.0**, which carries your permission names.
The split is simple: **whip_evidence keeps the things** (bags, photos, guns, lab and lockers), and **the MDT keeps the cases**.
The only link between them is the case ID.

## 1. The case ID is the MDT case number

- MDT case numbers look like `C-2026-0009`: a prefix, the year, then a running number. They fit your rules: `[A-Za-z0-9_-]`, at most 32 characters, and a leading `#` is ignored.
- Officers type the case number exactly as the MDT shows it (e.g. `C-2026-0009`) at the lab device or locker. Plain numbers like `9` are **not** accepted.
- The MDT hooks `SetCaseCheck(fn(caseId, source))`:
  - when es_mdt starts (it waits for whip_evidence to be `started`);
  - and again 1 s after every `onResourceStart` of `whip_evidence`.
- The check returns `true` for any MDT case that is open or closed but **not archived**, and matches case-sensitively. It answers from an in-memory cache of case numbers that refreshes every 30 s; a cache miss is looked up live when your calling thread can wait. **Please call the check from a thread** (a callback or a `CreateThread`), not from a raw tick.

## 2. Your side: config and start order

```lua
-- whip_evidence config
Config.ApiResources = { 'es_mdt' }
```

server.cfg: **`ensure es_mdt` comes before `ensure whip_evidence`** (since es_mdt 2.0.0 es_mdt declares the department jobs, which whip_evidence's `PoliceJobs` refer to). The MDT hooks whip_evidence whenever it starts or restarts.

```
ensure es_mdt
ensure whip_evidence_assets
ensure whip_evidence
```

On the MDT side nothing needs to change. `Config.WhipEvidence.enabled = 'auto'` (in `es_mdt/mdt/config.lua`) turns the bridge on as soon as a resource named `whip_evidence` exists on the server.

| `enabled` | Behaviour |
|---|---|
| `'auto'` (default) | On when `GetResourceState('whip_evidence') ~= 'missing'` |
| `true` | Always try. Calls still need the resource to be `started` |
| `false` | Completely off. The MDT never calls whip_evidence |

Other keys: `photoStoreBytes` (default 4 MB, the largest photo copy the MDT keeps), `cachePhotosOnUpload` (default `true`), `maxUpload` (default 30 items per upload) and `resource` (default `'whip_evidence'`).

## 3. Permissions: your names are supported natively (no remap needed)

es_departments **1.9.0** has `evidence_upload` and `evidence_case_close` as real department permissions. Keep checking those exact names; nothing needs changing on your side.

- **Where they live:** like every es_departments perm, they are WHIP job permissions. Each department (LSPD, BCSO, SASP, and so on) declares them on its job through `EnsureJob`. They show as switches on each rank in `/departments`:
  - "Upload evidence to cases (whip_evidence)"
  - "Close evidence lockers (whip_evidence)"
- **Existing ranks were migrated once:**
  - Every rank that had `evidence_collect` got `evidence_upload` (by default level 10 and up).
  - Every rank that had `cases_close` got `evidence_case_close` (by default level 60 and up, Sergeant+).
  - New departments and ranks get them by the same defaults. Server owners can toggle them per rank afterwards.
- **How to check them.** Any of these works:
  1. **whip_core, recommended if you already do this:** `exports.whip_core:HasJobPermission(source, job, 'evidence_upload', { onDuty = true })`.
     - `job` is the officer's department job (their clocked-on job, e.g. from `GetPlayerJob(source)`). A hard-coded `'police'` job key will **not** match, because each department is its own job.
     - Remember that level-100 roles pass any permission name.
  2. **es_departments, if you don't want to work out the job:** `exports.es_departments:HasPerm(source, 'evidence_upload')` returns `true, dept` or `false, why`.
     - It checks every department the player belongs to, and requires them to be on duty unless you pass `{ onDuty = false }` as the third argument.
  3. **es_departments, for a specific department:** `exports.es_departments:Can(source, deptRef, 'evidence_case_close')`.

**MDT gates for the same actions:**

| Action | MDT gate |
|---|---|
| "+ Add evidence" | Shows for officers who may file into the (open) case. Your `evidence_upload` check still decides each upload, and a refusal shows as that item's `why` |
| Close / Archive / Reopen | Needs `cases_close`. The MDT passes the officer's `source` to `CloseCase` / `ReopenCase`, so your `evidence_case_close` check applies |

The MDT never bypasses your checks. It passes the officer's `source` to `Upload`, `CloseCase`, `ReopenCase` and `OpenCaseLocker`.

## 4. What the MDT calls, and when

All calls are made on the server, wrapped in `pcall`, and only when the bridge is on and `whip_evidence` is `started`.

| Export | When |
|---|---|
| `GetUploadable(source)` | "+ Add evidence" opens, and again just before an upload, to drop refs the officer no longer carries |
| `Upload(source, refs, caseId)` | The officer picks items and presses Upload (at most 30 refs). The MDT saves each `ok` entry and shows each `why` |
| `GetCase(caseId)` | Every case-page load (for `taken` and `closed`), and after every `caseChanged` (to re-sync the saved entries) |
| `GetPhotoImage(photoId)` | In the background right after an upload, and on first view if not cached. Copies up to `photoStoreBytes` are kept in `es_mdt_wev_photos` |
| `OpenCaseLocker(source, caseId)` | "Open locker" button. A `false, why` is shown to the officer ("go to an evidence locker first") |
| `CloseCase(caseId, source)` | The MDT closes or archives an open case, only if the case has whip_evidence entries or `GetCase` knows it |
| `ReopenCase(caseId, source)` | The MDT reopens a closed or archived case (same condition) |
| `SetCaseCheck(fn)` | See section 1 |

- **Close / reopen:** the MDT change always stands. If your side answers `false, why`, the officer gets a warning toast ("Case closed, but: Evidence locker (whip_evidence): …") and the case timeline logs it.
- **Closed ⇄ archived:** moving between these makes no call, because the locker is already closed.

**Event:** the MDT listens to `whip_evidence:caseChanged(caseId, why)` and only accepts it when `GetInvokingResource()` is `whip_evidence`.

1. Within 0.5 s it calls `GetCase` and updates its copies.
2. Entries no longer in `items` or `taken` are kept but marked "no longer in the locker". After `deleted` (when `GetCase` returns nil), all of them are marked.
3. It pushes a refresh to everyone viewing cases or reports.
4. `taken`, `returned` and `deleted` are also written to the case timeline.

## 5. The MDT's tables

The MDT keeps its own copies, because your photos expire and items can be deleted.

| Table | Contents |
|---|---|
| `es_mdt_wev_entries` | `(caseId, ref)`: your entry snapshot as JSON, plus `gone`, `uploadedBy` and timestamps. Cascades on case delete |
| `es_mdt_wev_photos` | `photoId` → data URL (MEDIUMTEXT, up to `photoStoreBytes`) |
| `es_mdt_wev_report` | Which entries are attached to which report (chips on the report page) |

These replace your suggested `mdt_case_evidence` table. They are created empty on start, even when the bridge is off.

## 6. Security on the MDT side

- The page only sends the MDT's numeric case id and the refs it picked. The server:
  - resolves the case number itself;
  - checks the officer may file into that case (open, not read-only/off-duty, right rank);
  - accepts only refs that are well-formed (`kind:id`, ≤ 80 characters);
  - checks those refs are in this officer's `GetUploadable` list right now (at most 30 per upload).
- Photos are only served for entries saved on that case.
- Report chips need `mdt_reports_write` plus access to the report, and the item must belong to the report's own case.
- Every upload and attach is rate-limited and written to the MDT log.

## 7. Coexisting with es_evidence

es_evidence keeps working exactly as before: its Evidence tab, the "Evidence" and "Evidence locker" cards on a case, and chips on reports.

whip_evidence gets its own **"Evidence locker · WHIP_EVIDENCE"** card on the case page and on reports. With the bridge off or the resource missing, those cards are not rendered at all.

## 8. Test plan once whip_evidence is installed

1. **Start:** `ensure whip_evidence` before `ensure es_mdt`. The server console shows `[es_mdt] whip_evidence found: case check hooked`. Restart whip_evidence alone and the same line appears again about 1 s later.
2. **Lab device:**
   - A real case number (`C-2026-00xx`) is accepted.
   - A made-up number, a lowercase version and an archived case's number are refused.
3. **Add evidence** on an open case (MDT → Cases → case → Evidence locker card → "+ Add evidence"):
   - Analysed items are selectable.
   - Unanalysed items show "Lab first" (greyed).
   - An item from another case shows "Belongs to case X" (disabled).
   - Upload a mix and confirm each failure shows its `why`, while successes appear as cards with results and custody.
4. **Live refresh:** with the case open on a second officer's MDT, take an item out of the locker in game. Both MDTs show "Out of locker: taken by X" within a couple of seconds, and the timeline logs it. Return it and the pill goes away.
5. **Photos:** upload a photo. Its thumbnail loads and opens in the viewer. After `Config.Photo.KeepDays` (or after deleting it on your side), the MDT still shows its copy (photos up to 4 MB).
6. **Open locker:** pressing it away from a locker shows the friendly error; at a locker, the locker opens.
7. **Close / reopen:**
   - Close the case in the MDT and confirm the locker reports it as closed (`GetCase().closed`).
   - Reopen it, and confirm it is open again.
   - Turn off "Close evidence lockers (whip_evidence)" on a test rank in `/departments`: closing then shows the MDT warning toast, but the MDT status still changes.
8. **Reports:** on a report filed to that case, attach and remove whip_evidence chips. On a report with no case, a hint asks you to file it to a case first.
9. **Off switch:** set `Config.WhipEvidence.enabled = false`, then run `refresh` and `ensure es_mdt`. The cards disappear and es_evidence still works.

A mock stand-in for testing is in `test_resources/whip_evidence_mock/` (rename the folder to `whip_evidence`). Its `wevmock_*` console commands simulate taken, returned, deleted, locker and perms. It is **test servers only** and must never sit next to the real whip_evidence.

## 9. Verified against the real whip_evidence (LeSiiN, v4.0.0, commit 25ea96b) — 2026-11-17

- API matches the bridge: GetUploadable / Upload / GetCase / CloseCase / ReopenCase / OpenCaseLocker / GetPhotoImage / SetCaseCheck, event `whip_evidence:caseChanged`.
- Fixed in es_mdt 1.11.1: photo ids are **strings** (his `loadPhoto` refuses numbers); unrevealed lab results `'???'` are hidden.
- es_mdt 1.11.1 also hides every es_evidence part (Evidence nav, camera rolls, es_evidence case cards) when es_evidence is not started.
- whip_evidence config used on this server (config only, no code changes):
  - `ApiResources = { 'es_mdt' }`
  - `PoliceJobs = { 'police', 'bcso', 'sasp', 'sapr' }` (default lists `sahp`, which would be created as a new empty job).
- Permissions caveat: es_departments declares the police jobs, so whip_evidence's EnsureJob is refused and it turns its permissions off: every on-duty officer may use every evidence action. es_departments 1.9.0 already holds `evidence_upload` / `evidence_case_close` for when he supports foreign-declared jobs.
- Start order matters: `ensure es_departments` → `ensure whip_evidence_assets` → `ensure whip_evidence` → `ensure es_mdt`. If whip_evidence ever starts while es_departments is stopped, whip_core lets it take over the police job declarations (and replace their permission lists).
- es_evidence is disabled (both would drop casings/blood for the same shots).
- Timestamps: whip_evidence writes custody steps ("MM/DD HH:MM what · who") and item `time` with `os.date`, i.e. in the server's clock with no zone and no year — **UTC on this VPS**. es_mdt 1.11.3 reads them back on the server (same clock) and sends epoch times, so the MDT shows them in the officer's own time (e.g. "Nov 17, 12:43 PM" ET). Suggestion for the dev: store `os.time()` numbers (or ISO-8601 with `Z`) so other resources need not guess the zone/year.
- Case timeline (es_mdt 1.11.3): whip_evidence events have their own titles — Evidence filed (from the MDT), Lab result (uploaded from the lab), Taken from locker, Returned to locker, Evidence deleted — with "item — officer" underneath. whip_evidence fires no event for "sent to lab", so that step shows only in each item's chain of custody.
