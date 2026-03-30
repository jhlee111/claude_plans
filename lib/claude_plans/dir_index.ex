defmodule ClaudePlans.DirIndex do
  @moduledoc """
  Background directory indexer — scans home directory on startup,
  provides instant fuzzy search like Raycast/Spotlight.
  """
  use GenServer
  require Logger

  @max_depth 4
  @max_entries 10_000
  @rescan_interval_ms 300_000

  def start_link(_opts) do
    GenServer.start_link(__MODULE__, [], name: __MODULE__)
  end

  @doc """
  Fuzzy search indexed directories using subsequence matching.
  Returns up to `limit` results as `{rel_path, match_indices}` tuples,
  where match_indices are the character positions that matched the query.
  """
  @spec search(String.t(), pos_integer()) :: [{String.t(), [non_neg_integer()]}]
  def search(query, limit \\ 30) do
    GenServer.call(__MODULE__, {:search, query, limit})
  end

  @doc "Returns the base path that was indexed."
  @spec base_path() :: String.t()
  def base_path do
    GenServer.call(__MODULE__, :base_path)
  end

  @doc "Force re-index."
  @spec reindex() :: :ok
  def reindex do
    GenServer.cast(__MODULE__, :reindex)
  end

  @doc "Add a single path to the index (called when new directories are detected)."
  @spec add_path(String.t()) :: :ok
  def add_path(full_path) do
    GenServer.cast(__MODULE__, {:add_path, full_path})
  end

  # --- Server ---

  @impl true
  def init(_) do
    base = System.user_home!()
    send(self(), :scan)
    # dirs is a list of {rel_path, has_md?} tuples
    {:ok, %{base: base, dirs: [], indexing: true}}
  end

  @impl true
  def handle_call({:search, query, limit}, _from, state) do
    q = String.downcase(query) |> String.graphemes()

    results =
      state.dirs
      |> Stream.map(fn {rel, {direct, sub}} ->
        case subsequence_match(String.downcase(rel), q) do
          {:ok, indices, score} ->
            total = direct + sub
            boosted = if total > 0, do: score + 20, else: score
            {rel, indices, boosted, direct, sub}

          :no_match ->
            nil
        end
      end)
      |> Stream.reject(&is_nil/1)
      |> Enum.sort_by(fn {_rel, _indices, s, _d, _sub} -> s end, :desc)
      |> Enum.take(limit)
      |> Enum.map(fn {rel, indices, _s, direct, sub} -> {rel, indices, direct, sub} end)

    {:reply, results, state}
  end

  def handle_call(:base_path, _from, state) do
    {:reply, state.base, state}
  end

  @impl true
  def handle_cast(:reindex, state) do
    send(self(), :scan)
    {:noreply, %{state | indexing: true}}
  end

  def handle_cast({:add_path, full_path}, state) do
    rel = Path.relative_to(full_path, state.base)

    if rel != full_path and not Enum.any?(state.dirs, fn {r, _} -> r == rel end) do
      md_counts = count_markdown(full_path)
      {:noreply, %{state | dirs: [{rel, md_counts} | state.dirs]}}
    else
      {:noreply, state}
    end
  end

  @impl true
  def handle_info(:scan, state) do
    dirs = scan(state.base, @max_depth, @max_entries)
    Logger.info("[DirIndex] Indexed #{length(dirs)} directories under #{state.base}")
    Process.send_after(self(), :scan, @rescan_interval_ms)
    {:noreply, %{state | dirs: dirs, indexing: false}}
  end

  # --- Scan ---

  defp scan(base, max_depth, max_entries) do
    ref = make_ref()
    Process.put(ref, 0)

    results =
      do_scan(base, base, max_depth, max_entries, ref, [])
      |> Enum.reverse()

    Process.delete(ref)
    results
  end

  defp do_scan(_base, _current, 0, _max, _ref, acc), do: acc

  defp do_scan(base, current, depth, max, ref, acc) do
    if Process.get(ref) >= max, do: throw({:enough, acc})

    case File.ls(current) do
      {:ok, entries} ->
        entries
        |> Enum.filter(fn name -> not String.starts_with?(name, ".") end)
        |> Enum.sort()
        |> Enum.reduce(acc, fn name, acc ->
          if Process.get(ref) >= max do
            acc
          else
            full = Path.join(current, name)

            if File.dir?(full) and not symlink?(full) do
              rel = Path.relative_to(full, base)
              md_counts = count_markdown(full)
              Process.put(ref, Process.get(ref) + 1)
              acc = [{rel, md_counts} | acc]
              do_scan(base, full, depth - 1, max, ref, acc)
            else
              acc
            end
          end
        end)

      {:error, _} ->
        acc
    end
  catch
    {:enough, acc} -> acc
  end

  # Returns {direct_count, sub_count} — direct .md files and .md in subfolders
  defp count_markdown(path) do
    case File.ls(path) do
      {:ok, entries} ->
        direct = Enum.count(entries, &String.ends_with?(&1, ".md"))

        sub =
          entries
          |> Enum.filter(fn name ->
            not String.starts_with?(name, ".") and File.dir?(Path.join(path, name))
          end)
          |> Enum.take(50)
          |> Enum.reduce(0, fn dir, acc ->
            acc + count_md_recursive(Path.join(path, dir), 2)
          end)

        {direct, sub}

      {:error, _} ->
        {0, 0}
    end
  end

  defp count_md_recursive(_path, 0), do: 0

  defp count_md_recursive(path, depth) do
    case File.ls(path) do
      {:ok, entries} ->
        md = Enum.count(entries, &String.ends_with?(&1, ".md"))

        sub =
          entries
          |> Enum.filter(fn name ->
            not String.starts_with?(name, ".") and File.dir?(Path.join(path, name))
          end)
          |> Enum.take(30)
          |> Enum.reduce(0, fn dir, acc ->
            acc + count_md_recursive(Path.join(path, dir), depth - 1)
          end)

        md + sub

      {:error, _} ->
        0
    end
  end

  defp symlink?(path) do
    case File.lstat(path) do
      {:ok, %{type: :symlink}} -> true
      _ -> false
    end
  end

  # --- Subsequence matching (Sublime Text / VSCode style) ---

  # Returns {:ok, match_indices, score} or :no_match
  defp subsequence_match(haystack, needle_chars) do
    chars = String.graphemes(haystack)

    case find_subsequence(chars, needle_chars, 0, []) do
      {:ok, indices} ->
        score = compute_score(chars, indices, length(chars))
        {:ok, indices, score}

      :no_match ->
        :no_match
    end
  end

  defp find_subsequence(_chars, [], _pos, acc), do: {:ok, Enum.reverse(acc)}
  defp find_subsequence([], _needle, _pos, _acc), do: :no_match

  defp find_subsequence([c | rest], [n | needle_rest] = needle, pos, acc) do
    if c == n do
      find_subsequence(rest, needle_rest, pos + 1, [pos | acc])
    else
      find_subsequence(rest, needle, pos + 1, acc)
    end
  end

  defp compute_score(chars, indices, len) do
    n = length(indices)
    if n == 0, do: throw(0.0)

    # 1. Tightness: how close together are the matched chars?
    #    Best case: all consecutive (span == n), worst: spread across entire string
    first = hd(indices)
    last = List.last(indices)
    span = last - first + 1
    tightness = n / max(span, 1)

    # 2. Consecutive bonus: count pairs of adjacent matches
    consecutive =
      indices
      |> Enum.chunk_every(2, 1, :discard)
      |> Enum.count(fn [a, b] -> b == a + 1 end)

    consecutive_ratio = consecutive / max(n - 1, 1)

    # 3. Boundary bonus: matches at word starts (after /, -, _, space, or position 0)
    boundary =
      Enum.count(indices, fn idx ->
        idx == 0 or Enum.at(chars, idx - 1) in ["/", "-", "_", " ", "."]
      end)

    boundary_ratio = boundary / n

    # 4. Path length penalty: shorter paths are better
    length_score = 1.0 - min(len, 100) / 100

    # Weighted combination (all 0..1 range)
    # Tightness & consecutive are most important — we want tight clusters
    tightness * 40 + consecutive_ratio * 35 + length_score * 15 + boundary_ratio * 10
  catch
    score -> score
  end
end
