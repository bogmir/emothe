defmodule EmotheWeb.Admin.PlayContentEditorLive do
  use EmotheWeb, :live_view

  import EmotheWeb.Components.PlayText

  alias Emothe.Catalogue
  alias Emothe.PlayContent
  alias Emothe.PlayContent.{Character, Division, Element}
  alias Emothe.Statistics

  @impl true
  def mount(%{"id" => id}, _session, socket) do
    play = Catalogue.get_play!(id)
    characters = PlayContent.list_characters(play.id)
    divisions = PlayContent.list_top_divisions(play.id)

    {:ok,
     socket
     |> assign(
       page_title: "Edit Content: #{play.title}",
       play: play,
       characters: characters,
       divisions: divisions,
       selected_division_id: nil,
       elements: [],
       modal: nil,
       form: nil,
       editing: nil,
       modal_parent_id: nil,
       modal_element_type: nil,
       show_preview: false,
       preview_divisions: [],
       breadcrumbs: [
         %{label: "Admin", to: ~p"/admin/plays"},
         %{label: "Plays", to: ~p"/admin/plays"},
         %{label: play.title, to: ~p"/admin/plays/#{play.id}"},
         %{label: "Edit Content"}
       ],
       play_context: %{play: play, active_tab: :content}
     )}
  end

  # --- All handle_event/3 clauses grouped together ---

  @impl true
  def handle_event("close_modal", _, socket) do
    {:noreply, assign(socket, modal: nil, form: nil, editing: nil)}
  end

  def handle_event("toggle_preview", _, socket) do
    show = !socket.assigns.show_preview

    socket =
      if show do
        preview = PlayContent.load_play_content(socket.assigns.play.id)
        assign(socket, show_preview: true, preview_divisions: preview)
      else
        assign(socket, show_preview: false, preview_divisions: [])
      end

    {:noreply, socket}
  end

  def handle_event("validate_form", params, socket) do
    form_params = extract_form_params(params, socket.assigns.modal)

    changeset =
      case socket.assigns.modal do
        :character ->
          PlayContent.change_character(socket.assigns.editing || %Character{}, form_params)

        :division ->
          PlayContent.change_division(socket.assigns.editing || %Division{}, form_params)

        :element ->
          PlayContent.change_element(socket.assigns.editing || %Element{}, form_params)
      end

    {:noreply, assign(socket, form: to_form(Map.put(changeset, :action, :validate)))}
  end

  def handle_event("save_form", params, socket) do
    case socket.assigns.modal do
      :character -> save_character(socket, params)
      :division -> save_division(socket, params)
      :element -> save_element(socket, params)
    end
  end

  def handle_event("new_character", _, socket) do
    play = socket.assigns.play
    pos = PlayContent.next_character_position(play.id)

    changeset =
      PlayContent.change_character(%Character{}, %{play_id: play.id, position: pos})

    {:noreply,
     assign(socket,
       modal: :character,
       editing: nil,
       form: to_form(changeset)
     )}
  end

  def handle_event("edit_character", %{"id" => id}, socket) do
    character = PlayContent.get_character!(id)
    changeset = PlayContent.change_character(character)

    {:noreply,
     assign(socket,
       modal: :character,
       editing: character,
       form: to_form(changeset)
     )}
  end

  def handle_event("delete_character", %{"id" => id}, socket) do
    character = PlayContent.get_character!(id)
    {:ok, _} = PlayContent.delete_character(character)
    Statistics.delete_statistics(socket.assigns.play.id)

    {:noreply,
     socket
     |> put_flash(:info, "Character deleted.")
     |> reload_characters()}
  end

  def handle_event("new_division", params, socket) do
    play = socket.assigns.play
    parent_id = params["parent-id"]
    pos = PlayContent.next_division_position(play.id, parent_id)

    default_type = if parent_id, do: "escena", else: "acto"

    changeset =
      PlayContent.change_division(%Division{}, %{
        play_id: play.id,
        parent_id: parent_id,
        position: pos,
        type: default_type
      })

    {:noreply,
     assign(socket,
       modal: :division,
       editing: nil,
       modal_parent_id: parent_id,
       form: to_form(changeset)
     )}
  end

  def handle_event("edit_division", %{"id" => id}, socket) do
    division = PlayContent.get_division!(id)
    changeset = PlayContent.change_division(division)

    {:noreply,
     assign(socket,
       modal: :division,
       editing: division,
       form: to_form(changeset)
     )}
  end

  def handle_event("delete_division", %{"id" => id}, socket) do
    division = PlayContent.get_division!(id)
    {:ok, _} = PlayContent.delete_division(division)
    Statistics.delete_statistics(socket.assigns.play.id)

    selected =
      if socket.assigns.selected_division_id == id,
        do: nil,
        else: socket.assigns.selected_division_id

    {:noreply,
     socket
     |> put_flash(:info, "Division deleted.")
     |> assign(selected_division_id: selected)
     |> reload_divisions()
     |> reload_elements()}
  end

  def handle_event("select_division", %{"id" => id}, socket) do
    {:noreply,
     socket
     |> assign(selected_division_id: id)
     |> reload_elements()}
  end

  def handle_event("new_element", params, socket) do
    play = socket.assigns.play
    div_id = socket.assigns.selected_division_id
    parent_id = params["parent-id"]
    element_type = params["type"]
    pos = PlayContent.next_element_position(div_id, parent_id)

    attrs = %{
      play_id: play.id,
      division_id: div_id,
      parent_id: parent_id,
      type: element_type,
      position: pos
    }

    attrs = maybe_add_line_number(attrs, element_type, play.id)
    changeset = PlayContent.change_element(%Element{}, attrs)

    {:noreply,
     assign(socket,
       modal: :element,
       editing: nil,
       modal_element_type: element_type,
       form: to_form(changeset)
     )}
  end

  def handle_event("new_element_before", params, socket) do
    play = socket.assigns.play
    div_id = socket.assigns.selected_division_id

    parent_id =
      case params["parent-id"] do
        "" -> nil
        id -> id
      end

    element_type = params["type"]
    before_pos = String.to_integer(params["position"])

    # Shift existing elements to make room
    PlayContent.shift_element_positions(div_id, parent_id, before_pos)

    attrs = %{
      play_id: play.id,
      division_id: div_id,
      parent_id: parent_id,
      type: element_type,
      position: before_pos
    }

    attrs = maybe_add_line_number(attrs, element_type, play.id)
    changeset = PlayContent.change_element(%Element{}, attrs)

    {:noreply,
     socket
     |> reload_elements()
     |> assign(
       modal: :element,
       editing: nil,
       modal_element_type: element_type,
       form: to_form(changeset)
     )}
  end

  def handle_event("edit_element", %{"id" => id}, socket) do
    element = PlayContent.get_element!(id)
    changeset = PlayContent.change_element(element)

    {:noreply,
     assign(socket,
       modal: :element,
       editing: element,
       modal_element_type: element.type,
       form: to_form(changeset)
     )}
  end

  def handle_event("delete_element", %{"id" => id}, socket) do
    element = PlayContent.get_element!(id)
    play_id = socket.assigns.play.id

    # Check if we need to shift line numbers down after deletion
    should_shift_down =
      element.type == "verse_line" &&
        element.line_number != nil &&
        !PlayContent.split_verse?(play_id, element.id, element.line_number)

    {:ok, _} = PlayContent.delete_element(element)

    if should_shift_down do
      PlayContent.shift_line_numbers_down(play_id, element.line_number)
    end

    Statistics.delete_statistics(play_id)

    {:noreply,
     socket
     |> put_flash(:info, "Element deleted.")
     |> reload_elements()}
  end

  # --- Save helpers ---

  defp save_character(socket, params) do
    char_params = params["character"] || %{}
    play = socket.assigns.play

    result =
      case socket.assigns.editing do
        nil ->
          char_params = Map.put(char_params, "play_id", play.id)
          PlayContent.create_character(char_params)

        character ->
          PlayContent.update_character(character, char_params)
      end

    case result do
      {:ok, _} ->
        Statistics.delete_statistics(play.id)

        {:noreply,
         socket
         |> put_flash(:info, "Character saved.")
         |> assign(modal: nil, form: nil, editing: nil)
         |> reload_characters()}

      {:error, changeset} ->
        {:noreply, assign(socket, form: to_form(changeset))}
    end
  end

  defp save_division(socket, params) do
    div_params = params["division"] || %{}
    play = socket.assigns.play

    result =
      case socket.assigns.editing do
        nil ->
          div_params =
            div_params
            |> Map.put("play_id", play.id)
            |> Map.put("parent_id", socket.assigns.modal_parent_id)

          PlayContent.create_division(div_params)

        division ->
          PlayContent.update_division(division, div_params)
      end

    case result do
      {:ok, _} ->
        Statistics.delete_statistics(play.id)

        {:noreply,
         socket
         |> put_flash(:info, "Division saved.")
         |> assign(modal: nil, form: nil, editing: nil, modal_parent_id: nil)
         |> reload_divisions()}

      {:error, changeset} ->
        {:noreply, assign(socket, form: to_form(changeset))}
    end
  end

  defp save_element(socket, params) do
    el_params = params["element"] || %{}
    play = socket.assigns.play

    result =
      case socket.assigns.editing do
        nil ->
          el_params =
            el_params
            |> Map.put("play_id", play.id)
            |> Map.put("division_id", socket.assigns.selected_division_id)

          # Shift line numbers before creating a new verse_line
          if el_params["type"] == "verse_line" do
            case el_params["line_number"] do
              nil ->
                :ok

              "" ->
                :ok

              ln ->
                line_num = if is_binary(ln), do: String.to_integer(ln), else: ln
                PlayContent.shift_line_numbers(play.id, line_num)
            end
          end

          PlayContent.create_element(el_params)

        element ->
          PlayContent.update_element(element, el_params)
      end

    case result do
      {:ok, _} ->
        Statistics.delete_statistics(play.id)

        {:noreply,
         socket
         |> put_flash(:info, "Element saved.")
         |> assign(modal: nil, form: nil, editing: nil, modal_element_type: nil)
         |> reload_elements()}

      {:error, changeset} ->
        {:noreply, assign(socket, form: to_form(changeset))}
    end
  end

  # --- Reload helpers ---

  defp reload_characters(socket) do
    assign(socket, characters: PlayContent.list_characters(socket.assigns.play.id))
  end

  defp reload_divisions(socket) do
    assign(socket, divisions: PlayContent.list_top_divisions(socket.assigns.play.id))
  end

  defp reload_elements(socket) do
    socket =
      case socket.assigns.selected_division_id do
        nil -> assign(socket, elements: [])
        div_id -> assign(socket, elements: PlayContent.list_elements_for_division(div_id))
      end

    reload_preview(socket)
  end

  defp reload_preview(socket) do
    if socket.assigns.show_preview do
      assign(socket, preview_divisions: PlayContent.load_play_content(socket.assigns.play.id))
    else
      socket
    end
  end

  defp extract_form_params(params, :character), do: params["character"] || %{}
  defp extract_form_params(params, :division), do: params["division"] || %{}
  defp extract_form_params(params, :element), do: params["element"] || %{}
  defp extract_form_params(_params, _), do: %{}

  defp editing_label(nil), do: "Add"
  defp editing_label(_), do: "Edit"

  defp maybe_add_line_number(attrs, "verse_line", play_id) do
    parent_id = attrs[:parent_id] || attrs["parent_id"]
    position = attrs[:position] || attrs["position"]

    line_number = PlayContent.auto_line_number(play_id, parent_id, position)
    Map.put(attrs, :line_number, line_number)
  end

  defp maybe_add_line_number(attrs, _type, _play_id), do: attrs

  defp division_types do
    [
      {"Acto", "acto"},
      {"Escena", "escena"},
      {"Prologo", "prologo"},
      {"Argumento", "argumento"},
      {"Jornada", "jornada"},
      {"Dedicatoria", "dedicatoria"},
      {"Elenco", "elenco"},
      {"Front", "front"}
    ]
  end

  defp verse_types do
    [
      {"", ""},
      {"Redondilla", "redondilla"},
      {"Romance", "romance"},
      {"Romance tirada", "romance_tirada"},
      {"Octava real", "octava_real"},
      {"Soneto", "soneto"},
      {"Decima", "decima"},
      {"Terceto", "terceto"},
      {"Silva", "silva"},
      {"Quintilla", "quintilla"},
      {"Lira", "lira"},
      {"Cancion", "cancion"},
      {"Otro", "otro"}
    ]
  end

  defp part_options do
    [
      {"(none)", ""},
      {"I - Inicio", "I"},
      {"M - Medio", "M"},
      {"F - Final", "F"}
    ]
  end

  # --- Render ---

  @impl true
  def render(assigns) do
    ~H"""
    <div class="mx-auto max-w-7xl px-4 py-8">
      <div class="mb-6 flex flex-wrap items-start justify-between gap-4">
        <div>
          <h1 class="text-3xl font-semibold tracking-tight text-base-content">
            Edit Content: {@play.title}
          </h1>
          <p class="mt-1 text-sm text-base-content/70">{@play.author_name} — {@play.code}</p>
        </div>
        <div class="flex gap-2">
          <button
            phx-click="toggle_preview"
            class={"btn btn-sm #{if @show_preview, do: "btn-secondary", else: "btn-ghost"}"}
          >
            {if @show_preview, do: "Hide Preview", else: "Show Preview"}
          </button>
        </div>
      </div>

      <%!-- Characters Section --%>
      <section class="mb-8">
        <div class="mb-3 flex items-center justify-between">
          <h2 class="text-lg font-semibold text-base-content">Characters ({length(@characters)})</h2>
          <button phx-click="new_character" class="btn btn-xs btn-primary">Add Character</button>
        </div>
        <div
          :if={@characters == []}
          class="rounded-box border border-base-300 bg-base-100 p-4 text-sm text-base-content/70"
        >
          No characters yet. Add one to get started.
        </div>
        <div
          :if={@characters != []}
          class="divide-y rounded-box border border-base-300 bg-base-100 shadow-sm"
        >
          <div :for={char <- @characters} class="flex items-center justify-between gap-3 p-3">
            <div class="flex items-center gap-3">
              <span class="font-medium">{char.name}</span>
              <span class="text-xs text-base-content/50">{char.xml_id}</span>
              <span :if={char.description} class="text-sm text-base-content/70">
                {char.description}
              </span>
              <span :if={char.is_hidden} class="badge badge-ghost badge-sm">hidden</span>
            </div>
            <div class="flex gap-1">
              <button
                phx-click="edit_character"
                phx-value-id={char.id}
                class="btn btn-ghost btn-xs tooltip"
                data-tip="Edit"
              >
                <.icon name="hero-pencil-mini" class="size-4" />
              </button>
              <button
                phx-click="delete_character"
                phx-value-id={char.id}
                data-confirm="Delete this character? Speeches referencing it will lose their speaker."
                class="btn btn-ghost btn-xs text-error tooltip"
                data-tip="Delete"
              >
                <.icon name="hero-trash-mini" class="size-4" />
              </button>
            </div>
          </div>
        </div>
      </section>

      <%!-- Divisions Section --%>
      <section class="mb-8">
        <div class="mb-3 flex items-center justify-between">
          <h2 class="text-lg font-semibold text-base-content">Structure</h2>
          <button phx-click="new_division" class="btn btn-xs btn-primary">Add Act</button>
        </div>
        <div
          :if={@divisions == []}
          class="rounded-box border border-base-300 bg-base-100 p-4 text-sm text-base-content/70"
        >
          No acts or scenes yet. Add an act to get started.
        </div>
        <div :if={@divisions != []} class="space-y-2">
          <div
            :for={div <- @divisions}
            class="rounded-box border border-base-300 bg-base-100 shadow-sm"
          >
            <div class="flex items-center justify-between p-3">
              <div>
                <span class="font-medium">{div.title || String.capitalize(div.type)}</span>
                <span class="ml-2 text-sm text-base-content/70">{div.type} {div.number}</span>
              </div>
              <div class="flex gap-1">
                <button
                  phx-click="edit_division"
                  phx-value-id={div.id}
                  class="btn btn-ghost btn-xs tooltip"
                  data-tip="Edit"
                >
                  <.icon name="hero-pencil-mini" class="size-4" />
                </button>
                <button
                  phx-click="delete_division"
                  phx-value-id={div.id}
                  data-confirm="Delete this division and all its content?"
                  class="btn btn-ghost btn-xs text-error tooltip"
                  data-tip="Delete"
                >
                  <.icon name="hero-trash-mini" class="size-4" />
                </button>
              </div>
            </div>
            <%!-- Child divisions (scenes) --%>
            <div :if={div.children != []} class="border-t border-base-300 bg-base-200/50 px-3 py-2">
              <div :for={child <- div.children} class="flex items-center justify-between py-1 pl-4">
                <button
                  phx-click="select_division"
                  phx-value-id={child.id}
                  class={"text-sm hover:underline #{if @selected_division_id == child.id, do: "font-bold text-primary", else: "text-base-content/80"}"}
                >
                  {child.title || String.capitalize(child.type)} {child.number}
                </button>
                <div class="flex gap-1">
                  <button
                    phx-click="edit_division"
                    phx-value-id={child.id}
                    class="btn btn-ghost btn-xs tooltip"
                    data-tip="Edit"
                  >
                    <.icon name="hero-pencil-mini" class="size-4" />
                  </button>
                  <button
                    phx-click="delete_division"
                    phx-value-id={child.id}
                    data-confirm="Delete this scene and all its content?"
                    class="btn btn-ghost btn-xs text-error tooltip"
                    data-tip="Delete"
                  >
                    <.icon name="hero-trash-mini" class="size-4" />
                  </button>
                </div>
              </div>
            </div>
            <div class="border-t border-base-300 px-3 py-2">
              <button
                phx-click="new_division"
                phx-value-parent-id={div.id}
                class="btn btn-xs btn-ghost btn-outline"
              >
                Add Scene
              </button>
              <%!-- Allow selecting the act itself for content --%>
              <button
                phx-click="select_division"
                phx-value-id={div.id}
                class={"btn btn-xs btn-ghost #{if @selected_division_id == div.id, do: "btn-active"}"}
              >
                Edit Act Content
              </button>
            </div>
          </div>
        </div>
      </section>

      <%!-- Elements Section (for selected division) --%>
      <section :if={@selected_division_id} class="mb-8">
        <div class="mb-3 flex items-center justify-between">
          <h2 class="text-lg font-semibold text-base-content">
            Content for: {selected_division_label(@divisions, @selected_division_id)}
          </h2>
          <div class="flex gap-1">
            <button phx-click="new_element" phx-value-type="speech" class="btn btn-xs btn-primary">
              Add Speech
            </button>
            <button
              phx-click="new_element"
              phx-value-type="stage_direction"
              class="btn btn-xs btn-outline"
            >
              Add Stage Direction
            </button>
            <button phx-click="new_element" phx-value-type="prose" class="btn btn-xs btn-outline">
              Add Prose
            </button>
          </div>
        </div>
        <div
          :if={@elements == []}
          class="rounded-box border border-base-300 bg-base-100 p-4 text-sm text-base-content/70"
        >
          No content yet. Add a speech, stage direction, or prose to get started.
        </div>
        <div :if={@elements != []} class="space-y-2">
          <.element_card
            :for={element <- @elements}
            element={element}
            characters={@characters}
            depth={0}
          />
        </div>
      </section>

      <%!-- Play Text Preview --%>
      <section :if={@show_preview} class="mb-8">
        <div class="mb-3">
          <h2 class="text-lg font-semibold text-base-content">Play Text Preview</h2>
        </div>
        <div class="rounded-box border border-base-300 bg-base-100 p-6 shadow-sm max-h-[600px] overflow-y-auto">
          <div :if={@preview_divisions == []} class="text-sm text-base-content/70">
            No content to preview yet.
          </div>
          <.play_body
            :if={@preview_divisions != []}
            divisions={@preview_divisions}
            show_line_numbers={true}
            show_stage_directions={true}
          />
        </div>
      </section>

      <%!-- Modal --%>
      <.modal :if={@modal} id="content-modal" on_cancel={JS.push("close_modal")}>
        <.modal_content
          modal={@modal}
          form={@form}
          editing={@editing}
          characters={@characters}
          modal_element_type={@modal_element_type}
        />
      </.modal>
    </div>
    """
  end

  defp selected_division_label(divisions, id) do
    Enum.find_value(divisions, "Unknown", fn div ->
      if div.id == id do
        div.title || "#{String.capitalize(div.type)} #{div.number}"
      else
        Enum.find_value(div.children || [], nil, fn child ->
          if child.id == id do
            "#{div.title || String.capitalize(div.type)} #{div.number} > #{child.title || String.capitalize(child.type)} #{child.number}"
          end
        end)
      end
    end)
  end

  # --- Element card component (recursive) ---

  attr :element, :map, required: true
  attr :characters, :list, required: true
  attr :depth, :integer, default: 0

  defp element_card(assigns) do
    ~H"""
    <div class={"rounded-box border border-base-300 bg-base-100 shadow-sm #{if @depth > 0, do: "ml-4 mt-1"}"}>
      <div class="flex items-center justify-between p-3">
        <div class="flex-1">
          <span class="badge badge-sm badge-outline mr-2">{element_type_label(@element.type)}</span>
          <span :if={@element.speaker_label} class="font-medium">{@element.speaker_label}</span>
          <span :if={@element.content} class="text-sm text-base-content/80">
            {String.slice(@element.content || "", 0..80)}{if String.length(@element.content || "") >
                                                               80,
                                                             do: "..."}
          </span>
          <span :if={@element.verse_type} class="text-xs text-base-content/50 ml-2">
            ({@element.verse_type})
          </span>
          <span :if={@element.line_number} class="text-xs text-base-content/50 ml-1">
            L{@element.line_number}
          </span>
          <span :if={@element.is_aside} class="badge badge-ghost badge-xs ml-1">aside</span>
        </div>
        <div class="flex gap-1">
          <%!-- Insert Above for top-level elements (speeches, stage dirs, prose) --%>
          <div :if={@depth == 0} class="dropdown dropdown-end">
            <label tabindex="0" class="btn btn-xs btn-ghost btn-outline">Insert Above</label>
            <ul
              tabindex="0"
              class="dropdown-content z-[1] menu p-1 shadow bg-base-100 rounded-box w-40"
            >
              <li>
                <button
                  phx-click="new_element_before"
                  phx-value-type="speech"
                  phx-value-position={@element.position}
                  phx-value-parent-id=""
                >
                  Speech
                </button>
              </li>
              <li>
                <button
                  phx-click="new_element_before"
                  phx-value-type="stage_direction"
                  phx-value-position={@element.position}
                  phx-value-parent-id=""
                >
                  Stage Direction
                </button>
              </li>
              <li>
                <button
                  phx-click="new_element_before"
                  phx-value-type="prose"
                  phx-value-position={@element.position}
                  phx-value-parent-id=""
                >
                  Prose
                </button>
              </li>
            </ul>
          </div>
          <%!-- Insert Above for verse lines inside line groups --%>
          <button
            :if={@element.type == "verse_line" && @element.parent_id}
            phx-click="new_element_before"
            phx-value-type="verse_line"
            phx-value-position={@element.position}
            phx-value-parent-id={@element.parent_id}
            class="btn btn-xs btn-ghost btn-outline"
          >
            Insert Above
          </button>
          <button
            phx-click="edit_element"
            phx-value-id={@element.id}
            class="btn btn-ghost btn-xs tooltip"
            data-tip="Edit"
          >
            <.icon name="hero-pencil-mini" class="size-4" />
          </button>
          <button
            phx-click="delete_element"
            phx-value-id={@element.id}
            data-confirm="Delete this element and its children?"
            class="btn btn-ghost btn-xs text-error tooltip"
            data-tip="Delete"
          >
            <.icon name="hero-trash-mini" class="size-4" />
          </button>
        </div>
      </div>
      <%!-- Children --%>
      <div
        :if={match?([_ | _], Map.get(@element, :children, []))}
        class="border-t border-base-300 bg-base-200/30 px-3 py-2"
      >
        <.element_card
          :for={child <- @element.children}
          element={child}
          characters={@characters}
          depth={@depth + 1}
        />
      </div>
      <%!-- Add child buttons --%>
      <div :if={@element.type == "speech"} class="border-t border-base-300 px-3 py-2">
        <button
          phx-click="new_element"
          phx-value-type="line_group"
          phx-value-parent-id={@element.id}
          class="btn btn-xs btn-ghost btn-outline"
        >
          Add Line Group
        </button>
        <button
          phx-click="new_element"
          phx-value-type="stage_direction"
          phx-value-parent-id={@element.id}
          class="btn btn-xs btn-ghost btn-outline"
        >
          Add Stage Direction
        </button>
        <button
          phx-click="new_element"
          phx-value-type="prose"
          phx-value-parent-id={@element.id}
          class="btn btn-xs btn-ghost btn-outline"
        >
          Add Prose
        </button>
      </div>
      <div :if={@element.type == "line_group"} class="border-t border-base-300 px-3 py-2">
        <button
          phx-click="new_element"
          phx-value-type="verse_line"
          phx-value-parent-id={@element.id}
          class="btn btn-xs btn-ghost btn-outline"
        >
          Add Verse Line
        </button>
      </div>
    </div>
    """
  end

  defp element_type_label("speech"), do: "Speech"
  defp element_type_label("stage_direction"), do: "Stage Dir."
  defp element_type_label("verse_line"), do: "Verse"
  defp element_type_label("prose"), do: "Prose"
  defp element_type_label("line_group"), do: "Line Group"
  defp element_type_label(type), do: type

  # --- Modal content ---

  attr :modal, :atom, required: true
  attr :form, :any, required: true
  attr :editing, :any, default: nil
  attr :characters, :list, default: []
  attr :modal_element_type, :string, default: nil

  defp modal_content(%{modal: :character} = assigns) do
    ~H"""
    <h3 class="text-lg font-bold mb-4">{editing_label(@editing)} Character</h3>
    <.form
      for={@form}
      as={:character}
      phx-change="validate_form"
      phx-submit="save_form"
      class="space-y-4"
    >
      <div>
        <label class="label"><span class="label-text font-medium">XML ID *</span></label>
        <.input field={@form[:xml_id]} type="text" required placeholder="e.g. DONA_ANA" />
      </div>
      <div>
        <label class="label"><span class="label-text font-medium">Name *</span></label>
        <.input field={@form[:name]} type="text" required placeholder="e.g. Dona Ana" />
      </div>
      <div>
        <label class="label"><span class="label-text font-medium">Description</span></label>
        <.input field={@form[:description]} type="text" placeholder="e.g. una dama" />
      </div>
      <div>
        <label class="flex items-center gap-2">
          <.input field={@form[:is_hidden]} type="checkbox" />
          <span class="label-text">Hidden character</span>
        </label>
      </div>
      <.input field={@form[:position]} type="hidden" />
      <div class="flex gap-2 pt-2">
        <button type="submit" class="btn btn-primary">Save</button>
        <button type="button" phx-click="close_modal" class="btn btn-ghost">Cancel</button>
      </div>
    </.form>
    """
  end

  defp modal_content(%{modal: :division} = assigns) do
    ~H"""
    <h3 class="text-lg font-bold mb-4">{editing_label(@editing)} Division</h3>
    <.form
      for={@form}
      as={:division}
      phx-change="validate_form"
      phx-submit="save_form"
      class="space-y-4"
    >
      <div>
        <label class="label"><span class="label-text font-medium">Type *</span></label>
        <.input field={@form[:type]} type="select" options={division_types()} />
      </div>
      <div>
        <label class="label"><span class="label-text font-medium">Number</span></label>
        <.input field={@form[:number]} type="number" />
      </div>
      <div>
        <label class="label"><span class="label-text font-medium">Title</span></label>
        <.input field={@form[:title]} type="text" placeholder="e.g. ACTO PRIMERO" />
      </div>
      <.input field={@form[:position]} type="hidden" />
      <div class="flex gap-2 pt-2">
        <button type="submit" class="btn btn-primary">Save</button>
        <button type="button" phx-click="close_modal" class="btn btn-ghost">Cancel</button>
      </div>
    </.form>
    """
  end

  defp modal_content(%{modal: :element} = assigns) do
    ~H"""
    <h3 class="text-lg font-bold mb-4">
      {editing_label(@editing)} {element_type_label(@modal_element_type)}
    </h3>
    <.form
      for={@form}
      as={:element}
      phx-change="validate_form"
      phx-submit="save_form"
      class="space-y-4"
    >
      <.input field={@form[:type]} type="hidden" />
      <.input field={@form[:position]} type="hidden" />
      <.input field={@form[:parent_id]} type="hidden" />

      <%!-- Speech fields --%>
      <div :if={@modal_element_type == "speech"}>
        <div class="mb-4">
          <label class="label"><span class="label-text font-medium">Speaker Label</span></label>
          <.input field={@form[:speaker_label]} type="text" placeholder="e.g. ANA" />
        </div>
        <div class="mb-4">
          <label class="label"><span class="label-text font-medium">Character</span></label>
          <.input
            field={@form[:character_id]}
            type="select"
            options={[{"(none)", ""} | Enum.map(@characters, &{&1.name, &1.id})]}
          />
        </div>
        <div>
          <label class="flex items-center gap-2">
            <.input field={@form[:is_aside]} type="checkbox" />
            <span class="label-text">Aside</span>
          </label>
        </div>
      </div>

      <%!-- Stage direction fields --%>
      <div :if={@modal_element_type == "stage_direction"}>
        <div class="mb-4">
          <label class="label"><span class="label-text font-medium">Content</span></label>
          <.input
            field={@form[:content]}
            type="textarea"
            rows="3"
            placeholder="Stage direction text..."
          />
        </div>
        <div>
          <label class="label"><span class="label-text font-medium">Rend</span></label>
          <.input field={@form[:rend]} type="text" placeholder="e.g. italics" />
        </div>
      </div>

      <%!-- Prose fields --%>
      <div :if={@modal_element_type == "prose"}>
        <label class="label"><span class="label-text font-medium">Content</span></label>
        <.input field={@form[:content]} type="textarea" rows="4" placeholder="Prose text..." />
      </div>

      <%!-- Line group fields --%>
      <div :if={@modal_element_type == "line_group"}>
        <label class="label"><span class="label-text font-medium">Verse Type</span></label>
        <.input field={@form[:verse_type]} type="select" options={verse_types()} />
      </div>

      <%!-- Verse line fields --%>
      <div :if={@modal_element_type == "verse_line"}>
        <div class="mb-4">
          <label class="label"><span class="label-text font-medium">Content *</span></label>
          <.input field={@form[:content]} type="text" required placeholder="Verse line text..." />
        </div>
        <div class="grid grid-cols-2 gap-4">
          <div>
            <label class="label"><span class="label-text font-medium">Line Number</span></label>
            <.input field={@form[:line_number]} type="number" />
          </div>
          <div>
            <label class="label"><span class="label-text font-medium">Part (split line)</span></label>
            <.input field={@form[:part]} type="select" options={part_options()} />
          </div>
        </div>
      </div>

      <div class="flex gap-2 pt-2">
        <button type="submit" class="btn btn-primary">Save</button>
        <button type="button" phx-click="close_modal" class="btn btn-ghost">Cancel</button>
      </div>
    </.form>
    """
  end
end
