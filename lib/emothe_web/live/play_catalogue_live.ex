defmodule EmotheWeb.PlayCatalogueLive do
  use EmotheWeb, :live_view

  alias Emothe.Catalogue

  @impl true
  def mount(_params, _session, socket) do
    plays = Catalogue.list_plays()

    {:ok,
     socket
     |> assign(:page_title, gettext("Play Catalogue"))
     |> assign(:plays, plays)
     |> assign(:search, "")
     |> assign(:breadcrumbs, [%{label: gettext("Catalogue")}])}
  end

  @impl true
  def handle_event("search", %{"search" => search}, socket) do
    plays = Catalogue.list_plays(search: search)
    {:noreply, assign(socket, plays: plays, search: search)}
  end

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
              navigate={~p"/plays/#{play.code}"}
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
    </div>
    """
  end
end
