local A = FonzSaved
local L = A.locale

local _, module_name = A.module 'lockout'

--[[ Module: lockout

A lockout is defined as a contribution to a count limit for entry into instance 
zones.

This module will not attempt to assume any specific count, but will track the
lockouts that may apply within at least an hour. Typically, the limit in 
traditional WoW is 5 limits per hour per account.

Research facts:
1. Lockouts apply to an entire account (*1).
2. New lockouts are always created by a different character entering an 
instance. (*2)
3. Entering the same instance zone and difficulty on the same character with no
change in group status does NOT create a new lockout.
4. Resets allow entry into instance zones already entered, therefore the 
creation of new lockouts.
5. Resets can occur by:
a. Manually resetting all normal difficulty, non-raid instances, equivalent to 
the API command `ResetInstances()`. Note LBRS/UBRS entrance overlap so treating 
it as normal instance. Further testing required with specific instances (*3)
b. Changing instance difficulty setting will result in a more complete reset
that includes unsaved heroics and raids.
c. Entering a group will result in a more complete reset that includes unsaved 
heroics and raids.
6. Normal instance resets are NOT communicated to group members or even visible 
via the API.
7. Instance difficulty resets are communicated to group members via 
CHAT_MSG_SYSTEM.

Notes:
(*1) Does that include cross-faction? Do resets apply cross-faction?
(*2) Does that include entering the same instance as held by another account? 
How to reliably tell if given an id/id held for you, in general?
(*3) How do lockouts of instance zone groups behave, e.g. Dire Maul and Scarlet
Monastery wings?

--]]

local palette = A.require 'palette'
local savedinstances = A.require 'savedinstances'
local announce = A.require 'announce'

local util = A.requires(
  'util.table',
  'util.string',
  'util.time',
  'util.group',
  'util.network'
)

local isPveGroup = util.isPveGroup
local isPveInstance = util.isPveInstance
local isPveGroupLeader = util.isPveGroupLeader

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
  day = 24*60*60,
}

local NOTIFY_METHODS = {
  ["none"] = true,
  ["chat"] = true,
  ["error"] = true,
}

local defaults = {
  notify_method = "chat",
  announce_reset = true,
}

A.registerCharConfigDefaults(module_name, defaults)

local realm_defaults = {
  lockouts = {},
  maximum = 32,
}

A.registerRealmDefaults(module_name, realm_defaults)

function isExpired(entry, period)
  period = period or LOCKOUT_PERIODS.hour
  return entry and time() > (entry + period)
end

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
  
  function M.findInstanceKey(search_name, exact)
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
    local key = findInstanceKey(name)
    if not key then return end
    
    local translation = L["INSTANCE_ZONES"][key]
    return translation == true and key or translation
  end
end

function resetLockouts(reset_all, reset_instance)
  -- Ignore reset_instance and be conservative by resetting all normal or all
  -- instances.
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
  local function isSavedStale(saved)
    return saved and (time() > saved)
  end
  
  function cleanLockouts(lockouts)
    if not lockouts then return end
    
    local n = getn(lockouts)
    if n < 1 then return lockouts end
    
    local db = A.getProfileRealm(module_name)
    
    local updated = {}
    -- Resize from beginning if maximum allowed lockout table smaller than prior
    local first = (n <= db.maximum) and 1 or (n - db.maximum + 1)
    for i=first, n do
      local lockout = lockouts[i]
      -- Time-based "reset"
      if isExpired(lockout.entry) or isSavedStale(lockout.saved) then
        lockout.new = false
      end
      tinsert(updated, lockout)
    end
    
    return updated
  end
  
  function makeRoom(lockouts)
    if not lockouts then return end
    
    local n = getn(lockouts)
    local db = A.getProfileRealm(module_name)
    if n < db.maximum then return end
    
    -- Remove first/oldest entry
    table.remove(lockouts, 1)
  end
end

do
  local function errorMessage(msg)
    UIErrorsFrame:AddMessage(msg, 1, .25, .25, 1, 1)
  end

  function notifyLockout()
    local db = A.getCharConfig(module_name)
    local notify_method = db.notify_method or "chat"
    if notify_method == "none" then return end
    
    -- Find count of lockout within smallest lockout period
    local lockouts = getLockouts()
    local n = lockouts and getn(lockouts) or 0
    if n < 1 then return end
    
    local count = 1
    if n > 1 then
      local thetime = time()
      for i=n-1,1,-1 do
        local time_ago = thetime - lockouts[i].entry
        if time_ago < LOCKOUT_PERIODS.hour then
          count = count + 1
        end
      end
    end
    
    if notify_method == "chat" then
      A:print(format("%s%s",
        palette.color.lightyellow_text(L["New instance lockout: #"]), 
        palette.color.red_text(tostring(count))))
    elseif notify_method == "error" then
      errorMessage(format("%s%s",
        L["New instance lockout: #"], 
        tostring(count)))
    end
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
  
function M.getLockouts()
  local db = A.getProfileRealm(module_name)
  db.lockouts = cleanLockouts(db.lockouts) or {}
  return db.lockouts
end

function checkLockouts()  
  local is_instance, instance_type = isPveInstance()
  if not is_instance then return end
  
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
    makeRoom(lockouts)
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
    notifyLockout()
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
  local localeDateTime = util.localeDateTime
  
  local function formatDuration(duration, lang)
    -- Options: color + hide seconds
    return formatDurationFull(duration, false, true, lang)
  end
  
  local function formatDateTime(timestamp)
    local db = A.getProfileRealm("slashcmd")
    -- Options: 
    -- * is epoch, i.e. it comes from Lua time()
    -- * hide seconds
    -- * lang
    -- * datetime_format
    return localeDateTime(timestamp, true, true, nil, db.datetime_format)
  end
  
  local styles = {
    ["header"] = function(heading)
      return palette.color.gold_text(heading)
    end,
    ["1h"] = function(text)
      return palette.color.green_text(text)
    end,
    ["24h"] = function(text)
      return palette.color.lightyellow_text(text)
    end,
    ["older"] = function(text)
      return palette.color.rose_bud(text)
    end,
    ["character"] = function(name, class)
      return class_colors[strlower(class)](name)
    end,
    ["status"] = function(saved, added)
      return saved and palette.color.lightyellow_text(L["saved"])
        or added and palette.color.blue2(L["added"])
        or palette.color.gray_text(L["entered"])
    end,
    ["difftype"] = function(difficulty, instance_type)
      return instance_type =="raid" and L["raid"]
        or difficulty == INSTANCE_DIFFICULTY.heroic and L["heroic"]
        or palette.color.gray_text(L["normal"])
    end,
    ["duration"] = function(duration)
      return palette.color.green_text(formatDuration(duration))
    end,
    ["bracket"] = function(text, color)
      color = color or palette.color.white_text
      return format("%s%s%s", color("["), text or '', color("]"))
    end,
  }
  
  local function formatLockoutEntry(entry, time_ago)
    if time_ago < 60*60 then
      return styles["bracket"](styles["1h"](formatDateTime(entry)))
    elseif time_ago < 24*60*60 then
      return styles["bracket"](styles["24h"](formatDateTime(entry)))
    else
      return styles["bracket"](styles["older"](formatDateTime(entry)))
    end
  end
  
  -- Example format:
  -- 5. [<entry time>] <alt> "entered/saved to" <instance> - normal/heroic 
  -- (<entry time ago>)
  local function formatLockout(lockout)
    local time_ago = time() - lockout.entry
    local instance_name = findInstanceName(lockout.zone) or lockout.zone
    
    local msg = format("%s %s %s %s %s %s",
      formatLockoutEntry(lockout.entry, time_ago),
      styles["character"](lockout.name, lockout.class),
      styles["status"](lockout.saved, lockout.added),
      instance_name,
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
    -- List entries in normal order for chat so that latest is at the bottom
    for i=1,n do
      local lockout = lockouts[i]
      tinsert(msgtable, format("%02d. %s", i, formatLockout(lockout)))
    end
    
    A:print(format("%s\n%s", 
      styles["header"](L["Instances:"]),
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
    if n < 1 then
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
  
  function M.addLockout()
    local is_instance, instance_type = isPveInstance()
    if not is_instance then 
      A:print(styles["header"](L["You are not inside an instance."]))
      return
    end
    
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
    
    -- Force reset based on type of instance.
    if instance_type == "raid" or difficulty == INSTANCE_DIFFICULTY.heroic then
      resetLockouts(true)
    else
      resetLockouts()
    end
    
    local thetime = time()
    local lockouts = getLockouts()
    
    makeRoom(lockouts)
    tinsert(lockouts, {
      name = A.player.name,
      class = A.player.class,
      faction = A.player.faction,
      zone = zone,
      difficulty = difficulty,
      type = instance_type,
      entry = thetime,
      new = true,
      added = true,
    })
      
    notifyLockout()
    
    return true
  end
  
  local confirm_wipe_lockouts = format("%s%s", A.name, "_ConfirmWipeLockouts")
  
  StaticPopupDialogs[confirm_wipe_lockouts] = {
    text = L["Wipe ALL lockouts?"],
    button1 = TEXT(YES),
    button2 = TEXT(NO),
    OnAccept = function()
      wipeLockouts()
    end,
    timeout = 0,
    whileDead = 1,
    hideOnEscape = 1,
  } 
  
  function M.confirmWipeLockouts()
    local lockouts = getLockouts()
    
    local n = lockouts and getn(lockouts) or 0
    if n < 1 then
      A:print(styles["header"](L["You have 0 instance lockouts."]))
      return
    end
    
    StaticPopup_Show(confirm_wipe_lockouts)
  end
  
  function M.wipeLockouts()
    local db = A.getProfileRealm(module_name)
    local lockouts = db.lockouts
    if not lockouts then return end
    
    db.lockouts = nil
    listLockouts()
  end
end

-- EVENTS --

local frame = CreateFrame("Frame")
M.event_frame = frame

do
  local dispatcher = CreateFrame("Frame")
  dispatcher:SetScript("OnUpdate", function()
    if dispatcher.func and GetTime() >= dispatcher.timestamp then
      A.debug("Scheduled func dispatched.")
      dispatcher.func(dispatcher.args and unpack(dispatcher.args))
      dispatcher.func = nil
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

-- EVENTS: NEW LOCKOUTS --

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
    end
  end
end

do  
  local first_login_world = true
  local first_login_party = true
  local is_solo = true
  
  function frame:PARTY_MEMBERS_CHANGED()
    -- Assumes PARTY_MEMBERS_CHANGED always fires on login if in a group.
    
    -- Stop if first login and PLAYER_ENTERING_WORLD already set group status. 
    -- Resets can only occur when joining a group, i.e. from solo.
    if first_login_party and not is_solo then
      first_login_party = false
      return
    end
    
    local in_group = isPveGroup()
    
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
    -- Note. Necessary to use Unit functions before group events fire for
    -- reliable group status.
    is_solo = not (UnitInRaid("player") or UnitInParty("player"))

    -- Stop if already logged into world
    if not first_login_world then return end
    first_login_world = false
    
    -- Stop if not in an instance
    local is_instance, instance_type = isPveInstance()
    if not is_instance then return end
    
    A.trace("Logged into an instance. Checking for new lockout.")
    -- Schedule lockouts check due to lack of updates to zone API
    schedule(checkLockouts, 5.0) -- delay 5s
  end
end

-- EVENTS: RESETS (COMMUNICATION) --

local INSTANCE_TYPES = {
  party = 1,
  raid = 2,
}

local RESET_TYPES = {
  normal = 1,
  difficulty = 2,
}

local COMMANDS = {
  --[[
  Name chosen to function as a basic protocol in case other addons need to
  easily pickout reset messages from all addon messages.
  This is almost identical to TBC Classic's Nova Instance Tracker addon's 
  basic reset message, except Nova compresses all message content.
  --]]
  instancereset = "instancereset"
}

local reset_messages = {
  ["PARTY"] = function(sender)
    return format(L["Party leader %s has reset all normal instances."], 
      sender)
  end,
  ["RAID"] = function(sender)
    return format(L["Raid leader %s has reset all unsaved normal instances."], 
      sender)
  end,
}

do
  -- Time in seconds
  local DELAYS = {
    normal = 3,
    difficulty = 3,
  }
  local last_times = {}
  
  function resetSeen(tag)
    last_times[tag] = nil
  end
  
  -- No point spamming the server too often. Create throttle function
  function seen(tag)
    local last_time = last_times[tag]
    
    if not last_time or (GetTime() - last_time > DELAYS[tag]) then
      A.debug("[module: %s] %s %s", module_name, tag, "cache miss")
      last_times[tag] = GetTime()
      return false
    end
    
    return true
  end
end

function compareLastInstance(zone, entry, instance_type, difficulty)
  local lockouts = getLockouts()
  local n = lockouts and getn(lockouts) or 0
  if n < 1 then return end
  
  -- Basic checks for zone name and lockout period required
  if not zone then return end
  if entry and isExpired(entry) then return end
  
  local found = false
  for i=n,1,-1 do
    local lockout = lockouts[i]
    -- Find unsaved instance comparing zone name by token/key, not translation
    if not lockout.saved 
        and findInstanceKey(lockout.zone, true) == findInstanceKey(zone, true)
        and not isExpired(lockout.entry) then
      -- Default is found true if saved, zone and entry conditions met
      -- UNLESS more restrictive conditions are present and fail
      found = true
      if instance_type and lockout.type ~= instance_type then
        found = false
      end
      if difficulty and lockout.difficulty ~= difficulty then
        found = false
      end
    end
    if found then break end
  end
  
  return found
end

do
  local formatDurationFull = util.formatDurationFull
  local deserialize = util.deserialize
  local keyByValue = util.keyByValue
  
  local function formatDuration(duration, lang)
    -- Options: color + hide seconds
    return formatDurationFull(duration, false, true, lang)
  end
  
  local function printResetInfo(payload)
    local n = payload and getn(payload) or 0
    if n < 1 then return end
    
    local instance = payload[1]
    n = type(instance) == "table" and getn(instance)
    if n and n > 0 then
      local zone = instance[1]
      local entry = n > 1 and tonumber(instance[2])
      local instance_type = n > 2 and keyByValue(INSTANCE_TYPES, instance[3])
      local difficulty = n > 3 and tonumber(instance[4])
      
      local has_shared_instance = compareLastInstance(zone, entry, 
        instance_type, difficulty)
      if not has_shared_instance then return end
      
      local msg = format("%s", palette.color.green_text(zone))
      if difficulty then
        local str = keyByValue(INSTANCE_DIFFICULTY, difficulty, true)
        msg = str and format("%s - %s", msg, L[str])
      end
      if entry then
        local ago = time() - entry
        msg = format("%s (%s)", msg, formatDuration(ago))
      end
      
      A:print(format(L["Latest shared instance: %s."], msg))
    elseif not n and strlen(tostring(instance)) > 0 then
      local has_shared_instance = compareLastInstance(instance)
      if not has_shared_instance then return end
      
      local msg = format("%s", palette.color.green_text(instance))
      A:print(format(L["Latest shared instance: %s."], msg))
    end
  end
  
  local function printReset(channel, sender)
    A:print(reset_messages[channel](sender))
  end
  
  function frame:CHAT_MSG_ADDON(prefix, msg, channel, sender)
    if prefix ~= A.name then return end
    if sender == A.player.name then return end
    if not (channel == "PARTY" or channel == "RAID") then return end
    if not msg or strlen(msg) < 1 then
      A.warn("[module: %s] %s", module_name, "Empty message received.")
      return
    end
    if not isPveGroupLeader(sender) then 
      A.warn("[module: %s] %s %s", module_name, 
        "Reset command is not from a group leader. Sender:", sender)
      return
    end
    
    A.debug("Deserialize input: %s", msg)
    
    local command, instruction, payload = deserialize(msg)
    if not command or command ~= COMMANDS.instancereset then 
      A.warn("[module: %s] %s", module_name, "Received invalid command.")
      return
    end
    -- Instance reset command must have an instruction for the type of reset
    if not instruction or not tonumber(instruction) then 
      A.warn("[module: %s] %s", module_name, 
        "Received invalid instance reset instruction.")
      return
    end
    
    A.trace("command and instruction present.")
    
    -- Reset

    instruction = tonumber(instruction)
    if instruction == RESET_TYPES.normal then
      printReset(channel, sender)
      resetLockouts()
    elseif instruction == RESET_TYPES.difficulty then
      A.info("Group leader reset by changing instance difficulty.")
      -- Not necessary to reset lockouts here because this reset type
      -- is broadcast to group by server, visible as CHAT_MESSAGE_SYSTEM.
    else
      A.warn("[module: %s] %s %s", module_name, 
        "Received unknown reset instruction:", tostring(instruction))
    end
    
    -- Reset payload treated as informational only
    printResetInfo(payload)
  end
end

do
  local strmatch = string.match
  local gsub = string.gsub
  
  local serialize = util.serialize
  local send = util.send
  
  local first_login = true
  
  -- Convert Lua formatstring to Lua string pattern
  local function f2p(formatstring)
    -- Save string formatters
    formatstring = gsub(formatstring, "%%s", "¬@s")
    -- Escape pattern magic characters
    formatstring = gsub(formatstring, "([%^%$%(%)%%%.%[%]%*%+%?%)%-])", 
      "%%%1")
    -- Unescape string formatters
    return (gsub(formatstring, "¬@s", "%(%.%+%)"))
  end
  
  local PATTERNS = {
    ERR_DUNGEON_DIFFICULTY_CHANGED_S = f2p(ERR_DUNGEON_DIFFICULTY_CHANGED_S),
    INSTANCE_RESET_SUCCESS = f2p(INSTANCE_RESET_SUCCESS),
  }
  
  local function getLastUnsavedLockout()
    local lockouts = getLockouts()
    local n = lockouts and getn(lockouts) or 0
    if n < 1 then return end
    
    for i=n,1,-1 do
      local lockout = lockouts[i]
      if not lockout.saved and not isExpired(lockout.entry) then
        return lockout
      end
    end
  end
  
  local function formatPayload(zone, entry, instance_type, difficulty)
    return {
      { zone, entry, INSTANCE_TYPES[instance_type], difficulty, }
    }
  end
  
  local function sendReset(reset_type, group, lockout)
    local payload
    if lockout then
      payload = formatPayload(lockout.zone, lockout.entry, lockout.type,
        lockout.difficulty)
    end
    
    local msg = serialize(COMMANDS.instancereset, RESET_TYPES[reset_type], 
      payload)
    A.debug("Serialize output: %s", msg)
    send(msg, group)
  end
  
  function frame:CHAT_MSG_SYSTEM(msg, param1)    
    if not msg then return end
    --[[ Blizzard's GlobalStrings.lua:
    
    - ERR_DUNGEON_DIFFICULTY_CHANGED_S = 
      "Dungeon Difficulty set to %s. (All saved instances have been reset)";
    - INSTANCE_RESET_SUCCESS = "%s has been reset.";
    
    --]]
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
      
      -- Spam protection, e.g. from multiple different instances reset
      if seen("difficulty") then return end
      
      -- If in group and leader, send reset via addon channel.
      -- No need to announce this type of reset since it is visible to group.
      local group = isPveGroup()
      if not group then return end
      if not isPveGroupLeader() then return end
      
      local lockout = getLastUnsavedLockout()
      sendReset("difficulty", group, lockout)
      return
    end
    
    local reset_instance = strmatch(msg, PATTERNS["INSTANCE_RESET_SUCCESS"])
    if reset_instance then
      -- Reset normals only
      A.trace("resetLockouts() from INSTANCE_RESET_SUCCESS")
      resetLockouts(nil, reset_instance)

      -- Spam protection, e.g. from multiple different instances reset
      if seen("normal") then return end
      
      -- If in group and leader, announce to group and send reset via addon 
      -- channel.
      local group = isPveGroup()
      if not group then return end
      if not isPveGroupLeader() then return end
      
      local msg = reset_messages[group](A.player.name)
      local lockout = getLastUnsavedLockout()
      if lockout then
        msg = format("%s %s", msg, L["Latest instance: %s."])
        msg = format(msg, palette.color.green_text(lockout.zone))
      end
      
      local db = A.getCharConfig(module_name)
      if db.announce_reset then
        announce.announceMessage(msg, group)
      end
      sendReset("normal", group, lockout)
    end
  end
end

-- Fires when an addon communication message is received
-- args: prefix, text, channel, sender
frame:RegisterEvent("CHAT_MSG_ADDON")

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
    event_method(this, arg1, arg2, arg3, arg4)
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
    Maximum = {
      type = "range",
      name = L["Maximum Instances"],
      desc = L["Set maximum number of tracked instances."],
      get = function() 
        local db = A.getProfileRealm(module_name)
        return db.maximum
      end,
      set = function(msg) 
        local db = A.getProfileRealm(module_name)
        db.maximum = tonumber(msg)
      end,
      usage = L["<number: greater than 0>"],
      validate = function(msg)
        local n = msg and strlen(msg) > 0 and tonumber(msg)
        return n and n > 0
      end,
      min = 1, max = 60, softMin = 1, softMax = 32, step = 1, bigStep = 10,
    },
    Announce = {
      type = "toggle",
      name = L["Announce Resets"],
      desc = L["Toggle whether to announce resets to group chat."],
      get = function() 
        local db = A.getCharConfig(module_name)      
        return db.announce_reset
      end,
      set = function()
        local db = A.getCharConfig(module_name)      
        db.announce_reset = not db.announce_reset
      end,
    },
  },
}