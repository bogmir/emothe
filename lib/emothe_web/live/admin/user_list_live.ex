defmodule EmotheWeb.Admin.UserListLive do
  use EmotheWeb, :live_view

  alias Emothe.Accounts
  alias Emothe.ActivityLog

  @per_page 50

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(:page_title, gettext("Admin - Users"))
     |> assign(:users, [])
     |> assign(:search, "")
     |> assign(:page, 1)
     |> assign(:total_pages, 1)
     |> assign(:breadcrumbs, [
       %{label: gettext("Admin"), to: ~p"/admin/plays"},
       %{label: gettext("Users")}
     ])}
  end

  @impl true
  def handle_params(params, _url, socket) do
    search = params["search"] || ""
    page = parse_page(params["page"])

    total = Accounts.count_users(search: search)
    total_pages = max(1, ceil(total / @per_page))
    page = min(page, total_pages)

    users = Accounts.list_users(search: search, page: page, per_page: @per_page)

    {:noreply,
     socket
     |> assign(:users, users)
     |> assign(:search, search)
     |> assign(:page, page)
     |> assign(:total_pages, total_pages)}
  end

  @impl true
  def handle_event("search", %{"search" => search}, socket) do
    params = if search == "", do: [], else: [search: search]
    {:noreply, push_patch(socket, to: ~p"/admin/users?#{params}")}
  end

  def handle_event("set_role", %{"id" => id, "role" => role}, socket) do
    user = Accounts.get_user!(id)

    if user.id == socket.assigns.current_user.id do
      {:noreply, put_flash(socket, :error, gettext("You cannot change your own role."))}
    else
      old_role = user.role
      case Accounts.update_user_role(user, role) do
        {:ok, _user} ->
          ActivityLog.log!(%{
            user_id: socket.assigns.current_user.id,
            action: "role_change",
            resource_type: "user",
            resource_id: user.id,
            changes: %{"role" => [to_string(old_role), role]},
            metadata: %{email: user.email}
          })

          users =
            Accounts.list_users(
              search: socket.assigns.search,
              page: socket.assigns.page,
              per_page: @per_page
            )

          {:noreply, assign(socket, :users, users)}

        {:error, _changeset} ->
          {:noreply, put_flash(socket, :error, gettext("Failed to update role."))}
      end
    end
  end

  def handle_event("resend_confirmation", %{"id" => id}, socket) do
    user = Accounts.get_user!(id)

    case Accounts.deliver_user_confirmation_instructions(
           user,
           &url(~p"/users/confirm/#{&1}")
         ) do
      {:ok, _} ->
        {:noreply,
         put_flash(
           socket,
           :info,
           gettext("Confirmation email sent to %{email}.", email: user.email)
         )}

      {:error, :already_confirmed} ->
        {:noreply, put_flash(socket, :error, gettext("User is already confirmed."))}
    end
  end

  defp parse_page(nil), do: 1

  defp parse_page(s) do
    case Integer.parse(s) do
      {n, ""} -> max(1, n)
      _ -> 1
    end
  end

  defp page_params("", page), do: [page: page]
  defp page_params(search, page), do: [search: search, page: page]

  @impl true
  def render(assigns) do
    ~H"""
    <div class="mx-auto max-w-5xl px-4 py-8">
      <div class="mb-6 flex flex-wrap items-center justify-between gap-4">
        <div>
          <h1 class="text-3xl font-semibold tracking-tight text-base-content">
            {gettext("User Management")}
          </h1>
          <p class="mt-1 text-sm text-base-content/70">
            {gettext("Manage user roles and email confirmations.")}
          </p>
        </div>
      </div>

      <form phx-change="search" phx-submit="search" class="mb-5">
        <input
          type="text"
          name="search"
          value={@search}
          placeholder={gettext("Search by email...")}
          phx-debounce="300"
          class="input input-bordered w-full md:max-w-md"
        />
      </form>

      <div class="overflow-x-auto rounded-box border border-base-300 bg-base-100 shadow-sm">
        <table class="table table-zebra">
          <thead>
            <tr class="text-xs uppercase tracking-wide text-base-content/60">
              <th>{gettext("Email")}</th>
              <th class="w-28">{gettext("Role")}</th>
              <th class="w-28">{gettext("Confirmed")}</th>
              <th class="w-32">{gettext("Registered")}</th>
              <th class="w-36 text-right">{gettext("Actions")}</th>
            </tr>
          </thead>
          <tbody>
            <tr :for={user <- @users} class="hover">
              <td class="font-mono text-sm">
                {user.email}
                <span
                  :if={user.id == @current_user.id}
                  class="ml-1 badge badge-ghost badge-xs"
                >
                  {gettext("you")}
                </span>
              </td>
              <td>
                <span class={[
                  "badge badge-sm",
                  if(user.role == :admin, do: "badge-primary", else: "badge-ghost")
                ]}>
                  {user.role}
                </span>
              </td>
              <td>
                <span class={[
                  "badge badge-sm",
                  if(user.confirmed_at, do: "badge-success", else: "badge-warning")
                ]}>
                  {if user.confirmed_at,
                    do: gettext("confirmed"),
                    else: gettext("unconfirmed")}
                </span>
              </td>
              <td class="text-sm text-base-content/60">
                {Calendar.strftime(user.inserted_at, "%Y-%m-%d")}
              </td>
              <td>
                <div class="flex items-center justify-end gap-1">
                  <%= if user.id != @current_user.id do %>
                    <%= if user.role == :admin do %>
                      <button
                        phx-click="set_role"
                        phx-value-id={user.id}
                        phx-value-role="researcher"
                        data-confirm={gettext("Demote %{email} to researcher?", email: user.email)}
                        class="btn btn-ghost btn-xs tooltip tooltip-left"
                        data-tip={gettext("Demote to researcher")}
                      >
                        <.icon name="hero-arrow-down-mini" class="size-4" />
                      </button>
                    <% else %>
                      <button
                        phx-click="set_role"
                        phx-value-id={user.id}
                        phx-value-role="admin"
                        data-confirm={gettext("Promote %{email} to admin?", email: user.email)}
                        class="btn btn-ghost btn-xs tooltip tooltip-left"
                        data-tip={gettext("Promote to admin")}
                      >
                        <.icon name="hero-arrow-up-mini" class="size-4" />
                      </button>
                    <% end %>
                  <% end %>
                  <button
                    :if={is_nil(user.confirmed_at)}
                    phx-click="resend_confirmation"
                    phx-value-id={user.id}
                    class="btn btn-ghost btn-xs tooltip tooltip-left"
                    data-tip={gettext("Resend confirmation email")}
                  >
                    <.icon name="hero-envelope-mini" class="size-4" />
                  </button>
                </div>
              </td>
            </tr>
          </tbody>
        </table>
      </div>

      <p
        :if={@users == []}
        class="mt-8 rounded-box border border-dashed border-base-300 py-10 text-center text-base-content/60"
      >
        {gettext("No users found.")}
      </p>

      <div :if={@total_pages > 1} class="mt-6 flex items-center justify-center gap-4">
        <.link
          :if={@page > 1}
          patch={~p"/admin/users?#{page_params(@search, @page - 1)}"}
          class="btn btn-sm btn-ghost"
        >
          <.icon name="hero-chevron-left-mini" class="size-4" />{gettext("Previous")}
        </.link>
        <span class="text-sm text-base-content/60">
          {gettext("Page %{page} of %{total}", page: @page, total: @total_pages)}
        </span>
        <.link
          :if={@page < @total_pages}
          patch={~p"/admin/users?#{page_params(@search, @page + 1)}"}
          class="btn btn-sm btn-ghost"
        >
          {gettext("Next")}<.icon name="hero-chevron-right-mini" class="size-4" />
        </.link>
      </div>
    </div>
    """
  end
end
