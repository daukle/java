# Authoring notes

`plugin.lua`, `lib/jdks.lua` and `lib/launcher.lua` are the whole plugin. It is published as a
release asset, one uncompressed tar of the three files, and acquired by a `[plugins]` entry naming
`daukle/java@<range>`.

## What this plugin owns

A `java` toolchain that compiles, tests, runs and packages a JVM project, with its resources, using
a JDK it provisions itself. It generates no file anywhere. Everything it writes into the project is
written by `javac`, `jar` or the test launcher into `build/daukle/java/`.

It also exports `lib/jdks`, which is the table of pinned Temurin archives. `gradle` and `maven`
reach it with `daukle.require("java:lib/jdks")` to learn which JDK a host needs; they provision it
themselves, under their own capability. `lib/launcher` is exported on the same terms and is the
pinned JUnit Platform console launcher.

## What it does not own

**Coordinates.** This toolchain takes artifacts that are already pinned by url and sha256; it
resolves nothing, reads no POM and computes no transitive closure. Turning
`group:artifact:version` into a set of urls is what `gradle` and `maven` are for.

**A fat jar, and `mergeServiceFiles`.** `java:jar` packages this project's own classes and bundles
no dependency. Merging several jars correctly needs the resource-merge rules a shaded build has, and
a half-done version produces a jar that runs until a `ServiceLoader` lookup returns the wrong
implementation.

Annotation processors, the module path, javadoc and signing. The design spec's section 3 lists them
with the reason. **Tests left this list on 2026-10-04** and are below.

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
`java:test-compile` and `java:test` only, **never `java:compile`**: a test-only dependency is not
on the main compile classpath, which is `testImplementation` against `implementation` in Gradle's
terms. It reached `java:compile` until 2026-10-04, so a main source could import a test-only
dependency, compile, and fail at run time.

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
file. The archive is written in the derived directory, never in the repository.

Three refusals rather than silence: a missing `sourceRoot` and a `sourceRoot` holding no `.java`
are each an error naming the directory, and a listing larger than the **1 MiB** daukle captures
from a tool (`truncated`) is an error telling the user to name `roots` explicitly.

**The list reaches `javac` through an `@argfile`, and since 2026-10-04 that is true.** It was
written here before it was built: the paths used to be appended to `argv` one per source, and
`daukle.exec` takes at most 256 arguments, so a project of roughly **250 sources could not compile
at all**. `D-80` measured that raising the cap would not have helped, because Windows refuses a
command line over 32767 characters, which at ordinary path lengths is fewer sources still, and
because the real ceiling is a character count that moves when the checkout moves. The argfile makes
the whole list one argument: **400 sources compile, where 253 failed.**

**The quoting rule is not obvious and the obvious one is wrong.** `javac` treats backslash as an
escape INSIDE quotes, so an unescaped `"C:\Users\finn\..."` arrives as `C:Users innAppData...`.
Each path is quoted AND its backslashes doubled, which is the one form that survives both a Windows
path and a path containing a space. On POSIX the doubling matches nothing and the quoting carries
the space. **`jar` does not accept that same file** (`option --file requires an argument`), so the
dialect is per tool and lives here rather than in core, which is why `daukle.write` hands back a
path and formats nothing.

`javac` itself cannot do this: a directory argument is refused, it expands a FLAT glob but refuses
`**`, so a package tree genuinely needs a list.

## Resources, and what a jar contains

`resourceRoot` defaults to `src/main/resources` and `testResourceRoot` to `src/test/resources`.
**Both are optional and silently absent**, which is the asymmetry worth knowing: a missing
`sourceRoot` is an error, because a project with no sources is a mistake, and a missing resource
directory is the common case.

**Resources are never copied.** The directory goes on the classpath as itself and into a jar as a
second `-C` group, so `java:run` and `java:test` see a resource exactly as a packaged consumer
would. Nothing is staged into `classes/`, which also means a plugin needs no ability to write
files.

| root | compile | run | jar | test | sources jar |
| --- | --- | --- | --- | --- | --- |
| `sourceRoot` | compiled | via `classes/` | via `classes/` | via `classes/` | **packaged** |
| `resourceRoot` | no | **classpath** | **packaged** | **classpath** | **packaged** |
| `testResourceRoot` | no | no | no | **classpath** | no |

**Resources are deliberately not on the compile classpath.** `javac` does not read them, and
putting them there lets a source resolve a class out of a resource directory, which is a confusing
way to make a build pass. **A test fixture never reaches the jar**, which is why
`testResourceRoot` stops at the test classpath.

**`main` is optional for `java:jar` and required for `java:run`.** With no `main` the jar carries
no `Main-Class`, exactly as Gradle's does, because a library has no entry point. That is `D-74`'s
finding applied one task over: `java:compile` stopped requiring `roots` for the same reason and
`java:jar` went on charging for it until 2026-10-04.

`java:sources-jar` packages the source root and, when present, the resource root, as
`<artifact>-sources.jar`. It needs no compilation and depends on nothing. **It does not meet the
argument ceiling** in "How sources are found", because `jar -C dir .` is a fixed argument count
however large the tree.

**Presence is measured by running `jar`, not by asking.** The sandbox has no directory verb, so the
plugin probes with `jar --create -C <dir> .` under `check = false` and reads the exit code. The
probe is not optional: `jar --create -C classes . -C nosuchdir .` fails the whole invocation, so an
absent resource root must be omitted rather than passed and tolerated.

## Running a project's tests

`java:test-compile` compiles `testSourceRoot`, defaulting to `src/test/java`, into `test-classes/`
beside `classes/`. They are kept apart because `java:jar` packages `-C classes .` whole and a test
class in there would ship in the artifact. `java:test` then runs the JUnit Platform console
launcher over `test-classes/`.

**A project declares nothing about the launcher and needs nothing in `testClasspath` to write a
JUnit 5 test.** `lib/launcher.lua` pins `junit-platform-console-standalone`, which carries the
jupiter API, the jupiter engine, the vintage engine, `opentest4j` and `apiguardian` in one jar. It
is pinned here for the reason the default JDK version is: a given plugin version always runs the
same launcher. A project that wants a different JUnit puts it in `testClasspath`, where it lands
**before** the launcher on the compile classpath and wins.

Test sources are **always enumerated** and there is no `testRoots` or `testMain`. `roots` and
`main` exist because a program has entry points a human knows; a test tree's entry points are every
`@Test` in it.

**`--fail-if-no-tests` is passed always and is not configurable.** Without it the launcher exits 0
on a tree it discovered nothing in, so `java:test` would be green on a project whose tests reach
nothing. The launcher's exit codes are mapped rather than reported raw: 1 is a failing test, 2 is
nothing discovered under `testSourceRoot`.

`testArgs` appends arguments to the launcher, which is how a project reaches `--include-tag`,
`--select-class`, `--reports-dir` or `--details=tree` without this plugin modelling any of them.

## Tests

`test/run.sh` runs every directory under `test/cases/` against a real daukle.

- a case with `expect-error.txt` must fail `daukle sync` with a message carrying that clause
- a case with `task.txt` runs `daukle <task>`. It carries exactly one of `produces.txt`, requiring
  every listed path to exist and be non-empty afterwards, or `expect-task-error.txt`, requiring the
  task to fail carrying that clause; the two are mutually exclusive and a case carrying both fails
- a case may add `contains.txt` beside `produces.txt`, each line a produced path and a literal that
  must appear in it. **It is for archive ENTRY NAMES**: a zip stores them uncompressed in its
  central directory, so grepping the archive finds them with no `unzip` on the runner. **Entry
  CONTENTS are deflated and are not greppable**, which is why nothing asserts on a manifest;
  measured both ways
- a case with `expected/` must sync cleanly and match every file byte for byte, and is synced twice
- a case whose `expected/` or `produces.txt` lists nothing is a failure, not a pass

**Task cases run by default on Linux only.** They provision a real JDK, and one download per CI run
is the trade. Set `DAUKLE_JAVA_E2E=1` to run them on Windows or macOS. The test cases also fetch
the 3 MB launcher, which is small enough beside the JDK's 331 MB to need no gate of its own.

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

**`testArgs` reaches the launcher and a case proves it.** `passes-test-args-to-the-launcher` passes
`--details=tree` and asserts the per-test name appears, which the summary default does not print.
Dropping the `append_args` call reddens exactly that case.

**No case runs a JUnit 4 test.** The pinned launcher carries the vintage engine, so a JUnit 4 test
on the classpath is discovered, but nothing here asserts it and the plugin promises nothing about
it.

**No case has more test sources than fit in one `javac` invocation**, which is the ceiling
"How sources are found" names. Every case here is one or two files.

**Nothing asserts that a jar's manifest LACKS `Main-Class`.** A manifest is deflated, so the
`contains.txt` trick cannot read it, and no case unpacks a jar. What is asserted is that
`java:jar` SUCCEEDS with no `main`, which is what used to fail; the absence of the attribute is
`jar`'s own behaviour and is taken on trust.

**No case has a resource whose name collides with a class file path.** Two `-C` groups writing the
same entry is a real packaging hazard and this plugin neither detects nor resolves it.

**No case reads a resource from a jar through a CONSUMER.** A resource being in the archive is not
the same as a dependent project loading it, and nothing here builds that chain.

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
