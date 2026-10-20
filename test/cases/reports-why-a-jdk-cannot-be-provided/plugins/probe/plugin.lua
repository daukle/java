daukle.plugin{ api = 1, uses = {},
               requires = { java = { url = "https://invalid.example/plugin.lua", sha256 = "0000000000000000000000000000000000000000000000000000000000000000" } } }

local jdks = daukle.require("java:lib/jdks")

local UNPINNED = 'no pinned JDK for java "99". This plugin pins 25, 21, 17.'
  .. ' To target an OLDER Java than the one it compiles with, set "release"'
  .. ' rather than asking for an old JDK: javac emits that bytecode itself'
local NO_HOST_BUILD = 'java 17 is pinned, but Temurin publishes no windows aarch64 build of it,'
  .. ' so there is nothing for this host to download'

daukle.toolchain{ name = "probe", generate = function() return {} end }

local function announce_when(name, holds)
  if holds then
    daukle.task{ name = name, run = function() end }
  end
end

announce_when("probe:pinned-has-no-problem",
  jdks.problem_for_host{ version = "17", os = "linux", arch = "x86_64" } == nil)
announce_when("probe:unpinned-is-explained",
  jdks.problem_for_host{ version = "99", os = "linux", arch = "x86_64" } == UNPINNED)
announce_when("probe:missing-host-build-is-explained",
  jdks.problem_for_host{ version = "17", os = "windows", arch = "aarch64" } == NO_HOST_BUILD)
