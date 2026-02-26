defmodule EmotheWeb.Admin.PlayCompareLive do
  use EmotheWeb, :live_view

  import EmotheWeb.Components.PlayText

  alias Emothe.Catalogue
  alias Emothe.PlayContent

  @impl true
  def mount(%{"id" => id}, _session, socket) do
    play = Catalogue.get_play_with_all!(id)

    if play.relationship_type != "traduccion" || is_nil(play.parent_play_id) do
      {:ok,
       socket
       |> put_flash(:error, gettext("This play is not a translation with a linked original."))
       |> redirect(to: ~p"/admin/plays/#{id}")}
    else
      parent = Catalogue.get_play_with_all!(play.parent_play_id)
      play_divisions = PlayContent.load_play_content(play.id)
      parent_divisions = PlayContent.load_play_content(parent.id)
      play_characters = PlayContent.list_characters(play.id)
      parent_characters = PlayContent.list_characters(parent.id)

      {:ok,
       socket
       |> assign(:page_title, gettext("Compare: %{title}", title: play.title))
       |> assign(:play, play)
       |> assign(:parent_play, parent)
       |> assign(:play_divisions, play_divisions)
       |> assign(:parent_divisions, parent_divisions)
       |> assign(:play_characters, play_characters)
       |> assign(:parent_characters, parent_characters)
       |> assign(:show_line_numbers, true)
       |> assign(:show_stage_directions, true)
       |> assign(:show_asides, true)
       |> assign(:show_split_verses, false)
       |> assign(:show_verse_type, false)
       |> assign(:breadcrumbs, [
         %{label: gettext("Admin"), to: ~p"/admin/plays"},
         %{label: gettext("Plays"), to: ~p"/admin/plays"},
         %{label: play.title, to: ~p"/admin/plays/#{play.id}"},
         %{label: gettext("Comparison")}
       ])
       |> assign(:play_context, %{play: play, active_tab: :compare})}
    end
  end

  @impl true
  def handle_event("toggle_line_numbers", _, socket) do
    {:noreply, assign(socket, :show_line_numbers, !socket.assigns.show_line_numbers)}
  end

  def handle_event("toggle_stage_directions", _, socket) do
    {:noreply, assign(socket, :show_stage_directions, !socket.assigns.show_stage_directions)}
  end

  def handle_event("toggle_asides", _, socket) do
    {:noreply, assign(socket, :show_asides, !socket.assigns.show_asides)}
  end

  def handle_event("toggle_split_verses", _, socket) do
    {:noreply, assign(socket, :show_split_verses, !socket.assigns.show_split_verses)}
  end

  def handle_event("toggle_verse_type", _, socket) do
    {:noreply, assign(socket, :show_verse_type, !socket.assigns.show_verse_type)}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="mx-auto max-w-full px-4 py-4">
      <%!-- Toolbar --%>
      <div class="mb-4 flex flex-wrap items-center gap-4 rounded-box border border-base-300 bg-base-100 px-4 py-2 shadow-sm">
        <span class="text-xs font-semibold text-base-content/50">{gettext("Display")}</span>
        <label class="flex items-center gap-1.5 text-xs cursor-pointer">
          <input
            type="checkbox"
            checked={@show_line_numbers}
            phx-click="toggle_line_numbers"
            class="checkbox checkbox-xs checkbox-primary"
          /> {gettext("Line numbers")}
        </label>
        <label class="flex items-center gap-1.5 text-xs cursor-pointer">
          <input
            type="checkbox"
            checked={@show_stage_directions}
            phx-click="toggle_stage_directions"
            class="checkbox checkbox-xs checkbox-primary"
          /> {gettext("Stage directions")}
        </label>
        <label class="flex items-center gap-1.5 text-xs cursor-pointer">
          <input
            type="checkbox"
            checked={@show_asides}
            phx-click="toggle_asides"
            class="checkbox checkbox-xs checkbox-primary"
          /> {gettext("Asides")}
        </label>
        <label class="flex items-center gap-1.5 text-xs cursor-pointer">
          <input
            type="checkbox"
            checked={@show_split_verses}
            phx-click="toggle_split_verses"
            class="checkbox checkbox-xs checkbox-primary"
          /> {gettext("Split verses")}
        </label>
        <label class="flex items-center gap-1.5 text-xs cursor-pointer">
          <input
            type="checkbox"
            checked={@show_verse_type}
            phx-click="toggle_verse_type"
            class="checkbox checkbox-xs checkbox-primary"
          /> {gettext("Verse type")}
        </label>
      </div>

      <%!-- Two-column comparison --%>
      <div id="sync-scroll" phx-hook="SyncScroll" class="grid grid-cols-2 gap-4">
        <%!-- Left: Original --%>
        <div class="flex flex-col rounded-box border border-base-300 bg-base-100 shadow-sm">
          <div class="sticky top-0 z-10 border-b border-base-300 bg-base-100/95 backdrop-blur-sm px-4 py-2">
            <div class="flex items-center gap-2">
              <span class="badge badge-ghost badge-sm">{gettext("Original")}</span>
              <span class="text-sm font-semibold truncate">{@parent_play.title}</span>
            </div>
            <p class="text-xs text-base-content/50 truncate">
              {@parent_play.author_name} — {@parent_play.code}
            </p>
          </div>
          <div
            class="overflow-y-auto px-4 py-4 compare-panel"
            data-panel="left"
            style="max-height: calc(100vh - 220px);"
          >
            <.play_body
              divisions={@parent_divisions}
              characters={@parent_characters}
              show_line_numbers={@show_line_numbers}
              show_stage_directions={@show_stage_directions}
              show_asides={@show_asides}
              show_split_verses={@show_split_verses}
              show_verse_type={@show_verse_type}
              sync_keys={true}
            />
          </div>
        </div>

        <%!-- Right: Translation --%>
        <div class="flex flex-col rounded-box border border-base-300 bg-base-100 shadow-sm">
          <div class="sticky top-0 z-10 border-b border-base-300 bg-base-100/95 backdrop-blur-sm px-4 py-2">
            <div class="flex items-center gap-2">
              <span class="badge badge-primary badge-sm">{gettext("Translation")}</span>
              <span class="text-sm font-semibold truncate">{@play.title}</span>
            </div>
            <p class="text-xs text-base-content/50 truncate">
              {@play.author_name} — {@play.code}
            </p>
          </div>
          <div
            class="overflow-y-auto px-4 py-4 compare-panel"
            data-panel="right"
            style="max-height: calc(100vh - 220px);"
          >
            <.play_body
              divisions={@play_divisions}
              characters={@play_characters}
              show_line_numbers={@show_line_numbers}
              show_stage_directions={@show_stage_directions}
              show_asides={@show_asides}
              show_split_verses={@show_split_verses}
              show_verse_type={@show_verse_type}
              sync_keys={true}
            />
          </div>
        </div>
      </div>
    </div>
    """
  end
end
