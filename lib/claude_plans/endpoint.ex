defmodule ClaudePlans.Endpoint do
  use Phoenix.Endpoint, otp_app: :claude_plans

  @session_options [
    store: :cookie,
    key: "_claude_plans_key",
    signing_salt: "claude_plans"
  ]

  socket("/live", Phoenix.LiveView.Socket, websocket: [connect_info: [session: @session_options]])

  if Mix.env() == :dev do
    socket("/phoenix/live_reload/socket", Phoenix.LiveReloader.Socket)
  end

  if Mix.env() == :dev do
    plug(Tidewave)

    plug(Phoenix.LiveReloader)
    plug(Phoenix.CodeReloader)
  end

  plug(Plug.Parsers,
    parsers: [:urlencoded, :multipart, :json],
    pass: ["*/*"],
    json_decoder: Jason
  )

  plug(Plug.Session, @session_options)
  plug(ClaudePlans.Web.Router)
end
