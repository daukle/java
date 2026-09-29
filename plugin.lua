daukle.plugin{ api = 1, uses = { "provision", "exec" }, exports = { "lib/jdks" } }

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
    local argv = append_args({ "-cp", "classes" }, config.runArgs, "runArgs")
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
