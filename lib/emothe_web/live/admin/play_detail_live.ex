defmodule EmotheWeb.Admin.PlayDetailLive do
  use EmotheWeb, :live_view

  alias Emothe.Catalogue
  alias Emothe.PlayContent
  alias Emothe.Statistics

  @impl true
  def mount(%{"id" => id}, _session, socket) do
    play = Catalogue.get_play_with_all!(id)
    characters = PlayContent.list_characters(play.id)
    divisions = PlayContent.list_top_divisions(play.id)
    statistic = Statistics.get_statistics(play.id)

    {:ok,
     socket
     |> assign(:page_title, "Admin: #{play.title}")
     |> assign(:play, play)
     |> assign(:characters, characters)
     |> assign(:divisions, divisions)
     |> assign(:statistic, statistic)}
  end

  @impl true
  def handle_event("recompute_stats", _, socket) do
    statistic = Statistics.recompute(socket.assigns.play.id)
    {:noreply, assign(socket, statistic: statistic) |> put_flash(:info, "Statistics recomputed.")}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="mx-auto max-w-7xl px-4 py-8">
      <div class="mb-6 flex flex-wrap items-start justify-between gap-4">
        <div>
          <h1 class="text-3xl font-semibold tracking-tight text-base-content">{@play.title}</h1>
          <p class="mt-1 text-sm text-base-content/70">{@play.author_name} — {@play.code}</p>
        </div>
        <div class="flex gap-2">
          <.link
            navigate={~p"/admin/plays/#{@play.id}/edit"}
            class="btn btn-sm btn-primary"
          >
            Edit Metadata
          </.link>
          <.link
            navigate={~p"/admin/plays/#{@play.id}/content"}
            class="btn btn-sm btn-secondary"
          >
            Edit Content
          </.link>
          <.link
            href={~p"/admin/plays/#{@play.id}/export/tei"}
            class="btn btn-sm btn-neutral"
          >
            TEI-XML
          </.link>
          <.link
            navigate={~p"/plays/#{@play.code}"}
            class="btn btn-sm btn-outline"
          >
            Public View
          </.link>
        </div>
      </div>

      <%!-- Metadata --%>
      <section class="mb-8">
        <h2 class="mb-3 text-lg font-semibold text-base-content">Metadata</h2>
        <div class="grid grid-cols-1 gap-4 rounded-box border border-base-300 bg-base-100 p-4 text-sm shadow-sm md:grid-cols-2">
          <div><span class="font-medium text-base-content/85">Language:</span> {@play.language}</div>
          <div>
            <span class="font-medium text-base-content/85">Verse count:</span> {@play.verse_count ||
              "N/A"}
          </div>
          <div>
            <span class="font-medium text-base-content/85">Attribution:</span> {@play.author_attribution ||
              "N/A"}
          </div>
          <div>
            <span class="font-medium text-base-content/85">Publication:</span> {@play.pub_place} ({@play.publication_date})
          </div>
        </div>
      </section>

      <%!-- Editors --%>
      <section :if={@play.editors != []} class="mb-8">
        <h2 class="mb-3 text-lg font-semibold text-base-content">Editors</h2>
        <div class="divide-y rounded-box border border-base-300 bg-base-100 shadow-sm">
          <div :for={editor <- @play.editors} class="flex items-center justify-between p-3">
            <span>{editor.person_name}</span>
            <span class="text-sm text-base-content/70">
              {editor.role} {if editor.organization, do: "— #{editor.organization}"}
            </span>
          </div>
        </div>
      </section>

      <%!-- Characters --%>
      <section :if={@characters != []} class="mb-8">
        <h2 class="mb-3 text-lg font-semibold text-base-content">
          Characters ({length(@characters)})
        </h2>
        <div class="divide-y rounded-box border border-base-300 bg-base-100 shadow-sm">
          <div :for={char <- @characters} class="flex items-center gap-3 p-3">
            <span class="font-medium">{char.name}</span>
            <span :if={char.description} class="text-sm text-base-content/70">
              {char.description}
            </span>
            <span :if={char.is_hidden} class="badge badge-ghost badge-sm">
              hidden
            </span>
          </div>
        </div>
      </section>

      <%!-- Structure --%>
      <section :if={@divisions != []} class="mb-8">
        <h2 class="mb-3 text-lg font-semibold text-base-content">Structure</h2>
        <div class="divide-y rounded-box border border-base-300 bg-base-100 shadow-sm">
          <div :for={div <- @divisions} class="p-3">
            <span class="font-medium">{div.title || div.type}</span>
            <span class="ml-2 text-sm text-base-content/70">{div.type} {div.number}</span>
            <div :if={div.children != []} class="ml-6 mt-1">
              <div :for={child <- div.children} class="text-sm text-base-content/75">
                {child.title || child.type} {child.number}
              </div>
            </div>
          </div>
        </div>
      </section>

      <%!-- Statistics --%>
      <section class="mb-8">
        <div class="mb-3 flex items-center justify-between">
          <h2 class="text-lg font-semibold text-base-content">Statistics</h2>
          <button phx-click="recompute_stats" class="btn btn-xs btn-ghost">
            Recompute
          </button>
        </div>
        <div :if={@statistic} class="mb-2 text-sm text-base-content/70">
          Last computed: {Calendar.strftime(@statistic.computed_at, "%Y-%m-%d %H:%M")}
        </div>
        <pre
          :if={@statistic}
          class="overflow-auto rounded-box border border-base-300 bg-base-100 p-4 text-xs shadow-sm"
        >
          {Jason.encode!(@statistic.data, pretty: true)}
        </pre>
      </section>
    </div>
    """
  end
end
