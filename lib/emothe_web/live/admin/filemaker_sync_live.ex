defmodule EmotheWeb.Admin.FilemakerSyncLive do
  use EmotheWeb, :live_view

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
    </div>
    """
  end

  defp upload_error_to_string(:too_large), do: gettext("File is too large (max 20MB)")
  defp upload_error_to_string(:not_accepted), do: gettext("Only .ndjson files are accepted")
  defp upload_error_to_string(:too_many_files), do: gettext("Upload one file at a time")
  defp upload_error_to_string(err), do: "#{gettext("Error")}: #{inspect(err)}"
end
