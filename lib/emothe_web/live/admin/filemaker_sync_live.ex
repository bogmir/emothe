defmodule EmotheWeb.Admin.FilemakerSyncLive do
  use EmotheWeb, :live_view

  alias Emothe.Import.Filemaker
  alias Emothe.Import.FilemakerSync
  alias EmotheWeb.PlayLabels

  # Stricter than the live_session's :view_admin, declared here so admin
  # sections still navigate without a full page reload.
  on_mount {EmotheWeb.UserAuth, {:ensure_can, :import_filemaker}}

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(:page_title, gettext("FileMaker sync"))
     |> assign(:plan, nil)
     |> assign(:plays_by_id, %{})
     |> assign(:selected, MapSet.new())
     |> assign(:results, nil)
     |> allow_upload(:export,
       accept: ~w(.ndjson .json),
       max_entries: 1,
       max_file_size: 20_000_000
     )}
  end

  @impl true
  def handle_event("validate", _params, socket), do: {:noreply, socket}

  def handle_event("cancel-upload", %{"ref" => ref}, socket) do
    {:noreply, cancel_upload(socket, :export, ref)}
  end

  def handle_event("preview", _params, socket) do
    case consume_uploaded_entries(socket, :export, fn %{path: path}, _entry ->
           {:ok, read_plan(path)}
         end) do
      [] ->
        {:noreply, socket}

      [{:ok, plan, plays}] ->
        {:noreply,
         socket
         |> assign(:plan, plan)
         |> assign(:plays_by_id, Map.new(plays, &{&1.id, &1}))
         |> assign(:selected, MapSet.new())
         |> assign(:results, nil)}

      [{:error, reason}] ->
        {:noreply, put_flash(socket, :error, error_message(reason))}
    end
  end

  def handle_event("discard", _params, socket) do
    {:noreply,
     socket
     |> assign(:plan, nil)
     |> assign(:plays_by_id, %{})
     |> assign(:selected, MapSet.new())
     |> assign(:results, nil)}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="mx-auto max-w-5xl px-4 py-8">
      <div class="mb-6">
        <h1 class="text-3xl font-semibold tracking-tight text-base-content">
          {gettext("FileMaker sync")}
        </h1>
        <p class="mt-1 text-sm text-base-content/70">
          {gettext("Upload the FileMaker export, review what it would change, then apply it.")}
        </p>
      </div>

      <div
        :if={is_nil(@plan) && is_nil(@results)}
        class="card border border-base-300 bg-base-100 shadow-sm"
      >
        <div class="card-body">
          <h2 class="card-title">{gettext("Select the export")}</h2>
          <p class="mb-3 text-sm text-base-content/70">
            {gettext("One .ndjson file, as exported from FileMaker.")}
          </p>
          <form id="upload-form" phx-submit="preview" phx-change="validate">
            <.live_file_input
              upload={@uploads.export}
              class="file-input file-input-bordered w-full mb-4"
            />

            <div :for={err <- upload_errors(@uploads.export)} class="text-error text-sm mb-2">
              {upload_error_to_string(err)}
            </div>

            <button type="submit" class="btn btn-primary" disabled={@uploads.export.entries == []}>
              {gettext("Preview changes")}
            </button>
          </form>
        </div>
      </div>

      <div
        :if={@plan && @plan.changes != []}
        id="changes"
        class="card mb-6 border border-base-300 bg-base-100 shadow-sm"
      >
        <div class="card-body">
          <h2 class="card-title">
            {gettext("%{count} play(s) to update", count: length(@plan.changes))}
          </h2>
          <div class="overflow-x-auto">
            <table class="table table-sm">
              <thead>
                <tr>
                  <th>{gettext("Code")}</th>
                  <th>{gettext("Title")}</th>
                  <th>{gettext("Changes")}</th>
                </tr>
              </thead>
              <tbody>
                <tr :for={change <- @plan.changes}>
                  <td><span class="badge badge-primary badge-sm">{change.code}</span></td>
                  <td>{change.title}</td>
                  <td>
                    <ul class="space-y-0.5">
                      <li :for={{field, value} <- change.sets} class="text-xs">
                        <span class="font-medium">{field_label(field)}</span>:
                        <span class="text-base-content/60">
                          {current_value(@plays_by_id, change.play_id, field)}
                        </span>
                        <span aria-hidden="true">&rarr;</span>
                        <span class="font-medium">{value_label(field, value, @plays_by_id)}</span>
                      </li>
                    </ul>
                  </td>
                </tr>
              </tbody>
            </table>
          </div>
        </div>
      </div>

      <div :if={@plan} id="counts" class="card mb-6 border border-base-300 bg-base-100 shadow-sm">
        <div class="card-body gap-2">
          <details :if={@plan.unchanged != []} id="unchanged">
            <summary class="cursor-pointer text-sm">
              {gettext("%{count} play(s) already match", count: length(@plan.unchanged))}
            </summary>
            <p class="mt-2 font-mono text-xs text-base-content/70">
              {Enum.join(@plan.unchanged, ", ")}
            </p>
          </details>

          <details :if={@plan.missing != []} id="missing">
            <summary class="cursor-pointer text-sm">
              {gettext("%{count} play(s) are not in the published index",
                count: length(@plan.missing)
              )}
            </summary>
            <p class="mt-2 text-xs text-base-content/70">
              {gettext(
                "Nothing is created for these. A play can be absent from the index and still have research metadata to fill, in which case it is listed above as well."
              )}
            </p>
            <p class="mt-1 font-mono text-xs text-base-content/70">
              {Enum.join(@plan.missing, ", ")}
            </p>
          </details>
        </div>
      </div>

      <div :if={@plan} id="sync-actions" class="flex items-center gap-3">
        <p
          :if={@plan.changes == [] and @plan.conflicts == []}
          class="text-sm text-base-content/70"
        >
          {gettext("Everything already matches the export.")}
        </p>
        <button phx-click="discard" class="btn btn-ghost">{gettext("Discard")}</button>
      </div>
    </div>
    """
  end

  defp upload_error_to_string(:too_large), do: gettext("File is too large (max 20MB)")
  defp upload_error_to_string(:not_accepted), do: gettext("Only .ndjson files are accepted")
  defp upload_error_to_string(:too_many_files), do: gettext("Upload one file at a time")
  defp upload_error_to_string(err), do: "#{gettext("Error")}: #{inspect(err)}"

  # ponytail: synchronous. 649 lines parsed, 82 plays diffed in memory, ~11 rows
  # written. start_async if the export grows an order of magnitude.
  defp read_plan(path) do
    with {:ok, index} <- Filemaker.load_index(path),
         {:ok, versions} <- Filemaker.load_versions(path),
         true <- map_size(index) > 0 or map_size(versions) > 0 do
      plays = FilemakerSync.all_plays()
      {:ok, FilemakerSync.plan(index, plays, versions), plays}
    else
      false -> {:error, :no_records}
      {:error, reason} -> {:error, reason}
    end
  end

  defp error_message(:no_records) do
    gettext("No FileMaker records found in that file. Is it the right export?")
  end

  defp error_message(reason) do
    "#{gettext("Cannot read the file")}: #{inspect(reason)}"
  end

  @doc """
  The human name of a field in a plan's `sets`.

  The catch-all clause is deliberate: a later FileMaker slice adds a field to
  `Filemaker.load_versions/1` and therefore to `sets`, and it must render on this
  page without an edit here. Adding a clause is polish, not a requirement.
  """
  def field_label(:language), do: gettext("Language")
  def field_label(:relationship_type), do: gettext("Relationship")
  def field_label(:parent_play_id), do: gettext("Parent play")
  def field_label(:historical_time), do: gettext("Historical time")
  def field_label(:historical_time_note), do: gettext("Historical time note")
  def field_label(other), do: other |> to_string() |> String.replace("_", " ")

  @doc "The display value of a field, given the plays keyed by id."
  def value_label(:historical_time, value, _plays), do: PlayLabels.historical_time_label(value)

  def value_label(:parent_play_id, id, plays) do
    case Map.get(plays, id) do
      nil -> "—"
      play -> play.code
    end
  end

  def value_label(_field, value, _plays), do: to_string(value)

  defp current_value(plays_by_id, play_id, field) do
    case plays_by_id |> Map.fetch!(play_id) |> Map.get(field) do
      blank when blank in [nil, ""] -> gettext("(blank)")
      value -> value_label(field, value, plays_by_id)
    end
  end
end
