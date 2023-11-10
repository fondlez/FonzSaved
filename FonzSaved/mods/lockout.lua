local A = FonzSaved
local L = A.locale

local _, module_name = A.module 'lockout'

--[[ Module: lockout
A lockout is defined as a contribution to a count limit for entry into instance 
zones.

This module will not attempt to assume any specific count, but will track the
lockouts that may apply within an hour. Typically, the limit in traditional WoW
is 5 limits per hour per account.

Research facts:
1. Lockouts apply to an entire account.
2. New lockouts are always created by a different character entering an 
instance. (*)
3. Entering the same instance zone and difficulty on the same character with no
change in group status does NOT create a new lockout.
4. Resets allow entry into instance zones already entered, therefore the 
creation of new lockouts.
5. Resets can occur by:
a. Manually resetting all normal difficulty, non-raid instances, equivalent to 
the API command `ResetInstances()`. Note LBRS/UBRS entrance overlap so treating 
it as normal instance.
b. Changing instance difficulty setting will result in a more complete reset
that includes unsaved heroics and raids.
c. Entering a group will result in a more complete reset that includes unsaved 
heroics and raids.

Notes:
* Does that include entering the same instance as held by another account?
* How to reliably tell if given an id/id held for you, in general?

--]]

local palette = A.require 'palette'
local savedinstances = A.require 'savedinstances'

local util = A.requires(
  'util.table',
  'util.string',
  'util.time'
)

local GetInstanceDifficulty = GetInstanceDifficulty
local GetRealNumPartyMembers = GetRealNumPartyMembers
local GetRealNumRaidMembers = GetRealNumRaidMembers
local GetRealZoneText = GetRealZoneText
local IsInInstance = IsInInstance

local format = string.format
local strlen, strlower = strlen, strlower
local tinsert, tconcat = table.insert, table.concat

local INSTANCE_DIFFICULTY = {
  normal = 1,
  heroic = 2,
}
M.INSTANCE_DIFFICULTY = INSTANCE_DIFFICULTY

local LOCKOUT_PERIODS = {
  hour = 60*60,
}

local NOTIFY_METHODS = {
  ["none"] = true,
  ["chat"] = true,
  ["error"] = true,
}

local defaults = {
  notify_method = "chat",
}

A.registerCharConfigDefaults(module_name, defaults)

local realm_defaults = {
  lockouts = {},
}

A.registerRealmDefaults(module_name, realm_defaults)

do
  local strlen = strlen
  
  local uniqueKeySearch = util.uniqueKeySearch
  
  local merged_instance_names
  
  local function mergeTokenValuesAcrossLocales(token)
    local t = {}
    for code, catalog in pairs(A.locale_info.catalogs) do
      local entry = catalog[token]
      for key, value in pairs(entry) do
        t[value == true and key or value] = key
      end
    end
    
    return t
  end
  
  local function search(search_name, exact)
    if not search_name or strlen(search_name) < 1 then return end
    
    if not merged_instance_names then
      merged_instance_names = mergeTokenValuesAcrossLocales("INSTANCE_ZONES")
    end
    
    local t = merged_instance_names
    if exact then
      return t[search_name]
    else
      local name = uniqueKeySearch(t, search_name, util.leq)
      return name and t[name]
    end
  end
  
  function M.findInstanceName(name)
    local key = search(name)
    if not key then return end
    
    local translation = L["INSTANCE_ZONES"][key]
    translation = translation == true and key or translation
    return translation
  end
end

function resetLockouts(reset_all)
  local db = A.getProfileRealm(module_name)
  local lockouts = db.lockouts
  if not lockouts then return end

  A.trace("Reset lockouts.")
  
  db.lockouts = cleanLockouts(db.lockouts)
  
  for i, lockout in ipairs(lockouts) do
    if lockout.difficulty == INSTANCE_DIFFICULTY.normal 
        and lockout.type ~= "raid"
        or (reset_all and not lockout.saved) then
      lockout.new = false
    end
  end
end

do
  local function isSavedStale(lockout)
    return time() > lockout.saved
  end

  local function isExpired(lockout)
    return time() > (lockout.entry + LOCKOUT_PERIODS.hour)
  end
  
  function cleanLockouts(lockouts)
    if not lockouts then return end
    
    -- Cleanup lockouts, removing expired lockouts or stale saved instances
    local updated = {}
    for i, lockout in ipairs(lockouts) do
      if not (isExpired(lockout)
          or (lockout.saved and isSavedStale(lockout))) then
        tinsert(updated, lockout)
      end
    end
    return updated
  end
end

function isNewInstance(lockouts, zone, difficulty)
  -- Search latest instance first (reverse search)
  for i=getn(lockouts), 1, -1 do
    local lockout = lockouts[i]
    -- Check if existing new (non-reset) instance
    A.debug("Lockout: %s [%s] %s %s",
      lockout.name, lockout.zone, tostring(lockout.difficulty), 
      tostring(lockout.new))
    if lockout.name == A.player.name 
        and lockout.zone == zone and lockout.difficulty == difficulty 
        and lockout.new == true then
      return false
    end
  end
  
  return true
end

do
  local function errorMessage(msg)
    UIErrorsFrame:AddMessage(msg, 1, .25, .25, 1, 1)
  end

  function notifyLockout(num)
    local db = A.getCharConfig(module_name)
    local notify_method = db.notify_method or "chat"
    
    if notify_method == "none" then return end
    
    if notify_method == "chat" then
      A:print(format("%s%s",
        palette.color.lightyellow_text(L["New instance lockout: #"]), 
        palette.color.red_text(tostring(num))))
    elseif notify_method == "error" then
      errorMessage(format("%s%s",
        L["New instance lockout: #"], 
        tostring(num)))
    end
  end
end
  
function M.getLockouts()
  local db = A.getProfileRealm(module_name)
  db.lockouts = cleanLockouts(db.lockouts) or {}
  return db.lockouts
end

function checkLockouts()  
  -- Stop unless inside non-PvP instance
  local is_instance, instance_type = IsInInstance()
  if not is_instance then return end
  if instance_type == "pvp" or instance_type == "arena" then return end
  
  local zone = GetRealZoneText()
  if not zone or strlen(zone) < 1 then
    A.warn("No instance zone name. Potential lockout not registered.")
    return
  end
  
  local difficulty = GetInstanceDifficulty()
  if not difficulty then
    A.warn("Unknown instance difficulty. Potential lockout not registered")
    return
  end
  
  local thetime = time()
  local lockouts = getLockouts()
  
  -- Only one "new" instance for the same player, zone and difficulty is allowed
  if isNewInstance(lockouts, zone, difficulty) then
    tinsert(lockouts, {
      name = A.player.name,
      class = A.player.class,
      faction = A.player.faction,
      zone = zone,
      difficulty = difficulty,
      type = instance_type,
      entry = thetime,
      new = true,
    })
    notifyLockout(getn(lockouts))
  end
end

function M.pendingSaved()  
  -- Being saved means being inside an instance which means it must be new.
  -- Check there is actually a new instance for this zone.
  checkLockouts()
  
  local db = A.getProfileRealm(module_name)
  local lockouts = db.lockouts
  
  local zone = GetRealZoneText()
  local difficulty = GetInstanceDifficulty()
  
  local found = false
  for i=getn(lockouts), 1, -1 do
    local lockout = lockouts[i]
    -- Find unsaved lockout with matching properties
    if lockout.name == A.player.name 
        and lockout.zone == zone and lockout.difficulty == difficulty
        and lockout.new and not lockout.saved then
      found = true
      lockout.pending = true
      break
    end
  end

  if not found then
    A.error("Unable to find a matching lockout to queue as saved.")
  end
end

do
  local findHeroicByName = savedinstances.findHeroicByName
  local leq = util.leq
  
  -- 1. Assumes locale of saved is the same as locale of zone API
  -- 2. Assumes non-heroic saved names are the same as names from zone API
  local function findSavedReset(saved, zone)
    for name, detail in pairs(saved) do
      -- Heroic saved names are not zone names!
      local heroic = findHeroicByName(name, true)
      if heroic and leq(heroic.zone, zone) or leq(name, zone) then
        return detail.reset
      end
    end
  end
  
  function M.canSaveLockout(saved)
    if not saved then return end
    
    local db = A.getProfileRealm(module_name)
    local lockouts = db.lockouts
    if not lockouts then return end
    
    for i=getn(lockouts), 1, -1 do
      local lockout = lockouts[i]
      -- Search for pending saved
      if lockout.name == A.player.name and lockout.pending then
        lockout.saved = findSavedReset(saved, lockout.zone)
        lockout.pending = nil
        return
      end
    end
  end
end

do
  local class_colors = palette.color.classes
  
  local formatDurationFull = util.formatDurationFull
  local isoTime = util.isoTime
  
  local function formatDuration(duration, lang)
    -- Options: color + hide seconds
    return formatDurationFull(duration, false, true, lang)
  end
  
  local function formatTime(timestamp)
    -- Options: 
    -- * is epoch, i.e. it comes from Lua time()
    -- * hide seconds
    return isoTime(timestamp, true, true)
  end
  
  local styles = {
    ["header"] = function(heading)
      return palette.color.gold_text(heading)
    end,
    ["character"] = function(name, class)
      return class_colors[strlower(class)](name)
    end,
    ["entered"] = function(text)
      return palette.color.gray_text(text)
    end,  
    ["saved"] = function(text)
      return palette.color.lightyellow_text(text)
    end,  
    ["savedinstance"] = function(text)
      return palette.color.lightyellow_text(text)
    end,
    ["difftype"] = function(difficulty, instance_type)
      return instance_type =="raid" and L["raid"]
        or difficulty == INSTANCE_DIFFICULTY.heroic and L["heroic"]
        or palette.color.gray_text(L["normal"])
    end,
    ["duration"] = function(duration)
      return palette.color.green_text(formatDuration(duration))
    end,  
  }
  
  -- Example format:
  -- 5. [<entry time>] <alt> "entered/saved to" <instance> - normal/heroic 
  -- (<entry time ago>)
  local function formatLockout(lockout)
    local time_ago = time() - lockout.entry
    local instance_name = findInstanceName(lockout.zone) or lockout.zone
    
    local msg = format("%s %s %s %s %s %s",
      format("[%s]", formatTime(lockout.entry)),
      styles["character"](lockout.name, lockout.class),
      lockout.saved and styles["saved"](L["saved to"]) 
        or styles["entered"](L["entered"]),
      lockout.saved and styles["savedinstance"](instance_name) or instance_name,
      format("- %s", styles["difftype"](lockout.difficulty, lockout.type)),
      format("(%s)", formatDuration(time_ago))
    )
    return msg
  end
  
  function M.listLockouts()
    local lockouts = getLockouts()
    
    local n = lockouts and getn(lockouts) or 0
    if not lockouts or n < 1 then
      A:print(styles["header"](L["You have 0 instance lockouts."]))
      return
    end
    
    local msgtable = {}
    -- List lockouts in reverse order of entry but numbered from latest.
    for i=n,1,-1 do
      local lockout = lockouts[i]
      tinsert(msgtable, format("%d. %s", i, formatLockout(lockout)))
    end
    
    A:print(format("%s\n%s", 
      styles["header"](L["Instance lockouts:"]),
      tconcat(msgtable, "\n")
    ))
  end
  
  local confirm_delete_lockout_name
    = format("%s%s", A.name, "_ConfirmDeleteLockout")
  StaticPopupDialogs[confirm_delete_lockout_name] = {
    text = L["Delete this lockout?"],
    button1 = TEXT(YES),
    button2 = TEXT(NO),
    OnAccept = function()
      deleteLockout()
    end,
    timeout = 0,
    whileDead = 1,
    hideOnEscape = 1,
  }
  
  local delete_this_lockout
  
  function deleteLockout()
    A.debug("Deleting instance lockout [%d]", delete_this_lockout)
    
    local db = A.getProfileRealm(module_name)
    db.lockouts = cleanLockouts(db.lockouts) or {}
    
    local t = {}
    for i,lockout in ipairs(db.lockouts) do
      if i ~= delete_this_lockout then
        tinsert(t, lockout)
      end
    end
    
    db.lockouts = t
    delete_this_lockout = nil
    listLockouts()
  end
  
  function M.confirmDeleteLockout(index)
    local lockouts = getLockouts()
    
    local n = lockouts and getn(lockouts) or 0
    if not lockouts or n < 1 then
      A:print(styles["header"](L["You have 0 instance lockouts."]))
      return
    end
    
    if index < 1 or index > n then
      A:print(styles["header"](L["No such instance lockout index."]))
      return
    end
    
    delete_this_lockout = index
    StaticPopup_Show(confirm_delete_lockout_name)
  end
end

-- EVENTS --

local frame = CreateFrame("Frame")
M.event_frame = frame

local is_action_needed = false

do
  local dispatcher = CreateFrame("Frame")
  dispatcher:SetScript("OnUpdate", function()
    if not is_action_needed then
      dispatcher.func = nil
      dispatcher:Hide()
      return
    end
    if dispatcher.func and GetTime() >= dispatcher.timestamp then
      A.debug("Scheduled func dispatched.")
      dispatcher.func(dispatcher.args and unpack(dispatcher.args))
      dispatcher.func = nil
      is_action_needed = false
      dispatcher:Hide()
    end
  end)
  dispatcher:Hide()

  function schedule(func, delay)
    if not func then 
      A.error("Invalid func scheduled.")
      return
    end
    delay = tonumber(delay) or 0
    dispatcher.func = func
    dispatcher.timestamp = GetTime() + delay
    dispatcher:Show()
  end
end

-- NEW LOCKOUTS --

do
  local first_login = true
  local is_inside = false

  -- Not all instances occur on zone changes, e.g. Sunken Temple, which is also
  -- actually the same zone "The Temple of Atal'Hakkar" as its entrance zone.
  -- Check for specific instance change (entry) to trigger lockout checks.
  function frame:UPDATE_INSTANCE_INFO()
    -- Assumes that this event fires on login, regardless of instance status.
    -- First login checks are responsibility of PLAYER_ENTERING_WORLD event.
    if first_login then
      first_login = false
      return
    end
    
    local is_instance, instance_type = IsInInstance()    
    if not is_instance then
      is_inside = false
      return
    end
    if instance_type == "pvp" or instance_type == "arena" then return end

    -- If this fired due to an instance entry, then check for lockouts
    if not is_inside and is_instance then
      is_inside = true
      A.trace("Entered an instance. Checking for new lockout.")
      
      -- Schedule lockouts check due to lack of updates to zone API
      schedule(checkLockouts, 1.5) -- delay 1.5s
      is_action_needed = true
    end
  end
end

do
  local first_login = true
  local is_solo = true
  
  local function isInGroup()
    -- Only interested in group membership outside of PvP (battlegrounds)
    return GetRealNumPartyMembers() > 0 or GetRealNumRaidMembers() > 0
  end
  
  function frame:PARTY_MEMBERS_CHANGED()
    if first_login then 
      -- Should never be entered since PLAYER_ENTERING_WORLD fires first.
      A.error("Impossible to join a group on login.")
      return
    end
    
    local in_group = isInGroup()
    
    -- Joining a new group effectively resets instances
    if is_solo and in_group then
      is_solo = false
      -- Reset normals + unsaved heroics + unsaved raids
      A.trace("resetLockouts(true) from PARTY_MEMBERS_CHANGED")
      resetLockouts(true)
    -- Otherwise if previously in group and now solo, then update status
    elseif not is_solo and not in_group then
      -- Left the group
      is_solo = true
    end
  end

  function frame:PLAYER_ENTERING_WORLD()
    is_solo = not isInGroup()
    
    -- Stop if already logged in
    if not first_login then return end
    first_login = false
    
    A.trace("Logged into an instance. Checking for new lockout.")
    -- Schedule lockouts check due to lack of updates to zone API
    schedule(checkLockouts, 5.0) -- delay 5s
    is_action_needed = true
  end
end

-- RESETS --

do
  local strmatch = string.match
  local gsub = string.gsub
  
  local first_login = true
  
  -- Convert Lua formatstring to Lua string pattern
  local function f2p(formatstring)
    -- Save string formatters
    formatstring = (gsub(formatstring, "%%s", "¬@s"))
    -- Escape pattern magic characters
    formatstring = (gsub(formatstring, "([%^%$%(%)%%%.%[%]%*%+%?%)%-])", 
      "%%%1"))
    -- Unescape string formatters
    return (gsub(formatstring, "¬@s", "%[%%P%%S%]%+"))
  end
  
  local PATTERNS = {
    ERR_DUNGEON_DIFFICULTY_CHANGED_S = f2p(ERR_DUNGEON_DIFFICULTY_CHANGED_S),
    INSTANCE_RESET_SUCCESS = f2p(INSTANCE_RESET_SUCCESS),
  }
  
  function frame:CHAT_MSG_SYSTEM(msg, param1)    
    if not msg then return end
    -- Blizzard's GlobalStrings.lua:
    -- ERR_DUNGEON_DIFFICULTY_CHANGED_S = 
    --   "Dungeon Difficulty set to %s. (All saved instances have been reset)";
    -- INSTANCE_RESET_SUCCESS = "%s has been reset.";
    -- Assumes that, %s is a single word like "Normal" or "Heroic" in all
    -- locales.
    if strmatch(msg, PATTERNS["ERR_DUNGEON_DIFFICULTY_CHANGED_S"]) then
      -- Ignore spurious ERR_DUNGEON_DIFFICULTY_CHANGED_S message if inside
      -- instance on login.
      -- Assumes the message always appears (does this vary with server?)
      if IsInInstance() and first_login then
        first_login = false
        return
      end
      first_login = false

      -- Reset normals + unsaved heroics + unsaved raids
      A.trace("resetLockouts(true) from ERR_DUNGEON_DIFFICULTY_CHANGED_S")
      resetLockouts(true)
    elseif strmatch(msg, PATTERNS["INSTANCE_RESET_SUCCESS"]) then      
      -- Reset normals only
      resetLockouts()
    end
  end
end

-- Fires when a system message is received
frame:RegisterEvent("CHAT_MSG_SYSTEM")

-- Fires when information about the membership of the player’s party changes or 
-- becomes available. Also fires on leaving a group
frame:RegisterEvent("PARTY_MEMBERS_CHANGED")

-- Fired when the player enters the world, reloads the UI, enters/leaves an 
-- instance or battleground
frame:RegisterEvent("PLAYER_ENTERING_WORLD")

-- Fires when information about instances to which the player is saved changes 
-- or becomes available.
-- This is more reliable than "ZONE_CHANGED_NEW_AREA" due to some instances
-- inside the same zone name as their entrance, e.g. Sunken Temple.
frame:RegisterEvent("UPDATE_INSTANCE_INFO")

frame:SetScript("OnEvent", function()
  local event_method = frame[event]
  if event_method then
    event_method(this, arg1, arg2)
  end
end)

-- MODULE OPTIONS --

if not A.options then
  A.options = {
    type = "group",
    args = {},
  }
end

A.options.args["lockout"] = {
  name = L["Lockout"],
  desc = format(L["%s chat options for instance lockouts."], 
    L["SLASHCMD_LOCKOUT"]),
  type = "group",
  args = {
    Notify = {
      type = "choice",
      name = L["Notify Method"],
      desc = L["Select method of notification for new lockout."],
      get = function() 
        local db = A.getCharConfig(module_name)      
        return db.notify_method
      end,
      set = function(msg)
        msg = strlower(msg)
        if not NOTIFY_METHODS[msg] then return end
        local db = A.getCharConfig(module_name)
        db.notify_method = msg
      end,
      usage = "{ none | chat | error }",
      validate = function(msg)
        return msg and NOTIFY_METHODS[strlower(msg)]
      end,
      choices = {
        ["none"] = L["None"],
        ["chat"] = L["Chat message"],
        ["error"] = L["Error message"],
      },
      choiceType = "dict",
      choiceOrder = { 
        "none", "chat", "error",
      },
    },
  },
}
