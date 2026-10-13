-- No daukle.toml beside this file, which core accepts: with no primary
-- manifest it falls back to the overlay, so daukle.manifest names a Lua file
-- and daukle.parse refuses to run one. Parsing it unguarded was fatal on
-- EVERY command, not merely on the per-entry tasks that want it, which is the
-- crash daukle/cmake@1.4.0 shipped.
daukle.config.schema = 1
daukle.config.project = "example/app"
daukle.config.version = "1.0.0"
daukle.config.modules = {}
daukle.config.plugins = { java = "./plugins/java" }
daukle.config.toolchains = {
  java = {
    version = "21",
    main = "com.example.Main",
    entries = {
      cheapest = { main = "com.example.CheapestExample" },
    },
  },
}
