# Invite-only auth and admin shell — implementation plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace open self-registration and scattered `role == :admin` checks with invite-only accounts, one `Emothe.Authz` module, revocable sessions, and a sidebar admin layout.

**Architecture:** Accounts are created only by invitation; accepting an invite proves mailbox control and sets `confirmed_at`, so there is no separate confirmation step. Every authorization question routes through `Emothe.Authz.can?/3`, which both the router and the sidebar consult — nav and access can no longer disagree. Admin identity is declared in `ADMIN_EMAILS` and reconciled at boot, so it cannot be edited away from inside the app.

**Tech Stack:** Elixir 1.19.5 / OTP 28.1, Phoenix 1.8.3, LiveView 1.1.22, Ecto/PostgreSQL with UUID keys, bcrypt, Swoosh + gen_smtp, DaisyUI 5 / Tailwind 4, gettext.

**Design doc:** `docs/superpowers/specs/2026-08-02-auth-and-admin-ux-design.md`

## Global Constraints

- Shell PATH for every `mix`/`elixir`/`iex` command (asdf shims do not work in the sandbox):
  `export PATH="/home/bogdan/.asdf/installs/erlang/28.1/bin:/home/bogdan/.asdf/installs/elixir/1.19.5-otp-28/bin:/usr/bin:/usr/local/bin:/bin:$PATH"`
- TDD is mandatory: failing test first, watch it fail, minimal implementation, watch it pass, then `mix test` (whole suite) before claiming anything works.
- `mix format` after every task. `mix compile --warnings-as-errors` before every commit.
- All primary keys are `binary_id`. New columns are `utc_datetime` where they are timestamps.
- Passwords: minimum 12 characters, maximum 72 bytes. Unchanged.
- New user-facing strings go through `gettext(...)`. After a UI task run `mix gettext.extract --merge`; it fuzzy-matches new strings onto unrelated translations, so inspect every entry it marks `#, fuzzy` before trusting it.
- Never add a `role == :admin` or `Accounts.admin?/1` comparison outside `Emothe.Authz` after Task 4. That seam is what makes per-play scoping a local change later.
- Every code path that logs a user in must go through `EmotheWeb.UserAuth.log_in_user/3`. A second login path is an MFA bypass when MFA is added later.
- **Task 6 ends at a human approval gate.** It builds the sidebar as a dev-only mockup at `/demo/ui/admin/shell` and stops. Task 7, which swaps the real layout, does not start until the user has seen the mockup and approved it.

## Sequencing rules

- **Do not reorder the tasks.** The order is a security constraint, not a preference. Today anyone can self-register as a `:researcher`; Task 4 grants researchers content access. If Task 4 lands before Task 1 closes registration, every self-registered row becomes an editor of the corpus.
- **Tasks 1 and 2 belong in the same working session.** Between them there is deliberately no way to create an account at all — Task 1 deletes registration, Task 2 adds invitations. Do not stop in that gap.
- **Task 5 rewrites `deactivate_user/1`, which Task 1 wrote.** Deliberate, and flagged in the step. Task 1's version uses `Ecto.Multi.delete_all`, which cannot broadcast the LiveView disconnect; Task 5 introduces the broadcast helper, so the function moves onto it there. Do not "fix" this by hoisting it into Task 1.

## Decisions that are settled

Each of these was chosen by the user after being shown the alternatives, which are recorded
with their trade-offs in the design doc. A proposal to do otherwise is drift, not insight —
raise it with the user rather than acting on it.

- Invite-only accounts, not self-register-then-approve. Public registration is deleted.
- A flat researcher role (all content operations), *structured* so per-play scoping is a later local change. That structure is the point of `Emothe.Authz`, not incidental to it.
- A left sidebar admin shell, not a patched horizontal navbar.
- Baseline hardening plus session visibility. No login audit log this round.
- `ADMIN_EMAILS` reconciled at boot, not seeds and not UI promotion.
- No SSO. No MFA yet — but see the design doc's extension-points section for what must stay true so MFA remains cheap.

## Housekeeping

- **This plan and the design doc are intentionally uncommitted.** The user commits them
  themselves. Do not stage either file as part of a task commit.
- Report honestly. The most recent failure in this codebase is precisely this: `CLAUDE.md`
  claims "Email confirmation enforced" and the code has never enforced it. Do not add a
  second such claim — run the command, read the output, then say what happened.

---

## File Structure

**New:**

| File | Responsibility |
|---|---|
| `lib/emothe/authz.ex` | The only place that answers "may this user do that?" |
| `lib/emothe/accounts/admin_bootstrap.ex` | Reconciles `ADMIN_EMAILS` against the users table at boot |
| `lib/emothe_web/live/user_accept_invite_live.ex` | Invitee sets their password |
| `lib/emothe_web/live/current_path_hook.ex` | Assigns `:current_path` so the sidebar can mark the active entry |
| `lib/mix/tasks/emothe.invite.ex` | Break-glass invite from the console |
| `lib/emothe_web/controllers/demo_ui_html/admin_shell.html.heex` | **Temporary.** Shell mockup for visual approval; created in Task 6, deleted in Task 7 |
| `test/emothe/authz_test.exs` | The role × state × action matrix |
| `test/emothe/accounts_test.exs` | Invite lifecycle, deactivation, session queries |
| `test/emothe/accounts/admin_bootstrap_test.exs` | Reconciler idempotency and protection |
| `test/emothe_web/user_auth_test.exs` | The three gates |
| `test/emothe_web/live/user_accept_invite_live_test.exs` | Accept-invite page |
| `test/emothe_web/live/admin/user_list_live_test.exs` | Invite console |

**Modified:** `lib/emothe_web/controllers/demo_ui_controller.ex`, `lib/emothe_web/controllers/demo_ui_html/index.html.heex`, `lib/emothe/accounts.ex`, `lib/emothe/accounts/user.ex`, `lib/emothe/accounts/user_token.ex`, `lib/emothe/accounts/user_notifier.ex`, `lib/emothe/release.ex`, `lib/emothe/application.ex`, `config/runtime.exs`, `lib/emothe_web/user_auth.ex`, `lib/emothe_web/router.ex`, `lib/emothe_web/controllers/user_session_controller.ex`, `lib/emothe_web/live/user_login_live.ex`, `lib/emothe_web/live/user_settings_live.ex`, `lib/emothe_web/live/admin/user_list_live.ex`, `lib/emothe_web/components/layouts.ex`, `lib/emothe_web/components/layouts/admin.html.heex`, `lib/emothe_web/components/layouts/app.html.heex`, `test/support/fixtures.ex`, `test/support/conn_case.ex`.

**Deleted:** `lib/emothe_web/live/user_registration_live.ex`, `lib/emothe_web/live/user_confirmation_live.ex`, `lib/emothe_web/live/user_confirmation_instructions_live.ex`.

---

## Task 1: Close the door (slice A0)

Today anyone can self-register and the three auth gates never check `confirmed_at`. This task shuts both, and builds the test fixtures every later task needs. There are currently **no** tests for `Accounts` or `UserAuth` at all — this task creates the first ones.

**Files:**
- Create: `priv/repo/migrations/<generated>_add_deactivated_at_to_users.exs`
- Create: `test/emothe_web/user_auth_test.exs`
- Modify: `lib/emothe/accounts/user.ex` — add `deactivated_at` field, delete `registration_changeset/3`
- Modify: `lib/emothe/accounts.ex` — add `active?/1`, `deactivate_user/1`, `reactivate_user/1`; delete `register_user/1`, `change_user_registration/2`
- Modify: `lib/emothe_web/user_auth.ex:161-204,240-252` — the three gates
- Modify: `lib/emothe_web/router.ex:77,103-104` — drop registration and confirmation routes
- Modify: `lib/emothe_web/live/user_login_live.ex` — drop the Register link
- Modify: `test/support/fixtures.ex` — add `user_fixture/1`
- Modify: `test/support/conn_case.ex` — add `log_in_user/2`
- Modify: `test/emothe/activity_log_test.exs`, `test/emothe_web/live/admin/play_form_live_test.exs`, `test/emothe_web/live/admin/play_list_live_test.exs`, `test/emothe_web/controllers/admin/export_controller_test.exs` — switch to the fixture
- Delete: `lib/emothe_web/live/user_registration_live.ex`, `lib/emothe_web/live/user_confirmation_live.ex`, `lib/emothe_web/live/user_confirmation_instructions_live.ex`

**Interfaces:**
- Produces: `Emothe.Accounts.active?(user) :: boolean` — true only when `confirmed_at` is set and `deactivated_at` is nil. `Emothe.Accounts.deactivate_user(%User{}) :: {:ok, %User{}}` — sets `deactivated_at` and deletes all the user's tokens. `Emothe.Accounts.reactivate_user(%User{}) :: {:ok, %User{}}`. `Emothe.TestFixtures.user_fixture(attrs \\ %{}) :: %User{}`. `EmotheWeb.ConnCase.log_in_user(conn, user) :: Plug.Conn.t()`.
- Consumes: nothing.

- [x] **Step 1: Generate the migration**

```bash
mix ecto.gen.migration add_deactivated_at_to_users
```

Fill it in:

```elixir
defmodule Emothe.Repo.Migrations.AddDeactivatedAtToUsers do
  use Ecto.Migration

  def change do
    alter table(:users) do
      add :deactivated_at, :utc_datetime
    end
  end
end
```

- [x] **Step 2: Run the migration**

```bash
mix ecto.migrate && MIX_ENV=test mix ecto.migrate
```

Expected: two `create/alter table` lines, no error.

- [x] **Step 3: Add the schema field**

In `lib/emothe/accounts/user.ex`, after `field :confirmed_at, :utc_datetime`:

```elixir
    field :deactivated_at, :utc_datetime
```

- [x] **Step 4: Add the test fixtures**

In `test/support/fixtures.ex`, add to `Emothe.TestFixtures`:

```elixir
  @valid_user_password "verysecurepass123"

  def valid_user_password, do: @valid_user_password

  @doc """
  Inserts a user directly. Defaults to an active researcher.

  Accepts `:email`, `:role`, `:password`, `:confirmed_at`, `:deactivated_at`.
  Pass `confirmed_at: nil` for an unconfirmed user.
  """
  def user_fixture(attrs \\ %{}) do
    attrs = Enum.into(attrs, %{})

    %Emothe.Accounts.User{
      email: Map.get(attrs, :email, "user-#{System.unique_integer([:positive])}@example.com"),
      role: Map.get(attrs, :role, :researcher),
      confirmed_at: Map.get(attrs, :confirmed_at, DateTime.utc_now(:second)),
      deactivated_at: Map.get(attrs, :deactivated_at)
    }
    |> Emothe.Accounts.User.password_changeset(%{
      password: Map.get(attrs, :password, @valid_user_password)
    })
    |> Emothe.Repo.insert!()
  end

  def admin_fixture(attrs \\ %{}) do
    attrs |> Enum.into(%{}) |> Map.put(:role, :admin) |> user_fixture()
  end
```

In `test/support/conn_case.ex`, add after the `setup` block:

```elixir
  @doc """
  Puts a valid session token for `user` into `conn`.
  """
  def log_in_user(conn, user) do
    token = Emothe.Accounts.generate_user_session_token(user)

    conn
    |> Phoenix.ConnTest.init_test_session(%{})
    |> Plug.Conn.put_session(:user_token, token)
  end
```

- [x] **Step 5: Write the failing gate tests**

Create `test/emothe_web/user_auth_test.exs`:

```elixir
defmodule EmotheWeb.UserAuthTest do
  use EmotheWeb.ConnCase, async: true

  import Emothe.TestFixtures

  describe "require_authenticated_user/2" do
    test "given an unconfirmed user then access is refused", %{conn: conn} do
      user = user_fixture(confirmed_at: nil)

      conn =
        conn
        |> log_in_user(user)
        |> get(~p"/users/settings")

      assert redirected_to(conn) == ~p"/users/log-in"
    end

    test "given a deactivated user then access is refused", %{conn: conn} do
      user = user_fixture(deactivated_at: DateTime.utc_now(:second))

      conn =
        conn
        |> log_in_user(user)
        |> get(~p"/users/settings")

      assert redirected_to(conn) == ~p"/users/log-in"
    end

    test "given an active user then access is allowed", %{conn: conn} do
      conn =
        conn
        |> log_in_user(user_fixture())
        |> get(~p"/users/settings")

      assert html_response(conn, 200)
    end
  end

  describe "require_admin_user/2" do
    test "given an unconfirmed admin then the admin area is refused", %{conn: conn} do
      admin = admin_fixture(confirmed_at: nil)

      conn =
        conn
        |> log_in_user(admin)
        |> get(~p"/admin/plays")

      refute redirected_to(conn) == ~p"/admin/plays"
    end

    test "given a deactivated admin then the admin area is refused", %{conn: conn} do
      admin = admin_fixture(deactivated_at: DateTime.utc_now(:second))

      conn =
        conn
        |> log_in_user(admin)
        |> get(~p"/admin/plays")

      refute redirected_to(conn) == ~p"/admin/plays"
    end
  end

  describe "public registration" do
    test "given the registration path then it no longer exists", %{conn: conn} do
      assert_raise Phoenix.Router.NoRouteError, fn ->
        get(conn, "/users/register")
      end
    end
  end
end
```

- [x] **Step 6: Run the tests to verify they fail**

```bash
mix test test/emothe_web/user_auth_test.exs
```

Expected: the unconfirmed and deactivated tests FAIL (they currently reach the page, because no gate checks either column), and the registration test FAILS because the route still exists. The "active user then access is allowed" test should already pass.

- [x] **Step 7: Add `active?/1` and the deactivation functions**

In `lib/emothe/accounts.ex`, replace the `confirmed?/1` block (around line 369) with:

```elixir
  @doc """
  Returns true if the user has confirmed their email address.
  """
  def confirmed?(%User{confirmed_at: confirmed_at}), do: not is_nil(confirmed_at)
  def confirmed?(_), do: false

  @doc """
  Returns true if the user may log in: confirmed and not deactivated.
  """
  def active?(%User{confirmed_at: confirmed_at, deactivated_at: nil})
      when not is_nil(confirmed_at),
      do: true

  def active?(_), do: false

  @doc """
  Deactivates a user and destroys every token they hold.

  Deactivation rather than deletion, because `activity_logs.user_id`
  references this row.
  """
  def deactivate_user(%User{} = user) do
    changeset = Ecto.Changeset.change(user, deactivated_at: DateTime.utc_now(:second))

    Ecto.Multi.new()
    |> Ecto.Multi.update(:user, changeset)
    |> Ecto.Multi.delete_all(:tokens, UserToken.by_user_and_contexts_query(user, :all))
    |> Repo.transaction()
    |> case do
      {:ok, %{user: user}} -> {:ok, user}
      {:error, :user, changeset, _} -> {:error, changeset}
    end
  end

  @doc """
  Clears `deactivated_at`. Does not restore any tokens.
  """
  def reactivate_user(%User{} = user) do
    user |> Ecto.Changeset.change(deactivated_at: nil) |> Repo.update()
  end
```

- [x] **Step 8: Close the three gates**

In `lib/emothe_web/user_auth.ex`, replace `require_authenticated_user/2` (lines 237-252) with:

```elixir
  @doc """
  Used for routes that require an active user: authenticated, confirmed
  and not deactivated.
  """
  def require_authenticated_user(conn, _opts) do
    user = conn.assigns[:current_user]

    cond do
      is_nil(user) ->
        conn
        |> put_flash(:error, gettext("You must log in to access this page."))
        |> maybe_store_return_to()
        |> redirect(to: ~p"/users/log-in")
        |> halt()

      not Accounts.active?(user) ->
        reject_inactive(conn)

      true ->
        conn
    end
  end

  # Destroys the session of a user whose account is no longer usable, so they
  # get an explanation instead of a redirect loop.
  defp reject_inactive(conn) do
    user_token = get_session(conn, :user_token)
    user_token && Accounts.delete_user_session_token(user_token)

    conn
    |> renew_session()
    |> delete_resp_cookie(@remember_me_cookie)
    |> put_flash(
      :error,
      gettext("Your account is not active. Please contact an administrator.")
    )
    |> redirect(to: ~p"/users/log-in")
    |> halt()
  end
```

Replace `require_admin_user/2` (lines 254-266) with:

```elixir
  @doc """
  Used for routes that require an active admin.
  """
  def require_admin_user(conn, _opts) do
    user = conn.assigns[:current_user]

    cond do
      is_nil(user) or not Accounts.active?(user) ->
        require_authenticated_user(conn, [])

      not Accounts.admin?(user) ->
        conn
        |> put_flash(:error, gettext("You must be an admin to access this page."))
        |> redirect(to: ~p"/")
        |> halt()

      true ->
        conn
    end
  end
```

Replace the `:ensure_authenticated` and `:ensure_admin` `on_mount` clauses (lines 161-204) with:

```elixir
  def on_mount(:ensure_authenticated, _params, session, socket) do
    socket = mount_current_user(socket, session)

    if Accounts.active?(socket.assigns.current_user) do
      {:cont, socket}
    else
      {:halt, redirect_to_login(socket)}
    end
  end

  def on_mount(:ensure_admin, _params, session, socket) do
    socket = mount_current_user(socket, session)
    user = socket.assigns.current_user

    cond do
      not Accounts.active?(user) ->
        {:halt, redirect_to_login(socket)}

      not Accounts.admin?(user) ->
        socket =
          socket
          |> Phoenix.LiveView.put_flash(
            :error,
            gettext("You must be an admin to access this page.")
          )
          |> Phoenix.LiveView.redirect(to: ~p"/")

        {:halt, socket}

      true ->
        {:cont, socket}
    end
  end

  defp redirect_to_login(socket) do
    socket
    |> Phoenix.LiveView.put_flash(:error, gettext("You must log in to access this page."))
    |> Phoenix.LiveView.redirect(to: ~p"/users/log-in")
  end
```

- [x] **Step 9: Delete public registration and account confirmation**

Delete these three files:

```bash
git rm lib/emothe_web/live/user_registration_live.ex \
       lib/emothe_web/live/user_confirmation_live.ex \
       lib/emothe_web/live/user_confirmation_instructions_live.ex
```

In `lib/emothe_web/router.ex`, delete line 77 (`live "/users/register", UserRegistrationLive, :new`) and lines 103-104 (the two `/users/confirm` routes). The now-empty `live_session :current_user` block and its scope stay only if they still contain routes — after removing both confirm routes the `live_session :current_user do ... end` block is empty, so delete the `live_session` block but keep the surrounding scope for the `delete "/users/log-out"` route:

```elixir
  scope "/", EmotheWeb do
    pipe_through [:browser]

    delete "/users/log-out", UserSessionController, :delete
  end
```

In `lib/emothe/accounts.ex`, delete `register_user/1` (lines 64-80) and `change_user_registration/2` (lines 82-93), and delete the whole `## Confirmation` section: `deliver_user_confirmation_instructions/2` (lines 249-274), `confirm_user/1` (276-290) and `confirm_user_multi/1` (292-296). Keep `User.confirm_changeset/1` — `user_email_multi/3` still calls it.

In `lib/emothe/accounts/user.ex`, delete `registration_changeset/3` (lines 19-47). Keep the private `validate_email/2` and `validate_password/2`; `email_changeset/3` and `password_changeset/3` still use them.

In `lib/emothe/accounts/user_token.ex`, delete `defp days_for_context("confirm")` (line 130) and the `@confirm_validity_in_days` attribute (line 14).

In `lib/emothe_web/live/user_login_live.ex`, delete the `<:subtitle>` block containing the "Sign up" / register link and replace it with:

```heex
        <:subtitle>
          {gettext("Access is by invitation. Contact an administrator to request an account.")}
        </:subtitle>
```

In `lib/emothe_web/live/admin/user_list_live.ex`, delete the `handle_event("resend_confirmation", ...)` clause starting at line 83 and running to just before `defp parse_page(nil)`, and the button that triggers it at line 213 (the enclosing `<button ... phx-click="resend_confirmation" ...>` element). It calls the deleted `deliver_user_confirmation_instructions/2`, so leaving it in breaks compilation. Task 8 replaces it with "resend invite".

- [x] **Step 10: Point the existing tests at the fixture**

Four test files call the deleted `Accounts.register_user/1`. In each, replace the local login helper with the shared one.

`test/emothe_web/live/admin/play_list_live_test.exs` (lines 11-30), `test/emothe_web/live/admin/play_form_live_test.exs` and `test/emothe_web/controllers/admin/export_controller_test.exs` all define a `log_in_admin(conn)` helper. Replace each helper body with:

```elixir
  defp log_in_admin(conn) do
    log_in_user(conn, Emothe.TestFixtures.admin_fixture())
  end
```

and delete the now-unused `alias Emothe.Accounts`, `alias Emothe.Accounts.User` and `alias Emothe.Repo` lines from those files if nothing else uses them.

`test/emothe/activity_log_test.exs` defines its own `user_fixture/0` at lines 8-17. Delete it and add `import Emothe.TestFixtures` at the top of the module. Its call sites use `user_fixture()` with no arguments, which the shared fixture accepts.

- [x] **Step 11: Run the gate tests to verify they pass**

```bash
mix test test/emothe_web/user_auth_test.exs
```

Expected: PASS, 6 tests.

- [x] **Step 12: Run the whole suite**

```bash
mix test
```

Expected: PASS. Anything referencing a deleted route, module or function fails here — fix it now rather than deferring.

- [x] **Step 13: Deactivate every pre-existing account**

Every current row was created by open self-registration and none can be trusted. `ADMIN_EMAILS` does not exist yet (Task 3 introduces it), so deactivate all of them; Task 3's reconciler will create the real admins.

```bash
mix run -e 'Emothe.Repo.all(Emothe.Accounts.User) |> Enum.each(&Emothe.Accounts.deactivate_user/1); IO.puts("deactivated #{Emothe.Repo.aggregate(Emothe.Accounts.User, :count)} users")'
```

- [x] **Step 14: Format, compile, commit**

```bash
mix format
mix compile --warnings-as-errors
git add -A
git commit -m "feat: enforce account state and remove public registration

The three auth gates never checked confirmed_at, so an unconfirmed
account was a working account. They now require confirmed and
not-deactivated. Public registration and account-confirmation are
deleted outright: Task 2 replaces them with invitations."
```

---

## Task 2: Invitations (slice A1, part 1)

**Files:**
- Create: `priv/repo/migrations/<generated>_allow_null_hashed_password.exs`
- Create: `lib/emothe_web/live/user_accept_invite_live.ex`
- Create: `test/emothe/accounts_test.exs`
- Create: `test/emothe_web/live/user_accept_invite_live_test.exs`
- Modify: `lib/emothe/accounts/user.ex` — `invite_changeset/2`, `accept_invite_changeset/2`
- Modify: `lib/emothe/accounts/user_token.ex` — `"invite"` context validity
- Modify: `lib/emothe/accounts.ex` — invite functions
- Modify: `lib/emothe/accounts/user_notifier.ex` — invite email
- Modify: `lib/emothe_web/router.ex` — accept-invite route
- Modify: `test/support/fixtures.ex` — `invited_user_fixture/1`

**Interfaces:**
- Consumes: `Emothe.Accounts.active?/1` and `Emothe.TestFixtures.user_fixture/1` from Task 1.
- Produces:
  - `Emothe.Accounts.invite_user(email :: String.t(), role :: :admin | :researcher, invited_by :: %User{} | nil) :: {:ok, %User{}, token :: String.t()} | {:error, %Ecto.Changeset{}}` — creates or reuses the row, replaces any outstanding invite token, does **not** send mail.
  - `Emothe.Accounts.deliver_invite(user :: %User{}, token :: String.t(), url_fun :: (String.t() -> String.t())) :: {:ok, map()} | {:error, term()}`
  - `Emothe.Accounts.get_user_by_invite_token(token :: String.t()) :: %User{} | nil`
  - `Emothe.Accounts.accept_invite(user :: %User{}, attrs :: map()) :: {:ok, %User{}} | {:error, %Ecto.Changeset{}}`
  - `Emothe.Accounts.change_user_invite_acceptance(user, attrs \\ %{}) :: %Ecto.Changeset{}`
  - `Emothe.TestFixtures.invited_user_fixture(attrs \\ %{}) :: {%User{}, token :: String.t()}`

- [x] **Step 1: Generate and run the migration**

```bash
mix ecto.gen.migration allow_null_hashed_password
```

```elixir
defmodule Emothe.Repo.Migrations.AllowNullHashedPassword do
  use Ecto.Migration

  def change do
    alter table(:users) do
      modify :hashed_password, :string, null: true, from: {:string, null: false}
    end
  end
end
```

```bash
mix ecto.migrate && MIX_ENV=test mix ecto.migrate
```

- [x] **Step 2: Write the failing invite tests**

Create `test/emothe/accounts_test.exs`:

```elixir
defmodule Emothe.AccountsTest do
  use Emothe.DataCase, async: true

  import Emothe.TestFixtures

  alias Emothe.Accounts
  alias Emothe.Accounts.{User, UserToken}
  alias Emothe.Repo

  describe "invite_user/3" do
    test "given a new email then an invited user and a token are created" do
      assert {:ok, %User{} = user, token} =
               Accounts.invite_user("nuevo@uv.es", :researcher, nil)

      assert user.email == "nuevo@uv.es"
      assert user.role == :researcher
      assert is_nil(user.hashed_password)
      assert is_nil(user.confirmed_at)
      assert is_binary(token)
      assert Repo.get_by(UserToken, user_id: user.id, context: "invite")
    end

    test "given an email invited twice then the earlier token stops working" do
      {:ok, user, first} = Accounts.invite_user("dos@uv.es", :researcher, nil)
      {:ok, ^user, second} = Accounts.invite_user("dos@uv.es", :researcher, nil)

      refute first == second
      assert is_nil(Accounts.get_user_by_invite_token(first))
      assert %User{} = Accounts.get_user_by_invite_token(second)
    end

    test "given an already active user then inviting is refused" do
      user = user_fixture()

      assert {:error, :already_active} =
               Accounts.invite_user(user.email, :researcher, nil)
    end
  end

  describe "accept_invite/2" do
    test "given a valid token and password then the account becomes active" do
      {user, _token} = invited_user_fixture()

      assert {:ok, accepted} =
               Accounts.accept_invite(user, %{"password" => valid_user_password()})

      assert Accounts.active?(accepted)
      assert is_binary(accepted.hashed_password)
      assert Repo.all(from t in UserToken, where: t.context == "invite") == []
    end

    test "given a short password then acceptance fails and the account stays invited" do
      {user, _token} = invited_user_fixture()

      assert {:error, %Ecto.Changeset{}} =
               Accounts.accept_invite(user, %{"password" => "short"})

      refute Accounts.active?(Repo.reload!(user))
    end
  end

  describe "get_user_by_invite_token/1" do
    test "given a garbage token then nil" do
      assert is_nil(Accounts.get_user_by_invite_token("not-a-token"))
    end

    test "given a used token then nil" do
      {user, token} = invited_user_fixture()
      {:ok, _} = Accounts.accept_invite(user, %{"password" => valid_user_password()})

      assert is_nil(Accounts.get_user_by_invite_token(token))
    end

    test "given a token older than 7 days then nil" do
      {user, token} = invited_user_fixture()

      from(t in UserToken, where: t.user_id == ^user.id and t.context == "invite")
      |> Repo.update_all(
        set: [inserted_at: DateTime.add(DateTime.utc_now(:second), -8, :day)]
      )

      assert is_nil(Accounts.get_user_by_invite_token(token))
    end
  end

  describe "deactivate_user/1" do
    test "given an active user with a session then the session token is destroyed" do
      user = user_fixture()
      _token = Accounts.generate_user_session_token(user)

      assert {:ok, deactivated} = Accounts.deactivate_user(user)
      refute Accounts.active?(deactivated)
      assert Repo.all(from t in UserToken, where: t.user_id == ^user.id) == []
    end
  end
end
```

Add the fixture to `test/support/fixtures.ex`:

```elixir
  @doc """
  Creates an invited (password-less, unconfirmed) user.

  Returns `{user, raw_invite_token}`.
  """
  def invited_user_fixture(attrs \\ %{}) do
    attrs = Enum.into(attrs, %{})
    email = Map.get(attrs, :email, "invited-#{System.unique_integer([:positive])}@example.com")
    role = Map.get(attrs, :role, :researcher)

    {:ok, user, token} = Emothe.Accounts.invite_user(email, role, nil)
    {user, token}
  end
```

- [x] **Step 3: Run the tests to verify they fail**

```bash
mix test test/emothe/accounts_test.exs
```

Expected: FAIL with `function Emothe.Accounts.invite_user/3 is undefined`.

- [x] **Step 4: Add the changesets**

In `lib/emothe/accounts/user.ex`, add after the schema:

```elixir
  @doc """
  A changeset for creating an invited user: email and role, no password.
  """
  def invite_changeset(user, attrs) do
    user
    |> cast(attrs, [:email, :role])
    |> validate_required([:role])
    |> validate_email([])
  end

  @doc """
  A changeset for accepting an invitation: sets the password and marks the
  account confirmed, because clicking the emailed link proves control of the
  mailbox.
  """
  def accept_invite_changeset(user, attrs, opts \\ []) do
    user
    |> password_changeset(attrs, opts)
    |> put_change(:confirmed_at, DateTime.utc_now(:second))
  end
```

- [x] **Step 5: Add the invite token context**

In `lib/emothe/accounts/user_token.ex`, add the attribute next to the other validities:

```elixir
  @invite_validity_in_days 7
```

and the clause next to the other `days_for_context/1` clauses:

```elixir
  defp days_for_context("invite"), do: @invite_validity_in_days
```

- [x] **Step 6: Add the Accounts functions**

In `lib/emothe/accounts.ex`, add a `## Invitations` section after the getters:

```elixir
  ## Invitations

  @doc """
  Creates or re-invites a user.

  Returns `{:ok, user, raw_token}`. Any outstanding invite token for the user
  is deleted first, so re-inviting invalidates the earlier link. Refuses to
  invite an account that can already log in.
  """
  def invite_user(email, role, invited_by \\ nil) when is_binary(email) do
    case get_user_by_email(email) do
      %User{} = user ->
        if active?(user), do: {:error, :already_active}, else: issue_invite(user, role)

      nil ->
        %User{}
        |> User.invite_changeset(%{email: email, role: role})
        |> Repo.insert()
        |> case do
          {:ok, user} -> issue_invite(user, role)
          {:error, changeset} -> {:error, changeset}
        end
    end
    |> tap(fn
      {:ok, user, _token} -> log_invite(user, invited_by)
      _ -> :ok
    end)
  end

  defp issue_invite(user, role) do
    {encoded_token, user_token} = UserToken.build_email_token(user, "invite")

    Ecto.Multi.new()
    |> Ecto.Multi.delete_all(:old, UserToken.by_user_and_contexts_query(user, ["invite"]))
    |> Ecto.Multi.update(:user, User.role_changeset(user, %{role: role}))
    |> Ecto.Multi.insert(:token, user_token)
    |> Repo.transaction()
    |> case do
      {:ok, %{user: user}} -> {:ok, user, encoded_token}
      {:error, _, changeset, _} -> {:error, changeset}
    end
  end

  defp log_invite(_user, nil), do: :ok

  defp log_invite(user, %User{} = invited_by) do
    Emothe.ActivityLog.log(%{
      user_id: invited_by.id,
      action: "invite",
      resource_type: "user",
      resource_id: user.id,
      metadata: %{"email" => user.email, "role" => to_string(user.role)}
    })

    :ok
  end

  @doc """
  Mails the invitation link.
  """
  def deliver_invite(%User{} = user, token, url_fun) when is_function(url_fun, 1) do
    Emothe.Accounts.UserNotifier.deliver_invite_instructions(user, url_fun.(token))
  end

  @doc """
  Returns the user for a valid, unexpired invite token, or nil.
  """
  def get_user_by_invite_token(token) when is_binary(token) do
    with {:ok, query} <- UserToken.verify_email_token_query(token, "invite"),
         %User{} = user <- Repo.one(query) do
      user
    else
      _ -> nil
    end
  end

  @doc """
  Changeset for the accept-invitation form.
  """
  def change_user_invite_acceptance(%User{} = user, attrs \\ %{}) do
    User.accept_invite_changeset(user, attrs, hash_password: false)
  end

  @doc """
  Sets the password, confirms the account and consumes the invite token.
  """
  def accept_invite(%User{} = user, attrs) do
    Ecto.Multi.new()
    |> Ecto.Multi.update(:user, User.accept_invite_changeset(user, attrs))
    |> Ecto.Multi.delete_all(:tokens, UserToken.by_user_and_contexts_query(user, ["invite"]))
    |> Repo.transaction()
    |> case do
      {:ok, %{user: user}} -> {:ok, user}
      {:error, :user, changeset, _} -> {:error, changeset}
    end
  end
```

`Emothe.ActivityLog.log/1` takes a single attrs map (`lib/emothe/activity_log.ex:15`), which is what `log_invite/2` passes.

- [x] **Step 7: Add the invite email**

In `lib/emothe/accounts/user_notifier.ex`:

```elixir
  @doc """
  Deliver an invitation to join EMOTHE.
  """
  def deliver_invite_instructions(user, url) do
    deliver(user.email, "You have been invited to EMOTHE", """

    ==============================

    Hi #{user.email},

    You have been invited to the EMOTHE platform. Set your password by
    visiting the URL below:

    #{url}

    This invitation expires in 7 days. If you were not expecting it, ignore
    this message.

    ==============================
    """)
  end
```

- [x] **Step 8: Run the Accounts tests to verify they pass**

```bash
mix test test/emothe/accounts_test.exs
```

Expected: PASS, 9 tests.

- [x] **Step 9: Write the failing accept-invite page test**

Create `test/emothe_web/live/user_accept_invite_live_test.exs`:

```elixir
defmodule EmotheWeb.UserAcceptInviteLiveTest do
  use EmotheWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import Emothe.TestFixtures

  alias Emothe.Accounts

  test "given a valid token then setting a password logs the user in", %{conn: conn} do
    {user, token} = invited_user_fixture()

    {:ok, lv, _html} = live(conn, ~p"/users/accept-invite/#{token}")

    form =
      form(lv, "#accept_invite_form", user: %{"password" => valid_user_password()})

    render_submit(form)
    conn = follow_trigger_action(form, conn)

    assert redirected_to(conn) == ~p"/"
    assert Accounts.active?(Emothe.Repo.reload!(user))
  end

  test "given an invalid token then an explanation and no form", %{conn: conn} do
    {:ok, _lv, html} = live(conn, ~p"/users/accept-invite/nonsense")

    assert html =~ "no longer valid"
    refute html =~ "accept_invite_form"
  end
end
```

- [x] **Step 10: Run it to verify it fails**

```bash
mix test test/emothe_web/live/user_accept_invite_live_test.exs
```

Expected: FAIL with a `Phoenix.Router.NoRouteError` for `/users/accept-invite/...`.

- [x] **Step 11: Build the accept-invite LiveView**

Create `lib/emothe_web/live/user_accept_invite_live.ex`:

```elixir
defmodule EmotheWeb.UserAcceptInviteLive do
  use EmotheWeb, :live_view

  alias Emothe.Accounts

  def render(%{user: nil} = assigns) do
    ~H"""
    <div class="mx-auto max-w-sm text-center">
      <.header>{gettext("This invitation is no longer valid")}</.header>
      <p class="mt-4 text-sm text-base-content/70">
        {gettext("Ask an administrator to send you a new one.")}
      </p>
    </div>
    """
  end

  def render(assigns) do
    ~H"""
    <div class="mx-auto max-w-sm">
      <.header class="text-center">
        {gettext("Welcome to EMOTHE")}
        <:subtitle>{gettext("Choose a password for %{email}", email: @user.email)}</:subtitle>
      </.header>

      <.simple_form
        for={@form}
        id="accept_invite_form"
        phx-submit="save"
        phx-change="validate"
        phx-trigger-action={@trigger_submit}
        action={~p"/users/log-in?_action=invited"}
        method="post"
      >
        <input type="hidden" name="user[email]" value={@user.email} />
        <.input
          field={@form[:password]}
          type="password"
          label={gettext("Password")}
          required
          autocomplete="new-password"
        />
        <:actions>
          <.button phx-disable-with={gettext("Saving...")} class="w-full">
            {gettext("Set password and sign in")}
          </.button>
        </:actions>
      </.simple_form>
    </div>
    """
  end

  def mount(%{"token" => token}, _session, socket) do
    case Accounts.get_user_by_invite_token(token) do
      nil ->
        {:ok, assign(socket, user: nil, form: nil, trigger_submit: false)}

      user ->
        changeset = Accounts.change_user_invite_acceptance(user)

        {:ok,
         socket
         |> assign(user: user, trigger_submit: false)
         |> assign_form(changeset)}
    end
  end

  def handle_event("validate", %{"user" => params}, socket) do
    changeset = Accounts.change_user_invite_acceptance(socket.assigns.user, params)
    {:noreply, assign_form(socket, Map.put(changeset, :action, :validate))}
  end

  def handle_event("save", %{"user" => params}, socket) do
    case Accounts.accept_invite(socket.assigns.user, params) do
      {:ok, user} ->
        changeset = Accounts.change_user_invite_acceptance(user)
        {:noreply, socket |> assign(trigger_submit: true) |> assign_form(changeset)}

      {:error, changeset} ->
        {:noreply, assign_form(socket, Map.put(changeset, :action, :insert))}
    end
  end

  defp assign_form(socket, changeset) do
    assign(socket, form: to_form(changeset, as: "user"))
  end
end
```

The form posts to `UserSessionController.create/2`, which is the single login path — that is deliberate, and it is what keeps MFA a one-place change later.

Add the route in `lib/emothe_web/router.ex`, inside the existing `live_session :redirect_if_user_is_authenticated` block:

```elixir
      live "/users/accept-invite/:token", UserAcceptInviteLive, :edit
```

Add a `create/2` clause in `lib/emothe_web/controllers/user_session_controller.ex`, next to the other `_action` clauses:

```elixir
  def create(conn, %{"_action" => "invited"} = params) do
    create(conn, params, gettext("Welcome to EMOTHE!"))
  end
```

- [x] **Step 12: Run the page test to verify it passes**

```bash
mix test test/emothe_web/live/user_accept_invite_live_test.exs
```

Expected: PASS, 2 tests.

- [x] **Step 13: Run the whole suite, extract translations, commit**

```bash
mix test
mix gettext.extract --merge
```

Open `priv/gettext/es/LC_MESSAGES/default.po`, translate the new invite strings, and check every entry marked `#, fuzzy` — the merge attaches new strings to unrelated existing translations.

```bash
mix format
mix compile --warnings-as-errors
git add -A
git commit -m "feat: invite users instead of letting them register

invite_user/3 creates a password-less row plus a 7-day token; accepting
sets the password and confirms in one transaction, because clicking the
emailed link already proves the mailbox. Re-inviting invalidates the
previous link."
```

---

## Task 3: Predefined admins (slice A1, part 2)

**Files:**
- Create: `lib/emothe/accounts/admin_bootstrap.ex`
- Create: `lib/mix/tasks/emothe.invite.ex`
- Create: `test/emothe/accounts/admin_bootstrap_test.exs`
- Modify: `config/runtime.exs` — read `ADMIN_EMAILS`
- Modify: `config/test.exs` — pin it empty
- Modify: `lib/emothe/application.ex:19-30` — add to the supervision tree
- Modify: `lib/emothe/release.ex` — `invite_url/1`
- Modify: `lib/emothe/accounts.ex` — `protected_admin?/1`

**Interfaces:**
- Consumes: `Accounts.invite_user/3`, `Accounts.deliver_invite/3`, `Accounts.reactivate_user/1`, `Accounts.active?/1` from Tasks 1-2.
- Produces:
  - `Emothe.Accounts.AdminBootstrap.reconcile(emails :: [String.t()]) :: :ok` — pure of config, so tests call it directly.
  - `Emothe.Accounts.AdminBootstrap.configured_emails() :: [String.t()]` — reads `:emothe, :admin_emails`, downcased and trimmed.
  - `Emothe.Accounts.protected_admin?(user :: %User{}) :: boolean` — true when the user's email is in `ADMIN_EMAILS`.
  - `Emothe.Release.invite_url(email :: String.t()) :: :ok` — prints the accept-invite URL.

- [x] **Step 1: Write the failing reconciler tests**

Create `test/emothe/accounts/admin_bootstrap_test.exs`:

```elixir
defmodule Emothe.Accounts.AdminBootstrapTest do
  use Emothe.DataCase, async: true

  import Emothe.TestFixtures

  alias Emothe.Accounts
  alias Emothe.Accounts.AdminBootstrap

  test "given an unknown email then an invited admin is created" do
    assert :ok = AdminBootstrap.reconcile(["jefa@uv.es"])

    user = Accounts.get_user_by_email("jefa@uv.es")
    assert user.role == :admin
    refute Accounts.active?(user)
  end

  test "given a researcher in the list then they are promoted" do
    user = user_fixture(email: "jefa@uv.es", role: :researcher)

    assert :ok = AdminBootstrap.reconcile(["jefa@uv.es"])
    assert Emothe.Repo.reload!(user).role == :admin
  end

  test "given a deactivated admin in the list then they are reactivated" do
    user = user_fixture(email: "jefa@uv.es", role: :admin)
    {:ok, _} = Accounts.deactivate_user(user)

    assert :ok = AdminBootstrap.reconcile(["jefa@uv.es"])
    assert Accounts.active?(Emothe.Repo.reload!(user))
  end

  test "given two runs then the second changes nothing" do
    :ok = AdminBootstrap.reconcile(["jefa@uv.es"])
    first = Accounts.get_user_by_email("jefa@uv.es")

    :ok = AdminBootstrap.reconcile(["jefa@uv.es"])
    second = Accounts.get_user_by_email("jefa@uv.es")

    assert first.id == second.id
    assert first.role == second.role
  end

  test "given an empty list then nothing happens" do
    assert :ok = AdminBootstrap.reconcile([])
    assert Emothe.Repo.aggregate(Emothe.Accounts.User, :count) == 0
  end

  test "given a configured email then it is a protected admin" do
    Application.put_env(:emothe, :admin_emails, ["Jefa@UV.es"])
    on_exit(fn -> Application.put_env(:emothe, :admin_emails, []) end)

    user = user_fixture(email: "jefa@uv.es", role: :admin)
    other = user_fixture(role: :admin)

    assert Accounts.protected_admin?(user)
    refute Accounts.protected_admin?(other)
  end
end
```

- [x] **Step 2: Run to verify it fails**

```bash
mix test test/emothe/accounts/admin_bootstrap_test.exs
```

Expected: FAIL with `module Emothe.Accounts.AdminBootstrap is not available`.

- [x] **Step 3: Write the reconciler**

Create `lib/emothe/accounts/admin_bootstrap.ex`:

```elixir
defmodule Emothe.Accounts.AdminBootstrap do
  @moduledoc """
  Reconciles the `ADMIN_EMAILS` configuration against the users table at boot.

  Config is the source of truth for who is an admin. Because these accounts
  cannot be demoted, deactivated or deleted through the UI, a compromised
  admin session cannot strip the co-admins or lock the owner out.

  Runs once at startup as a `Task`; a failure here must never stop the
  supervision tree, so every error is logged rather than raised.
  """

  require Logger

  alias Emothe.Accounts
  alias Emothe.Accounts.User

  def child_spec(_opts) do
    %{
      id: __MODULE__,
      start: {Task, :start_link, [&run/0]},
      restart: :transient
    }
  end

  def run do
    case configured_emails() do
      [] ->
        if Application.get_env(:emothe, :env) == :prod do
          Logger.error("ADMIN_EMAILS is not set — nobody can administer this instance")
        end

        :ok

      emails ->
        reconcile(emails)
    end
  end

  @doc """
  Returns the configured admin addresses, downcased and trimmed.
  """
  def configured_emails do
    :emothe
    |> Application.get_env(:admin_emails, [])
    |> Enum.map(&(&1 |> to_string() |> String.trim() |> String.downcase()))
    |> Enum.reject(&(&1 == ""))
  end

  @doc """
  Ensures every address in `emails` exists as an active-or-invited admin.
  """
  def reconcile(emails) when is_list(emails) do
    Enum.each(emails, &reconcile_one/1)
  end

  defp reconcile_one(email) do
    case Accounts.get_user_by_email(email) do
      nil -> invite_admin(email)
      %User{} = user -> repair_admin(user)
    end
  rescue
    error ->
      Logger.error("admin bootstrap failed for #{email}: #{Exception.message(error)}")
      :ok
  end

  defp invite_admin(email) do
    case Accounts.invite_user(email, :admin, nil) do
      {:ok, user, token} ->
        Accounts.deliver_invite(user, token, &invite_url/1)
        Logger.info("admin bootstrap: invited #{email}")

      {:error, reason} ->
        Logger.error("admin bootstrap: could not invite #{email}: #{inspect(reason)}")
    end

    :ok
  end

  defp repair_admin(user) do
    if user.role != :admin do
      {:ok, _} = Accounts.update_user_role(user, :admin)
      Logger.info("admin bootstrap: promoted #{user.email}")
    end

    if user.deactivated_at do
      {:ok, _} = Accounts.reactivate_user(user)
      Logger.info("admin bootstrap: reactivated #{user.email}")
    end

    :ok
  end

  @doc """
  Builds the accept-invite URL for a raw token.
  """
  def invite_url(token) do
    EmotheWeb.Endpoint.url() <> "/users/accept-invite/" <> token
  end
end
```

`update_user_role/2` already sets `confirmed_at` when promoting an unconfirmed user to admin (`lib/emothe/accounts.ex:412-421`). For a **bootstrap-invited** admin that is wrong — it would let them log in before proving the mailbox, except they have no password, so `valid_password?/2` still refuses. Leave the existing behaviour alone; note it and move on.

Add `protected_admin?/1` to `lib/emothe/accounts.ex`:

```elixir
  @doc """
  True when this user's email is listed in `ADMIN_EMAILS`.

  Protected admins cannot be demoted, deactivated or deleted from the UI.
  Enforce this here, not by hiding a button.
  """
  def protected_admin?(%User{email: email}) do
    String.downcase(email) in Emothe.Accounts.AdminBootstrap.configured_emails()
  end

  def protected_admin?(_), do: false
```

- [x] **Step 4: Run to verify it passes**

```bash
mix test test/emothe/accounts/admin_bootstrap_test.exs
```

Expected: PASS, 6 tests.

- [x] **Step 5: Wire the configuration**

In `config/runtime.exs`, after the `PHX_SERVER` block (around line 21):

```elixir
config :emothe,
  env: config_env(),
  admin_emails:
    System.get_env("ADMIN_EMAILS", "")
    |> String.split(",", trim: true)
    |> Enum.map(&String.trim/1)
```

In `config/test.exs`, pin it so a stray environment variable cannot alter test behaviour:

```elixir
config :emothe, admin_emails: []
```

In `lib/emothe/application.ex`, add the reconciler to `children` **after** `Emothe.Repo` and before `EmotheWeb.Endpoint`:

```elixir
      Emothe.Repo,
      Emothe.Accounts.AdminBootstrap,
```

- [x] **Step 6: Add the break-glass paths**

Create `lib/mix/tasks/emothe.invite.ex`:

```elixir
defmodule Mix.Tasks.Emothe.Invite do
  @shortdoc "Invites a user, optionally printing the link instead of mailing it"

  @moduledoc """
  Invites a user to EMOTHE.

      mix emothe.invite ana@uv.es
      mix emothe.invite ana@uv.es --admin
      mix emothe.invite ana@uv.es --admin --print-url

  `--print-url` writes the accept-invite link to stdout instead of sending
  mail. Use it on a fresh deployment where SMTP is not configured yet — the
  invitation that would let you configure the app cannot otherwise arrive.
  """

  use Mix.Task

  alias Emothe.Accounts
  alias Emothe.Accounts.AdminBootstrap

  @impl Mix.Task
  def run(args) do
    {opts, argv, _} =
      OptionParser.parse(args, strict: [admin: :boolean, print_url: :boolean])

    email =
      case argv do
        [email] -> email
        _ -> Mix.raise("usage: mix emothe.invite EMAIL [--admin] [--print-url]")
      end

    Mix.Task.run("app.start")

    role = if opts[:admin], do: :admin, else: :researcher

    case Accounts.invite_user(email, role, nil) do
      {:ok, user, token} ->
        if opts[:print_url] do
          Mix.shell().info(AdminBootstrap.invite_url(token))
        else
          Accounts.deliver_invite(user, token, &AdminBootstrap.invite_url/1)
          Mix.shell().info("invitation sent to #{email}")
        end

      {:error, :already_active} ->
        Mix.raise("#{email} already has an active account")

      {:error, reason} ->
        Mix.raise("could not invite #{email}: #{inspect(reason)}")
    end
  end
end
```

Add to `lib/emothe/release.ex`, so the same escape hatch works from `fly ssh console` where Mix is not available:

```elixir
  @doc """
  Prints an accept-invite URL for `email`, creating the invitation if needed.

  Break-glass for a deployment whose SMTP is not working yet.
  """
  def invite_url(email, role \\ :admin) do
    load_app()
    {:ok, _} = Application.ensure_all_started(:emothe)

    case Emothe.Accounts.invite_user(email, role, nil) do
      {:ok, _user, token} ->
        IO.puts(Emothe.Accounts.AdminBootstrap.invite_url(token))

      {:error, reason} ->
        IO.puts("could not invite #{email}: #{inspect(reason)}")
    end
  end
```

`load_app/0` is the existing private helper in that module (`lib/emothe/release.ex:23`), so the call above compiles as written.

- [x] **Step 7: Verify the break-glass path end to end**

```bash
mix emothe.invite bootstrap-test@example.com --admin --print-url
```

Expected: a single line like `http://localhost:4000/users/accept-invite/<token>`. Open it in a browser with `mix phx.server` running, set a password, and confirm you land logged in as an admin.

Then clean up:

```bash
mix run -e 'Emothe.Accounts.get_user_by_email("bootstrap-test@example.com") |> Emothe.Repo.delete!()'
```

- [x] **Step 8: Run the whole suite, format, commit**

```bash
mix test
mix format
mix compile --warnings-as-errors
git add -A
git commit -m "feat: predefine admins with ADMIN_EMAILS

Reconciled at boot: unknown addresses get an invited admin plus mail,
existing non-admins get promoted, deactivated ones get reactivated.
Those accounts are protected from UI demotion, so a compromised admin
session cannot strip its co-admins. mix emothe.invite --print-url is
the break-glass for a deployment whose SMTP is not up yet."
```

Add `ADMIN_EMAILS` to the Fly.io deployment checklist in `CLAUDE.md` under "High Priority" — an unset value in production means zero admins.

---

## Task 4: The Authz module (slice A2)

**Files:**
- Create: `lib/emothe/authz.ex`
- Create: `test/emothe/authz_test.exs`
- Modify: `lib/emothe_web/user_auth.ex` — `require_permission/2` plug, `{:ensure_can, action}` on_mount, `signed_in_path/2`
- Modify: `lib/emothe_web/router.ex:108-145` — pipeline and per-view permissions
- Modify: `lib/emothe_web/live/admin/user_list_live.ex`, `activity_log_live.ex`, `export_site_live.ex` — module-level `on_mount`
- Modify: `lib/emothe_web/components/layouts/app.html.heex:22,29,42` — replace `@current_user.role == :admin`

**Interfaces:**
- Consumes: `Accounts.active?/1` from Task 1.
- Produces:
  - `Emothe.Authz.can?(user :: %User{} | nil, action :: atom(), resource :: term() | nil) :: boolean`
  - `Emothe.Authz.actions() :: [atom()]`
  - `EmotheWeb.UserAuth.require_permission(conn, action :: atom()) :: Plug.Conn.t()` — a plug taking the action as its option.
  - `on_mount({:ensure_can, action})` for LiveViews.

- [x] **Step 1: Write the failing matrix test**

Create `test/emothe/authz_test.exs`:

```elixir
defmodule Emothe.AuthzTest do
  use Emothe.DataCase, async: true

  import Emothe.TestFixtures

  alias Emothe.Authz

  @researcher_actions ~w(view_admin manage_plays edit_content manage_editors
                         manage_sources import_tei download_export archive_play)a

  @admin_only_actions ~w(purge_play manage_users view_activity_log
                         deploy_site view_dashboard)a

  describe "an active researcher" do
    setup do: %{user: user_fixture(role: :researcher)}

    test "may do every content action", %{user: user} do
      for action <- @researcher_actions do
        assert Authz.can?(user, action), "expected researcher to be allowed #{action}"
      end
    end

    test "may do no admin-only action", %{user: user} do
      for action <- @admin_only_actions do
        refute Authz.can?(user, action), "expected researcher to be denied #{action}"
      end
    end
  end

  describe "an active admin" do
    setup do: %{user: admin_fixture()}

    test "may do everything", %{user: user} do
      for action <- @researcher_actions ++ @admin_only_actions do
        assert Authz.can?(user, action), "expected admin to be allowed #{action}"
      end
    end
  end

  describe "inactive accounts" do
    test "a deactivated admin may do nothing" do
      user = admin_fixture(deactivated_at: DateTime.utc_now(:second))

      for action <- Authz.actions() do
        refute Authz.can?(user, action), "expected deactivated admin to be denied #{action}"
      end
    end

    test "an unconfirmed admin may do nothing" do
      user = admin_fixture(confirmed_at: nil)

      for action <- Authz.actions() do
        refute Authz.can?(user, action)
      end
    end

    test "nil may do nothing" do
      for action <- Authz.actions() do
        refute Authz.can?(nil, action)
      end
    end
  end

  test "an unknown action is denied even for an admin" do
    refute Authz.can?(admin_fixture(), :launch_missiles)
  end
end
```

- [x] **Step 2: Run to verify it fails**

```bash
mix test test/emothe/authz_test.exs
```

Expected: FAIL with `module Emothe.Authz is not available`.

- [x] **Step 3: Write the module**

Create `lib/emothe/authz.ex`:

```elixir
defmodule Emothe.Authz do
  @moduledoc """
  The only place that answers "may this user do that?".

  Every route plug, LiveView mount hook and navigation item asks `can?/3`.
  Do not compare `user.role` anywhere else — a scattered role check is what
  produced an admin page (`/admin/users`) that no menu linked to, because the
  nav and the router had drifted apart.

  ## Extending to per-play scoping

  `can?/3` already receives the resource. To restrict researchers to plays
  they are assigned to, add a clause above the general researcher clause:

      def can?(%User{role: :researcher} = user, action, %Play{} = play)
          when action in @play_scoped_actions do
        active?(user) and assigned?(user, play)
      end

  plus a `play_assignments` join table and an assignment UI. No call site
  changes, because every caller already passes the resource it is acting on.
  """

  alias Emothe.Accounts
  alias Emothe.Accounts.User

  @researcher_actions ~w(view_admin manage_plays edit_content manage_editors
                         manage_sources import_tei download_export archive_play)a

  @admin_actions @researcher_actions ++
                   ~w(purge_play manage_users view_activity_log deploy_site
                      view_dashboard)a

  @doc """
  Every action this system knows about. Useful for exhaustive tests.
  """
  def actions, do: @admin_actions

  @doc """
  Returns true when `user` may perform `action`, optionally on `resource`.

  Inactive accounts — unconfirmed or deactivated — are denied everything.
  """
  def can?(user, action, resource \\ nil)

  def can?(%User{role: :admin} = user, action, _resource),
    do: Accounts.active?(user) and action in @admin_actions

  def can?(%User{role: :researcher} = user, action, _resource),
    do: Accounts.active?(user) and action in @researcher_actions

  def can?(_user, _action, _resource), do: false
end
```

- [x] **Step 4: Run to verify it passes**

```bash
mix test test/emothe/authz_test.exs
```

Expected: PASS, 7 tests.

- [x] **Step 5: Route everything through it**

In `lib/emothe_web/user_auth.ex`, add `alias Emothe.Authz` at the top, then replace `require_admin_user/2` (written in Task 1) with:

```elixir
  @doc """
  Plug requiring a named permission. Takes the action as its option:

      plug :require_permission, :view_admin
  """
  def require_permission(conn, action) do
    user = conn.assigns[:current_user]

    cond do
      is_nil(user) or not Accounts.active?(user) ->
        require_authenticated_user(conn, [])

      Authz.can?(user, action) ->
        conn

      true ->
        conn
        |> put_flash(:error, gettext("You do not have access to that page."))
        |> redirect(to: ~p"/")
        |> halt()
    end
  end
```

Add the LiveView equivalent next to the other `on_mount/4` clauses, and delete the `:ensure_admin` clause:

```elixir
  def on_mount({:ensure_can, action}, _params, session, socket) do
    socket = mount_current_user(socket, session)
    user = socket.assigns.current_user

    cond do
      not Accounts.active?(user) ->
        {:halt, redirect_to_login(socket)}

      Authz.can?(user, action) ->
        {:cont, socket}

      true ->
        socket =
          socket
          |> Phoenix.LiveView.put_flash(:error, gettext("You do not have access to that page."))
          |> Phoenix.LiveView.redirect(to: ~p"/")

        {:halt, socket}
    end
  end
```

Replace `signed_in_path/2` (lines 280-292) with:

```elixir
  defp signed_in_path(conn_or_socket, user \\ nil) do
    current_user =
      user ||
        conn_or_socket
        |> Map.get(:assigns, %{})
        |> Map.get(:current_user)

    if Authz.can?(current_user, :view_admin), do: ~p"/admin/plays", else: ~p"/"
  end
```

- [x] **Step 6: Update the router**

In `lib/emothe_web/router.ex`, replace the admin scope's pipeline and on_mount:

```elixir
  scope "/admin", EmotheWeb.Admin do
    pipe_through [:browser, :require_authenticated_user, {EmotheWeb.UserAuth, :require_permission, :view_admin}]

    live_session :admin,
      layout: {EmotheWeb.Layouts, :admin},
      on_mount: [
        EmotheWeb.SetLocaleHook,
        {EmotheWeb.UserAuth, {:ensure_can, :view_admin}}
      ] do
```

`pipe_through` does not take a plug with options, so instead define the pipeline above the scopes:

```elixir
  pipeline :require_admin_area do
    plug :require_permission, :view_admin
  end
```

and use `pipe_through [:browser, :require_authenticated_user, :require_admin_area]`. Delete the old `:require_admin_user` references.

For the LiveDashboard scope (lines 141-145), add a second pipeline and use it:

```elixir
  pipeline :require_dashboard do
    plug :require_permission, :view_dashboard
  end
```

Move `get "/export/download-zip", ExportController, :download_zip` (line 130) into its own scope gated on `:deploy_site`:

```elixir
  pipeline :require_deploy do
    plug :require_permission, :deploy_site
  end

  scope "/admin", EmotheWeb.Admin do
    pipe_through [:browser, :require_authenticated_user, :require_deploy]

    get "/export/download-zip", ExportController, :download_zip
  end
```

- [x] **Step 7: Gate the three admin-only LiveViews**

Rather than splitting `live_session :admin` — which would force a full page reload when navigating between sidebar sections — declare the stricter requirement in the module itself. It runs after the `live_session` hooks, with `current_user` already assigned.

At the top of `lib/emothe_web/live/admin/user_list_live.ex`:

```elixir
  on_mount {EmotheWeb.UserAuth, {:ensure_can, :manage_users}}
```

In `lib/emothe_web/live/admin/activity_log_live.ex`:

```elixir
  on_mount {EmotheWeb.UserAuth, {:ensure_can, :view_activity_log}}
```

In `lib/emothe_web/live/admin/export_site_live.ex`:

```elixir
  on_mount {EmotheWeb.UserAuth, {:ensure_can, :deploy_site}}
```

- [x] **Step 8: Replace the inline role checks in the public layout**

In `lib/emothe_web/components/layouts/app.html.heex`, three `@current_user.role == :admin` tests appear at lines 22, 29 and 42. Replace each condition with:

```heex
<%= if Emothe.Authz.can?(assigns[:current_user], :view_admin) do %>
```

Then confirm none are left anywhere:

```bash
grep -rn "role == :admin\|Accounts.admin?" lib/ --include="*.ex" --include="*.heex"
```

Expected: only `lib/emothe/accounts.ex` (the `admin?/1` definition itself) and `lib/emothe/accounts/admin_bootstrap.ex`. Any hit inside `lib/emothe_web/` is a leak — route it through `Authz`.

- [x] **Step 9: Add a researcher access test**

Append to `test/emothe_web/user_auth_test.exs`:

```elixir
  describe "researcher access" do
    test "given a researcher then the admin play list is reachable", %{conn: conn} do
      conn =
        conn
        |> log_in_user(Emothe.TestFixtures.user_fixture(role: :researcher))
        |> get(~p"/admin/plays")

      assert html_response(conn, 200)
    end

    test "given a researcher then user management is refused", %{conn: conn} do
      conn =
        conn
        |> log_in_user(Emothe.TestFixtures.user_fixture(role: :researcher))
        |> get(~p"/admin/users")

      assert redirected_to(conn) == ~p"/"
    end
  end
```

- [x] **Step 10: Run everything**

```bash
mix test
```

Expected: PASS, including the two new researcher tests.

- [x] **Step 11: Format, compile, commit**

```bash
mix format
mix compile --warnings-as-errors
git add -A
git commit -m "feat: centralise authorization in Emothe.Authz

One can?/3 answers every access question, so the router and the nav can
no longer disagree — which is how /admin/users ended up unreachable.
Researchers gain content access, which is only safe now that Task 1
closed public registration. can?/3 already takes the resource, so
per-play scoping is a new clause, not a rewrite."
```

---

## Task 5: Visible, revocable sessions (slice B1)

**Files:**
- Create: `priv/repo/migrations/<generated>_add_device_info_to_users_tokens.exs`
- Modify: `lib/emothe/accounts/user_token.ex` — `build_session_token/2`, 30-day validity
- Modify: `lib/emothe/accounts.ex` — session listing and revocation
- Modify: `lib/emothe_web/user_auth.ex:17,32-41` — pass device info, 30-day cookie
- Modify: `lib/emothe_web/controllers/user_session_controller.ex` — per-email throttle
- Modify: `lib/emothe_web/live/user_settings_live.ex` — active sessions panel
- Modify: `test/emothe/accounts_test.exs` — session tests

**Interfaces:**
- Consumes: `Accounts.active?/1`, `user_fixture/1`, `log_in_user/2` from Task 1.
- Produces:
  - `Emothe.Accounts.generate_user_session_token(user, device_info :: map()) :: binary()` — `device_info` accepts `:ip_address` and `:user_agent`; the one-argument form still works.
  - `Emothe.Accounts.list_user_sessions(user) :: [%UserToken{}]` — newest first.
  - `Emothe.Accounts.delete_user_session(user, token_id :: String.t()) :: :ok` — disconnects that session's LiveViews.
  - `Emothe.Accounts.delete_other_user_sessions(user, current_token :: binary()) :: :ok`
  - `Emothe.Accounts.force_logout(user) :: :ok` — used by Task 8.

- [x] **Step 1: Generate and run the migration**

```bash
mix ecto.gen.migration add_device_info_to_users_tokens
```

```elixir
defmodule Emothe.Repo.Migrations.AddDeviceInfoToUsersTokens do
  use Ecto.Migration

  def change do
    alter table(:users_tokens) do
      add :ip_address, :string
      add :user_agent, :string
    end
  end
end
```

```bash
mix ecto.migrate && MIX_ENV=test mix ecto.migrate
```

- [x] **Step 2: Write the failing session tests**

Append to `test/emothe/accounts_test.exs`:

```elixir
  describe "sessions" do
    test "given a login with device info then it is stored and listable" do
      user = user_fixture()

      Accounts.generate_user_session_token(user, %{
        ip_address: "10.0.0.7",
        user_agent: "Firefox/141"
      })

      assert [session] = Accounts.list_user_sessions(user)
      assert session.ip_address == "10.0.0.7"
      assert session.user_agent == "Firefox/141"
    end

    test "given several sessions then deleting one leaves the others" do
      user = user_fixture()
      Accounts.generate_user_session_token(user)
      Accounts.generate_user_session_token(user)

      [first | _] = Accounts.list_user_sessions(user)
      assert :ok = Accounts.delete_user_session(user, first.id)

      assert length(Accounts.list_user_sessions(user)) == 1
    end

    test "given several sessions then delete_other_user_sessions keeps only the current one" do
      user = user_fixture()
      current = Accounts.generate_user_session_token(user)
      Accounts.generate_user_session_token(user)
      Accounts.generate_user_session_token(user)

      assert :ok = Accounts.delete_other_user_sessions(user, current)

      assert [remaining] = Accounts.list_user_sessions(user)
      assert remaining.token == current
    end

    test "given force_logout then every session is gone" do
      user = user_fixture()
      Accounts.generate_user_session_token(user)
      Accounts.generate_user_session_token(user)

      assert :ok = Accounts.force_logout(user)
      assert Accounts.list_user_sessions(user) == []
    end

    test "given another user's token id then deleting it is refused" do
      mine = user_fixture()
      theirs = user_fixture()
      Accounts.generate_user_session_token(theirs)
      [their_session] = Accounts.list_user_sessions(theirs)

      assert :ok = Accounts.delete_user_session(mine, their_session.id)
      assert length(Accounts.list_user_sessions(theirs)) == 1
    end
  end
```

The last test matters: the settings UI passes a token id from the browser, so the query must be scoped by `user_id` or one user can end another's session.

- [x] **Step 3: Run to verify it fails**

```bash
mix test test/emothe/accounts_test.exs
```

Expected: FAIL with `function Emothe.Accounts.list_user_sessions/1 is undefined`.

- [x] **Step 4: Extend the token schema**

In `lib/emothe/accounts/user_token.ex`, add the fields to the schema:

```elixir
    field :ip_address, :string
    field :user_agent, :string
```

change the session validity:

```elixir
  @session_validity_in_days 30
```

and replace `build_session_token/1`:

```elixir
  @doc """
  Builds a session token, recording where it was issued.

  `device_info` may carry `:ip_address` and `:user_agent`. They exist so the
  "active sessions" list is legible — a bare timestamp tells nobody which row
  is theirs. They are not identity: both change constantly and neither may
  ever be treated as an authentication factor.
  """
  def build_session_token(user, device_info \\ %{}) do
    token = :crypto.strong_rand_bytes(@rand_size)

    {token,
     %Emothe.Accounts.UserToken{
       token: token,
       context: "session",
       user_id: user.id,
       ip_address: Map.get(device_info, :ip_address),
       user_agent: device_info |> Map.get(:user_agent) |> truncate(255)
     }}
  end

  defp truncate(nil, _length), do: nil
  defp truncate(string, length), do: String.slice(string, 0, length)
```

- [x] **Step 5: Add the Accounts functions**

In `lib/emothe/accounts.ex`, replace `generate_user_session_token/1` and add the rest:

```elixir
  @doc """
  Generates a session token, optionally recording the issuing device.
  """
  def generate_user_session_token(user, device_info \\ %{}) do
    {token, user_token} = UserToken.build_session_token(user, device_info)
    Repo.insert!(user_token)
    token
  end

  @doc """
  Lists the user's session tokens, newest first.
  """
  def list_user_sessions(%User{} = user) do
    from(t in UserToken,
      where: t.user_id == ^user.id and t.context == "session",
      order_by: [desc: t.inserted_at]
    )
    |> Repo.all()
  end

  @doc """
  Deletes one of the user's own sessions by token id.

  Scoped by `user_id`: the id arrives from the browser, so an unscoped query
  would let one user end another's session.
  """
  def delete_user_session(%User{} = user, token_id) do
    from(t in UserToken,
      where: t.user_id == ^user.id and t.context == "session" and t.id == ^token_id
    )
    |> Repo.all()
    |> disconnect_and_delete()
  end

  @doc """
  Deletes every session except the one identified by `current_token`.
  """
  def delete_other_user_sessions(%User{} = user, current_token) do
    from(t in UserToken,
      where: t.user_id == ^user.id and t.context == "session" and t.token != ^current_token
    )
    |> Repo.all()
    |> disconnect_and_delete()
  end

  @doc """
  Deletes every session the user holds. Used by admins to evict someone.
  """
  def force_logout(%User{} = user) do
    from(t in UserToken, where: t.user_id == ^user.id and t.context == "session")
    |> Repo.all()
    |> disconnect_and_delete()
  end

  defp disconnect_and_delete(tokens) do
    Enum.each(tokens, fn token ->
      EmotheWeb.Endpoint.broadcast(
        "users_sessions:#{Base.url_encode64(token.token)}",
        "disconnect",
        %{}
      )

      Repo.delete!(token)
    end)

    :ok
  end
```

The broadcast topic must match the `live_socket_id` written in `put_token_in_session/2` (`lib/emothe_web/user_auth.ex:271`), so open LiveViews drop at once instead of on their next navigation.

Note that `deactivate_user/1` from Task 1 uses `Ecto.Multi.delete_all`, which does not broadcast. Change its `:tokens` step to run `disconnect_and_delete/1` after the transaction:

```elixir
  def deactivate_user(%User{} = user) do
    tokens = Repo.all(UserToken.by_user_and_contexts_query(user, :all))

    changeset = Ecto.Changeset.change(user, deactivated_at: DateTime.utc_now(:second))

    case Repo.update(changeset) do
      {:ok, user} ->
        disconnect_and_delete(tokens)
        {:ok, user}

      {:error, changeset} ->
        {:error, changeset}
    end
  end
```

- [x] **Step 6: Record device info at login and shorten the cookie**

In `lib/emothe_web/user_auth.ex`, change the cookie age (line 17):

```elixir
  # Keep in step with @session_validity_in_days in UserToken.
  @max_age 60 * 60 * 24 * 30
```

and replace `log_in_user/3`'s first line:

```elixir
  def log_in_user(conn, user, params \\ %{}) do
    token = Accounts.generate_user_session_token(user, device_info(conn))
    user_return_to = get_session(conn, :user_return_to)

    conn
    |> renew_session()
    |> put_token_in_session(token)
    |> maybe_write_remember_me_cookie(token, params)
    |> redirect(to: user_return_to || signed_in_path(conn, user))
  end

  defp device_info(conn) do
    %{
      ip_address: conn.remote_ip |> :inet.ntoa() |> to_string(),
      user_agent: conn |> get_req_header("user-agent") |> List.first()
    }
  end
```

- [x] **Step 7: Add the per-email login throttle**

In `lib/emothe_web/controllers/user_session_controller.ex`, replace the private `create/3`:

```elixir
  defp create(conn, %{"user" => user_params}, info) do
    %{"email" => email, "password" => password} = user_params
    ip = conn.remote_ip |> :inet.ntoa() |> to_string()
    email_key = "login-email:#{String.downcase(email)}"

    # Two keys: a broad per-IP cap against bots, and a narrow per-email cap
    # against guessing one known account. Deliberately a rate limit rather
    # than an account lock — a lock would let a stranger shut a named admin
    # out of their own site.
    with :ok <- EmotheWeb.RateLimit.check_rate("login:#{ip}", 20, 60_000),
         :ok <- EmotheWeb.RateLimit.check_rate(email_key, 10, 900_000) do
      if user = Accounts.get_user_by_email_and_password(email, password) do
        EmotheWeb.RateLimit.reset(email_key)

        conn
        |> put_flash(:info, info)
        |> UserAuth.log_in_user(user, user_params)
      else
        # Don't disclose whether the email is registered.
        conn
        |> put_flash(:error, gettext("Invalid email or password"))
        |> put_flash(:email, String.slice(email, 0, 160))
        |> redirect(to: ~p"/users/log-in")
      end
    else
      {:error, :rate_limited} ->
        conn
        |> put_flash(
          :error,
          gettext("Too many login attempts. Please wait a few minutes and try again.")
        )
        |> redirect(to: ~p"/users/log-in")
    end
  end
```

`check_rate/3` counts every call, so a successful login must clear the email counter or a legitimate user hits the cap after ten sessions. Add to `lib/emothe_web/rate_limit.ex`:

```elixir
  @doc """
  Clears the counter for `key`. Called after a successful login so only
  failures consume the budget.
  """
  @spec reset(String.t()) :: :ok
  def reset(key) do
    :ets.delete(@table, key)
    :ok
  end
```

- [x] **Step 8: Add the active sessions panel**

In `lib/emothe_web/live/user_settings_live.ex`, append to the `render/1` template inside the outermost `<div class="space-y-12 divide-y">`:

```heex
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
```

The LiveView needs the raw session token to mark the current row. It is in the session, so read it in `mount/3`. Change the router entry for `/users/settings` to a `live_session` that passes it through — it already does, via `session["user_token"]`, so in `mount/3` add:

```elixir
  def mount(_params, session, socket) do
    # ... keep the existing assigns ...
    socket =
      socket
      |> assign(:current_token, session["user_token"])
      |> assign_sessions()

    {:ok, socket}
  end

  defp assign_sessions(socket) do
    assign(socket, :sessions, Accounts.list_user_sessions(socket.assigns.current_user))
  end
```

The existing `mount/3` at line 94 takes `_session`; give it the name `session` and thread the two lines above into the socket it already builds. The `mount(%{"token" => token}, ...)` clause at line 81 handles email-change confirmation and redirects, so it needs no session panel.

Add the handlers:

```elixir
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
```

- [x] **Step 9: Run the tests**

```bash
mix test test/emothe/accounts_test.exs
mix test
```

Expected: PASS.

- [x] **Step 10: Verify the panel by hand**

Start the server, log in from two different browsers, open `/users/settings` in the first, confirm two rows with distinct user agents and one marked "This device". Click "Sign out everywhere else" and confirm the second browser is dropped on its next interaction.

- [x] **Step 11: Extract translations, format, commit**

```bash
mix gettext.extract --merge
```

Translate the new session strings; check every `#, fuzzy` entry.

```bash
mix format
mix compile --warnings-as-errors
git add -A
git commit -m "feat: list and revoke active sessions

Sessions record IP and user agent so the list is legible, and both the
DB token and the remember-me cookie drop from 60 days to 30. Revocation
broadcasts on live_socket_id, so open LiveViews disconnect at once.
Login throttling gains a per-email key; only failures consume it."
```

---

## Task 6: Shell mockup for visual approval (slice C1, part 1)

**This task ends at a human approval gate. Do not proceed to Task 7 until the shell has been looked at and approved.**

The real layout is not touched here. This task builds the two components and a throwaway preview route, so the shell can be judged in a browser — real Tailwind, real DaisyUI, real theme toggle — before any live page depends on it.

The repo already has the harness for exactly this: `/demo/ui` is dev-only, has its own `demo_root` layout, and renders static HEEx against fake data from `EmotheWeb.Demo.UIDemoData` (`lib/emothe_web/controllers/demo_ui_controller.ex`, `lib/emothe_web/router.ex:155-164`). Extend it rather than inventing a second preview mechanism.

The components built here are the real ones and survive into Task 7. Only the preview route and template are thrown away.

**Files:**
- Modify: `lib/emothe_web/components/layouts.ex` — `user_menu/1`, `admin_sidebar/1`
- Create: `lib/emothe_web/controllers/demo_ui_html/admin_shell.html.heex`
- Modify: `lib/emothe_web/controllers/demo_ui_controller.ex` — `admin_shell/2`
- Modify: `lib/emothe_web/router.ex:155-164` — preview route
- Modify: `lib/emothe_web/controllers/demo_ui_html/index.html.heex` — link to it

**Interfaces:**
- Consumes: `Emothe.Authz.can?/3` from Task 4.
- Produces: `EmotheWeb.Layouts.user_menu/1` (attrs: `current_user`, `locale`) and `EmotheWeb.Layouts.admin_sidebar/1` (attrs: `current_user`, `current_path`). Task 7 consumes both.

- [x] **Step 1: Extract the shared user menu**

The identity dropdown, locale toggle and theme toggle are duplicated across both layouts and have already drifted. In `lib/emothe_web/components/layouts.ex`, add:

```elixir
  @doc """
  Identity dropdown, locale toggle and theme toggle.

  Shared by both layouts — this markup existed twice and drifted apart.
  """
  attr :current_user, :map, default: nil
  attr :locale, :string, default: "es"

  def user_menu(assigns) do
    ~H"""
    <div class="flex-none flex items-center gap-2">
      <.locale_toggle locale={@locale} />
      <.theme_toggle />
      <div :if={@current_user} class="dropdown dropdown-end">
        <label tabindex="0" class="btn btn-ghost btn-xs gap-1">
          <.icon name="hero-user-circle-micro" class="size-4" />
          <span class="max-w-[8rem] truncate text-xs">{@current_user.email}</span>
          <.icon name="hero-chevron-down-micro" class="size-3" />
        </label>
        <ul
          tabindex="0"
          class="dropdown-content z-[1] menu p-1 shadow-lg bg-base-100 rounded-box w-48 border border-base-300"
        >
          <li><.link navigate={~p"/users/settings"}>{gettext("Settings")}</.link></li>
          <li><.link href={~p"/users/log-out"} method="delete">{gettext("Log out")}</.link></li>
        </ul>
      </div>
      <.link :if={!@current_user} navigate={~p"/users/log-in"} class="btn btn-ghost btn-xs">
        {gettext("Log in")}
      </.link>
    </div>
    """
  end
```

- [x] **Step 2: Build the sidebar**

Add to `lib/emothe_web/components/layouts.ex`:

```elixir
  @doc """
  Admin sidebar.

  Entries are filtered through `Emothe.Authz.can?/3`, the same predicate that
  guards the routes — so the menu cannot offer a page the user will be bounced
  from, and cannot hide one they are entitled to.
  """
  attr :current_user, :map, default: nil
  attr :current_path, :string, default: ""

  def admin_sidebar(assigns) do
    assigns = assign(assigns, :groups, sidebar_groups(assigns.current_user))

    ~H"""
    <aside class="w-56 shrink-0 border-r border-base-300 bg-base-200/40 min-h-full">
      <nav class="p-3 space-y-4">
        <div :for={{label, items} <- @groups}>
          <p class="px-2 pb-1 text-[0.65rem] font-semibold uppercase tracking-wider text-base-content/40">
            {label}
          </p>
          <ul class="menu menu-sm gap-0.5 p-0">
            <li :for={item <- items}>
              <.link
                navigate={item.to}
                class={if String.starts_with?(@current_path, item.to), do: "active", else: ""}
              >
                <.icon name={item.icon} class="size-4" />
                {item.label}
              </.link>
            </li>
          </ul>
        </div>

        <div class="border-t border-base-300 pt-3">
          <ul class="menu menu-sm p-0">
            <li>
              <.link navigate={~p"/plays"}>
                <.icon name="hero-arrow-top-right-on-square-micro" class="size-4" />
                {gettext("View public site")}
              </.link>
            </li>
          </ul>
        </div>
      </nav>
    </aside>
    """
  end

  defp sidebar_groups(user) do
    [
      {gettext("Content"),
       [
         %{label: gettext("Plays"), to: "/admin/plays", icon: "hero-book-open-micro",
           action: :manage_plays},
         %{label: gettext("Import"), to: "/admin/plays/import", icon: "hero-arrow-down-tray-micro",
           action: :import_tei}
       ]},
      {gettext("Site"),
       [
         %{label: gettext("Export"), to: "/admin/export", icon: "hero-globe-alt-micro",
           action: :deploy_site},
         %{label: gettext("Activity"), to: "/admin/activity-log", icon: "hero-clock-micro",
           action: :view_activity_log}
       ]},
      {gettext("System"),
       [
         %{label: gettext("Users"), to: "/admin/users", icon: "hero-users-micro",
           action: :manage_users},
         %{label: gettext("Dashboard"), to: "/admin/dashboard", icon: "hero-chart-bar-micro",
           action: :view_dashboard}
       ]}
    ]
    |> Enum.map(fn {label, items} ->
      {label, Enum.filter(items, &Emothe.Authz.can?(user, &1.action))}
    end)
    |> Enum.reject(fn {_label, items} -> items == [] end)
  end
```

`/admin/plays/import` starts with `/admin/plays`, so the naive `String.starts_with?` marks both entries active on the import page. Order the check so the longest matching path wins — replace the `class=` expression with a call to a helper:

```elixir
  defp sidebar_active?(current_path, to, groups) do
    longest =
      groups
      |> Enum.flat_map(fn {_label, items} -> items end)
      |> Enum.map(& &1.to)
      |> Enum.filter(&String.starts_with?(current_path, &1))
      |> Enum.max_by(&String.length/1, fn -> nil end)

    longest == to
  end
```

and use `class={if sidebar_active?(@current_path, item.to, @groups), do: "active", else: ""}`.

- [x] **Step 3: Build the preview page**

Create `lib/emothe_web/controllers/demo_ui_html/admin_shell.html.heex`. It renders the whole chrome twice — once as an admin, once as a researcher — so the role filtering is visible side by side rather than requiring two logins. Fake users are plain structs; `Authz.can?/3` reads `role`, `confirmed_at` and `deactivated_at` off the struct and never touches the database.

```heex
<div class="p-6 space-y-10">
  <div>
    <h1 class="text-xl font-bold">{gettext("Admin shell preview")}</h1>
    <p class="text-sm text-base-content/60">
      Static mockup. Nothing here is wired up — judge the layout, spacing and
      role filtering, then approve or send it back.
    </p>
  </div>

  <section :for={{label, user, path} <- @variants} class="space-y-2">
    <h2 class="text-sm font-semibold uppercase tracking-wide text-base-content/50">
      {label}
    </h2>

    <div class="border border-base-300 rounded-box overflow-hidden h-[32rem]">
      <div class="drawer lg:drawer-open h-full">
        <input id={"preview-drawer-#{user.role}"} type="checkbox" class="drawer-toggle" />

        <div class="drawer-content flex flex-col">
          <header class="navbar bg-base-100 border-b border-base-300 px-4 min-h-0 py-2">
            <div class="flex-1 gap-3">
              <label
                for={"preview-drawer-#{user.role}"}
                class="btn btn-ghost btn-xs btn-square lg:hidden"
              >
                <.icon name="hero-bars-3-micro" class="size-4" />
              </label>
              <span class="flex items-center gap-2">
                <img src={~p"/images/logo.svg"} width="28" />
                <span class="text-sm font-bold tracking-tight">EMOTHE</span>
              </span>
            </div>
            <.user_menu current_user={user} locale="es" />
          </header>

          <.play_context_bar play={@play} active_tab={:content} />

          <main class="flex-1 p-6 bg-base-100">
            <div class="skeleton h-8 w-1/3 mb-4"></div>
            <div class="skeleton h-4 w-full mb-2"></div>
            <div class="skeleton h-4 w-5/6 mb-2"></div>
            <div class="skeleton h-4 w-2/3"></div>
          </main>
        </div>

        <div class="drawer-side">
          <label for={"preview-drawer-#{user.role}"} class="drawer-overlay"></label>
          <.admin_sidebar current_user={user} current_path={path} />
        </div>
      </div>
    </div>
  </section>
</div>
```

Add the action to `lib/emothe_web/controllers/demo_ui_controller.ex`, following the shape of the existing ones:

```elixir
  def admin_shell(conn, _params) do
    now = DateTime.utc_now(:second)

    admin = %Emothe.Accounts.User{
      email: "ana@uv.es",
      role: :admin,
      confirmed_at: now
    }

    researcher = %Emothe.Accounts.User{
      email: "investigador@uv.es",
      role: :researcher,
      confirmed_at: now
    }

    conn
    |> put_layout(html: {EmotheWeb.Layouts, :demo_root})
    |> render(:admin_shell,
      page_title: "Admin Shell (Demo)",
      play: UIDemoData.play(),
      variants: [
        {"Admin — on /admin/plays/import", admin, "/admin/plays/import"},
        {"Researcher — on /admin/plays", researcher, "/admin/plays"}
      ]
    )
  end
```

`put_layout(html: {EmotheWeb.Layouts, :demo_root})` is deliberate: the preview must not render inside the layout it is previewing.

Add the route inside the existing dev-only demo scope in `lib/emothe_web/router.ex`:

```elixir
      get "/admin/shell", DemoUIController, :admin_shell
```

Add a link to it in `lib/emothe_web/controllers/demo_ui_html/index.html.heex`, matching how the other demo pages are listed there.

- [x] **Step 4: Look at it, and stop**

```bash
mix phx.server
```

Open `http://localhost:4000/demo/ui/admin/shell` and check:

- The admin panel shows all three groups: Content (Plays, Import), Site (Export, Activity), System (Users, Dashboard).
- The researcher panel shows Content only — no Site, no System. Both groups are dropped entirely, not rendered empty.
- In the admin panel, **Import** is marked active and **Plays** is not, even though `/admin/plays/import` starts with `/admin/plays`. If both light up, `sidebar_active?/3` is not wired in.
- Two strips of chrome above the content area, not four.
- The theme toggle in the top bar flips light and dark, and the sidebar is readable in both.
- Narrowing the browser below `lg` collapses the sidebar behind the hamburger.

**Then stop and show the user.** This is the approval gate the whole task exists for. Do not start Task 7 until they have said the shell is right. If they want changes, change the components here and look again — the real layout is still untouched, so iterating costs nothing.

- [x] **Step 5: Commit the components and the preview**

```bash
mix format
mix compile --warnings-as-errors
mix test
git add -A
git commit -m "feat: add admin sidebar components behind a demo preview

Builds user_menu/1 and admin_sidebar/1 plus a dev-only preview at
/demo/ui/admin/shell showing both roles side by side. The real layout
is untouched, so the shell can be judged before anything depends on it."
```

---

## Task 7: Adopt the shell (slice C1, part 2)

Only start this once Task 6's preview has been approved.

Swapping the layout is one line in the router plus one template. LiveViews render into `{@inner_content}` and know nothing about the chrome, so if the result is wrong, reverting this commit reverts the whole change.

**Files:**
- Modify: `lib/emothe_web/components/layouts/admin.html.heex` — full rewrite
- Modify: `lib/emothe_web/components/layouts/app.html.heex` — use the shared menu
- Create: `lib/emothe_web/live/current_path_hook.ex`
- Modify: `lib/emothe_web/router.ex` — add the hook to `live_session :admin`
- Delete: `lib/emothe_web/controllers/demo_ui_html/admin_shell.html.heex` and its route

**Interfaces:**
- Consumes: `EmotheWeb.Layouts.user_menu/1` and `EmotheWeb.Layouts.admin_sidebar/1` from Task 6.
- Produces: `EmotheWeb.CurrentPathHook.on_mount/4` — assigns `:current_path` for sidebar highlighting.

- [x] **Step 1: Rewrite the admin layout**

Replace `lib/emothe_web/components/layouts/admin.html.heex` entirely:

```heex
<div class="drawer lg:drawer-open min-h-screen">
  <input id="admin-drawer" type="checkbox" class="drawer-toggle" />

  <div class="drawer-content flex flex-col">
    <header class="navbar bg-base-100 border-b border-base-300 px-4 min-h-0 py-2 sticky top-0 z-30">
      <div class="flex-1 gap-3">
        <label for="admin-drawer" class="btn btn-ghost btn-xs btn-square lg:hidden">
          <.icon name="hero-bars-3-micro" class="size-4" />
        </label>
        <.link navigate={~p"/"} class="flex items-center gap-2 hover:opacity-80 transition-opacity">
          <img src={~p"/images/logo.svg"} width="28" />
          <span class="text-sm font-bold tracking-tight">EMOTHE</span>
        </.link>
      </div>
      <.user_menu current_user={assigns[:current_user]} locale={assigns[:locale] || "es"} />
    </header>

    <%= if assigns[:play_context] do %>
      <.play_context_bar play={@play_context.play} active_tab={@play_context.active_tab} />
    <% end %>

    <main class="flex-1">
      {@inner_content}
    </main>
  </div>

  <div class="drawer-side z-40">
    <label for="admin-drawer" aria-label="close sidebar" class="drawer-overlay"></label>
    <.admin_sidebar
      current_user={assigns[:current_user]}
      current_path={assigns[:current_path] || ""}
    />
  </div>
</div>

<.flash_group flash={@flash} />
```

Breadcrumbs are gone. The `:breadcrumbs` assigns in the LiveViews stay for now — dead but harmless — and Task 9 sweeps them.

`@current_path` needs to reach the layout. Add an `on_mount` hook that tracks it, in `lib/emothe_web/live/set_locale_hook.ex`'s neighbourhood — create `lib/emothe_web/live/current_path_hook.ex`:

```elixir
defmodule EmotheWeb.CurrentPathHook do
  @moduledoc """
  Assigns `:current_path` so the admin sidebar can mark the active entry.
  """
  import Phoenix.Component
  import Phoenix.LiveView

  def on_mount(:default, _params, _session, socket) do
    {:cont,
     attach_hook(socket, :current_path, :handle_params, fn _params, uri, socket ->
       {:cont, assign(socket, :current_path, URI.parse(uri).path)}
     end)}
  end
end
```

and add it to the `live_session :admin` `on_mount` list in `lib/emothe_web/router.ex`:

```elixir
      on_mount: [
        EmotheWeb.SetLocaleHook,
        EmotheWeb.CurrentPathHook,
        {EmotheWeb.UserAuth, {:ensure_can, :view_admin}}
      ] do
```

- [x] **Step 2: Trim the public layout**

In `lib/emothe_web/components/layouts/app.html.heex`, delete the three admin-link blocks (the mobile dropdown entries, the desktop nav entries and the dashboard icon) and the whole trailing identity/locale/theme `<div class="flex-none ...">`. Replace the nav with a single admin entry and the shared menu:

```heex
    <nav class="hidden sm:flex items-center gap-1">
      <.link navigate={~p"/plays"} class="btn btn-ghost btn-xs">{gettext("Catalogue")}</.link>
      <.link
        :if={Emothe.Authz.can?(assigns[:current_user], :view_admin)}
        navigate={~p"/admin/plays"}
        class="btn btn-ghost btn-xs"
      >
        {gettext("Admin")}
      </.link>
    </nav>
```

and at the end of the header:

```heex
  <.user_menu current_user={assigns[:current_user]} locale={assigns[:locale] || "es"} />
```

Do the same inside the mobile hamburger dropdown: `Catalogue`, plus `Admin` behind the same `Authz` guard.

- [x] **Step 3: Verify against the real application**

The preview proved the markup. This proves the wiring.

```bash
mix phx.server
```

As an admin, on real pages this time: the sidebar shows all three groups; `/admin/plays/import` marks **Import** active and not Plays; navigating between sections does **not** cause a full page reload (they share one `live_session`); a play page shows exactly two strips.

Then log in as a researcher — `mix emothe.invite you+res@example.com --print-url`, open the link, set a password — and confirm the System group is absent and `/admin/users` typed directly redirects to `/` with a flash.

- [x] **Step 4: Delete the preview**

It has done its job, and a mockup left in the tree drifts from the thing it mocked.

```bash
git rm lib/emothe_web/controllers/demo_ui_html/admin_shell.html.heex
```

Remove `admin_shell/2` from `lib/emothe_web/controllers/demo_ui_controller.ex`, the `get "/admin/shell"` route from `lib/emothe_web/router.ex`, and the link from `lib/emothe_web/controllers/demo_ui_html/index.html.heex`.

The other `/demo/ui/admin/*` pages stay — they call `with_admin_layout()`, so they now render inside the new shell and keep working as the ongoing visual harness.

- [x] **Step 5: Run the suite**

```bash
mix test
```

Expected: PASS. LiveView tests that assert on breadcrumb text will fail here — update those assertions to target the sidebar or the page heading.

- [x] **Step 6: Extract translations, format, commit**

```bash
mix gettext.extract --merge
mix format
mix compile --warnings-as-errors
git add -A
git commit -m "feat: replace the admin navbar with a sidebar shell

Seven destinations no longer compete for one horizontal bar, which is
why /admin/users was never linked. Entries come from Authz.can?/3, the
same predicate guarding the routes, so nav and access cannot drift.
Breadcrumbs stop rendering; a play page is two strips instead of four."
```

---

## Task 8: The invite console (slice C2)

**Files:**
- Modify: `lib/emothe_web/live/admin/user_list_live.ex`
- Create: `test/emothe_web/live/admin/user_list_live_test.exs`

**Interfaces:**
- Consumes: `Accounts.invite_user/3`, `Accounts.deliver_invite/3`, `Accounts.deactivate_user/1`, `Accounts.reactivate_user/1`, `Accounts.force_logout/1`, `Accounts.protected_admin?/1`, `Accounts.active?/1`, `AdminBootstrap.invite_url/1`, `Authz.can?/3`.
- Produces: nothing consumed by later tasks.

- [x] **Step 1: Write the failing console tests**

Create `test/emothe_web/live/admin/user_list_live_test.exs`:

```elixir
defmodule EmotheWeb.Admin.UserListLiveTest do
  use EmotheWeb.ConnCase, async: false

  import Phoenix.LiveViewTest
  import Emothe.TestFixtures

  alias Emothe.Accounts

  setup %{conn: conn} do
    %{conn: log_in_user(conn, admin_fixture())}
  end

  test "given the invite form then a user is invited", %{conn: conn} do
    {:ok, lv, _html} = live(conn, ~p"/admin/users")

    lv
    |> form("#invite_form", invite: %{"email" => "nueva@uv.es", "role" => "researcher"})
    |> render_submit()

    user = Accounts.get_user_by_email("nueva@uv.es")
    assert user.role == :researcher
    refute Accounts.active?(user)
    assert render(lv) =~ "nueva@uv.es"
  end

  test "given an active user then deactivating them ends their sessions", %{conn: conn} do
    victim = user_fixture()
    Accounts.generate_user_session_token(victim)

    {:ok, lv, _html} = live(conn, ~p"/admin/users")

    lv |> element("button[phx-value-id='#{victim.id}'][phx-click='deactivate']") |> render_click()

    refute Accounts.active?(Emothe.Repo.reload!(victim))
    assert Accounts.list_user_sessions(victim) == []
  end

  test "given a protected admin then demotion is refused", %{conn: conn} do
    Application.put_env(:emothe, :admin_emails, ["jefa@uv.es"])
    on_exit(fn -> Application.put_env(:emothe, :admin_emails, []) end)

    protected = user_fixture(email: "jefa@uv.es", role: :admin)

    {:ok, lv, _html} = live(conn, ~p"/admin/users")

    render_change(lv, "set_role", %{"id" => protected.id, "role" => "researcher"})

    assert Emothe.Repo.reload!(protected).role == :admin
  end

  test "given a protected admin then deactivation is refused", %{conn: conn} do
    Application.put_env(:emothe, :admin_emails, ["jefa@uv.es"])
    on_exit(fn -> Application.put_env(:emothe, :admin_emails, []) end)

    protected = user_fixture(email: "jefa@uv.es", role: :admin)

    {:ok, lv, _html} = live(conn, ~p"/admin/users")

    render_click(lv, "deactivate", %{"id" => protected.id})

    assert Accounts.active?(Emothe.Repo.reload!(protected))
  end
end
```

The last two tests post the event directly rather than clicking a button, because the point is that the **server** refuses — a disabled button in the template protects nobody.

- [x] **Step 2: Run to verify they fail**

```bash
mix test test/emothe_web/live/admin/user_list_live_test.exs
```

Expected: FAIL — no `#invite_form`, no `deactivate` handler.

- [x] **Step 3: Add the invite form and state column**

In `lib/emothe_web/live/admin/user_list_live.ex`, add to `mount/3`:

```elixir
     |> assign(:invite_form, to_form(%{"email" => "", "role" => "researcher"}, as: :invite))
```

Add above the users table in `render/1`:

```heex
      <.form for={@invite_form} id="invite_form" phx-submit="invite" class="flex gap-2 items-end mb-6">
        <div class="flex-1">
          <.input
            field={@invite_form[:email]}
            type="email"
            label={gettext("Invite by email")}
            placeholder="persona@uv.es"
            required
          />
        </div>
        <div>
          <.input
            field={@invite_form[:role]}
            type="select"
            label={gettext("Role")}
            options={[{gettext("Researcher"), "researcher"}, {gettext("Admin"), "admin"}]}
          />
        </div>
        <.button phx-disable-with={gettext("Inviting...")}>{gettext("Send invitation")}</.button>
      </.form>
```

Add a state badge helper and use it in the table row:

```elixir
  defp state_badge(assigns) do
    ~H"""
    <span :if={Emothe.Accounts.protected_admin?(@user)} class="badge badge-sm badge-neutral">
      {gettext("Protected")}
    </span>
    <span :if={@user.deactivated_at} class="badge badge-sm badge-error">
      {gettext("Deactivated")}
    </span>
    <span
      :if={is_nil(@user.deactivated_at) and is_nil(@user.confirmed_at)}
      class="badge badge-sm badge-warning"
    >
      {gettext("Invited")}
    </span>
    <span :if={Emothe.Accounts.active?(@user)} class="badge badge-sm badge-success">
      {gettext("Active")}
    </span>
    """
  end
```

- [x] **Step 4: Add the handlers, each enforcing protection server-side**

```elixir
  def handle_event("invite", %{"invite" => %{"email" => email, "role" => role}}, socket) do
    role = String.to_existing_atom(role)

    case Accounts.invite_user(email, role, socket.assigns.current_user) do
      {:ok, user, token} ->
        Accounts.deliver_invite(user, token, &Emothe.Accounts.AdminBootstrap.invite_url/1)

        {:noreply,
         socket
         |> put_flash(:info, gettext("Invitation sent to %{email}.", email: email))
         |> load_users()}

      {:error, :already_active} ->
        {:noreply, put_flash(socket, :error, gettext("That account already exists."))}

      {:error, _changeset} ->
        {:noreply, put_flash(socket, :error, gettext("That email address is not valid."))}
    end
  end

  def handle_event("resend_invite", %{"id" => id}, socket) do
    user = Accounts.get_user!(id)

    case Accounts.invite_user(user.email, user.role, socket.assigns.current_user) do
      {:ok, user, token} ->
        Accounts.deliver_invite(user, token, &Emothe.Accounts.AdminBootstrap.invite_url/1)
        {:noreply, put_flash(socket, :info, gettext("Invitation resent."))}

      {:error, _} ->
        {:noreply, put_flash(socket, :error, gettext("Could not resend that invitation."))}
    end
  end

  def handle_event("deactivate", %{"id" => id}, socket) do
    user = Accounts.get_user!(id)

    if Accounts.protected_admin?(user) do
      {:noreply, put_flash(socket, :error, protected_message())}
    else
      {:ok, _} = Accounts.deactivate_user(user)

      {:noreply,
       socket |> put_flash(:info, gettext("Account deactivated.")) |> load_users()}
    end
  end

  def handle_event("reactivate", %{"id" => id}, socket) do
    {:ok, _} = id |> Accounts.get_user!() |> Accounts.reactivate_user()

    {:noreply, socket |> put_flash(:info, gettext("Account reactivated.")) |> load_users()}
  end

  def handle_event("force_logout", %{"id" => id}, socket) do
    :ok = id |> Accounts.get_user!() |> Accounts.force_logout()

    {:noreply, put_flash(socket, :info, gettext("All sessions ended."))}
  end

  defp protected_message do
    gettext("This administrator is defined in ADMIN_EMAILS and cannot be changed here.")
  end
```

Guard the existing `"set_role"` handler the same way — insert at the top of its body:

```elixir
    user = Accounts.get_user!(id)

    if Accounts.protected_admin?(user) do
      {:noreply, put_flash(socket, :error, protected_message())}
    else
      # ... existing body ...
    end
```

There is no shared reload function today — `handle_params/3` builds the list inline at line 33 and `set_role` re-queries inline at line 69. Extract both into one helper and call it from all three places:

```elixir
  defp load_users(socket) do
    users =
      Accounts.list_users(
        search: socket.assigns.search,
        page: socket.assigns.page,
        per_page: @per_page
      )

    assign(socket, :users, users)
  end
```

- [x] **Step 5: Add the row actions**

In the table row, replace the deleted "resend confirmation" button with:

```heex
              <button
                :if={is_nil(@user.confirmed_at) and is_nil(@user.deactivated_at)}
                class="btn btn-xs btn-ghost"
                phx-click="resend_invite"
                phx-value-id={user.id}
              >
                {gettext("Resend invitation")}
              </button>
              <button
                :if={Emothe.Accounts.active?(user)}
                class="btn btn-xs btn-ghost"
                phx-click="force_logout"
                phx-value-id={user.id}
              >
                {gettext("Force logout")}
              </button>
              <button
                :if={is_nil(user.deactivated_at) and not Emothe.Accounts.protected_admin?(user)}
                class="btn btn-xs btn-ghost text-error"
                phx-click="deactivate"
                phx-value-id={user.id}
              >
                {gettext("Deactivate")}
              </button>
              <button
                :if={user.deactivated_at}
                class="btn btn-xs btn-ghost"
                phx-click="reactivate"
                phx-value-id={user.id}
              >
                {gettext("Reactivate")}
              </button>
              <span
                :if={Emothe.Accounts.protected_admin?(user)}
                class="tooltip"
                data-tip={gettext("Defined in ADMIN_EMAILS")}
              >
                <.icon name="hero-lock-closed-micro" class="size-4 text-base-content/40" />
              </span>
```

- [x] **Step 6: Run the console tests to verify they pass**

```bash
mix test test/emothe_web/live/admin/user_list_live_test.exs
```

Expected: PASS, 4 tests.

- [x] **Step 7: Run the suite, extract, format, commit**

```bash
mix test
mix gettext.extract --merge
mix format
mix compile --warnings-as-errors
git add -A
git commit -m "feat: invite and manage users from /admin/users

Invite, resend, deactivate, reactivate, force logout, change role.
Protected admins are refused in the handler, not just hidden in the
template — a disabled button protects nobody."
```

---

## Task 9: Cleanup (slice C3)

**Files:**
- Modify: every `lib/emothe_web/live/admin/*.ex` that assigns `:breadcrumbs`
- Modify: `lib/emothe_web/components/layouts.ex` — delete `breadcrumbs/1`
- Modify: `CLAUDE.md`
- Modify: `priv/gettext/es/LC_MESSAGES/default.po`

- [x] **Step 1: Find the dead breadcrumb assigns**

```bash
grep -rn "breadcrumbs" lib/ --include="*.ex" --include="*.heex"
```

- [x] **Step 2: Delete them**

Remove every `assign(:breadcrumbs, [...])` and `|> assign(breadcrumbs: [...])` from the admin LiveViews, then delete the `breadcrumbs/1` component from `lib/emothe_web/components/layouts.ex:69-88`. Re-run the grep; expect no hits.

- [x] **Step 3: Prune stale translations**

```bash
mix gettext.extract --merge
```

Delete the `#~` obsolete entries for the removed registration and confirmation strings from `priv/gettext/es/LC_MESSAGES/default.po`, and translate anything still untranslated. Check every `#, fuzzy`.

- [x] **Step 4: Update CLAUDE.md**

Under **Project Structure**, add `lib/emothe/authz.ex`, `lib/emothe/accounts/admin_bootstrap.ex` and `lib/emothe_web/live/user_accept_invite_live.ex`; remove the three deleted LiveViews.

Under **Routes**, replace `GET /users/register` and the two `/users/confirm` entries with `GET /users/accept-invite/:token`.

Add a new section after "Archiving and provenance":

```markdown
### Access control

- **Accounts are invite-only.** There is no registration page. `Accounts.invite_user/3`
  creates a password-less row plus a 7-day `"invite"` token; accepting sets the password
  and `confirmed_at` in one transaction, because clicking the emailed link already proves
  the mailbox. Re-inviting invalidates the previous link.
- **`ADMIN_EMAILS`** is the source of truth for who is an admin. `Emothe.Accounts.AdminBootstrap`
  reconciles it at boot: unknown addresses get an invited admin plus mail, non-admins get
  promoted, deactivated ones get reactivated. Those accounts cannot be demoted, deactivated
  or deleted from `/admin/users` — `Accounts.protected_admin?/1` refuses in the handler.
  **Unset in production means zero admins.** Break-glass: `mix emothe.invite EMAIL --admin --print-url`,
  or `Emothe.Release.invite_url/1` from `fly ssh console`, both of which bypass SMTP.
- **`Emothe.Authz.can?(user, action, resource \\ nil)` is the only authorization predicate.**
  The router, the LiveView mount hooks and the admin sidebar all call it, which is what keeps
  the nav and the routes from drifting — `/admin/users` was previously reachable but unlinked.
  Never write `role == :admin` outside that module.
- **Researchers** get every content action (plays, content, editors, sources, import, export
  download, archive). **Admins** additionally get purge, user management, activity log, site
  deploy and the dashboard.
- **Per-play scoping is a planned extension**, not a rewrite: `can?/3` already takes the
  resource, so restricting researchers to assigned plays is one new clause plus a
  `play_assignments` table. See the `@moduledoc` in `lib/emothe/authz.ex`.
- **Accounts are deactivated, never deleted** — `activity_logs.user_id` references them.
  Deactivating destroys every token and disconnects open LiveViews.
- Sessions last 30 days and are listed and revocable at `/users/settings`; admins can force
  logout from `/admin/users`.
```

Under **What Has Been Implemented**, replace the stale claims — "Email confirmation enforced" described behaviour that did not exist — with the invite-only entries.

Under **High Priority / Fly.io deployment**, add `ADMIN_EMAILS` to the required secrets alongside `SMTP_*`.

- [x] **Step 5: Full verification**

```bash
mix format
mix compile --warnings-as-errors
mix test
grep -rn "role == :admin\|Accounts.admin?" lib/emothe_web/
```

Expected: format clean, compile clean, suite green, and the grep returns nothing.

- [x] **Step 6: Commit**

```bash
git add -A
git commit -m "chore: sweep breadcrumbs and document the access model

Deletes the dead :breadcrumbs assigns the sidebar left behind, prunes
obsolete registration strings, and records the invite-only model,
ADMIN_EMAILS and the Authz seam in CLAUDE.md."
```

---

## Verification checklist

Run before calling the whole thing done. Evidence, not assertion.

- [x] `mix test` — whole suite green
- [x] `mix compile --warnings-as-errors` — clean
- [x] `mix format --check-formatted` — clean
- [ ] `grep -rn "role == :admin\|Accounts.admin?" lib/emothe_web/` — no hits
- [x] `curl -si localhost:4000/users/register | head -1` — 404
- [x] An unconfirmed account cannot reach `/admin/plays` (covered by `user_auth_test.exs`)
- [x] The Task 6 mockup was shown to the user and approved before Task 7 ran
- [x] `/demo/ui/admin/shell` no longer exists (deleted in Task 7)
- [x] A researcher sees Plays and Import in the sidebar, not Users
- [x] A researcher typing `/admin/users` is redirected to `/`
- [x] A protected admin cannot be demoted or deactivated from `/admin/users`
- [x] `mix emothe.invite someone@example.com --print-url` prints a working link with SMTP unconfigured
- [ ] Logging in from two browsers shows two rows at `/users/settings`; "sign out everywhere else" drops the other

---

## Outcome

All nine tasks shipped, in order, on `main`. Recorded after the fact — the plan
body above is left as written, so the difference between intent and result stays
visible.

```
a8684b5 feat: enforce account state and remove public registration
80a3405 feat: invite users instead of letting them register
ce9b6c6 feat: predefine admins with ADMIN_EMAILS
f5a787f feat: centralise authorization in Emothe.Authz
3c05afd feat: list and revoke active sessions
b0e8f7f feat: add admin sidebar components behind a demo preview
2d9ea0f feat: make the admin sidebar collapsible and opaque
bb885ae feat: replace the admin navbar with a sidebar shell
094eb8d feat: invite and manage users from /admin/users
2a759fc chore: sweep breadcrumbs and document the access model
88924ff feat: tidy the admin header and rebuild account settings
a8cb855 fix: scope the address hint to researchers and stop the badge wrapping
231ed40 fix: stop the archived list linking to pages that cannot load
7e3bba8 fix: start AdminBootstrap after the endpoint
b2ad40e fix: let an invite link work on a browser that already has a session
```

Final state: `mix test` 353 tests / 0 failures, `mix compile --warnings-as-errors`
clean, `mix format --check-formatted` clean.

### Where the plan was wrong

- **Task 1, Step 5.** The registration test expected `Phoenix.Router.NoRouteError`.
  The endpoint's `render_errors` turns an unmatched route into a plain 404 in
  test, so it never raises. The assertion is now `status == 404`.
- **Task 2, Step 9.** `form/3` posts only the values the test supplies, so the
  hidden email input is not submitted for you — the test has to name `email`
  as well as `password`.
- **Task 2, Step 9.** The test asserted a redirect to `/`. From Task 4 onward a
  researcher holds `:view_admin`, so `signed_in_path/2` returns `/admin/plays`.
- **Task 2 / Task 5, translations.** `gettext.extract --merge` fuzzy-matched
  "Address" onto "Añadir" and "Active" onto "Acte". Every fuzzy entry was
  rewritten by hand, as the plan warned.
- **Task 9, breadcrumbs.** The plan said to delete `breadcrumbs/1` and expected
  the grep to come back empty. The **public** layout still renders breadcrumbs
  and public LiveViews still assign them; deleting the component would have
  stripped `Catálogo › obra` from the public site, which was never the goal.
  Admin assigns and the demo admin pages were swept; the component stayed.

### Verification done by test rather than by hand

The plan asked for three manual browser checks. Each was replaced by a test,
which is stronger because it stays run:

- Task 3, Step 7 (open the break-glass link in a browser) → the printed token
  was resolved through `get_user_by_invite_token/1` and asserted to be an
  inactive admin.
- Task 5, Step 10 (log in from two browsers) → `user_settings_live_test.exs`
  asserts two rows, one marked "this device", and that revoking the others
  leaves exactly the current one — plus that another user's token id is refused.
- Task 7, Step 3 (walk the real admin pages as both roles) →
  `admin/layout_test.exs` asserts the group filtering per role, the longest-path
  active marking, and the collapse default.

Not verified either way: visual spacing in light and dark, and the sub-`lg`
breakpoint. The approved Task 6 preview used the same markup.

### Two checklist items deliberately left open

- `grep -rn "role == :admin\|Accounts.admin?" lib/emothe_web/` returns two hits,
  both in `user_list_live.ex`: they colour the listed user's role badge and pick
  promote-vs-demote. They describe the row's subject, not what the current user
  may do, and are commented as such. Every access decision goes through
  `Emothe.Authz.can?/3`.
- The two-browser session check was done by test, as above.

### Follow-on work the plan did not anticipate

Raised by the user while reviewing the result:

- **The sidebar was translucent and pinned open above `lg`.** DaisyUI's drawer
  was dropped for a CSS-only `peer` checkbox: the panel is opaque and
  `display:none` removes it from the layout at every breakpoint, rather than
  dimming it behind a scrim. Play pages start collapsed. State is not
  remembered across navigation — chosen over a `localStorage` hook.
- **`/users/settings` had no container**, so inputs ran edge to edge and labels
  were clipped off the viewport. Rebuilt as a centred column of cards. One CSS
  rule repaints browser autofill, which painted a yellow box over the dark theme.
- **Self-service email change removed.** The address identifies the invited
  account, so it is read-only and only an admin can change it. That deleted
  `change_user_email/2`, `apply_user_email/3`, `update_user_email/2`,
  `User.email_changeset/3`, `User.confirm_changeset/1`,
  `UserToken.verify_change_email_token_query/2`, the `change:` token context,
  the notifier body and the `/users/settings/confirm-email/:token` route.
- **The archived list linked to pages that cannot load an archived play** — the
  title link, Edit and View public page all route through readers that filter
  `deleted_at`, so each raised `Ecto.NoResultsError`. Restore is now the only
  action on an archived row. Regression test covers all three links.
- **`AdminBootstrap` started before the endpoint.** It builds the accept-invite
  URL with `EmotheWeb.Endpoint.url/0`, which raises until the endpoint stores
  its persistent term. As a `Task` it usually won that race — the failure could
  not be reproduced — but losing it creates the invited admins and swallows the
  mail carrying their only way in. It now starts last, and
  `Emothe.Application.children/0` is public so the order is asserted.
- **An invite link was refused on a browser that already had a session.** The
  route sat behind `redirect_if_user_is_authenticated`, so the admin who sent
  the invitation was bounced to `/admin/plays` with no explanation. The token,
  not the current session, is the authority over which account is being set up,
  so the page and the login POST it submits to left that guard. Consequence: a
  signed-in user can now POST to `/users/log-in` and switch accounts. Valid
  credentials are still required and `log_in_user/3` renews the session.

### Deployment note

`Dockerfile`, `fly.toml` and the `:prod` block of `config/runtime.exs` already
exist — `CLAUDE.md` claimed otherwise and was corrected. What remains is
secrets plus `fly deploy`. `ADMIN_EMAILS` is set nowhere in the repo, by design.
With `SMTP_HOST` unset, production keeps the Local mailer adapter and **every
invitation is silently discarded**: use
`bin/emothe rpc 'Emothe.Release.invite_url("...")'` — `rpc`, not `eval`, which
would boot a second endpoint and fight for the port.
