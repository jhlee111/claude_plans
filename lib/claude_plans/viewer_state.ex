defmodule ClaudePlans.ViewerState do
  @moduledoc """
  Viewer state struct and transformation functions.
  Some functions call VersionStore/RenderCache — not pure.
  Used by FoldersViewerComponent. Reusable for Plans tab refactoring later.
  """

  alias ClaudePlans.{Annotations, RenderCache, VersionStore}

  defstruct [
    :html,
    :selected,
    :full_path,
    :version_key,
    versions: [],
    view_mode: :rendered,
    diff_html: nil,
    diff_version_a: nil,
    diff_version_b: nil,
    show_versions: false,
    annotations: [],
    annotation_counter: 0,
    editing_annotation: nil,
    show_annotation_panel: false,
    inspector_mode: false,
    has_file_annotations: false
  ]

  @type t :: %__MODULE__{}

  @spec load_file(t(), String.t(), String.t(), String.t()) :: t()
  def load_file(%__MODULE__{}, rel_path, full_path, version_key) do
    %__MODULE__{
      selected: rel_path,
      full_path: full_path,
      version_key: version_key
    }
  end

  @spec toggle_diff(t()) :: t()
  def toggle_diff(%__MODULE__{view_mode: :diff} = vs) do
    %{vs | view_mode: :rendered}
  end

  def toggle_diff(%__MODULE__{versions: versions} = vs) when length(versions) >= 2 do
    [latest, previous | _] = versions
    diff_html = VersionStore.diff(vs.version_key, previous.id, latest.id)

    %{vs |
      view_mode: :diff,
      diff_html: diff_html,
      diff_version_a: previous.id,
      diff_version_b: latest.id
    }
  end

  def toggle_diff(vs), do: vs

  @spec toggle_versions(t()) :: t()
  def toggle_versions(%__MODULE__{} = vs) do
    %{vs | show_versions: !vs.show_versions}
  end

  @spec select_diff_versions(t(), String.t(), String.t()) :: t()
  def select_diff_versions(%__MODULE__{} = vs, id_a, id_b) do
    diff_html = VersionStore.diff(vs.version_key, id_a, id_b)
    %{vs | diff_html: diff_html, diff_version_a: id_a, diff_version_b: id_b}
  end

  @spec toggle_inspector(t()) :: t()
  def toggle_inspector(%__MODULE__{} = vs) do
    showing = !vs.show_annotation_panel
    %{vs | show_annotation_panel: showing, inspector_mode: showing}
  end

  @spec add_annotation(t(), String.t(), integer()) :: t()
  def add_annotation(%__MODULE__{} = vs, block_path, block_index) do
    counter = vs.annotation_counter + 1
    id = "A#{counter}"

    annotation = %{
      id: id,
      block_path: block_path,
      block_index: block_index,
      direction: ""
    }

    %{vs |
      annotations: vs.annotations ++ [annotation],
      annotation_counter: counter,
      editing_annotation: id
    }
  end

  @spec update_annotation(t(), String.t(), String.t()) :: t()
  def update_annotation(%__MODULE__{} = vs, id, direction) do
    annotations =
      Enum.map(vs.annotations, fn ann ->
        if ann.id == id, do: %{ann | direction: direction}, else: ann
      end)

    %{vs | annotations: annotations}
  end

  @spec save_annotation(t(), String.t()) :: t()
  def save_annotation(%__MODULE__{} = vs, _id) do
    %{vs | editing_annotation: nil}
  end

  @spec edit_annotation(t(), String.t()) :: t()
  def edit_annotation(%__MODULE__{} = vs, id) do
    %{vs | editing_annotation: id}
  end

  @spec remove_annotation(t(), String.t()) :: t()
  def remove_annotation(%__MODULE__{} = vs, id) do
    annotations = Enum.reject(vs.annotations, &(&1.id == id))
    %{vs | annotations: annotations, editing_annotation: nil}
  end

  @spec clear_annotations(t()) :: t()
  def clear_annotations(%__MODULE__{} = vs) do
    %{vs |
      annotations: [],
      annotation_counter: 0,
      editing_annotation: nil
    }
  end

  @spec write_annotations(t()) :: :ok | :error
  def write_annotations(%__MODULE__{full_path: path, annotations: annotations})
      when is_binary(path) do
    case File.read(path) do
      {:ok, content} ->
        updated = Annotations.inject(content, annotations)
        File.write!(path, updated)
        :ok

      {:error, _} ->
        :error
    end
  end

  def write_annotations(_vs), do: :error

  @spec strip_annotations(t()) :: :ok | :error
  def strip_annotations(%__MODULE__{full_path: path}) when is_binary(path) do
    case File.read(path) do
      {:ok, content} ->
        cleaned = Annotations.strip(content)
        File.write!(path, cleaned <> "\n")
        :ok

      {:error, _} ->
        :error
    end
  end

  def strip_annotations(_vs), do: :error

  @spec refresh_on_file_change(t()) :: t()
  def refresh_on_file_change(%__MODULE__{full_path: path, version_key: key} = vs)
      when is_binary(path) and is_binary(key) do
    case File.read(path) do
      {:ok, content} ->
        VersionStore.snapshot_file(key, path)
        versions = VersionStore.list_versions(key)

        vs = %{vs |
          html: RenderCache.render(content),
          versions: versions,
          has_file_annotations: Annotations.present?(content)
        }

        if vs.view_mode == :diff and vs.diff_version_a and vs.diff_version_b do
          diff_html = VersionStore.diff(key, vs.diff_version_a, vs.diff_version_b)
          %{vs | diff_html: diff_html}
        else
          vs
        end

      {:error, _} ->
        vs
    end
  end

  def refresh_on_file_change(vs), do: vs
end
