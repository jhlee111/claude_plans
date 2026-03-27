defmodule ClaudePlans.Web.Components.AnnotationComponents do
  @moduledoc "Annotation panel and keyboard shortcuts help modal components."
  use Phoenix.Component

  def annotation_panel(assigns) do
    ~H"""
    <div :if={@active_tab == :plans && @show_annotation_panel} class="cb-annotation-panel">
      <div class="cb-annotation-header">
        <span class="cb-section-label">Annotations</span>
        <span :if={@annotations != []} class="cb-count">({length(@annotations)})</span>
        <button :if={@annotations != []} phx-click="clear_annotations" class="cb-annotation-clear">Clear all</button>
      </div>
      <div class="cb-annotation-body">
        <div :if={@annotations == []} class="cb-annotation-empty">
          Click any block in the plan to annotate it
        </div>
        <div :for={ann <- @annotations} class="cb-annotation-card" id={"ann-#{ann.id}"}>
          <div class="cb-annotation-card-header">
            <span class="cb-annotation-label">{ann.id}</span>
            <button phx-click="remove_annotation" phx-value-id={ann.id} class="cb-annotation-remove" title="Remove">&times;</button>
          </div>
          <div class="cb-annotation-ref">{ann.block_path}</div>
          <%= if @editing_annotation == ann.id do %>
            <form phx-change="update_annotation" phx-value-id={ann.id}>
              <textarea
                id={"ann-input-#{ann.id}"}
                name="direction"
                class="cb-annotation-input"
                placeholder="What should change?"
                rows="2"
                phx-debounce="300"
              >{ann.direction}</textarea>
            </form>
            <button phx-click="save_annotation" phx-value-id={ann.id} class="cb-annotation-save">Save</button>
          <% else %>
            <div
              phx-click="edit_annotation"
              phx-value-id={ann.id}
              class={"cb-annotation-display#{if ann.direction == "", do: " cb-annotation-display--empty", else: ""}"}
            >
              {if ann.direction == "", do: "Click to add direction...", else: ann.direction}
            </div>
          <% end %>
        </div>
      </div>
      <div :if={@annotations != []} class="cb-annotation-footer">
        <button id="copy-annotations" class="cb-annotation-copy" phx-hook="CopyAnnotations" data-filename={@selected} data-annotations={Jason.encode!(@annotations)}>
          Copy All Annotations
        </button>
        <button id="write-annotations" class="cb-annotation-write" phx-hook="WriteAnnotations" phx-click="write_annotations_to_file">
          Write to Plan File
        </button>
      </div>
      <div :if={@annotations == [] && @has_file_annotations} class="cb-annotation-footer">
        <button phx-click="strip_annotations_from_file" class="cb-annotation-strip">
          Strip Annotations from File
        </button>
      </div>
    </div>
    """
  end

  def help_modal(assigns) do
    ~H"""
    <div :if={@show_help} class="cb-help-overlay" phx-click="kb_help">
      <div class="cb-help-modal" phx-click="noop">
        <div class="cb-help-title">Keyboard Shortcuts</div>
        <dl class="cb-help-grid">
          <dt><kbd>j</kbd> <kbd>k</kbd></dt><dd>Navigate down / up</dd>
          <dt><kbd>gg</kbd> <kbd>G</kbd></dt><dd>Jump to top / bottom</dd>
          <dt><kbd>Enter</kbd> <kbd>l</kbd></dt><dd>Open selected / Go to file (activity)</dd>
          <dt><kbd>/</kbd></dt><dd>Focus search</dd>
          <dt><kbd>Esc</kbd></dt><dd>Exit input → clear highlight → clear search</dd>
          <dt><kbd>n</kbd> <kbd>N</kbd></dt><dd>Next / prev match in doc</dd>
          <dt><kbd>]</kbd> <kbd>[</kbd></dt><dd>Next / prev search result</dd>
          <dt><kbd>Ctrl+d</kbd> <kbd>Ctrl+u</kbd></dt><dd>Scroll content down / up</dd>
          <dt><kbd>d</kbd></dt><dd>Toggle diff view</dd>
          <dt><kbd>v</kbd></dt><dd>Toggle version history</dd>
          <dt><kbd>a</kbd></dt><dd>Toggle annotation inspector</dd>
          <dt><kbd>e</kbd></dt><dd>Open in editor (PLUG_EDITOR)</dd>
          <dt><kbd>x</kbd></dt><dd>Delete selected file</dd>
          <dt><kbd>1</kbd> <kbd>2</kbd> <kbd>3</kbd></dt><dd>Plans / Projects / Activity tab</dd>
          <dt><kbd>?</kbd></dt><dd>Toggle this help</dd>
        </dl>
      </div>
    </div>
    """
  end
end
