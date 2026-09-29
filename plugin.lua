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

daukle.toolchain{
  name = "java",
  generate = function(context)
    roots_of(context.config)
    jdks.for_host{ os = context.host.os, arch = context.host.arch,
                   version = version_of(context) }
    return {}
  end,
}
