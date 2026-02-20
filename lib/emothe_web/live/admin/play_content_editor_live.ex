defmodule EmotheWeb.Admin.PlayContentEditorLive do
  use EmotheWeb, :live_view

  import EmotheWeb.Components.PlayText

  alias Emothe.Catalogue
  alias Emothe.PlayContent
  alias Emothe.PlayContent.{Character, Division, Element}

  @impl true
  def mount(%{"id" => id}, _session, socket) do
    play = Catalogue.get_play!(id)

    if connected?(socket) do
      PlayContent.subscribe(play.id)
    end

    characters = PlayContent.list_characters(play.id)
    divisions = PlayContent.list_top_divisions(play.id)

    {:ok,
     socket
     |> assign(
       page_title: "#{gettext("Edit Content")}: #{play.title}",
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
       preview_divisions: [],
       editor_tab: :characters,
       breadcrumbs: [
         %{label: gettext("Admin"), to: ~p"/admin/plays"},
         %{label: gettext("Plays"), to: ~p"/admin/plays"},
         %{label: play.title, to: ~p"/admin/plays/#{play.id}"},
         %{label: gettext("Edit Content")}
       ],
       play_context: %{play: play, active_tab: :content}
     )}
  end

  # --- All handle_event/3 clauses grouped together ---

  @impl true
  def handle_event("close_modal", _, socket) do
    {:noreply, assign(socket, modal: nil, form: nil, editing: nil)}
  end

  def handle_event("switch_tab", %{"tab" => tab}, socket) do
    tab = String.to_existing_atom(tab)

    socket =
      case tab do
        :preview ->
          preview = PlayContent.load_play_content(socket.assigns.play.id)
          scroll_target = preview_scroll_target(socket.assigns)

          socket
          |> assign(editor_tab: :preview, preview_divisions: preview)
          |> then(fn s ->
            if scroll_target,
              do: push_event(s, "scroll-to-preview", %{target: scroll_target}),
              else: s
          end)

        _ ->
          assign(socket, editor_tab: tab)
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
    PlayContent.broadcast_content_changed(socket.assigns.play.id)

    {:noreply,
     socket
     |> put_flash(:info, gettext("Character deleted."))
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
    PlayContent.broadcast_content_changed(socket.assigns.play.id)

    selected =
      if socket.assigns.selected_division_id == id,
        do: nil,
        else: socket.assigns.selected_division_id

    {:noreply,
     socket
     |> put_flash(:info, gettext("Division deleted."))
     |> assign(selected_division_id: selected)
     |> reload_divisions()
     |> reload_elements()}
  end

  def handle_event("select_division", %{"id" => id}, socket) do
    {:noreply,
     socket
     |> assign(selected_division_id: id, editor_tab: :content)
     |> reload_elements()}
  end

  def handle_event("select_division_auto", %{"id" => id}, socket) do
    target_id =
      case find_division(socket.assigns.divisions, id) do
        %{children: [first_child | _]} -> first_child.id
        _ -> id
      end

    {:noreply,
     socket
     |> assign(selected_division_id: target_id, editor_tab: :content)
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

    should_shift_down =
      element.type == "verse_line" &&
        element.line_number != nil &&
        !PlayContent.split_verse?(play_id, element.id, element.line_number)

    {:ok, _} = PlayContent.delete_element(element)

    if should_shift_down do
      PlayContent.shift_line_numbers_down(play_id, element.line_number)
    end

    PlayContent.broadcast_content_changed(play_id)

    {:noreply,
     socket
     |> put_flash(:info, gettext("Element deleted."))
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
        PlayContent.broadcast_content_changed(play.id)

        {:noreply,
         socket
         |> put_flash(:info, gettext("Character saved."))
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
        PlayContent.broadcast_content_changed(play.id)

        {:noreply,
         socket
         |> put_flash(:info, gettext("Division saved."))
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
        PlayContent.broadcast_content_changed(play.id)

        {:noreply,
         socket
         |> put_flash(:info, gettext("Element saved."))
         |> assign(modal: nil, form: nil, editing: nil, modal_element_type: nil)
         |> reload_elements()}

      {:error, changeset} ->
        {:noreply, assign(socket, form: to_form(changeset))}
    end
  end

  # --- PubSub handler ---

  @impl true
  def handle_info({:play_content_changed, _play_id}, socket) do
    play = Catalogue.get_play!(socket.assigns.play.id)

    {:noreply,
     socket
     |> assign(:play, play)
     |> reload_characters()
     |> reload_divisions()
     |> reload_elements()}
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
    if socket.assigns.editor_tab == :preview do
      assign(socket, preview_divisions: PlayContent.load_play_content(socket.assigns.play.id))
    else
      socket
    end
  end

  defp extract_form_params(params, :character), do: params["character"] || %{}
  defp extract_form_params(params, :division), do: params["division"] || %{}
  defp extract_form_params(params, :element), do: params["element"] || %{}
  defp extract_form_params(_params, _), do: %{}

  defp editing_label(nil), do: gettext("Add")
  defp editing_label(_), do: gettext("Edit")

  defp find_division(divisions, id) do
    Enum.find_value(divisions, fn div ->
      if div.id == id do
        div
      else
        Enum.find(div.children || [], &(&1.id == id))
      end
    end)
  end

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
      <%!-- Header --%>
      <div class="mb-6">
        <h1 class="text-3xl font-semibold tracking-tight text-base-content">
          {gettext("Edit Content")}: {@play.title}
        </h1>
        <p class="mt-1 text-sm text-base-content/70">{@play.author_name} — {@play.code}</p>
      </div>

      <%!-- Tab Bar --%>
      <div class="border-b border-base-300 mb-6">
        <nav class="-mb-px flex gap-1" aria-label="Editor tabs">
          <.tab_button
            tab={:characters}
            active={@editor_tab}
            icon="hero-user-group-mini"
            count={length(@characters)}
          />
          <.tab_button
            tab={:structure}
            active={@editor_tab}
            icon="hero-bars-3-bottom-left-mini"
            count={length(@divisions)}
          />
          <.tab_button
            tab={:content}
            active={@editor_tab}
            icon="hero-document-text-mini"
            badge={
              if @selected_division_id,
                do: selected_division_short_label(@divisions, @selected_division_id)
            }
          />
          <.tab_button tab={:preview} active={@editor_tab} icon="hero-eye-mini" />
        </nav>
      </div>

      <%!-- Tab: Characters --%>
      <div :if={@editor_tab == :characters} class="animate-in fade-in">
        <div class="mb-4 flex items-center justify-between">
          <h2 class="text-lg font-semibold text-base-content">
            {gettext("Dramatis Personae")}
            <span class="text-base-content/50 font-normal">({length(@characters)})</span>
          </h2>
          <button phx-click="new_character" class="btn btn-sm btn-primary gap-1">
            <.icon name="hero-plus-mini" class="size-4" /> {gettext("Add Character")}
          </button>
        </div>
        <div
          :if={@characters == []}
          class="rounded-box border border-dashed border-base-300 bg-base-200/30 p-8 text-center text-sm text-base-content/60"
        >
          <.icon name="hero-user-group" class="mx-auto mb-2 size-8 text-base-content/30" />
          <p>{gettext("No characters yet. Add one to get started.")}</p>
        </div>
        <div
          :if={@characters != []}
          class="divide-y rounded-box border border-base-300 bg-base-100 shadow-sm"
        >
          <div
            :for={char <- @characters}
            class="flex items-center justify-between gap-3 px-4 py-3 transition-colors hover:bg-base-200/40"
          >
            <div class="flex items-center gap-3 min-w-0">
              <div class="flex size-8 shrink-0 items-center justify-center rounded-full bg-primary/10 text-xs font-bold text-primary">
                {String.first(char.name)}
              </div>
              <div class="min-w-0">
                <span class="font-medium">{char.name}</span>
                <span class="ml-2 text-xs text-base-content/40 font-mono">{char.xml_id}</span>
                <p :if={char.description} class="text-sm text-base-content/60 truncate">
                  {char.description}
                </p>
              </div>
              <span :if={char.is_hidden} class="badge badge-ghost badge-xs">{gettext("hidden")}</span>
            </div>
            <div class="flex gap-1 shrink-0">
              <button
                phx-click="edit_character"
                phx-value-id={char.id}
                class="btn btn-ghost btn-xs tooltip"
                data-tip={gettext("Edit")}
              >
                <.icon name="hero-pencil-mini" class="size-4" />
              </button>
              <button
                phx-click="delete_character"
                phx-value-id={char.id}
                data-confirm={gettext("Delete this character? Speeches referencing it will lose their speaker.")}
                class="btn btn-ghost btn-xs text-error tooltip"
                data-tip={gettext("Delete")}
              >
                <.icon name="hero-trash-mini" class="size-4" />
              </button>
            </div>
          </div>
        </div>
      </div>

      <%!-- Tab: Structure --%>
      <div :if={@editor_tab == :structure} class="animate-in fade-in">
        <div class="mb-4 flex items-center justify-between">
          <h2 class="text-lg font-semibold text-base-content">
            {gettext("Play Structure")}
            <span class="text-base-content/50 font-normal">({length(@divisions)} {gettext("acts")})</span>
          </h2>
          <button phx-click="new_division" class="btn btn-sm btn-primary gap-1">
            <.icon name="hero-plus-mini" class="size-4" /> {gettext("Add Act")}
          </button>
        </div>
        <div
          :if={@divisions == []}
          class="rounded-box border border-dashed border-base-300 bg-base-200/30 p-8 text-center text-sm text-base-content/60"
        >
          <.icon name="hero-bars-3-bottom-left" class="mx-auto mb-2 size-8 text-base-content/30" />
          <p>{gettext("No acts or scenes yet. Add an act to get started.")}</p>
        </div>
        <div :if={@divisions != []} class="space-y-3">
          <div
            :for={div <- @divisions}
            class="rounded-box border border-base-300 bg-base-100 shadow-sm overflow-hidden"
          >
            <div class="flex items-center justify-between px-4 py-3 bg-base-200/30">
              <div class="flex items-center gap-2">
                <.icon name="hero-folder-mini" class="size-4 text-base-content/40" />
                <span class="font-semibold">{div.title || String.capitalize(div.type)}</span>
                <span class="text-sm text-base-content/50">{div.type} {div.number}</span>
              </div>
              <div class="flex items-center gap-1">
                <button
                  phx-click="select_division_auto"
                  phx-value-id={div.id}
                  class="btn btn-xs btn-ghost btn-outline gap-1"
                >
                  <.icon name="hero-pencil-square-mini" class="size-3" /> {gettext("Edit Content")}
                </button>
                <button
                  phx-click="edit_division"
                  phx-value-id={div.id}
                  class="btn btn-ghost btn-xs tooltip"
                  data-tip={gettext("Edit metadata")}
                >
                  <.icon name="hero-cog-6-tooth-mini" class="size-4" />
                </button>
                <button
                  phx-click="delete_division"
                  phx-value-id={div.id}
                  data-confirm={gettext("Delete this division and all its content?")}
                  class="btn btn-ghost btn-xs text-error tooltip"
                  data-tip={gettext("Delete")}
                >
                  <.icon name="hero-trash-mini" class="size-4" />
                </button>
              </div>
            </div>
            <%!-- Child divisions (scenes) --%>
            <div :if={div.children != []} class="divide-y divide-base-300/50">
              <div
                :for={child <- div.children}
                class="flex items-center justify-between px-4 py-2 pl-8 transition-colors hover:bg-base-200/30"
              >
                <button
                  phx-click="select_division"
                  phx-value-id={child.id}
                  class={[
                    "flex items-center gap-2 text-sm transition-colors",
                    if(@selected_division_id == child.id,
                      do: "font-bold text-primary",
                      else: "text-base-content/70 hover:text-base-content"
                    )
                  ]}
                >
                  <.icon name="hero-document-mini" class="size-3.5" />
                  {child.title || String.capitalize(child.type)} {child.number}
                  <span
                    :if={@selected_division_id == child.id}
                    class="badge badge-primary badge-xs ml-1"
                  >
                    {gettext("editing")}
                  </span>
                </button>
                <div class="flex gap-1">
                  <button
                    phx-click="edit_division"
                    phx-value-id={child.id}
                    class="btn btn-ghost btn-xs tooltip"
                    data-tip={gettext("Edit metadata")}
                  >
                    <.icon name="hero-cog-6-tooth-mini" class="size-4" />
                  </button>
                  <button
                    phx-click="delete_division"
                    phx-value-id={child.id}
                    data-confirm={gettext("Delete this scene and all its content?")}
                    class="btn btn-ghost btn-xs text-error tooltip"
                    data-tip={gettext("Delete")}
                  >
                    <.icon name="hero-trash-mini" class="size-4" />
                  </button>
                </div>
              </div>
            </div>
            <div class="border-t border-base-300 px-4 py-2 bg-base-200/20">
              <button
                phx-click="new_division"
                phx-value-parent-id={div.id}
                class="btn btn-xs btn-ghost gap-1"
              >
                <.icon name="hero-plus-mini" class="size-3" /> {gettext("Add Scene")}
              </button>
            </div>
          </div>
        </div>
      </div>

      <%!-- Tab: Content --%>
      <div :if={@editor_tab == :content} class="animate-in fade-in">
        <%!-- No division selected --%>
        <div
          :if={!@selected_division_id}
          class="rounded-box border border-dashed border-base-300 bg-base-200/30 p-12 text-center"
        >
          <.icon name="hero-cursor-arrow-rays" class="mx-auto mb-3 size-10 text-base-content/30" />
          <p class="text-base-content/60 mb-3">
            {gettext("Select a scene or act from the Structure tab to edit its content.")}
          </p>
          <button
            phx-click="switch_tab"
            phx-value-tab="structure"
            class="btn btn-sm btn-outline gap-1"
          >
            <.icon name="hero-bars-3-bottom-left-mini" class="size-4" /> {gettext("Go to Structure")}
          </button>
        </div>

        <%!-- Division selected --%>
        <div :if={@selected_division_id}>
          <%!-- Content header with division selector --%>
          <div class="mb-4 flex flex-wrap items-center justify-between gap-3">
            <div class="flex flex-col gap-1">
              <div
                :if={parent_division_label(@divisions, @selected_division_id)}
                class="flex items-center gap-1.5 text-sm text-base-content/50"
              >
                <.icon name="hero-folder-mini" class="size-3.5" />
                <span>{parent_division_label(@divisions, @selected_division_id)}</span>
                <.icon name="hero-chevron-right-mini" class="size-3" />
              </div>
              <div class="flex items-center gap-3">
                <h2 class="text-lg font-semibold text-base-content">
                  {current_division_label(@divisions, @selected_division_id)}
                </h2>
                <%!-- Quick division navigation --%>
                <div class="flex gap-1">
                  <button
                    :if={prev_division_id(@divisions, @selected_division_id)}
                    phx-click="select_division"
                    phx-value-id={prev_division_id(@divisions, @selected_division_id)}
                    class="btn btn-ghost btn-xs tooltip"
                    data-tip={gettext("Previous")}
                  >
                    <.icon name="hero-chevron-left-mini" class="size-4" />
                  </button>
                  <button
                    :if={next_division_id(@divisions, @selected_division_id)}
                    phx-click="select_division"
                    phx-value-id={next_division_id(@divisions, @selected_division_id)}
                    class="btn btn-ghost btn-xs tooltip"
                    data-tip={gettext("Next")}
                  >
                    <.icon name="hero-chevron-right-mini" class="size-4" />
                  </button>
                </div>
              </div>
            </div>
            <div class="flex gap-1">
              <button
                phx-click="new_element"
                phx-value-type="speech"
                class="btn btn-xs btn-primary gap-1"
              >
                <.icon name="hero-plus-mini" class="size-3" /> {gettext("Speech")}
              </button>
              <button
                phx-click="new_element"
                phx-value-type="stage_direction"
                class="btn btn-xs btn-outline gap-1"
              >
                <.icon name="hero-plus-mini" class="size-3" /> {gettext("Stage Dir.")}
              </button>
              <button
                phx-click="new_element"
                phx-value-type="prose"
                class="btn btn-xs btn-outline gap-1"
              >
                <.icon name="hero-plus-mini" class="size-3" /> {gettext("Prose")}
              </button>
            </div>
          </div>

          <div
            :if={@elements == []}
            class="rounded-box border border-dashed border-base-300 bg-base-200/30 p-8 text-center text-sm text-base-content/60"
          >
            <.icon name="hero-document-text" class="mx-auto mb-2 size-8 text-base-content/30" />
            <p>{gettext("No content yet. Add a speech, stage direction, or prose.")}</p>
          </div>
          <div :if={@elements != []} class="space-y-2">
            <.element_card
              :for={element <- @elements}
              element={element}
              characters={@characters}
              depth={0}
            />
          </div>
        </div>
      </div>

      <%!-- Tab: Preview --%>
      <div :if={@editor_tab == :preview} class="animate-in fade-in">
        <div class="mb-4">
          <h2 class="text-lg font-semibold text-base-content">{gettext("Play Text Preview")}</h2>
        </div>
        <div
          id="preview-scroll-container"
          phx-hook=".PreviewScroll"
          class="rounded-box border border-base-300 bg-base-100 p-6 shadow-sm max-h-[70vh] overflow-y-auto"
        >
          <script :type={Phoenix.LiveView.ColocatedHook} name=".PreviewScroll">
            export default {
              mounted() {
                this.handleEvent("scroll-to-preview", ({target}) => {
                  // Wait for LiveView DOM patch to complete
                  setTimeout(() => {
                    const el = document.getElementById(target)
                    if (el) {
                      const container = this.el
                      const elTop = el.offsetTop - container.offsetTop
                      container.scrollTo({top: elTop, behavior: "smooth"})
                    }
                  }, 100)
                })
              }
            }
          </script>
          <div :if={@preview_divisions == []} class="text-center py-8 text-base-content/60">
            <.icon name="hero-document" class="mx-auto mb-2 size-8 text-base-content/30" />
            <p>{gettext("No content to preview yet.")}</p>
          </div>
          <.play_body
            :if={@preview_divisions != []}
            divisions={@preview_divisions}
            show_line_numbers={true}
            show_stage_directions={true}
          />
        </div>
      </div>

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

  defp parent_division_label(divisions, id) do
    Enum.find_value(divisions, nil, fn div ->
      Enum.find_value(div.children || [], nil, fn child ->
        if child.id == id do
          div.title || "#{String.capitalize(div.type)} #{div.number}"
        end
      end)
    end)
  end

  defp current_division_label(divisions, id) do
    Enum.find_value(divisions, "Unknown", fn div ->
      if div.id == id do
        div.title || "#{String.capitalize(div.type)} #{div.number}"
      else
        Enum.find_value(div.children || [], nil, fn child ->
          if child.id == id do
            child.title || "#{String.capitalize(child.type)} #{child.number}"
          end
        end)
      end
    end)
  end

  defp selected_division_short_label(divisions, id) do
    Enum.find_value(divisions, nil, fn div ->
      if div.id == id do
        String.slice(div.title || "#{String.capitalize(div.type)} #{div.number}", 0..15)
      else
        Enum.find_value(div.children || [], nil, fn child ->
          if child.id == id do
            String.slice(div.title || "#{String.capitalize(div.type)} #{div.number}", 0..15)
          end
        end)
      end
    end)
  end

  defp all_leaf_divisions(divisions) do
    Enum.flat_map(divisions, fn div ->
      case div.children do
        [] -> [div.id]
        children -> Enum.map(children, & &1.id)
      end
    end)
  end

  defp prev_division_id(divisions, current_id) do
    leaves = all_leaf_divisions(divisions)
    idx = Enum.find_index(leaves, &(&1 == current_id))

    if idx && idx > 0, do: Enum.at(leaves, idx - 1)
  end

  defp next_division_id(divisions, current_id) do
    leaves = all_leaf_divisions(divisions)
    idx = Enum.find_index(leaves, &(&1 == current_id))

    if idx && idx < length(leaves) - 1, do: Enum.at(leaves, idx + 1)
  end

  defp preview_scroll_target(assigns) do
    case assigns.selected_division_id do
      nil -> nil
      id -> "div-#{id}"
    end
  end

  # --- Tab button component ---

  attr :tab, :atom, required: true
  attr :active, :atom, required: true
  attr :icon, :string, required: true
  attr :count, :integer, default: nil
  attr :badge, :string, default: nil

  defp tab_button(assigns) do
    ~H"""
    <button
      phx-click="switch_tab"
      phx-value-tab={@tab}
      class={[
        "flex items-center gap-2 px-4 py-2.5 text-sm font-medium border-b-2 transition-colors",
        if(@active == @tab,
          do: "border-primary text-primary",
          else:
            "border-transparent text-base-content/60 hover:text-base-content hover:border-base-300"
        )
      ]}
    >
      <.icon name={@icon} class="size-4" />
      <span class="capitalize">{@tab}</span>
      <span :if={@count} class="badge badge-sm badge-ghost">{@count}</span>
      <span :if={@badge} class="badge badge-sm badge-primary">{@badge}</span>
    </button>
    """
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
          <span :if={@element.is_aside} class="badge badge-ghost badge-xs ml-1">{gettext("aside")}</span>
        </div>
        <div class="flex gap-1">
          <%!-- Insert Above for top-level elements (speeches, stage dirs, prose) --%>
          <div :if={@depth == 0} class="dropdown dropdown-end">
            <label tabindex="0" class="btn btn-xs btn-ghost btn-outline">{gettext("Insert Above")}</label>
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
                  {gettext("Speech")}
                </button>
              </li>
              <li>
                <button
                  phx-click="new_element_before"
                  phx-value-type="stage_direction"
                  phx-value-position={@element.position}
                  phx-value-parent-id=""
                >
                  {gettext("Stage Direction")}
                </button>
              </li>
              <li>
                <button
                  phx-click="new_element_before"
                  phx-value-type="prose"
                  phx-value-position={@element.position}
                  phx-value-parent-id=""
                >
                  {gettext("Prose")}
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
            {gettext("Insert Above")}
          </button>
          <button
            phx-click="edit_element"
            phx-value-id={@element.id}
            class="btn btn-ghost btn-xs tooltip"
            data-tip={gettext("Edit")}
          >
            <.icon name="hero-pencil-mini" class="size-4" />
          </button>
          <button
            phx-click="delete_element"
            phx-value-id={@element.id}
            data-confirm={gettext("Delete this element and its children?")}
            class="btn btn-ghost btn-xs text-error tooltip"
            data-tip={gettext("Delete")}
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
          {gettext("Add Line Group")}
        </button>
        <button
          phx-click="new_element"
          phx-value-type="stage_direction"
          phx-value-parent-id={@element.id}
          class="btn btn-xs btn-ghost btn-outline"
        >
          {gettext("Add Stage Direction")}
        </button>
        <button
          phx-click="new_element"
          phx-value-type="prose"
          phx-value-parent-id={@element.id}
          class="btn btn-xs btn-ghost btn-outline"
        >
          {gettext("Add Prose")}
        </button>
      </div>
      <div :if={@element.type == "line_group"} class="border-t border-base-300 px-3 py-2">
        <button
          phx-click="new_element"
          phx-value-type="verse_line"
          phx-value-parent-id={@element.id}
          class="btn btn-xs btn-ghost btn-outline"
        >
          {gettext("Add Verse Line")}
        </button>
      </div>
    </div>
    """
  end

  defp element_type_label("speech"), do: gettext("Speech")
  defp element_type_label("stage_direction"), do: gettext("Stage Dir.")
  defp element_type_label("verse_line"), do: gettext("Verse")
  defp element_type_label("prose"), do: gettext("Prose")
  defp element_type_label("line_group"), do: gettext("Line Group")
  defp element_type_label(type), do: type

  # --- Modal content ---

  attr :modal, :atom, required: true
  attr :form, :any, required: true
  attr :editing, :any, default: nil
  attr :characters, :list, default: []
  attr :modal_element_type, :string, default: nil

  defp modal_content(%{modal: :character} = assigns) do
    ~H"""
    <h3 class="text-lg font-bold mb-4">{editing_label(@editing)} {gettext("Character")}</h3>
    <.form
      for={@form}
      as={:character}
      phx-change="validate_form"
      phx-submit="save_form"
      class="space-y-4"
    >
      <div>
        <label class="label"><span class="label-text font-medium">XML ID *</span></label>
        <.input field={@form[:xml_id]} type="text" required placeholder={gettext("e.g. DONA_ANA")} />
      </div>
      <div>
        <label class="label"><span class="label-text font-medium">{gettext("Name")} *</span></label>
        <.input field={@form[:name]} type="text" required placeholder={gettext("e.g. Dona Ana")} />
      </div>
      <div>
        <label class="label"><span class="label-text font-medium">{gettext("Description")}</span></label>
        <.input field={@form[:description]} type="text" placeholder={gettext("e.g. una dama")} />
      </div>
      <div>
        <label class="flex items-center gap-2">
          <.input field={@form[:is_hidden]} type="checkbox" />
          <span class="label-text">{gettext("Hidden character")}</span>
        </label>
      </div>
      <.input field={@form[:position]} type="hidden" />
      <div class="flex gap-2 pt-2">
        <button type="submit" class="btn btn-primary">{gettext("Save")}</button>
        <button type="button" phx-click="close_modal" class="btn btn-ghost">{gettext("Cancel")}</button>
      </div>
    </.form>
    """
  end

  defp modal_content(%{modal: :division} = assigns) do
    ~H"""
    <h3 class="text-lg font-bold mb-4">{editing_label(@editing)} {gettext("Division")}</h3>
    <.form
      for={@form}
      as={:division}
      phx-change="validate_form"
      phx-submit="save_form"
      class="space-y-4"
    >
      <div>
        <label class="label"><span class="label-text font-medium">{gettext("Type")} *</span></label>
        <.input field={@form[:type]} type="select" options={division_types()} />
      </div>
      <div>
        <label class="label"><span class="label-text font-medium">{gettext("Number")}</span></label>
        <.input field={@form[:number]} type="number" />
      </div>
      <div>
        <label class="label"><span class="label-text font-medium">{gettext("Title")}</span></label>
        <.input field={@form[:title]} type="text" placeholder={gettext("e.g. ACTO PRIMERO")} />
      </div>
      <.input field={@form[:position]} type="hidden" />
      <div class="flex gap-2 pt-2">
        <button type="submit" class="btn btn-primary">{gettext("Save")}</button>
        <button type="button" phx-click="close_modal" class="btn btn-ghost">{gettext("Cancel")}</button>
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
          <label class="label"><span class="label-text font-medium">{gettext("Speaker Label")}</span></label>
          <.input field={@form[:speaker_label]} type="text" placeholder={gettext("e.g. ANA")} />
        </div>
        <div class="mb-4">
          <label class="label"><span class="label-text font-medium">{gettext("Character")}</span></label>
          <.input
            field={@form[:character_id]}
            type="select"
            options={[{gettext("(none)"), ""} | Enum.map(@characters, &{&1.name, &1.id})]}
          />
        </div>
        <div>
          <label class="flex items-center gap-2">
            <.input field={@form[:is_aside]} type="checkbox" />
            <span class="label-text">{gettext("Aside")}</span>
          </label>
        </div>
      </div>

      <%!-- Stage direction fields --%>
      <div :if={@modal_element_type == "stage_direction"}>
        <div class="mb-4">
          <label class="label"><span class="label-text font-medium">{gettext("Content")}</span></label>
          <.input
            field={@form[:content]}
            type="textarea"
            rows="3"
            placeholder={gettext("Stage direction text...")}
          />
        </div>
        <div>
          <label class="label"><span class="label-text font-medium">Rend</span></label>
          <.input field={@form[:rend]} type="text" placeholder={gettext("e.g. italics")} />
        </div>
      </div>

      <%!-- Prose fields --%>
      <div :if={@modal_element_type == "prose"}>
        <label class="label"><span class="label-text font-medium">{gettext("Content")}</span></label>
        <.input field={@form[:content]} type="textarea" rows="4" placeholder={gettext("Prose text...")} />
      </div>

      <%!-- Line group fields --%>
      <div :if={@modal_element_type == "line_group"}>
        <label class="label"><span class="label-text font-medium">{gettext("Verse Type")}</span></label>
        <.input field={@form[:verse_type]} type="select" options={verse_types()} />
      </div>

      <%!-- Verse line fields --%>
      <div :if={@modal_element_type == "verse_line"}>
        <div class="mb-4">
          <label class="label"><span class="label-text font-medium">{gettext("Content")} *</span></label>
          <.input field={@form[:content]} type="text" required placeholder={gettext("Verse line text...")} />
        </div>
        <div class="grid grid-cols-2 gap-4">
          <div>
            <label class="label"><span class="label-text font-medium">{gettext("Line Number")}</span></label>
            <.input field={@form[:line_number]} type="number" />
          </div>
          <div>
            <label class="label"><span class="label-text font-medium">{gettext("Part (split line)")}</span></label>
            <.input field={@form[:part]} type="select" options={part_options()} />
          </div>
        </div>
      </div>

      <div class="flex gap-2 pt-2">
        <button type="submit" class="btn btn-primary">{gettext("Save")}</button>
        <button type="button" phx-click="close_modal" class="btn btn-ghost">{gettext("Cancel")}</button>
      </div>
    </.form>
    """
  end
end
