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
  const LIGHT_MERMAID = { theme: 'base', startOnLoad: false, themeVariables: { darkMode: false, background: '#ffffff', primaryColor: '#eef2ff', primaryTextColor: '#1e293b', primaryBorderColor: '#94a3b8', lineColor: '#64748b', secondaryColor: '#f1f5f9', tertiaryColor: '#f8fafc' } };
  const DARK_MERMAID = { theme: 'dark', startOnLoad: false };

  function getTheme() {
    const stored = localStorage.getItem('claude-plans-theme');
    if (stored) return stored;
    return window.matchMedia('(prefers-color-scheme: dark)').matches ? 'dark' : 'light';
  }
  function applyTheme(t) {
    document.documentElement.setAttribute('data-theme', t);
    localStorage.setItem('claude-plans-theme', t);
    if (typeof mermaid !== 'undefined') mermaid.initialize(t === 'dark' ? DARK_MERMAID : LIGHT_MERMAID);
    document.querySelectorAll('.cb-theme-toggle').forEach(b => b.textContent = t === 'dark' ? '\u2600' : '\u263E');
  }
  applyTheme(getTheme());

  let Hooks = {};
  Hooks.ThemeToggle = {
    mounted() {
      this.el.textContent = getTheme() === 'dark' ? '\u2600' : '\u263E';
      this.el.addEventListener("click", (e) => {
        e.preventDefault();
        const next = document.documentElement.getAttribute('data-theme') === 'dark' ? 'light' : 'dark';
        applyTheme(next);
      });
    }
  };
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
        {raw("<script>mermaid.initialize({ startOnLoad: false });</script>")}
        {raw("<script>" <> @phoenix_js <> "</script>")}
        {raw("<script>" <> @app_js <> "</script>")}
      </body>
    </html>
    """
  end
end
