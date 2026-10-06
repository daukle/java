# java-hello-jar

A managed Java project. The repository holds `daukle.toml` and `src/main/java/` and **no build
file**: no Gradle, no Maven, no wrapper, no `pom.xml`. daukle downloads a JDK, verifies it against a
digest the plugin pins, and runs `javac` and `jar` out of it.

```console
$ daukle java:run
hello from daukle
```

`daukle java:jar` packages `build/daukle/java/example-java-hello-jar.jar`, and `daukle tasks` lists
the three tasks the plugin declares and their order. Only the `console` block is executed, so the
JDK-heavy tasks are named here rather than run a second and third time for no new information.

## What to look at

**This copy points at the working tree, and a real project names a coordinate.** The manifest here
says `java = "./plugins/java"` so that the suite in this repository tests the plugin as it stands;
a red example then means a real defect rather than a stale release. In your own project the two
lines are a pinned resolver and a coordinate:

```toml
[resolvers.github]
url = "https://raw.githubusercontent.com/daukle/daukle/<commit>/plugins/github-releases.lua"
sha256 = "..."

[plugins]
java = { resolver = "github", coordinate = "daukle/java@^1.1.0" }
```

Nothing vendors a copy of the plugin either way.

**`version` may be left out.** It is kept here because this example also pins what it exercises; a
project that leaves it out gets 21, which the plugin pins and moves only with its own release.

**`main` is a class name, not a path.** The plugin turns it into
`src/main/java/com/example/Main.java` and hands `javac` a source path, so there is no source list to
maintain.

**`version = "21"` is an exact major version.** `">=17"` is refused. The plugin ships a table of
pinned JDK archives with their published digests, and matching a range would mean a semver
implementation in Lua.

## What this example cannot show

**A classpath**, which this example does not use although the toolchain has one. The example next
door, `java-pinned-classpath`, is the one that does: `classpath` and `testClasspath` take pinned
entries, each a url and a sha256, and it compiles and runs against one.

What neither of them shows is **resolution**: a coordinate like `com.example:thing:1.2` becoming a
url, a digest and a transitive closure. That is `daukle/maven`, which writes classpath blocks of
exactly that shape into a generated file the manifest includes, so that nobody writes them by hand.

**A class reached only reflectively or through `ServiceLoader`** is not compiled unless you name it
in `roots`. `javac -sourcepath` compiles what is reachable from the roots it is given.

## The first run is slow

Roughly 331 MB of JDK, with no progress reported while it downloads. It is cached per digest
afterwards, shared by every project on the machine that pins the same JDK.

## The one file that is a harness input rather than part of the example

`needs-tools` marks this example as one that provisions real tools, which the harness skips unless
`DAUKLE_EXAMPLE_E2E=1` is set. CI sets it on every runner. The `console` block above is **executed**
rather than decorative: its `$ ` line is run and the line beneath it must appear in the output, so
the command and its result cannot drift apart the way a separate expectation file did.

**There is no committed executable here, and nothing is missing.** `java:run` really does build and
run the program; `build/` is gitignored, which is the only reason you cannot see the result in the
repository.
