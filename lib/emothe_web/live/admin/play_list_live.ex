defmodule EmotheWeb.Admin.PlayListLive do
  use EmotheWeb, :live_view

  alias Emothe.Catalogue

  @impl true
  def mount(_params, _session, socket) do
    plays = Catalogue.list_plays()

    {:ok,
     socket
     |> assign(:page_title, "Admin - Plays")
     |> assign(:plays, plays)
     |> assign(:search, "")
     |> assign(:breadcrumbs, [
       %{label: "Admin", to: ~p"/admin/plays"},
       %{label: "Plays"}
     ])}
  end

  @impl true
  def handle_event("search", %{"search" => search}, socket) do
    plays = Catalogue.list_plays(search: search)
    {:noreply, assign(socket, plays: plays, search: search)}
  end

  def handle_event("delete", %{"id" => id}, socket) do
    play = Catalogue.get_play!(id)
    {:ok, _} = Catalogue.delete_play(play)
    plays = Catalogue.list_plays(search: socket.assigns.search)
    {:noreply, assign(socket, plays: plays)}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="mx-auto max-w-7xl px-4 py-8">
      <div class="mb-6 flex flex-wrap items-center justify-between gap-4">
        <div>
          <h1 class="text-3xl font-semibold tracking-tight text-base-content">Play Management</h1>
          <p class="mt-1 text-sm text-base-content/70">Browse, edit, and curate imported plays.</p>
        </div>
        <div class="flex gap-2">
          <.link
            navigate={~p"/admin/plays/import"}
            class="btn btn-sm btn-success"
          >
            Import TEI-XML
          </.link>
          <.link
            navigate={~p"/admin/plays/new"}
            class="btn btn-sm btn-primary"
          >
            New Play
          </.link>
        </div>
      </div>

      <form phx-change="search" class="mb-5">
        <input
          type="text"
          name="search"
          value={@search}
          placeholder="Search plays..."
          phx-debounce="300"
          class="input input-bordered w-full md:max-w-md"
        />
      </form>

      <div class="overflow-x-auto rounded-box border border-base-300 bg-base-100 shadow-sm">
        <table class="table table-zebra">
          <thead>
            <tr class="text-xs uppercase tracking-wide text-base-content/60">
              <th>Code</th>
              <th>Title</th>
              <th>Author</th>
              <th>Verses</th>
              <th>Actions</th>
            </tr>
          </thead>
          <tbody>
            <tr :for={play <- @plays} class="hover">
              <td class="font-mono text-sm text-base-content/75">{play.code}</td>
              <td>
                <.link
                  navigate={~p"/admin/plays/#{play.id}/content"}
                  class="font-medium text-base-content hover:underline"
                >
                  {play.title}
                </.link>
              </td>
              <td class="text-sm text-base-content/75">{play.author_name}</td>
              <td class="text-sm text-base-content/75">{play.verse_count || "-"}</td>
              <td>
                <div class="flex items-center gap-3 text-sm">
                  <.link navigate={~p"/admin/plays/#{play.id}/edit"} class="link link-primary">
                    Edit
                  </.link>
                  <.link navigate={~p"/plays/#{play.code}"} class="link link-hover">View</.link>
                  <button
                    phx-click="delete"
                    phx-value-id={play.id}
                    data-confirm="Are you sure you want to delete this play?"
                    class="link link-error"
                  >
                    Delete
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
        No plays yet. Import a TEI-XML file or create a new play.
      </p>
    </div>
    """
  end
end
