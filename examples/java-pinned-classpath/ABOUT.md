# java-pinned-classpath

A Java project that compiles against a third-party library without a resolver, a repository or a
lock file. Every classpath entry is a url and the sha256 of the bytes that url must serve, written
out in the manifest by hand, and daukle refuses an entry that has no digest.

```console
$ daukle java:run
hello from example.Main
```

## What to look at

**There is no unpinned form.** A `[[toolchains.java.classpath]]` entry carries a `url` and a
`sha256`, and that is the whole vocabulary. An entry without a digest is refused by name rather
than fetched and trusted, which is the same rule every acquisition in daukle obeys: nothing arrives
unverified.

**`as` is a label, not a coordinate.** It is what diagnostics call the jar, so a message names
`slf4j-api 1.7.36` rather than a path into a cache directory. Nothing resolves it and nothing
parses it.

**The jar is cached by digest**, so a second project pinning the same url and digest downloads
nothing, and two projects pinning the same url with *different* digests are two different jars and
are kept apart.

**This is what `daukle/maven` exists to stop you doing.** Writing a url and a digest per jar is
exact and it does not scale: a real library has a transitive closure, and eight declared
coordinates became twenty pinned blocks the first time that was measured here. `daukle/maven`
turns a coordinate into exactly these blocks so that you do not write them. This example is the
layer underneath it, and it is worth seeing once.

## What this example cannot show

**Resolution.** One jar is pinned here and nothing computes it. A real dependency brings its own
dependencies, and working out which versions those are is the whole of what a resolver does. That
is `daukle/maven`, which writes blocks of exactly this shape into a generated file the manifest
includes.

**A version conflict.** With one jar there is nothing to conflict. Gradle settles three of them in
the library this toolchain was measured against, and a hand-written classpath cannot notice that
two entries are the same artifact at different versions.

**Tests.** This example compiles and runs a `main`. `daukle/java` has `java:test` and the example
next door, `java-hello-jar`, is the one that packages a jar.

**A multi-release jar.** An exploded jar is not a jar, and a dependency with versioned classes
loses them with no diagnostic, which is why the classpath keeps archives rather than directories.
Nothing here has one.
