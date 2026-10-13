daukle.plugin{ api = 1, uses = { "provision", "artifact", "exec", "write", "read", "parse" },
               exports = { "lib/jdks", "lib/launcher", "lib/entries" } }

local jdks = daukle.require("lib/jdks")
--[[ Aliased because "entries" is already a local inside java:run and java:jar,
     where it names the classpath being assembled. ]]
local entry_points = daukle.require("lib/entries")
local settings = daukle.require("lib/settings")
local jdk_tools = daukle.require("lib/jdk_tools")
local classpaths = daukle.require("lib/classpaths")

daukle.toolchain{
  name = "java",
  generate = function(context)
    local config = settings.config_of(context)
    settings.source_paths(config, context.root)
    settings.test_source_root_of(config)
    settings.resource_root_of(config)
    settings.test_resource_root_of(config)
    settings.release_of(config)
    settings.checked_args(config.compileArgs, "compileArgs")
    settings.checked_args(config.runArgs, "runArgs")
    settings.checked_args(config.jarArgs, "jarArgs")
    settings.checked_args(config.testArgs, "testArgs")
    classpaths.checked_classpath(config.classpath, "classpath")
    classpaths.checked_classpath(config.testClasspath, "testClasspath")
    jdks.for_host{ os = context.host.os, arch = context.host.arch,
                   version = settings.version_of(context) }
    return {}
  end,
}

local SOURCE_ARCHIVE = ".daukle-sources.jar"
local TEST_SOURCE_ARCHIVE = ".daukle-test-sources.jar"
local SOURCE_ARGFILE = ".daukle-sources.args"
local TEST_SOURCE_ARGFILE = ".daukle-test-sources.args"
local CLASSES = "classes"
local TEST_CLASSES = "test-classes"

local function artifact_name(project, suffix)
  local last = string.match(project, "([^/]+)$")
  if last == nil then
    error('the project id "' .. project .. '" has no final segment to name a jar from', 0)
  end
  return last .. (suffix or "") .. ".jar"
end

--[[ One runner for java:run and for every java:run-<entry>, so a classpath or
     resource change cannot reach one and miss the others.

     @implNote a project-wide "runArgs" applies to EVERY entry and the entry's
     own are appended after it, which is the same rule daukle/gradle settled on
     for project-wide keys: they reach every module rather than only the
     unnamed one. An entry that must not see them is a second toolchain. ]]
local function run_class(context, main_class, run_args)
  local root, pick = jdk_tools.provision_jdk(context)
  local config = settings.config_of(context)
  local resources = jdk_tools.resource_directories(context, root, pick, config,
                                                   { settings.resource_root_of })
  local classpath = classpaths.appended({ CLASSES }, resources)
  classpaths.appended(classpath, classpaths.classpath_of(context, config, "classpath"))
  local argv = settings.append_args({ "-cp", classpaths.classpath_argument(context, classpath) },
                                    config.runArgs, "runArgs")
  if run_args ~= nil then
    for index = 1, #run_args do argv[#argv + 1] = run_args[index] end
  end
  argv[#argv + 1] = main_class
  daukle.exec(root:tool(jdk_tools.executable(context.host.os, pick, "java")), argv)
end

daukle.task{
  name = "java:compile",
  run = function(context)
    local config = settings.config_of(context)
    local paths, source_root = settings.source_paths(config, context.root)
    local root, pick = jdk_tools.provision_jdk(context)
    if paths == nil then
      paths = jdk_tools.enumerated_sources(context, root, pick, source_root, SOURCE_ARCHIVE)
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
    local release = settings.release_of(config)
    if release ~= nil then
      argv[#argv + 1] = "--release"
      argv[#argv + 1] = release
    end
    local classpath = classpaths.classpath_argument(context,
                                                    classpaths.classpath_of(context, config,
                                                                            "classpath"))
    if classpath ~= nil then
      argv[#argv + 1] = "-cp"
      argv[#argv + 1] = classpath
    end
    settings.append_args(argv, config.compileArgs, "compileArgs")
    argv[#argv + 1] = jdk_tools.source_argfile(paths, SOURCE_ARGFILE)

    daukle.exec(root:tool(jdk_tools.executable(context.host.os, pick, "javac")), argv)
  end,
}

daukle.task{
  name = "java:run",
  dependsOn = { "java:compile" },
  run = function(context)
    local config = settings.config_of(context)
    run_class(context, settings.main_of(config), nil)
  end,
}

daukle.task{
  name = "java:jar",
  dependsOn = { "java:compile" },
  run = function(context)
    local root, pick = jdk_tools.provision_jdk(context)
    local config = settings.config_of(context)
    local argv = { "--create", "--file", artifact_name(context.project) }
    --[[ A library has no entry point, which is D-74's finding one task over:
         Gradle's jar needs no main class and writes Main-Class only when given
         one. java:run still requires it, because a run target genuinely needs
         one. D-81. ]]
    if config.main ~= nil then
      argv[#argv + 1] = "--main-class"
      argv[#argv + 1] = settings.main_of(config)
    end
    settings.append_args(argv, config.jarArgs, "jarArgs")
    argv[#argv + 1] = "-C"
    argv[#argv + 1] = CLASSES
    argv[#argv + 1] = "."
    local resources = jdk_tools.resource_directories(context, root, pick, config,
                                                     { settings.resource_root_of })
    for index = 1, #resources do
      argv[#argv + 1] = "-C"
      argv[#argv + 1] = resources[index]
      argv[#argv + 1] = "."
    end
    daukle.exec(root:tool(jdk_tools.executable(context.host.os, pick, "jar")), argv)
  end,
}

daukle.task{
  name = "java:test-compile",
  dependsOn = { "java:compile" },
  run = function(context)
    local config = settings.config_of(context)
    local source_root = settings.test_source_root_of(config)
    local root, pick = jdk_tools.provision_jdk(context)
    local paths = jdk_tools.enumerated_sources(context, root, pick, source_root,
                                               TEST_SOURCE_ARCHIVE)
    if paths == nil then
      error('no directory "' .. source_root .. '" to compile tests from: create it, or set'
            .. ' "testSourceRoot" if the tests live elsewhere', 0)
    end
    if #paths == 0 then
      error('no ".java" test was found under "' .. source_root .. '": set "testSourceRoot" if'
            .. ' the tests live elsewhere', 0)
    end

    local argv = { "-d", TEST_CLASSES, "-sourcepath", context.root .. "/" .. source_root }
    local release = settings.release_of(config)
    if release ~= nil then
      argv[#argv + 1] = "--release"
      argv[#argv + 1] = release
    end
    --[[ The launcher is last so a project that pins its own junit in
         testClasspath compiles against that one, and a project that pins
         nothing still compiles. ]]
    local resources = jdk_tools.resource_directories(context, root, pick, config,
                                                     { settings.resource_root_of,
                                                       settings.test_resource_root_of })
    local entries = classpaths.appended({ CLASSES }, resources)
    classpaths.appended(entries, classpaths.test_classpath_entries(context, config))
    entries[#entries + 1] = classpaths.launcher_jar()
    argv[#argv + 1] = "-cp"
    argv[#argv + 1] = classpaths.classpath_argument(context, entries)
    settings.append_args(argv, config.compileArgs, "compileArgs")
    argv[#argv + 1] = jdk_tools.source_argfile(paths, TEST_SOURCE_ARGFILE)

    daukle.exec(root:tool(jdk_tools.executable(context.host.os, pick, "javac")), argv)
  end,
}

--[[ Without --fail-if-no-tests the launcher exits 0 on a tree it discovered
     nothing in, so a java:test that trusted the default would be green on a
     project whose tests reach nothing. D-51 is the same shape. D-79. ]]
daukle.task{
  name = "java:test",
  dependsOn = { "java:test-compile" },
  run = function(context)
    local config = settings.config_of(context)
    local source_root = settings.test_source_root_of(config)
    local root, pick = jdk_tools.provision_jdk(context)
    local resources = jdk_tools.resource_directories(context, root, pick, config,
                                                     { settings.resource_root_of,
                                                       settings.test_resource_root_of })
    local entries = classpaths.appended({ TEST_CLASSES, CLASSES }, resources)
    classpaths.appended(entries, classpaths.test_classpath_entries(context, config))

    --[[ java -jar ignores -cp, so the project classpath goes to the launcher's
         own option rather than to the JVM. ]]
    local argv = { "-jar", classpaths.launcher_jar(), "execute",
                   "--class-path", classpaths.classpath_argument(context, entries),
                   "--scan-class-path", TEST_CLASSES,
                   "--details=summary", "--fail-if-no-tests" }
    settings.append_args(argv, config.testArgs, "testArgs")

    local java = root:tool(jdk_tools.executable(context.host.os, pick, "java"))
    local result = daukle.exec(java, argv, { check = false })
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
    local config = settings.config_of(context)
    local _, source_root = settings.source_paths(config, context.root)
    local root, pick = jdk_tools.provision_jdk(context)
    local sources = jdk_tools.readable_directory(context, root, pick, source_root)
    if sources == nil then
      error('no directory "' .. source_root .. '" to package sources from: set "sourceRoot" if'
            .. ' the sources live elsewhere', 0)
    end

    local argv = settings.append_args({ "--create", "--file",
                                        artifact_name(context.project, "-sources") },
                                      config.jarArgs, "jarArgs")
    argv[#argv + 1] = "-C"
    argv[#argv + 1] = sources
    argv[#argv + 1] = "."
    local resources = jdk_tools.resource_directories(context, root, pick, config,
                                                     { settings.resource_root_of })
    for index = 1, #resources do
      argv[#argv + 1] = "-C"
      argv[#argv + 1] = resources[index]
      argv[#argv + 1] = "."
    end
    daukle.exec(root:tool(jdk_tools.executable(context.host.os, pick, "jar")), argv)
  end,
}

--[[ A task per declared entry point, registered from the CHUNK because a daukle
     task takes no arguments: N runnable classes need N registered tasks and a
     fixed vocabulary cannot substitute. D-110 granted the chunk-time manifest
     read this needs.

     @implNote the ".toml" gate is not optional. Parsing daukle.manifest when it
     is Lua is FATAL on every command rather than degraded, which is the crash
     daukle/cmake@1.4.0 shipped. A project with a Lua manifest keeps java:run
     and gains no entry tasks, because nothing a chunk can reach sees a
     Lua-declared config. ]]
local function declarative_manifest()
  if string.match(daukle.manifest, "%.toml$") == nil then return nil end
  return daukle.parse(daukle.read(daukle.manifest), daukle.manifest)
end

local function declared_entries()
  local document = declarative_manifest()
  if document == nil then return {} end
  local toolchains = document.toolchains
  local config = type(toolchains) == "table" and toolchains.java or nil
  if type(config) ~= "table" then return {} end
  return entry_points.declared(config, settings.class_to_path)
end

for _, entry in ipairs(declared_entries()) do
  daukle.task{
    name = "java:run-" .. entry.name,
    dependsOn = { "java:compile" },
    run = function(context)
      run_class(context, entry.main, entry.runArgs)
    end,
  }
end
