local A = FonzSaved
local L = A.locale

-- [Optional] Addon dependency: GUI

local _, module_name = A.module 'slashcmd'

local palette = A.require 'palette'
local cmdoptions = A.require 'cmdoptions'
local announce = A.require 'announce'
local whisper = A.require 'whisper'
local lockout = A.require 'lockout'
local raidleadersaved = A.require 'raidleadersaved'

local util = A.requires(
  'util.table',
  'util.string',
  'util.time'
)

local realm_defaults = {
  lang = A.locale_info.code,
  datetime_format = "ISO",
}

A.registerRealmDefaults(module_name, realm_defaults)

local UnitName = UnitName
local UnitClass = UnitClass

local format = string.format
local strlen = strlen
local strlower, strupper = strlower, strupper
local unpack = unpack or util.unpack
local tinsert, tconcat = tinsert, table.concat

function A.prefix()
  return format("{%s}", A.name)
end

do
  local strsplit = strsplit or util.strsplit
  local strfind = strfind
  local strtrim = util.strtrim
  local strpsplit = util.strpsplit
  
  local saved_match_list = {
    [1] = { word = 1, pattern = "p|%[party%]", token = "PARTY" },
    [2] = { word = 1, pattern = "r|%[raid%]", token = "RAID" }, 
    [3] = { word = 1, pattern = "g|%[guild%]", token = "GUILD" },
    [4] = { word = 1, pattern = "o|%[officer%]", token = "OFFICER" },
    [5] = { word = 1, pattern = "b|%[battleground%]", token = "BATTLEGROUND" },
    [6] = { word = 1, pattern = "s|%[say%]", token = "SAY" },
    [7] = { word = 1, pattern = "y|%[yell%]", token = "YELL" },
    [8] = { word = 1, pattern = "t|%[target%]", token = "TARGET" },
    [9] = { word = 1, pattern = "m|%[mouseover%]", token = "MOUSEOVER" },
    [10] = { word = 1, pattern = "?|h|%[help%]", token = "HELP" },
    [11] = { word = 1, pattern = "(%d+)", token = "CHANNEL_NUM" },
    [12] = { word = 1, pattern = "%[([^%]]+)%]", token = "CHANNEL_NAME" },
    [13] = { word = 0, pattern = "(%a%a%a?%a?%a?%a?%a?%a?%a?%a?%a?%a?)", 
      token = "NAME" }, -- WoW name: 2-12 letters
    [14] = { word = 0, pattern = "(%a%a%a?%a?%a?%a?%a?%a?%a?%a?%a?%a?)%s+(.+)", 
      token = "NAME_RAID" }, -- WoW name: 2-12 letters
  }
  
  local saved_help = {
    PARTY = { usage="p|[party]", 
      help = "Announce to party" },
    RAID = { usage="r|[raid]", 
      help = "Announce to raid" },
    GUILD = { usage="g|[guild]", 
      help = "Announce to guild" },
    OFFICER = { usage="o|[officer]", 
      help = "Announce to guild officers" },
    BATTLEGROUND = { usage="b|[battleground]", 
      help = "Announce to battleground" },
    SAY = { usage="s|[say]", 
      help = "Announce to /say" },
    YELL = { usage="y|[yell]", 
      help = "Announce to /yell" },
    TARGET = { usage="t|[target]", 
      help = "Query target" },
    MOUSEOVER = { usage="m|[mouseover]", 
      help = "Query mouseover" },
    HELP = { usage="?|h|[help]", 
      help = "Show help" },
    CHANNEL_NUM = { usage="<number>", 
      help = "Announce to channel number" },
    CHANNEL_NAME = { usage="[<name>]", 
      help = "Announce to channel <name>" },
    NAME = { usage="<player>", 
      help = "Query player with <player> name" },
    NAME_RAID = { usage="<player> <raid>", 
      help = "Query player with <player> name and <raid> raid name" },
  }
  
  local color_heading = palette.color.yellow
  local color_normal = palette.color.white
  
  local function optionFormatter(usage, help)
    return format("- %s %s", 
      color_heading(format("%s:", usage)),
      color_normal(help))
  end
  
  local function usageFormatter(command, description)
    return format("%s %s %s",
      color_heading(L["Usage:"]),
      color_normal(command),
      color_normal(description or ''))
  end
  
  function showSavedHelp()
    A:print(L["Announce or query saved instances for raids."])
    A:rawPrint(usageFormatter(L["SLASHCMD_SAVED"], L["{ p | r | g | ... }"]))
    for i, record in ipairs(saved_match_list) do
      local token = record.token
      local usage = saved_help[token].usage
      local help = saved_help[token].help
      
      A:rawPrint(optionFormatter(usage, help))
    end
  end
  
  local function matchAlternation(msg, words, record)
    if getn(words) < record.word then return end
    
    local index = record.word
    -- Only apply case-insensitive string search to words not whole message
    local str = index > 0 and strlower(words[index]) or msg
    
    local subpatterns = { strsplit("|", record.pattern) }
    
    for i, subpattern in ipairs(subpatterns) do
      -- Turn sub-pattern into end-to-end pattern
      local p = format("^%s$", subpattern)

      local t = { strfind(str, p) }
      -- Match found
      if t[1] then 
        local n = getn(t)
        
        if n < 3 then
          return record.token
        else
          -- Captures detected
          return record.token, { unpack(t, 3) }
        end
      end
    end
  end
  
  local function getWords(msg)
    return strpsplit(msg, "%s+")
  end

  function tokenFromMatchlist(msg)
    if not msg then return end
    
    msg = strtrim(msg)
    if strlen(msg) < 1 then return end
    
    local words = getWords(msg)
    
    for i, record in ipairs(saved_match_list) do
      local token, args = matchAlternation(msg, words, record)
      if token then
        return token, args
      end
    end
  end

  local tokenToFunc = {
    ["PARTY"] = announce.announceToChat,
    ["RAID"] = announce.announceToChat,
    ["GUILD"] = announce.announceToChat,
    ["OFFICER"] = announce.announceToChat,
    ["BATTLEGROUND"] = announce.announceToChat,
    ["SAY"] = announce.announceToChat,
    ["YELL"] = announce.announceToChat,
    ["TARGET"] = whisper.queryUnit,
    ["MOUSEOVER"] = whisper.queryUnit,
    ["HELP"] = showSavedHelp,
    ["CHANNEL_NUM"] = announce.announceByChannelNum,
    ["CHANNEL_NAME"] = announce.announceByChannelName,
    ["NAME"] = whisper.queryUnitName,
    ["NAME_RAID"] = whisper.queryUnitName,
  }

  function SlashCmdList.fs_saved(msg)
    if not msg or strlen(msg) < 1 then
      announce.announceSelf()
      return
    end
    
    local token, args = tokenFromMatchlist(msg)
    local func = token and tokenToFunc[token]
    
    if func and not args then
      func(token)
    elseif func and args then
      func(unpack(args))
    else
      showSavedHelp()
    end
  end
  _G.SLASH_fs_saved1 = L["SLASHCMD_SAVED"]
  _G.SLASH_fs_saved2 = L["SLASHCMD_SAVED_ALT1"]
end

function SlashCmdList.fs_options(msg)
  A.options.help = L["Configure options for showing saved raid instances."]
  cmdoptions.processCommand(msg, A.options, L["SLASHCMD_SHORT"])
  
  -- Call the GUI config menu, if available, and no specific options used
  if FonzSavedFu and (not msg or strlen(msg) < 1) then
    FonzSavedFu:OpenConfigMenu()
  end
end
_G.SLASH_fs_options1 = L["SLASHCMD_SHORT"]
_G.SLASH_fs_options2 = L["SLASHCMD_LONG"]

-- Command to conveniently toggle Raid Leader Saved chat announcement until
-- reload/next login.
function SlashCmdList.fs_rls()
  raidleadersaved.toggleQuiet(true)
end
_G.SLASH_fs_rls1 = L["SLASHCMD_RLS"]
_G.SLASH_fs_rls2 = L["SLASHCMD_RLS_ALT1"]

do
  local pending_delete_this_lockout
  
  -- Command to list instance lockouts (aka. instance limit by count).
  function SlashCmdList.fs_lockout(msg)
    if not msg or strlen(msg) < 1 then
      lockout.listLockouts()
      return
    end
    
    local options = {
      type = "group",
      help = L["Options for managing lockouts."],
      args = {
        Del = {
          type = "range",
          name = L["Delete Lockout"],
          desc = L["Delete lockout number #."],
          get = function()
            local index = pending_delete_this_lockout
            pending_delete_this_lockout = nil
            return index or "#"
          end,
          set = function(msg)
            local index = msg and tonumber(msg)
            if not index then 
              A.warn("No lockout index provided for deletion.")
              return
            end
            pending_delete_this_lockout = index
            lockout.confirmDeleteLockout(index)
          end,
          usage = L["<number: greater than 0>"],
          validate = function(msg)
            local n = msg and tonumber(msg)
            return n and n > 0
          end,
          min = 1, max = 10, step = 1,
        },
        Add = {
          type = "execute",
          name = L["Add Lockout"],
          desc = L["Resets and adds a lockout inside an instance."],
          func = lockout.addLockout,
        },
        Wipe = {
          type = "execute",
          name = L["Wipe Lockouts"],
          desc = L["Wipes all lockouts."],
          func = lockout.confirmWipeLockouts,
        },        
      },
    }
    
    cmdoptions.processCommand(msg, options, L["SLASHCMD_LOCKOUT"])
  end
end
_G.SLASH_fs_lockout1 = L["SLASHCMD_LOCKOUT"]
_G.SLASH_fs_lockout2 = L["SLASHCMD_LOCKOUT_ALT1"]
_G.SLASH_fs_lockout3 = L["SLASHCMD_LOCKOUT_ALT2"]
_G.SLASH_fs_lockout4 = L["SLASHCMD_LOCKOUT_ALT3"]
_G.SLASH_fs_lockout5 = L["SLASHCMD_LOCKOUT_ALT4"]

-- Convenience command to add a lockout
function SlashCmdList.fs_lockout_add()
  lockout.addLockout()
end
_G.SLASH_fs_lockout_add1 = L["SLASHCMD_LOCKOUT_ADD"]

-- EVENTS --

local frame = CreateFrame("Frame")
A.event_frame = frame

-- Fires when an addon and its saved variables are loaded
frame:RegisterEvent("ADDON_LOADED")

frame:SetScript("OnEvent", function()
  if arg1 ~= A.name then return end
  
  A.is_loaded = true
  A.loaded_name = A.name
  
  A.player = { 
    name = UnitName("player"),
    class = UnitClass("player"),
    faction = UnitFactionGroup("player"),
  }
  
  A.setCharConfigDefaults()
  A.setRealmDefaults()
  A.setProfileDefaults()
  
  -- Note that user language setting occurs after defaults are collected.
  -- Therefore, avoid using locale-sensitive strings in defaults.
  setLang()
end)

-- MODULE OPTIONS --

if not A.options then
  A.options = {
    type = "group",
    args = {},
  }
end

do
  local locale_codes = {
    [strlower("enUS")] = "enUS",
    [strlower("deDE")] = "deDE",
    [strlower("esES")] = "esES",
    [strlower("esMX")] = "esMX",
    [strlower("frFR")] = "frFR",
    [strlower("koKR")] = "koKR",
    [strlower("ruRU")] = "ruRU",
    [strlower("zhCN")] = "zhCN",
    [strlower("zhTW")] = "zhTW",
    ["en"] = "enUS",
    ["de"] = "deDE",
    ["es"] = "esES",
    ["mx"] = "esMX",
    ["fr"] = "frFR",
    ["kr"] = "koKR",
    ["ru"] = "ruRU",
    ["cn"] = "zhCN",
    ["tw"] = "zhTW",
  }
  
  function M.setLang(lang)
    local db = A.getCharConfig(module_name)
    A.locale_info.code = lang or db.lang or A.locale_info.code
  end

  A.options.args["lang"] = {
    type = "choice",
    name = L["Language"],
    desc = L["Set the language of text."],
    get = function() 
      local db = A.getProfileRealm(module_name)
      return db.lang
    end,
    set = function(msg)
      local db = A.getProfileRealm(module_name)
      db.lang = msg and locale_codes[strlower(msg)]
      A.locale_info.code = db.lang or A.locale_info.code
      
      -- Set GUI's lang code, if available
      if FonzSavedFu then 
        FonzSavedFu.locale_info.code = db.lang or FonzSavedFu.locale_info.code
        --[[
        FonzSavedFu:UpdateFuBarPlugin()
        --]]
      end
    end,
    usage = "{ enUS | deDE | esES | esMX | frFR | koKR | ruRU | zhCN | zhTW }",
    validate = function(msg)
      return msg and locale_codes[strlower(msg)]
    end,
    choices = {
      ["enUS"] = "English",
      ["deDE"] = "Deutsch",
      ["esES"] = "Español ",
      ["esMX"] = "Español de México",
      ["frFR"] = "Français",
      ["koKR"] = "한국어",
      ["ruRU"] = "Русский",
      ["zhCN"] = "简体中文",
      ["zhTW"] = "繁體中文",
    },
    choiceType = "dict",
    choiceOrder = { 
      "enUS", "deDE", "esES", "esMX", "frFR", "koKR", "ruRU", "zhCN", "zhTW" 
    },
  }
end

do
  local datetime_formats = {
    "ISO", 
    "FR", "DE", "GB", "US_CIV", "US_MIL", "CN",
    "D-M-Y", "D.M.Y", "D/M/Y",
    "Y-M-D", "Y.M.D", "Y/M/D",
    "M-D-Y", "M/D/Y"
  }
  
  A.options.args["datetime"] = {
    type = "choice",
    name = L["Date Time"],
    desc = L["Set the date time format."],
    get = function() 
      local db = A.getProfileRealm(module_name)
      return db.datetime_format
    end,
    set = function(msg)
      if not msg then return end
      msg = strupper(msg)
      local db = A.getProfileRealm(module_name)
      db.datetime_format = util.datetime_formats[msg] and msg
    end,
    usage = format("{ %s }", tconcat(datetime_formats, " | ")),
    validate = function(msg)
      return msg and util.datetime_formats[strupper(msg)]
    end,
    choices = {
      ["ISO"] =L["International"], 
      ["FR"] =L["France"],
      ["DE"] =L["Germany"], 
      ["GB"] =L["UK"], 
      ["US_CIV"] =L["US Civilian"], 
      ["US_MIL"] =L["US Military"], 
      ["CN"] =L["China"],
      ["D-M-Y"] =L["Day-Month-Year"], 
      ["D.M.Y"] =L["Day.Month.Year"], 
      ["D/M/Y"] =L["Day/Month/Year"],
      ["Y-M-D"] =L["Year-Month-Day"], 
      ["Y.M.D"] =L["Year.Month.Day"], 
      ["Y/M/D"] =L["Year/Month/Day"],
      ["M-D-Y"] =L["Month-Day-Year"], 
      ["M/D/Y"] =L["Month/Day/Year"],
    },
    choiceType = "dict",
    choiceOrder = datetime_formats,
  }
end