import Config

# Configure the database for development
config :shoppollama, Shoppollama.Repo,
  database: Path.expand("../shoppollama_dev.db", __DIR__),
  pool_size: 5,
  stacktrace: true,
  show_sensitive_data_on_connection_error: true

# Configure the endpoint for development
config :shoppollama, ShoppollamaWeb.Endpoint,
  http: [ip: {127, 0, 0, 1}, port: 4000],
  check_origin: false,
  code_reloader: true,
  debug_errors: true,
  secret_key_base: "dev_secret_key_base_that_is_at_least_64_bytes_long_for_cookie_signing",
  watchers: [
    esbuild: {Esbuild, :install_and_run, [:shoppollama, ~w(--sourcemap=inline --watch)]},
    tailwind: {Tailwind, :install_and_run, [:shoppollama, ~w(--watch)]}
  ]

# Watch static and templates for browser reloading
config :shoppollama, ShoppollamaWeb.Endpoint,
  live_reload: [
    patterns: [
      ~r"priv/static/(?!uploads/).*(js|css|png|jpeg|jpg|gif|svg)$",
      ~r"lib/shoppollama_web/(controllers|live|components)/.*(ex|heex)$"
    ]
  ]

# Note: cache_static_manifest is only needed for production
# Remove it for dev to avoid the missing manifest warning

# Configures Swoosh API Client
config :swoosh, api_client: Swoosh.ApiClient.Req

# Disable Swoosh Local Memory Storage
config :swoosh, local: false

# Do not print debug messages in production
config :logger, level: :debug

# Runtime production configuration, including reading
# of environment variables, is done on config/runtime.exs.
