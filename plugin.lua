daukle.plugin{ api = 1, uses = { "provision", "exec" }, exports = { "lib/jdks" } }

local function roots_of(config)
  local roots = config.roots
  local main = config.main
  if roots == nil and main == nil then
    error('a java toolchain needs "main" or "roots": there is nothing to compile'
          .. ' without at least one root class', 0)
  end
  return roots, main
end

daukle.toolchain{
  name = "java",
  generate = function(context)
    roots_of(context.config)
    return {}
  end,
}
