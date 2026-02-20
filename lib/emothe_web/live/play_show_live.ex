defmodule EmotheWeb.PlayShowLive do
  use EmotheWeb, :live_view

  import EmotheWeb.Components.PlayText
  import EmotheWeb.Components.StatisticsPanel

  alias Emothe.Catalogue
  alias Emothe.PlayContent
  alias Emothe.Statistics

  @impl true
  def mount(%{"code" => code}, _session, socket) do
    play = Catalogue.get_play_by_code_with_all!(code)
    divisions = PlayContent.load_play_content(play.id)
    characters = PlayContent.list_characters(play.id)
    statistic = Statistics.get_statistics(play.id)

    %{metadata: metadata_sections, play: play_sections} =
      build_sections_navigation(play, divisions)

    {:ok,
     socket
     |> assign(:page_title, play.title)
     |> assign(:play, play)
     |> assign(:divisions, divisions)
     |> assign(:characters, characters)
     |> assign(:statistic, statistic)
     |> assign(:metadata_sections, metadata_sections)
     |> assign(:play_sections, play_sections)
     |> assign(:show_line_numbers, true)
     |> assign(:show_stage_directions, true)
     |> assign(:active_tab, :text)
     |> assign(:sidebar_open, true)
     |> assign(:breadcrumbs, [
       %{label: gettext("Catalogue"), to: ~p"/plays"},
       %{label: play.title}
     ])}
  end

  @impl true
  def handle_event("toggle_line_numbers", _, socket) do
    {:noreply, assign(socket, :show_line_numbers, !socket.assigns.show_line_numbers)}
  end

  def handle_event("toggle_stage_directions", _, socket) do
    {:noreply, assign(socket, :show_stage_directions, !socket.assigns.show_stage_directions)}
  end

  def handle_event("switch_tab", %{"tab" => tab}, socket) do
    {:noreply, assign(socket, :active_tab, String.to_existing_atom(tab))}
  end

  def handle_event("toggle_sidebar", _, socket) do
    {:noreply, assign(socket, :sidebar_open, !socket.assigns.sidebar_open)}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="play-text-page min-h-screen">
      <div class="max-w-7xl mx-auto px-4 py-6 lg:grid lg:grid-cols-[16rem_minmax(0,1fr)] lg:gap-6">
        <%!-- Sidebar toggle (mobile + desktop) --%>
        <aside id="play-sections-panel" class="mb-4 lg:mb-0 lg:sticky lg:top-4 lg:self-start">
          <div class="rounded-box border border-base-300 bg-base-100/90 backdrop-blur-sm shadow-sm">
            <button
              phx-click="toggle_sidebar"
              class="flex w-full items-center justify-between gap-2 px-3 py-2.5 text-sm font-semibold text-primary cursor-pointer"
            >
              <span class="flex items-center gap-2">
                <.icon name="hero-list-bullet-micro" class="size-4" /> {gettext("Contents")}
              </span>
              <.icon
                name={if @sidebar_open, do: "hero-chevron-up-micro", else: "hero-chevron-down-micro"}
                class="size-4 text-base-content/40"
              />
            </button>

            <div
              :if={@sidebar_open}
              id="scroll-spy-nav"
              phx-hook="ScrollSpy"
              class="border-t border-base-300 max-h-[65vh] overflow-y-auto px-2 py-2 space-y-3"
            >
              <section :if={@metadata_sections != []}>
                <h3 class="px-2 pt-1 text-[10px] font-semibold uppercase tracking-widest text-base-content/40">
                  {gettext("Metadata")}
                </h3>
                <nav class="mt-1 space-y-px">
                  <a
                    :for={section <- @metadata_sections}
                    href={"##{section.id}"}
                    class="block rounded-md px-2 py-1 text-xs text-base-content/70 transition-colors hover:bg-primary/10 hover:text-primary active:bg-primary/20"
                  >
                    {section.label}
                  </a>
                </nav>
              </section>

              <section :if={@play_sections != []}>
                <h3 class="px-2 pt-1 text-[10px] font-semibold uppercase tracking-widest text-base-content/40">
                  {gettext("Sections")}
                </h3>
                <nav class="mt-1 space-y-px">
                  <a
                    :for={section <- @play_sections}
                    href={"##{section.id}"}
                    class="block rounded-md py-1 text-xs text-base-content/70 transition-colors hover:bg-primary/10 hover:text-primary active:bg-primary/20"
                    style={"padding-left: #{0.5 + section.depth * 0.625}rem"}
                  >
                    {section.label}
                  </a>
                </nav>
              </section>
            </div>
          </div>

          <%!-- Admin/researcher quick link --%>
          <.link
            :if={assigns[:current_user]}
            navigate={~p"/admin/plays/#{@play.id}"}
            class="mt-2 flex items-center gap-1.5 rounded-box border border-base-300 bg-base-100/90 px-3 py-2 text-xs text-base-content/60 hover:text-primary hover:border-primary/30 transition-colors"
          >
            <.icon name="hero-pencil-square-micro" class="size-3.5" /> {gettext("Edit in Admin")}
          </.link>
        </aside>

        <div>
          <%!-- Header --%>
          <header
            id="meta-overview"
            class="play-header mb-8 border-b border-base-300 pb-6 scroll-mt-20 text-center"
          >
            <h2 class="play-author">{@play.author_name}</h2>
            <h1 class="play-title font-bold">{@play.title}</h1>

            <%!-- Source info --%>
            <div :if={@play.sources != []} id="meta-sources" class="scroll-mt-20">
              <div :for={source <- @play.sources} class="mt-4 text-xs text-base-content/50">
                <p :if={source.note} class="italic">{source.note}</p>
              </div>
            </div>

            <%!-- Editors --%>
            <div
              :if={@play.editors != []}
              id="meta-editors"
              class="mt-3 flex flex-wrap justify-center gap-2 scroll-mt-20"
            >
              <span :for={editor <- @play.editors} class="text-xs text-base-content/50">
                {editor.person_name}
                <span class="text-base-content/35">({editor.role})</span>
              </span>
            </div>

            <p :if={@play.verse_count} class="mt-2 text-xs text-base-content/50">
              {if @play.is_verse, do: "#{@play.verse_count} #{gettext("verses")}", else: gettext("Prose")}
            </p>
          </header>

          <%!-- Editorial notes --%>
          <div
            :for={{note, index} <- Enum.with_index(@play.editorial_notes, 1)}
            id={"meta-note-#{index}"}
            class="mb-6 max-w-2xl mx-auto scroll-mt-20 text-justify text-sm"
          >
            <h3 :if={note.heading} class="font-bold text-center mb-2">{note.heading}</h3>
            <div class="whitespace-pre-line">{note.content}</div>
          </div>

          <%!-- Tab navigation --%>
          <nav id="play-tab-nav" class="flex border-b border-stone-300 mb-6">
            <button
              :for={
                tab <- [{:text, gettext("Text")}, {:characters, gettext("Characters")}, {:statistics, gettext("Statistics")}]
              }
              phx-click="switch_tab"
              phx-value-tab={elem(tab, 0)}
              class={[
                "px-4 py-2.5 text-sm font-medium border-b-2 -mb-px transition-colors cursor-pointer",
                if(@active_tab == elem(tab, 0),
                  do: "border-amber-700 text-amber-800",
                  else: "border-transparent text-stone-500 hover:text-stone-700"
                )
              ]}
            >
              {elem(tab, 1)}
            </button>
          </nav>

          <%!-- Text tab --%>
          <div :if={@active_tab == :text} id="play-tab-text">
            <%!-- Controls --%>
            <div class="flex gap-4 mb-6 p-2.5 bg-base-200/50 rounded-box border border-base-300">
              <label class="flex items-center gap-2 text-xs cursor-pointer text-base-content/70">
                <input
                  type="checkbox"
                  checked={@show_line_numbers}
                  phx-click="toggle_line_numbers"
                  class="checkbox checkbox-xs checkbox-primary"
                /> {gettext("Line numbers")}
              </label>
              <label class="flex items-center gap-2 text-xs cursor-pointer text-base-content/70">
                <input
                  type="checkbox"
                  checked={@show_stage_directions}
                  phx-click="toggle_stage_directions"
                  class="checkbox checkbox-xs checkbox-primary"
                /> {gettext("Stage directions")}
              </label>
            </div>

            <.play_body
              divisions={@divisions}
              show_line_numbers={@show_line_numbers}
              show_stage_directions={@show_stage_directions}
            />
          </div>

          <%!-- Characters tab --%>
          <div :if={@active_tab == :characters} id="play-tab-characters">
            <h2 class="text-lg font-bold mb-4 text-base-content">{gettext("Dramatis Personae")}</h2>
            <div class="grid gap-2 max-w-2xl">
              <div
                :for={char <- Enum.filter(@characters, &(!&1.is_hidden))}
                class="flex items-center gap-3 p-3 bg-base-100/60 border border-base-300 rounded-box"
              >
                <span class="font-semibold text-base-content">{char.name}</span>
                <span :if={char.description} class="text-sm text-base-content/50">
                  {char.description}
                </span>
              </div>
            </div>
          </div>

          <%!-- Statistics tab --%>
          <div :if={@active_tab == :statistics} id="play-tab-statistics">
            <.stats_panel statistic={@statistic} play={@play} />
          </div>
        </div>
      </div>
    </div>
    """
  end

  defp build_sections_navigation(play, divisions) do
    metadata_sections = build_metadata_sections(play)
    play_sections = divisions |> Enum.flat_map(&division_navigation_item(&1, 0))

    %{metadata: metadata_sections, play: play_sections}
  end

  defp build_metadata_sections(play) do
    base = [%{id: "meta-overview", label: gettext("Overview")}]

    base
    |> maybe_add_section(play.sources != [], "meta-sources", gettext("Source"))
    |> maybe_add_section(play.editors != [], "meta-editors", gettext("Editors"))
    |> Kernel.++(build_editorial_note_sections(play.editorial_notes))
  end

  defp maybe_add_section(sections, true, id, label), do: sections ++ [%{id: id, label: label}]
  defp maybe_add_section(sections, false, _id, _label), do: sections

  defp build_editorial_note_sections(notes) do
    notes
    |> Enum.with_index(1)
    |> Enum.map(fn {note, index} ->
      label =
        case note.heading do
          heading when is_binary(heading) and heading != "" -> heading
          _ -> "#{gettext("Editorial Note")} #{index}"
        end

      %{id: "meta-note-#{index}", label: label}
    end)
  end

  defp division_navigation_item(division, depth) do
    current =
      case division.title do
        title when is_binary(title) and title != "" ->
          [%{id: "div-#{division.id}", label: title, depth: depth}]

        _ ->
          []
      end

    children =
      division
      |> Map.get(:children, [])
      |> Enum.flat_map(&division_navigation_item(&1, depth + 1))

    current ++ children
  end
end
