defmodule ClaudePlans.Web.Layouts do
  @moduledoc false
  use Phoenix.Component
  import Phoenix.HTML, only: [raw: 1]

  # Compile-time asset embedding (Clarity pattern)
  @external_resource css_path = Path.expand("css/app.css", __DIR__)
  @css File.read!(css_path)

  phoenix_js_paths =
    for app <- ~w(phoenix phoenix_html phoenix_live_view)a do
      path = Application.app_dir(app, ["priv", "static", "#{app}.js"])
      Module.put_attribute(__MODULE__, :external_resource, path)
      path
    end

  @phoenix_js for(path <- phoenix_js_paths, do: File.read!(path)) |> Enum.join("\n")
  @external_resource js_path = Path.expand("js/app.js", __DIR__)
  @app_js File.read!(js_path)

  defp css, do: @css
  defp phoenix_js, do: @phoenix_js
  defp app_js, do: @app_js

  def root(assigns) do
    assigns =
      assigns
      |> assign(:css, css())
      |> assign(:phoenix_js, phoenix_js())
      |> assign(:app_js, app_js())

    ~H"""
    <!DOCTYPE html>
    <html lang="en">
      <head>
        <meta charset="utf-8" />
        <meta name="viewport" content="width=device-width, initial-scale=1" />
        <meta name="csrf-token" content={Phoenix.Controller.get_csrf_token()} />
        <title>Claude Browser</title>
        {raw("<style>" <> @css <> "</style>")}
      </head>
      <body>
        {@inner_content}
        {raw("<script>" <> @phoenix_js <> "</script>")}
        {raw("<script>" <> @app_js <> "</script>")}
      </body>
    </html>
    """
  end
end
