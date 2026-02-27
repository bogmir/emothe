defmodule EmotheWeb.Admin.ImportLive do
  use EmotheWeb, :live_view

  # alias Emothe.Export.TeiValidator
  alias Emothe.Import.TeiParser

  require Logger

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(:page_title, gettext("Import TEI-XML"))
     |> assign(:successes, [])
     |> assign(:errors, [])
     |> assign(:importing, false)
     |> assign(:import_total, 0)
     |> assign(:import_done, 0)
     |> assign(:breadcrumbs, [
       %{label: gettext("Admin"), to: ~p"/admin/plays"},
       %{label: gettext("Plays"), to: ~p"/admin/plays"},
       %{label: gettext("Import TEI-XML")}
     ])
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
    # Consume uploads: copy each to a stable temp path so we can process async
    pending_files =
      consume_uploaded_entries(socket, :tei_files, fn %{path: path}, entry ->
        dest =
          Path.join(System.tmp_dir!(), "emothe-import-#{System.unique_integer([:positive])}.xml")

        File.cp!(path, dest)
        {:ok, {dest, entry.client_name}}
      end)

    send(self(), {:import_next, pending_files})

    {:noreply,
     socket
     |> assign(:importing, true)
     |> assign(:successes, [])
     |> assign(:errors, [])
     |> assign(:import_total, length(pending_files))
     |> assign(:import_done, 0)}
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
          {:noreply,
           put_flash(socket, :error, gettext("No .xml files found in %{dir}", dir: dir))}
        else
          pending =
            Enum.map(xml_files, fn file ->
              {Path.join(dir, file), file}
            end)

          send(self(), {:import_next, pending})

          {:noreply,
           socket
           |> assign(:importing, true)
           |> assign(:successes, [])
           |> assign(:errors, [])
           |> assign(:import_total, length(pending))
           |> assign(:import_done, 0)}
        end

      {:error, reason} ->
        {:noreply,
         put_flash(
           socket,
           :error,
           "#{gettext("Cannot read directory")}: #{format_error(reason)}"
         )}
    end
  end

  @impl true
  def handle_info({:import_next, []}, socket) do
    successes = Enum.reverse(socket.assigns.successes)
    errors = Enum.reverse(socket.assigns.errors)

    socket = assign(socket, :importing, false)
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

          put_flash(socket, :error, "#{gettext("Import errors")}:\n#{error_msg}")
      end

    socket =
      case successes do
        [] ->
          socket

        _ ->
          put_flash(
            socket,
            :info,
            gettext("Successfully imported %{count} play(s).", count: length(successes))
          )
      end

    {:noreply, socket}
  end

  def handle_info({:import_next, [{path, filename} | rest]}, socket) do
    socket =
      case TeiParser.import_file(path) do
        {:ok, play} ->
          # validation_warnings = validate_source_file(path)
          validation_warnings = []
          success = {filename, play.title, play.code, play.id, validation_warnings}
          update(socket, :successes, &[success | &1])

        {:error, reason} ->
          update(socket, :errors, &[{filename, reason} | &1])
      end

    # Clean up temp files created by upload consume (not directory imports)
    if String.starts_with?(path, System.tmp_dir!()) do
      File.rm(path)
    end

    send(self(), {:import_next, rest})
    {:noreply, update(socket, :import_done, &(&1 + 1))}
  end

  defp validate_source_file(path) do
    case File.read(path) do
      {:ok, xml} ->
        case TeiValidator.validate(xml) do
          {:ok, :valid} -> []
          {:error, errors} when is_list(errors) -> errors
          {:error, _atom} -> []
        end

      {:error, _} ->
        []
    end
  end

  defp format_error(reason) when is_atom(reason), do: to_string(reason)
  defp format_error({:xml_parse_error, detail}), do: "XML parse error: #{inspect(detail)}"

  defp format_error({:play_already_exists, code}),
    do: gettext("Play with code %{code} already exists", code: code)

  defp format_error(reason), do: inspect(reason)

  @impl true
  def render(assigns) do
    ~H"""
    <div class="mx-auto max-w-5xl px-4 py-8">
      <div class="mb-6">
        <h1 class="text-3xl font-semibold tracking-tight text-base-content">
          {gettext("Import TEI-XML Files")}
        </h1>
        <p class="mt-1 text-sm text-base-content/70">
          {gettext("Import one or many TEI files and review successful ingestions.")}
        </p>
      </div>

      <%!-- Upload files from browser --%>
      <div class="card mb-6 border border-base-300 bg-base-100 shadow-sm">
        <div class="card-body">
          <h2 class="card-title">{gettext("Select Files")}</h2>
          <p class="mb-3 text-sm text-base-content/70">
            {gettext("Choose one or more TEI-XML files from your computer.")}
          </p>
          <form id="upload-form" phx-submit="import" phx-change="validate">
            <.live_file_input
              upload={@uploads.tei_files}
              class="file-input file-input-bordered w-full mb-4"
              disabled={@importing}
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
                class="btn btn-ghost btn-xs text-error tooltip"
                data-tip={gettext("Remove")}
              >
                <.icon name="hero-x-mark-mini" class="size-4" />
              </button>
            </div>

            <div :for={err <- upload_errors(@uploads.tei_files)} class="text-error text-sm mb-2">
              {upload_error_to_string(err)}
            </div>

            <button
              type="submit"
              class="btn btn-primary mt-2"
              disabled={@uploads.tei_files.entries == [] || @importing}
            >
              {gettext("Import %{count} file(s)", count: length(@uploads.tei_files.entries))}
            </button>
          </form>
        </div>
      </div>

      <%!-- Import progress --%>
      <div :if={@importing} class="card mb-6 border border-base-300 bg-base-100 shadow-sm">
        <div class="card-body">
          <div class="flex items-center gap-3">
            <span class="loading loading-spinner loading-md text-primary"></span>
            <span class="font-medium">
              {gettext("Importing file %{done} of %{total}...",
                done: @import_done + 1,
                total: @import_total
              )}
            </span>
          </div>
          <progress
            value={@import_done}
            max={@import_total}
            class="progress progress-primary w-full mt-2"
          />
        </div>
      </div>

      <%!-- Success results --%>
      <div
        :if={@successes != [] && !@importing}
        class="card border border-base-300 bg-base-100 shadow-sm"
      >
        <div class="card-body">
          <h2 class="card-title">{gettext("Imported Plays")}</h2>
          <div class="overflow-x-auto">
            <table class="table table-sm">
              <thead>
                <tr>
                  <th>{gettext("File")}</th>
                  <th>{gettext("Title")}</th>
                  <th>{gettext("Code")}</th>
                  <th>{gettext("Schema")}</th>
                  <th></th>
                </tr>
              </thead>
              <tbody>
                <tr :for={{filename, title, code, play_id, warnings} <- @successes}>
                  <td class="font-mono text-xs">{filename}</td>
                  <td>{title}</td>
                  <td>
                    <span class="badge badge-primary badge-sm">{code}</span>
                  </td>
                  <td>
                    <%= if warnings == [] do %>
                      <span class="badge badge-success badge-sm gap-1">
                        <.icon name="hero-check-mini" class="size-3" />
                        {gettext("Valid")}
                      </span>
                    <% else %>
                      <details>
                        <summary class="badge badge-warning badge-sm gap-1 cursor-pointer">
                          <.icon name="hero-exclamation-triangle-mini" class="size-3" />
                          {gettext("%{count} warning(s)", count: length(warnings))}
                        </summary>
                        <ul class="mt-2 ml-2 text-xs font-mono text-base-content/70 space-y-1 max-h-40 overflow-y-auto">
                          <li :for={w <- Enum.take(warnings, 10)}>{w}</li>
                          <li :if={length(warnings) > 10} class="text-base-content/50">
                            … {gettext("and %{count} more", count: length(warnings) - 10)}
                          </li>
                        </ul>
                      </details>
                    <% end %>
                  </td>
                  <td class="flex gap-1">
                    <.link
                      navigate={~p"/admin/plays/#{play_id}"}
                      class="btn btn-ghost btn-xs tooltip"
                      data-tip={gettext("Edit in Admin")}
                    >
                      <.icon name="hero-pencil-square-mini" class="size-4" />
                    </.link>
                    <.link
                      href={~p"/plays/#{code}"}
                      target="_blank"
                      class="btn btn-ghost btn-xs tooltip"
                      data-tip={gettext("View public page")}
                    >
                      <.icon name="hero-arrow-top-right-on-square-mini" class="size-4" />
                    </.link>
                  </td>
                </tr>
              </tbody>
            </table>
          </div>
          <div class="card-actions mt-4">
            <.link navigate={~p"/admin/plays"} class="btn btn-sm btn-outline">
              {gettext("View all plays")}
            </.link>
          </div>
        </div>
      </div>
    </div>
    """
  end

  defp upload_error_to_string(:too_large), do: gettext("File is too large (max 20MB)")
  defp upload_error_to_string(:not_accepted), do: gettext("Only .xml files are accepted")
  defp upload_error_to_string(:too_many_files), do: gettext("Too many files (max 20)")
  defp upload_error_to_string(err), do: "#{gettext("Error")}: #{inspect(err)}"
end
