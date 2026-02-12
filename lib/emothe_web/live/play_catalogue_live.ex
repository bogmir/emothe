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
     |> assign(:search, "")}
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
      <h1 class="text-3xl font-bold text-gray-900 mb-2">EMOTHE Digital Library</h1>
      <p class="text-gray-600 mb-8">
        European Theatre of the 16th and 17th Centuries: Heritage and Digital Editions
      </p>

      <form phx-change="search" class="mb-8">
        <input
          type="text"
          name="search"
          value={@search}
          placeholder="Search by title, author, or code..."
          phx-debounce="300"
          class="w-full md:w-96 px-4 py-2 border border-gray-300 rounded-lg focus:ring-2 focus:ring-amber-500 focus:border-amber-500"
        />
      </form>

      <div class="grid gap-4">
        <div
          :for={play <- @plays}
          class="bg-white border border-gray-200 rounded-lg p-6 hover:shadow-md transition-shadow"
        >
          <.link navigate={~p"/plays/#{play.code}"} class="block">
            <div class="flex justify-between items-start">
              <div>
                <h2 class="text-xl font-semibold text-gray-900 hover:text-amber-700">
                  {play.title}
                </h2>
                <p :if={play.author_name} class="text-gray-600 mt-1">{play.author_name}</p>
              </div>
              <div class="text-right">
                <span class="inline-block bg-amber-100 text-amber-800 text-sm px-3 py-1 rounded-full">
                  {play.code}
                </span>
                <p :if={play.verse_count} class="text-sm text-gray-500 mt-1">
                  {play.verse_count} verses
                </p>
              </div>
            </div>
          </.link>
        </div>

        <p :if={@plays == []} class="text-gray-500 text-center py-12">
          No plays found. Try a different search term.
        </p>
      </div>
    </div>
    """
  end
end
