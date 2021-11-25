defmodule BorutaIdentityWeb.Endpoint do
  use Phoenix.Endpoint, otp_app: :boruta_identity

  @session_options [
    store: :cookie,
    key: "_boruta_web_key",
    signing_salt: "OCKBuS86"
  ]

  # Serve at "/" the static files from "priv/static" directory.
  #
  # You should set gzip to true if you are running phx.digest
  # when deploying your static files in production.
  plug Plug.Static,
    at: "/accounts",
    from: :boruta_identity,
    gzip: false,
    only: ~w(css fonts images js favicon.ico robots.txt)

  # Code reloading can be explicitly enabled under the
  # :code_reloader configuration of your endpoint.
  #
  # disabled since we cannot forward socket behind boruta_web proxy
  #
  # if code_reloading? do
  #   socket "/phoenix/live_reload/socket", Phoenix.LiveReloader.Socket
  #   plug Phoenix.LiveReloader
  #   plug Phoenix.CodeReloader
  #   plug Phoenix.Ecto.CheckRepoStatus, otp_app: :boruta_identity
  # end

  plug Plug.RequestId
  plug Plug.Telemetry, event_prefix: [:phoenix, :endpoint]

  plug Plug.Parsers,
    parsers: [:urlencoded, :multipart, :json],
    pass: ["*/*"],
    json_decoder: Phoenix.json_library()

  plug Plug.MethodOverride
  plug Plug.Head
  plug Plug.Session, @session_options
  plug BorutaIdentityWeb.Router
end
