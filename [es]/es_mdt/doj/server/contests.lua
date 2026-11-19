local _ENV = ESAPP('doj'); -- es_mdt 2.1.0: ticket contests before the DOJ, and the citizen's tickets and impounded vehicles in /court.
-- The rules live with the MDT (mdt/server/tickets.lua, impound.lua): this file is the court's side of them.
--   Tablet: Ticket contests (open, ruled). A judge (doj_sign) rules: dismiss, reduce (a new amount) or uphold.
--   Portal: My tickets (contest an unsigned one: the payment pauses), Impounded vehicles (pay and release once any hold is over).
-- Online judges are warned (Config.Tickets.contestWarnDays in the MDT's settings) before a contest lapses in the citizen's favour.
local WC, str, id = DOJ.WC, DOJ.str, DOJ.id
local function MDTP() return (ESPART('mdt') or {}).MDT end

-- the MDT calls these (a contest filed / ruled, one about to lapse)
CreateThread(function()
    local M = MDTP()
    if not M then return end
    M.dojRefresh = function() DOJ.refresh('contests') end
    M.dojWarn = function(text)
        local d = DOJ.dept()
        for src in pairs(WC:GetPlayers({ light = true }) or {}) do
            src = tonumber(src)
            local judge = d and WC:HasJobPermission(src, d.jobId, 'doj_sign', { onDuty = false }) == true
            if judge or DOJ.ED:IsStaff(src) == true then WC:NotifyPlayer(src, '⚖ ' .. text, 'warning', 12000) end
        end
        DOJ.refresh('contests')
    end
end)

function DOJ.registerContests()
    local cb, pcb = DOJ.cb, DOJ.pcb

    -- ---------------------------------------------------------------- the tablet
    cb('contests', { role = { 'judge', 'clerk', 'cases' }, rate = 400, burst = 6 }, function(c, d)
        local M = MDTP()
        if not M or not M.contestList then return false, 'The MDT is not running' end
        local rows = M.contestList(d.status == 'ruled' and 'ruled' or 'open')
        return { rows = rows, canRule = c.r.judge == true and not c.readOnly, enabled = ((ESPART('mdt') or {}).Config or {}).Tickets == nil or ((ESPART('mdt') or {}).Config.Tickets.contests ~= false) }
    end)

    cb('contestRule', { role = 'judge', write = true, rate = 2000, burst = 2, why = 'Only a judge rules on a contest' }, function(c, d)
        local M = MDTP()
        if not M or not M.ruleContest then return false, 'The MDT is not running' end
        local ruling = ({ dismiss = 1, reduce = 1, uphold = 1 })[d.ruling] and d.ruling or nil
        if not ruling then return false, 'Dismiss, reduce or uphold' end
        local ok, why = M.ruleContest({ charId = c.charId, name = c.label or c.name }, id(d.id), ruling, d.amount, str(d.note, 500))
        if not ok then return false, why end
        DOJ.log(nil, c, 'contest_' .. ruling, ('Ticket contest #%d: %s'):format(id(d.id) or 0, ruling))
        return true
    end)

    -- ---------------------------------------------------------------- the portal
    pcb('tickets', { rate = 400 }, function(p)
        local M = MDTP()
        if not M or not M.ticketRow then return { rows = {}, contests = false } end
        local ids = MySQL.query.await('SELECT `id` FROM `es_mdt_tickets` WHERE `charId` = ? ORDER BY `id` DESC LIMIT 30', { p.charId }) or {}
        local rows = {}
        for _, r in ipairs(ids) do
            local t = M.ticketRow(r.id)
            if t then t.officerCharId = nil rows[#rows + 1] = t end
        end
        local T = ((ESPART('mdt') or {}).Config or {}).Tickets or {}
        return { rows = rows, contests = T.contests ~= false, lapseDays = T.contestLapseDays or 5 }
    end)

    pcb('contest', { rate = 3000, burst = 2 }, function(p, d)
        local M = MDTP()
        if not M or not M.contestTicket then return false, 'The MDT is not running' end
        return M.contestTicket(p, id(d.id), d.reason)
    end)

    pcb('impounds', { rate = 400 }, function(p)
        local M = MDTP()
        if not M or not M.impoundsOf then return { rows = {} } end
        return { rows = M.impoundsOf(p.charId) }
    end)

    pcb('impoundPay', { rate = 3000, burst = 2 }, function(p, d)
        local M = MDTP()
        if not M or not M.impoundPay then return false, 'The MDT is not running' end
        return M.impoundPay(p, id(d.id), d.method)
    end)
end
