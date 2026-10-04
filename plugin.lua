daukle.plugin{ api = 1, uses = { "provision", "artifact", "exec" },
               exports = { "lib/jdks", "lib/launcher" } }

local jdks = daukle.require("lib/jdks")
local launcher = daukle.require("lib/launcher")

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
  if #paths == 0 then
    error('"roots" is empty: remove it to compile every source under "'
          .. source_root .. '", or name at least one class', 0)
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
    test_source_root_of(config)
    resource_root_of(config)
    test_resource_root_of(config)
    release_of(config)
    checked_args(config.compileArgs, "compileArgs")
    checked_args(config.runArgs, "runArgs")
    checked_args(config.jarArgs, "jarArgs")
    checked_args(config.testArgs, "testArgs")
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

local SOURCE_ARCHIVE = ".daukle-sources.jar"
local TEST_SOURCE_ARCHIVE = ".daukle-test-sources.jar"
local CLASSES = "classes"
local TEST_CLASSES = "test-classes"

--[[ jar walks a tree recursively and prints it, which is the only enumeration
     available to a plugin: the sandbox has no directory verb and daukle.read
     takes one file. The tool is the JDK's own, already provisioned, so this
     costs no new acquisition and behaves the same on every platform.
     A nil return means the directory could not be read at all, which the
     caller reports as a missing source root rather than as a jar exit code. ]]
local function listed_entries(jar_tool, archive, directory, suffix)
  local created = daukle.exec(jar_tool, { "--create", "--file", archive, "-C", directory, "." },
                              { check = false })
  if created.code ~= 0 then return nil end
  local listed = daukle.exec(jar_tool, { "--list", "--file", archive }, { capture = true })
  if listed.truncated then
    error('the listing of "' .. directory .. '" exceeded the 1 MiB daukle captures from a'
          .. ' tool, so it cannot be read in full: name "roots" explicitly for a tree'
          .. ' this large', 0)
  end
  local entries = {}
  for line in string.gmatch(listed.stdout, "[^\r\n]+") do
    if string.sub(line, -#suffix) == suffix then
      entries[#entries + 1] = line
    end
  end
  return entries
end

local function enumerated_sources(context, root, pick, source_root, archive)
  local jar_tool = root:tool(executable(context.host.os, pick, "jar"))
  local directory = context.root .. "/" .. source_root
  local entries = listed_entries(jar_tool, archive, directory, ".java")
  if entries == nil then return nil end
  local paths = {}
  for index = 1, #entries do paths[index] = directory .. "/" .. entries[index] end
  return paths
end

local PROBE_ARCHIVE = ".daukle-probe.jar"

--[[ The sandbox has no directory verb, so presence is measured the only way a
     plugin can: jar refuses a directory that is not there and its exit code is
     the answer. A missing resource root must be OMITTED rather than passed,
     because "jar -C nosuchdir ." fails the whole invocation. D-81. ]]
local function readable_directory(context, root, pick, directory)
  local jar_tool = root:tool(executable(context.host.os, pick, "jar"))
  local absolute = context.root .. "/" .. directory
  local probed = daukle.exec(jar_tool,
                             { "--create", "--file", PROBE_ARCHIVE, "-C", absolute, "." },
                             { check = false })
  if probed.code ~= 0 then return nil end
  return absolute
end

local function resource_directories(context, root, pick, config, keys)
  local found = {}
  for index = 1, #keys do
    local directory = readable_directory(context, root, pick, keys[index](config))
    if directory ~= nil then found[#found + 1] = directory end
  end
  return found
end

local function artifact_name(project, suffix)
  local last = string.match(project, "([^/]+)$")
  if last == nil then
    error('the project id "' .. project .. '" has no final segment to name a jar from', 0)
  end
  return last .. (suffix or "") .. ".jar"
end

local function main_of(config)
  local main = config.main
  if main == nil then
    error('a java toolchain needs "main" to run: a run target\'s entry point cannot be inferred'
          .. ' from "roots". A jar does NOT need one, and omitting it builds a library jar'
          .. ' with no Main-Class', 0)
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
    if paths == nil then
      paths = enumerated_sources(context, root, pick, source_root, SOURCE_ARCHIVE)
      if paths == nil then
        error('no directory "' .. source_root .. '" to compile from: set "sourceRoot" if the'
              .. ' sources live elsewhere', 0)
      end
      if #paths == 0 then
        error('no ".java" source was found under "' .. source_root .. '": set "sourceRoot" if the'
              .. ' sources live elsewhere, or name "roots" or "main"', 0)
      end
    end

    local argv = { "-d", CLASSES, "-sourcepath", context.root .. "/" .. source_root }
    local release = release_of(config)
    if release ~= nil then
      argv[#argv + 1] = "--release"
      argv[#argv + 1] = release
    end
    local classpath = classpath_argument(context, classpath_of(context, config, "classpath"))
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
    local entries = appended({ CLASSES },
                             resource_directories(context, root, pick, config, { resource_root_of }))
    appended(entries, classpath_of(context, config, "classpath"))
    local argv = append_args({ "-cp", classpath_argument(context, entries) },
                             config.runArgs, "runArgs")
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
    local argv = { "--create", "--file", artifact_name(context.project) }
    --[[ A library has no entry point, which is D-74's finding one task over:
         Gradle's jar needs no main class and writes Main-Class only when given
         one. java:run still requires it, because a run target genuinely needs
         one. D-81. ]]
    if config.main ~= nil then
      argv[#argv + 1] = "--main-class"
      argv[#argv + 1] = main_of(config)
    end
    append_args(argv, config.jarArgs, "jarArgs")
    argv[#argv + 1] = "-C"
    argv[#argv + 1] = CLASSES
    argv[#argv + 1] = "."
    local resources = resource_directories(context, root, pick, config, { resource_root_of })
    for index = 1, #resources do
      argv[#argv + 1] = "-C"
      argv[#argv + 1] = resources[index]
      argv[#argv + 1] = "."
    end
    daukle.exec(root:tool(executable(context.host.os, pick, "jar")), argv)
  end,
}

daukle.task{
  name = "java:test-compile",
  dependsOn = { "java:compile" },
  run = function(context)
    local config = config_of(context)
    local source_root = test_source_root_of(config)
    local root, pick = provision_jdk(context)
    local paths = enumerated_sources(context, root, pick, source_root, TEST_SOURCE_ARCHIVE)
    if paths == nil then
      error('no directory "' .. source_root .. '" to compile tests from: create it, or set'
            .. ' "testSourceRoot" if the tests live elsewhere', 0)
    end
    if #paths == 0 then
      error('no ".java" test was found under "' .. source_root .. '": set "testSourceRoot" if'
            .. ' the tests live elsewhere', 0)
    end

    local argv = { "-d", TEST_CLASSES, "-sourcepath", context.root .. "/" .. source_root }
    local release = release_of(config)
    if release ~= nil then
      argv[#argv + 1] = "--release"
      argv[#argv + 1] = release
    end
    --[[ The launcher is last so a project that pins its own junit in
         testClasspath compiles against that one, and a project that pins
         nothing still compiles. ]]
    local entries = appended({ CLASSES },
                             resource_directories(context, root, pick, config,
                                                  { resource_root_of, test_resource_root_of }))
    appended(entries, test_classpath_entries(context, config))
    entries[#entries + 1] = launcher_jar()
    argv[#argv + 1] = "-cp"
    argv[#argv + 1] = classpath_argument(context, entries)
    append_args(argv, config.compileArgs, "compileArgs")
    for index = 1, #paths do argv[#argv + 1] = paths[index] end

    daukle.exec(root:tool(executable(context.host.os, pick, "javac")), argv)
  end,
}

--[[ Without --fail-if-no-tests the launcher exits 0 on a tree it discovered
     nothing in, so a java:test that trusted the default would be green on a
     project whose tests reach nothing. D-51 is the same shape. D-79. ]]
daukle.task{
  name = "java:test",
  dependsOn = { "java:test-compile" },
  run = function(context)
    local config = config_of(context)
    local source_root = test_source_root_of(config)
    local root, pick = provision_jdk(context)
    local entries = appended({ TEST_CLASSES, CLASSES },
                             resource_directories(context, root, pick, config,
                                                  { resource_root_of, test_resource_root_of }))
    appended(entries, test_classpath_entries(context, config))

    --[[ java -jar ignores -cp, so the project classpath goes to the launcher's
         own option rather than to the JVM. ]]
    local argv = { "-jar", launcher_jar(), "execute",
                   "--class-path", classpath_argument(context, entries),
                   "--scan-class-path", TEST_CLASSES,
                   "--details=summary", "--fail-if-no-tests" }
    append_args(argv, config.testArgs, "testArgs")

    local result = daukle.exec(root:tool(executable(context.host.os, pick, "java")), argv,
                               { check = false })
    if result.code == 1 then
      error("a test failed; the summary above names which", 0)
    end
    if result.code == 2 then
      error('no test was found under "' .. source_root .. '": the sources compiled, but none of'
            .. ' them holds a test the launcher recognises', 0)
    end
    if result.code ~= 0 then
      error("the test launcher exited with code " .. tostring(result.code), 0)
    end
  end,
}

--[[ A sources jar packages sources AND resources, which is what Gradle's
     sourcesJar does (sourceSets.main.allSource) rather than merely resembles.
     It needs no compilation, so it depends on nothing. D-81. ]]
daukle.task{
  name = "java:sources-jar",
  run = function(context)
    local config = config_of(context)
    local _, source_root = source_paths(config, context.root)
    local root, pick = provision_jdk(context)
    local sources = readable_directory(context, root, pick, source_root)
    if sources == nil then
      error('no directory "' .. source_root .. '" to package sources from: set "sourceRoot" if'
            .. ' the sources live elsewhere', 0)
    end

    local argv = append_args({ "--create", "--file", artifact_name(context.project, "-sources") },
                             config.jarArgs, "jarArgs")
    argv[#argv + 1] = "-C"
    argv[#argv + 1] = sources
    argv[#argv + 1] = "."
    local resources = resource_directories(context, root, pick, config, { resource_root_of })
    for index = 1, #resources do
      argv[#argv + 1] = "-C"
      argv[#argv + 1] = resources[index]
      argv[#argv + 1] = "."
    end
    daukle.exec(root:tool(executable(context.host.os, pick, "jar")), argv)
  end,
}
