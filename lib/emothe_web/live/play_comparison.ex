defmodule EmotheWeb.PlayComparison do
  @moduledoc """
  Shared logic for the side-by-side play comparison views.

  Used by both the admin (`EmotheWeb.Admin.PlayCompareLive`) and the public
  (`EmotheWeb.PlayCompareLive`) comparison LiveViews. Holds the family-building,
  panel-loading, layout, and display-toggle logic so neither LiveView duplicates it.

  A "panel" is a map `%{play: play, divisions: divisions, characters: characters}`.
  A "family" is the original (root) play plus all of its derived plays
  (translations/adaptations), excluding the play currently being viewed.
  """

  import Phoenix.Component, only: [assign: 2]

  alias Emothe.Catalogue
  alias Emothe.PlayContent

  @max_panels 4

  @doc "Maximum number of comparison panels allowed."
  def max_panels, do: @max_panels

  @doc """
  Builds a comparison panel for a fully-loaded play, loading its content tree
  and characters.
  """
  def build_panel(play) do
    %{
      play: play,
      divisions: PlayContent.load_play_content(play.id),
      characters: PlayContent.list_characters(play.id)
    }
  end

  @doc """
  Builds the initial panel list for a play. When the play is a translation with a
  parent, the parent play is prepended as the first (left) panel.
  """
  def build_initial_panels(play, family) do
    panels = [build_panel(play)]

    if play.relationship_type == "traduccion" && play.parent_play_id do
      case Enum.find(family, &(&1.id == play.parent_play_id)) do
        nil -> panels
        parent -> [build_panel(Catalogue.get_play_with_all!(parent.id)) | panels]
      end
    else
      panels
    end
  end

  @doc """
  Builds a flat list of all plays in the same translation family as `play`
  (root original + its derived plays), excluding `play` itself.
  """
  def build_family(play) do
    root =
      if play.parent_play_id do
        Catalogue.get_play_with_all!(play.parent_play_id)
      else
        play
      end

    [root | root.derived_plays || []]
    |> Enum.reject(&(&1.id == play.id))
  end

  @doc "Plays in `family` that are not already shown in `panels`."
  def available_plays(family, panels) do
    selected_ids = MapSet.new(panels, & &1.play.id)
    Enum.reject(family, &MapSet.member?(selected_ids, &1.id))
  end

  @doc """
  Appends a panel for `play_id`. Returns `{:ok, panels}` or `{:error, :max_reached}`
  when the panel limit is hit.
  """
  def add_panel(panels, play_id) do
    if length(panels) >= @max_panels do
      {:error, :max_reached}
    else
      panel = build_panel(Catalogue.get_play_with_all!(play_id))
      {:ok, panels ++ [panel]}
    end
  end

  @doc "Removes the panel at `index`, keeping at least one panel."
  def remove_panel(panels, index) when is_integer(index) do
    if length(panels) <= 1, do: panels, else: List.delete_at(panels, index)
  end

  @doc "Tailwind grid column class for a given panel count."
  def grid_class(panel_count) do
    case panel_count do
      1 -> "grid-cols-1"
      2 -> "grid-cols-2"
      3 -> "grid-cols-3"
      _ -> "grid-cols-2"
    end
  end

  @doc "Inline max-height style for panels based on the panel count."
  def panel_height(panel_count) do
    if panel_count >= 4,
      do: "max-height: calc(50vh - 120px);",
      else: "max-height: calc(100vh - 220px);"
  end

  @doc "Assigns the shared default display-toggle state onto the socket."
  def assign_display_defaults(socket) do
    assign(socket,
      show_line_numbers: true,
      show_stage_directions: true,
      show_asides: true,
      show_split_verses: false,
      show_verse_type: false
    )
  end

  @doc "Maps a toggle event name to its assign key, or `nil` if unknown."
  def toggle_key("toggle_line_numbers"), do: :show_line_numbers
  def toggle_key("toggle_stage_directions"), do: :show_stage_directions
  def toggle_key("toggle_asides"), do: :show_asides
  def toggle_key("toggle_split_verses"), do: :show_split_verses
  def toggle_key("toggle_verse_type"), do: :show_verse_type
  def toggle_key(_), do: nil
end
