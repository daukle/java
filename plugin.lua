daukle.plugin{ api = 1, uses = { "provision", "exec" }, exports = { "lib/jdks" } }

local jdks = daukle.require("lib/jdks")

local function roots_of(config)
  local roots = config.roots
  local main = config.main
  if roots == nil and main == nil then
    error('a java toolchain needs "main" or "roots": there is nothing to compile'
          .. ' without at least one root class', 0)
  end
  return roots, main
end

local function version_of(context)
  local version = context.toolchain ~= nil and context.toolchain.version or context.config.version
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

local function class_to_path(name)
  if type(name) ~= "string" then
    error('every entry in "roots" must be a class name string, not a '
          .. type(name), 0)
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
  local names = {}
  if roots ~= nil then
    for index = 1, #roots do names[#names + 1] = roots[index] end
  end
  if main ~= nil then names[#names + 1] = main end

  local paths = {}
  for index = 1, #names do
    paths[index] = project_root .. "/" .. source_root .. "/" .. class_to_path(names[index])
  end
  return paths, source_root
end

daukle.toolchain{
  name = "java",
  generate = function(context)
    source_paths(context.config, context.root)
    jdks.for_host{ os = context.host.os, arch = context.host.arch,
                   version = version_of(context) }
    return {}
  end,
}
