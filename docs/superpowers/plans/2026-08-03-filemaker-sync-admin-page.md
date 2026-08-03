# FileMaker Sync Admin Page Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Give admins a browser page that uploads the FileMaker NDJSON export, previews the diff against the database, and applies it — including per-conflict overwrite of curated research metadata.

**Architecture:** One LiveView (`EmotheWeb.Admin.FilemakerSyncLive`) over the existing pure domain layer. `Filemaker.load_index/1` + `load_versions/1` + `FilemakerSync.plan/3` run inside the upload's `consume_uploaded_entries` callback; the resulting plan lives in assigns and the uploaded file is never copied anywhere. Apply narrows `plan.conflicts` to the ticked subset and calls `FilemakerSync.apply_plan/2` with `force: true` — so per-conflict granularity costs zero change to the domain layer.

**Tech Stack:** Elixir 1.19.5 / OTP 28.1, Phoenix 1.8.3, LiveView 1.1.22, Tailwind 4 + DaisyUI, gettext, ExUnit.

**Spec:** `docs/superpowers/specs/2026-08-03-filemaker-sync-admin-page-design.md`

## Global Constraints

- **TDD is mandatory.** Failing test first, watch it fail, minimal implementation, watch it pass, then `mix test` (whole suite) before any completion claim. See the top of `CLAUDE.md`.
- **Zero changes to `lib/emothe/import/filemaker.ex`, `lib/emothe/import/filemaker_sync.ex`, the schema, or `lib/mix/tasks/emothe.import.filemaker.ex`.** If a task appears to need one, stop and report it.
- **No template may name a metadata column.** Field labels and value labels go through helpers with catch-all clauses, so S2b–S2f (`place_of_action`, `composition_date`, `collection`, `legacy_url`, `original_title`, `title_sort`) render with no edit to this page.
- **Assert through gettext, never literal English:** `Gettext.gettext(EmotheWeb.Gettext, "…", count: 3)`. The default locale is `"es"` (`config/config.exs:15`), so a literal-English assertion passes only until Task 6 translates the string.
- **Run mix with the sandbox PATH:** `export PATH="/home/bogdan/.asdf/installs/erlang/28.1/bin:/home/bogdan/.asdf/installs/elixir/1.19.5-otp-28/bin:/usr/bin:/usr/local/bin:/bin:$PATH"` — asdf shims are bash scripts and do not work here.
- `mix format` after every task. `mix compile --warnings-as-errors` before every commit.
- Baseline suite: **299 tests passing.**

---

### Task 1: The `:import_filemaker` permission

`Emothe.Authz.can?/3` is the only authorization predicate in this codebase. A sidebar entry *requires* an action atom, because `sidebar_groups/1` filters items through `Authz.can?/2` — that filter is what stops the router and the menu drifting apart. So the permission comes first.

Admin-only, not researcher-level like `:import_tei`: this sync is corpus-wide and its force path overwrites curated research metadata across every play at once, where a TEI import replaces one named file's play.

**Files:**
- Modify: `lib/emothe/authz.ex:30-32`
- Test: `test/emothe/authz_test.exs:11-12`

**Interfaces:**
- Consumes: nothing.
- Produces: `Emothe.Authz.can?(user, :import_filemaker)` — true for an active admin, false for everyone else. `Emothe.Authz.actions/0` includes `:import_filemaker`.

- [ ] **Step 1: Write the failing test**

`test/emothe/authz_test.exs` duplicates the action lists as literals on purpose — that literal is the tripwire that catches an action added to the module and nowhere else. Add the new atom to the admin-only literal:

```elixir
  @admin_only_actions ~w(purge_play manage_users view_activity_log
                         deploy_site view_dashboard import_filemaker)a
```

- [ ] **Step 2: Run the test to verify it fails**

```bash
export PATH="/home/bogdan/.asdf/installs/erlang/28.1/bin:/home/bogdan/.asdf/installs/elixir/1.19.5-otp-28/bin:/usr/bin:/usr/local/bin:/bin:$PATH"
mix test test/emothe/authz_test.exs
```

Expected: FAIL in `"an active admin"` / `"may do everything"`, with the message `expected admin to be allowed import_filemaker`. The researcher test passes trivially — an unknown action is denied to everyone, which is exactly why the admin assertion is the one that carries the weight here.

- [ ] **Step 3: Write the minimal implementation**

In `lib/emothe/authz.ex`:

```elixir
  @admin_actions @researcher_actions ++
                   ~w(purge_play manage_users view_activity_log deploy_site
                      view_dashboard import_filemaker)a
```

- [ ] **Step 4: Run the test to verify it passes**

```bash
mix test test/emothe/authz_test.exs
```

Expected: PASS, all tests in the file.

- [ ] **Step 5: Run the whole suite**

```bash
mix format && mix compile --warnings-as-errors && mix test
```

Expected: 299 passing, 0 failures.

- [ ] **Step 6: Commit**

```bash
git add lib/emothe/authz.ex test/emothe/authz_test.exs
git commit -m "feat: an :import_filemaker permission, admin only"
```

---

### Task 2: The route, the gate and the sidebar entry

The page renders nothing useful yet — this task is the access-control seam and the navigation, which are the two things easiest to get subtly wrong and hardest to notice.

**Files:**
- Create: `lib/emothe_web/live/admin/filemaker_sync_live.ex`
- Modify: `lib/emothe_web/router.ex:155` (inside `live_session :admin`)
- Modify: `lib/emothe_web/components/layouts.ex:261-275` (the `"Content"` group in `sidebar_groups/1`)
- Create: `test/emothe_web/live/admin/filemaker_sync_live_test.exs`
- Modify: `test/emothe_web/live/admin/layout_test.exs:8-27`

**Interfaces:**
- Consumes: `Emothe.Authz.can?(user, :import_filemaker)` from Task 1.
- Produces: the route `~p"/admin/filemaker"` mounting `EmotheWeb.Admin.FilemakerSyncLive`, with a form `#upload-form` carrying a `:export` upload. Later tasks add handlers to this module.

- [ ] **Step 1: Write the failing tests**

Create `test/emothe_web/live/admin/filemaker_sync_live_test.exs`:

```elixir
defmodule EmotheWeb.Admin.FilemakerSyncLiveTest do
  use EmotheWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import Emothe.TestFixtures

  describe "access" do
    test "given an admin then the upload form is rendered", %{conn: conn} do
      {:ok, lv, _html} = live(log_in_user(conn, admin_fixture()), ~p"/admin/filemaker")

      assert has_element?(lv, "#upload-form")
    end

    test "given a researcher then the page is refused", %{conn: conn} do
      conn = log_in_user(conn, user_fixture(role: :researcher))

      assert {:error, {:redirect, %{to: "/", flash: flash}}} = live(conn, ~p"/admin/filemaker")
      assert flash["error"] == t("You do not have access to that page.")
    end
  end

  defp t(msgid, bindings \\ []) do
    Gettext.gettext(EmotheWeb.Gettext, msgid, bindings)
  end
end
```

`"/"` and that flash are what `UserAuth.on_mount({:ensure_can, action}, …)` already does at `lib/emothe_web/user_auth.ex:188-195` — this test pins the existing behaviour to the new action, it does not ask for new behaviour.

Then in `test/emothe_web/live/admin/layout_test.exs`, add one line to each of the first two tests:

```elixir
    test "given an admin then every group is rendered", %{conn: conn} do
      {:ok, _lv, html} = live(log_in_user(conn, admin_fixture()), ~p"/admin/plays")

      assert html =~ ~p"/admin/plays/import"
      assert html =~ ~p"/admin/filemaker"
      assert html =~ ~p"/admin/export"
      assert html =~ ~p"/admin/activity-log"
      assert html =~ ~p"/admin/users"
      assert html =~ "/admin/dashboard"
    end

    test "given a researcher then only the content group is rendered", %{conn: conn} do
      {:ok, _lv, html} =
        live(log_in_user(conn, user_fixture(role: :researcher)), ~p"/admin/plays")

      assert html =~ ~p"/admin/plays/import"
      refute html =~ ~p"/admin/filemaker"
      refute html =~ ~p"/admin/users"
      refute html =~ ~p"/admin/activity-log"
      refute html =~ "/admin/dashboard"
    end
```

- [ ] **Step 2: Run the tests to verify they fail**

```bash
mix test test/emothe_web/live/admin/filemaker_sync_live_test.exs test/emothe_web/live/admin/layout_test.exs
```

Expected: the new file fails to compile the route (`no route found for GET /admin/filemaker`), and `layout_test` fails on the admin assertion because the sidebar has no such entry.

- [ ] **Step 3: Write the minimal implementation**

Create `lib/emothe_web/live/admin/filemaker_sync_live.ex`:

```elixir
defmodule EmotheWeb.Admin.FilemakerSyncLive do
  use EmotheWeb, :live_view

  # Stricter than the live_session's :view_admin, declared here so admin
  # sections still navigate without a full page reload.
  on_mount {EmotheWeb.UserAuth, {:ensure_can, :import_filemaker}}

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(:page_title, gettext("FileMaker sync"))
     |> assign(:plan, nil)
     |> assign(:plays_by_id, %{})
     |> assign(:selected, MapSet.new())
     |> assign(:results, nil)
     |> allow_upload(:export,
       accept: ~w(.ndjson .json),
       max_entries: 1,
       max_file_size: 20_000_000
     )}
  end

  @impl true
  def handle_event("validate", _params, socket), do: {:noreply, socket}

  def handle_event("cancel-upload", %{"ref" => ref}, socket) do
    {:noreply, cancel_upload(socket, :export, ref)}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="mx-auto max-w-5xl px-4 py-8">
      <div class="mb-6">
        <h1 class="text-3xl font-semibold tracking-tight text-base-content">
          {gettext("FileMaker sync")}
        </h1>
        <p class="mt-1 text-sm text-base-content/70">
          {gettext(
            "Upload the FileMaker export, review what it would change, then apply it."
          )}
        </p>
      </div>

      <div :if={is_nil(@plan) && is_nil(@results)} class="card border border-base-300 bg-base-100 shadow-sm">
        <div class="card-body">
          <h2 class="card-title">{gettext("Select the export")}</h2>
          <p class="mb-3 text-sm text-base-content/70">
            {gettext("One .ndjson file, as exported from FileMaker.")}
          </p>
          <form id="upload-form" phx-submit="preview" phx-change="validate">
            <.live_file_input
              upload={@uploads.export}
              class="file-input file-input-bordered w-full mb-4"
            />

            <div :for={err <- upload_errors(@uploads.export)} class="text-error text-sm mb-2">
              {upload_error_to_string(err)}
            </div>

            <button type="submit" class="btn btn-primary" disabled={@uploads.export.entries == []}>
              {gettext("Preview changes")}
            </button>
          </form>
        </div>
      </div>
    </div>
    """
  end

  defp upload_error_to_string(:too_large), do: gettext("File is too large (max 20MB)")
  defp upload_error_to_string(:not_accepted), do: gettext("Only .ndjson files are accepted")
  defp upload_error_to_string(:too_many_files), do: gettext("Upload one file at a time")
  defp upload_error_to_string(err), do: "#{gettext("Error")}: #{inspect(err)}"
end
```

There is no `"preview"` handler yet — the form cannot be submitted in this task, which is fine; Task 3 adds it. Do **not** assign `:breadcrumbs`: breadcrumbs left the admin layout in the auth and admin UX work, and the one still assigned in `import_live.ex:20-24` is dead code. Do not assign `:play_context` either — its absence is what leaves the sidebar open, which is right for a corpus-wide page.

In `lib/emothe_web/router.ex`, inside `live_session :admin`, after the `live "/export", ExportSiteLive, :index` line:

```elixir
      live "/filemaker", FilemakerSyncLive, :index
```

No new pipeline. The scope pipeline stays `:require_admin_area` and the LiveView tightens the gate itself, which is how `UserListLive` handles `:manage_users` in this same session.

In `lib/emothe_web/components/layouts.ex`, in `sidebar_groups/1`, add a third item to the `"Content"` group after `Import`:

```elixir
         %{
           label: gettext("FileMaker"),
           to: "/admin/filemaker",
           icon: "hero-circle-stack-micro",
           action: :import_filemaker
         }
```

`sidebar_active?/3` needs nothing — it picks the longest matching prefix and `/admin/filemaker` shares no prefix with another entry.

- [ ] **Step 4: Run the tests to verify they pass**

```bash
mix test test/emothe_web/live/admin/filemaker_sync_live_test.exs test/emothe_web/live/admin/layout_test.exs
```

Expected: PASS.

- [ ] **Step 5: Run the whole suite**

```bash
mix format && mix compile --warnings-as-errors && mix test
```

Expected: 301 passing (299 + the 2 new access tests), 0 failures.

- [ ] **Step 6: Commit**

```bash
git add lib/emothe_web/live/admin/filemaker_sync_live.ex lib/emothe_web/router.ex \
        lib/emothe_web/components/layouts.ex \
        test/emothe_web/live/admin/filemaker_sync_live_test.exs \
        test/emothe_web/live/admin/layout_test.exs
git commit -m "feat: an admin route and sidebar entry for the FileMaker sync"
```

---

### Task 3: The combined test fixture

The page uploads **one** file carrying both layouts, which is what the real export
(`doc/w3emothe_T01_tituloEM.ndjson`, git-ignored) is. The two existing fixtures are split one
layout per file. Both readers key off the `_meta` envelope lines and ignore records belonging to
the other layout, so concatenation is all this takes.

This task exists separately because the next two both depend on the fixture and on knowing exactly
what it plans to. Those numbers were produced by running `plan/3`, not estimated.

**Files:**
- Create: `test/fixtures/filemaker/export_sample.ndjson`
- Test: `test/emothe/import/filemaker_test.exs` (add one test)

**Interfaces:**
- Consumes: `test/fixtures/filemaker/index_sample.ndjson`, `test/fixtures/filemaker/versions_sample.ndjson`.
- Produces: `test/fixtures/filemaker/export_sample.ndjson`, for which `load_index/1` returns keys `["EMOTHE0038", "EMOTHE0052", "HIE0393"]` and `load_versions/1` returns keys `["EMOTHE0038", "EMOTHE0211", "HIE0393"]`.

- [ ] **Step 1: Write the failing test**

Add to `test/emothe/import/filemaker_test.exs` (match the surrounding `describe` style in that file):

```elixir
  # The admin page uploads one file carrying both layouts, the way the real
  # export does. Both readers must find their own records in it.
  test "given one file with both layouts then each reader finds its own records" do
    path = "test/fixtures/filemaker/export_sample.ndjson"

    assert {:ok, index} = Filemaker.load_index(path)
    assert {:ok, versions} = Filemaker.load_versions(path)

    assert Enum.sort(Map.keys(index)) == ["EMOTHE0038", "EMOTHE0052", "HIE0393"]
    assert Enum.sort(Map.keys(versions)) == ["EMOTHE0038", "EMOTHE0211", "HIE0393"]
  end
```

- [ ] **Step 2: Run the test to verify it fails**

```bash
mix test test/emothe/import/filemaker_test.exs
```

Expected: FAIL — `load_index/1` returns `{:error, :enoent}`, so the `assert {:ok, index}` match fails.

- [ ] **Step 3: Create the fixture**

```bash
cat test/fixtures/filemaker/index_sample.ndjson \
    test/fixtures/filemaker/versions_sample.ndjson \
    > test/fixtures/filemaker/export_sample.ndjson
wc -l test/fixtures/filemaker/export_sample.ndjson
```

Expected: `7 test/fixtures/filemaker/export_sample.ndjson` — two `_meta` envelopes plus five records.

- [ ] **Step 4: Run the test to verify it passes**

```bash
mix test test/emothe/import/filemaker_test.exs
```

Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add test/fixtures/filemaker/export_sample.ndjson test/emothe/import/filemaker_test.exs
git commit -m "test: a filemaker fixture carrying both layouts in one file"
```

---

### Task 4: Upload, plan, and render the four buckets

**Files:**
- Modify: `lib/emothe_web/live/admin/filemaker_sync_live.ex`
- Test: `test/emothe_web/live/admin/filemaker_sync_live_test.exs`

**Interfaces:**
- Consumes: `test/fixtures/filemaker/export_sample.ndjson` (Task 3); the route and module from Task 2; `Emothe.Import.Filemaker.load_index/1`, `load_versions/1`; `Emothe.Import.FilemakerSync.all_plays/0`, `plan/3`.
- Produces: assigns `@plan` (the `%{changes:, conflicts:, unchanged:, missing:}` map), `@plays_by_id` (`%{play_id => %Play{}}`); DOM ids `#changes`, `#conflicts`, `#unchanged`, `#missing`, `#sync-actions`; the public helpers `field_label/1` and `value_label/3`, and the `"preview"` and `"discard"` events. Task 5 adds `"toggle-conflict"` and `"apply"`.

**The corpus these tests build, and what it plans to.** Verified by running `FilemakerSync.plan/3` against `export_sample.ndjson`, not guessed:

| Play | Set up as | Lands in |
|---|---|---|
| `EMOTHE0038` | `historical_time: "edad_media"` | `changes` (`language: "en"`, `historical_time_note`) **and** `conflicts` (`historical_time`) |
| `EMOTHE0052` | `relationship_type: "traduccion"`, `parent_play_id: p38.id` | `unchanged` |
| `EMOTHE0211` | defaults | `changes` (`historical_time: "siglo_xvii"`) **and** `missing` |
| `HIE0393` | `historical_time: "edad_media"` | `changes` (`language: "en"`, `relationship_type: "traduccion"`, `historical_time_note`) **and** `conflicts` (`historical_time`) |
| `AL0001` | defaults | `missing` only |

Totals: 3 changes, 2 conflicts, 1 unchanged, 2 missing. `play_fixture/1` defaults `"language" => "es"`, which is why `EMOTHE0038` and `HIE0393` get a language change while `EMOTHE0052` does not — the index says `es` for that one. `play_fixture/1` takes **string** keys.

- [ ] **Step 1: Write the failing tests**

Add to `test/emothe_web/live/admin/filemaker_sync_live_test.exs`, inside the module:

```elixir
  @export "test/fixtures/filemaker/export_sample.ndjson"

  defp corpus do
    p38 =
      play_fixture(%{
        "code" => "EMOTHE0038",
        "title" => "Antony and Cleopatra",
        "historical_time" => "edad_media"
      })

    p52 =
      play_fixture(%{
        "code" => "EMOTHE0052",
        "title" => "Antonio y Cleopatra",
        "relationship_type" => "traduccion",
        "parent_play_id" => p38.id
      })

    p211 = play_fixture(%{"code" => "EMOTHE0211", "title" => "El caballero de Olmedo"})

    p393 =
      play_fixture(%{
        "code" => "HIE0393",
        "title" => "The Spanish Bawd",
        "historical_time" => "edad_media"
      })

    al = play_fixture(%{"code" => "AL0001", "title" => "Artelope play"})

    %{p38: p38, p52: p52, p211: p211, p393: p393, al: al}
  end

  defp upload_and_preview(lv, path) do
    lv
    |> file_input("#upload-form", :export, [
      %{name: Path.basename(path), content: File.read!(path), type: "application/x-ndjson"}
    ])
    |> render_upload(Path.basename(path))

    lv |> element("#upload-form") |> render_submit()
  end

  describe "preview" do
    setup do
      corpus()
      :ok
    end

    test "given the export then every bucket is reported", %{conn: conn} do
      {:ok, lv, _html} = live(log_in_user(conn, admin_fixture()), ~p"/admin/filemaker")

      upload_and_preview(lv, @export)

      changes = lv |> element("#changes") |> render()
      assert changes =~ "EMOTHE0038"
      assert changes =~ "EMOTHE0211"
      assert changes =~ "HIE0393"
      refute changes =~ "AL0001"

      assert lv |> element("#unchanged") |> render() =~ "EMOTHE0052"

      missing = lv |> element("#missing") |> render()
      assert missing =~ "AL0001"
      assert missing =~ "EMOTHE0211"
    end

    # A play absent from the published index can still carry a T01 research
    # record. EMOTHE0341 is that case in the real export. Presenting the buckets
    # as tabs would imply they are exclusive; they are not.
    test "given a play with research metadata but no index entry then it is in both buckets",
         %{conn: conn} do
      {:ok, lv, _html} = live(log_in_user(conn, admin_fixture()), ~p"/admin/filemaker")

      upload_and_preview(lv, @export)

      assert lv |> element("#changes") |> render() =~ "EMOTHE0211"
      assert lv |> element("#missing") |> render() =~ "EMOTHE0211"
    end

    test "given a new value then the current one is shown beside it", %{conn: conn} do
      {:ok, lv, _html} = live(log_in_user(conn, admin_fixture()), ~p"/admin/filemaker")

      upload_and_preview(lv, @export)
      changes = lv |> element("#changes") |> render()

      assert changes =~ t("Historical time")
      assert changes =~ EmotheWeb.PlayLabels.historical_time_label("siglo_xvii")
    end

    test "given discard then the upload form comes back", %{conn: conn} do
      {:ok, lv, _html} = live(log_in_user(conn, admin_fixture()), ~p"/admin/filemaker")

      upload_and_preview(lv, @export)
      assert has_element?(lv, "#changes")

      lv |> element("button", t("Discard")) |> render_click()

      assert has_element?(lv, "#upload-form")
      refute has_element?(lv, "#changes")
    end
  end

  # A field with no field_label/1 clause of its own must still render. This is
  # what makes S2b--S2f (place_of_action, composition_date, …) land on this page
  # with no edit to it.
  describe "field labels" do
    test "given an unknown field then the catch-all renders it readably" do
      assert EmotheWeb.Admin.FilemakerSyncLive.field_label(:place_of_action) == "place of action"
    end

    test "given an unknown field then its value renders as text" do
      assert EmotheWeb.Admin.FilemakerSyncLive.value_label(:place_of_action, "Roma", %{}) ==
               "Roma"
    end
  end
```

- [ ] **Step 2: Run the tests to verify they fail**

```bash
mix test test/emothe_web/live/admin/filemaker_sync_live_test.exs
```

Expected: FAIL. The preview tests fail on the missing `"preview"` event handler (`no handle_event/3 clause`), and the field-label tests fail with `UndefinedFunctionError` for `field_label/1`.

- [ ] **Step 3: Write the minimal implementation**

In `lib/emothe_web/live/admin/filemaker_sync_live.ex`, add the aliases:

```elixir
  alias Emothe.Import.Filemaker
  alias Emothe.Import.FilemakerSync
  alias EmotheWeb.PlayLabels
```

Add the handlers after `handle_event("cancel-upload", …)`:

```elixir
  def handle_event("preview", _params, socket) do
    case consume_uploaded_entries(socket, :export, fn %{path: path}, _entry ->
           {:ok, read_plan(path)}
         end) do
      [] ->
        {:noreply, socket}

      [{:ok, plan, plays}] ->
        {:noreply,
         socket
         |> assign(:plan, plan)
         |> assign(:plays_by_id, Map.new(plays, &{&1.id, &1}))
         |> assign(:selected, MapSet.new())
         |> assign(:results, nil)}

      [{:error, reason}] ->
        {:noreply, put_flash(socket, :error, error_message(reason))}
    end
  end

  def handle_event("discard", _params, socket) do
    {:noreply,
     socket
     |> assign(:plan, nil)
     |> assign(:plays_by_id, %{})
     |> assign(:selected, MapSet.new())
     |> assign(:results, nil)}
  end
```

And the private reader. The `:no_records` guard is load-bearing: `load_index/1` only fails when `File.read` fails — it decodes line by line and silently drops anything that is not a record for its layout. Upload the wrong file and both readers return `{:ok, %{}}`, which plans cleanly as "all 82 plays are not in the published index". That screen is indistinguishable from real data loss.

```elixir
  defp read_plan(path) do
    with {:ok, index} <- Filemaker.load_index(path),
         {:ok, versions} <- Filemaker.load_versions(path),
         true <- map_size(index) > 0 or map_size(versions) > 0 do
      plays = FilemakerSync.all_plays()
      {:ok, FilemakerSync.plan(index, plays, versions), plays}
    else
      false -> {:error, :no_records}
      {:error, reason} -> {:error, reason}
    end
  end

  defp error_message(:no_records) do
    gettext("No FileMaker records found in that file. Is it the right export?")
  end

  defp error_message(reason) do
    "#{gettext("Cannot read the file")}: #{inspect(reason)}"
  end
```

Add the label helpers. They are public because the test calls them directly — a unit test on the catch-all clauses is what the suite can actually guard; that a template never hardcodes a column name is a review matter.

```elixir
  @doc """
  The human name of a field in a plan's `sets`.

  The catch-all clause is deliberate: a later FileMaker slice adds a field to
  `Filemaker.load_versions/1` and therefore to `sets`, and it must render on this
  page without an edit here. Adding a clause is polish, not a requirement.
  """
  def field_label(:language), do: gettext("Language")
  def field_label(:relationship_type), do: gettext("Relationship")
  def field_label(:parent_play_id), do: gettext("Parent play")
  def field_label(:historical_time), do: gettext("Historical time")
  def field_label(:historical_time_note), do: gettext("Historical time note")
  def field_label(other), do: other |> to_string() |> String.replace("_", " ")

  @doc "The display value of a field, given the plays keyed by id."
  def value_label(:historical_time, value, _plays), do: PlayLabels.historical_time_label(value)

  def value_label(:parent_play_id, id, plays) do
    case Map.get(plays, id) do
      nil -> "—"
      play -> play.code
    end
  end

  def value_label(_field, value, _plays), do: to_string(value)
```

Add the preview markup to `render/1`, after the upload card:

```heex
      <div :if={@plan && @plan.changes != []} id="changes" class="card mb-6 border border-base-300 bg-base-100 shadow-sm">
        <div class="card-body">
          <h2 class="card-title">
            {gettext("%{count} play(s) to update", count: length(@plan.changes))}
          </h2>
          <div class="overflow-x-auto">
            <table class="table table-sm">
              <thead>
                <tr>
                  <th>{gettext("Code")}</th>
                  <th>{gettext("Title")}</th>
                  <th>{gettext("Changes")}</th>
                </tr>
              </thead>
              <tbody>
                <tr :for={change <- @plan.changes}>
                  <td><span class="badge badge-primary badge-sm">{change.code}</span></td>
                  <td>{change.title}</td>
                  <td>
                    <ul class="space-y-0.5">
                      <li :for={{field, value} <- change.sets} class="text-xs">
                        <span class="font-medium">{field_label(field)}</span>:
                        <span class="text-base-content/60">
                          {current_value(@plays_by_id, change.play_id, field)}
                        </span>
                        <span aria-hidden="true">&rarr;</span>
                        <span class="font-medium">{value_label(field, value, @plays_by_id)}</span>
                      </li>
                    </ul>
                  </td>
                </tr>
              </tbody>
            </table>
          </div>
        </div>
      </div>

      <div :if={@plan} id="counts" class="card mb-6 border border-base-300 bg-base-100 shadow-sm">
        <div class="card-body gap-2">
          <details :if={@plan.unchanged != []} id="unchanged">
            <summary class="cursor-pointer text-sm">
              {gettext("%{count} play(s) already match", count: length(@plan.unchanged))}
            </summary>
            <p class="mt-2 font-mono text-xs text-base-content/70">
              {Enum.join(@plan.unchanged, ", ")}
            </p>
          </details>

          <details :if={@plan.missing != []} id="missing">
            <summary class="cursor-pointer text-sm">
              {gettext("%{count} play(s) are not in the published index",
                count: length(@plan.missing)
              )}
            </summary>
            <p class="mt-2 text-xs text-base-content/70">
              {gettext(
                "Nothing is created for these. A play can be absent from the index and still have research metadata to fill, in which case it is listed above as well."
              )}
            </p>
            <p class="mt-1 font-mono text-xs text-base-content/70">
              {Enum.join(@plan.missing, ", ")}
            </p>
          </details>
        </div>
      </div>

      <div :if={@plan} id="sync-actions" class="flex items-center gap-3">
        <p
          :if={@plan.changes == [] and @plan.conflicts == []}
          class="text-sm text-base-content/70"
        >
          {gettext("Everything already matches the export.")}
        </p>
        <button phx-click="discard" class="btn btn-ghost">{gettext("Discard")}</button>
      </div>
```

The Apply button and the `#conflicts` card arrive in Task 5. Add this private helper beside the label helpers:

```elixir
  defp current_value(plays_by_id, play_id, field) do
    case plays_by_id |> Map.fetch!(play_id) |> Map.get(field) do
      blank when blank in [nil, ""] -> gettext("(blank)")
      value -> value_label(field, value, plays_by_id)
    end
  end
```

- [ ] **Step 4: Run the tests to verify they pass**

```bash
mix test test/emothe_web/live/admin/filemaker_sync_live_test.exs
```

Expected: PASS, every test in the file. The `#conflicts` card belongs to Task 5, and no test here asserts it — this task ends green.

- [ ] **Step 5: Confirm the timing claim**

The spec asserts this is fast enough to be synchronous rather than needing the `handle_info` progress chain `import_live.ex` has. Confirm it rather than assume:

```bash
mix test test/emothe_web/live/admin/filemaker_sync_live_test.exs --trace 2>&1 | /usr/bin/tail -20
```

Expected: each preview test well under a second. If the real 649-line export ever makes this slow, `start_async` is the upgrade path — leave a `ponytail:` comment saying so above `read_plan/1`:

```elixir
  # ponytail: synchronous. 649 lines parsed, 82 plays diffed in memory, ~11 rows
  # written. start_async if the export grows an order of magnitude.
```

- [ ] **Step 6: Commit**

```bash
mix format && mix compile --warnings-as-errors
git add lib/emothe_web/live/admin/filemaker_sync_live.ex \
        test/emothe_web/live/admin/filemaker_sync_live_test.exs
git commit -m "feat: preview a FileMaker export's changes in the admin page"
```

---

### Task 5: Per-conflict checkboxes and Apply

The reason the page exists. Two things land here: the curator picks which curated values the export
may overwrite, and the writes finally carry a `user_id` — today the mix task passes `nil` and every
FileMaker write in `activity_logs` is attributed to nobody.

Per-conflict granularity needs **no domain change**. `FilemakerSync.writes/2` folds `plan.conflicts`
into the writes when `force: true`, so handing it a plan whose `:conflicts` is the ticked subset is
exactly per-conflict force. An empty selection reduces to `force: false`, because folding an empty
list in adds nothing — one code path, no branch.

**Files:**
- Modify: `lib/emothe_web/live/admin/filemaker_sync_live.ex`
- Test: `test/emothe_web/live/admin/filemaker_sync_live_test.exs`

**Interfaces:**
- Consumes: everything Task 4 produced; `Emothe.Import.FilemakerSync.apply_plan/2`, which returns `[{:ok, code} | {:error, code, changeset}]` and writes one `activity_logs` row per play.
- Produces: the `"toggle-conflict"` and `"apply"` events, the `@results` assign, DOM ids `#conflicts` and `#results`.

- [ ] **Step 1: Write the failing tests**

Add to `test/emothe_web/live/admin/filemaker_sync_live_test.exs`:

```elixir
  describe "apply" do
    setup do
      Map.put(corpus(), :admin, admin_fixture())
    end

    test "given no conflict ticked then fills are written and curated values are left alone",
         %{conn: conn, admin: admin, p38: p38, p211: p211, p393: p393} do
      {:ok, lv, _html} = live(log_in_user(conn, admin), ~p"/admin/filemaker")

      upload_and_preview(lv, @export)
      lv |> element("#sync-actions button", t("Apply")) |> render_click()

      # Blank columns filled.
      assert Catalogue.get_play!(p211.id).historical_time == "siglo_xvii"
      assert Catalogue.get_play!(p38.id).language == "en"

      assert Catalogue.get_play!(p38.id).historical_time_note ==
               "First century BC. The play dramatizes events taking place between 40 and 30 BC."

      # Curated values a researcher set are untouched.
      assert Catalogue.get_play!(p38.id).historical_time == "edad_media"
      assert Catalogue.get_play!(p393.id).historical_time == "edad_media"
    end

    test "given one conflict ticked then only that one is overwritten",
         %{conn: conn, admin: admin, p38: p38, p393: p393} do
      {:ok, lv, _html} = live(log_in_user(conn, admin), ~p"/admin/filemaker")

      upload_and_preview(lv, @export)

      lv
      |> element(~s(#conflicts input[phx-value-play-id="#{p393.id}"]))
      |> render_click()

      lv |> element("#sync-actions button", t("Apply")) |> render_click()

      assert Catalogue.get_play!(p393.id).historical_time == "siglo_xvi"
      assert Catalogue.get_play!(p38.id).historical_time == "edad_media"
    end

    # apply_plan/2 already logs; only a LiveView has a user_id to give it. This
    # is the whole provenance argument for the page.
    test "given an apply then every write is attributed to the signed-in admin",
         %{conn: conn, admin: admin, p211: p211} do
      {:ok, lv, _html} = live(log_in_user(conn, admin), ~p"/admin/filemaker")

      upload_and_preview(lv, @export)
      lv |> element("#sync-actions button", t("Apply")) |> render_click()

      entries = ActivityLog.list_entries(play_id: p211.id)

      assert Enum.any?(entries, fn entry ->
               entry.user_id == admin.id and entry.metadata["source"] == "filemaker_index"
             end)
    end

    test "given an apply then the results replace the preview", %{conn: conn, admin: admin} do
      {:ok, lv, _html} = live(log_in_user(conn, admin), ~p"/admin/filemaker")

      upload_and_preview(lv, @export)
      lv |> element("#sync-actions button", t("Apply")) |> render_click()

      assert has_element?(lv, "#results")
      refute has_element?(lv, "#changes")
    end
  end
```

Add the aliases the tests need at the top of the test module:

```elixir
  alias Emothe.ActivityLog
  alias Emothe.Catalogue
```

`ActivityLog.list_entries/1` accepts `:play_id` (`lib/emothe/activity_log.ex:71`) and `metadata` is JSONB, so its keys come back as strings — hence `entry.metadata["source"]`, not `entry.metadata.source`.

Also add the two conflict-card assertions Task 4 left out, to the bucket test in the `"preview"` describe:

```elixir
      conflicts = lv |> element("#conflicts") |> render()
      assert conflicts =~ "EMOTHE0038"
      assert conflicts =~ "HIE0393"
```

- [ ] **Step 2: Run the tests to verify they fail**

```bash
mix test test/emothe_web/live/admin/filemaker_sync_live_test.exs
```

Expected: FAIL — no element matching `#sync-actions button` with the Apply text, and no `#conflicts` card.

- [ ] **Step 3: Write the minimal implementation**

Add the handlers to `lib/emothe_web/live/admin/filemaker_sync_live.ex`:

```elixir
  # The key is {play_id, field-as-string} because phx-value-* arrives as strings.
  def handle_event("toggle-conflict", %{"play-id" => play_id, "field" => field}, socket) do
    key = {play_id, field}

    selected =
      if MapSet.member?(socket.assigns.selected, key) do
        MapSet.delete(socket.assigns.selected, key)
      else
        MapSet.put(socket.assigns.selected, key)
      end

    {:noreply, assign(socket, :selected, selected)}
  end

  # The ticked set *is* the force list. Narrowing plan.conflicts before handing it
  # over is what makes per-conflict force free: an empty selection folds nothing
  # in, which is exactly force: false.
  def handle_event("apply", _params, socket) do
    %{plan: plan, selected: selected} = socket.assigns

    results =
      %{plan | conflicts: Enum.filter(plan.conflicts, &selected?(&1, selected))}
      |> FilemakerSync.apply_plan(user_id: socket.assigns.current_user.id, force: true)

    written = Enum.count(results, &match?({:ok, _code}, &1))

    {:noreply,
     socket
     |> assign(:results, results)
     |> assign(:plan, nil)
     |> assign(:selected, MapSet.new())
     |> put_flash(:info, gettext("Updated %{count} play(s).", count: written))}
  end
```

Add the two private helpers:

```elixir
  defp selected?(conflict, selected) do
    MapSet.member?(selected, {conflict.play_id, to_string(conflict.field)})
  end
```

Add the `#conflicts` card to `render/1`, between the `#changes` card and the `#counts` card:

```heex
      <div :if={@plan && @plan.conflicts != []} id="conflicts" class="card mb-6 border border-warning bg-base-100 shadow-sm">
        <div class="card-body">
          <h2 class="card-title text-warning">
            <.icon name="hero-exclamation-triangle" class="size-5" />
            {gettext("%{count} value(s) already set by a researcher",
              count: length(@plan.conflicts)
            )}
          </h2>
          <p class="text-sm text-base-content/70">
            {gettext(
              "These are left alone unless you tick them. For research metadata the export is a starting point, not the authority."
            )}
          </p>

          <ul class="mt-3 space-y-2">
            <li :for={conflict <- @plan.conflicts} class="rounded-box bg-base-200 px-3 py-2">
              <label class="flex items-start gap-3 cursor-pointer">
                <input
                  type="checkbox"
                  class="checkbox checkbox-warning checkbox-sm mt-0.5"
                  checked={selected?(conflict, @selected)}
                  phx-click="toggle-conflict"
                  phx-value-play-id={conflict.play_id}
                  phx-value-field={conflict.field}
                />
                <span class="min-w-0">
                  <span class="badge badge-primary badge-sm">{conflict.code}</span>
                  <span class="font-medium">{conflict.title}</span>
                  <span class="block text-xs mt-1">
                    <span class="font-medium">{field_label(conflict.field)}</span>:
                    {gettext("keep %{current}",
                      current: value_label(conflict.field, conflict.current, @plays_by_id)
                    )} — {gettext("the export says %{indexed}",
                      indexed: value_label(conflict.field, conflict.indexed, @plays_by_id)
                    )}
                  </span>
                </span>
              </label>
            </li>
          </ul>
        </div>
      </div>
```

Add the Apply button to the `#sync-actions` div, before the Discard button:

```heex
        <button
          :if={@plan.changes != [] or @plan.conflicts != []}
          phx-click="apply"
          class="btn btn-primary"
        >
          {gettext("Apply")}
        </button>
```

Add the results card at the end of `render/1`, after `#sync-actions`:

```heex
      <div :if={@results} id="results" class="card border border-base-300 bg-base-100 shadow-sm">
        <div class="card-body">
          <h2 class="card-title">{gettext("Applied")}</h2>
          <ul class="space-y-1 text-sm">
            <li :for={result <- @results}>
              <%= case result do %>
                <% {:ok, code} -> %>
                  <span class="badge badge-success badge-sm">{code}</span>
                <% {:error, code, changeset} -> %>
                  <span class="badge badge-error badge-sm">{code}</span>
                  <span class="ml-2 text-xs text-error">{inspect(changeset.errors)}</span>
              <% end %>
            </li>
          </ul>
          <div class="card-actions mt-4">
            <button phx-click="discard" class="btn btn-sm btn-outline">
              {gettext("Sync another export")}
            </button>
          </div>
        </div>
      </div>
```

Finally, add the staleness note above `handle_event("apply", …)`:

```elixir
  # ponytail: the plan is held in assigns, so it can go stale if someone else
  # edits a play between preview and Apply. Single-curator tool; re-plan on
  # Apply if that stops being true.
```

- [ ] **Step 4: Run the tests to verify they pass**

```bash
mix test test/emothe_web/live/admin/filemaker_sync_live_test.exs
```

Expected: PASS, every test in the file including the two `#conflicts` assertions.

- [ ] **Step 5: Run the whole suite**

```bash
mix format && mix compile --warnings-as-errors && mix test
```

Expected: 0 failures.

- [ ] **Step 6: Commit**

```bash
git add lib/emothe_web/live/admin/filemaker_sync_live.ex \
        test/emothe_web/live/admin/filemaker_sync_live_test.exs
git commit -m "feat: apply a FileMaker sync, one conflict at a time"
```

---

### Task 6: The bad-file guard, Spanish translations and the stale docs

**Files:**
- Test: `test/emothe_web/live/admin/filemaker_sync_live_test.exs`
- Create: `test/fixtures/filemaker/not_an_export.ndjson`
- Modify: `priv/gettext/es/LC_MESSAGES/default.po`, `priv/gettext/default.pot`
- Modify: `CLAUDE.md`
- Modify: `lib/emothe_web/live/admin/import_live.ex:20-24`

**Interfaces:**
- Consumes: the whole page from Tasks 4 and 5.
- Produces: nothing new. This task closes the trust boundary and the documentation.

- [ ] **Step 1: Write the failing test**

```elixir
  describe "a file that is not the export" do
    test "given a file with no FileMaker records then nothing is planned or written",
         %{conn: conn} do
      corpus()
      {:ok, lv, _html} = live(log_in_user(conn, admin_fixture()), ~p"/admin/filemaker")

      html = upload_and_preview(lv, "test/fixtures/filemaker/not_an_export.ndjson")

      assert html =~ t("No FileMaker records found in that file. Is it the right export?")
      refute has_element?(lv, "#changes")
      assert has_element?(lv, "#upload-form")
    end
  end
```

Create `test/fixtures/filemaker/not_an_export.ndjson` — valid NDJSON, no FileMaker layout:

```
{"hello":"world"}
{"another":"line"}
```

Without the `:no_records` guard this file plans cleanly as "all five plays are not in the published index" — a screen indistinguishable from real data loss. That is the whole reason the guard exists.

- [ ] **Step 2: Run the test to verify it fails or passes**

```bash
mix test test/emothe_web/live/admin/filemaker_sync_live_test.exs
```

Expected: PASS, if you implemented `read_plan/1` with the `:no_records` guard in Task 4 as written. **If it passes, that is fine — say so and move on.** The guard was specified with its own justification in Task 4; this step is the regression test that stops it being deleted as dead defensiveness later. If it fails, the guard is missing — add it now.

- [ ] **Step 3: Extract and translate the new strings**

```bash
mix gettext.extract --merge
```

Then open `priv/gettext/es/LC_MESSAGES/default.po` and translate every new `msgid` from this feature. **Check every entry marked `#, fuzzy`** — `mix gettext.extract --merge` fuzzy-matches new strings onto unrelated existing translations in this repo, and a wrong fuzzy match ships a Spanish string that says something else. Delete the `fuzzy` flag once you have written the real translation.

Strings needing Spanish (msgid → suggested msgstr):

| msgid | msgstr |
|---|---|
| `FileMaker sync` | `Sincronizar FileMaker` |
| `FileMaker` | `FileMaker` |
| `Upload the FileMaker export, review what it would change, then apply it.` | `Sube la exportación de FileMaker, revisa qué cambiaría y aplícalo.` |
| `Select the export` | `Selecciona la exportación` |
| `One .ndjson file, as exported from FileMaker.` | `Un archivo .ndjson, tal como lo exporta FileMaker.` |
| `Preview changes` | `Previsualizar cambios` |
| `%{count} play(s) to update` | `%{count} obra(s) por actualizar` |
| `Changes` | `Cambios` |
| `%{count} value(s) already set by a researcher` | `%{count} valor(es) ya establecido(s) por un investigador` |
| `These are left alone unless you tick them. For research metadata the export is a starting point, not the authority.` | `No se modifican salvo que los marques. Para los metadatos de investigación la exportación es un punto de partida, no la autoridad.` |
| `keep %{current}` | `mantener %{current}` |
| `the export says %{indexed}` | `la exportación dice %{indexed}` |
| `%{count} play(s) already match` | `%{count} obra(s) ya coinciden` |
| `%{count} play(s) are not in the published index` | `%{count} obra(s) no están en el índice publicado` |
| `Nothing is created for these. A play can be absent from the index and still have research metadata to fill, in which case it is listed above as well.` | `No se crea nada para estas. Una obra puede faltar en el índice y aun así tener metadatos de investigación por rellenar, en cuyo caso también aparece arriba.` |
| `Everything already matches the export.` | `Todo coincide ya con la exportación.` |
| `Apply` | `Aplicar` |
| `Discard` | `Descartar` |
| `Applied` | `Aplicado` |
| `Sync another export` | `Sincronizar otra exportación` |
| `Updated %{count} play(s).` | `%{count} obra(s) actualizada(s).` |
| `No FileMaker records found in that file. Is it the right export?` | `No se han encontrado registros de FileMaker en ese archivo. ¿Es la exportación correcta?` |
| `Cannot read the file` | `No se puede leer el archivo` |
| `(blank)` | `(vacío)` |
| `Historical time note` | `Nota del tiempo histórico` |
| `Only .ndjson files are accepted` | `Solo se aceptan archivos .ndjson` |
| `Upload one file at a time` | `Sube un archivo a la vez` |
| `Relationship` | `Relación` |
| `Parent play` | `Obra original` |

`Language`, `Historical time`, `Code`, `Title`, `Error`, `File is too large (max 20MB)` are already in the `.po` — reuse the existing entries rather than adding duplicates.

- [ ] **Step 4: Run the whole suite**

```bash
mix format && mix compile --warnings-as-errors && mix test
```

Expected: 0 failures. Translating a string is exactly what breaks a literal-English assertion, so if a test fails here it is asserting English somewhere and should be switched to `Gettext.gettext(EmotheWeb.Gettext, …)`.

- [ ] **Step 5: Fix the two stale documentation facts**

In `lib/emothe_web/live/admin/import_live.ex`, delete the `:breadcrumbs` assign at lines 20-24 — nothing reads it since breadcrumbs left the admin layout:

```elixir
     |> assign(:breadcrumbs, [
       %{label: gettext("Admin"), to: ~p"/admin/plays"},
       %{label: gettext("Plays"), to: ~p"/admin/plays"},
       %{label: gettext("Import TEI-XML")}
     ])
```

In `CLAUDE.md`:

1. Under **Routes → Admin**, add:
   `- `GET /admin/filemaker` - Sync the FileMaker export: upload, preview the diff, apply (`:import_filemaker`)`
2. Under **Access control**, extend the researcher/admin sentence so `:import_filemaker` is listed among the admin-only actions beside purge, user management, activity log, site deploy and the dashboard.
3. Under **What Still Needs To Be Done → High Priority**, the Fly.io bullet says the deployment configuration is still to write. `Dockerfile` and `fly.toml` both exist; what is left is setting the secrets and running `fly deploy`. Correct the bullet to say that.
4. Under **FileMaker import (S3-S8)** / the S2 roadmap bullets, note that the admin page at `/admin/filemaker` renders whatever `sets` and `conflicts` contain, so each later slice needs no change to it.

- [ ] **Step 6: Run the whole suite one last time and commit**

```bash
mix format && mix compile --warnings-as-errors && mix test
```

Expected: 0 failures.

```bash
git add priv/gettext CLAUDE.md lib/emothe_web/live/admin/import_live.ex \
        test/emothe_web/live/admin/filemaker_sync_live_test.exs \
        test/fixtures/filemaker/not_an_export.ndjson
git commit -m "feat: Spanish for the FileMaker sync page, and fix two stale docs"
```

---

## Verification before claiming done

Do not report this feature complete without pasting the output of each:

1. `mix test` — the whole suite, 0 failures.
2. `mix compile --warnings-as-errors` — clean.
3. `mix format --check-formatted` — clean.
4. A manual pass on a running server, because no test proves the page is usable:
   ```bash
   mix phx.server
   ```
   Sign in as an admin, open `http://localhost:4000/admin/filemaker`, upload
   `doc/w3emothe_T01_tituloEM.ndjson` (the real 1.8 MB / 649-line export, git-ignored — if it is
   not on this machine, say so rather than skipping the step silently). Confirm: the four buckets
   render, `EMOTHE0341` appears in both `missing` and `changes`, ticking a conflict and applying
   overwrites only that field, and `/admin/activity-log` shows the writes attributed to you rather
   than to nobody.
5. Confirm the sidebar shows **FileMaker** for an admin and not for a researcher.

## What this plan deliberately does not do

Nothing in `lib/emothe/import/filemaker.ex`, `lib/emothe/import/filemaker_sync.ex`, the schema, or
the mix task. No scheduled sync. No storing the export on disk or in `priv/`. No editing of field
values on this page — that is the play form. `place_of_action`, `composition_date`, `collection`,
`legacy_url`, `original_title` and `title_sort` are S2b–S2f and reuse this page unchanged.
