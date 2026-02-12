defmodule EmotheWeb.Admin.ImportLive do
  use EmotheWeb, :live_view

  alias Emothe.Import.TeiParser

  require Logger

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(:page_title, "Import TEI-XML")
     |> assign(:successes, [])
     |> assign(:importing, false)
     |> allow_upload(:tei_files,
       accept: ~w(.xml),
       max_entries: 20,
       max_file_size: 20_000_000
     )}
  end

  @impl true
  def handle_event("validate", _params, socket) do
    {:noreply, socket}
  end

  def handle_event("cancel-upload", %{"ref" => ref}, socket) do
    {:noreply, cancel_upload(socket, :tei_files, ref)}
  end

  def handle_event("import", _params, socket) do
    {successes, errors} =
      consume_uploaded_entries(socket, :tei_files, fn %{path: path}, entry ->
        result =
          case TeiParser.import_file(path) do
            {:ok, play} ->
              {:ok, {entry.client_name, play.title, play.code}}

            {:error, reason} ->
              {:error, {entry.client_name, reason}}
          end

        {:ok, result}
      end)
      |> split_results()

    socket =
      socket
      |> assign(:successes, successes)
      |> assign(:importing, false)

    socket =
      case errors do
        [] ->
          socket

        _ ->
          error_msg =
            Enum.map_join(errors, "\n", fn {file, reason} ->
              "#{file}: #{format_error(reason)}"
            end)

          put_flash(socket, :error, "Import errors:\n#{error_msg}")
      end

    socket =
      case successes do
        [] ->
          socket

        _ ->
          put_flash(socket, :info, "Successfully imported #{length(successes)} play(s).")
      end

    {:noreply, socket}
  end

  def handle_event("import_directory", %{"directory" => dir}, socket) do
    dir = String.trim(dir)

    case File.ls(dir) do
      {:ok, files} ->
        xml_files =
          files
          |> Enum.filter(&String.ends_with?(&1, ".xml"))
          |> Enum.sort()

        if xml_files == [] do
          {:noreply, put_flash(socket, :error, "No .xml files found in #{dir}")}
        else
          {successes, errors} =
            xml_files
            |> Enum.map(fn file ->
              path = Path.join(dir, file)

              case TeiParser.import_file(path) do
                {:ok, play} -> {:ok, {file, play.title, play.code}}
                {:error, reason} -> {:error, {file, reason}}
              end
            end)
            |> split_results()

          socket = assign(socket, :successes, successes)

          socket =
            case errors do
              [] ->
                socket

              _ ->
                error_msg =
                  Enum.map_join(errors, "\n", fn {file, reason} ->
                    "#{file}: #{format_error(reason)}"
                  end)

                put_flash(socket, :error, "Import errors:\n#{error_msg}")
            end

          socket =
            case successes do
              [] ->
                socket

              _ ->
                put_flash(socket, :info, "Successfully imported #{length(successes)} play(s).")
            end

          {:noreply, socket}
        end

      {:error, reason} ->
        {:noreply, put_flash(socket, :error, "Cannot read directory: #{format_error(reason)}")}
    end
  end

  defp split_results(results) do
    {oks, errs} = Enum.split_with(results, fn {status, _} -> status == :ok end)
    successes = Enum.map(oks, fn {:ok, val} -> val end)
    errors = Enum.map(errs, fn {:error, val} -> val end)
    {successes, errors}
  end

  defp format_error(reason) when is_atom(reason), do: to_string(reason)
  defp format_error({:xml_parse_error, detail}), do: "XML parse error: #{inspect(detail)}"
  defp format_error(reason), do: inspect(reason)

  @impl true
  def render(assigns) do
    ~H"""
    <div class="mx-auto max-w-5xl px-4 py-8">
      <div class="mb-6">
        <h1 class="text-3xl font-semibold tracking-tight text-base-content">Import TEI-XML Files</h1>
        <p class="mt-1 text-sm text-base-content/70">
          Import one or many TEI files and review successful ingestions.
        </p>
      </div>

      <%!-- Upload files from browser --%>
      <div class="card mb-6 border border-base-300 bg-base-100 shadow-sm">
        <div class="card-body">
          <h2 class="card-title">Select Files</h2>
          <p class="mb-3 text-sm text-base-content/70">
            Choose one or more TEI-XML files from your computer.
          </p>
          <form id="upload-form" phx-submit="import" phx-change="validate">
            <.live_file_input
              upload={@uploads.tei_files}
              class="file-input file-input-bordered w-full mb-4"
            />

            <div
              :for={entry <- @uploads.tei_files.entries}
              class="mb-2 flex items-center gap-3 rounded-box bg-base-200 px-2 py-1.5"
            >
              <span class="text-sm font-mono flex-1">{entry.client_name}</span>
              <progress value={entry.progress} max="100" class="progress progress-primary w-32" />
              <button
                type="button"
                phx-click="cancel-upload"
                phx-value-ref={entry.ref}
                class="btn btn-xs btn-ghost text-error"
              >
                Remove
              </button>
            </div>

            <div :for={err <- upload_errors(@uploads.tei_files)} class="text-error text-sm mb-2">
              {upload_error_to_string(err)}
            </div>

            <button
              type="submit"
              class="btn btn-primary mt-2"
              disabled={@uploads.tei_files.entries == []}
            >
              Import {length(@uploads.tei_files.entries)} file(s)
            </button>
          </form>
        </div>
      </div>

      <%!-- Import from server directory --%>
      <div class="card mb-6 border border-base-300 bg-base-100 shadow-sm">
        <div class="card-body">
          <h2 class="card-title">Import from Server Directory</h2>
          <p class="mb-3 text-sm text-base-content/70">
            Import all .xml files from a directory on the server.
          </p>
          <form phx-submit="import_directory" class="flex gap-3">
            <input
              type="text"
              name="directory"
              value="/home/bogdan/Downloads/tei_files"
              class="input input-bordered flex-1"
            />
            <button type="submit" class="btn btn-primary">
              Import Directory
            </button>
          </form>
        </div>
      </div>

      <%!-- Success results --%>
      <div :if={@successes != []} class="card border border-base-300 bg-base-100 shadow-sm">
        <div class="card-body">
          <h2 class="card-title">Imported Plays</h2>
          <div class="overflow-x-auto">
            <table class="table table-sm">
              <thead>
                <tr>
                  <th>File</th>
                  <th>Title</th>
                  <th>Code</th>
                  <th></th>
                </tr>
              </thead>
              <tbody>
                <tr :for={{filename, title, code} <- @successes}>
                  <td class="font-mono text-xs">{filename}</td>
                  <td>{title}</td>
                  <td>
                    <span class="badge badge-primary badge-sm">{code}</span>
                  </td>
                  <td>
                    <.link navigate={~p"/plays/#{code}"} class="btn btn-xs btn-ghost">
                      View
                    </.link>
                  </td>
                </tr>
              </tbody>
            </table>
          </div>
          <div class="card-actions mt-4">
            <.link navigate={~p"/admin/plays"} class="btn btn-sm btn-outline">
              View all plays
            </.link>
          </div>
        </div>
      </div>
    </div>
    """
  end

  defp upload_error_to_string(:too_large), do: "File is too large (max 20MB)"
  defp upload_error_to_string(:not_accepted), do: "Only .xml files are accepted"
  defp upload_error_to_string(:too_many_files), do: "Too many files (max 20)"
  defp upload_error_to_string(err), do: "Error: #{inspect(err)}"
end
