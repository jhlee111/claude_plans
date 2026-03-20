defmodule ClaudePlans.Web.Layouts do
  @moduledoc false
  use Phoenix.Component
  import Phoenix.HTML, only: [raw: 1]

  # Compile-time asset embedding (Clarity pattern)
  @external_resource css_path = Path.expand("css/app.css", __DIR__)
  @css File.read!(css_path)

  phoenix_js_paths =
    for app <- ~w(phoenix phoenix_live_view)a do
      path = Application.app_dir(app, ["priv", "static", "#{app}.js"])
      Module.put_attribute(__MODULE__, :external_resource, path)
      path
    end

  @phoenix_js for(path <- phoenix_js_paths, do: File.read!(path)) |> Enum.join("\n")

  @app_js ~S"""
  let Hooks = {};
  Hooks.CopyPath = {
    mounted() {
      this.el.addEventListener("click", (e) => {
        e.stopPropagation();
        const path = this.el.dataset.path;
        navigator.clipboard.writeText(path).then(() => {
          const orig = this.el.textContent;
          this.el.textContent = "Copied!";
          this.el.classList.add("cb-copied");
          setTimeout(() => { this.el.textContent = orig; this.el.classList.remove("cb-copied"); }, 1200);
        });
      });
    }
  };
  Hooks.Mermaid = {
    mounted() { this.render(); },
    updated() { this.render(); },
    async render() {
      if (typeof mermaid === 'undefined') return;
      const blocks = this.el.querySelectorAll("pre > code.language-mermaid");
      for (const block of blocks) {
        const pre = block.parentElement;
        const div = document.createElement("div");
        div.className = "mermaid";
        div.textContent = block.textContent;
        pre.replaceWith(div);
      }
      const divs = this.el.querySelectorAll(".mermaid:not([data-processed])");
      if (divs.length > 0) {
        try { await mermaid.run({ nodes: Array.from(divs) }); } catch (e) { console.error("Mermaid:", e); }
      }
    }
  };
  let csrfToken = document.querySelector("meta[name='csrf-token']").getAttribute("content");
  let liveSocket = new window.LiveView.LiveSocket("/live", window.Phoenix.Socket, {
    params: { _csrf_token: csrfToken },
    hooks: Hooks
  });
  liveSocket.connect();
  """

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
        <script src="https://cdn.jsdelivr.net/npm/mermaid@11/dist/mermaid.min.js"></script>
        {raw("<script>mermaid.initialize({ startOnLoad: false, theme: 'neutral' });</script>")}
        {raw("<script>" <> @phoenix_js <> "</script>")}
        {raw("<script>" <> @app_js <> "</script>")}
      </body>
    </html>
    """
  end
end
