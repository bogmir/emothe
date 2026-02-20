defmodule EmotheWeb.Admin.PlayDetailLive do
  use EmotheWeb, :live_view

  import EmotheWeb.Components.StatisticsPanel

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
     |> assign(:statistic, statistic)
     |> assign(:breadcrumbs, [
       %{label: gettext("Admin"), to: ~p"/admin/plays"},
       %{label: gettext("Plays"), to: ~p"/admin/plays"},
       %{label: play.title}
     ])
     |> assign(:play_context, %{play: play, active_tab: :overview})}
  end

  @impl true
  def handle_event("recompute_stats", _, socket) do
    statistic = Statistics.recompute(socket.assigns.play.id)
    {:noreply, assign(socket, statistic: statistic) |> put_flash(:info, gettext("Statistics recomputed."))}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="mx-auto max-w-7xl px-4 py-8">
      <div class="mb-6 flex flex-wrap items-center justify-between gap-4">
        <div>
          <h1 class="text-3xl font-semibold tracking-tight text-base-content">{@play.title}</h1>
          <p class="mt-1 text-sm text-base-content/60">{@play.author_name} — {@play.code}</p>
        </div>
        <div class="flex items-center gap-1">
          <span class="text-xs text-base-content/40 mr-1">{gettext("Export")}</span>
          <a
            href={~p"/admin/plays/#{@play.id}/export/tei"}
            target="_blank"
            class="btn btn-ghost btn-xs tooltip"
            data-tip={gettext("Export TEI-XML")}
          >
            <.icon name="hero-code-bracket-mini" class="size-4" />
          </a>
          <a
            href={~p"/admin/plays/#{@play.id}/export/html"}
            target="_blank"
            class="btn btn-ghost btn-xs tooltip"
            data-tip={gettext("Export HTML")}
          >
            <.icon name="hero-globe-alt-mini" class="size-4" />
          </a>
          <a
            href={~p"/admin/plays/#{@play.id}/export/pdf"}
            target="_blank"
            class="btn btn-ghost btn-xs tooltip"
            data-tip={gettext("Export PDF")}
          >
            <.icon name="hero-document-arrow-down-mini" class="size-4" />
          </a>
        </div>
      </div>

      <%!-- Metadata --%>
      <section class="mb-8">
        <h2 class="mb-3 text-lg font-semibold text-base-content">{gettext("Metadata")}</h2>
        <div class="grid grid-cols-1 gap-4 rounded-box border border-base-300 bg-base-100 p-4 text-sm shadow-sm md:grid-cols-2">
          <div><span class="font-medium">{gettext("Language:")}</span> <span class="text-base-content/70">{@play.language}</span></div>
          <div>
            <span class="font-medium">{gettext("Verse count:")}</span>
            <span class="text-base-content/70">{@play.verse_count || gettext("N/A")}</span>
          </div>
          <div>
            <span class="font-medium">{gettext("Attribution:")}</span>
            <span class="text-base-content/70">{@play.author_attribution || gettext("N/A")}</span>
          </div>
          <div>
            <span class="font-medium">{gettext("Publication:")}</span>
            <span class="text-base-content/70">{@play.pub_place} ({@play.publication_date})</span>
          </div>
        </div>
      </section>

      <%!-- Editors --%>
      <section :if={@play.editors != []} class="mb-8">
        <h2 class="mb-3 text-lg font-semibold text-base-content">{gettext("Editors")}</h2>
        <div class="divide-y rounded-box border border-base-300 bg-base-100 shadow-sm">
          <div :for={editor <- @play.editors} class="flex items-center justify-between p-3">
            <span class="font-medium">{editor.person_name}</span>
            <span class="text-sm text-base-content/60">
              {editor.role} {if editor.organization, do: "— #{editor.organization}"}
            </span>
          </div>
        </div>
      </section>

      <%!-- Characters --%>
      <section :if={@characters != []} class="mb-8">
        <h2 class="mb-3 text-lg font-semibold text-base-content">
          {gettext("Characters")} ({length(@characters)})
        </h2>
        <div class="divide-y rounded-box border border-base-300 bg-base-100 shadow-sm">
          <div :for={char <- @characters} class="flex items-center gap-3 p-3">
            <span class="font-medium">{char.name}</span>
            <span :if={char.description} class="text-sm text-base-content/60">
              {char.description}
            </span>
            <span :if={char.is_hidden} class="badge badge-ghost badge-sm">
              {gettext("hidden")}
            </span>
          </div>
        </div>
      </section>

      <%!-- Structure --%>
      <section :if={@divisions != []} class="mb-8">
        <h2 class="mb-3 text-lg font-semibold text-base-content">{gettext("Structure")}</h2>
        <div class="divide-y rounded-box border border-base-300 bg-base-100 shadow-sm">
          <div :for={div <- @divisions} class="p-3">
            <span class="font-medium">{div.title || div.type}</span>
            <span class="ml-2 text-sm text-base-content/60">{div.type} {div.number}</span>
            <div :if={div.children != []} class="ml-6 mt-1">
              <div :for={child <- div.children} class="text-sm text-base-content/70">
                {child.title || child.type} {child.number}
              </div>
            </div>
          </div>
        </div>
      </section>

      <%!-- Statistics --%>
      <section class="mb-8">
        <div class="mb-3 flex items-center justify-between">
          <h2 class="text-lg font-semibold text-base-content">{gettext("Statistics")}</h2>
          <button phx-click="recompute_stats" class="btn btn-xs btn-ghost">
            <.icon name="hero-arrow-path-mini" class="size-4" /> {gettext("Recompute")}
          </button>
        </div>
        <div :if={@statistic} class="mb-4 text-xs text-base-content/60">
          {gettext("Last computed:")} {Calendar.strftime(@statistic.computed_at, "%Y-%m-%d %H:%M")}
        </div>
        <.stats_panel :if={@statistic} statistic={@statistic} play={@play} />
      </section>
    </div>
    """
  end
end
