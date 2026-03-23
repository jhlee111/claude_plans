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

  @app_js ~S"""
  const PREFS_KEY = 'claude-plans-prefs';
  function loadPrefs() {
    try { return JSON.parse(localStorage.getItem(PREFS_KEY) || '{}'); } catch(e) { return {}; }
  }
  function savePrefs(update) {
    const prefs = loadPrefs();
    Object.assign(prefs, update);
    localStorage.setItem(PREFS_KEY, JSON.stringify(prefs));
  }

  function getTheme() {
    const stored = localStorage.getItem('claude-plans-theme');
    if (stored) return stored;
    return window.matchMedia('(prefers-color-scheme: dark)').matches ? 'dark' : 'light';
  }
  function applyTheme(t) {
    document.documentElement.setAttribute('data-theme', t);
    localStorage.setItem('claude-plans-theme', t);
    const moonSvg = '<svg xmlns="http://www.w3.org/2000/svg" width="14" height="14" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><path d="M12 3a6 6 0 0 0 9 9 9 9 0 1 1-9-9Z"/></svg>';
    const sunSvg = '<svg xmlns="http://www.w3.org/2000/svg" width="14" height="14" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><circle cx="12" cy="12" r="4"/><path d="M12 2v2"/><path d="M12 20v2"/><path d="m4.93 4.93 1.41 1.41"/><path d="m17.66 17.66 1.41 1.41"/><path d="M2 12h2"/><path d="M20 12h2"/><path d="m6.34 17.66-1.41 1.41"/><path d="m19.07 4.93-1.41 1.41"/></svg>';
    document.querySelectorAll('.cb-theme-toggle').forEach(b => b.innerHTML = t === 'dark' ? sunSvg : moonSvg);
  }
  applyTheme(getTheme());

  let Hooks = {};
  Hooks.ThemeToggle = {
    mounted() {
      applyTheme(getTheme());
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
  Hooks.TimeAgo = {
    mounted() { this.render(); this._interval = setInterval(() => this.render(), 30000); },
    updated() { this.render(); },
    render() {
      const ts = this.el.dataset.timestamp;
      if (!ts) return;
      const diff = Math.floor((Date.now() - new Date(ts).getTime()) / 1000);
      let text;
      if (diff < 10) text = "just now";
      else if (diff < 60) text = diff + "s ago";
      else if (diff < 3600) text = Math.floor(diff / 60) + "m ago";
      else if (diff < 86400) text = Math.floor(diff / 3600) + "h ago";
      else text = Math.floor(diff / 86400) + "d ago";
      this.el.textContent = text;
    },
    destroyed() { if (this._interval) clearInterval(this._interval); }
  };
  function cleanText(el, max) {
    let s;
    if (typeof el === "string") { s = el; }
    else {
      const label = el.querySelector ? el.querySelector("span.nodeLabel") : null;
      if (label) {
        s = label.innerText || label.textContent || "";
      } else {
        s = el.innerText || el.textContent || "";
      }
    }
    const t = s.replace(/\s+/g, " ").trim();
    return t.length > max ? t.substring(0, max) + "..." : t;
  }
  Hooks.PlanContent = {
    mounted() { this.render(); this.setupInspector(); },
    updated() { this.render(); },
    render() {
      this.el.querySelectorAll(".mermaid").forEach(div => this.tagMermaidElements(div));
      this.highlightSearch();
      this.applyAnnotationMarkers();
      this.setupEdgeHitTargets();
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
    },
    setupInspector() {
      if (this._inspectorBound) return;
      const SELECTORS = "h1, h2, h3, h4, h5, h6, p, li, pre, blockquote, table tr, .mermaid";
      const self = this;
      function resolveBlock(target) {
        let block = target.closest(SELECTORS);
        if (block && block.closest(".mermaid") && !block.classList.contains("mermaid")) {
          block = block.closest(".mermaid");
        }
        return block;
      }
      this._lastMermaidHighlight = null;
      const tip = document.createElement("div");
      tip.className = "cb-inspector-tooltip";
      tip.style.display = "none";
      document.body.appendChild(tip);
      self._inspectorTip = tip;
      function tipLabel(el, mermaidPart) {
        if (mermaidPart) {
          if (mermaidPart.classList.contains("node")) {
            const nid = mermaidPart.getAttribute("data-mermaid-node") || "";
            const label = mermaidPart.getAttribute("data-mermaid-label") || cleanText(mermaidPart, 35);
            return (nid ? "node " + nid + ": " : "node: ") + label;
          }
          if (mermaidPart.classList.contains("edgePath")) {
            const conn = mermaidPart.getAttribute("data-mermaid-edge");
            return conn ? "edge: " + conn : "edge";
          }
          if (mermaidPart.classList.contains("edgeLabel")) {
            const lbl = mermaidPart.getAttribute("data-mermaid-label") || cleanText(mermaidPart, 30);
            const conn = mermaidPart.getAttribute("data-mermaid-edge");
            return "label: " + lbl + (conn ? " (" + conn + ")" : "");
          }
          if (mermaidPart.classList.contains("cluster")) return "group: " + cleanText(mermaidPart.textContent, 30);
        }
        if (!el) return "";
        const tag = el.tagName.toLowerCase();
        if (/^h[1-6]$/.test(tag)) return "heading: " + cleanText(el.textContent, 40);
        if (tag === "p") return "paragraph: " + cleanText(el.textContent, 40);
        if (tag === "li") return "bullet: " + cleanText(el.textContent, 40);
        if (tag === "pre") return "code block";
        if (tag === "blockquote") return "blockquote: " + cleanText(el.textContent, 40);
        if (tag === "tr") {
          const cells = Array.from(el.querySelectorAll("td, th")).map(c => c.textContent.trim());
          return "table row: " + cleanText(cells.join(" | "), 40);
        }
        if (el.classList.contains("mermaid")) return "diagram";
        return tag;
      }
      function showTip(e, text) {
        if (!text) { tip.style.display = "none"; return; }
        tip.textContent = text;
        tip.style.display = "block";
        tip.style.left = (e.clientX + 12) + "px";
        tip.style.top = (e.clientY - 8) + "px";
      }
      this.el.addEventListener("mousemove", function(e) {
        if (self.el.dataset.inspector !== "true") { tip.style.display = "none"; return; }
        const mermaidEl = e.target.closest(".mermaid");
        if (mermaidEl && self.el.contains(mermaidEl)) {
          const els = document.elementsFromPoint(e.clientX, e.clientY);
          let found = null;
          for (const el of els) {
            const part = el.closest(".node, .edgePath, .edgeLabel, .cluster");
            if (part && mermaidEl.contains(part)) { found = part; break; }
          }
          if (self._lastMermaidHighlight && self._lastMermaidHighlight !== found) {
            self._lastMermaidHighlight.classList.remove("cb-mermaid-highlight");
          }
          if (found) {
            found.classList.add("cb-mermaid-highlight");
            self._lastMermaidHighlight = found;
            mermaidEl.classList.remove("cb-inspector-highlight");
            showTip(e, tipLabel(null, found));
            return;
          }
          self._lastMermaidHighlight = null;
          showTip(e, "diagram");
          return;
        }
        const block = e.target.closest(SELECTORS);
        if (block && self.el.contains(block)) {
          showTip(e, tipLabel(block, null));
        } else {
          tip.style.display = "none";
        }
      });
      this.el.addEventListener("mouseover", function(e) {
        if (self.el.dataset.inspector !== "true") return;
        const block = resolveBlock(e.target);
        if (block && self.el.contains(block)) {
          block.classList.add("cb-inspector-highlight");
        }
      });
      this.el.addEventListener("mouseout", function(e) {
        if (self._lastMermaidHighlight) {
          self._lastMermaidHighlight.classList.remove("cb-mermaid-highlight");
          self._lastMermaidHighlight = null;
        }
        const block = resolveBlock(e.target);
        if (block) block.classList.remove("cb-inspector-highlight");
        tip.style.display = "none";
      });
      document.addEventListener("mousedown", function(e) {
        if (self.el.dataset.inspector !== "true") return;
        const block = resolveBlock(e.target);
        if (!block || !self.el.contains(block)) return;
        e.preventDefault();
        e.stopPropagation();
        e.stopImmediatePropagation();
        let mermaidPart = null;
        if (block.classList.contains("mermaid") && self._lastMermaidHighlight) {
          mermaidPart = self._lastMermaidHighlight;
        }
        if (self._lastMermaidHighlight) {
          self._lastMermaidHighlight.classList.remove("cb-mermaid-highlight");
          self._lastMermaidHighlight = null;
        }
        tip.style.display = "none";
        const blockIndex = self._getBlockIndex(block);
        const blockPath = self._computeBlockPath(block, e, mermaidPart);
        self.pushEvent("add_annotation", { block_path: blockPath, block_index: blockIndex });
      }, true);
      this._inspectorBound = true;
    },
    _getBlockIndex(el) {
      const SELECTORS = "h1, h2, h3, h4, h5, h6, p, li, pre, blockquote, table tr, .mermaid";
      const all = Array.from(this.el.querySelectorAll(SELECTORS));
      return all.indexOf(el);
    },
    _computeBlockPath(el, clickEvent, mermaidPart) {
      let heading = null;
      let node = el;
      while (node && node !== this.el) {
        let sib = node.previousElementSibling;
        while (sib) {
          if (/^H[1-6]$/.test(sib.tagName)) {
            heading = sib;
            break;
          }
          sib = sib.previousElementSibling;
        }
        if (heading) break;
        node = node.parentElement;
      }
      let headingText = "(top)";
      if (heading) {
        const clone = heading.cloneNode(true);
        clone.querySelectorAll(".cb-annotation-badge").forEach(b => b.remove());
        headingText = clone.textContent.trim();
      }
      const headingPrefix = heading ? "#".repeat(parseInt(heading.tagName[1])) + " " : "";
      const tag = el.tagName.toLowerCase();
      let typeLabel;
      if (/^h[1-6]$/.test(tag)) {
        return headingPrefix + headingText;
      } else if (tag === "li") {
        const list = el.parentElement;
        const items = list ? Array.from(list.children).filter(c => c.tagName === "LI") : [el];
        const pos = items.indexOf(el) + 1;
        typeLabel = "bullet " + pos;
      } else if (tag === "pre") {
        typeLabel = "code block";
        if (clickEvent) {
          const code = el.querySelector("code");
          if (code) {
            const text = code.textContent || "";
            const lines = text.split("\n");
            if (lines.length > 1) {
              const rect = code.getBoundingClientRect();
              const clickY = clickEvent.clientY - rect.top;
              const lineHeight = rect.height / lines.length;
              const lineNum = Math.min(Math.floor(clickY / lineHeight) + 1, lines.length);
              const lineText = (lines[lineNum - 1] || "").trim();
              const preview = lineText.length > 30 ? lineText.substring(0, 30) + "..." : lineText;
              typeLabel = "code block line " + lineNum + (preview ? " `" + preview + "`" : "");
            }
          }
        }
      } else if (tag === "p") {
        let count = 0;
        let s = el;
        while (s) {
          if (s.tagName === "P") count++;
          if (s === heading) break;
          s = s.previousElementSibling;
        }
        typeLabel = count > 1 ? "paragraph " + count : "paragraph";
      } else if (tag === "blockquote") {
        typeLabel = "blockquote";
      } else if (tag === "tr") {
        const table = el.closest("table");
        const rows = table ? Array.from(table.querySelectorAll("tr")) : [el];
        const rowPos = rows.indexOf(el) + 1;
        if (clickEvent) {
          const td = clickEvent.target.closest("td, th");
          if (td) {
            const cells = Array.from(el.children);
            const colPos = cells.indexOf(td) + 1;
            const cellText = td.textContent.trim();
            const preview = cellText.length > 30 ? cellText.substring(0, 30) + "..." : cellText;
            typeLabel = "table row " + rowPos + " col " + colPos + (preview ? ' "' + preview + '"' : "");
          } else {
            typeLabel = "table row " + rowPos;
          }
        } else {
          typeLabel = "table row " + rowPos;
        }
      } else if (el.classList.contains("mermaid")) {
        typeLabel = "diagram";
        if (mermaidPart) {
          const edgePath = mermaidPart.classList.contains("edgePath") ? mermaidPart : null;
          const edgeLabel = mermaidPart.classList.contains("edgeLabel") ? mermaidPart : null;
          const nodeEl = mermaidPart.classList.contains("node") ? mermaidPart : null;
          const cluster = mermaidPart.classList.contains("cluster") ? mermaidPart : null;
          if (edgePath) {
            const conn = edgePath.getAttribute("data-mermaid-edge");
            typeLabel = conn ? 'diagram edge ' + conn : "diagram edge";
          } else if (edgeLabel) {
            const lbl = edgeLabel.getAttribute("data-mermaid-label") || cleanText(edgeLabel, 30);
            const conn = edgeLabel.getAttribute("data-mermaid-edge");
            typeLabel = 'diagram label "' + lbl + '"' + (conn ? " on " + conn : "");
          } else if (nodeEl) {
            const nid = nodeEl.getAttribute("data-mermaid-node") || "";
            const label = nodeEl.getAttribute("data-mermaid-label") || cleanText(nodeEl, 35);
            typeLabel = nid ? 'diagram node ' + nid + ' "' + label + '"' : 'diagram node "' + label + '"';
          } else if (cluster) {
            const label = cleanText(cluster, 30);
            typeLabel = label ? 'diagram group "' + label + '"' : "diagram group";
          }
        }
      } else {
        typeLabel = tag;
      }
      return headingPrefix + headingText + " > " + typeLabel;
    },
    applyAnnotationMarkers() {
      // Remove old markers
      this.el.querySelectorAll(".cb-annotation-badge").forEach(b => b.remove());
      this.el.querySelectorAll(".cb-annotated").forEach(b => b.classList.remove("cb-annotated"));
      let annotatedIndices;
      try { annotatedIndices = JSON.parse(this.el.dataset.annotations || "[]"); } catch(e) { return; }
      if (!annotatedIndices.length) return;
      const SELECTORS = "h1, h2, h3, h4, h5, h6, p, li, pre, blockquote, table tr, .mermaid";
      const all = Array.from(this.el.querySelectorAll(SELECTORS));
      // Get annotation IDs from the panel to match with indices
      const panel = document.querySelector(".cb-annotation-panel");
      const cards = panel ? Array.from(panel.querySelectorAll(".cb-annotation-card")) : [];
      annotatedIndices.forEach((blockIdx, i) => {
        const el = all[blockIdx];
        if (!el) return;
        el.classList.add("cb-annotated");
        el.style.position = "relative";
        const badge = document.createElement("span");
        badge.className = "cb-annotation-badge";
        const cardId = cards[i] ? cards[i].id.replace("ann-", "") : "A" + (i + 1);
        badge.textContent = cardId;
        el.appendChild(badge);
      });
    },
    setupEdgeHitTargets() {
      // no-op: elementsFromPoint handles edge detection without hit targets
    },
    tagMermaidElements(container) {
      container.querySelectorAll(".node[id]").forEach(node => {
        const rawId = node.id || "";
        const nodeId = rawId.replace(/^flowchart-/, "").replace(/-\d+$/, "");
        if (nodeId) node.setAttribute("data-mermaid-node", nodeId);
        const label = cleanText(node, 60);
        if (label) node.setAttribute("data-mermaid-label", label);
      });
      const edges = Array.from(container.querySelectorAll(".edgePath[id]"));
      const labels = Array.from(container.querySelectorAll(".edgeLabel"));
      edges.forEach((edge, i) => {
        const rawId = edge.id || "";
        const parts = rawId.replace(/^L-/, "").split("-");
        if (parts.length >= 2) {
          edge.setAttribute("data-mermaid-from", parts[0]);
          edge.setAttribute("data-mermaid-to", parts[1]);
          edge.setAttribute("data-mermaid-edge", parts[0] + " -> " + parts[1]);
        }
        if (labels[i]) {
          const labelText = cleanText(labels[i], 40);
          labels[i].setAttribute("data-mermaid-label", labelText);
          if (parts.length >= 2) {
            labels[i].setAttribute("data-mermaid-from", parts[0]);
            labels[i].setAttribute("data-mermaid-to", parts[1]);
            labels[i].setAttribute("data-mermaid-edge", parts[0] + " -> " + parts[1]);
          }
        }
      });
    }
  };
  Hooks.CopyAnnotations = {
    mounted() {
      this.el.addEventListener("click", (e) => {
        e.preventDefault();
        const filename = this.el.dataset.filename || "plan.md";
        let annotations;
        try { annotations = JSON.parse(this.el.dataset.annotations || "[]"); } catch(e) { return; }
        if (!annotations.length) return;
        let lines = ["Plan annotations for: " + filename, ""];
        for (const ann of annotations) {
          const dir = (ann.direction || "").trim();
          lines.push(ann.id + " (" + ann.block_path + "): " + (dir || "(no direction)"));
        }
        const text = lines.join("\n");
        navigator.clipboard.writeText(text).then(() => {
          const orig = this.el.textContent;
          this.el.textContent = "Copied!";
          this.el.classList.add("cb-copied");
          setTimeout(() => { this.el.textContent = orig; this.el.classList.remove("cb-copied"); }, 1200);
        });
      });
    }
  };
  Hooks.WriteAnnotations = {
    mounted() {
      this.handleEvent("write_feedback", ({status}) => {
        if (status === "ok") {
          const orig = this.el.textContent;
          this.el.textContent = "Written!";
          this.el.classList.add("cb-copied");
          setTimeout(() => { this.el.textContent = orig; this.el.classList.remove("cb-copied"); }, 1200);
        }
      });
    }
  };
  function scrollHighlightedIntoView() {
    setTimeout(() => {
      const el = document.querySelector('.cb-file-btn--active') || document.querySelector('.cb-activity-row-wrap.cb-activity-row--active');
      if (el) el.scrollIntoView({ block: 'nearest', behavior: 'smooth' });
    }, 50);
  }
  Hooks.KeyboardNav = {
    mounted() {
      this._pendingG = false;
      this.handleEvent("save_preferences", (prefs) => { savePrefs(prefs); });
      this.handleKeyDown = (e) => {
        if (!document.hasFocus()) return;
        const tag = document.activeElement?.tagName;
        if (tag === 'INPUT' || tag === 'TEXTAREA' || tag === 'SELECT') {
          if (e.key === 'Escape') {
            document.activeElement.blur();
            e.preventDefault();
          }
          if (e.key === 'Enter' && tag === 'INPUT') {
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
        if (document.activeElement && document.activeElement !== document.body) {
          document.activeElement.blur();
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
          case '3':
            this.pushEvent("kb_tab", {tab: "activity"});
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
          case 'x':
            this.pushEvent("kb_delete", {});
            e.preventDefault();
            break;
          case 'i':
            this.pushEvent("toggle_inspector", {});
            e.preventDefault();
            break;
          case 'e':
            this.pushEvent("kb_edit", {});
            e.preventDefault();
            break;
          case '?':
            this.pushEvent("kb_help", {});
            e.preventDefault();
            break;
        }
      };
      window.addEventListener('keydown', this.handleKeyDown);
      this.handleEvent("confirm_delete", ({path}) => {
        if (confirm("Delete " + path + "?")) {
          this.pushEvent("delete_file", {path: path});
        }
      });
      this.handleEvent("open_editor", ({url}) => {
        window.location.href = url;
      });
    },
    destroyed() {
      window.removeEventListener('keydown', this.handleKeyDown);
    }
  };
  let csrfToken = document.querySelector("meta[name='csrf-token']").getAttribute("content");
  let liveSocket = new window.LiveView.LiveSocket("/live", window.Phoenix.Socket, {
    params: () => {
      const prefs = loadPrefs();
      return { _csrf_token: csrfToken, font_size: prefs.font_size || 16 };
    },
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
        {raw("<script>" <> @phoenix_js <> "</script>")}
        {raw("<script>" <> @app_js <> "</script>")}
      </body>
    </html>
    """
  end
end
