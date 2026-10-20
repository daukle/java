daukle.config.schema = 1
daukle.config.project = "example/probe"
daukle.config.version = "1.0.0"
daukle.config.modules = {}
daukle.config.plugins = {
  java = "./plugins/java",
  probe = { path = "./plugins/probe", requires = { java = { path = "./plugins/java" } } },
}
daukle.config.toolchains = { probe = {} }
