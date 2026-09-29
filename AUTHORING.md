# Authoring notes

`plugin.lua` and `lib/jdks.lua` are the whole plugin. It is published as a release asset, one
uncompressed tar of both files, and acquired by a `[plugins]` entry naming `daukle/java@<range>`.

## What this plugin owns

A `java` toolchain that compiles, runs and packages a JVM project with a JDK it provisions itself.
It generates no file anywhere. Everything it causes to exist is written by `javac` or `jar` into
`build/daukle/java/`.

It also exports `lib/jdks`, which is the table of pinned Temurin archives. `gradle` and `maven`
reach it with `daukle.require("java:lib/jdks")` to learn which JDK a host needs; they provision it
themselves, under their own capability.

## What it does not own

External dependencies on a classpath. `daukle.provision` unpacks an archive and does not keep it,
and a classpath entry is the archive, so there is no mechanism that fits. A project under this
toolchain compiles against the JDK and its own sources. Coordinates are what `gradle` and `maven`
are for.

Tests, annotation processors, the module path, javadoc and signing. The design spec's section 3
lists them with the reason.

## Limits a user will meet

**A class reached only reflectively or through `ServiceLoader` is not compiled** unless it is named
in `roots`. `javac -sourcepath` compiles what is reachable from the roots it is given, and nothing
here detects a class that is not.

**A class name may use only ASCII identifiers.** `javac` accepts more; this plugin's validation
does not, because Lua's `%a` is ASCII-only under the sandbox's locale.

**`version` must be an exact major version.** `>=17` is refused. This plugin pins its JDKs and does
not match ranges, because doing so would mean a semver implementation in Lua.

**The first build downloads roughly 331 MB and reports no progress while it does.** That is daukle's
open risk, not this plugin's, and it is named here because this is where a user meets it.

## Tests

`test/run.sh` runs every directory under `test/cases/` against a real daukle.

- a case with `expect-error.txt` must fail `daukle sync` with a message carrying that clause
- a case with `task.txt` runs `daukle <task>`; with `produces.txt` every listed path must exist and
  be non-empty afterwards, and with `expect-task-error.txt` the task must fail carrying that clause
- a case with `expected/` must sync cleanly and match every file byte for byte, and is synced twice
- a case whose `expected/` or `produces.txt` lists nothing is a failure, not a pass

**Task cases run by default on Linux only.** They provision a real JDK, and one download per CI run
is the trade. Set `DAUKLE_JAVA_E2E=1` to run them on Windows or macOS.

**Do not use `javaw` as a broken-tool mutation on Windows.** Temurin's Windows JDK ships
`javaw.exe` beside `java.exe`, and with output redirected it runs a class identically, so the swap
proves nothing. `javac` is the tool that is present and wrong.

## Coverage this repository does not have, stated rather than implied

**The Windows `.exe` suffix is not covered by the default run.** Dropping it from `executable`
turns no case red on Linux. Running the suite with `DAUKLE_JAVA_E2E=1` on Windows is what covers it.

**The macOS `Contents/Home` path is not covered by the default run**, for the same reason and with
the same remedy.

**The digests in `lib/jdks.lua` are covered only by the task cases**, so a wrong digest for a
platform whose task cases are skipped is not detected here. It fails loudly at provisioning time on
the machine that first uses it.

**A user's `compileArgs` can send output into the repository.** `javac` honours the last `-d`, so
`compileArgs = ["-d", "../../.."]` writes class files outside `build/daukle/java/`. This plugin's
"nothing is written into the repository" property is therefore a property of what the plugin itself
passes, not a boundary it enforces against the manifest. It is the user's own manifest, so this is a
sharp edge rather than a hole, and it is named here rather than left for someone to discover.

**Nothing asserts the absence of output outside the derived directory.** The task cases assert that
the expected files exist and are non-empty. A `javac` invocation that wrote to the right place AND
somewhere else would still pass every case.

**No case runs a task twice.** Every sync case is run twice to prove that applying twice equals
applying once, and task cases get no equivalent, so a task that is not idempotent would not be
caught here.

**`for_host`'s missing-digest branch is unreachable by any test.** The guard refuses a version that
has a release entry but no digest for the host, which is exactly one combination: java 17 on
windows/aarch64, the one build Temurin does not publish. `for_host` receives the real host and the
host is not injectable through a manifest, so no case can reach it on any other machine. The guard is
kept regardless: without it, a windows/aarch64 user asking for java 17 would be handed
`sha256 = nil` and refused by daukle with a message about a missing digest rather than one naming
their host and version.

## Conventions this repository is held to

**Every message uses `error(msg, 0)`**, so Lua's `plugin.lua:<line>:` prefix is suppressed and a
message reads as daukle's. A test asserting on a message must assert on a clause, never on a token.

**The version constraint is read in exactly one function**, `version_of`. `generate` receives it as
`config.version` and a task's `run` receives it as `toolchain.version`, with
`toolchain.config.version` absent. Reading it in one place is what stops that asymmetry becoming two
behaviours.

**`.github/workflows/test.yml` pins `extra_ref: development`** because `daukle/daukle`'s `main` has
no managed mode. Remove the pin only in the change that promotes managed mode to `main`.
