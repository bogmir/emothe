defmodule EmotheWeb.PlayCatalogueLive do
  use EmotheWeb, :live_view

  alias Emothe.Catalogue

  @impl true
  def mount(_params, _session, socket) do
    plays = Catalogue.list_plays()

    {:ok,
     socket
     |> assign(:page_title, "Play Catalogue")
     |> assign(:plays, plays)
     |> assign(:search, "")
     |> assign(:breadcrumbs, [%{label: "Catalogue"}])}
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
      <h1 class="text-3xl font-bold text-base-content mb-2">EMOTHE Digital Library</h1>
      <p class="text-base-content/70 mb-8">
        European Theatre of the 16th and 17th Centuries: Heritage and Digital Editions
      </p>

      <form phx-change="search" phx-submit="search" class="mb-8">
        <input
          type="text"
          name="search"
          value={@search}
          placeholder="Search by title, author, or code..."
          phx-debounce="300"
          class="input input-bordered w-full md:max-w-md"
        />
      </form>

      <div class="grid gap-3">
        <.link
          :for={play <- @plays}
          navigate={~p"/plays/#{play.code}"}
          class="block rounded-box border border-base-300 bg-base-100 p-5 hover:shadow-md transition-shadow"
        >
          <div class="flex justify-between items-start">
            <div>
              <h2 class="text-lg font-semibold text-base-content hover:text-primary">
                {play.title}
              </h2>
              <p :if={play.author_name} class="text-sm text-base-content/70 mt-1">
                {play.author_name}
              </p>
            </div>
            <div class="text-right flex-shrink-0 ml-4">
              <span class="badge badge-primary badge-outline">{play.code}</span>
              <p :if={play.verse_count} class="text-xs text-base-content/50 mt-1">
                {play.verse_count} verses
              </p>
            </div>
          </div>
        </.link>

        <p :if={@plays == []} class="text-base-content/50 text-center py-12">
          No plays found. Try a different search term.
        </p>
      </div>
    </div>
    """
  end
end
