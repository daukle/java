daukle.plugin{ api = 1, uses = { "provision", "artifact", "exec" }, exports = { "lib/jdks" } }

local jdks = daukle.require("lib/jdks")

local function roots_of(config)
  local roots = config.roots
  local main = config.main
  if roots ~= nil and type(roots) ~= "table" then
    error('"roots" must be a list of class names, not a ' .. type(roots), 0)
  end
  if roots == nil and main == nil then
    error('a java toolchain needs "main" or "roots": there is nothing to compile'
          .. ' without at least one root class', 0)
  end
  return roots, main
end

local function config_of(context)
  return context.toolchain ~= nil and context.toolchain.config or context.config
end

local function version_of(context)
  local version = (context.toolchain ~= nil and context.toolchain.version) or config_of(context).version
  if version == nil then
    error('a java toolchain needs a "version": which JDK to provision is not inferred', 0)
  end
  if string.match(version, "^%d+$") == nil then
    error('a java toolchain version must be an exact major version such as "21", not a range:'
          .. ' this plugin pins its JDKs and does not match ranges', 0)
  end
  return version
end

local DEFAULT_SOURCE_ROOT = "src/main/java"

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

local function source_paths(config, project_root)
  local roots, main = roots_of(config)
  local source_root = config.sourceRoot or DEFAULT_SOURCE_ROOT
  if type(source_root) ~= "string" then
    error('"sourceRoot" must be a path string, not a ' .. type(source_root), 0)
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
  if #paths == 0 then
    error('a java toolchain needs at least one root class, and "roots" is empty', 0)
  end
  return paths, source_root
end

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

daukle.toolchain{
  name = "java",
  generate = function(context)
    local config = config_of(context)
    source_paths(config, context.root)
    release_of(config)
    checked_args(config.compileArgs, "compileArgs")
    checked_args(config.runArgs, "runArgs")
    checked_args(config.jarArgs, "jarArgs")
    checked_classpath(config.classpath, "classpath")
    checked_classpath(config.testClasspath, "testClasspath")
    jdks.for_host{ os = context.host.os, arch = context.host.arch,
                   version = version_of(context) }
    return {}
  end,
}

local function provision_jdk(context)
  local version = version_of(context)
  local pick = jdks.for_host{ os = context.host.os, arch = context.host.arch,
                              version = version }
  return daukle.provision{
    url = pick.url,
    sha256 = pick.sha256,
    as = "temurin " .. version,
  }, pick
end

local function executable(host_os, pick, name)
  local suffix = host_os == "windows" and ".exe" or ""
  return pick.home .. "/bin/" .. name .. suffix
end

local function artifact_name(project)
  local last = string.match(project, "([^/]+)$")
  if last == nil then
    error('the project id "' .. project .. '" has no final segment to name a jar from', 0)
  end
  return last .. ".jar"
end

local function main_of(config)
  local main = config.main
  if main == nil then
    error('a java toolchain needs "main": a jar\'s entry point cannot be inferred'
          .. ' from "roots", and neither can a run target', 0)
  end
  class_to_path(main, "main")
  return main
end

daukle.task{
  name = "java:compile",
  run = function(context)
    local config = config_of(context)
    local paths, source_root = source_paths(config, context.root)
    local root, pick = provision_jdk(context)

    local argv = { "-d", "classes", "-sourcepath", context.root .. "/" .. source_root }
    local release = release_of(config)
    if release ~= nil then
      argv[#argv + 1] = "--release"
      argv[#argv + 1] = release
    end
    local entries = classpath_of(context, config, "classpath")
    local test_entries = classpath_of(context, config, "testClasspath")
    for index = 1, #test_entries do entries[#entries + 1] = test_entries[index] end
    local classpath = classpath_argument(context, entries)
    if classpath ~= nil then
      argv[#argv + 1] = "-cp"
      argv[#argv + 1] = classpath
    end
    append_args(argv, config.compileArgs, "compileArgs")
    for index = 1, #paths do argv[#argv + 1] = paths[index] end

    daukle.exec(root:tool(executable(context.host.os, pick, "javac")), argv)
  end,
}

daukle.task{
  name = "java:run",
  dependsOn = { "java:compile" },
  run = function(context)
    local root, pick = provision_jdk(context)
    local config = config_of(context)
    local entries = classpath_of(context, config, "classpath")
    local separator = context.host.os == "windows" and ";" or ":"
    local run_classpath = "classes"
    for index = 1, #entries do run_classpath = run_classpath .. separator .. entries[index] end
    local argv = append_args({ "-cp", run_classpath }, config.runArgs, "runArgs")
    argv[#argv + 1] = main_of(config)
    daukle.exec(root:tool(executable(context.host.os, pick, "java")), argv)
  end,
}

daukle.task{
  name = "java:jar",
  dependsOn = { "java:compile" },
  run = function(context)
    local root, pick = provision_jdk(context)
    local config = config_of(context)
    local argv = append_args({ "--create", "--file", artifact_name(context.project),
                               "--main-class", main_of(config) }, config.jarArgs, "jarArgs")
    argv[#argv + 1] = "-C"
    argv[#argv + 1] = "classes"
    argv[#argv + 1] = "."
    daukle.exec(root:tool(executable(context.host.os, pick, "jar")), argv)
  end,
}
