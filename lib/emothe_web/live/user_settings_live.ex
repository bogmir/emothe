defmodule EmotheWeb.UserSettingsLive do
  use EmotheWeb, :live_view

  alias Emothe.Accounts

  def render(assigns) do
    ~H"""
    <.header class="text-center">
      {gettext("Account Settings")}
      <:subtitle>{gettext("Manage your account email address and password settings")}</:subtitle>
    </.header>

    <div class="space-y-12 divide-y">
      <div>
        <.simple_form
          for={@email_form}
          id="email_form"
          phx-submit="update_email"
          phx-change="validate_email"
        >
          <.input field={@email_form[:email]} type="email" label={gettext("Email")} required />
          <.input
            field={@email_form[:current_password]}
            name="current_password"
            id="current_password_for_email"
            type="password"
            label={gettext("Current password")}
            value={@email_form_current_password}
            required
          />
          <:actions>
            <.button phx-disable-with={gettext("Changing...")}>{gettext("Change Email")}</.button>
          </:actions>
        </.simple_form>
      </div>
      <div>
        <.simple_form
          for={@password_form}
          id="password_form"
          action={~p"/users/log-in?_action=password_updated"}
          method="post"
          phx-change="validate_password"
          phx-submit="update_password"
          phx-trigger-action={@trigger_submit}
        >
          <input
            name={@password_form[:email].name}
            type="hidden"
            id="hidden_user_email"
            value={@current_email}
          />
          <.input
            field={@password_form[:password]}
            type="password"
            label={gettext("New password")}
            required
          />
          <.input
            field={@password_form[:password_confirmation]}
            type="password"
            label={gettext("Confirm new password")}
          />
          <.input
            field={@password_form[:current_password]}
            name="current_password"
            type="password"
            label={gettext("Current password")}
            id="current_password_for_password"
            value={@current_password}
            required
          />
          <:actions>
            <.button phx-disable-with={gettext("Changing...")}>{gettext("Change Password")}</.button>
          </:actions>
        </.simple_form>
      </div>
      <div>
        <.header class="text-lg">
          {gettext("Active sessions")}
          <:subtitle>
            {gettext("Where your account is currently signed in.")}
          </:subtitle>
        </.header>

        <table class="table table-sm mt-4">
          <thead>
            <tr>
              <th>{gettext("Signed in")}</th>
              <th>{gettext("Address")}</th>
              <th>{gettext("Browser")}</th>
              <th></th>
            </tr>
          </thead>
          <tbody>
            <tr :for={session <- @sessions}>
              <td>{Calendar.strftime(session.inserted_at, "%Y-%m-%d %H:%M")}</td>
              <td class="font-mono text-xs">{session.ip_address || "—"}</td>
              <td class="max-w-xs truncate text-xs">{session.user_agent || "—"}</td>
              <td class="text-right">
                <span :if={session.token == @current_token} class="badge badge-sm badge-primary">
                  {gettext("This device")}
                </span>
                <button
                  :if={session.token != @current_token}
                  class="btn btn-xs btn-ghost text-error"
                  phx-click="revoke_session"
                  phx-value-id={session.id}
                >
                  {gettext("Revoke")}
                </button>
              </td>
            </tr>
          </tbody>
        </table>

        <button
          :if={length(@sessions) > 1}
          class="btn btn-sm btn-outline btn-error mt-4"
          phx-click="revoke_other_sessions"
        >
          {gettext("Sign out everywhere else")}
        </button>
      </div>
    </div>
    """
  end

  def mount(%{"token" => token}, _session, socket) do
    socket =
      case Accounts.update_user_email(socket.assigns.current_user, token) do
        :ok ->
          put_flash(socket, :info, gettext("Email changed successfully."))

        :error ->
          put_flash(socket, :error, gettext("Email change link is invalid or it has expired."))
      end

    {:ok, push_navigate(socket, to: ~p"/users/settings")}
  end

  def mount(_params, session, socket) do
    user = socket.assigns.current_user
    email_changeset = Accounts.change_user_email(user)
    password_changeset = Accounts.change_user_password(user)

    socket =
      socket
      |> assign(:current_password, nil)
      |> assign(:email_form_current_password, nil)
      |> assign(:current_email, user.email)
      |> assign(:email_form, to_form(email_changeset, as: "user"))
      |> assign(:password_form, to_form(password_changeset, as: "user"))
      |> assign(:trigger_submit, false)
      |> assign(:current_token, session["user_token"])
      |> assign_sessions()

    {:ok, socket}
  end

  defp assign_sessions(socket) do
    assign(socket, :sessions, Accounts.list_user_sessions(socket.assigns.current_user))
  end

  def handle_event("validate_email", params, socket) do
    %{"current_password" => password, "user" => user_params} = params

    email_form =
      socket.assigns.current_user
      |> Accounts.change_user_email(user_params)
      |> Map.put(:action, :validate)
      |> to_form(as: "user")

    {:noreply, assign(socket, email_form: email_form, email_form_current_password: password)}
  end

  def handle_event("update_email", params, socket) do
    %{"current_password" => password, "user" => user_params} = params
    user = socket.assigns.current_user

    case Accounts.apply_user_email(user, password, user_params) do
      {:ok, applied_user} ->
        Accounts.deliver_user_update_email_instructions(
          applied_user,
          user.email,
          &url(~p"/users/settings/confirm-email/#{&1}")
        )

        info = gettext("A link to confirm your email change has been sent to the new address.")
        {:noreply, socket |> put_flash(:info, info) |> assign(email_form_current_password: nil)}

      {:error, changeset} ->
        {:noreply,
         assign(socket, :email_form, to_form(Map.put(changeset, :action, :insert), as: "user"))}
    end
  end

  def handle_event("validate_password", params, socket) do
    %{"current_password" => password, "user" => user_params} = params

    password_form =
      socket.assigns.current_user
      |> Accounts.change_user_password(user_params)
      |> Map.put(:action, :validate)
      |> to_form(as: "user")

    {:noreply, assign(socket, password_form: password_form, current_password: password)}
  end

  def handle_event("update_password", params, socket) do
    %{"current_password" => password, "user" => user_params} = params
    user = socket.assigns.current_user

    case Accounts.update_user_password(user, password, user_params) do
      {:ok, user} ->
        password_form =
          user
          |> Accounts.change_user_password(user_params)
          |> to_form(as: "user")

        {:noreply, assign(socket, trigger_submit: true, password_form: password_form)}

      {:error, changeset} ->
        {:noreply, assign(socket, password_form: to_form(changeset, as: "user"))}
    end
  end

  def handle_event("revoke_session", %{"id" => id}, socket) do
    :ok = Accounts.delete_user_session(socket.assigns.current_user, id)

    {:noreply,
     socket
     |> put_flash(:info, gettext("Session revoked."))
     |> assign_sessions()}
  end

  def handle_event("revoke_other_sessions", _params, socket) do
    :ok =
      Accounts.delete_other_user_sessions(
        socket.assigns.current_user,
        socket.assigns.current_token
      )

    {:noreply,
     socket
     |> put_flash(:info, gettext("Signed out of all other sessions."))
     |> assign_sessions()}
  end
end
