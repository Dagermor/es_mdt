-- es_mdt 2.0.0: settings for the whole resource (each part still has its own config.lua).
EsSuite = {
    -- Staff testing tools: /dojtest, /ftotest and MDT → Admin · Test data. Off on a live server; turn on to test alone.
    DevTools = false,
}

-- The testing commands only exist when DevTools is on
if Whip and Whip.command then
    local DEV = { dojtest = true, ftotest = true }
    local command = Whip.command
    Whip.command = function(name, opts, fn)
        if DEV[name] and not EsSuite.DevTools then return end
        return command(name, opts, fn)
    end
end

-- 2.4.2: the job pack is whip_jobs (named es_jobs before its 0.5.0); either name works. started = true: only a
-- running one; otherwise any installed one (stopped or starting too). nil when neither is on this server.
EsSuite.JobsNames = { 'whip_jobs', 'es_jobs' }
function EsSuite.jobsRes(started)
    for _, n in ipairs(EsSuite.JobsNames) do
        local s = GetResourceState(n)
        if started then if s == 'started' then return n end
        elseif s ~= 'missing' and s ~= 'unknown' then return n end
    end
    return nil
end
