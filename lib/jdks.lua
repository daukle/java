--[[ Which JDK RUNS the build, which is not which bytecode comes out: javac's
     own --release does that, so a project targeting Java 8 needs no JDK 8 row
     and "release" is the key for it. Measured across 433 build files here, 57
     declare a toolchain to compile WITH: 39 ask for 17, 7 for 21, 5 for 25,
     7 for 8 and 1 for 11. The last two are the --release case. D-112. ]]
local RELEASES = {
  ["25"] = { full = "25.0.4.1+1", underscored = "25.0.4.1_1" },
  ["21"] = { full = "21.0.5+11", underscored = "21.0.5_11" },
  ["17"] = { full = "17.0.13+11", underscored = "17.0.13_11" },
}

-- The unpacker strips no leading component, so a member path carries the
-- archive's own top-level directory. macOS keeps the JDK under Contents/Home,
-- which is folded in here so a caller composes one string on every platform.
local HOMES = {
  linux = "jdk-%s",
  windows = "jdk-%s",
  macos = "jdk-%s/Contents/Home",
}

-- daukle names the host; Adoptium names the file. The two disagree on x86_64,
-- so the table is keyed on daukle's spelling and translated on the way out.
local ASSET_OS = { linux = "linux", windows = "windows", macos = "mac" }
local ASSET_ARCH = { x86_64 = "x64", aarch64 = "aarch64" }
local ASSET_EXT = { linux = "tar.gz", windows = "zip", macos = "tar.gz" }

-- Transcribed from the .sha256.txt Adoptium publishes beside each asset.
-- Never computed from a file on disk: core.autocrlf rewrites line endings and
-- a digest taken from a working tree stops matching the published bytes.
local DIGESTS = {
  -- Temurin 25 publishes no windows/aarch64 build either, so it has the same
  -- five rows as 17 rather than 21's six.
  ["25"] = {
    ["linux/x86_64"]    = "dbb698396d478e7fa2b1e50f4103324b2a99b90569ee27c33f2261f9215cf41e",
    ["linux/aarch64"]   = "69df11a02cfa3ef7d7ca645e03edce6778ec090e100f6ae2b42097865730ac52",
    ["macos/x86_64"]    = "e6229d9504f7922053ab31821b9e6bee8761daf7b026a3476d1a027563009880",
    ["macos/aarch64"]   = "61979887f7506a24a57439ff99adb8b3a7fc89977d9cfe3b8984f58a981b7b9d",
    ["windows/x86_64"]  = "00c847d804f4a78e9f04f2683faf14fed898535b177b7fc704486cb0284e9283",
  },
  ["21"] = {
    ["linux/x86_64"]    = "3c654d98404c073b8a7e66bffb27f4ae3e7ede47d13284c132d40a83144bfd8c",
    ["linux/aarch64"]   = "6482639ed9fd22aa2e704cc366848b1b3e1586d2bf1213869c43e80bca58fe5c",
    ["macos/x86_64"]    = "b9b46f396ab5f3658fa5569af963896167c7f735cfec816359c04101fae38bdf",
    ["macos/aarch64"]   = "dc6db7347907d23743d13af935d3c10e8b3490acdf542115f578838227da0dab",
    ["windows/x86_64"]  = "6f09d4a3598542313cca1540106d537c7092a54e415d569f7b928160a90d3128",
    ["windows/aarch64"] = "05a0bceabb9038b2f5cd843177b86028c14d246f6152e07a27cca0c74ed83dad",
  },
  -- Temurin 17 publishes no windows/aarch64 build, so there is no entry for it.
  ["17"] = {
    ["linux/x86_64"]    = "8682892fc02965930b9022c066fa164dd6f458ef4a5dc262016aa28333b30f49",
    ["linux/aarch64"]   = "0c17fa4f14c0d2cc9e9334f996fccdddc5da4459d768f3105c7ff0283c47bf62",
    ["macos/x86_64"]    = "840535070200a944a6b582d258ee84608bd25c9f2b5d1cdddb58dfadb019675a",
    ["macos/aarch64"]   = "d8b2f77f755d06e81a540834c5be22ed86f3c8a51a20396606c074303f8f9e2d",
    ["windows/x86_64"]  = "6b64255e1bd690b09a135d44ac6b0d6bd4490728a8bad81904941d2789d394c0",
  },
}

local function asset_url(major, release, os_name, arch)
  return string.format(
    "https://github.com/adoptium/temurin%s-binaries/releases/download/jdk-%s/"
      .. "OpenJDK%sU-jdk_%s_%s_hotspot_%s.%s",
    major, release.full, major, ASSET_ARCH[arch], ASSET_OS[os_name],
    release.underscored, ASSET_EXT[os_name])
end

--- The pinned majors, newest first, for a refusal that names them.
local function known()
  local versions = {}
  for version in pairs(RELEASES) do versions[#versions + 1] = version end
  table.sort(versions, function(left, right) return tonumber(left) > tonumber(right) end)
  return table.concat(versions, ", ")
end

local function for_host(request)
  local version = request.version
  local os_name = request.os
  local arch = request.arch

  local release = RELEASES[version]
  local digests = DIGESTS[version]
  local key = os_name .. "/" .. arch

  --[[ The two failures are different and the message said the same thing for
       both. A version this plugin does not pin is answered by the list; a
       version it pins but not for this host is answered by nothing the user
       can change, so saying so is the whole of the help. And an OLD version is
       almost always the wrong question: "release" targets old bytecode from a
       modern JDK, which is why there is no JDK 8 row and should not be. ]]
  if release == nil or digests == nil then
    error(string.format('no pinned JDK for java "%s". This plugin pins %s.'
                        .. ' To target an OLDER Java than the one it compiles with, set "release"'
                        .. ' rather than asking for an old JDK: javac emits that bytecode itself',
                        tostring(version), known()), 0)
  end
  if digests[key] == nil then
    error(string.format('java %s is pinned, but Temurin publishes no %s %s build of it,'
                        .. ' so there is nothing for this host to download',
                        version, tostring(os_name), tostring(arch)), 0)
  end

  return {
    url = asset_url(version, release, os_name, arch),
    sha256 = digests[key],
    home = string.format(HOMES[os_name], release.full),
  }
end

return { for_host = for_host }
