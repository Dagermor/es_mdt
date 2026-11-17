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
