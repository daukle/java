--[[ The test launcher is infrastructure rather than a project dependency, so
     it is pinned HERE and moves only with a release of this plugin: a given
     plugin version always runs the same launcher, and a project writes nothing
     about it. Same reproducibility argument lib/jdks.lua makes for the default
     JDK version. D-79. ]]
local VERSION = "6.1.3"

--[[ Transcribed from the .sha256 Maven Central publishes beside the asset and
     checked once against the downloaded bytes. Never computed from a file on
     disk: core.autocrlf rewrites line endings and a digest taken from a working
     tree stops matching the published bytes. ]]
local SHA256 = "e62b96ac475dbcde8599ea905d088f65d90778f86e259b856a49fa5c4ea256ec"

--[[ The standalone jar carries the jupiter api, the jupiter engine, the vintage
     engine, opentest4j and apiguardian, so a project that declares nothing in
     testClasspath can still write and run a JUnit 5 test. Measured: 2135
     entries, and bytecode compiled against jupiter 5.10.1 runs under it
     unchanged. Platform 6 needs java 17, which every version lib/jdks.lua pins
     satisfies. ]]
local function jar()
  return {
    url = "https://repo1.maven.org/maven2/org/junit/platform/junit-platform-console-standalone/"
          .. VERSION .. "/junit-platform-console-standalone-" .. VERSION .. ".jar",
    sha256 = SHA256,
    as = "junit-platform-console-standalone " .. VERSION,
  }
end

return { jar = jar, version = VERSION }
