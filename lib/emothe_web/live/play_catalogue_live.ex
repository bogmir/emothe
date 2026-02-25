defmodule EmotheWeb.PlayCatalogueLive do
  use EmotheWeb, :live_view

  alias Emothe.Catalogue

  @per_page 25

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(:page_title, gettext("Play Catalogue"))
     |> assign(:breadcrumbs, [%{label: gettext("Catalogue")}])
     |> assign(:plays, [])
     |> assign(:search, "")
     |> assign(:page, 1)
     |> assign(:total_pages, 1)}
  end

  @impl true
  def handle_params(params, _url, socket) do
    search = params["search"] || ""
    page = parse_page(params["page"])

    total = Catalogue.count_plays(search: search)
    total_pages = max(1, ceil(total / @per_page))
    page = min(page, total_pages)

    plays = Catalogue.list_plays(search: search, page: page, per_page: @per_page)

    {:noreply,
     socket
     |> assign(:plays, plays)
     |> assign(:search, search)
     |> assign(:page, page)
     |> assign(:total_pages, total_pages)}
  end

  @impl true
  def handle_event("search", %{"search" => search}, socket) do
    params = if search == "", do: [], else: [search: search]
    {:noreply, push_patch(socket, to: ~p"/plays?#{params}")}
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
    <div class="max-w-6xl mx-auto px-4 py-8">
      <h1 class="text-3xl font-bold text-base-content mb-2">{gettext("EMOTHE Digital Library")}</h1>
      <p class="text-base-content/70 mb-8">
        {gettext("European Theatre of the 16th and 17th Centuries: Heritage and Digital Editions")}
      </p>

      <form phx-change="search" phx-submit="search" class="mb-8">
        <input
          type="text"
          name="search"
          value={@search}
          placeholder={gettext("Search by title, author, or code...")}
          phx-debounce="300"
          class="input input-bordered w-full md:max-w-md"
        />
      </form>

      <div class="grid gap-3">
        <div
          :for={play <- @plays}
          class="rounded-box border border-base-300 bg-base-100 px-5 py-3.5 hover:shadow-md transition-shadow"
        >
          <div class="flex items-center gap-3">
            <.link
              href={~p"/plays/#{play.code}"}
              target="_blank"
              class="flex-1 min-w-0"
            >
              <span class="font-semibold text-base-content hover:text-primary transition-colors">
                {play.title}
              </span>
              <span :if={play.author_name} class="text-sm text-base-content/60 ml-2">
                {play.author_name}
              </span>
            </.link>
            <span
              :if={play.verse_count}
              class="text-xs text-base-content/40 tabular-nums hidden sm:inline"
            >
              {play.verse_count}v
            </span>
            <span class="badge badge-primary badge-outline badge-sm hidden md:inline-flex">
              {play.code}
            </span>
            <div class="flex items-center border-l border-base-200 pl-2 ml-1 gap-0.5">
              <a
                href={~p"/export/#{play.id}/tei"}
                class="btn btn-xs btn-ghost btn-square text-base-content/50 hover:text-primary tooltip tooltip-bottom"
                data-tip="TEI-XML"
              >
                <.icon name="hero-code-bracket-mini" class="size-3.5" />
              </a>
              <a
                href={~p"/export/#{play.id}/html"}
                class="btn btn-xs btn-ghost btn-square text-base-content/50 hover:text-primary tooltip tooltip-bottom"
                data-tip="HTML"
              >
                <.icon name="hero-globe-alt-mini" class="size-3.5" />
              </a>
              <a
                href={~p"/export/#{play.id}/pdf"}
                class="btn btn-xs btn-ghost btn-square text-base-content/50 hover:text-primary tooltip tooltip-bottom"
                data-tip="PDF"
              >
                <.icon name="hero-document-arrow-down-mini" class="size-3.5" />
              </a>
            </div>
          </div>
        </div>

        <p :if={@plays == []} class="text-base-content/50 text-center py-12">
          {gettext("No plays found. Try a different search term.")}
        </p>
      </div>

      <%!-- Pagination --%>
      <div :if={@total_pages > 1} class="mt-6 flex items-center justify-center gap-4">
        <.link
          :if={@page > 1}
          patch={~p"/plays?#{page_params(@search, @page - 1)}"}
          class="btn btn-sm btn-ghost"
        >
          <.icon name="hero-chevron-left-mini" class="size-4" />{gettext("Previous")}
        </.link>
        <span class="text-sm text-base-content/60">
          {gettext("Page %{page} of %{total}", page: @page, total: @total_pages)}
        </span>
        <.link
          :if={@page < @total_pages}
          patch={~p"/plays?#{page_params(@search, @page + 1)}"}
          class="btn btn-sm btn-ghost"
        >
          {gettext("Next")}<.icon name="hero-chevron-right-mini" class="size-4" />
        </.link>
      </div>
    </div>
    """
  end
end
