# java-several-entry-points

Three runnable classes in one project, each with its own task, from a project holding `daukle.toml`
and `src/main/java/` and **no `build.gradle`, no wrapper and no Gradle anywhere**. `main` keeps its
meaning and `entries` names the rest.

```console
$ daukle java:run
Main ran in default mode
$ daukle java:run-report
ReportExample ran in default mode
$ daukle java:run-cleanup
CleanupExample ran in quiet mode
```

That third line is the point: `runArgs` on an entry reaches that entry and nothing else. The other
two print `default`, because they never see it.

**`runArgs` is JVM-level, not program arguments**, which is the same edge the project-wide key has
and is worth knowing before writing one. They are passed before the main class, so a system
property works and a flag your `main` expects to find in `args` does not arrive at all. There is no
program-argument mechanism in this plugin. The first draft of this example passed `--dry-run`
expecting it to reach `args`; **that is a real JDK 21 launcher option that loads every class and
then skips `main`**, so the example exited 0 and printed nothing.

| task | what it runs |
| --- | --- |
| `daukle java:run` | `com.example.Main`, named by the project-wide `main` |
| `daukle java:run-report` | `com.example.ReportExample` |
| `daukle java:run-cleanup` | `com.example.CleanupExample`, with `-Dcleanup.mode=quiet` |

## What to look at

**`java:run` still runs `main` and nothing became ambiguous.** `main` is the declared default, so
adding entries does not change what the plain verb does. Leave `main` out and `java:run` tells you
which entry tasks exist instead of demanding a key you omitted deliberately.

**The task names are `java:run-<name>`, not `java:<name>`.** `daukle/cmake` set that convention: a
buildable thing is `cmake:<target>` and a runnable one `cmake:run-<target>`, and an entry point is
only ever runnable.

**A task is REGISTERED, not dispatched.** A daukle task takes no arguments, so three runnable
classes need three registered tasks rather than one task and a flag. `daukle tasks` lists all
three, which is what makes them discoverable without reading this file.

**Nothing scanned the source tree for `main()` methods.** The plugin cannot probe a path without
dying on the project that lacks it, because `pcall` is removed from its sandbox and a read raises.
So entries are declared. Three blocks for three classes is the honest cost, and it is why a project
with eleven examples writes eleven blocks.

## What this example cannot show

**A second entry point that needs build LOGIC.** The one project in the tree this feature was
measured against that really declares two Gradle entry points has a second one carrying
`standardInput`, an environment value read from the host and an `if` over the host OS. None of that
is data, and daukle's answer to it is a manifest task's `run = { tool, args }` rather than anything
here.

**A per-entry classpath, JDK, source root or jar.** Each is refused by name. Two entries needing
two JDKs is one project needing two toolchains, and one jar per entry would be N artifacts, which
is a different task.

**An entry changing the jar.** `java:jar` reads `Main-Class` from the project-wide `main` or omits
it for a library. Entries contribute nothing to it, and a fat jar is served through
`daukle/gradle`.

**Entries narrowing what is compiled.** This project names no `roots`, so its whole tree compiles,
which already holds all three classes. Entries are appended to a narrowed build rather than
creating one, so declaring them can never compile less than before.

**A project whose manifest is Lua.** Entry tasks are registered from a chunk that reads
`daukle.toml`, and a Lua manifest is one `daukle.parse` refuses, so such a project keeps `java:run`
and gains no entry tasks. A test case covers it; an example cannot, because the console block above
is what a reader would type and the difference is in what is absent.

## The one file that is a harness input rather than part of the example

`needs-tools` marks this example as one that provisions real tools, which the harness skips unless
`DAUKLE_EXAMPLE_E2E=1` is set. CI sets it on every runner. The `console` block above is **executed**
rather than decorative: each `$ ` line is run and the lines beneath it must appear in the output.

## The first run is slow

Roughly 190 MB for a JDK, cached per digest afterwards and shared by every project on the machine
that pins the same one. Nothing else is downloaded: this example declares no dependency.
