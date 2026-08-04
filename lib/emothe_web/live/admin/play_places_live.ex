defmodule EmotheWeb.Admin.PlayPlacesLive do
  use EmotheWeb, :live_view

  alias Emothe.ActivityLog
  alias Emothe.Catalogue
  alias Emothe.Places
  alias Emothe.Places.Place
  alias EmotheWeb.PlayLabels

  @impl true
  def mount(%{"id" => id}, _session, socket) do
    play = Catalogue.get_play!(id)

    {:ok,
     socket
     |> assign(:page_title, "#{play.title} — #{gettext("Places")}")
     |> assign(:play, play)
     |> assign(:editing, nil)
     |> assign(:play_context, %{play: play, active_tab: :places})
     |> load_links()}
  end

  @impl true
  def handle_event("link", %{"place_id" => place_id} = params, socket) do
    case Places.link_place(socket.assigns.play.id, place_id, %{
           "role" => params["role"] || "setting"
         }) do
      {:ok, link} ->
        log(socket, "create", link)
        {:noreply, socket |> load_links() |> put_flash(:info, gettext("Place added."))}

      {:error, _changeset} ->
        {:noreply,
         put_flash(socket, :error, gettext("That place is already linked to this play."))}
    end
  end

  def handle_event("update_link", %{"link_id" => id, "play_place" => params}, socket) do
    link = Places.get_play_place!(id)

    case Places.update_play_place(link, params) do
      {:ok, updated} ->
        log(socket, "update", updated)
        {:noreply, socket |> load_links() |> put_flash(:info, gettext("Place updated."))}

      {:error, _changeset} ->
        {:noreply, put_flash(socket, :error, gettext("That change could not be saved."))}
    end
  end

  def handle_event("move_up", %{"id" => id}, socket) do
    :ok = id |> Places.get_play_place!() |> Places.move_play_place(:up)
    {:noreply, load_links(socket)}
  end

  def handle_event("move_down", %{"id" => id}, socket) do
    :ok = id |> Places.get_play_place!() |> Places.move_play_place(:down)
    {:noreply, load_links(socket)}
  end

  def handle_event("unlink", %{"id" => id}, socket) do
    link = Places.get_play_place!(id)
    {:ok, _} = Places.unlink_place(link)
    log(socket, "delete", link)
    {:noreply, socket |> load_links() |> put_flash(:info, gettext("Place removed."))}
  end

  def handle_event("new", _params, socket) do
    {:noreply, assign(socket, :editing, %Place{names: [%Places.PlaceName{}]})}
  end

  def handle_event("cancel_edit", _params, socket) do
    {:noreply, assign(socket, :editing, nil)}
  end

  @impl true
  def handle_info({:place_saved, place}, socket) do
    {:ok, link} = Places.link_place(socket.assigns.play.id, place.id, %{})
    log(socket, "create", link)

    {:noreply,
     socket
     |> assign(:editing, nil)
     |> load_links()
     |> put_flash(:info, gettext("Place created and added."))}
  end

  defp log(socket, action, link) do
    ActivityLog.log!(%{
      user_id: socket.assigns.current_user.id,
      play_id: socket.assigns.play.id,
      action: action,
      resource_type: "play_place",
      resource_id: link.id,
      metadata: %{place_id: link.place_id, role: link.role}
    })
  end

  defp load_links(socket) do
    links = Places.list_play_places(socket.assigns.play.id)
    linked = MapSet.new(links, & &1.place_id)

    available =
      Places.list_places()
      |> Enum.reject(&MapSet.member?(linked, &1.id))
      |> Enum.map(&{Places.display_name(&1, "es"), &1.id})

    socket
    |> assign(:links, links)
    |> assign(:available, available)
    |> assign(:gazetteer, Places.gazetteer())
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="mx-auto max-w-4xl px-4 py-8">
      <div class="mb-6 flex items-center justify-between">
        <div>
          <h1 class="text-2xl font-semibold tracking-tight text-base-content">
            {gettext("Places")}
          </h1>
          <p class="mt-1 text-sm text-base-content/60">
            {gettext("Where this play is set, and the places it names.")}
          </p>
        </div>
        <button :if={is_nil(@editing)} phx-click="new" class="btn btn-ghost btn-sm gap-1">
          <.icon name="hero-plus-mini" class="size-4" /> {gettext("New place")}
        </button>
      </div>

      <.live_component
        :if={@editing}
        module={EmotheWeb.Admin.PlaceFormComponent}
        id="place-form-component"
        place={@editing}
        current_user={@current_user}
        on_saved={fn place -> send(self(), {:place_saved, place}) end}
      />

      <form :if={@available != []} phx-submit="link" class="mb-6 mt-4 flex items-end gap-2">
        <div class="grow">
          <label class="label">
            <span class="label-text font-medium">{gettext("Add an existing place")}</span>
          </label>
          <select name="place_id" class="select select-bordered select-sm w-full">
            <option :for={{label, id} <- @available} value={id}>{label}</option>
          </select>
        </div>
        <div class="w-40">
          <label class="label"><span class="label-text font-medium">{gettext("Role")}</span></label>
          <select name="role" class="select select-bordered select-sm w-full">
            <option :for={{label, value} <- PlayLabels.place_role_options()} value={value}>
              {label}
            </option>
          </select>
        </div>
        <button type="submit" class="btn btn-primary btn-sm">{gettext("Add")}</button>
      </form>

      <div :if={@links == []} class="py-12 text-center text-base-content/50">
        <.icon name="hero-map-pin" class="mx-auto mb-3 size-12 opacity-30" />
        <p class="text-sm">{gettext("No places recorded for this play.")}</p>
      </div>

      <div class="space-y-3">
        <div
          :for={link <- @links}
          id={"link-#{link.id}"}
          class="rounded-box border border-base-300 bg-base-100 p-4 shadow-sm"
        >
          <div class="mb-2 flex items-start justify-between gap-3">
            <div>
              <span class="font-medium">{Places.display_name(link.place, "es")}</span>
              <span class="block text-xs text-base-content/50">
                {Places.breadcrumb(link.place, @gazetteer, "es")}
              </span>
            </div>
            <div class="flex gap-1">
              <button phx-click="move_up" phx-value-id={link.id} class="btn btn-ghost btn-xs">
                <.icon name="hero-arrow-up-micro" class="size-3.5" />
              </button>
              <button phx-click="move_down" phx-value-id={link.id} class="btn btn-ghost btn-xs">
                <.icon name="hero-arrow-down-micro" class="size-3.5" />
              </button>
              <button
                phx-click="unlink"
                phx-value-id={link.id}
                data-confirm={gettext("Remove this place from the play?")}
                class="btn btn-ghost btn-xs text-error"
              >
                {gettext("Remove")}
              </button>
            </div>
          </div>

          <form
            phx-submit="update_link"
            id={"link-form-#{link.id}"}
            class="flex flex-wrap items-end gap-2"
          >
            <input type="hidden" name="link_id" value={link.id} />
            <div class="w-40">
              <select name="play_place[role]" class="select select-bordered select-sm w-full">
                <option
                  :for={{label, value} <- PlayLabels.place_role_options()}
                  value={value}
                  selected={link.role == value}
                >
                  {label}
                </option>
              </select>
            </div>
            <div class="grow">
              <input
                type="text"
                name="play_place[note]"
                value={link.note}
                placeholder={gettext("Note, e.g. Act III only")}
                class="input input-bordered input-sm w-full"
              />
            </div>
            <button type="submit" class="btn btn-ghost btn-sm">{gettext("Save")}</button>
          </form>
        </div>
      </div>
    </div>
    """
  end
end
