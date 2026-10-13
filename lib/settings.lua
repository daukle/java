local entry_points = daukle.require("lib/entries")

local function roots_of(config)
  local roots = config.roots
  local main = config.main
  if roots ~= nil and type(roots) ~= "table" then
    error('"roots" must be a list of class names, not a ' .. type(roots), 0)
  end
  return roots, main
end

local function config_of(context)
  return context.toolchain ~= nil and context.toolchain.config or context.config
end

--[[ A default is only compatible with this project's reproducibility stance
     because it is pinned HERE and moves only with a release of this plugin: a
     given plugin version always provisions the same JDK, so two machines
     holding one daukle.toml and one plugin pin cannot disagree. It is not read
     from the host and never follows "whatever is newest". Changing it is a
     breaking change for every project that left the version out. D-46. ]]
local DEFAULT_VERSION = "21"

local function version_of(context)
  local version = (context.toolchain ~= nil and context.toolchain.version) or config_of(context).version
  if version == nil then
    return DEFAULT_VERSION
  end
  if string.match(version, "^%d+$") == nil then
    error('a java toolchain version must be an exact major version such as "21", not a range:'
          .. ' this plugin pins its JDKs and does not match ranges', 0)
  end
  return version
end

local DEFAULT_SOURCE_ROOT = "src/main/java"
local DEFAULT_TEST_SOURCE_ROOT = "src/test/java"
local DEFAULT_RESOURCE_ROOT = "src/main/resources"
local DEFAULT_TEST_RESOURCE_ROOT = "src/test/resources"

local function path_key_of(config, key, fallback)
  local value = config[key] or fallback
  if type(value) ~= "string" then
    error('"' .. key .. '" must be a path string, not a ' .. type(value), 0)
  end
  return value
end

local function test_source_root_of(config)
  return path_key_of(config, "testSourceRoot", DEFAULT_TEST_SOURCE_ROOT)
end

--[[ A resource root is OPTIONAL in a way a source root is not: a project with
     no sources is a mistake and a project with no resources is the common
     case, so an absent directory here is silence rather than an error. D-81. ]]
local function resource_root_of(config)
  return path_key_of(config, "resourceRoot", DEFAULT_RESOURCE_ROOT)
end

local function test_resource_root_of(config)
  return path_key_of(config, "testResourceRoot", DEFAULT_TEST_RESOURCE_ROOT)
end

local function class_to_path(name, key)
  if type(name) ~= "string" then
    error('"' .. key .. '" must name a class as a string, not a ' .. type(name), 0)
  end
  local path = nil
  local remaining = name
  while true do
    local segment, rest = string.match(remaining, "^([^.]*)%.(.*)$")
    if segment == nil then segment, rest = remaining, nil end
    if string.match(segment, "^[%a_$][%w_$]*$") == nil then
      error(string.format('"%s" is not a java class name: the segment "%s" is not an identifier',
                          name, segment), 0)
    end
    path = path == nil and segment or (path .. "/" .. segment)
    if rest == nil then break end
    remaining = rest
  end
  return path .. ".java"
end

--[[ A nil path list means every source under the source root, which is what a
     LIBRARY needs: its entry points are its consumers and none of them exists
     at compile time, so naming roots would restate the source tree by hand.
     Gradle's java plugin compiles the whole tree with no configuration, and a
     replacement that charges for what the original gives away is not one.
     D-74. ]]
local function source_paths(config, project_root)
  local roots, main = roots_of(config)
  local source_root = config.sourceRoot or DEFAULT_SOURCE_ROOT
  if type(source_root) ~= "string" then
    error('"sourceRoot" must be a path string, not a ' .. type(source_root), 0)
  end
  --[[ Entries do NOT narrow on their own. A project naming neither "roots" nor
       "main" compiles its whole tree, which already holds every entry class, so
       a project that only declares entries keeps the library default rather
       than silently compiling less than it did before. ]]
  if roots == nil and main == nil then
    return nil, source_root
  end
  local prefix = project_root .. "/" .. source_root .. "/"
  local paths = {}
  if roots ~= nil then
    for index = 1, #roots do
      paths[#paths + 1] = prefix .. class_to_path(roots[index], "roots")
    end
  end
  if main ~= nil then
    paths[#paths + 1] = prefix .. class_to_path(main, "main")
  end
  --[[ Appended to a narrowed list, because a narrowed build that omitted its
       own entry classes would fail at run time with a missing class rather
       than at compile time with a cause. ]]
  local declared = entry_points.declared(config, class_to_path)
  for index = 1, #declared do
    paths[#paths + 1] = prefix .. class_to_path(declared[index].main,
                                                'entries.' .. declared[index].name .. '.main')
  end
  if #paths == 0 then
    error('"roots" is empty: remove it to compile every source under "'
          .. source_root .. '", or name at least one class', 0)
  end
  return paths, source_root
end

local function checked_args(extra, key)
  if extra ~= nil and type(extra) ~= "table" then
    error('"' .. key .. '" must be a list of arguments, not a ' .. type(extra), 0)
  end
  return extra
end

local function append_args(argv, extra, key)
  checked_args(extra, key)
  if extra == nil then return argv end
  for index = 1, #extra do argv[#argv + 1] = extra[index] end
  return argv
end

local function release_of(config)
  local release = config.release
  if release == nil then return nil end
  local kind = type(release)
  if kind == "number" then
    if release ~= math.floor(release) then
      error('"release" must be a whole version such as 17, not ' .. tostring(release), 0)
    end
    return string.format("%d", release)
  end
  if kind ~= "string" then
    error('"release" must be a version such as "17", not a ' .. kind, 0)
  end
  return release
end

local function main_of(config)
  local main = config.main
  if main == nil then
    --[[ A project that declared entries has already named what to run, so the
         refusal names those tasks rather than demanding a key the project
         deliberately left out. Same answer node:run gives a package that
         declares scripts and no entry. ]]
    local declared = entry_points.declared(config, class_to_path)
    if #declared > 0 then
      local names = {}
      for index = 1, #declared do names[index] = "java:run-" .. declared[index].name end
      error('this project declares "entries" and no project-wide "main", so there is no single'
            .. ' entry point for "java:run": run one of ' .. table.concat(names, ", ")
            .. ', or add a "main" to name the default', 0)
    end
    error('a java toolchain needs "main" to run: a run target\'s entry point cannot be inferred'
          .. ' from "roots". A jar does NOT need one, and omitting it builds a library jar'
          .. ' with no Main-Class', 0)
  end
  class_to_path(main, "main")
  return main
end

return {
  config_of = config_of,
  version_of = version_of,
  test_source_root_of = test_source_root_of,
  resource_root_of = resource_root_of,
  test_resource_root_of = test_resource_root_of,
  class_to_path = class_to_path,
  source_paths = source_paths,
  checked_args = checked_args,
  append_args = append_args,
  release_of = release_of,
  main_of = main_of,
}
