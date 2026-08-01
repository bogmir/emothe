defmodule EmotheWeb.Admin.PlayListLive do
  use EmotheWeb, :live_view

  alias Emothe.Catalogue
  alias Emothe.PlayContent
  alias Emothe.ActivityLog

  @per_page 50

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(:page_title, gettext("Admin - Plays"))
     |> assign(:plays, [])
     |> assign(:search, "")
     |> assign(:page, 1)
     |> assign(:total_pages, 1)
     |> assign(:breadcrumbs, [
       %{label: gettext("Admin"), to: ~p"/admin/plays"},
       %{label: gettext("Plays")}
     ])}
  end

  @impl true
  def handle_params(params, _url, socket) do
    search = params["search"] || ""
    page = parse_page(params["page"])
    archived = params["archived"] == "1"

    total = Catalogue.count_plays(search: search, archived: archived)
    total_pages = max(1, ceil(total / @per_page))
    page = min(page, total_pages)

    plays =
      Catalogue.list_plays(
        search: search,
        page: page,
        per_page: @per_page,
        archived: archived
      )

    if connected?(socket) do
      for play <- plays, do: PlayContent.subscribe(play.id)
    end

    {:noreply,
     socket
     |> assign(:plays, plays)
     |> assign(:search, search)
     |> assign(:page, page)
     |> assign(:total_pages, total_pages)
     |> assign(:archived, archived)
     |> assign(:archived_count, Catalogue.count_plays(archived: true))}
  end

  @impl true
  def handle_event("search", %{"search" => search}, socket) do
    params = if search == "", do: [], else: [search: search]
    {:noreply, push_patch(socket, to: ~p"/admin/plays?#{params}")}
  end

  def handle_event("delete", %{"id" => id}, socket) do
    play = Catalogue.get_play!(id)

    ActivityLog.log!(%{
      user_id: socket.assigns.current_user.id,
      play_id: play.id,
      action: "delete",
      resource_type: "play",
      resource_id: play.id,
      metadata: %{title: play.title, code: play.code, archived: true}
    })

    {:ok, _} = Catalogue.delete_play(play)

    {:noreply, reload(socket)}
  end

  def handle_event("restore", %{"id" => id}, socket) do
    play = Catalogue.get_play!(id, include_deleted: true)

    {:ok, _} = Catalogue.restore_play(play)

    ActivityLog.log!(%{
      user_id: socket.assigns.current_user.id,
      play_id: play.id,
      action: "update",
      resource_type: "play",
      resource_id: play.id,
      metadata: %{title: play.title, code: play.code, restored: true}
    })

    {:noreply, reload(socket)}
  end

  defp reload(socket) do
    opts = [search: socket.assigns.search, archived: socket.assigns.archived]

    total = Catalogue.count_plays(opts)
    total_pages = max(1, ceil(total / @per_page))
    page = min(socket.assigns.page, total_pages)
    plays = Catalogue.list_plays(opts ++ [page: page, per_page: @per_page])

    assign(socket,
      plays: plays,
      page: page,
      total_pages: total_pages,
      archived_count: Catalogue.count_plays(archived: true)
    )
  end

  @impl true
  def handle_info({:play_content_changed, _play_id}, socket) do
    {:noreply, reload(socket)}
  end

  defp parse_page(nil), do: 1

  defp parse_page(s) do
    case Integer.parse(s) do
      {n, ""} -> max(1, n)
      _ -> 1
    end
  end

  defp page_params("", page), do: [page: page]
  defp page_params(search, page), do: [search: search, page: page]

  @impl true
  def render(assigns) do
    ~H"""
    <div class="mx-auto max-w-7xl px-4 py-8">
      <div class="mb-6 flex flex-wrap items-center justify-between gap-4">
        <div>
          <h1 class="text-3xl font-semibold tracking-tight text-base-content">
            {gettext("Play Management")}
          </h1>
          <p class="mt-1 text-sm text-base-content/70">
            {gettext("Browse, edit, and curate imported plays.")}
          </p>
        </div>
        <div class="flex gap-2">
          <.link
            navigate={~p"/admin/plays/import"}
            class="btn btn-sm btn-success"
          >
            {gettext("Import TEI-XML")}
          </.link>
          <.link
            navigate={~p"/admin/plays/new"}
            class="btn btn-sm btn-primary"
          >
            {gettext("New Play")}
          </.link>
        </div>
      </div>

      <div class="mb-5 flex flex-wrap items-center gap-3">
        <form phx-change="search" phx-submit="search" class="flex-1 md:max-w-md">
          <input
            type="text"
            name="search"
            value={@search}
            placeholder={gettext("Search plays...")}
            phx-debounce="300"
            class="input input-bordered w-full"
          />
        </form>

        <.link
          :if={@archived_count > 0 or @archived}
          patch={if @archived, do: ~p"/admin/plays", else: ~p"/admin/plays?archived=1"}
          class={["btn btn-sm", @archived && "btn-active"]}
        >
          <.icon name="hero-archive-box-mini" class="size-4" />
          {gettext("Archived plays")}
          <span class="badge badge-sm">{@archived_count}</span>
        </.link>
      </div>

      <div class="overflow-x-auto rounded-box border border-base-300 bg-base-100 shadow-sm">
        <table class="table table-zebra">
          <thead>
            <tr class="text-xs uppercase tracking-wide text-base-content/60">
              <th class="w-28">{gettext("Code")}</th>
              <th>{gettext("Title")}</th>
              <th class="w-20 text-right">{gettext("Verses")}</th>
              <th class="w-32 text-right">{gettext("Actions")}</th>
            </tr>
          </thead>
          <tbody>
            <tr :for={play <- @plays} class="hover">
              <td class="font-mono text-xs text-base-content/60">
                {play.code}
                <.icon
                  :if={play.is_complete}
                  name="hero-check-circle-mini"
                  class="size-4 text-success ml-1 inline"
                />
              </td>
              <td>
                <.link
                  navigate={~p"/admin/plays/#{play.id}"}
                  class="font-medium text-base-content hover:text-primary"
                >
                  {play.title}
                </.link>
                <span :if={play.deleted_at} class="badge badge-ghost badge-sm ml-2">
                  {gettext("Archived")}
                </span>
                <p :if={play.author_name} class="text-xs text-base-content/60 mt-0.5">
                  {play.author_name}
                </p>
              </td>
              <td class="text-sm text-right tabular-nums text-base-content/70">
                {play.verse_count || "—"}
              </td>
              <td>
                <div class="flex items-center justify-end gap-1">
                  <.link
                    navigate={~p"/admin/plays/#{play.id}/edit"}
                    class="btn btn-ghost btn-xs tooltip tooltip-left"
                    data-tip={gettext("Edit metadata")}
                  >
                    <.icon name="hero-pencil-mini" class="size-4" />
                  </.link>
                  <.link
                    href={~p"/plays/#{play.code}"}
                    target="_blank"
                    class="btn btn-ghost btn-xs tooltip tooltip-left"
                    data-tip={gettext("View public page")}
                  >
                    <.icon name="hero-arrow-top-right-on-square-mini" class="size-4" />
                  </.link>
                  <button
                    :if={play.deleted_at}
                    phx-click="restore"
                    phx-value-id={play.id}
                    class="btn btn-ghost btn-xs text-success tooltip tooltip-left"
                    data-tip={gettext("Restore")}
                  >
                    <.icon name="hero-arrow-uturn-left-mini" class="size-4" />
                  </button>
                  <button
                    :if={is_nil(play.deleted_at)}
                    phx-click="delete"
                    phx-value-id={play.id}
                    data-confirm={
                      gettext("Archive «%{title}»? It is hidden from the site and can be restored.",
                        title: play.title
                      )
                    }
                    class="btn btn-ghost btn-xs text-error tooltip tooltip-left"
                    data-tip={gettext("Archive")}
                  >
                    <.icon name="hero-archive-box-mini" class="size-4" />
                  </button>
                </div>
              </td>
            </tr>
          </tbody>
        </table>
      </div>

      <p
        :if={@plays == []}
        class="mt-8 rounded-box border border-dashed border-base-300 py-10 text-center text-base-content/60"
      >
        {gettext("No plays yet. Import a TEI-XML file or create a new play.")}
      </p>

      <%!-- Pagination --%>
      <div :if={@total_pages > 1} class="mt-6 flex items-center justify-center gap-4">
        <.link
          :if={@page > 1}
          patch={~p"/admin/plays?#{page_params(@search, @page - 1)}"}
          class="btn btn-sm btn-ghost"
        >
          <.icon name="hero-chevron-left-mini" class="size-4" />{gettext("Previous")}
        </.link>
        <span class="text-sm text-base-content/60">
          {gettext("Page %{page} of %{total}", page: @page, total: @total_pages)}
        </span>
        <.link
          :if={@page < @total_pages}
          patch={~p"/admin/plays?#{page_params(@search, @page + 1)}"}
          class="btn btn-sm btn-ghost"
        >
          {gettext("Next")}<.icon name="hero-chevron-right-mini" class="size-4" />
        </.link>
      </div>
    </div>
    """
  end
end
