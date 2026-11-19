# Tickets, invoices, contests and impound (es_mdt 2.1.0)

All of this is part of es_mdt. It runs on whip_core alone. whip_phone is optional (for texts).

## 1. Roadside tickets

- **Open it:** `/ticket` (rename it in `Tickets.command`), or a controller button. Add **"Write a ticket"** to a slot in the pause menu → es_mdt controller buttons. The MDT doesn't need to be open. A rank needs the **"Tickets: write roadside citations…"** permission (`tickets_issue`).
- **Three kinds:**
  - **Citation:** to a person.
  - **Parking ticket:** to the owner of a parked vehicle.
  - **Written warning:** no fine, no signature.
- **Who or what:** only people and vehicles within `Tickets.range` (12 m) are listed, nearest first. The server checks the distance again when the ticket is issued. Nobody's cars (locals, rentals) can't get a parking ticket. Tow them instead (see section 5).
- **Charges** come from the penal code. Only the categories in `Tickets.categories` are offered (infractions and misdemeanors by default), with up to `maxCharges` (6) of them, each ×1–5. **The price is set on the server from the penal code, never by the page.**
- **Signing (citations):**
  - The person gets a **sign prompt**: the paper ticket, **Sign** and **Refuse**, and a countdown ring (`signSeconds`, 45).
  - **Refusing, no answer in time, or logging off mid-ticket** files it **unsigned**. A server restart mid-signature does the same.
  - The officer sees the answer live.
  - Parking tickets have nobody to sign (unsigned). Warnings need no signature.
- **Paper:**
  - Both sides get an **`es_mdt_citation`** item (`Tickets.paper`). Use it to see the printable ticket.
  - The MDT shows the same paper view on the ticket.
  - The recipient also gets a text and a court portal notice.
- **MDT → Tickets** has five tabs: Mine, Department, Contested, Unpaid and Unsigned, plus search.
  - Open a ticket for its paper, the contest, the **officer's statement** box and **Void** (with a reason).
  - A person's page and a vehicle's page list their tickets.

## 2. Every fine is an invoice

`Invoices.enabled` is on by default. **Every** fine becomes an invoice: roadside tickets, MDT report fines, custom fines and impound fees charged by the lot.

- Nothing is taken when the fine is written. The fine is **due in `Invoices.dueDays` (3) days**.
- **Pay** in the court portal: `/court` → Payments (bank or cash), or someone else can pay it there for you.
- **Reminder:** a text `reminderHours` (24) before the due date.
- **On the due day:** with `autoCollect` on, it is taken from the bank account. If the bank can't cover it, the person gets a text saying it is overdue.
- **Overdue:** the existing **`UnpaidFineWarrantDays`** setting (MDT → Fines) now counts from the **due date** and skips contested fines.
- **Turning `Invoices.enabled` off** brings back the old behaviour: charged at once, unpaid if the bank can't cover it.
- **Bank:** this server has no separate bank or billing script, because banking is part of whip_core. es_mdt uses whip_core's `ChargePlayer` (portal), `BankSystemWithdraw` (due day) and the department account deposit. Payment records are written with `CommitWithAction`, in the same transaction as the charge.

## 3. Contests (needs the DOJ part, `Tickets.contests`)

- **Who can contest:** only an **unsigned** ticket, by its recipient, in **/court → My tickets → Contest**, before the due date and with a reason. A signed ticket can only be paid.
- **The deadline pauses.** No reminder, no collection and no warrant while it is contested. The time that was left is kept.
- **The issuing officer** is texted and asked for a **statement** (MDT → Tickets; supervisors can file it too).
- **A judge** (`doj_sign`) rules in **DOJ tablet → Ticket contests**. Both sides are shown, sorted by the soonest to lapse. Rulings:
  - **Dismiss:** the invoice is voided.
  - **Reduce:** a new, lower amount.
  - **Uphold:** the full amount.

  When reduced or upheld, the paused time runs again, at least one day.
- **No ruling within `contestLapseDays` (5):** dismissed **in the citizen's favour**. Online judges get a warning `contestWarnDays` (1) before, and the contest turns red on the tablet.
- **`Tickets.contests` off (no DOJ):** tickets must simply be paid. The sign prompt says so, and the Contest button is gone.
- Both sides are texted about every ruling.

## 4. Impound and holds

Ranks need these permissions (`/departments` → Ranks):

| Permission | Lets them |
|---|---|
| `impound_vehicle` | impound and tow |
| `impound_hold` | put a hold on a vehicle |
| `impound_lot` | release, charge or waive |
| `impound_override` | release early (an override, with a reason, logged) |

New and existing ranks get them once, by rank level: 30 for `tickets_issue` and `impound_vehicle`, 60 for `impound_hold` and `impound_lot`, 80 for `impound_override`.

- **From the MDT:** a vehicle's page → **Impound**.
  - **In a garage, or not in the world:** impounded **now**, moved to the lot.
  - **Out in the city:** **marked**. The form says so. It goes to the lot the next time it is stored (or at the next server start), and it can't be taken out again until it is released.
- **On the street:** `/mdtimpound` (`Impound.command`). Stand by the car. It uses **the same form** and takes the car straight away; occupied cars are refused.
- **The form shows:**
  - warnings for a **stolen** flag, an **active BOLO** and an impound already in place
  - the owner (and whether they are online), where the car is, and its **prior impound** count
  - reason chips, the lot, the fee (up to `maxFee`), the hold, notes and an optional **photo link with a live preview**
  - the **bill**: the fee, storage per day, the storage cap, what is owed today and the most it can reach

  Impounding **closes an active BOLO** on the plate (`resolveBolos`).
- **Holds:** none, **N days** (up to `maxHoldDays`, 30), or **until released**. Making a hold shorter, lifting it or releasing during it needs `impound_override` and a reason, and is logged as an **override**.
- **Fees:** the impound fee plus `dailyFee` (100) per day stored, with storage capped at `storageCap` (1,500).
  - **The owner** pays in **/court → Impounded vehicles** (bank or cash) once any hold is over, and the car is released at the lot (`releaseTo = 'lot'`, or `'home'` for their garage).
  - **The lot (`impound_lot`)** can release a car and **invoice the owner** (a normal invoice) or **waive** the fees (with a reason).
- **Lot view:** MDT → Impound lot. Shows what is on the lot and what is marked, what each owes now, holds, photos, and the outstanding total. The **Released** tab keeps the history: who released it, what was paid, overrides.
- **Lots** are whip_core garages, listed in `/whip` → Settings → MDT → Impound → Impound lots (map points). They are made at start when missing. Add parking bays in `/whip` → Garages. The default is "LS Impound Lot" (409.3, -1623.1).

## 5. Abandoned cars nobody owns

`/mdtimpound` on a car **no player owns** offers **Tow it away** for an officer payout (`unowned.payout`, $150 to the bank). It is refused for:
- an occupied car
- a rental or job car
- a car a player owns
- a car whose **last driver is still within `ownerRange` (60 m)**

There is a cooldown per officer (`cooldownSec`, 120) and a cap of `perShift` (10) paid tows per shift. Every tow is logged (`es_mdt_tows`).

## 6. Texts to owners (whip_phone)

whip_phone has no "send a text" export, so es_mdt does exactly what whip_phone's own story characters do. It never changes whip_phone:
1. It makes one government number (`555xxxxxxx`, `phone_numbers.loreKey = 'es_mdt_gov'`) and calls `ReloadCache`.
2. It writes the text into `phone_messages`, where it **waits while the person is offline**.
3. It adds the contact name (`Texts.sender`, "San Andreas Gov").
4. For an online person, it calls `Push(src, 'messages', 'incoming', …)`.

Texts are sent for: an impound or mark, a hold changed, a release, fees paid, a ticket, a payment reminder, an overdue fine, a contest filed, and a ruling. **A copy always goes to /court → Notices.** With no whip_phone, or no phone number, the person gets the notice and a toast. `Texts.enabled = false` turns texts off.

## 7. Settings (/whip → Settings → MDT)

New groups:
- **Tickets:** on/off, range, categories, charges, time to sign, paper, contests, lapse days, warn days, command
- **Fines and invoices:** on/off, due days, auto-collect, reminder hours
- **Impound:** on/off, lots, fee, maximum fee, daily fee, storage cap, longest hold, release to lot or home, close BOLOs, abandoned tows (payout, cooldown, per shift, owner range), command
- **Owner texts:** on/off, sender name

The commands need a restart. The impound reasons (`Impound.reasons`) and allowed photo sites (`Impound.photoHosts`, empty = any https site) are in `mdt/config.lua`.

## 8. Hooks for other scripts (server side)

**Exports:**
```lua
exports.es_mdt:GetTickets(charId)      -- that person's tickets (newest first)
exports.es_mdt:GetTicket(ticketId)     -- one ticket, with its charges, invoice and contest
exports.es_mdt:GetInvoices(charId)     -- their unpaid fines / invoices, with dueAt and contested
exports.es_mdt:IsImpounded(vehicleId)  -- false, or true + { id, status, lot, held, holdUntil, owed, reason }
exports.es_mdt:GetImpounds(charId)     -- their impounds (held, marked, released in the last 14 days)
exports.es_mdt:MarkFinePaid(fineId, by, how) -- an outside bank/billing script settles an invoice
```

**Events** (`AddEventHandler`, server only, never sent to players):

| Event | Data |
|---|---|
| `es_mdt:ticket:issued` | `{ ticketId, number, kind, charId, vehicleId, plate, total, sign, fineId, officerCharId, deptId }` |
| `es_mdt:fine:paid` | `{ fineId, charId, amount, ticketId, impoundId, how }` |
| `es_mdt:contest:ruled` | `{ contestId, ticketId, number, ruling, amount, charId, judgeCharId }` (ruling: dismiss, reduce, uphold, lapsed) |
| `es_mdt:impound:created` | `{ impoundId, vehicleId, plate, status ('held' or 'pending'), lot, ownerCharId, reason, officerCharId, deptId, street }` |
| `es_mdt:impound:stored` | `{ impoundId, vehicleId, plate, lot, ownerCharId }` (it reached the lot) |
| `es_mdt:impound:released` | `{ impoundId, vehicleId, plate, status ('released' or 'cancelled'), by, override, paid }` |

**Garage scripts:**
- es_mdt holds an impounded car with whip_core's **`SetVehicleCustody`** and parks it in the lot garage. Any garage script built on whip_core (whip_autos, whip_dealership, …) already refuses to hand it out, and nothing needs changing.
- A garage script with its own impound can listen to `es_mdt:impound:created` and `es_mdt:impound:released`.
- A marked car moves on whip_core's `whip_core:vehicle:despawned` event, which fires whenever it is stored.
- None of the installed garage scripts (whip_autos, whip_autos_shop, whip_dealership) has an impound of its own, so there is nothing to clash with.

## 9. Tables

New tables: `es_mdt_tickets`, `es_mdt_ticket_contests`, `es_mdt_impounds`, `es_mdt_tows`. `es_mdt_fines` gains `kind`, `ticketId`, `impoundId`, `dueAt`, `contested`, `pausedSecs`, `remindedAt` and `collectTriedAt` (migration `002_invoices`). All of this is made at start; no SQL import is needed.
