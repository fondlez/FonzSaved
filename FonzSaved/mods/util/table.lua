local A = FonzSaved

A.module 'util.table'

local find, strlower = string.find, strlower
local sort = table.sort

function M.wipe(t)
  local mt = getmetatable(t) or {}
  if not mt.__mode or mt.__mode ~= "kv" then
    mt.__mode = "kv"
    t = setmetatable(t, mt)
  end
  for k in pairs(t) do
    t[k] = nil
  end
  return t
end

function M.unpack(t, start, stop)    
  start = start or 1
  stop = stop or getn(t)
  
  if type(start) ~= "number" then return end
  if type(stop) ~= "number" then return end
  
  if start == stop then
    return t[start]
  else
    return t[start], unpack(t, start + 1, stop)
  end
end

function M.select(index, ...)
  local arg = {...}
  if index == "#" then return getn(arg) end
  return unpack(arg, index)
end

function M.insertUnique(t, value)
  if not value then return end
  
  local found = false
  for i,v in ipairs(t) do
    if v == value then
      found = true
      break
    end
  end
  if not found then
    tinsert(t, value)
  end
  return t
end
  
function M.keys(t)
  if not t then return end
  local result = {}
  for k,v in pairs(t) do
    result[getn(result) + 1] = k
  end
  return result
end

function M.keyslower(t)
  local l = {}
  for k, v in pairs(t) do
    if type(k) == "string" then
      l[strlower(k)] = v
    end
  end
  return l
end

function M.keySearch(t, substring, comparator, case_sensitive)
  local compare = comparator or find
  local result = {}
  local found = false
  for k in pairs(t) do
    local key = k
    if not case_sensitive then
      key = strlower(k)
      substring = strlower(substring)
    end
    if compare(key, substring) then
      result[k] = result[k] and result[k] + 1 or 1
      found = true
    end
  end
  return found, result
end

function M.valueSearch(t, substring, comparator, case_sensitive)
  local compare = comparator or find
  local result = {}
  local found = false
  for k, v in pairs(t) do
    local strv = tostring(v)
    local value = strv
    if not case_sensitive then
      value = strlower(v)
      substring = strlower(substring)
    end
    if compare(value, substring) then
      -- Special treatment of numbers due to overlap of indexing with lists.
      -- Must convert numbers to strings for keys.
      local key = type(v) == "number" and strv or v
      result[key] = result[key] and (result[key] + 1) or 1
      found = true
    end
  end
  return found, result
end

function M.uniqueKeySearch(t, substring, comparator, case_sensitive)
  local compare = comparator or find
  local result
  local count = 0
  for k in pairs(t) do
    local key = k
    if not case_sensitive then
      key = strlower(k)
      substring = strlower(substring)
    end
    if compare(key, substring) then
      result = k
      count = count + 1
    end
  end
  if result and count == 1 then return result end
end

function M.keyByValue(t, value, exact, comparator, case_sensitive)
  local compare = comparator or find
  for k, v in pairs(t) do
    if exact then
      if v == value then
        return k
      end
    else
      local strv = tostring(v)
      if not case_sensitive then
        strv = strlower(v)
        value = strlower(value)
      end
      if compare(strv, value) then
        return k
      end
    end
  end
end

function M.sortedKeys(t, cmp)
  if not t then return end
  local result = keys(t)
  sort(result, cmp)
  return result
end

function M.sortedPairs(t, cmp)
  if not t then return end
  local result = keys(t)
  sort(result, cmp)
  local i = 0
  local iterator = function()
    i = i + 1
    local key = result[i]        
    return key, key and t[key]
  end
  return iterator
end

function M.sortRecords1(records, field1, reverse1)
  if not records or type(records) ~= "table" then return end
  if getn(records) < 2 then return records end
  if not field1 then return end
  
  sort(records, function(a, b)
    if not reverse1 then
      return a[field1] < b[field1]
    else
      return a[field1] > b[field1]
    end
  end)
  
  return records
end

function M.sortRecords2(records, field1, reverse1, field2, reverse2)
  if not records or type(records) ~= "table" then return end
  if getn(records) < 2 then return records end
  if not field1 then return end
  
  sort(records, function(a, b)
    if a[field1] ~= b[field1] then
      if not reverse1 then
        return a[field1] < b[field1]
      else
        return a[field1] > b[field1]
      end
    end
    if field2 and a[field2] ~= b[field2] then
      if not reverse2 then
        return a[field2] < b[field2]
      else
        return a[field2] > b[field2]
      end
    end
  end)
  
  return records
end

function M.sortRecords3(records, field1, reverse1, field2, reverse2, 
    field3, reverse3)
  if not records or type(records) ~= "table" then return end
  if getn(records) < 2 then return records end
  if not field1 then return end
  
  sort(records, function(a, b)
    if a[field1] ~= b[field1] then
      if not reverse1 then
        return a[field1] < b[field1]
      else
        return a[field1] > b[field1]
      end
    end
    if field2 and a[field2] ~= b[field2] then
      if not reverse2 then
        return a[field2] < b[field2]
      else
        return a[field2] > b[field2]
      end
    end
    if field3 and a[field3] ~= b[field3] then
      if not reverse3 then
        return a[field3] < b[field3]
      else
        return a[field3] > b[field3]
      end
    end
  end)
  
  return records
end

function M.sortRecords4(records, field1, reverse1, field2, reverse2, 
    field3, reverse3, field4, reverse4)
  if not records or type(records) ~= "table" then return end
  if getn(records) < 2 then return records end
  if not field1 then return end
  
  sort(records, function(a, b)
    if a[field1] ~= b[field1] then
      if not reverse1 then
        return a[field1] < b[field1]
      else
        return a[field1] > b[field1]
      end
    end
    if field2 and a[field2] ~= b[field2] then
      if not reverse2 then
        return a[field2] < b[field2]
      else
        return a[field2] > b[field2]
      end
    end
    if field3 and a[field3] ~= b[field3] then
      if not reverse3 then
        return a[field3] < b[field3]
      else
        return a[field3] > b[field3]
      end
    end
    if field4 and a[field4] ~= b[field4] then
      if not reverse4 then
        return a[field4] < b[field4]
      else
        return a[field4] > b[field4]
      end
    end
  end)
  
  return records
end

function M.sortRecords(records, fields)
  if not records or type(records) ~= "table" then return end
  if getn(records) < 2 then return records end
  if not fields or type(fields) ~= "table" then return end

  sort(records, function(a, b)
    for i, entry in ipairs(fields) do
      local field = entry.field
      local reverse = entry.reverse
      if field and a[field] and b[field] and a[field] ~= b[field] then
        if not reverse then
          return a[field] < b[field]
        else
          return a[field] > b[field]
        end
      end
    end
  end)
  
  return records
end