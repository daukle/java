# Authoring notes

`plugin.lua` and `lib/jdks.lua` are the whole plugin. It is published as a release asset, one
uncompressed tar of both files, and acquired by a `[plugins]` entry naming `daukle/java@<range>`.

## What this plugin owns

A `java` toolchain that compiles, runs and packages a JVM project with a JDK it provisions itself.
It generates no file anywhere. Everything it writes into the project is written by `javac` or `jar`
into `build/daukle/java/`.

It also exports `lib/jdks`, which is the table of pinned Temurin archives. `gradle` and `maven`
reach it with `daukle.require("java:lib/jdks")` to learn which JDK a host needs; they provision it
themselves, under their own capability.

## What it does not own

**Coordinates.** This toolchain takes artifacts that are already pinned by url and sha256; it
resolves nothing, reads no POM and computes no transitive closure. Turning
`group:artifact:version` into a set of urls is what `gradle` and `maven` are for.

**A fat jar, and `mergeServiceFiles`.** `java:jar` packages this project's own classes and bundles
no dependency. Merging several jars correctly needs the resource-merge rules a shaded build has, and
a half-done version produces a jar that runs until a `ServiceLoader` lookup returns the wrong
implementation.

Tests, annotation processors, the module path, javadoc and signing. The design spec's section 3
lists them with the reason.

## The classpath

A dependency is declared as a pinned artifact, and repeated for as many as the project has:

```toml
[[toolchains.java.classpath]]
url = "https://repo1.maven.org/maven2/org/slf4j/slf4j-api/2.0.13/slf4j-api-2.0.13.jar"
sha256 = "..."
as = "slf4j-api 2.0.13"
```

`url` and `sha256` are both required: a classpath entry is pinned like every other acquisition and
there is no unpinned form. `as` is an optional label for the acquisition report. Entries reach
`java:compile` and `java:run` in **declaration order**, which is preserved because classpath order
decides which of two copies of a class wins. `testClasspath` takes the same fields and reaches
`java:compile` only.

**The jar is kept as a jar and never unpacked**, and that is the whole point rather than an
implementation detail. An exploded jar is not a jar: a multi-release dependency serves its
versioned classes as a file on the classpath and its **base** classes as the same content in a
directory, with no error and no warning, and signed jars and sealed packages lose their meaning the
same way. Measured both ways; see `2026-10-02-java-classpath-design.md`.

**An entry with `path` is a distribution archive rather than a single jar.** It is provisioned and
unpacked, and `path` names the directory inside it that belongs on the classpath:

```toml
[[toolchains.java.classpath]]
url = "https://example.invalid/some-distribution.tar.gz"
sha256 = "..."
path = "lib"
```

The JVM expands its own `lib/*` wildcard, so a directory of jars needs no enumeration. Use this form
only for an archive that really is a distribution: a single jar given a `path` would be unpacked,
which is what the paragraph above warns about.

**A producer can hand its artifact over instead**, in its own module block for this toolchain, with
the same `url` and `sha256` fields. That is the same shape `daukle/c` receives and writes into a
`FetchContent` block; here the two fields are fetched rather than delegated.

## Limits a user will meet

**`roots` NARROWS what is compiled; leaving it out compiles everything.** A toolchain naming
neither `roots` nor `main` compiles every `.java` under `sourceRoot`, which is what a library needs:
its entry points are its consumers and none of them exists at compile time. Gradle's `java` plugin
compiles the whole tree with no configuration, and a replacement that charges for what the original
gives away is not one. `main` is still required by `java:run` and `java:jar`, which need an entry
point.

**When you DO name `roots`, a class no root reaches is not compiled, and nothing here reports it.**
`javac -sourcepath` compiles what is reachable from the roots it is given, so a class reached only
reflectively or through `ServiceLoader` is absent from the output and the first symptom is a
`NoClassDefFoundError` in a consumer. **This plugin cannot warn**: the sandbox gives a plugin no
log channel, only `error()`, and erroring would break the legitimate case of narrowing on purpose.
Leaving `roots` out is the remedy.

**A class name may use only ASCII identifiers.** `javac` accepts more; this plugin's validation
does not, because Lua's `%a` is ASCII-only under the sandbox's locale.

**`version` must be an exact major version.** `>=17` is refused. This plugin pins its JDKs and does
not match ranges, because doing so would mean a semver implementation in Lua.

**`version` may be left out, and then it is 21.** The default is pinned in this plugin and moves
only with a release of it, which is what makes having one compatible with daukle's reproducibility
stance at all: a given plugin version always provisions the same JDK, so two machines holding one
`daukle.toml` and one plugin pin cannot disagree. It is never read from the host and never follows
whatever is newest. **Raising it is a breaking change** for every project that left the version out,
so it moves with a major release and not with a patch. The acquisition report always names the
version that was actually provisioned, so a project on the default can still see which JDK it got.

**The first build downloads roughly 331 MB and reports no progress while it does.** That is daukle's
open risk, not this plugin's, and it is named here because this is where a user meets it.

## How sources are found

With no `roots` and no `main`, the plugin enumerates the source tree itself, using the JDK it has
already provisioned:

```
jar --create --file .daukle-sources.jar -C <sourceRoot> .
jar --list   --file .daukle-sources.jar
```

`jar` walks a tree recursively and prints it, identically on every platform. **This is the only
enumeration available to a plugin**: the sandbox has no directory verb and `daukle.read` takes one
file. The archive is written in the derived directory, never in the repository, and the resulting
list is passed to `javac` through an `@argfile`, which also avoids the Windows command-line length
limit a large tree would hit.

Two refusals rather than silence: a `sourceRoot` holding no `.java` is an error naming the
directory, and a listing larger than the **1 MiB** daukle captures from a tool (`truncated`) is an
error telling the user to name `roots` explicitly. That cap is roughly seventeen thousand paths.

`javac` itself cannot do this: a directory argument is refused, it expands a FLAT glob but refuses
`**`, so a package tree genuinely needs a list.

## Tests

`test/run.sh` runs every directory under `test/cases/` against a real daukle.

- a case with `expect-error.txt` must fail `daukle sync` with a message carrying that clause
- a case with `task.txt` runs `daukle <task>`. It carries exactly one of `produces.txt`, requiring
  every listed path to exist and be non-empty afterwards, or `expect-task-error.txt`, requiring the
  task to fail carrying that clause; the two are mutually exclusive and a case carrying both fails
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

**`jarArgs` and `runArgs` have the same edge, and `runArgs` is now the expensive one.** Measured
with the JDK rather than reasoned: `jar --create --file first.jar --file second.jar` writes
`second.jar`, so the last `--file` wins exactly as the last `-d` does, and a `jarArgs` naming one
decides where the artifact lands. `java` honours the last `-cp` the same way, so
`runArgs = ["-cp", "classes"]` silently replaces the classpath this plugin built and **every
declared dependency disappears from the run**, with no error: the first class that resolved only
through a dependency fails at the point it is loaded, which may be nowhere near the start. Add to a
classpath by declaring another `[[toolchains.java.classpath]]` entry, never by passing `-cp`.

**Nothing asserts the absence of output outside the derived directory.** The task cases assert that
the expected files exist and are non-empty. A `javac` invocation that wrote to the right place AND
somewhere else would still pass every case.

**No case runs a task twice.** Every sync case is run twice to prove that applying twice equals
applying once, and task cases get no equivalent, so a task that is not idempotent would not be
caught here.

**`for_host`'s missing-digest branch is unreachable by any test.** The guard refuses any host and
version combination the table does not hold, which includes every architecture daukle reports as
`x86` and every unusual platform it reports as `linux`, on both java versions this plugin pins. Of
the combinations this plugin means to support, windows/aarch64 on java 17 is the only one Temurin
simply does not build. `for_host` receives the real host and the host is not injectable through a
manifest, so no case can reach the guard on any machine this suite runs on. The guard is kept
regardless: without it, a host the table does not hold would be handed `sha256 = nil` and refused by
daukle with a message about a missing digest rather than one naming their host and version.

## Conventions this repository is held to

**Every message uses `error(msg, 0)`**, so Lua's `plugin.lua:<line>:` prefix is suppressed and a
message reads as daukle's. A test asserting on a message must assert on a clause, never on a token.

**The version constraint is read in exactly one function**, `version_of`. `generate` receives it as
`config.version` and a task's `run` receives it as `toolchain.version`, with
`toolchain.config.version` absent. Reading it in one place is what stops that asymmetry becoming two
behaviours.

**`.github/workflows/test.yml` pins `extra_ref: development`** because `daukle/daukle`'s `main` has
no managed mode. Remove the pin only in the change that promotes managed mode to `main`.
