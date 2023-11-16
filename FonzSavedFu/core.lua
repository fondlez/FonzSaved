local A = FonzSavedFu
local L = A.locale

-- Dependencies
-- * libraries
local LibTablet
-- * modules
local palette = A.require 'palette'
local util = A.requires(
  'util.table',
  'util.string',
  'util.time'
)

local format = string.format

-- Fubar options
A:SetFuBarOption("tooltipType", "Tablet-2.0")
A:SetFuBarOption("iconPath", A.path([[\img\icon]]))
A:SetFuBarOption("showIcon", true)
A:SetFuBarOption("defaultPosition", "MINIMAP")
A:SetFuBarOption("defaultMinimapPosition", 260)
A:SetFuBarOption("cannotDetachTooltip", true)
A:SetFuBarOption("cannotHideText", false)
A:SetFuBarOption("hasNoColor", true)
A:SetFuBarOption("clickableTooltip", true)
A:SetFuBarOption("hideWithoutStandby", true)

-- Saved variable defaults
A:SetDatabaseDefaults('profile', {
  fubar_text_hide_zero = false,
  fubar_text_short_text = false,
  gui_hide_errors = false,
})

-- Dependency on another addon (FonzSaved) means must not use OnInitialize().
-- This is because within LibRock addon loading, there is no guarantee when
-- addon dependencies are available - this can cause upvalue nil errors.
-- Use OnEnable() instead, which only runs after login is complete.
function A:OnEnable()
  self:syncLocale()
  self:createUnicodeFonts()
  
  local profile = self.db.profile
  local fubar_options = {
    FubarHideZero = {
      type = "toggle",
      name = L["Hide Fubar text for zero saved instances"],
      desc = 
        L["Hide the Fubar text when characters have zero saved instances."],
      order = 40,
      get = function()
        return profile.fubar_text_hide_zero
      end,
      set = function()
        profile.fubar_text_hide_zero = not profile.fubar_text_hide_zero
        self:UpdateFuBarText()
        return profile.fubar_text_hide_zero
      end,
    },
    FubarShortText = {
      type = "toggle",
      name = L["Short Fubar text"],
      desc = L["Only show the number of saved instances in the Fubar text."],
      order = 30,
      get = function()
        return profile.fubar_text_short_text
      end,
      set = function()
        profile.fubar_text_short_text = not profile.fubar_text_short_text
        self:UpdateFuBarText()
        return profile.fubar_text_short_text
      end,      
    },
  }
 
  local self_options = FonzSaved.options.args["self"]
  self_options.order = 150
  local chat_options = FonzSaved.options.args["chat"]
  chat_options.order = 200
  local query_options = FonzSaved.options.args["query"]
  query_options.order = 300
  local rls_options = FonzSaved.options.args["rls"]
  rls_options.order = 400
  local lockout_options = FonzSaved.options.args["lockout"]
  lockout_options.order = 450
  local lang_option = FonzSaved.options.args["lang"]
  lang_option.order = 110
  local datetime_option = FonzSaved.options.args["datetime"]
  datetime_option.order = 120
  -- Font paths added after login due to other addons changing default fonts,
  -- e.g. UnicodeFont
  local chat_font_path = ChatFontNormal:GetFont()
  lang_option["choiceFonts"] = {
    ["enUS"] = chat_font_path,
    ["deDE"] = chat_font_path,
    ["esES"] = chat_font_path,
    ["esMX"] = chat_font_path,
    ["frFR"] = chat_font_path,
    ["koKR"] = chat_font_path,
    ["ruRU"] = chat_font_path,
    ["zhCN"] = chat_font_path,
    ["zhTW"] = chat_font_path,
  }
  
  -- Hide non-Roman locales on Roman clients without UNICODEFONT
  self:hideNonRomanLocale(lang_option)
  
  local options = {
    name = A.title,
    desc = self.notes,
    handler = A,
    type = "group",
    args = {
      self = self_options,
      chat = chat_options,
      query = query_options,
      rls = rls_options,
      lockout = lockout_options,
      lang = lang_option,
      datetime = datetime_option,
      gui = {
        name = L["Interface"],
        desc = L["Graphical options"],
        type = "group",
        order = 1000,
        args = {
          HideErrors = {
            type = "toggle",
            name = L["Hide Errors"],
            desc = L["Hide errors in chat for graphical options."],
            get = function()
              return profile.gui_hide_errors
            end,
            set = function()
              profile.gui_hide_errors = not profile.gui_hide_errors
              return profile.gui_hide_errors
            end,   
          },
        },
      },
    },
  }
  
  if FuBar then
    for name, option in pairs(fubar_options) do
      options.args[name] = option
    end
  end
  
  A:SetConfigTable(options)
  A:SetConfigSlashCommand(L["SLASHCMD_LONG"], L["SLASHCMD_SHORT"])
  A.OnMenuRequest = options
end
  
do
  local strlower = strlower
  
  local color_keypress = palette.c(palette.hexRgb("#eda55f"))
  local class_colors = palette.color.classes
  local formatDurationFull = util.formatDurationFull
  local localeDateTime = util.localeDateTime
  local isoTime = util.isoTime
  local sortedPairs = util.sortedPairs
  local sortRecords = util.sortRecords1
  
  local DURATION_MAX_RESET = {
    instances = 24*60*60, --24 hours
    raids = 7*24*60*60, --7 days
  }
  local DURATION_NEAR_RESET = 24*60*60 --24 hours
  
  local function formatDuration(duration, lang)
    -- Options: color + hide seconds
    return formatDurationFull(duration, false, true, lang)
  end
  
  local function formatDateTime(timestamp)
    local db = FonzSaved.getProfileRealm("slashcmd")
    -- Options: 
    -- * is epoch, i.e. it comes from Lua time()
    -- * hide seconds
    return localeDateTime(timestamp, true, true, nil, db.datetime_format)
  end
  
  local function formatTime(timestamp)
    -- Options: 
    -- * is epoch, i.e. it comes from Lua time()
    -- * hide seconds
    return isoTime(timestamp, true, true)
  end
  
  local styles = {
    ["class"] = function(name, class)
      return class_colors[strlower(class)](name)
    end,
    ["heading"] = function(heading)
      return palette.color.white_text(heading)
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
    ["id"] = function(id)
      return palette.color.gray_text(id)
    end,
    ["raid"] = function(name)
      return palette.color.gold_text(name)
    end,
    ["instance"] = function(name)
      return palette.color.white_text(name)
    end,
    ["duration"] = function(duration)
      local locale_code = A.locale_info.code
      return duration <= DURATION_NEAR_RESET
        and palette.color.red_text(formatDuration(duration, 
          locale_code))
        or palette.color.green_text(formatDuration(duration, 
          locale_code))
    end,
    ["raidreset"] = function(timestamp)
      return palette.color.gold_text(formatDateTime(timestamp))
    end,
    ["instancereset"] = function(timestamp)
      return palette.color.lightyellow_text(formatDateTime(timestamp))
    end,
    ["count"] = function(count)
      return palette.color.white_text(tostring(count))
    end,
    ["entry"] = function(timestamp)
      return palette.color.white_text(formatTime(timestamp))
    end,
    ["status"] = function(saved, added)
      return saved and palette.color.gold_text(L["saved"])
        or added and palette.color.blue2(L["added"])
        or palette.color.gray_text(L["entered"])
    end,
    ["difftype"] = function(difficulty, instance_type)
      local INSTANCE_DIFFICULTY 
        = FonzSaved.require("lockout").INSTANCE_DIFFICULTY
      return instance_type =="raid" 
          and palette.color.white_text(L["raid"])
        or difficulty == INSTANCE_DIFFICULTY.heroic 
          and palette.color.white_text(L["heroic"])
        or palette.color.gray_text(L["normal"])
    end,
    ["ago"] = function(duration)
      local locale_code = A.locale_info.code
      return palette.color.white_text(formatDuration(duration, 
        locale_code))
    end,
    ["bracket"] = function(text, color)
      color = color or palette.color.white_text
      return format("%s%s%s", color("["), text or '', color("]"))
    end,
  }
  
  local function formatTitle(category, name, class)
    local locale_font = A:getLocaleFont("GameTooltipText")
    category:AddLine(
      "text", styles["class"](name, class),
      "font", locale_font
    )
  end
  
  local function formatTableHeader(category)
    local locale_font = A:getLocaleFont("GameTooltipText")
    category:AddLine(
      "text", styles["heading"](L["Instance ID"]),
      "font", locale_font,
      "justify", "LEFT",
      "text2", styles["heading"](L["Instance"]),
      "font2", locale_font,
      "justify2", "CENTER",
      "text3", styles["heading"](L["Remaining"]),
      "font3", locale_font,      
      "justify3", "CENTER",
      "text4", styles["heading"](L["Reset"]),
      "font4", locale_font,
      "justify4", "RIGHT"
    )
  end
  
  local function formatRaid(category, raid)
    local time_left = tonumber(raid.reset) - time()    
    if time_left <= 0 then return end
    
    local findRaidNameById = 
      FonzSaved.require("savedinstances").findRaidNameById
    local locale_font = A:getLocaleFont("GameTooltipText")
    category:AddLine(
      "text", styles["id"](raid.id),
      "font", locale_font,
      "text2", styles["raid"](findRaidNameById(raid.raid_id)),
      "font2", locale_font,
      "text3", styles["duration"](time_left),
      "font3", locale_font,
      "justify3", "RIGHT",
      "text4", styles["raidreset"](raid.reset),
      "font4", locale_font,
      "justify4", "RIGHT"
    )
  end
  
  local function formatInstance(category, instance)
    local time_left = tonumber(instance.reset) - time()
    if time_left <= 0 then return end
    
    local locale_font = A:getLocaleFont("GameTooltipText")
    category:AddLine(
      "text", styles["id"](instance.id),
      "font", locale_font,
      "text2", styles["instance"](instance.name),
      "font2", locale_font,
      "text3", styles["duration"](time_left),
      "font3", locale_font,
      "justify3", "RIGHT",
      "text4", styles["instancereset"](instance.reset),
      "font4", locale_font,
      "justify4", "RIGHT"
    )
  end
  
  local function formatRaidTable(category, raid_info)
    local n = raid_info and raid_info.n or 0
    if n < 1 then return end
    
    local raids = raid_info.raids
    -- Sort raid entries by raid_id in descending order
    sortRecords(raids, "raid_id", true)
    
    for i, raid in ipairs(raids) do
      if tonumber(raid.reset) > time() then
        formatRaid(category, raid)
      end
    end
  end
  
  local function formatInstanceTable(category, instance_info)
    local n = instance_info and instance_info.n or 0
    if n < 1 then return end
    
    local instances = instance_info.instances
    local found_all_ids = true
    for i, instance in ipairs(instances) do
      if not instance.heroic_id then
        found_all_ids = false
        break
      end
    end
    
    -- Sort instance entries by id in descending order, if available
    if found_all_ids then
      sortRecords(instances, "heroic_id", true)
    else
      -- Sort by name in ascending order
      sortRecords(instances, "name")
    end
    
    for i, instance in ipairs(instances) do
      if tonumber(instance.reset) > time() then
        formatInstance(category, instance)
      end
    end
  end
  
  local function formatCharacter(category, saved, char_name)
    local char_class = saved and saved.player.class
    local raid_info = saved and saved.raid_info
    local instance_info = saved and saved.instance_info
    
    formatTitle(category, char_name, char_class)
    formatTableHeader(category)
    formatRaidTable(category, raid_info)
    formatInstanceTable(category, instance_info)
  end
  
  local function maxResetExpired(saved_type, query_time)
    if not query_time then return false end
    return time() - tonumber(query_time) > DURATION_MAX_RESET[saved_type]
  end
  
  local function getTotalCountFromSaved(saved)
    local raid_info = saved and saved.raid_info
    local instance_info = saved and saved.instance_info
    local query_time = saved and saved.query_time
    
    local num_raids = raid_info and tonumber(raid_info.n) or 0
    local num_instances = instance_info and tonumber(instance_info.n) or 0
    
    -- Check saved instance info is not guaranteed stale
    if maxResetExpired("raids", query_time) then
      num_raids = 0
    end
    if maxResetExpired("instances", query_time) then 
      num_instances = 0
    end
    if num_raids + num_instances == 0 then
      return 0
    end
    
    -- Check for staleness of saved individually
    if num_raids > 0 then
      for i, raid in ipairs(raid_info.raids) do
        if tonumber(raid.reset) <= time() and num_raids > 0 then
          num_raids = num_raids - 1
          if num_raids == 0 then break end
        end
      end
    end
    if num_instances > 0 then
      for i, instance in ipairs(instance_info.instances) do
        if tonumber(instance.reset) <= time() and num_instances > 0 then
          num_instances = num_instances - 1
          if num_instances == 0 then break end
        end
      end
    end
    
    return num_raids + num_instances
  end
  
  do
    local function formatTableHeader(category)
      local locale_font = A:getLocaleFont("GameTooltipText")
      category:AddLine(
        "text", styles["heading"](""),
        "font", locale_font,
        "justify", "LEFT",
        "text2", styles["1h"](L["[Past hour]"]),
        "font2", locale_font,
        "justify2", "CENTER",
        "text3", styles["heading"](""),
        "font3", locale_font,      
        "justify3", "CENTER",
        "text4", styles["24h"](L["[Past 24 hours]"]),
        "font4", locale_font,
        "justify4", "CENTER",
        "text5", styles["heading"](""),
        "font5", locale_font,
        "justify5", "CENTER",
        "text6", styles["older"](L["[Older]"]),
        "font6", locale_font,
        "justify6", "CENTER",
        "text7", styles["heading"](""),
        "font7", locale_font,
        "justify7", "CENTER"
      )
      category:AddLine(
        "text", styles["heading"](L["#"]),
        "font", locale_font,
        "justify", "LEFT",
        "text2", styles["heading"](L["Entry"]),
        "font2", locale_font,
        "justify2", "CENTER",
        "text3", styles["heading"](L["Char"]),
        "font3", locale_font,      
        "justify3", "CENTER",
        "text4", styles["heading"](L["Status"]),
        "font4", locale_font,
        "justify4", "CENTER",
        "text5", styles["heading"](L["Instance"]),
        "font5", locale_font,
        "justify5", "CENTER",
        "text6", styles["heading"](L["Type"]),
        "font6", locale_font,
        "justify6", "CENTER",
        "text7", styles["heading"](L["Ago"]),
        "font7", locale_font,
        "justify7", "RIGHT"
      )
    end
    
    local function formatLockoutEntry(entry, time_ago)
      if time_ago < 60*60 then
        return styles["bracket"](styles["1h"](formatDateTime(entry)))
      elseif time_ago < 24*60*60 then
        return styles["bracket"](styles["24h"](formatDateTime(entry)))
      else
        return styles["bracket"](styles["older"](formatDateTime(entry)))
      end
    end
  
    local function formatLockout(category, lockout, count)
      local locale_font = A:getLocaleFont("GameTooltipText")
      local time_ago = time() - tonumber(lockout.entry)
      local findInstanceName = FonzSaved.require("lockout").findInstanceName
      local instance_name = findInstanceName(lockout.zone) or lockout.zone
      category:AddLine(
        "text", styles["count"](count),
        "font", locale_font,
        "justify", "LEFT",
        "text2", formatLockoutEntry(lockout.entry, time_ago),
        "font2", locale_font,
        "justify2", "LEFT",
        "text3", styles["class"](lockout.name, lockout.class),
        "font3", locale_font,      
        "justify3", "CENTER",
        "text4", styles["status"](lockout.saved, lockout.added),
        "font4", locale_font,
        "justify4", "CENTER",
        "text5", styles["instance"](instance_name),
        "font5", locale_font,
        "justify5", "CENTER",
        "text6", styles["difftype"](lockout.difficulty, lockout.type),
        "font6", locale_font,
        "justify6", "CENTER",
        "text7", styles["ago"](time_ago),
        "font7", locale_font,
        "justify7", "RIGHT"        
      )
    end
    
    function displayLockouts()      
      local lockouts = FonzSaved.require("lockout").getLockouts()
      local n = lockouts and getn(lockouts) or 0
      
      LibTablet:SetTitle(format("%s - %s", A.name, L["Instances"]))
      LibTablet:SetHint(format(L["Release %s button to view saved instances."], 
        color_keypress(L["Shift"])))
      
      if n < 1 then
        local locale_font = A:getLocaleFont("GameTooltipText")
        local cat1 = LibTablet:AddCategory("columns", 1)
        cat1:AddLine(
          "text", L["No instance lockouts."],
          "font", locale_font
        )
        return
      end
      
      local category = LibTablet:AddCategory("columns", 7)
      formatTableHeader(category)
      for i=n,1,-1 do
        local lockout = lockouts[i]
        formatLockout(category, lockout, i)
      end
    end
  end

  function A:OnUpdateFuBarTooltip()
    LibTablet = LibTablet or Rock("Tablet-2.0")
    
    self:syncLocale()
    
    if IsShiftKeyDown() then
      displayLockouts()
      return
    end
    
    LibTablet:SetTitle(format("%s - %s", A.name, "Saved"))
    LibTablet:SetHint(format(L["Hold %s button to view instance lockouts."],
      color_keypress(L["Shift"])))
    
    local chars = FonzSaved.getProfileRealmChars()
    
    -- An empty Tablet + Dewdrop results in a tooltip with just the addon name
    local category = LibTablet:AddCategory("columns", 4)
    
    -- Self --
    
    local self_name = FonzSaved.player.name
    local self_saved = chars[self_name]["savedinstances"]
    local self_saved_total = getTotalCountFromSaved(self_saved)
    
    if self_saved_total > 0 then
      formatCharacter(category, self_saved, self_name)
    end
    
    -- Others --
    
    -- Check total saved instance count across all characters that are not self
    local other_saved_total = 0
    local other_saveds = {}
    local other_counts = {}
    for char_name, char_profile in pairs(chars) do
      -- Not self
      if char_name ~= self_name then
        local saved = char_profile["savedinstances"]
        other_saveds[char_name] = saved
        
        local char_count = getTotalCountFromSaved(saved)
        other_counts[char_name] = char_count
        other_saved_total = other_saved_total + char_count
      end
    end
    
    if other_saved_total > 0 then
      for other_name, other_saved in sortedPairs(other_saveds) do
        if other_counts[other_name] > 0 then
          formatCharacter(category, other_saved, other_name)
        end
      end
    end
    
    -- None --
    
    if self_saved_total + other_saved_total == 0 then
      local locale_font = A:getLocaleFont("GameTooltipText")
      local cat1 = LibTablet:AddCategory("columns", 1)
      cat1:AddLine(
        "text", L["No saved instances."],
        "font", locale_font
      )
    end
  end
end

do  
  local num_saved_formats = {
    zero = "",
    single = L["%d Saved Instance"],
    plural = L["%d Saved Instances"], 
    short = "%d",
  }
  
  function A:OnUpdateFuBarText()
    self:syncLocale()
    
    local player_name = FonzSaved.player.name
    local chars = FonzSaved.getProfileRealmChars()
    local saved = chars[player_name]["savedinstances"]
    local raid_info = saved and saved.raid_info
    local instance_info = saved and saved.instance_info
    local num_raids = raid_info and tonumber(raid_info.n) or 0
    local num_instances = instance_info and tonumber(instance_info.n) or 0
    local num_total = num_raids + num_instances
    
    local profile = self.db.profile

    if num_total == 0 and profile.fubar_text_hide_zero then
      self:SetFuBarText(format(num_saved_formats.zero, num_total))
    else
      if not profile.fubar_text_short_text then
        local text_format = num_total == 1 and num_saved_formats.single
          or num_saved_formats.plural
        self:SetFuBarText(format(text_format, num_total))
      else
        self:SetFuBarText(format(num_saved_formats.short, num_total))
      end
    end
  end
end

do
  local GetLocale = GetLocale
  
  local keys = util.keys
  
  local roman = {
    ["enUS"] = "English",
    ["deDE"] = "Deutsch",
    ["esES"] = "Español ",
    ["esMX"] = "Español de México",
    ["frFR"] = "Français",
  }
  
  local existing_fonts = {
    ["GameTooltipText"] = true,
  }
  
  local unicode_fonts = {}
  
  function A:hideNonRomanLocale(option)
    -- If client locale is non-Roman then nothing to be done.
    if not roman[GetLocale()] then return end
    -- UNICODEFONT path is from the UnicodeFont (or UnicodeFont-tbc) addon.
    -- If present, then no need to hide non-Roman local choices.
    if UNICODEFONT then return end
    
    -- Delete non-Roman choices
    local t = keys(option.choices)
    for i, code in ipairs(t) do
      if not roman[code] then
        option.choices[code] = nil
      end
    end
    
    -- Find Roman choices in option order list
    local o = {}
    for i, code in ipairs(option.choiceOrder) do
      if roman[code] then tinsert(o, code) end
    end
    
    -- Assign new Roman-only option order list
    option.choiceOrder = o
  end
  
  function A:getLocaleFont(name)
    -- When client locale is Roman, but selected locale is not, then there
    -- is no default font support for the selected language.
    -- So, get a modified version of original font with Unicode support.
    if roman[GetLocale()] and not roman[A.locale_info.code] then
      if UNICODEFONT then
        if not unicode_fonts[name] then
          self:createUnicodeFonts()
        end
        return unicode_fonts[name]
      else
        local profile = self.db.profile
        if not profile.gui_hide_errors then
          A.error(
            "Non-Roman language selected on Roman language client."  
            .. " Install a font that supports this language,"
            .. " e.g. with the addon https://github.com/fondlez/UnicodeFont"
          )
        end
        return _G[name]
      end
    else
      return _G[name] 
    end
  end
  
  local function mangle(name)
    return format("%s_%s", name, A.name)
  end
  
  function A:createUnicodeFonts()
    -- UNICODEFONT path is from the UnicodeFont (or UnicodeFont-tbc) addon.
    if not UNICODEFONT then return end
    
    for font_name, v in pairs(existing_fonts) do
      if not unicode_fonts[font_name] then
        local font = CreateFont(mangle(font_name))
        font:CopyFontObject(font_name)
        
        -- Get properties of the original font
        local _, fontHeight, flags = font:GetFont()
        
        font:SetFont(UNICODEFONT, fontHeight, flags)
        
        unicode_fonts[font_name] = font
      end
    end
  end
end
  
function A:syncLocale()
  -- Synchronize locale with FonzSaved
  self.locale_info.code = FonzSaved.locale_info.code
  local locale_code = self.locale_info.code
end