local A = FonzSaved

A.module 'palette'

local format = string.format

function M.c(r, g, b, a, multiplier)
  a = tonumber(a) or 1
  multiplier = tonumber(multiplier) or 1
  
  local mt = {
    __metatable = false,
    __newindex = pass,
    color = { 
      tonumber(r) * multiplier, 
      tonumber(g) * multiplier, 
      tonumber(b) * multiplier, 
      tonumber(a)
    },
  }
  
  function mt:__call(text)
		local r, g, b, a = unpack(mt.color)
		if text then
			return format("|c%02X%02X%02X%02X", a, r, g, b) 
        .. tostring(text) .. FONT_COLOR_CODE_CLOSE
		else
			return r/255, g/255, b/255, a
		end
  end
  
  function mt:__concat(text)
		local r, g, b, a = unpack(mt.color)
		return format("|c%02X%02X%02X%02X", a, r, g, b) .. tostring(text)
  end
  
  return setmetatable({}, mt)
end

--[[
  Globals from FrameXML/Fonts.xml:
  
  NORMAL_FONT_COLOR_CODE = "|cffffd200";
  HIGHLIGHT_FONT_COLOR_CODE = "|cffffffff";
  RED_FONT_COLOR_CODE = "|cffff2020";
  GREEN_FONT_COLOR_CODE = "|cff20ff20";
  GRAY_FONT_COLOR_CODE = "|cff808080";
  LIGHTYELLOW_FONT_COLOR_CODE = "|cffffff9a";
  FONT_COLOR_CODE_CLOSE = "|r";
  NORMAL_FONT_COLOR = {r=1.0, g=0.82, b=0};
  HIGHLIGHT_FONT_COLOR = {r=1.0, g=1.0, b=1.0};
  GRAY_FONT_COLOR = {r=0.5, g=0.5, b=0.5};
  GREEN_FONT_COLOR = {r=0.1, g=1.0, b=0.1};
  RED_FONT_COLOR = {r=1.0, g=0.1, b=0.1};
  PASSIVE_SPELL_FONT_COLOR = {r=0.77, g=0.64, b=0};
  MATERIAL_TEXT_COLOR_TABLE = {
    ["Default"] = {0.18, 0.12, 0.06},
    ["Stone"] = {1.0, 1.0, 1.0},
    ["Parchment"] = {0.18, 0.12, 0.06},
    ["Marble"] = {0, 0, 0},
    ["Silver"] = {0.12, 0.12, 0.12},
    ["Bronze"] = {0.18, 0.12, 0.06}
  };
  MATERIAL_TITLETEXT_COLOR_TABLE = {
    ["Default"] = {0, 0, 0},
    ["Stone"] = {0.93, 0.82, 0},
    ["Parchment"] = {0, 0, 0},
    ["Marble"] = {0.93, 0.82, 0},
    ["Silver"] = {0.93, 0.82, 0},
    ["Bronze"] = {0.93, 0.82, 0}
  };
  RAID_CLASS_COLORS = {
    ["HUNTER"] = { r = 0.67, g = 0.83, b = 0.45 },
    ["WARLOCK"] = { r = 0.58, g = 0.51, b = 0.79 },
    ["PRIEST"] = { r = 1.0, g = 1.0, b = 1.0 },
    ["PALADIN"] = { r = 0.96, g = 0.55, b = 0.73 },
    ["MAGE"] = { r = 0.41, g = 0.8, b = 0.94 },
    ["ROGUE"] = { r = 1.0, g = 0.96, b = 0.41 },
    ["DRUID"] = { r = 1.0, g = 0.49, b = 0.04 },
    ["SHAMAN"] = { r = 0.14, g = 0.35, b = 1.0 },
    ["WARRIOR"] = { r = 0.78, g = 0.61, b = 0.43 }
  };
--]]

function M.rgb(t, multiplier)
  multiplier = multiplier or 255
  return t.r, t.g, t.b, t.a, multiplier
end

do
  local find = string.find
  
  function M.hexRgb(str)
    -- Blizzard color code
    do
      local s, _, a, r, g, b = find(str, "|c(%x%x)(%x%x)(%x%x)(%x%x)")
      if s then
        return
          tonumber(r, 16), 
          tonumber(g, 16),
          tonumber(b, 16),
          tonumber(a, 16)
      end
    end
    -- HTML color code
    do
      local s, _, r, g, b = find(str, "#(%x%x)(%x%x)(%x%x)")
      if s then
        return
          tonumber(r, 16), 
          tonumber(g, 16),
          tonumber(b, 16)
      end
    end
  end
end

M.color = {
  transparent = c(0, 0, 0, 0),
  original = c(255, 255, 255),
  
  black = c(0, 0, 0),
  white = c(255, 255, 255),
	red = c(255, 0, 0),
	green = c(0, 255, 0),
	blue = c(0, 0, 255),
  blue1 = c(102, 178, 255),
  blue2 = c(153, 204, 255),
  
  black_trans10 = c(0, 0, 0, 0.1),
  black_trans50 = c(0, 0, 0, 0.5),
  brown = c(179, 38, 13),
	gold = c(255, 255, 154),
	gray = c(187, 187, 187),
  grey = c(187, 187, 187),
  nero1 = c(24, 24, 24),
  nero2 = c(30, 30, 30),
  nero3 = c(42, 42, 42),
  orange = c(255, 146, 24),
	yellow = c(255, 255, 13),
  rose_bud = c(hexRgb("#FF9A9A")),
  
  gold_text = c(hexRgb(NORMAL_FONT_COLOR_CODE)),
  white_text = c(hexRgb(HIGHLIGHT_FONT_COLOR_CODE)),
  red_text = c(hexRgb(RED_FONT_COLOR_CODE)),
  green_text = c(hexRgb(GREEN_FONT_COLOR_CODE)),
  gray_text = c(hexRgb(GRAY_FONT_COLOR_CODE)),
  lightyellow_text = c(hexRgb(LIGHTYELLOW_FONT_COLOR_CODE)),
}

color.classes = {
  hunter = c(rgb(RAID_CLASS_COLORS.HUNTER)),
  warlock = c(rgb(RAID_CLASS_COLORS.WARLOCK)),
  priest = c(rgb(RAID_CLASS_COLORS.PRIEST)),
  paladin = c(rgb(RAID_CLASS_COLORS.PALADIN)),
  mage = c(rgb(RAID_CLASS_COLORS.MAGE)),
  rogue = c(rgb(RAID_CLASS_COLORS.ROGUE)),
  druid = c(rgb(RAID_CLASS_COLORS.DRUID)),
  shaman = c(rgb(RAID_CLASS_COLORS.SHAMAN)),
  vanilla_shaman = c(rgb(RAID_CLASS_COLORS.PALADIN)),
  warrior = c(rgb(RAID_CLASS_COLORS.WARRIOR)),
}
