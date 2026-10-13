local jdks = daukle.require("lib/jdks")
local settings = daukle.require("lib/settings")

local function provision_jdk(context)
  local version = settings.version_of(context)
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

--[[ One argument per source would cap a project at about 250 files, and
     raising that would not help: Windows refuses a command line over 32767
     characters, which at ordinary path lengths is fewer sources still. An
     argfile turns the whole list into one argument. D-80.

     javac treats backslash as an escape INSIDE quotes, so an unescaped
     "C:\Users\..." arrives as "C:Users...". Quoting and doubling the
     backslashes is the one form that survives both a Windows path and a path
     containing a space; on POSIX the doubling matches nothing and the quoting
     is what carries the space. ]]
local function source_argfile(paths, name)
  local lines = {}
  for index = 1, #paths do
    lines[index] = '"' .. string.gsub(paths[index], "\\", "\\\\") .. '"'
  end
  return "@" .. daukle.write{ path = name, text = table.concat(lines, "\n") .. "\n" }
end

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

return {
  provision_jdk = provision_jdk,
  executable = executable,
  source_argfile = source_argfile,
  enumerated_sources = enumerated_sources,
  readable_directory = readable_directory,
  resource_directories = resource_directories,
}
