local RELEASES = {
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

local function for_host(request)
  local version = request.version
  local os_name = request.os
  local arch = request.arch

  local release = RELEASES[version]
  local digests = DIGESTS[version]
  local key = os_name .. "/" .. arch
  if release == nil or digests == nil or digests[key] == nil then
    error(string.format('no pinned JDK for java %s on this host (%s %s)',
                        tostring(version), tostring(os_name), tostring(arch)), 0)
  end

  return {
    url = asset_url(version, release, os_name, arch),
    sha256 = digests[key],
    home = string.format(HOMES[os_name], release.full),
  }
end

return { for_host = for_host }
