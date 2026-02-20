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
    |> assign(:page_title, "New Play")
    |> assign(:play, play)
    |> assign(:form, to_form(Catalogue.change_play_form(play)))
    |> assign(:breadcrumbs, [
      %{label: "Admin", to: ~p"/admin/plays"},
      %{label: "Plays", to: ~p"/admin/plays"},
      %{label: "New Play"}
    ])
    |> assign(:play_context, nil)
  end

  defp apply_action(socket, :edit, %{"id" => id}) do
    play = Catalogue.get_play!(id)

    socket
    |> assign(:page_title, "Edit: #{play.title}")
    |> assign(:play, play)
    |> assign(:form, to_form(Catalogue.change_play_form(play)))
    |> assign(:breadcrumbs, [
      %{label: "Admin", to: ~p"/admin/plays"},
      %{label: "Plays", to: ~p"/admin/plays"},
      %{label: play.title, to: ~p"/admin/plays/#{play.id}"},
      %{label: "Edit Metadata"}
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

  defp save_play(socket, :new, play_params) do
    case Catalogue.create_play_from_form(play_params) do
      {:ok, play} ->
        {:noreply,
         socket
         |> put_flash(:info, "Play created successfully.")
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
         |> put_flash(:info, "Play updated successfully.")
         |> push_navigate(to: ~p"/admin/plays/#{play.id}")}

      {:error, %Ecto.Changeset{} = changeset} ->
        {:noreply, assign(socket, form: to_form(changeset))}
    end
  end

  defp language_options do
    [
      {"Spanish", "es"},
      {"English", "en"},
      {"Italian", "it"},
      {"Catalan", "ca"},
      {"French", "fr"},
      {"Portuguese", "pt"}
    ]
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="mx-auto max-w-4xl px-4 py-8">
      <div class="mb-6">
        <h1 class="text-3xl font-semibold tracking-tight text-base-content">{@page_title}</h1>
        <p class="mt-1 text-sm text-base-content/70">
          Update bibliographic and editorial metadata for this play.
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
            <label class="label"><span class="label-text font-medium">Title *</span></label>
            <.input field={@form[:title]} type="text" required />
          </div>
          <div>
            <label class="label"><span class="label-text font-medium">Code *</span></label>
            <.input field={@form[:code]} type="text" required placeholder="e.g. AL0569" />
          </div>
        </div>

        <div class="grid grid-cols-1 gap-4 md:grid-cols-2">
          <div>
            <label class="label"><span class="label-text font-medium">Author Name</span></label>
            <.input field={@form[:author_name]} type="text" />
          </div>
          <div>
            <label class="label"><span class="label-text font-medium">Author (sort)</span></label>
            <.input field={@form[:author_sort]} type="text" placeholder="Surname, Name" />
          </div>
        </div>

        <div class="grid grid-cols-1 gap-4 md:grid-cols-2">
          <div>
            <label class="label"><span class="label-text font-medium">Language</span></label>
            <.input field={@form[:language]} type="select" options={language_options()} />
          </div>
          <div>
            <label class="label"><span class="label-text font-medium">Attribution</span></label>
            <.input field={@form[:author_attribution]} type="text" placeholder="fiable, dudosa..." />
          </div>
        </div>

        <div class="grid grid-cols-1 gap-4 md:grid-cols-2">
          <div>
            <label class="label"><span class="label-text font-medium">Publication Place</span></label>
            <.input field={@form[:pub_place]} type="text" />
          </div>
          <div>
            <label class="label"><span class="label-text font-medium">Publication Date</span></label>
            <.input
              field={@form[:publication_date]}
              type="text"
              placeholder="dd-mm-yyyy"
              pattern="[0-9]{2}-[0-9]{2}-[0-9]{4}"
            />
          </div>
        </div>

        <div class="rounded-box bg-base-200 px-3 py-2">
          <label class="flex items-center gap-2 text-sm text-base-content/85">
            <.input field={@form[:is_verse]} type="checkbox" /> Verse play
          </label>
        </div>

        <div class="flex flex-wrap gap-2 border-t border-base-300 pt-4">
          <button type="submit" class="btn btn-primary">
            Save Play
          </button>
          <.link navigate={~p"/admin/plays"} class="btn btn-ghost">
            Cancel
          </.link>
        </div>
      </.form>
    </div>
    """
  end
end
