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
      if (typeof mermaid !== 'undefined') {
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
      this.highlightSearch();
    },
    highlightSearch() {
      const wrap = this.el.closest(".cb-content-wrap");
      const oldNav = wrap && wrap.querySelector(".cb-match-nav");
      if (oldNav) oldNav.remove();
      window._matchMarks = [];
      window._matchIdx = -1;
      window._navigateMatch = null;
      const query = this.el.dataset.highlight;
      if (!query) return;
      const regex = new RegExp("(" + query.replace(/[.*+?^${}()|[\]\\]/g, "\\$&") + ")", "gi");
      const walker = document.createTreeWalker(this.el, NodeFilter.SHOW_TEXT, null);
      const textNodes = [];
      while (walker.nextNode()) textNodes.push(walker.currentNode);
      const allMarks = [];
      for (const node of textNodes) {
        if (node.parentElement && node.parentElement.closest(".mermaid")) continue;
        if (!regex.test(node.nodeValue)) continue;
        regex.lastIndex = 0;
        const frag = document.createDocumentFragment();
        let lastIdx = 0;
        let match;
        while ((match = regex.exec(node.nodeValue)) !== null) {
          if (match.index > lastIdx) frag.appendChild(document.createTextNode(node.nodeValue.slice(lastIdx, match.index)));
          const mark = document.createElement("mark");
          mark.className = "cb-content-highlight";
          mark.textContent = match[1];
          frag.appendChild(mark);
          allMarks.push(mark);
          lastIdx = regex.lastIndex;
        }
        if (lastIdx < node.nodeValue.length) frag.appendChild(document.createTextNode(node.nodeValue.slice(lastIdx)));
        node.parentNode.replaceChild(frag, node);
      }
      window._matchMarks = allMarks;
      if (allMarks.length === 0) return;
      window._matchIdx = 0;
      allMarks[0].classList.add("cb-content-highlight--current");
      setTimeout(() => allMarks[0].scrollIntoView({ behavior: "smooth", block: "center" }), 100);
      if (wrap) {
        const nav = document.createElement("div");
        nav.className = "cb-match-nav";
        const prevBtn = document.createElement("button");
        prevBtn.className = "cb-match-nav-btn";
        prevBtn.innerHTML = "\u2191 <span class='cb-hint'>N</span>";
        prevBtn.onclick = () => window._navigateMatch && window._navigateMatch("prev");
        const countSpan = document.createElement("span");
        countSpan.className = "cb-match-nav-count";
        countSpan.textContent = "1 / " + allMarks.length;
        const nextBtn = document.createElement("button");
        nextBtn.className = "cb-match-nav-btn";
        nextBtn.innerHTML = "\u2193 <span class='cb-hint'>n</span>";
        nextBtn.onclick = () => window._navigateMatch && window._navigateMatch("next");
        const prevDocBtn = document.createElement("button");
        prevDocBtn.className = "cb-match-nav-doc-btn";
        prevDocBtn.innerHTML = "\u25C0 <span class='cb-hint'>[</span>";
        prevDocBtn.onclick = () => window.dispatchEvent(new KeyboardEvent('keydown', { key: '[' }));
        const nextDocBtn = document.createElement("button");
        nextDocBtn.className = "cb-match-nav-doc-btn";
        nextDocBtn.innerHTML = "\u25B6 <span class='cb-hint'>]</span>";
        nextDocBtn.onclick = () => window.dispatchEvent(new KeyboardEvent('keydown', { key: ']' }));
        nav.appendChild(prevDocBtn);
        nav.appendChild(prevBtn);
        nav.appendChild(countSpan);
        nav.appendChild(nextBtn);
        nav.appendChild(nextDocBtn);
        wrap.insertBefore(nav, this.el);
      }
      window._navigateMatch = function(dir) {
        const marks = window._matchMarks || [];
        if (marks.length === 0) return;
        let idx = window._matchIdx;
        marks[idx]?.classList.remove("cb-content-highlight--current");
        if (dir === "next") idx = (idx + 1) % marks.length;
        else idx = (idx - 1 + marks.length) % marks.length;
        window._matchIdx = idx;
        marks[idx].classList.add("cb-content-highlight--current");
        marks[idx].scrollIntoView({ behavior: "smooth", block: "center" });
        const countEl = document.querySelector(".cb-match-nav-count");
        if (countEl) countEl.textContent = (idx + 1) + " / " + marks.length;
      };
    }
  };
  function scrollHighlightedIntoView() {
    setTimeout(() => {
      const el = document.querySelector('.cb-file-btn--highlighted');
      if (el) el.scrollIntoView({ block: 'nearest', behavior: 'smooth' });
    }, 50);
  }
  Hooks.KeyboardNav = {
    mounted() {
      this._pendingG = false;
      this.handleKeyDown = (e) => {
        const tag = document.activeElement?.tagName;
        if (tag === 'INPUT' || tag === 'TEXTAREA' || tag === 'SELECT') {
          if (e.key === 'Escape') {
            document.activeElement.blur();
            e.preventDefault();
          }
          if (e.key === 'Enter') {
            document.activeElement.blur();
            this.pushEvent("confirm_search", {});
            e.preventDefault();
          }
          return;
        }
        if (e.ctrlKey) {
          if (e.key === 'd') {
            const main = document.querySelector('.cb-main');
            if (main) main.scrollBy({ top: main.clientHeight / 2, behavior: 'smooth' });
            e.preventDefault();
            return;
          }
          if (e.key === 'u') {
            const main = document.querySelector('.cb-main');
            if (main) main.scrollBy({ top: -main.clientHeight / 2, behavior: 'smooth' });
            e.preventDefault();
            return;
          }
        }
        if (this._pendingG) {
          this._pendingG = false;
          if (e.key === 'g') { this.pushEvent("kb_navigate", {direction: "top"}); scrollHighlightedIntoView(); e.preventDefault(); }
          return;
        }
        switch(e.key) {
          case 'j':
            this.pushEvent("kb_navigate", {direction: "down"});
            scrollHighlightedIntoView();
            e.preventDefault();
            break;
          case 'k':
            this.pushEvent("kb_navigate", {direction: "up"});
            scrollHighlightedIntoView();
            e.preventDefault();
            break;
          case 'g':
            this._pendingG = true;
            setTimeout(() => { this._pendingG = false; }, 500);
            break;
          case 'G':
            this.pushEvent("kb_navigate", {direction: "bottom"});
            scrollHighlightedIntoView();
            e.preventDefault();
            break;
          case 'Enter':
          case 'l':
            this.pushEvent("kb_select", {});
            e.preventDefault();
            break;
          case '/':
            const si = document.getElementById('search-input');
            if (si) { si.focus(); si.select(); }
            e.preventDefault();
            break;
          case 'Escape':
            this.pushEvent("kb_escape", {});
            e.preventDefault();
            break;
          case '1':
            this.pushEvent("kb_tab", {tab: "plans"});
            e.preventDefault();
            break;
          case '2':
            this.pushEvent("kb_tab", {tab: "projects"});
            e.preventDefault();
            break;
          case 'n':
            if (window._navigateMatch) { window._navigateMatch("next"); e.preventDefault(); }
            break;
          case 'N':
            if (window._navigateMatch) { window._navigateMatch("prev"); e.preventDefault(); }
            break;
          case ']':
            this.pushEvent("kb_next_result", {});
            e.preventDefault();
            break;
          case '[':
            this.pushEvent("kb_prev_result", {});
            e.preventDefault();
            break;
          case 'd':
            this.pushEvent("toggle_diff", {});
            e.preventDefault();
            break;
          case 'v':
            this.pushEvent("toggle_versions", {});
            e.preventDefault();
            break;
          case '?':
            this.pushEvent("kb_help", {});
            e.preventDefault();
            break;
        }
      };
      window.addEventListener('keydown', this.handleKeyDown);
    },
    destroyed() {
      window.removeEventListener('keydown', this.handleKeyDown);
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
