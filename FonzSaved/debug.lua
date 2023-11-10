local A = FonzSaved

A.loglevels = {
  FATAL=0, -- kills the service [very rare in a hosted application like WoW]
  ERROR=1, -- kills the application [minimum logging for releases]
  WARN=2,  -- unwanted, but potentially recoverable, state
  INFO=3,  -- configuration or administration detail
  TRACE=4, -- developer: path detail
  DEBUG=5, -- developer: state detail
}
A.loglevel = A.loglevels["ERROR"]

function A.logging(level)
  return A.loglevel >= A.loglevels[level]
end

do
  local format = string.format
  local addon = format("|cffffff0c[%s]|r", A.name)
  
  function A.createDebugFunction(prefix, color)
    color = color or "ffff1100"
    return function(...)
      if A.loglevel < A.loglevels[prefix] then return end
      local arg = {...}
      local result, message = pcall(format, unpack(arg))
      if not result then
        local t = {}
        for i, v in ipairs(arg) do
          t[i] = tostring(v)
        end
        message = table.concat(t, " ")
      end
      
      DEFAULT_CHAT_FRAME:AddMessage(
        format("%s |c%s%s:|r %s", addon, color, prefix, message))
    end
  end
end

A.debug = A.createDebugFunction("DEBUG", "ff00ffff") --cyan
A.trace = A.createDebugFunction("TRACE", "ffd800ff") --purple
A.warn = A.createDebugFunction("WARN", "ffffff00")   --yellow
A.info = A.createDebugFunction("INFO", "ff00ff00")   --green
A.error = A.createDebugFunction("ERROR", "ffff0000") --red
A.fatal = A.createDebugFunction("FATAL", "ffffffff") --white
