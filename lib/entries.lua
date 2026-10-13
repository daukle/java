--[[ The entries map, which is what makes a project's SECOND entry point
     reachable. This toolchain modelled one "main", so a project with twelve
     runnable classes had one task and eleven it could only reach from an IDE.
     Measured: 9 live projects here declare several main() methods and not one
     of them exposes the extras through Gradle either. D-111. ]]

local entries = {}

local RESERVED = {
  compile = true, run = true, jar = true, test = true,
  ["test-compile"] = true, ["sources-jar"] = true,
}

--[[ @implNote the "-" sits LAST in the class so it is a literal. A bare "-"
     inside a Lua pattern is a lazy quantifier and matches nothing at all, which
     this repository has shipped twice in daukle/gradle. ]]
local NAMEABLE = "^[%l%d%._-]+$"

local function checked_name(name, seen)
  if type(name) ~= "string" or name == "" then
    error('every key of "entries" names an entry point, and "' .. tostring(name)
          .. '" is not a name', 0)
  end
  if string.match(name, NAMEABLE) == nil then
    error('"' .. name .. '" is an entry this toolchain cannot name a task after: a name is'
          .. ' lowercase letters, digits, ".", "_" and "-"', 0)
  end
  --[[ Every entry task is prefixed "run-", so a name can only collide with
       another entry. The reserved list is checked anyway: it costs one table
       and it is what stops "java:run-run" reading as a verb this plugin
       declares, should the prefix ever change. ]]
  if RESERVED[name] then
    error('an entry may not be called "' .. name .. '": it is a verb this toolchain declares'
          .. ' itself', 0)
  end
  if seen[name] then
    error('"entries" declares "' .. name .. '" twice', 0)
  end
  seen[name] = true
  return name
end

local function checked_run_args(args, where)
  if args == nil then return nil end
  if type(args) ~= "table" then
    error(where .. ' has "runArgs" that is a ' .. type(args)
          .. ', and runArgs is a list of strings', 0)
  end
  for index = 1, #args do
    if type(args[index]) ~= "string" then
      error(where .. ' has a "runArgs" entry that is a ' .. type(args[index])
            .. ', and every argument is a string', 0)
    end
  end
  return args
end

--- Every declared entry point, sorted by name so registration is deterministic.
---
--- @param config the toolchain's config table
--- @param check_class a validator for a class name, which the caller owns
--- because the class-to-path rule lives in plugin.lua
function entries.declared(config, check_class)
  local block = config.entries
  if block == nil then return {} end
  if type(block) ~= "table" then
    error('"entries" must be a table of per-entry blocks, not a ' .. type(block), 0)
  end

  local names = {}
  local seen = {}
  for name in pairs(block) do
    names[#names + 1] = checked_name(name, seen)
  end
  table.sort(names)

  local out = {}
  for index = 1, #names do
    local name = names[index]
    local where = '"entries.' .. name .. '"'
    local entry = block[name]
    if type(entry) ~= "table" then
      error(where .. ' is a ' .. type(entry)
            .. ', and an entry is a block naming the class to run', 0)
    end
    if type(entry.main) ~= "string" or entry.main == "" then
      error(where .. ' needs a "main" naming the class to run, and it is a '
            .. type(entry.main), 0)
    end
    check_class(entry.main, 'entries.' .. name .. '.main')
    out[index] = { name = name, main = entry.main,
                   runArgs = checked_run_args(entry.runArgs, where) }
  end
  return out
end

return entries
