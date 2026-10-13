# daukle/java

The Java toolchain. It provisions a JDK, compiles, tests, and packages, against a classpath whose
every entry is pinned by sha256. A project holds `daukle.toml` and sources and no build file.

## Declaring it

```toml
[plugins]
java = "daukle/java@^1"

[toolchains.java]
sourceRoot = "src/main/java"
release = "17"
main = "example.Main"
```

## Keys

| key | meaning |
| --- | --- |
| `version` | which JDK to provision: `"17"`, `"21"` or `"25"`, exact. Moves only with a release of this plugin |
| `release` | the Java source and target level. **This is how you target an OLD Java**, not an old `version` |
| `sourceRoot` | defaults to `src/main/java` |
| `resourceRoot` | defaults to `src/main/resources` |
| `testSourceRoot` | defaults to `src/test/java` |
| `testResourceRoot` | defaults to `src/test/resources` |
| `main` | the class `java:run` runs, and the jar's `Main-Class` |
| `entries` | per-entry blocks keyed by name; each needs a `main` and may add `runArgs`, and each gets a `java:run-<name>` task |
| `roots` | compile only these classes and what they reach; omit to compile every source |
| `classpath`, `testClasspath` | pinned entries, normally written by `daukle/maven` |
| `compileArgs`, `runArgs`, `jarArgs`, `testArgs` | passed straight through |

## Tasks

`java:compile`, `java:test-compile`, `java:test`, `java:jar`, `java:sources-jar`, `java:run`, and
one `java:run-<name>` per declared entry.

## Several runnable classes

`main` names one class. A project with more than one runnable class names the rest under
`entries`, and each gets its own task:

```toml
[toolchains.java]
main = "com.example.Main"

[toolchains.java.entries.cheapest]
main = "com.example.CheapestExample"

[toolchains.java.entries.display-demo]
main = "com.example.DisplayDemo"
runArgs = ["--fullscreen"]
```

`daukle tasks` then lists `java:run-cheapest` and `java:run-display-demo` beside `java:run`, which
still runs `main`. With entries declared and no `main`, `java:run` tells you which entry tasks
exist instead of asking for a key you left out on purpose. A project-wide `runArgs` applies to
every entry, and an entry's own are appended after it.

## Tests need nothing declared

`java:test` runs the JUnit Platform console launcher, which this plugin pins. The standalone jar
carries the jupiter api and engine, the vintage engine, **JUnit 4 and hamcrest**, opentest4j and
apiguardian, so a project writes a test without declaring anything at all.

**That also means neither JUnit nor hamcrest can tell you whether your resolved test classpath is
reaching the compiler**: both come from the launcher. A library the launcher does not carry, such
as assertj or mockito, is the honest check.

`--fail-if-no-tests` is always passed: the launcher exits 0 on a tree it found nothing in, so
without it a project whose tests reach nothing would be green.

## Where each root goes

| root | compile | test | jar |
| --- | --- | --- | --- |
| `sourceRoot` | compiled | via `classes/` | packaged |
| `resourceRoot` | no | classpath | packaged |
| `testSourceRoot` | no | compiled | no |
| `testResourceRoot` | no | classpath | no |

Resources are deliberately **not** on the compile classpath.

## What it does not own

Coordinates, shading, and javadoc. Coordinates are `daukle/maven`'s; a fat jar and a javadoc jar
are not built. `java:jar` packages a library with no `Main-Class` as happily as an application.
