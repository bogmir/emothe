defmodule EmotheWeb.Components.StatisticsPanel do
  @moduledoc """
  Modern visualization components for play statistics.
  """
  use Phoenix.Component

  attr :statistic, :map, required: true
  attr :play, :map, required: true

  def stats_panel(assigns) do
    data = if assigns.statistic, do: assigns.statistic.data, else: %{}
    assigns = assign(assigns, :data, data)

    ~H"""
    <div :if={@data != %{}} class="space-y-6">
      <%!-- Summary cards --%>
      <div class="grid grid-cols-2 md:grid-cols-4 gap-4">
        <.stat_card label="Acts" value={@data["num_acts"]} icon="📜" />
        <.stat_card label="Scenes" value={get_in(@data, ["scenes", "total"])} icon="🎭" />
        <.stat_card label="Verses" value={@data["total_verses"]} icon="✍️" />
        <.stat_card label="Stage Directions" value={@data["total_stage_directions"]} icon="🎬" />
      </div>

      <%!-- Scenes per act --%>
      <.bar_chart
        title="Scenes per Act"
        items={get_in(@data, ["scenes", "per_act"]) || []}
        label_key="act"
        value_key="count"
        label_prefix="Act "
        color="bg-amber-500"
      />

      <%!-- Verse distribution --%>
      <.bar_chart
        title="Verse Distribution"
        items={@data["verse_distribution"] || []}
        label_key="act"
        value_key="count"
        label_prefix="Act "
        color="bg-indigo-500"
      />

      <%!-- Prose fragments --%>
      <.bar_chart
        :if={(@data["total_prose_fragments"] || 0) > 0}
        title="Prose Fragments"
        items={@data["prose_fragments"] || []}
        label_key="act"
        value_key="count"
        label_prefix="Act "
        color="bg-emerald-500"
      />

      <%!-- Additional stats --%>
      <div class="grid grid-cols-2 md:grid-cols-3 gap-4">
        <.stat_card label="Split Verses" value={@data["split_verses"]} icon="↔️" />
        <.stat_card label="Asides" value={@data["total_asides"]} icon="🤫" />
        <.stat_card label="Aside Verses" value={@data["aside_verses"]} icon="💬" />
      </div>

      <%!-- Character appearances --%>
      <div :if={@data["character_appearances"] && @data["character_appearances"] != []}>
        <h3 class="text-lg font-semibold text-gray-900 mb-3">Character Speeches</h3>
        <div class="space-y-2">
          <div :for={char <- @data["character_appearances"]} class="flex items-center gap-3">
            <span class="w-28 text-sm font-medium text-gray-700 truncate" title={char["name"]}>
              {char["name"]}
            </span>
            <div class="flex-1 bg-gray-100 rounded-full h-5 overflow-hidden">
              <div
                class="bg-amber-500 h-full rounded-full transition-all"
                style={"width: #{bar_percent(char["speeches"], max_speeches(@data["character_appearances"]))}%"}
              >
              </div>
            </div>
            <span class="text-sm text-gray-500 w-10 text-right">{char["speeches"]}</span>
          </div>
        </div>
      </div>
    </div>
    """
  end

  attr :label, :string, required: true
  attr :value, :any, required: true
  attr :icon, :string, default: ""

  defp stat_card(assigns) do
    ~H"""
    <div class="bg-white border border-gray-200 rounded-xl p-4 text-center">
      <div class="text-2xl mb-1">{@icon}</div>
      <div class="text-2xl font-bold text-gray-900">{@value || 0}</div>
      <div class="text-sm text-gray-500">{@label}</div>
    </div>
    """
  end

  attr :title, :string, required: true
  attr :items, :list, required: true
  attr :label_key, :string, required: true
  attr :value_key, :string, required: true
  attr :label_prefix, :string, default: ""
  attr :color, :string, default: "bg-blue-500"

  defp bar_chart(assigns) do
    max = assigns.items |> Enum.map(&(&1[assigns.value_key] || 0)) |> Enum.max(fn -> 1 end)
    assigns = assign(assigns, :max, max)

    ~H"""
    <div class="bg-white border border-gray-200 rounded-xl p-5">
      <h3 class="text-lg font-semibold text-gray-900 mb-4">{@title}</h3>
      <div class="space-y-3">
        <div :for={item <- @items} class="flex items-center gap-3">
          <span class="w-16 text-sm text-gray-600 text-right">
            {@label_prefix}{item[@label_key]}
          </span>
          <div class="flex-1 bg-gray-100 rounded-full h-6 overflow-hidden">
            <div
              class={"#{@color} h-full rounded-full transition-all flex items-center justify-end pr-2"}
              style={"width: #{bar_percent(item[@value_key], @max)}%"}
            >
              <span class="text-xs text-white font-medium">
                {item[@value_key]}
              </span>
            </div>
          </div>
        </div>
      </div>
    </div>
    """
  end

  defp bar_percent(nil, _max), do: 0
  defp bar_percent(_value, 0), do: 0

  defp bar_percent(value, max) do
    min(round(value / max * 100), 100) |> max(5)
  end

  defp max_speeches([]), do: 1

  defp max_speeches(characters) do
    characters |> Enum.map(&(&1["speeches"] || 0)) |> Enum.max(fn -> 1 end)
  end
end
