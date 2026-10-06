# java

The java toolchain plugin for daukle. It compiles, runs and packages a JVM project with a JDK it provisions itself, generating no build file anywhere, and exports the pinned JDK table that the gradle and maven plugins resolve their runtime from.

## Examples

- [`java-hello-jar`](examples/java-hello-jar): A managed Java project.
- [`java-pinned-classpath`](examples/java-pinned-classpath): A Java project that compiles against a third-party library without a resolver, a repository or a lock file.

## What this plugin is

A `daukle.toolchain` named `java`: it provisions a JDK, compiles, tests and packages, against a
classpath whose every entry is pinned by sha256. A project holds `daukle.toml` and sources and no
build file of any kind.

It uses no Gradle and no Maven. Coordinates are `daukle/maven`'s job, and the two meet at a pinned
jar on disk rather than at a resolver this plugin owns.

## What it has actually been held against

`intisy/libs/java-utils`, a real library rather than a fixture. From eight declared coordinates,
`daukle/maven` resolves twenty modules and this toolchain compiles them to **39 class files, equal
to Gradle's 39**, and reports 6 of 6 tests where Gradle reports 6 of 6.

**"On the same JDK" is load bearing.** Gradle 8.13 on Corretto 17 gives 39 and so does this plugin
told to use 17; on its own default JDK it gives 38, because javac 21 does not emit the synthetic
`$SwitchMap` holder javac 17 emits for an enum `switch`. Neither compilation is wrong. The honest
claim is that the two tools agree when told to use the same compiler, and that is the claim this
repository makes.

## What it does not own is a boundary, not a gap

Coordinates, shading and javadoc are outside this plugin, and that was decided rather than deferred.
A fat jar and a javadoc jar are not built; `java:jar` packages a library with no `Main-Class` as
happily as it packages an application.

Keeping those four separate from "the architecture forbids this" is what made the question of what
daukle is for answerable at all, because a missing mechanism and a drawn boundary need opposite
work.

## A test needs nothing declared, and that cuts both ways

`java:test` runs a JUnit Platform console launcher this plugin pins, and the standalone jar carries
the jupiter api and engine, the vintage engine, JUnit 4, hamcrest, opentest4j and apiguardian.

**So neither JUnit nor hamcrest can tell you whether your resolved test classpath reaches the
compiler**: both arrive with the launcher whatever you declared. A library the launcher does not
carry, assertj or mockito, is the honest check.

## Where the rest is

The keys, the task list, where each source and resource root goes, and why resources are
deliberately off the compile classpath are in this repository's `wiki/index.md`, rendered at
<https://daukle.github.io/guide/>. `AUTHORING.md` is the measured detail for anyone changing the
plugin, and its **What it does not own** section is the boundary above.

## License

[![MIT License](https://img.shields.io/badge/License-MIT-blue.svg)](LICENSE)
