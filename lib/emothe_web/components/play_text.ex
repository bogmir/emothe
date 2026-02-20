defmodule EmotheWeb.Components.PlayText do
  @moduledoc """
  Components for rendering play text: speeches, verse lines, stage directions.
  Styled to match the production EMOTHE/Artelope color scheme and fonts.
  """
  use Phoenix.Component

  attr :divisions, :list, required: true
  attr :show_line_numbers, :boolean, default: true
  attr :show_stage_directions, :boolean, default: true

  def play_body(assigns) do
    ~H"""
    <div class="play-text">
      <div :for={division <- @divisions} class="mb-8 scroll-mt-16" id={"div-#{division.id}"}>
        <.division_heading division={division} />

        <div :if={Map.has_key?(division, :loaded_elements)}>
          <.element_list
            elements={Map.get(division, :loaded_elements, [])}
            show_line_numbers={@show_line_numbers}
            show_stage_directions={@show_stage_directions}
          />
        </div>

        <div
          :for={child <- Map.get(division, :children, [])}
          class="mb-6 scroll-mt-16"
          id={"div-#{child.id}"}
        >
          <.division_heading division={child} />
          <div :if={Map.has_key?(child, :loaded_elements)}>
            <.element_list
              elements={Map.get(child, :loaded_elements, [])}
              show_line_numbers={@show_line_numbers}
              show_stage_directions={@show_stage_directions}
            />
          </div>
        </div>
      </div>
    </div>
    """
  end

  @act_types ~w(acto act acte jornada)

  attr :division, :map, required: true

  defp division_heading(assigns) do
    assigns = assign(assigns, :is_act, assigns.division.type in @act_types)

    ~H"""
    <h2
      :if={@division.title && @is_act}
      class="font-bold text-center my-6 text-lg tracking-wide text-base-content"
    >
      {@division.title}
    </h2>
    <h3
      :if={@division.title && !@is_act}
      class="font-semibold text-center my-4 text-sm text-base-content/70"
    >
      {@division.title}
    </h3>
    """
  end

  attr :elements, :list, required: true
  attr :show_line_numbers, :boolean, default: true
  attr :show_stage_directions, :boolean, default: true

  defp element_list(assigns) do
    ~H"""
    <div>
      <div :for={element <- @elements}>
        <.render_element
          element={element}
          show_line_numbers={@show_line_numbers}
          show_stage_directions={@show_stage_directions}
        />
      </div>
    </div>
    """
  end

  attr :element, :map, required: true
  attr :show_line_numbers, :boolean, default: true
  attr :show_stage_directions, :boolean, default: true

  defp render_element(%{element: %{type: "speech"}} = assigns) do
    ~H"""
    <div class={["speech mt-3 mb-5", @element.is_aside && "pl-6 aside-border"]}>
      <div :if={@element.speaker_label} class="speaker mb-1">
        {@element.speaker_label}
      </div>
      <div :for={child <- Map.get(@element, :children, [])}>
        <.render_element
          element={child}
          show_line_numbers={@show_line_numbers}
          show_stage_directions={@show_stage_directions}
        />
      </div>
    </div>
    """
  end

  defp render_element(%{element: %{type: "line_group"}} = assigns) do
    ~H"""
    <div class="line-group">
      <div :for={child <- Map.get(@element, :children, [])}>
        <.render_element
          element={child}
          show_line_numbers={@show_line_numbers}
          show_stage_directions={@show_stage_directions}
        />
      </div>
    </div>
    """
  end

  defp render_element(%{element: %{type: "verse_line"}} = assigns) do
    ~H"""
    <div class="verse-line flex items-baseline gap-2 ml-4">
      <span class={[
        "flex-1",
        @element.rend == "indent" && "pl-8",
        @element.part == "F" && "part-f",
        @element.part == "M" && "part-m"
      ]}>
        {@element.content}
      </span>
      <span
        :if={@element.line_number}
        class={["line-number w-8 text-left shrink-0 select-none", !@show_line_numbers && "invisible"]}
      >
        {@element.line_number}
      </span>
      <span
        :if={!@element.line_number}
        class="w-8 shrink-0"
      />
    </div>
    """
  end

  defp render_element(%{element: %{type: "stage_direction"}} = assigns) do
    ~H"""
    <div :if={@show_stage_directions} class="stage-direction text-center my-4 px-8">
      ({@element.content})
    </div>
    """
  end

  defp render_element(%{element: %{type: "prose"}} = assigns) do
    ~H"""
    <div class="ml-4 mb-2 text-justify">
      {@element.content}
    </div>
    """
  end

  defp render_element(assigns) do
    ~H"""
    <div :if={@element.content}>
      {@element.content}
    </div>
    """
  end
end
