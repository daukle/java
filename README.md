# java

The java toolchain plugin for daukle. It compiles, runs and packages a JVM project with a JDK it provisions itself, generating no build file anywhere, and exports the pinned JDK table that the gradle and maven plugins resolve their runtime from.

## Examples

- [`java-hello-jar`](examples/java-hello-jar): A managed Java project.
- [`java-pinned-classpath`](examples/java-pinned-classpath): A Java project that compiles against a third-party library without a resolver, a repository or a lock file.

## License

[![MIT License](https://img.shields.io/badge/License-MIT-blue.svg)](LICENSE)
