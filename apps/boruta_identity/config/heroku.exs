use Mix.Config

config :boruta_identity, BorutaIdentity.Repo,
  ssl: true,
  url: System.get_env("DATABASE_URL"),
  pool_size: String.to_integer(System.get_env("POOL_SIZE") || "10")

config :boruta_identity, Boruta.Accounts,
  secret_key_base: System.get_env("SECRET_KEY_BASE")