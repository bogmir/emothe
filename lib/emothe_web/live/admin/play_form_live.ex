defmodule EmotheWeb.Admin.PlayFormLive do
  use EmotheWeb, :live_view

  alias Emothe.Catalogue
  alias Emothe.Catalogue.Play

  @impl true
  def mount(_params, _session, socket) do
    {:ok, socket}
  end

  @impl true
  def handle_params(params, _url, socket) do
    {:noreply, apply_action(socket, socket.assigns.live_action, params)}
  end

  defp apply_action(socket, :new, _params) do
    play = %Play{}

    socket
    |> assign(:page_title, gettext("New Play"))
    |> assign(:play, play)
    |> assign(:form, to_form(Catalogue.change_play_form(play)))
    |> assign(:parent_play_id, nil)
    |> assign(:parent_play_label, "")
    |> assign(:parent_play_search, "")
    |> assign(:parent_play_suggestions, [])
    |> assign(:breadcrumbs, [
      %{label: gettext("Admin"), to: ~p"/admin/plays"},
      %{label: gettext("Plays"), to: ~p"/admin/plays"},
      %{label: gettext("New Play")}
    ])
    |> assign(:play_context, nil)
  end

  defp apply_action(socket, :edit, %{"id" => id}) do
    play = Catalogue.get_play!(id)

    parent_label =
      if play.parent_play_id do
        parent = Catalogue.get_play!(play.parent_play_id)
        "#{parent.title} (#{parent.code})"
      else
        ""
      end

    socket
    |> assign(:page_title, "#{gettext("Edit")}: #{play.title}")
    |> assign(:play, play)
    |> assign(:form, to_form(Catalogue.change_play_form(play)))
    |> assign(:parent_play_id, play.parent_play_id)
    |> assign(:parent_play_label, parent_label)
    |> assign(:parent_play_search, "")
    |> assign(:parent_play_suggestions, [])
    |> assign(:breadcrumbs, [
      %{label: gettext("Admin"), to: ~p"/admin/plays"},
      %{label: gettext("Plays"), to: ~p"/admin/plays"},
      %{label: play.title, to: ~p"/admin/plays/#{play.id}"},
      %{label: gettext("Edit Metadata")}
    ])
    |> assign(:play_context, %{play: play, active_tab: :metadata})
  end

  @impl true
  def handle_event("validate", %{"play" => play_params}, socket) do
    changeset = Catalogue.change_play_form(socket.assigns.play, play_params)
    {:noreply, assign(socket, form: to_form(Map.put(changeset, :action, :validate)))}
  end

  def handle_event("save", %{"play" => play_params}, socket) do
    save_play(socket, socket.assigns.live_action, play_params)
  end

  def handle_event("suggest_parent", params, socket) do
    search = params["parent_play_search"] || ""

    suggestions =
      if String.trim(search) == "" do
        []
      else
        Catalogue.list_plays(search: search)
        |> Enum.reject(&(&1.id == socket.assigns.play.id))
        |> Enum.take(8)
      end

    {:noreply, assign(socket, parent_play_search: search, parent_play_suggestions: suggestions)}
  end

  def handle_event("pick_parent", %{"id" => id, "label" => label}, socket) do
    {:noreply,
     socket
     |> assign(:parent_play_id, id)
     |> assign(:parent_play_label, label)
     |> assign(:parent_play_search, "")
     |> assign(:parent_play_suggestions, [])}
  end

  def handle_event("clear_parent", _, socket) do
    {:noreply,
     socket
     |> assign(:parent_play_id, nil)
     |> assign(:parent_play_label, "")
     |> assign(:parent_play_search, "")
     |> assign(:parent_play_suggestions, [])}
  end

  defp save_play(socket, :new, play_params) do
    case Catalogue.create_play_from_form(play_params) do
      {:ok, play} ->
        {:noreply,
         socket
         |> put_flash(:info, gettext("Play created successfully."))
         |> push_navigate(to: ~p"/admin/plays/#{play.id}")}

      {:error, %Ecto.Changeset{} = changeset} ->
        {:noreply, assign(socket, form: to_form(changeset))}
    end
  end

  defp save_play(socket, :edit, play_params) do
    case Catalogue.update_play_from_form(socket.assigns.play, play_params) do
      {:ok, play} ->
        {:noreply,
         socket
         |> put_flash(:info, gettext("Play updated successfully."))
         |> push_navigate(to: ~p"/admin/plays/#{play.id}")}

      {:error, %Ecto.Changeset{} = changeset} ->
        {:noreply, assign(socket, form: to_form(changeset))}
    end
  end

  defp relationship_type_options do
    [
      {gettext("— (Original / standalone)"), ""},
      {gettext("Translation"), "traduccion"},
      {gettext("Adaptation"), "adaptacion"},
      {gettext("Reworking"), "refundicion"}
    ]
  end

  defp language_options do
    [
      {gettext("Spanish"), "es"},
      {gettext("English"), "en"},
      {gettext("Italian"), "it"},
      {gettext("Catalan"), "ca"},
      {gettext("French"), "fr"},
      {gettext("Portuguese"), "pt"}
    ]
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="mx-auto max-w-4xl px-4 py-8">
      <div class="mb-6">
        <h1 class="text-3xl font-semibold tracking-tight text-base-content">{@page_title}</h1>
        <p class="mt-1 text-sm text-base-content/70">
          {gettext("Update bibliographic and editorial metadata for this play.")}
        </p>
      </div>

      <.form
        for={@form}
        phx-change="validate"
        phx-submit="save"
        class="space-y-6 rounded-box border border-base-300 bg-base-100 p-5 shadow-sm"
      >
        <div class="grid grid-cols-1 gap-4 md:grid-cols-2">
          <div>
            <label class="label">
              <span class="label-text font-medium">{gettext("Title")} *</span>
            </label>
            <.input field={@form[:title]} type="text" required />
          </div>
          <div>
            <label class="label">
              <span class="label-text font-medium">{gettext("Original Title")}</span>
            </label>
            <.input
              field={@form[:original_title]}
              type="text"
              placeholder={gettext("Title in original language")}
            />
          </div>
        </div>

        <div class="grid grid-cols-1 gap-4 md:grid-cols-2">
          <div>
            <label class="label">
              <span class="label-text font-medium">{gettext("Title (sort)")}</span>
            </label>
            <.input
              field={@form[:title_sort]}
              type="text"
              placeholder={gettext("Alphabetical sorting form")}
            />
          </div>
          <div>
            <label class="label">
              <span class="label-text font-medium">{gettext("Edition Title")}</span>
            </label>
            <.input
              field={@form[:edition_title]}
              type="text"
              placeholder={gettext("Full editorial citation")}
            />
          </div>
        </div>

        <div class="grid grid-cols-1 gap-4 md:grid-cols-2">
          <div>
            <label class="label">
              <span class="label-text font-medium">{gettext("Code")} *</span>
            </label>
            <.input field={@form[:code]} type="text" required placeholder={gettext("e.g. AL0569")} />
          </div>
          <div>
            <label class="label">
              <span class="label-text font-medium">{gettext("EMOTHE ID")}</span>
            </label>
            <.input field={@form[:emothe_id]} type="text" placeholder={gettext("e.g. 0703")} />
          </div>
        </div>

        <div class="space-y-3 rounded-box border border-base-300 bg-base-50 p-4">
          <h3 class="text-sm font-semibold uppercase tracking-wide text-base-content/60">
            {gettext("Work Relationship")}
          </h3>
          <div class="grid grid-cols-1 gap-4 md:grid-cols-2">
            <div>
              <label class="label">
                <span class="label-text font-medium">{gettext("Relationship Type")}</span>
              </label>
              <.input
                field={@form[:relationship_type]}
                type="select"
                options={relationship_type_options()}
              />
            </div>
            <div>
              <label class="label">
                <span class="label-text font-medium">{gettext("Original Work")}</span>
              </label>
              <%!-- Autocomplete combobox for parent play --%>
              <div class="relative">
                <%!-- Selected state --%>
                <div
                  :if={@parent_play_id}
                  class="input input-bordered flex items-center justify-between gap-2 h-auto min-h-[2.5rem] py-1.5"
                >
                  <span class="text-sm truncate">{@parent_play_label}</span>
                  <button
                    type="button"
                    phx-click="clear_parent"
                    class="btn btn-ghost btn-xs btn-circle shrink-0"
                    title={gettext("Clear")}
                  >
                    <.icon name="hero-x-mark-mini" class="size-3.5" />
                  </button>
                </div>
                <%!-- Search state --%>
                <div :if={!@parent_play_id}>
                  <input
                    type="text"
                    name="parent_play_search"
                    value={@parent_play_search}
                    phx-change="suggest_parent"
                    phx-debounce="200"
                    placeholder={gettext("Search by title or code...")}
                    class="input input-bordered w-full"
                    autocomplete="off"
                  />
                  <%!-- Suggestions dropdown --%>
                  <ul
                    :if={@parent_play_suggestions != []}
                    class="absolute z-20 mt-1 w-full bg-base-100 border border-base-300 rounded-box shadow-lg max-h-64 overflow-y-auto"
                  >
                    <li :for={sugg <- @parent_play_suggestions}>
                      <button
                        type="button"
                        phx-click="pick_parent"
                        phx-value-id={sugg.id}
                        phx-value-label={sugg.title}
                        class="w-full text-left px-3 py-2 hover:bg-base-200 transition-colors"
                      >
                        <div class="text-sm font-medium text-base-content truncate">
                          {sugg.title}
                        </div>
                        <div class="text-xs text-base-content/50 truncate mt-0.5">
                          {sugg.code}
                        </div>
                      </button>
                    </li>
                  </ul>
                  <p
                    :if={@parent_play_search == ""}
                    class="mt-1 text-xs text-base-content/50"
                  >
                    {gettext("Type to search for a play")}
                  </p>
                  <p
                    :if={@parent_play_search != "" && @parent_play_suggestions == []}
                    class="mt-1 text-xs text-base-content/50"
                  >
                    {gettext("No plays found")}
                  </p>
                </div>
                <%!-- Hidden input carries the value through form submit / validate --%>
                <input
                  type="hidden"
                  name={@form[:parent_play_id].name}
                  value={@parent_play_id || ""}
                />
              </div>
            </div>
          </div>
        </div>

        <div class="grid grid-cols-1 gap-4 md:grid-cols-2">
          <div>
            <label class="label">
              <span class="label-text font-medium">{gettext("Author Name")}</span>
            </label>
            <.input field={@form[:author_name]} type="text" />
          </div>
          <div>
            <label class="label">
              <span class="label-text font-medium">{gettext("Author (sort)")}</span>
            </label>
            <.input field={@form[:author_sort]} type="text" placeholder={gettext("Surname, Name")} />
          </div>
        </div>

        <div class="grid grid-cols-1 gap-4 md:grid-cols-2">
          <div>
            <label class="label">
              <span class="label-text font-medium">{gettext("Language")}</span>
            </label>
            <.input field={@form[:language]} type="select" options={language_options()} />
          </div>
          <div>
            <label class="label">
              <span class="label-text font-medium">{gettext("Attribution")}</span>
            </label>
            <.input
              field={@form[:author_attribution]}
              type="text"
              placeholder={gettext("fiable, dudosa...")}
            />
          </div>
        </div>

        <div class="grid grid-cols-1 gap-4 md:grid-cols-2">
          <div>
            <label class="label">
              <span class="label-text font-medium">{gettext("Publication Place")}</span>
            </label>
            <.input field={@form[:pub_place]} type="text" />
          </div>
          <div>
            <label class="label">
              <span class="label-text font-medium">{gettext("Publication Date")}</span>
            </label>
            <.input
              field={@form[:publication_date]}
              type="text"
              placeholder="e.g. 2023 or 01-01-2023"
            />
          </div>
        </div>

        <div class="grid grid-cols-1 gap-4 md:grid-cols-2">
          <div>
            <label class="label">
              <span class="label-text font-medium">{gettext("Publisher")}</span>
            </label>
            <.input field={@form[:publisher]} type="text" />
          </div>
          <div>
            <label class="label">
              <span class="label-text font-medium">{gettext("Authority")}</span>
            </label>
            <.input
              field={@form[:authority]}
              type="text"
              placeholder={gettext("Institutional authority")}
            />
          </div>
        </div>

        <div>
          <label class="label">
            <span class="label-text font-medium">{gettext("Availability Note")}</span>
          </label>
          <.input
            field={@form[:availability_note]}
            type="textarea"
            placeholder={gettext("Usage terms and citation info")}
          />
        </div>

        <div class="rounded-box bg-base-200 px-3 py-2">
          <label class="flex items-center gap-2 text-sm text-base-content/85">
            <.input field={@form[:is_verse]} type="checkbox" /> {gettext("Verse play")}
          </label>
        </div>

        <div class="space-y-3 rounded-box border border-base-300 bg-base-50 p-4">
          <h3 class="text-sm font-semibold uppercase tracking-wide text-base-content/60">
            {gettext("Funding & Licence")}
          </h3>
          <div>
            <label class="label">
              <span class="label-text font-medium">{gettext("Sponsor")}</span>
            </label>
            <.input
              field={@form[:sponsor]}
              type="text"
              placeholder={gettext("Sponsoring organization")}
            />
          </div>
          <div>
            <label class="label">
              <span class="label-text font-medium">{gettext("Funder")}</span>
            </label>
            <.input
              field={@form[:funder]}
              type="textarea"
              placeholder={gettext("Funding organization(s) and grant references")}
            />
          </div>
          <div>
            <label class="label">
              <span class="label-text font-medium">{gettext("Licence URL")}</span>
            </label>
            <.input
              field={@form[:licence_url]}
              type="text"
              placeholder="https://creativecommons.org/licenses/..."
            />
          </div>
          <div>
            <label class="label">
              <span class="label-text font-medium">{gettext("Licence Text")}</span>
            </label>
            <.input
              field={@form[:licence_text]}
              type="text"
              placeholder={gettext("e.g. CC BY-NC-ND 4.0")}
            />
          </div>
        </div>

        <div class="flex flex-wrap gap-2 border-t border-base-300 pt-4">
          <button type="submit" class="btn btn-primary">
            {gettext("Save Play")}
          </button>
          <.link navigate={~p"/admin/plays"} class="btn btn-ghost">
            {gettext("Cancel")}
          </.link>
        </div>
      </.form>
    </div>
    """
  end
end
