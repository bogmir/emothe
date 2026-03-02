defmodule EmotheWeb.Admin.PlayCompareLive do
  use EmotheWeb, :live_view

  import EmotheWeb.Components.PlayText

  alias Emothe.Catalogue
  alias Emothe.PlayContent

  @max_panels 4

  @impl true
  def mount(%{"id" => id}, _session, socket) do
    play = Catalogue.get_play_with_all!(id)
    divisions = PlayContent.load_play_content(play.id)
    characters = PlayContent.list_characters(play.id)

    panels = [%{play: play, divisions: divisions, characters: characters}]

    # Build the family of related plays (parent + all translations)
    family = build_family(play)

    # Auto-add parent play if this is a translation
    panels =
      if play.relationship_type == "traduccion" && play.parent_play_id do
        parent = Enum.find(family, &(&1.id == play.parent_play_id))

        if parent do
          parent_full = Catalogue.get_play_with_all!(parent.id)
          parent_divisions = PlayContent.load_play_content(parent.id)
          parent_characters = PlayContent.list_characters(parent.id)

          [%{play: parent_full, divisions: parent_divisions, characters: parent_characters} | panels]
        else
          panels
        end
      else
        panels
      end

    {:ok,
     socket
     |> assign(:page_title, gettext("Compare: %{title}", title: play.title))
     |> assign(:play, play)
     |> assign(:panels, panels)
     |> assign(:family, family)
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

  # Build a flat list of all plays in the same translation family
  defp build_family(play) do
    # Find the root (original) play
    root =
      if play.parent_play_id do
        Catalogue.get_play_with_all!(play.parent_play_id)
      else
        play
      end

    # Root + all its derived plays (translations)
    [root | root.derived_plays || []]
    |> Enum.reject(&(&1.id == play.id))
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

  def handle_event("add_play", %{"id" => ""}, socket), do: {:noreply, socket}

  def handle_event("add_play", %{"id" => play_id}, socket) do
    if length(socket.assigns.panels) >= @max_panels do
      {:noreply,
       put_flash(socket, :error, gettext("Maximum %{max} plays allowed.", max: @max_panels))}
    else
      play = Catalogue.get_play_with_all!(play_id)
      divisions = PlayContent.load_play_content(play.id)
      characters = PlayContent.list_characters(play.id)

      panel = %{play: play, divisions: divisions, characters: characters}

      {:noreply, assign(socket, :panels, socket.assigns.panels ++ [panel])}
    end
  end

  def handle_event("remove_panel", %{"index" => index_str}, socket) do
    index = String.to_integer(index_str)

    if length(socket.assigns.panels) <= 1 do
      {:noreply, socket}
    else
      {:noreply, assign(socket, :panels, List.delete_at(socket.assigns.panels, index))}
    end
  end

  defp available_plays(family, panels) do
    selected_ids = MapSet.new(panels, & &1.play.id)
    Enum.reject(family, &MapSet.member?(selected_ids, &1.id))
  end

  defp grid_class(panel_count) do
    case panel_count do
      1 -> "grid-cols-1"
      2 -> "grid-cols-2"
      3 -> "grid-cols-3"
      _ -> "grid-cols-2"
    end
  end

  defp panel_height(panel_count) do
    if panel_count >= 4,
      do: "max-height: calc(50vh - 120px);",
      else: "max-height: calc(100vh - 220px);"
  end

  @impl true
  def render(assigns) do
    assigns = assign(assigns, :available, available_plays(assigns.family, assigns.panels))

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

        <%!-- Add play selector --%>
        <div :if={@available != [] && length(@panels) < 4} class="ml-auto flex items-center gap-2">
          <form phx-change="add_play" class="inline">
            <select name="id" class="select select-xs select-bordered w-64">
              <option value="">{gettext("Add play to compare...")}</option>
              <option :for={p <- @available} value={p.id}>
                {p.title} ({p.code})
              </option>
            </select>
          </form>
        </div>
      </div>

      <%!-- N-panel comparison --%>
      <div
        id="sync-scroll"
        phx-hook="SyncScroll"
        class={"grid #{grid_class(length(@panels))} gap-4"}
      >
        <div
          :for={{panel, idx} <- Enum.with_index(@panels)}
          class="flex flex-col rounded-box border border-base-300 bg-base-100 shadow-sm"
        >
          <div class="sticky top-0 z-10 border-b border-base-300 bg-base-100/95 backdrop-blur-sm px-4 py-2">
            <div class="flex items-center gap-2">
              <span class={[
                "badge badge-sm",
                if(idx == 0, do: "badge-ghost", else: "badge-primary")
              ]}>
                {idx + 1}
              </span>
              <span class="text-sm font-semibold truncate flex-1">{panel.play.title}</span>
              <button
                :if={length(@panels) > 1}
                phx-click="remove_panel"
                phx-value-index={idx}
                class="btn btn-ghost btn-xs btn-circle text-base-content/40 hover:text-error"
                title={gettext("Remove")}
              >
                <.icon name="hero-x-mark-micro" class="size-3.5" />
              </button>
            </div>
            <p class="text-xs text-base-content/50 truncate">
              {panel.play.author_name} — {panel.play.code}
            </p>
          </div>
          <div
            class="overflow-y-auto px-4 py-4 compare-panel"
            data-panel={"panel-#{idx}"}
            style={panel_height(length(@panels))}
          >
            <.play_body
              divisions={panel.divisions}
              characters={panel.characters}
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
