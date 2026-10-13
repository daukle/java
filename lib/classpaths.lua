local launcher = daukle.require("lib/launcher")

local CLASSPATH_FIELDS = { url = true, sha256 = true, as = true, path = true }

local function checked_classpath(entries, key)
  if entries == nil then return nil end
  if type(entries) ~= "table" then
    error('"' .. key .. '" must be a list of pinned artifacts, not a ' .. type(entries), 0)
  end
  for index = 1, #entries do
    local entry = entries[index]
    if type(entry) ~= "table" then
      error(string.format('%s[%d] must be a table naming a url and a sha256, not a %s',
                          key, index, type(entry)), 0)
    end
    for name in pairs(entry) do
      if not CLASSPATH_FIELDS[name] then
        error(string.format('%s[%d] does not take "%s"; it takes url, sha256, as and path',
                            key, index, tostring(name)), 0)
      end
    end
    if type(entry.url) ~= "string" then
      error(string.format('%s[%d] needs a "url" string', key, index), 0)
    end
    if type(entry.sha256) ~= "string" then
      error(string.format('%s[%d] needs a "sha256" string: a classpath entry is pinned like'
                          .. ' every other acquisition and there is no unpinned form', key, index), 0)
    end
    if entry.path ~= nil and type(entry.path) ~= "string" then
      error(string.format('%s[%d] field "path" must name a directory inside the archive, not a %s',
                          key, index, type(entry.path)), 0)
    end
  end
  return entries
end

--[[ An entry without "path" is the common case and is fetched as a FILE: a jar
     has to stay the jar it was published as, because a multi-release one serves
     its base classes once it has been unpacked into a directory and says
     nothing about having done so. An entry WITH "path" is a distribution
     archive, where the classpath entry is a directory inside it and the JVM's
     own "/*" expands the jars within. ]]
local function classpath_entry(entry)
  if entry.path == nil then
    return daukle.artifact{ url = entry.url, sha256 = entry.sha256, as = entry.as }
  end
  local root = daukle.provision{ url = entry.url, sha256 = entry.sha256, as = entry.as }
  return root:dir(entry.path)
end

local function classpath_of(context, config, key)
  local entries = checked_classpath(config[key], key)
  local resolved = {}
  if entries ~= nil then
    for index = 1, #entries do resolved[#resolved + 1] = classpath_entry(entries[index]) end
  end
  --[[ A producer hands its artifact over in its own module block, exactly as
       daukle/c receives { package, url, sha256 } and writes a FetchContent
       block from it. Here the same two fields are fetched rather than
       delegated. ]]
  local dependencies = context.dependencies
  if key == "classpath" and dependencies ~= nil then
    for index = 1, #dependencies do
      local block = dependencies[index].block
      if type(block) == "table" and type(block.url) == "string" then
        if type(block.sha256) ~= "string" then
          error(string.format('the dependency "%s" offers a url with no sha256, and a classpath'
                              .. ' entry is pinned like every other acquisition',
                              tostring(dependencies[index].project)), 0)
        end
        resolved[#resolved + 1] = classpath_entry(block)
      end
    end
  end
  return resolved
end

--[[ Order is declaration order and never a set, because classpath order decides
     which of two copies of a class wins. ]]
local function classpath_argument(context, entries)
  if #entries == 0 then return nil end
  local separator = context.host.os == "windows" and ";" or ":"
  local joined = entries[1]
  for index = 2, #entries do joined = joined .. separator .. entries[index] end
  return joined
end

local function appended(list, extra)
  for index = 1, #extra do list[#list + 1] = extra[index] end
  return list
end

--[[ A test sees the project's own dependencies as well as its test-only ones,
     and a main source sees neither of the latter: testClasspath reaches here
     and never java:compile, which is the testImplementation/implementation
     separation the toolchain replaces. D-79. ]]
local function test_classpath_entries(context, config)
  return appended(classpath_of(context, config, "classpath"),
                  classpath_of(context, config, "testClasspath"))
end

local function launcher_jar()
  local pin = launcher.jar()
  return daukle.artifact{ url = pin.url, sha256 = pin.sha256, as = pin.as }
end

return {
  checked_classpath = checked_classpath,
  classpath_of = classpath_of,
  classpath_argument = classpath_argument,
  appended = appended,
  test_classpath_entries = test_classpath_entries,
  launcher_jar = launcher_jar,
}
