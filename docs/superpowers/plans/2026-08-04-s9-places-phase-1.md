# S9 Places (Phase 1) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** A corpus-global gazetteer of places with multilingual names, attached to plays as an ordered per-play index, editable in the admin, published on the public play page, and round-tripping through TEI.

**Architecture:** Three new tables in one new context (`Emothe.Places`) — `places` (the referent, self-referencing for containment), `place_names` (surface forms tagged by language), `play_places` (the play-level link, carrying `role`, `position`, `note`, `origin`). A `Places.Authority` behaviour with a Wikidata implementation and a test stub supplies coordinates and multilingual labels. Two admin pages share one LiveComponent form. TEI expresses the hierarchy as nested `<place>` inside `<listPlace>` and the play links as `<placeName ref>` inside `<setting>`, which keeps containers distinguishable from settings.

**Tech Stack:** Elixir 1.19.5 / OTP 28.1, Phoenix 1.8.3, LiveView 1.1.22, Ecto SQL 3.13 (Postgres, `binary_id` PKs), Tailwind 4 + DaisyUI, gettext, `req` 0.5 (already a dependency) with `Req.Test` for stubbing, Saxy + xml_builder for TEI, ExUnit.

**Spec:** `docs/superpowers/specs/2026-08-04-s9-places-design.md`

## Global Constraints

- **TDD is mandatory.** Failing test first, run it and watch it fail, minimal implementation, run it and watch it pass, then `mix test` (whole suite) before any completion claim. See the top of `CLAUDE.md`.
- **Run mix with the sandbox PATH:** `export PATH="/home/bogdan/.asdf/installs/erlang/28.1/bin:/home/bogdan/.asdf/installs/elixir/1.19.5-otp-28/bin:/usr/bin:/usr/local/bin:/bin:$PATH"` — asdf shims are bash scripts and do not work in the tool sandbox.
- `mix format` after every task. `mix compile --warnings-as-errors` before every commit.
- **Baseline suite: 299 tests passing.** Record the new total at the end of each task.
- **The default locale is `"es"`** (`config/config.exs:15`). Never assert literal English in a test — assert through `Gettext.gettext(EmotheWeb.Gettext, "…")`. A literal-English assertion passes only until Task 12 adds the translation.
- **`Emothe.Authz.can?/3` is the only authorization predicate.** Never compare `user.role` anywhere else.
- **Attribute maps use string keys.** `Places.create_place/1`, `update_place/2` and `link_place/3` take string-keyed maps, matching `Emothe.TestFixtures.play_fixture/1` and what LiveView forms submit.
- **No new dependency.** `req` is already in `mix.exs`; nothing else gets added.
- **`play_places` carries `origin`** (`"tei" | "manual" | "filemaker"`, validated against `Emothe.Catalogue.origins/0`). This is the standing S0b rule for any table an importer writes.
- **No `plays` column is added**, so `@platform_owned` in `lib/emothe/import/tei_parser.ex` needs no entry. Do not add `plays.place_of_action`.
- **No FileMaker code.** The `pub_LugAccion` import is a separate slice.

## Deviations from the spec, and why

Three, all visible rather than smuggled:

1. **Local pickers are `<select>`, not typeaheads.** The spec describes a typeahead for the parent place and for "add place to play". The gazetteer is a bounded list (tens to low hundreds), so a select is less code and better UX than a debounced search, and "no match" is covered by a `New place` button that opens the same form. The **Wikidata** search stays a typeahead, because that list is remote and unbounded.
2. **`PlaceFormComponent` is this repo's first `LiveComponent`.** Every other admin form is an inline form in a plain LiveView. A component is justified here because two pages need the identical form *and* its events; the alternative is duplicating create/update handlers in both LiveViews.
3. **The static-site renderer gets a places section and a `historical_time` row in the same task.** `Renderer.play_page/5` already renders sources, editors and verse info, but S2a never added `historical_time` — so adding places alone would leave a visibly inconsistent panel. The `historical_time` row is three lines and gets fixed while the file is open.

## File Structure

**New:**

| File | Responsibility |
|---|---|
| `priv/repo/migrations/*_create_places.exs` | The three tables and every index |
| `lib/emothe/places.ex` | The context: gazetteer CRUD, hierarchy helpers, play links |
| `lib/emothe/places/place.ex` | Place schema, `types/0`, `authorities/0` |
| `lib/emothe/places/place_name.ex` | PlaceName schema |
| `lib/emothe/places/play_place.ex` | PlayPlace schema, `roles/0` |
| `lib/emothe/places/authority.ex` | Behaviour, registry, `impl/0` |
| `lib/emothe/places/authority/wikidata.ex` | Wikidata search + fetch over `req` |
| `lib/emothe/places/authority/stub.ex` | Deterministic test implementation |
| `lib/emothe_web/live/admin/place_form_component.ex` | The shared modal form |
| `lib/emothe_web/live/admin/place_list_live.ex` | `/admin/places` |
| `lib/emothe_web/live/admin/play_places_live.ex` | `/admin/plays/:id/places` |
| `test/fixtures/wikidata/Q220.json` | Entity fixture |
| `test/fixtures/wikidata/search_roma.json` | Search-response fixture |

**Modified:**

| File | Change |
|---|---|
| `lib/emothe/authz.ex:30` | `manage_places` in `@researcher_actions` |
| `lib/emothe/catalogue/play.ex` | `has_many :play_places` |
| `lib/emothe/catalogue.ex:69-95` | preload `play_places` in the two `*_with_all!` readers |
| `lib/emothe_web/router.ex:—` | two `live` routes in the `:admin` live_session |
| `lib/emothe_web/components/layouts.ex:142` | context-bar tab; `:260` sidebar entry |
| `lib/emothe_web/play_labels.ex` | `place_type_label/1`, `place_role_label/1`, options helpers |
| `lib/emothe_web/live/play_show_live.ex:340,391` | `#meta-places` section + scroll-spy entry |
| `lib/emothe/export/static_site/renderer.ex:85` | `render_places/1` and the `historical_time` row |
| `lib/emothe/export/tei_xml.ex:281` | `<settingDesc>` in `build_profile_desc/1` |
| `lib/emothe/import/tei_parser.ex:267` | read `settingDesc`; `reset_tei_content/1` clears `"tei"` links |
| `test/support/fixtures.ex` | `place_fixture/1`, `play_place_fixture/2` |
| `config/test.exs` | `config :emothe, :place_authority, Emothe.Places.Authority.Stub` |
| `config/config.exs` | `config :emothe, :place_authority, Emothe.Places.Authority.Wikidata` |
| `priv/gettext/es/LC_MESSAGES/default.po` | every new string |

---

### Task 1: The `:manage_places` permission

`Authz.can?/3` is the only authorization predicate, and `sidebar_groups/1` filters menu items through it — so the action atom has to exist before any page can be linked. Researcher-level, decided in the spec's Authorization section: places are content, the destructive case is already blocked by a foreign key, and admin-only would make adding a place a prerequisite a researcher cannot satisfy.

**Files:**
- Modify: `lib/emothe/authz.ex:30-32`
- Test: `test/emothe/authz_test.exs:8-9`

**Interfaces:**
- Consumes: nothing.
- Produces: `Emothe.Authz.can?(user, :manage_places)` — true for an active researcher or admin, false otherwise. `Authz.actions/0` includes `:manage_places`.

- [ ] **Step 1: Write the failing test**

In `test/emothe/authz_test.exs`, add `manage_places` to the researcher list:

```elixir
  @researcher_actions ~w(view_admin manage_plays edit_content manage_editors
                         manage_sources manage_places import_tei download_export
                         archive_play)a
```

- [ ] **Step 2: Run it and watch it fail**

```bash
mix test test/emothe/authz_test.exs
```

Expected: FAIL — `expected researcher to be allowed manage_places`, and the same for the admin case.

- [ ] **Step 3: Add the action**

`lib/emothe/authz.ex`:

```elixir
  @researcher_actions ~w(view_admin manage_plays edit_content manage_editors
                         manage_sources manage_places import_tei download_export
                         archive_play)a
```

- [ ] **Step 4: Run it and watch it pass**

```bash
mix test test/emothe/authz_test.exs
```

Expected: PASS.

- [ ] **Step 5: Whole suite, format, commit**

```bash
mix test && mix format && mix compile --warnings-as-errors
git add lib/emothe/authz.ex test/emothe/authz_test.exs
git commit -m "feat: a :manage_places permission, researcher level"
```

---

### Task 2: Migration and schemas

Three tables and the four constraints that carry the design's guarantees: one place per authority entity, one preferred name per place per language, one link per play-place pair, and `:restrict` on both foreign keys into `places`.

The tests here go through `Repo` directly, because the context does not exist yet. They assert that a violated `:restrict` **raises** `Ecto.ConstraintError`; Task 3 is what turns that into a changeset error.

**Files:**
- Create: `priv/repo/migrations/<timestamp>_create_places.exs`
- Create: `lib/emothe/places/place.ex`, `lib/emothe/places/place_name.ex`, `lib/emothe/places/play_place.ex`
- Modify: `lib/emothe/catalogue/play.ex`
- Test: `test/emothe/places/schema_test.exs`

**Interfaces:**
- Consumes: `Emothe.Catalogue.origins/0` (returns `["tei", "manual", "filemaker"]`).
- Produces:
  - `Emothe.Places.Place` — fields `slug, type, parent_place_id, latitude, longitude, is_fictional, authority, authority_id, note`, virtual `play_count`; assocs `parent`, `children`, `names` (`on_replace: :delete`), `play_places`; `Place.types/0`, `Place.authorities/0`, `Place.changeset/2`.
  - `Emothe.Places.PlaceName` — `name, language, is_preferred, is_historical, position, place_id`; `PlaceName.changeset/2`.
  - `Emothe.Places.PlayPlace` — `role, position, note, origin, play_id, place_id`; `PlayPlace.roles/0`, `PlayPlace.changeset/2`.
  - `Emothe.Catalogue.Play` gains `has_many :play_places`.

- [ ] **Step 1: Generate the migration file**

```bash
mix ecto.gen.migration create_places
```

- [ ] **Step 2: Write the migration**

Replace the generated file's body:

```elixir
defmodule Emothe.Repo.Migrations.CreatePlaces do
  use Ecto.Migration

  def change do
    create table(:places, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :slug, :string, null: false
      add :type, :string, null: false
      add :parent_place_id, references(:places, type: :binary_id, on_delete: :restrict)
      add :latitude, :float
      add :longitude, :float
      add :is_fictional, :boolean, default: false, null: false
      add :authority, :string
      add :authority_id, :string
      add :note, :text

      timestamps(type: :utc_datetime)
    end

    create unique_index(:places, [:slug])
    create index(:places, [:parent_place_id])

    create unique_index(:places, [:authority, :authority_id],
             where: "authority_id IS NOT NULL"
           )

    create table(:place_names, primary_key: false) do
      add :id, :binary_id, primary_key: true

      add :place_id, references(:places, type: :binary_id, on_delete: :delete_all),
        null: false

      add :name, :string, null: false
      add :language, :string
      add :is_preferred, :boolean, default: false, null: false
      add :is_historical, :boolean, default: false, null: false
      add :position, :integer, default: 0

      timestamps(type: :utc_datetime)
    end

    create index(:place_names, [:place_id])

    create unique_index(:place_names, ["place_id", "coalesce(language, '')"],
             where: "is_preferred",
             name: :one_preferred_name_per_place_and_language
           )

    create table(:play_places, primary_key: false) do
      add :id, :binary_id, primary_key: true

      add :play_id, references(:plays, type: :binary_id, on_delete: :delete_all),
        null: false

      add :place_id, references(:places, type: :binary_id, on_delete: :restrict),
        null: false

      add :role, :string, default: "setting", null: false
      add :position, :integer, default: 0
      add :note, :text
      add :origin, :string, default: "manual", null: false

      timestamps(type: :utc_datetime)
    end

    create unique_index(:play_places, [:play_id, :place_id])
    create index(:play_places, [:place_id])
  end
end
```

- [ ] **Step 3: Migrate both databases**

```bash
mix ecto.migrate
MIX_ENV=test mix ecto.migrate
```

- [ ] **Step 4: Write the failing test**

Create `test/emothe/places/schema_test.exs`:

```elixir
defmodule Emothe.Places.SchemaTest do
  use Emothe.DataCase, async: true

  import Emothe.TestFixtures

  alias Emothe.Places.{Place, PlaceName, PlayPlace}
  alias Emothe.Repo

  defp insert_place(attrs \\ %{}) do
    attrs = Map.merge(%{"slug" => "p#{System.unique_integer([:positive])}", "type" => "city"}, attrs)
    {:ok, place} = %Place{} |> Place.changeset(attrs) |> Repo.insert()
    place
  end

  defp insert_name(place, attrs) do
    %PlaceName{}
    |> PlaceName.changeset(Map.put(attrs, "place_id", place.id))
    |> Repo.insert()
  end

  describe "places" do
    test "a slug is unique across the corpus" do
      insert_place(%{"slug" => "roma"})

      assert {:error, changeset} =
               %Place{} |> Place.changeset(%{"slug" => "roma", "type" => "city"}) |> Repo.insert()

      assert "has already been taken" in errors_on(changeset).slug
    end

    test "an unknown type is rejected" do
      changeset = Place.changeset(%Place{}, %{"slug" => "x", "type" => "planet"})
      assert "is invalid" in errors_on(changeset).type
    end

    test "coordinates outside the globe are rejected" do
      changeset =
        Place.changeset(%Place{}, %{
          "slug" => "x",
          "type" => "city",
          "latitude" => "91.0",
          "longitude" => "0.0"
        })

      assert errors_on(changeset).latitude != []
    end

    test "one authority entity cannot become two places" do
      insert_place(%{"authority" => "wikidata", "authority_id" => "Q220"})

      assert {:error, changeset} =
               %Place{}
               |> Place.changeset(%{
                 "slug" => "roma-2",
                 "type" => "city",
                 "authority" => "wikidata",
                 "authority_id" => "Q220"
               })
               |> Repo.insert()

      assert errors_on(changeset).authority_id != []
    end

    test "two places with no authority link are both allowed" do
      insert_place(%{})
      assert %Place{} = insert_place(%{})
    end
  end

  describe "place_names" do
    test "one preferred name per language, and a second in the same language is refused" do
      place = insert_place()
      assert {:ok, _} = insert_name(place, %{"name" => "Roma", "language" => "es", "is_preferred" => true})

      assert {:error, changeset} =
               insert_name(place, %{"name" => "Rroma", "language" => "es", "is_preferred" => true})

      assert errors_on(changeset).is_preferred != []
    end

    test "a preferred name in another language is allowed" do
      place = insert_place()
      {:ok, _} = insert_name(place, %{"name" => "Roma", "language" => "es", "is_preferred" => true})

      assert {:ok, _} =
               insert_name(place, %{"name" => "Rome", "language" => "en", "is_preferred" => true})
    end

    test "two preferred language-neutral names are refused" do
      place = insert_place()
      {:ok, _} = insert_name(place, %{"name" => "Miseno", "is_preferred" => true})
      assert {:error, _} = insert_name(place, %{"name" => "Misenum", "is_preferred" => true})
    end

    test "deleting a place deletes its names" do
      place = insert_place()
      {:ok, _} = insert_name(place, %{"name" => "Roma", "language" => "es"})
      Repo.delete!(place)
      assert Repo.aggregate(PlaceName, :count, :id) == 0
    end
  end

  describe "play_places" do
    test "a play links a place once" do
      play = play_fixture()
      place = insert_place()
      attrs = %{"play_id" => play.id, "place_id" => place.id}

      {:ok, _} = %PlayPlace{} |> PlayPlace.changeset(attrs) |> Repo.insert()

      assert {:error, changeset} = %PlayPlace{} |> PlayPlace.changeset(attrs) |> Repo.insert()
      assert errors_on(changeset) != %{}
    end

    test "an unknown role is rejected" do
      changeset = PlayPlace.changeset(%PlayPlace{}, %{"role" => "birthplace"})
      assert "is invalid" in errors_on(changeset).role
    end

    test "an unknown origin is rejected" do
      changeset = PlayPlace.changeset(%PlayPlace{}, %{"origin" => "guesswork"})
      assert "is invalid" in errors_on(changeset).origin
    end

    test "a referenced place cannot be deleted" do
      play = play_fixture()
      place = insert_place()

      {:ok, _} =
        %PlayPlace{}
        |> PlayPlace.changeset(%{"play_id" => play.id, "place_id" => place.id})
        |> Repo.insert()

      assert_raise Ecto.ConstraintError, fn -> Repo.delete!(place) end
    end

    test "a place that is a parent cannot be deleted" do
      parent = insert_place(%{"slug" => "italia", "type" => "country"})
      _child = insert_place(%{"parent_place_id" => parent.id})

      assert_raise Ecto.ConstraintError, fn -> Repo.delete!(parent) end
    end
  end
end
```

- [ ] **Step 5: Run it and watch it fail**

```bash
mix test test/emothe/places/schema_test.exs
```

Expected: FAIL — `module Emothe.Places.Place is not available`.

- [ ] **Step 6: Write the three schemas**

`lib/emothe/places/place.ex`:

```elixir
defmodule Emothe.Places.Place do
  @moduledoc """
  A place: one stable referent, real or fictional.

  Deliberately has **no name column** — every surface form lives in `place_names`,
  because a denormalised copy and its child row have no constraint keeping them in
  step and drift silently. `Emothe.Places.display_name/2` picks the one to show.

  Containment is `parent_place_id`, and depth is opportunistic: a place may have no
  parent at all. "Woods in Transylvania" is a row with a parent, no coordinates and a
  note — absent coordinates are what say "not pinned", so there is no extra column for
  it. `is_fictional` means something narrower: no real referent, as in Atlántida.
  """

  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  # One axis only: every term answers "what kind of geographic feature is this".
  # `port` was rejected because it describes a function, not a feature class, and
  # Naples is both a city and a port. Adding a term is three lines; removing one is a
  # data migration, so the list errs toward too few.
  @types ~w(continent country province region district city town
            building forest river lake sea island mountain other)

  @authorities ~w(wikidata geonames tgn pleiades)

  def types, do: @types
  def authorities, do: @authorities

  schema "places" do
    field :slug, :string
    field :type, :string
    field :latitude, :float
    field :longitude, :float
    field :is_fictional, :boolean, default: false
    field :authority, :string
    field :authority_id, :string
    field :note, :string

    field :play_count, :integer, virtual: true

    belongs_to :parent, __MODULE__, foreign_key: :parent_place_id
    has_many :children, __MODULE__, foreign_key: :parent_place_id
    has_many :names, Emothe.Places.PlaceName, on_replace: :delete
    has_many :play_places, Emothe.Places.PlayPlace

    timestamps(type: :utc_datetime)
  end

  def changeset(place, attrs) do
    place
    |> cast(attrs, [
      :slug,
      :type,
      :parent_place_id,
      :latitude,
      :longitude,
      :is_fictional,
      :authority,
      :authority_id,
      :note
    ])
    |> validate_required([:slug, :type])
    |> validate_inclusion(:type, @types)
    |> validate_inclusion(:authority, @authorities)
    |> validate_number(:latitude, greater_than_or_equal_to: -90, less_than_or_equal_to: 90)
    |> validate_number(:longitude, greater_than_or_equal_to: -180, less_than_or_equal_to: 180)
    |> validate_not_self_parent()
    |> unique_constraint(:slug)
    |> unique_constraint([:authority, :authority_id],
      name: :places_authority_authority_id_index,
      error_key: :authority_id,
      message: "is already linked to another place"
    )
    |> foreign_key_constraint(:parent_place_id)
  end

  defp validate_not_self_parent(changeset) do
    case {get_field(changeset, :id), get_change(changeset, :parent_place_id)} do
      {id, id} when not is_nil(id) -> add_error(changeset, :parent_place_id, "cannot be itself")
      _ -> changeset
    end
  end
end
```

`lib/emothe/places/place_name.ex`:

```elixir
defmodule Emothe.Places.PlaceName do
  @moduledoc """
  One surface form of a place, tagged with a language.

  `İstanbul`, `Constantinopla`, `Constantinople` and `Bizancio` are four of these on
  one place. `is_preferred` is unique per place **per language**, enforced by a partial
  index, so a Spanish UI can prefer `Roma` while an English one prefers `Rome`.
  """

  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "place_names" do
    field :name, :string
    field :language, :string
    field :is_preferred, :boolean, default: false
    field :is_historical, :boolean, default: false
    field :position, :integer, default: 0

    belongs_to :place, Emothe.Places.Place

    timestamps(type: :utc_datetime)
  end

  def changeset(place_name, attrs) do
    place_name
    |> cast(attrs, [:name, :language, :is_preferred, :is_historical, :position, :place_id])
    |> validate_required([:name])
    |> unique_constraint(:is_preferred,
      name: :one_preferred_name_per_place_and_language,
      message: "another name is already preferred for this language"
    )
  end
end
```

`lib/emothe/places/play_place.ex`:

```elixir
defmodule Emothe.Places.PlayPlace do
  @moduledoc """
  A play's link to a place — the Phase 1 deliverable, a play-level place index.

  `role` distinguishes where the play is set from what it merely names; the FileMaker
  export encodes the same distinction with parentheses, `( Miseno )`. In-text mentions
  are Phase 2 and a different table.

  Carries `origin` because the TEI importer writes these rows: a re-import deletes only
  its own `"tei"` links and never touches a hand-entered one. Standing S0b rule.
  """

  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  @roles ~w(setting mentioned)

  def roles, do: @roles

  schema "play_places" do
    field :role, :string, default: "setting"
    field :position, :integer, default: 0
    field :note, :string
    field :origin, :string, default: "manual"

    belongs_to :play, Emothe.Catalogue.Play
    belongs_to :place, Emothe.Places.Place

    timestamps(type: :utc_datetime)
  end

  def changeset(play_place, attrs) do
    play_place
    |> cast(attrs, [:role, :position, :note, :origin, :play_id, :place_id])
    |> validate_required([:play_id, :place_id])
    |> validate_inclusion(:role, @roles)
    |> validate_inclusion(:origin, Emothe.Catalogue.origins())
    |> unique_constraint([:play_id, :place_id],
      error_key: :place_id,
      message: "is already linked to this play"
    )
    |> foreign_key_constraint(:place_id)
  end
end
```

- [ ] **Step 7: Add the association to `Play`**

In `lib/emothe/catalogue/play.ex`, beside the other `has_many` declarations:

```elixir
    has_many :play_places, Emothe.Places.PlayPlace
```

- [ ] **Step 8: Run it and watch it pass**

```bash
mix test test/emothe/places/schema_test.exs
```

Expected: PASS, 14 tests.

- [ ] **Step 9: Whole suite, format, commit**

```bash
mix test && mix format && mix compile --warnings-as-errors
git add priv/repo/migrations lib/emothe/places lib/emothe/catalogue/play.ex test/emothe/places
git commit -m "feat: places, place_names and play_places tables"
```

---

### Task 3: `Emothe.Places` — gazetteer CRUD

The context functions that create, read, update and delete a place, plus the two derived values everything else depends on: `slugify/1` and `display_name/2`. This is also where the `:restrict` violations become changeset errors instead of exceptions.

**Files:**
- Create: `lib/emothe/places.ex`
- Test: `test/emothe/places_test.exs`
- Modify: `test/support/fixtures.ex`

**Interfaces:**
- Consumes: `Place`, `PlaceName`, `PlayPlace` from Task 2.
- Produces:
  - `Places.slugify(String.t()) :: String.t()`
  - `Places.change_place(%Place{}, map()) :: Ecto.Changeset.t()`
  - `Places.create_place(map()) :: {:ok, %Place{}} | {:error, Ecto.Changeset.t()}`
  - `Places.update_place(%Place{}, map()) :: {:ok, %Place{}} | {:error, Ecto.Changeset.t()}`
  - `Places.delete_place(%Place{}) :: {:ok, %Place{}} | {:error, Ecto.Changeset.t()}`
  - `Places.get_place!(binary()) :: %Place{}` — names and parent preloaded
  - `Places.list_places(keyword()) :: [%Place{}]` — names preloaded, `play_count` set, sorted
  - `Places.display_name(%Place{}, String.t()) :: String.t()`
  - `Emothe.TestFixtures.place_fixture(map()) :: %Place{}`

- [ ] **Step 1: Write the failing test**

Create `test/emothe/places_test.exs`:

```elixir
defmodule Emothe.PlacesTest do
  use Emothe.DataCase, async: true

  import Emothe.TestFixtures

  alias Emothe.Places

  describe "slugify/1" do
    test "strips accents and punctuation" do
      assert Places.slugify("Atlántida") == "atlantida"
      assert Places.slugify("La Cortigiana (1525)") == "la-cortigiana-1525"
      assert Places.slugify("İstanbul") == "istanbul"
    end

    test "a name with no latin characters still yields a usable slug" do
      assert Places.slugify("……") == "place"
    end
  end

  describe "create_place/1" do
    test "requires at least one name" do
      assert {:error, changeset} = Places.create_place(%{"type" => "city", "names" => []})
      assert errors_on(changeset).names != []
    end

    test "derives the slug from the first name when none is given" do
      {:ok, place} =
        Places.create_place(%{
          "type" => "city",
          "names" => %{"0" => %{"name" => "Roma", "language" => "es", "is_preferred" => "true"}}
        })

      assert place.slug == "roma"
    end

    test "a colliding slug is suffixed rather than rejected" do
      _first = place_fixture(%{"name" => "Woods"})
      second = place_fixture(%{"name" => "Woods"})

      assert second.slug == "woods-2"
    end

    test "an explicit slug is respected" do
      place = place_fixture(%{"name" => "Roma", "slug" => "roma-antica"})
      assert place.slug == "roma-antica"
    end
  end

  describe "display_name/2" do
    setup do
      place =
        place_fixture(%{
          "name" => "Roma",
          "names" => [
            %{"name" => "Roma", "language" => "es", "is_preferred" => "true"},
            %{"name" => "Rome", "language" => "en", "is_preferred" => "true"},
            %{"name" => "Roma antica", "language" => "it"}
          ]
        })

      %{place: Places.get_place!(place.id)}
    end

    test "prefers the preferred name in the requested locale", %{place: place} do
      assert Places.display_name(place, "es") == "Roma"
      assert Places.display_name(place, "en") == "Rome"
    end

    test "falls back to a non-preferred name in the locale", %{place: place} do
      assert Places.display_name(place, "it") == "Roma antica"
    end

    test "falls back to any preferred name for an unknown locale", %{place: place} do
      assert Places.display_name(place, "de") in ["Roma", "Rome"]
    end
  end

  describe "update_place/2" do
    test "a place cannot become its own parent" do
      place = place_fixture(%{"name" => "Roma"})

      assert {:error, changeset} =
               Places.update_place(place, %{"parent_place_id" => place.id})

      assert errors_on(changeset).parent_place_id != []
    end

    test "a parent cycle is refused" do
      europe = place_fixture(%{"name" => "Europa", "type" => "continent"})
      italy = place_fixture(%{"name" => "Italia", "type" => "country", "parent_place_id" => europe.id})

      assert {:error, changeset} = Places.update_place(europe, %{"parent_place_id" => italy.id})
      assert errors_on(changeset).parent_place_id != []
    end
  end

  describe "delete_place/1" do
    test "a place used by a play is refused with a readable message" do
      play = play_fixture()
      place = place_fixture(%{"name" => "Roma"})
      {:ok, _} = Places.link_place(play.id, place.id, %{})

      assert {:error, changeset} = Places.delete_place(place)
      assert "is still used by one or more plays" in errors_on(changeset).play_places
    end

    test "a place that is a parent is refused" do
      parent = place_fixture(%{"name" => "Italia", "type" => "country"})
      _child = place_fixture(%{"name" => "Roma", "parent_place_id" => parent.id})

      assert {:error, changeset} = Places.delete_place(parent)
      assert "is the parent of other places" in errors_on(changeset).children
    end

    test "an unreferenced place is deleted" do
      place = place_fixture(%{"name" => "Roma"})
      assert {:ok, _} = Places.delete_place(place)
    end
  end

  describe "list_places/1" do
    test "sorts by display name, ignoring accents, and carries the play count" do
      play = play_fixture()
      zaragoza = place_fixture(%{"name" => "Zaragoza"})
      alava = place_fixture(%{"name" => "Álava"})
      {:ok, _} = Places.link_place(play.id, alava.id, %{})

      names = Places.list_places() |> Enum.map(&Places.display_name(&1, "es"))
      assert names == ["Álava", "Zaragoza"]

      counts = Map.new(Places.list_places(), &{&1.id, &1.play_count})
      assert counts[alava.id] == 1
      assert counts[zaragoza.id] == 0
    end
  end
end
```

- [ ] **Step 2: Add the fixture**

In `test/support/fixtures.ex`, add `Emothe.Places` to the aliases at the top and append:

```elixir
  @doc """
  A place with one or more names. `"name"` is shorthand for a single preferred
  Spanish name; pass `"names"` for the full list.
  """
  def place_fixture(attrs \\ %{}) do
    {name, attrs} = Map.pop(attrs, "name")

    names =
      Map.get(attrs, "names") ||
        [%{"name" => name || "Place #{System.unique_integer([:positive])}",
           "language" => "es",
           "is_preferred" => "true"}]

    attrs =
      attrs
      |> Map.put_new("type", "city")
      |> Map.put("names", names)

    {:ok, place} = Emothe.Places.create_place(attrs)
    place
  end

  def play_place_fixture(play, place, attrs \\ %{}) do
    {:ok, play_place} = Emothe.Places.link_place(play.id, place.id, attrs)
    play_place
  end
```

- [ ] **Step 3: Run it and watch it fail**

```bash
mix test test/emothe/places_test.exs
```

Expected: FAIL — `function Emothe.Places.slugify/1 is undefined (module Emothe.Places is not available)`.

- [ ] **Step 4: Write the context**

Create `lib/emothe/places.ex`. `link_place/3` is stubbed minimally here so the delete tests can reference it; Task 5 fills out the rest of the play-link API.

```elixir
defmodule Emothe.Places do
  @moduledoc """
  The corpus-global gazetteer: places, their names, and the plays that reference them.

  Places are shared across every play, which is what makes "every play set in Italy"
  answerable — and also why a delete is constrained rather than cascading. See
  `docs/superpowers/specs/2026-08-04-s9-places-design.md`.
  """

  import Ecto.Query

  alias Ecto.Changeset
  alias Emothe.Places.{Place, PlaceName, PlayPlace}
  alias Emothe.Repo

  @name_order [desc: :is_preferred, asc: :position, asc: :name]

  # --- Places ---

  def change_place(%Place{} = place, attrs \\ %{}) do
    place
    |> Place.changeset(attrs)
    |> Changeset.cast_assoc(:names,
      required: true,
      required_message: "at least one name is required",
      sort_param: :names_order,
      drop_param: :names_delete
    )
  end

  def create_place(attrs) do
    %Place{}
    |> change_place(ensure_slug(attrs, nil))
    |> Repo.insert()
  end

  def update_place(%Place{} = place, attrs) do
    place
    |> Repo.preload(:names)
    |> change_place(ensure_slug(attrs, place))
    |> reject_parent_cycle(place)
    |> Repo.update()
  end

  def delete_place(%Place{} = place) do
    place
    |> Changeset.change()
    |> Changeset.no_assoc_constraint(:play_places,
      message: "is still used by one or more plays"
    )
    |> Changeset.no_assoc_constraint(:children, message: "is the parent of other places")
    |> Repo.delete()
  end

  def get_place!(id) do
    Place
    |> Repo.get!(id)
    |> Repo.preload([:parent, names: from(n in PlaceName, order_by: ^@name_order)])
  end

  def list_places(opts \\ []) do
    locale = opts[:locale] || "es"

    counts =
      PlayPlace
      |> group_by([pp], pp.place_id)
      |> select([pp], {pp.place_id, count(pp.id)})
      |> Repo.all()
      |> Map.new()

    Place
    |> Repo.all()
    |> Repo.preload(names: from(n in PlaceName, order_by: ^@name_order))
    |> Enum.map(&%{&1 | play_count: Map.get(counts, &1.id, 0)})
    |> Enum.sort_by(&slugify(display_name(&1, locale)))
  end

  @doc """
  The name to print. A fallback chain, which is what the per-language `is_preferred`
  index makes possible: preferred-in-locale, any-in-locale, preferred-anywhere, first.
  """
  def display_name(%Place{names: names}, locale \\ "es") when is_list(names) do
    find = fn fun -> Enum.find(names, fun) end

    name =
      find.(&(&1.is_preferred and &1.language == locale)) ||
        find.(&(&1.language == locale)) ||
        find.(& &1.is_preferred) ||
        List.first(names)

    if name, do: name.name, else: ""
  end

  @doc """
  A URL- and `xml:id`-safe form of a name. Latin letters and digits only, so it is a
  legal TEI `xml:id` in any language the corpus uses.
  """
  def slugify(name) do
    slug =
      name
      |> to_string()
      |> :unicode.characters_to_nfd_binary()
      |> String.replace(~r/[^\x00-\x7F]/u, "")
      |> String.downcase()
      |> String.replace(~r/[^a-z0-9]+/, "-")
      |> String.trim("-")

    if slug == "", do: "place", else: slug
  end

  # A blank slug is derived from the first name; a taken one gets -2, -3, … The suffix
  # is a last resort, not a way to hide a duplicate — the form warns before it is used.
  defp ensure_slug(attrs, place) do
    case attrs["slug"] do
      slug when is_binary(slug) and slug != "" ->
        attrs

      _ ->
        case first_name(attrs["names"]) do
          nil -> attrs
          name -> Map.put(attrs, "slug", unique_slug(slugify(name), place))
        end
    end
  end

  defp first_name(names) when is_list(names), do: names |> List.first() |> extract_name()

  defp first_name(names) when is_map(names) do
    names |> Enum.sort_by(fn {k, _} -> k end) |> List.first() |> then(&elem(&1 || {nil, nil}, 1)) |> extract_name()
  end

  defp first_name(_), do: nil

  defp extract_name(%{"name" => name}) when is_binary(name) and name != "", do: name
  defp extract_name(_), do: nil

  defp unique_slug(base, place) do
    taken =
      Place
      |> where([p], like(p.slug, ^"#{base}%"))
      |> then(fn q -> if place, do: where(q, [p], p.id != ^place.id), else: q end)
      |> select([p], p.slug)
      |> Repo.all()
      |> MapSet.new()

    if MapSet.member?(taken, base) do
      Enum.find_value(2..100, "#{base}-#{System.unique_integer([:positive])}", fn n ->
        candidate = "#{base}-#{n}"
        if MapSet.member?(taken, candidate), do: nil, else: candidate
      end)
    else
      base
    end
  end

  @doc """
  True when `place` already exists under a name matching `name`. The form calls this to
  warn about a probable duplicate before the slug gets silently suffixed.
  """
  def find_by_name(name) do
    slug = slugify(name)

    PlaceName
    |> join(:inner, [n], p in assoc(n, :place))
    |> where([n], fragment("lower(?) = lower(?)", n.name, ^name))
    |> or_where([n, p], p.slug == ^slug)
    |> select([n, p], p)
    |> limit(1)
    |> Repo.one()
    |> case do
      nil -> nil
      place -> get_place!(place.id)
    end
  end

  # Setting a parent that is a descendant would make `ancestors/2` walk forever. The
  # walk is bounded anyway, but a refused write is better than a truncated breadcrumb.
  defp reject_parent_cycle(changeset, %Place{id: id}) do
    case Changeset.get_change(changeset, :parent_place_id) do
      nil ->
        changeset

      parent_id ->
        if id in ancestor_ids(parent_id) do
          Changeset.add_error(changeset, :parent_place_id, "would create a loop")
        else
          changeset
        end
    end
  end

  defp ancestor_ids(nil), do: []

  defp ancestor_ids(id) do
    Enum.reduce_while(1..10, {id, []}, fn _, {current, acc} ->
      case Repo.one(from p in Place, where: p.id == ^current, select: p.parent_place_id) do
        nil -> {:halt, {nil, [current | acc]}}
        parent -> {:cont, {parent, [current | acc]}}
      end
    end)
    |> elem(1)
  end

  # --- Play links (completed in Task 5) ---

  def link_place(play_id, place_id, attrs) do
    attrs
    |> Map.merge(%{"play_id" => play_id, "place_id" => place_id})
    |> then(&PlayPlace.changeset(%PlayPlace{}, &1))
    |> Repo.insert()
  end
end
```

- [ ] **Step 5: Run it and watch it pass**

```bash
mix test test/emothe/places_test.exs
```

Expected: PASS, 14 tests.

- [ ] **Step 6: Whole suite, format, commit**

```bash
mix test && mix format && mix compile --warnings-as-errors
git add lib/emothe/places.ex test/emothe/places_test.exs test/support/fixtures.ex
git commit -m "feat: the Places context, with slug derivation and a guarded delete"
```

---

### Task 4: Hierarchy, search, and find-or-create

Breadcrumbs are built from one full-gazetteer load rather than by walking parents with queries — the table is a hundred rows, so this is one query and no N+1. `find_or_create_by_slug/1` is what both importers call, and it **never overwrites** an existing place.

**Files:**
- Modify: `lib/emothe/places.ex`
- Test: `test/emothe/places_test.exs`

**Interfaces:**
- Consumes: Task 3's `Places` functions.
- Produces:
  - `Places.gazetteer() :: %{binary() => %Place{}}`
  - `Places.ancestors(%Place{}, map()) :: [%Place{}]` — root first, excludes the place itself
  - `Places.breadcrumb(%Place{}, map(), String.t()) :: String.t()`
  - `Places.search_names(String.t(), keyword()) :: [%Place{}]`
  - `Places.find_or_create_by_slug(map()) :: {:ok, %Place{}, :created | :existing} | {:error, Ecto.Changeset.t()}`

- [ ] **Step 1: Write the failing test**

Append to `test/emothe/places_test.exs`:

```elixir
  describe "hierarchy" do
    setup do
      europe = place_fixture(%{"name" => "Europa", "type" => "continent"})

      romania =
        place_fixture(%{"name" => "Rumanía", "type" => "country", "parent_place_id" => europe.id})

      transylvania =
        place_fixture(%{
          "name" => "Transilvania",
          "type" => "region",
          "parent_place_id" => romania.id
        })

      woods =
        place_fixture(%{
          "name" => "Bosque",
          "type" => "forest",
          "parent_place_id" => transylvania.id
        })

      %{europe: europe, woods: woods}
    end

    test "ancestors are returned root first", %{woods: woods, europe: europe} do
      gazetteer = Places.gazetteer()
      ancestors = Places.ancestors(gazetteer[woods.id], gazetteer)

      assert Enum.map(ancestors, & &1.id) |> List.first() == europe.id
      assert length(ancestors) == 3
    end

    test "a breadcrumb reads outward from the place", %{woods: woods} do
      gazetteer = Places.gazetteer()

      assert Places.breadcrumb(gazetteer[woods.id], gazetteer, "es") ==
               "Bosque, Transilvania, Rumanía, Europa"
    end

    test "a place with no parent is its own breadcrumb", %{europe: europe} do
      gazetteer = Places.gazetteer()
      assert Places.breadcrumb(gazetteer[europe.id], gazetteer, "es") == "Europa"
    end
  end

  describe "search_names/2" do
    test "matches a name variant that is not the preferred one" do
      place =
        place_fixture(%{
          "names" => [
            %{"name" => "Constantinopla", "language" => "es", "is_preferred" => "true"},
            %{"name" => "İstanbul", "language" => "tr"}
          ]
        })

      assert [found] = Places.search_names("istanbul")
      assert found.id == place.id
    end

    test "is case insensitive and matches a fragment" do
      place = place_fixture(%{"name" => "Alexandría"})
      assert [found] = Places.search_names("ALEX")
      assert found.id == place.id
    end

    test "an empty term returns nothing" do
      place_fixture(%{"name" => "Roma"})
      assert Places.search_names("") == []
    end
  end

  describe "find_or_create_by_slug/1" do
    test "creates a place the first time and reuses it the second" do
      attrs = %{
        "slug" => "roma",
        "type" => "city",
        "names" => [%{"name" => "Roma", "language" => "es", "is_preferred" => "true"}]
      }

      assert {:ok, first, :created} = Places.find_or_create_by_slug(attrs)
      assert {:ok, second, :existing} = Places.find_or_create_by_slug(attrs)
      assert first.id == second.id
    end

    test "never overwrites the existing place" do
      curated = place_fixture(%{"name" => "Roma", "slug" => "roma", "note" => "Curated note"})

      {:ok, found, :existing} =
        Places.find_or_create_by_slug(%{
          "slug" => "roma",
          "type" => "town",
          "note" => "From a stale file",
          "names" => [%{"name" => "Rooma", "language" => "es", "is_preferred" => "true"}]
        })

      assert found.id == curated.id
      assert found.note == "Curated note"
      assert found.type == "city"
      assert Places.display_name(found, "es") == "Roma"
    end
  end
```

- [ ] **Step 2: Run it and watch it fail**

```bash
mix test test/emothe/places_test.exs
```

Expected: FAIL — `function Emothe.Places.gazetteer/0 is undefined or private`.

- [ ] **Step 3: Implement**

Add to `lib/emothe/places.ex`, above the "Play links" comment:

```elixir
  @doc """
  Every place, keyed by id, with names preloaded. Feeds `ancestors/2` and
  `breadcrumb/3` so a page walks the tree in memory instead of issuing a query per
  level.

  ponytail: one full load is right at a hundred places. Past a few thousand, replace
  with a recursive CTE returning only the requested place's chain.
  """
  def gazetteer do
    Place
    |> Repo.all()
    |> Repo.preload(names: from(n in PlaceName, order_by: ^@name_order))
    |> Map.new(&{&1.id, &1})
  end

  @doc "The containing places, outermost first. Bounded, so a data loop cannot hang a page."
  def ancestors(%Place{} = place, gazetteer) do
    Enum.reduce_while(1..10, {place.parent_place_id, []}, fn _, {id, acc} ->
      case id && Map.get(gazetteer, id) do
        nil -> {:halt, {nil, acc}}
        parent -> {:cont, {parent.parent_place_id, [parent | acc]}}
      end
    end)
    |> elem(1)
  end

  @doc ~S(The place and its containers, `"Bosque, Transilvania, Rumanía, Europa"`.)
  def breadcrumb(%Place{} = place, gazetteer, locale \\ "es") do
    [place | Enum.reverse(ancestors(place, gazetteer))]
    |> Enum.map(&display_name(&1, locale))
    |> Enum.reject(&(&1 == ""))
    |> Enum.join(", ")
  end

  @doc """
  Places with any name matching `term`, in any language. Searching every variant is why
  the names are normalised: typing `Istanbul` has to find the place whose preferred
  form is `Constantinopla`, or two curators will each create one.
  """
  def search_names(term, opts \\ [])
  def search_names(term, _opts) when term in [nil, ""], do: []

  def search_names(term, opts) do
    pattern = "%#{String.replace(term, ~r/[%_]/, "")}%"

    PlaceName
    |> join(:inner, [n], p in assoc(n, :place))
    |> where([n], ilike(n.name, ^pattern))
    |> select([n, p], p)
    |> distinct(true)
    |> limit(^(opts[:limit] || 20))
    |> Repo.all()
    |> Repo.preload(names: from(n in PlaceName, order_by: ^@name_order))
  end

  @doc """
  For importers. An existing slug is returned untouched — the gazetteer is curated and
  the file may be stale — so the caller can report what it left alone.
  """
  def find_or_create_by_slug(%{"slug" => slug} = attrs) do
    case Repo.get_by(Place, slug: slug) do
      nil ->
        case create_place(attrs) do
          {:ok, place} -> {:ok, get_place!(place.id), :created}
          {:error, changeset} -> {:error, changeset}
        end

      %Place{id: id} ->
        {:ok, get_place!(id), :existing}
    end
  end
```

- [ ] **Step 4: Run it and watch it pass**

```bash
mix test test/emothe/places_test.exs
```

Expected: PASS, 22 tests.

- [ ] **Step 5: Whole suite, format, commit**

```bash
mix test && mix format && mix compile --warnings-as-errors
git add lib/emothe/places.ex test/emothe/places_test.exs
git commit -m "feat: place hierarchy, name search and find-or-create for importers"
```

---

### Task 5: The play-level place index API

`link_place/3` already exists in skeleton form. This completes the link API: listing in order, updating role and note, unlinking, and reordering.

**Files:**
- Modify: `lib/emothe/places.ex`
- Test: `test/emothe/places_test.exs`

**Interfaces:**
- Consumes: Task 3–4 `Places` functions, `PlayPlace` from Task 2.
- Produces:
  - `Places.list_play_places(binary()) :: [%PlayPlace{}]` — `place` and its `names` preloaded, ordered by `position`
  - `Places.link_place(binary(), binary(), map()) :: {:ok, %PlayPlace{}} | {:error, Ecto.Changeset.t()}` — appends at the end
  - `Places.change_play_place(%PlayPlace{}, map()) :: Ecto.Changeset.t()`
  - `Places.update_play_place(%PlayPlace{}, map()) :: {:ok, %PlayPlace{}} | {:error, Ecto.Changeset.t()}`
  - `Places.get_play_place!(binary()) :: %PlayPlace{}`
  - `Places.unlink_place(%PlayPlace{}) :: {:ok, %PlayPlace{}}`
  - `Places.move_play_place(%PlayPlace{}, :up | :down) :: :ok`
  - `Places.delete_tei_play_places(binary()) :: {integer(), nil}`

- [ ] **Step 1: Write the failing test**

Append to `test/emothe/places_test.exs`:

```elixir
  describe "play links" do
    setup do
      play = play_fixture()
      roma = place_fixture(%{"name" => "Roma"})
      miseno = place_fixture(%{"name" => "Miseno"})
      %{play: play, roma: roma, miseno: miseno}
    end

    test "linking appends at the end", %{play: play, roma: roma, miseno: miseno} do
      {:ok, first} = Places.link_place(play.id, roma.id, %{})
      {:ok, second} = Places.link_place(play.id, miseno.id, %{"role" => "mentioned"})

      assert first.position == 0
      assert second.position == 1
      assert second.role == "mentioned"
      assert first.origin == "manual"
    end

    test "listing returns them in position order with the place preloaded", %{
      play: play,
      roma: roma,
      miseno: miseno
    } do
      {:ok, _} = Places.link_place(play.id, roma.id, %{})
      {:ok, _} = Places.link_place(play.id, miseno.id, %{})

      assert [one, two] = Places.list_play_places(play.id)
      assert Places.display_name(one.place, "es") == "Roma"
      assert Places.display_name(two.place, "es") == "Miseno"
    end

    test "a place cannot be linked to the same play twice", %{play: play, roma: roma} do
      {:ok, _} = Places.link_place(play.id, roma.id, %{})

      assert {:error, changeset} = Places.link_place(play.id, roma.id, %{})
      assert "is already linked to this play" in errors_on(changeset).place_id
    end

    test "role and note are editable", %{play: play, roma: roma} do
      {:ok, link} = Places.link_place(play.id, roma.id, %{})

      {:ok, updated} =
        Places.update_play_place(link, %{"role" => "mentioned", "note" => "Act III only"})

      assert updated.role == "mentioned"
      assert updated.note == "Act III only"
    end

    test "moving a link down swaps it with its neighbour", %{
      play: play,
      roma: roma,
      miseno: miseno
    } do
      {:ok, first} = Places.link_place(play.id, roma.id, %{})
      {:ok, _second} = Places.link_place(play.id, miseno.id, %{})

      :ok = Places.move_play_place(first, :down)

      assert Places.list_play_places(play.id)
             |> Enum.map(&Places.display_name(&1.place, "es")) == ["Miseno", "Roma"]
    end

    test "moving the first link up is a no-op", %{play: play, roma: roma} do
      {:ok, first} = Places.link_place(play.id, roma.id, %{})
      assert :ok = Places.move_play_place(first, :up)
      assert [only] = Places.list_play_places(play.id)
      assert only.position == 0
    end

    test "unlinking leaves the place in the gazetteer", %{play: play, roma: roma} do
      {:ok, link} = Places.link_place(play.id, roma.id, %{})
      {:ok, _} = Places.unlink_place(link)

      assert Places.list_play_places(play.id) == []
      assert Places.get_place!(roma.id)
    end

    test "delete_tei_play_places/1 removes only importer-created links", %{
      play: play,
      roma: roma,
      miseno: miseno
    } do
      {:ok, _} = Places.link_place(play.id, roma.id, %{"origin" => "tei"})
      {:ok, _} = Places.link_place(play.id, miseno.id, %{"origin" => "manual"})

      {1, nil} = Places.delete_tei_play_places(play.id)

      assert [kept] = Places.list_play_places(play.id)
      assert Places.display_name(kept.place, "es") == "Miseno"
    end
  end
```

- [ ] **Step 2: Run it and watch it fail**

```bash
mix test test/emothe/places_test.exs
```

Expected: FAIL — `function Emothe.Places.list_play_places/1 is undefined or private`.

- [ ] **Step 3: Implement**

Replace the "Play links (completed in Task 5)" section of `lib/emothe/places.ex` with:

```elixir
  # --- Play links ---

  def list_play_places(play_id) do
    PlayPlace
    |> where([pp], pp.play_id == ^play_id)
    |> order_by([pp], asc: pp.position, asc: pp.inserted_at)
    |> Repo.all()
    |> Repo.preload(place: [names: from(n in PlaceName, order_by: ^@name_order)])
  end

  def get_play_place!(id) do
    PlayPlace
    |> Repo.get!(id)
    |> Repo.preload(place: [names: from(n in PlaceName, order_by: ^@name_order)])
  end

  def change_play_place(%PlayPlace{} = play_place, attrs \\ %{}) do
    PlayPlace.changeset(play_place, attrs)
  end

  def link_place(play_id, place_id, attrs) do
    next = Repo.aggregate(from(pp in PlayPlace, where: pp.play_id == ^play_id), :count, :id)

    attrs
    |> Map.merge(%{"play_id" => play_id, "place_id" => place_id})
    |> Map.put_new("position", next)
    |> then(&PlayPlace.changeset(%PlayPlace{}, &1))
    |> Repo.insert()
  end

  def update_play_place(%PlayPlace{} = play_place, attrs) do
    play_place
    |> PlayPlace.changeset(attrs)
    |> Repo.update()
  end

  def unlink_place(%PlayPlace{} = play_place), do: Repo.delete(play_place)

  @doc "Swaps a link with its neighbour. A move past either end is a no-op."
  def move_play_place(%PlayPlace{} = play_place, direction) when direction in [:up, :down] do
    links = list_play_places(play_place.play_id)
    index = Enum.find_index(links, &(&1.id == play_place.id))
    target = if direction == :up, do: index - 1, else: index + 1

    if is_nil(index) or target < 0 or target >= length(links) do
      :ok
    else
      neighbour = Enum.at(links, target)

      Repo.transaction(fn ->
        Repo.update!(PlayPlace.changeset(play_place, %{"position" => neighbour.position}))
        Repo.update!(PlayPlace.changeset(neighbour, %{"position" => play_place.position}))
      end)

      renumber(play_place.play_id)
      :ok
    end
  end

  @doc """
  Deletes only the links a TEI import created. Place rows are never deleted by an
  import: the gazetteer is authority data, and an orphan shows with a play count of 0.
  """
  def delete_tei_play_places(play_id) do
    Repo.delete_all(
      from pp in PlayPlace, where: pp.play_id == ^play_id and pp.origin == "tei"
    )
  end

  defp renumber(play_id) do
    play_id
    |> list_play_places()
    |> Enum.with_index()
    |> Enum.each(fn {link, index} ->
      if link.position != index do
        Repo.update!(PlayPlace.changeset(link, %{"position" => index}))
      end
    end)
  end
```

- [ ] **Step 4: Run it and watch it pass**

```bash
mix test test/emothe/places_test.exs
```

Expected: PASS, 30 tests.

- [ ] **Step 5: Whole suite, format, commit**

```bash
mix test && mix format && mix compile --warnings-as-errors
git add lib/emothe/places.ex test/emothe/places_test.exs
git commit -m "feat: link, reorder and unlink places on a play"
```

---

### Task 6: The authority seam and the Wikidata implementation

A behaviour with two implementations from the start — `Wikidata` over `req`, and `Stub` for tests, so **no test touches the network**. `fetch/1` returns multilingual labels, which is what lets one click seed four `place_names` rows.

**Files:**
- Create: `lib/emothe/places/authority.ex`, `lib/emothe/places/authority/wikidata.ex`, `lib/emothe/places/authority/stub.ex`
- Create: `test/fixtures/wikidata/Q220.json`, `test/fixtures/wikidata/search_roma.json`
- Modify: `config/config.exs`, `config/test.exs`
- Test: `test/emothe/places/authority/wikidata_test.exs`

**Interfaces:**
- Consumes: `Place.authorities/0` from Task 2.
- Produces:
  - `Authority.registry() :: [%{slug: String.t(), label: String.t(), url_pattern: String.t(), module: module() | nil}]`
  - `Authority.impl() :: module()` — from `Application.get_env(:emothe, :place_authority)`
  - `Authority.url(String.t(), String.t()) :: String.t() | nil`
  - `@callback search(String.t(), keyword()) :: {:ok, [%{id: String.t(), label: String.t(), description: String.t() | nil}]} | {:error, atom()}`
  - `@callback fetch(String.t()) :: {:ok, details} | {:error, atom()}` where `details` is `%{labels: %{String.t() => String.t()}, latitude: float() | nil, longitude: float() | nil, type_hint: String.t() | nil, parent: %{id: String.t(), label: String.t()} | nil, url: String.t()}`
  - `Wikidata.search/2` and `Wikidata.fetch/2` accept `plug:` for `Req.Test`.

- [ ] **Step 1: Write the fixtures**

`test/fixtures/wikidata/search_roma.json`:

```json
{
  "searchinfo": { "search": "Roma" },
  "search": [
    {
      "id": "Q220",
      "label": "Rome",
      "description": "capital city of Italy"
    },
    {
      "id": "Q2634",
      "label": "Roma",
      "description": "ethnic group"
    }
  ],
  "success": 1
}
```

`test/fixtures/wikidata/Q220.json`:

```json
{
  "entities": {
    "Q220": {
      "id": "Q220",
      "labels": {
        "es": { "language": "es", "value": "Roma" },
        "en": { "language": "en", "value": "Rome" },
        "fr": { "language": "fr", "value": "Rome" },
        "it": { "language": "it", "value": "Roma" }
      },
      "claims": {
        "P31": [
          {
            "mainsnak": {
              "snaktype": "value",
              "property": "P31",
              "datavalue": { "value": { "id": "Q515" }, "type": "wikibase-entityid" }
            }
          }
        ],
        "P17": [
          {
            "mainsnak": {
              "snaktype": "value",
              "property": "P17",
              "datavalue": { "value": { "id": "Q38" }, "type": "wikibase-entityid" }
            }
          }
        ],
        "P625": [
          {
            "mainsnak": {
              "snaktype": "value",
              "property": "P625",
              "datavalue": {
                "value": { "latitude": 41.9028, "longitude": 12.4964 },
                "type": "globecoordinate"
              }
            }
          }
        ]
      }
    }
  },
  "success": 1
}
```

- [ ] **Step 2: Write the failing test**

Create `test/emothe/places/authority/wikidata_test.exs`:

```elixir
defmodule Emothe.Places.Authority.WikidataTest do
  use ExUnit.Case, async: true

  alias Emothe.Places.Authority
  alias Emothe.Places.Authority.Wikidata

  defp json(name), do: File.read!("test/fixtures/wikidata/#{name}.json") |> Jason.decode!()

  defp stub(body) do
    {Req.Test,
     fn conn ->
       Req.Test.json(conn, body)
     end}
  end

  describe "search/2" do
    test "returns id, label and description per candidate" do
      assert {:ok, [first, second]} =
               Wikidata.search("Roma", plug: stub(json("search_roma")))

      assert first == %{id: "Q220", label: "Rome", description: "capital city of Italy"}
      assert second.id == "Q2634"
    end

    test "a blank term makes no request" do
      assert {:ok, []} = Wikidata.search("", plug: stub(%{}))
    end

    test "a transport failure is an :unavailable error, never a crash" do
      plug = {Req.Test, fn conn -> Req.Test.transport_error(conn, :timeout) end}
      assert {:error, :unavailable} = Wikidata.search("Roma", plug: plug)
    end
  end

  describe "fetch/2" do
    test "extracts labels, coordinates, a type hint and the parent" do
      assert {:ok, details} = Wikidata.fetch("Q220", plug: stub(json("Q220")))

      assert details.labels["es"] == "Roma"
      assert details.labels["en"] == "Rome"
      assert details.latitude == 41.9028
      assert details.longitude == 12.4964
      assert details.type_hint == "city"
      assert details.parent == %{id: "Q38", label: "Q38"}
      assert details.url == "https://www.wikidata.org/wiki/Q220"
    end

    test "an entity with no coordinates yields nil rather than failing" do
      body = %{
        "entities" => %{
          "Q1" => %{"id" => "Q1", "labels" => %{"es" => %{"value" => "Atlántida"}}, "claims" => %{}}
        }
      }

      assert {:ok, details} = Wikidata.fetch("Q1", plug: stub(body))
      assert details.latitude == nil
      assert details.type_hint == nil
      assert details.parent == nil
      assert details.labels["es"] == "Atlántida"
    end

    test "a malformed body is an error, not a match failure" do
      assert {:error, :unexpected_response} = Wikidata.fetch("Q220", plug: stub(%{"oops" => true}))
    end

    test "a 404 is an error" do
      plug = {Req.Test, fn conn -> Plug.Conn.send_resp(conn, 404, "not found") end}
      assert {:error, :not_found} = Wikidata.fetch("Q999999999", plug: plug)
    end
  end

  describe "the registry" do
    test "lists every authority slug the schema allows" do
      slugs = Enum.map(Authority.registry(), & &1.slug)
      assert Enum.sort(slugs) == Enum.sort(Emothe.Places.Place.authorities())
    end

    test "builds an outbound URL for a linked place" do
      assert Authority.url("wikidata", "Q220") == "https://www.wikidata.org/wiki/Q220"
      assert Authority.url("geonames", "3169070") == "https://www.geonames.org/3169070"
      assert Authority.url("wikidata", nil) == nil
      assert Authority.url(nil, "Q220") == nil
    end

    test "the test environment uses the stub, so nothing calls out" do
      assert Authority.impl() == Emothe.Places.Authority.Stub
    end
  end
end
```

- [ ] **Step 3: Run it and watch it fail**

```bash
mix test test/emothe/places/authority/wikidata_test.exs
```

Expected: FAIL — `module Emothe.Places.Authority.Wikidata is not available`.

- [ ] **Step 4: Write the behaviour and registry**

`lib/emothe/places/authority.ex`:

```elixir
defmodule Emothe.Places.Authority do
  @moduledoc """
  A gazetteer authority: somewhere a place already has a stable identifier.

  Wikidata is the one that can be searched; GeoNames, Getty TGN and Pleiades are
  link-out targets until someone wants them. The behaviour exists because the seam was
  a requirement, and it has two implementations from day one — `Wikidata` and the
  `Stub` the test environment uses, which is what keeps the suite off the network.
  """

  alias Emothe.Places.Place

  @callback search(term :: String.t(), opts :: keyword()) ::
              {:ok, [%{id: String.t(), label: String.t(), description: String.t() | nil}]}
              | {:error, atom()}

  @callback fetch(id :: String.t()) ::
              {:ok,
               %{
                 labels: %{String.t() => String.t()},
                 latitude: float() | nil,
                 longitude: float() | nil,
                 type_hint: String.t() | nil,
                 parent: %{id: String.t(), label: String.t()} | nil,
                 url: String.t()
               }}
              | {:error, atom()}

  @registry %{
    "wikidata" => %{
      label: "Wikidata",
      url_pattern: "https://www.wikidata.org/wiki/~s",
      module: Emothe.Places.Authority.Wikidata
    },
    "geonames" => %{
      label: "GeoNames",
      url_pattern: "https://www.geonames.org/~s",
      module: nil
    },
    "tgn" => %{
      label: "Getty TGN",
      url_pattern: "https://vocab.getty.edu/page/tgn/~s",
      module: nil
    },
    "pleiades" => %{
      label: "Pleiades",
      url_pattern: "https://pleiades.stoa.org/places/~s",
      module: nil
    }
  }

  def registry do
    Enum.map(Place.authorities(), fn slug ->
      @registry |> Map.fetch!(slug) |> Map.put(:slug, slug)
    end)
  end

  @doc "The searchable implementation for the current environment."
  def impl do
    Application.get_env(:emothe, :place_authority, Emothe.Places.Authority.Wikidata)
  end

  @doc "The public page for a linked identifier, or nil when either half is missing."
  def url(slug, id) when is_binary(slug) and is_binary(id) do
    case Map.fetch(@registry, slug) do
      {:ok, %{url_pattern: pattern}} -> String.replace(pattern, "~s", id)
      :error -> nil
    end
  end

  def url(_slug, _id), do: nil

  def label(slug) do
    case Map.fetch(@registry, slug || "") do
      {:ok, %{label: label}} -> label
      :error -> ""
    end
  end
end
```

- [ ] **Step 5: Write the Wikidata implementation**

`lib/emothe/places/authority/wikidata.ex`:

```elixir
defmodule Emothe.Places.Authority.Wikidata do
  @moduledoc """
  Wikidata over `req`. Two endpoints: `wbsearchentities` for the typeahead and
  `Special:EntityData/<id>.json` for the details.

  Nothing here is load-bearing for the app. A timeout or a 500 returns
  `{:error, :unavailable}`, the form says so inline, and every field stays typeable —
  a curator with no network can still do the whole job.
  """

  @behaviour Emothe.Places.Authority

  require Logger

  @search_url "https://www.wikidata.org/w/api.php"
  @entity_url "https://www.wikidata.org/wiki/Special:EntityData"
  @timeout 5_000

  # P31 "instance of" → our own vocabulary. Anything unlisted yields nil, which leaves
  # the curator to choose rather than guessing wrong.
  @type_hints %{
    "Q515" => "city",
    "Q1549591" => "city",
    "Q3957" => "town",
    "Q6256" => "country",
    "Q5107" => "continent",
    "Q82794" => "region",
    "Q4022" => "river",
    "Q23397" => "lake",
    "Q165" => "sea",
    "Q23442" => "island",
    "Q8502" => "mountain",
    "Q4421" => "forest",
    "Q41176" => "building"
  }

  @impl true
  def search(term, opts \\ [])
  def search(term, _opts) when term in [nil, ""], do: {:ok, []}

  def search(term, opts) do
    params = [
      action: "wbsearchentities",
      search: term,
      language: opts[:locale] || "es",
      uselang: opts[:locale] || "es",
      type: "item",
      limit: 10,
      format: "json"
    ]

    case get(@search_url, [params: params] ++ req_opts(opts)) do
      {:ok, %{"search" => results}} when is_list(results) ->
        {:ok, Enum.map(results, &candidate/1)}

      {:ok, _other} ->
        {:error, :unexpected_response}

      {:error, reason} ->
        {:error, reason}
    end
  end

  @impl true
  def fetch(id), do: fetch(id, [])

  def fetch(id, opts) do
    case get("#{@entity_url}/#{id}.json", req_opts(opts)) do
      {:ok, %{"entities" => entities}} when is_map(entities) ->
        case Map.values(entities) do
          [entity | _] -> {:ok, details(entity, id)}
          [] -> {:error, :not_found}
        end

      {:ok, _other} ->
        {:error, :unexpected_response}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp candidate(result) do
    %{
      id: result["id"],
      label: result["label"] || result["id"],
      description: result["description"]
    }
  end

  defp details(entity, id) do
    claims = entity["claims"] || %{}
    {latitude, longitude} = coordinates(claims)

    %{
      labels: labels(entity["labels"] || %{}),
      latitude: latitude,
      longitude: longitude,
      type_hint: type_hint(claims),
      parent: parent(claims),
      url: "https://www.wikidata.org/wiki/#{id}"
    }
  end

  defp labels(labels) do
    for {language, %{"value" => value}} <- labels,
        language in ~w(es en fr it pt ca),
        into: %{},
        do: {language, value}
  end

  defp coordinates(claims) do
    case entity_value(claims, "P625") do
      %{"latitude" => latitude, "longitude" => longitude} -> {latitude, longitude}
      _ -> {nil, nil}
    end
  end

  defp type_hint(claims) do
    case entity_value(claims, "P31") do
      %{"id" => qid} -> Map.get(@type_hints, qid)
      _ -> nil
    end
  end

  defp parent(claims) do
    case entity_value(claims, "P17") do
      %{"id" => qid} -> %{id: qid, label: qid}
      _ -> nil
    end
  end

  defp entity_value(claims, property) do
    with [%{"mainsnak" => %{"datavalue" => %{"value" => value}}} | _] <- claims[property] do
      value
    else
      _ -> nil
    end
  end

  defp req_opts(opts), do: Keyword.take(opts, [:plug])

  defp get(url, options) do
    [url: url, receive_timeout: @timeout, retry: false]
    |> Keyword.merge(options)
    |> Req.new()
    |> Req.get()
    |> case do
      {:ok, %Req.Response{status: 200, body: body}} when is_map(body) ->
        {:ok, body}

      {:ok, %Req.Response{status: 404}} ->
        {:error, :not_found}

      {:ok, %Req.Response{status: status}} ->
        Logger.warning("Wikidata returned #{status} for #{url}")
        {:error, :unavailable}

      {:error, reason} ->
        Logger.warning("Wikidata request failed: #{inspect(reason)}")
        {:error, :unavailable}
    end
  end
end
```

- [ ] **Step 6: Write the stub**

`lib/emothe/places/authority/stub.ex`:

```elixir
defmodule Emothe.Places.Authority.Stub do
  @moduledoc """
  The authority the test environment uses. Deterministic, offline, and deliberately
  small: two known entities and an error trigger, which is everything the LiveView
  tests need to exercise the happy path and the failure path.
  """

  @behaviour Emothe.Places.Authority

  @entities %{
    "Q220" => %{
      labels: %{"es" => "Roma", "en" => "Rome", "it" => "Roma"},
      latitude: 41.9028,
      longitude: 12.4964,
      type_hint: "city",
      parent: %{id: "Q38", label: "Italia"},
      url: "https://www.wikidata.org/wiki/Q220"
    },
    "Q1136668" => %{
      labels: %{"es" => "Atlántida", "en" => "Atlantis"},
      latitude: nil,
      longitude: nil,
      type_hint: nil,
      parent: nil,
      url: "https://www.wikidata.org/wiki/Q1136668"
    }
  }

  @impl true
  def search(term, _opts \\ [])
  def search("boom", _opts), do: {:error, :unavailable}
  def search(term, _opts) when term in [nil, ""], do: {:ok, []}

  def search(term, _opts) do
    results =
      for {id, entity} <- @entities,
          label = entity.labels["es"],
          String.contains?(String.downcase(label), String.downcase(term)),
          do: %{id: id, label: label, description: "stubbed"}

    {:ok, Enum.sort_by(results, & &1.id)}
  end

  @impl true
  def fetch(id) do
    case Map.fetch(@entities, id) do
      {:ok, entity} -> {:ok, entity}
      :error -> {:error, :not_found}
    end
  end
end
```

- [ ] **Step 7: Configure both environments**

In `config/config.exs`, before the `import_config` line:

```elixir
config :emothe, :place_authority, Emothe.Places.Authority.Wikidata
```

In `config/test.exs`, after the mailer config:

```elixir
# No test touches the network.
config :emothe, :place_authority, Emothe.Places.Authority.Stub
```

- [ ] **Step 8: Run it and watch it pass**

```bash
mix test test/emothe/places/authority/wikidata_test.exs
```

Expected: PASS, 12 tests.

- [ ] **Step 9: Whole suite, format, commit**

```bash
mix test && mix format && mix compile --warnings-as-errors
git add lib/emothe/places/authority* config/config.exs config/test.exs test/fixtures/wikidata test/emothe/places/authority
git commit -m "feat: a swappable place authority, with Wikidata and a test stub"
```

---

### Task 7: The shared form and the gazetteer page

`/admin/places` plus the `LiveComponent` both admin pages use. The form warns on a duplicate name rather than letting `unique_slug/1` silently produce `woods-2`.

**Files:**
- Create: `lib/emothe_web/live/admin/place_form_component.ex`, `lib/emothe_web/live/admin/place_list_live.ex`
- Modify: `lib/emothe_web/router.ex`, `lib/emothe_web/components/layouts.ex`, `lib/emothe_web/play_labels.ex`
- Test: `test/emothe_web/live/admin/place_list_live_test.exs`

**Interfaces:**
- Consumes: `Places` (Tasks 3–5), `Authority` (Task 6), `Authz.can?(user, :manage_places)` (Task 1).
- Produces:
  - `EmotheWeb.Admin.PlaceFormComponent` — attrs `id`, `place`, `current_user`, `on_saved` (a 1-arity function taking the saved `%Place{}`)
  - `EmotheWeb.Admin.PlaceListLive` at `/admin/places`
  - `EmotheWeb.PlayLabels.place_type_label/1`, `place_type_options/0`, `place_role_label/1`, `place_role_options/0`

- [ ] **Step 1: Write the failing test**

Create `test/emothe_web/live/admin/place_list_live_test.exs`:

```elixir
defmodule EmotheWeb.Admin.PlaceListLiveTest do
  use EmotheWeb.ConnCase, async: true

  import Phoenix.LiveViewTest

  alias Emothe.Places
  alias Emothe.TestFixtures

  defp t(msgid), do: Gettext.gettext(EmotheWeb.Gettext, msgid)

  defp log_in_researcher(conn) do
    log_in_user(conn, TestFixtures.user_fixture(role: :researcher))
  end

  test "a researcher may reach the gazetteer", %{conn: conn} do
    {:ok, _view, html} = live(log_in_researcher(conn), ~p"/admin/places")
    assert html =~ t("Places")
  end

  test "a logged-out visitor may not", %{conn: conn} do
    assert {:error, {:redirect, %{to: "/users/log-in"}}} = live(conn, ~p"/admin/places")
  end

  test "a place is created with one name and shows its type and play count", %{conn: conn} do
    {:ok, view, _html} = live(log_in_researcher(conn), ~p"/admin/places")

    view |> element("button", t("New place")) |> render_click()

    html =
      view
      |> form("#place-form",
        place: %{
          "type" => "city",
          "names" => %{"0" => %{"name" => "Roma", "language" => "es", "is_preferred" => "true"}}
        }
      )
      |> render_submit()

    assert html =~ "Roma"
    assert html =~ t("City")
    assert [place] = Places.list_places()
    assert place.slug == "roma"
    assert place.play_count == 0
  end

  test "searching matches a non-preferred name variant", %{conn: conn} do
    TestFixtures.place_fixture(%{
      "names" => [
        %{"name" => "Constantinopla", "language" => "es", "is_preferred" => "true"},
        %{"name" => "İstanbul", "language" => "tr"}
      ]
    })

    TestFixtures.place_fixture(%{"name" => "Roma"})

    {:ok, view, _html} = live(log_in_researcher(conn), ~p"/admin/places")

    html =
      view |> element("form[phx-change=search]") |> render_change(%{"search" => "istanbul"})

    assert html =~ "Constantinopla"
    refute html =~ "Roma"
  end

  test "a place used by a play cannot be deleted, and says why", %{conn: conn} do
    play = TestFixtures.play_fixture()
    place = TestFixtures.place_fixture(%{"name" => "Roma"})
    TestFixtures.play_place_fixture(play, place)

    {:ok, view, _html} = live(log_in_researcher(conn), ~p"/admin/places")

    html = view |> element("button[phx-value-id='#{place.id}'][phx-click=delete]") |> render_click()

    assert html =~ t("This place is still used by a play. Unlink it there first.")
    assert Places.list_places() != []
  end

  test "an unreferenced place is deleted", %{conn: conn} do
    place = TestFixtures.place_fixture(%{"name" => "Roma"})
    {:ok, view, _html} = live(log_in_researcher(conn), ~p"/admin/places")

    view |> element("button[phx-value-id='#{place.id}'][phx-click=delete]") |> render_click()

    assert Places.list_places() == []
  end

  test "a name that already exists warns instead of silently suffixing", %{conn: conn} do
    TestFixtures.place_fixture(%{"name" => "Woods"})

    {:ok, view, _html} = live(log_in_researcher(conn), ~p"/admin/places")
    view |> element("button", t("New place")) |> render_click()

    html =
      view
      |> form("#place-form",
        place: %{
          "type" => "forest",
          "names" => %{"0" => %{"name" => "Woods", "language" => "es", "is_preferred" => "true"}}
        }
      )
      |> render_change()

    assert html =~ t("A place with this name already exists.")
  end

  test "a Wikidata search fills the coordinates and one name per language", %{conn: conn} do
    {:ok, view, _html} = live(log_in_researcher(conn), ~p"/admin/places")
    view |> element("button", t("New place")) |> render_click()

    view
    |> element("form[phx-change=authority_search]")
    |> render_change(%{"term" => "Roma"})

    html = view |> element("button[phx-value-authority-id=Q220]") |> render_click()

    assert html =~ "41.9028"
    assert html =~ "Rome"
  end

  test "an authority failure is reported and does not crash the form", %{conn: conn} do
    {:ok, view, _html} = live(log_in_researcher(conn), ~p"/admin/places")
    view |> element("button", t("New place")) |> render_click()

    html =
      view
      |> element("form[phx-change=authority_search]")
      |> render_change(%{"term" => "boom"})

    assert html =~ t("The authority is unavailable. Enter the details by hand.")
  end
end
```

- [ ] **Step 2: Run it and watch it fail**

```bash
mix test test/emothe_web/live/admin/place_list_live_test.exs
```

Expected: FAIL — no route for `/admin/places`.

- [ ] **Step 3: Add the labels**

Append to `lib/emothe_web/play_labels.ex`, and add `alias Emothe.Places.{Place, PlayPlace}` at the top:

```elixir
  @doc "The Spanish-or-English name of a place type slug."
  def place_type_label("continent"), do: gettext("Continent")
  def place_type_label("country"), do: gettext("Country")
  def place_type_label("province"), do: gettext("Province")
  def place_type_label("region"), do: gettext("Region")
  def place_type_label("district"), do: gettext("District")
  def place_type_label("city"), do: gettext("City")
  def place_type_label("town"), do: gettext("Town")
  def place_type_label("building"), do: gettext("Building")
  def place_type_label("forest"), do: gettext("Forest")
  def place_type_label("river"), do: gettext("River")
  def place_type_label("lake"), do: gettext("Lake")
  def place_type_label("sea"), do: gettext("Sea")
  def place_type_label("island"), do: gettext("Island")
  def place_type_label("mountain"), do: gettext("Mountain")
  def place_type_label("other"), do: gettext("Other")
  def place_type_label(_other), do: ""

  def place_type_options, do: Enum.map(Place.types(), &{place_type_label(&1), &1})

  def place_role_label("setting"), do: gettext("Setting")
  def place_role_label("mentioned"), do: gettext("Mentioned")
  def place_role_label(_other), do: ""

  def place_role_options, do: Enum.map(PlayPlace.roles(), &{place_role_label(&1), &1})
```

- [ ] **Step 4: Write the form component**

Create `lib/emothe_web/live/admin/place_form_component.ex`:

```elixir
defmodule EmotheWeb.Admin.PlaceFormComponent do
  @moduledoc """
  The one place-editing surface, used by the gazetteer page and the per-play page.

  A `LiveComponent` rather than this repo's usual inline form because two pages need
  the identical form *and* its events; the alternative is duplicating create, update,
  authority-search and name-row handlers in both LiveViews.
  """

  use EmotheWeb, :live_component

  alias Emothe.ActivityLog
  alias Emothe.Places
  alias Emothe.Places.Authority
  alias EmotheWeb.PlayLabels

  @impl true
  def update(%{place: place} = assigns, socket) do
    {:ok,
     socket
     |> assign(assigns)
     |> assign(:form, to_form(Places.change_place(place)))
     |> assign_new(:candidates, fn -> [] end)
     |> assign_new(:authority_error, fn -> nil end)
     |> assign_new(:duplicate, fn -> nil end)
     |> assign(:parent_options, parent_options(place))}
  end

  @impl true
  def handle_event("validate", %{"place" => params}, socket) do
    changeset =
      socket.assigns.place
      |> Places.change_place(params)
      |> Map.put(:action, :validate)

    {:noreply,
     socket
     |> assign(:form, to_form(changeset))
     |> assign(:duplicate, duplicate_for(params, socket.assigns.place))}
  end

  def handle_event("save", %{"place" => params}, socket) do
    save(socket, socket.assigns.place.id, params)
  end

  def handle_event("authority_search", %{"term" => term}, socket) do
    case Authority.impl().search(term, locale: Gettext.get_locale(EmotheWeb.Gettext)) do
      {:ok, candidates} ->
        {:noreply, socket |> assign(:candidates, candidates) |> assign(:authority_error, nil)}

      {:error, _reason} ->
        {:noreply,
         socket
         |> assign(:candidates, [])
         |> assign(
           :authority_error,
           gettext("The authority is unavailable. Enter the details by hand.")
         )}
    end
  end

  def handle_event("authority_select", %{"authority-id" => id}, socket) do
    case Authority.impl().fetch(id) do
      {:ok, details} ->
        params = merge_authority(socket.assigns.form.params, id, details)

        changeset =
          socket.assigns.place
          |> Places.change_place(params)
          |> Map.put(:action, :validate)

        {:noreply, socket |> assign(:form, to_form(changeset)) |> assign(:candidates, [])}

      {:error, _reason} ->
        {:noreply,
         assign(
           socket,
           :authority_error,
           gettext("The authority is unavailable. Enter the details by hand.")
         )}
    end
  end

  defp save(socket, nil, params) do
    case Places.create_place(params) do
      {:ok, place} ->
        log(socket, "create", place)
        socket.assigns.on_saved.(place)
        {:noreply, socket}

      {:error, changeset} ->
        {:noreply, assign(socket, :form, to_form(changeset))}
    end
  end

  defp save(socket, _id, params) do
    case Places.update_place(socket.assigns.place, params) do
      {:ok, place} ->
        log(socket, "update", place)
        socket.assigns.on_saved.(place)
        {:noreply, socket}

      {:error, changeset} ->
        {:noreply, assign(socket, :form, to_form(changeset))}
    end
  end

  defp log(socket, action, place) do
    ActivityLog.log!(%{
      user_id: socket.assigns.current_user.id,
      action: action,
      resource_type: "place",
      resource_id: place.id,
      metadata: %{slug: place.slug}
    })
  end

  # One Wikidata click seeds a name row per language it knows, which is the whole point
  # of a names layer the curator would otherwise fill in four submissions.
  defp merge_authority(params, id, details) do
    names =
      details.labels
      |> Enum.sort_by(fn {language, _} -> language end)
      |> Enum.with_index()
      |> Map.new(fn {{language, value}, index} ->
        {to_string(index),
         %{
           "name" => value,
           "language" => language,
           "is_preferred" => "true",
           "position" => to_string(index)
         }}
      end)

    params
    |> Map.merge(%{
      "authority" => "wikidata",
      "authority_id" => id,
      "names" => names
    })
    |> maybe_put("latitude", details.latitude)
    |> maybe_put("longitude", details.longitude)
    |> maybe_put("type", details.type_hint)
  end

  defp maybe_put(params, _key, nil), do: params
  defp maybe_put(params, key, value), do: Map.put(params, key, to_string(value))

  defp duplicate_for(%{"names" => names}, place) when is_map(names) do
    names
    |> Map.values()
    |> Enum.map(& &1["name"])
    |> Enum.reject(&(&1 in [nil, ""]))
    |> Enum.find_value(fn name ->
      case Places.find_by_name(name) do
        nil -> nil
        %{id: id} when id == place.id -> nil
        found -> found
      end
    end)
  end

  defp duplicate_for(_params, _place), do: nil

  defp parent_options(place) do
    [{gettext("— none —"), nil}] ++
      (Places.list_places()
       |> Enum.reject(&(&1.id == place.id))
       |> Enum.map(&{Places.display_name(&1, "es"), &1.id}))
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="rounded-box border border-primary/30 bg-base-100 p-5 shadow-md">
      <h3 class="mb-4 text-sm font-semibold text-primary">
        {if @place.id, do: gettext("Edit place"), else: gettext("New place")}
      </h3>

      <%!-- Authority search: the only remote lookup, so the only typeahead --%>
      <div class="mb-4 rounded-box bg-base-200 p-3">
        <form phx-change="authority_search" phx-target={@myself} phx-debounce="300">
          <label class="label">
            <span class="label-text font-medium">{gettext("Search Wikidata")}</span>
          </label>
          <input type="text" name="term" value="" class="input input-bordered input-sm w-full" />
        </form>
        <p :if={@authority_error} class="mt-2 text-xs text-warning">{@authority_error}</p>
        <ul class="mt-2 space-y-1">
          <li :for={candidate <- @candidates}>
            <button
              type="button"
              phx-click="authority_select"
              phx-target={@myself}
              phx-value-authority-id={candidate.id}
              class="btn btn-ghost btn-xs justify-start w-full"
            >
              <span class="font-medium">{candidate.label}</span>
              <span class="text-base-content/50">{candidate.description}</span>
            </button>
          </li>
        </ul>
      </div>

      <.form
        for={@form}
        id="place-form"
        phx-change="validate"
        phx-submit="save"
        phx-target={@myself}
      >
        <div :if={@duplicate} class="alert alert-warning mb-4 text-sm">
          {gettext("A place with this name already exists.")}
          <span class="font-medium">{Places.display_name(@duplicate, "es")}</span>
        </div>

        <fieldset class="mb-4">
          <legend class="label-text font-medium">{gettext("Names")}</legend>
          <.inputs_for :let={name} field={@form[:names]}>
            <input type="hidden" name="place[names_order][]" value={name.index} />
            <div class="mb-2 flex flex-wrap items-end gap-2">
              <div class="grow">
                <.input field={name[:name]} type="text" placeholder={gettext("Name")} />
              </div>
              <div class="w-28">
                <.input
                  field={name[:language]}
                  type="select"
                  options={[{"", nil}, {"es", "es"}, {"en", "en"}, {"fr", "fr"}, {"it", "it"},
                            {"pt", "pt"}, {"ca", "ca"}]}
                />
              </div>
              <label class="label cursor-pointer gap-1">
                <.input field={name[:is_preferred]} type="checkbox" />
                <span class="label-text text-xs">{gettext("Preferred")}</span>
              </label>
              <label class="label cursor-pointer gap-1">
                <.input field={name[:is_historical]} type="checkbox" />
                <span class="label-text text-xs">{gettext("Historical")}</span>
              </label>
              <button
                type="button"
                name="place[names_delete][]"
                value={name.index}
                phx-click={JS.dispatch("change")}
                class="btn btn-ghost btn-xs text-error"
              >
                {gettext("Remove")}
              </button>
            </div>
          </.inputs_for>

          <input type="hidden" name="place[names_delete][]" />
          <label class="btn btn-ghost btn-xs mt-1">
            <input type="checkbox" name="place[names_order][]" class="hidden" /> {gettext("Add name")}
          </label>
        </fieldset>

        <div class="grid grid-cols-1 gap-4 md:grid-cols-2">
          <div>
            <label class="label"><span class="label-text font-medium">{gettext("Type")}</span></label>
            <.input field={@form[:type]} type="select" options={PlayLabels.place_type_options()} />
          </div>
          <div>
            <label class="label">
              <span class="label-text font-medium">{gettext("Contained in")}</span>
            </label>
            <.input field={@form[:parent_place_id]} type="select" options={@parent_options} />
          </div>
          <div>
            <label class="label">
              <span class="label-text font-medium">{gettext("Latitude")}</span>
            </label>
            <.input field={@form[:latitude]} type="text" />
          </div>
          <div>
            <label class="label">
              <span class="label-text font-medium">{gettext("Longitude")}</span>
            </label>
            <.input field={@form[:longitude]} type="text" />
          </div>
          <div>
            <label class="label"><span class="label-text font-medium">{gettext("Slug")}</span></label>
            <.input field={@form[:slug]} type="text" />
          </div>
          <div>
            <label class="label">
              <span class="label-text font-medium">{gettext("Wikidata id")}</span>
            </label>
            <.input field={@form[:authority_id]} type="text" />
            <.input field={@form[:authority]} type="hidden" />
          </div>
        </div>

        <label class="label mt-2 cursor-pointer gap-2 justify-start">
          <.input field={@form[:is_fictional]} type="checkbox" />
          <span class="label-text">{gettext("Fictional place")}</span>
        </label>

        <div class="mt-2">
          <label class="label"><span class="label-text font-medium">{gettext("Note")}</span></label>
          <.input field={@form[:note]} type="textarea" rows="2" />
        </div>

        <p class="mt-2 text-xs text-base-content/50">
          {gettext("Leave the coordinates empty for a place that cannot be located.")}
        </p>

        <div class="mt-4 flex justify-end gap-2">
          <button type="button" phx-click="cancel_edit" class="btn btn-ghost btn-sm">
            {gettext("Cancel")}
          </button>
          <button type="submit" class="btn btn-primary btn-sm">{gettext("Save")}</button>
        </div>
      </.form>
    </div>
    """
  end
end
```

- [ ] **Step 5: Write the gazetteer page**

Create `lib/emothe_web/live/admin/place_list_live.ex`:

```elixir
defmodule EmotheWeb.Admin.PlaceListLive do
  use EmotheWeb, :live_view

  alias Emothe.ActivityLog
  alias Emothe.Places
  alias Emothe.Places.{Authority, Place}
  alias EmotheWeb.PlayLabels

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(:page_title, gettext("Places"))
     |> assign(:search, "")
     |> assign(:editing, nil)
     |> load_places()}
  end

  @impl true
  def handle_event("search", %{"search" => term}, socket) do
    {:noreply, socket |> assign(:search, term) |> load_places()}
  end

  def handle_event("new", _params, socket) do
    {:noreply, assign(socket, :editing, %Place{names: []})}
  end

  def handle_event("edit", %{"id" => id}, socket) do
    {:noreply, assign(socket, :editing, Places.get_place!(id))}
  end

  def handle_event("cancel_edit", _params, socket) do
    {:noreply, assign(socket, :editing, nil)}
  end

  def handle_event("delete", %{"id" => id}, socket) do
    place = Places.get_place!(id)

    case Places.delete_place(place) do
      {:ok, _} ->
        ActivityLog.log!(%{
          user_id: socket.assigns.current_user.id,
          action: "delete",
          resource_type: "place",
          resource_id: place.id,
          metadata: %{slug: place.slug}
        })

        {:noreply,
         socket |> load_places() |> put_flash(:info, gettext("Place deleted."))}

      {:error, changeset} ->
        {:noreply, put_flash(socket, :error, delete_error(changeset))}
    end
  end

  defp delete_error(changeset) do
    cond do
      changeset.errors[:play_places] ->
        gettext("This place is still used by a play. Unlink it there first.")

      changeset.errors[:children] ->
        gettext("This place contains other places. Move them out first.")

      true ->
        gettext("This place could not be deleted.")
    end
  end

  defp load_places(socket) do
    gazetteer = Places.gazetteer()

    places =
      case socket.assigns.search do
        term when term in [nil, ""] -> Places.list_places()
        term -> Places.search_names(term)
      end

    socket |> assign(:places, places) |> assign(:gazetteer, gazetteer)
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="mx-auto max-w-5xl px-4 py-8">
      <div class="mb-6 flex items-center justify-between">
        <div>
          <h1 class="text-2xl font-semibold tracking-tight text-base-content">
            {gettext("Places")}
          </h1>
          <p class="mt-1 text-sm text-base-content/60">
            {gettext("One record per place, shared by every play that references it.")}
          </p>
        </div>
        <button :if={is_nil(@editing)} phx-click="new" class="btn btn-primary btn-sm gap-1">
          <.icon name="hero-plus-mini" class="size-4" /> {gettext("New place")}
        </button>
      </div>

      <.live_component
        :if={@editing}
        module={EmotheWeb.Admin.PlaceFormComponent}
        id="place-form-component"
        place={@editing}
        current_user={@current_user}
        on_saved={fn _place -> send(self(), :place_saved) end}
      />

      <form phx-change="search" class="mb-4 mt-6">
        <input
          type="text"
          name="search"
          value={@search}
          placeholder={gettext("Search any name, in any language")}
          class="input input-bordered input-sm w-full max-w-md"
        />
      </form>

      <div :if={@places == []} class="py-12 text-center text-base-content/50">
        <.icon name="hero-map-pin" class="mx-auto mb-3 size-12 opacity-30" />
        <p class="text-sm">{gettext("No places yet.")}</p>
      </div>

      <table :if={@places != []} class="table table-sm">
        <thead>
          <tr>
            <th>{gettext("Place")}</th>
            <th>{gettext("Type")}</th>
            <th>{gettext("Authority")}</th>
            <th>{gettext("Plays")}</th>
            <th></th>
          </tr>
        </thead>
        <tbody>
          <tr :for={place <- @places} id={"place-#{place.id}"}>
            <td>
              <span class="font-medium">{Places.display_name(place, "es")}</span>
              <span class="block text-xs text-base-content/50">
                {Places.breadcrumb(place, @gazetteer, "es")}
              </span>
            </td>
            <td>
              <span class="badge badge-ghost badge-sm">
                {PlayLabels.place_type_label(place.type)}
              </span>
              <span :if={place.is_fictional} class="badge badge-outline badge-sm">
                {gettext("Fictional")}
              </span>
            </td>
            <td class="text-xs">
              <a
                :if={Authority.url(place.authority, place.authority_id)}
                href={Authority.url(place.authority, place.authority_id)}
                target="_blank"
                class="link"
              >
                {place.authority_id}
              </a>
              <span :if={place.latitude} class="block text-base-content/50">
                {place.latitude}, {place.longitude}
              </span>
            </td>
            <td class="text-xs">{place.play_count}</td>
            <td class="text-right">
              <button phx-click="edit" phx-value-id={place.id} class="btn btn-ghost btn-xs">
                {gettext("Edit")}
              </button>
              <button
                phx-click="delete"
                phx-value-id={place.id}
                data-confirm={gettext("Delete this place?")}
                class="btn btn-ghost btn-xs text-error"
              >
                {gettext("Delete")}
              </button>
            </td>
          </tr>
        </tbody>
      </table>
    </div>
    """
  end

  @impl true
  def handle_info(:place_saved, socket) do
    {:noreply,
     socket
     |> assign(:editing, nil)
     |> load_places()
     |> put_flash(:info, gettext("Place saved."))}
  end
end
```

- [ ] **Step 6: Add the route and the sidebar entry**

In `lib/emothe_web/router.ex`, inside the `live_session :admin` block, after the `live "/plays/:id/compare"` line:

```elixir
      live "/places", PlaceListLive, :index
```

In `lib/emothe_web/components/layouts.ex`, in `sidebar_groups/1`'s `Content` list, after the `Import` entry:

```elixir
         %{
           label: gettext("Places"),
           to: "/admin/places",
           icon: "hero-map-pin-micro",
           action: :manage_places
         },
```

- [ ] **Step 7: Run it and watch it pass**

```bash
mix test test/emothe_web/live/admin/place_list_live_test.exs
```

Expected: PASS, 9 tests. If the `Add name` label does not add a row, check that `Place` declares `has_many :names, on_replace: :delete` — `sort_param` needs it.

- [ ] **Step 8: Whole suite, format, commit**

```bash
mix test && mix format && mix compile --warnings-as-errors
git add lib/emothe_web lib/emothe_web/play_labels.ex test/emothe_web/live/admin/place_list_live_test.exs
git commit -m "feat: the places gazetteer at /admin/places"
```

---

### Task 8: The per-play place index

A peer tab in the play context bar, at the same level as Metadata, Editors, Sources and Content — between Sources and Content.

**Files:**
- Create: `lib/emothe_web/live/admin/play_places_live.ex`
- Modify: `lib/emothe_web/router.ex`, `lib/emothe_web/components/layouts.ex:103-147`
- Test: `test/emothe_web/live/admin/play_places_live_test.exs`

**Interfaces:**
- Consumes: `Places.list_play_places/1`, `link_place/3`, `update_play_place/2`, `move_play_place/2`, `unlink_place/1`, `PlaceFormComponent`.
- Produces: `EmotheWeb.Admin.PlayPlacesLive` at `/admin/plays/:id/places`; `play_context_bar` accepts `active_tab={:places}`.

- [ ] **Step 1: Write the failing test**

Create `test/emothe_web/live/admin/play_places_live_test.exs`:

```elixir
defmodule EmotheWeb.Admin.PlayPlacesLiveTest do
  use EmotheWeb.ConnCase, async: true

  import Phoenix.LiveViewTest

  alias Emothe.Places
  alias Emothe.TestFixtures

  defp t(msgid), do: Gettext.gettext(EmotheWeb.Gettext, msgid)

  defp setup_play(conn) do
    conn = log_in_user(conn, TestFixtures.user_fixture(role: :researcher))
    play = TestFixtures.play_fixture()
    {conn, play}
  end

  test "the context bar offers Places beside Sources and Content", %{conn: conn} do
    {conn, play} = setup_play(conn)
    {:ok, _view, html} = live(conn, ~p"/admin/plays/#{play.id}/places")

    assert html =~ ~p"/admin/plays/#{play.id}/sources"
    assert html =~ ~p"/admin/plays/#{play.id}/content"
    assert html =~ t("Places")
  end

  test "an existing place is linked from the picker", %{conn: conn} do
    {conn, play} = setup_play(conn)
    place = TestFixtures.place_fixture(%{"name" => "Roma"})

    {:ok, view, _html} = live(conn, ~p"/admin/plays/#{play.id}/places")

    html =
      view
      |> element("form[phx-submit=link]")
      |> render_submit(%{"place_id" => place.id, "role" => "setting"})

    assert html =~ "Roma"
    assert [link] = Places.list_play_places(play.id)
    assert link.role == "setting"
    assert link.origin == "manual"
  end

  test "role and note are editable in place", %{conn: conn} do
    {conn, play} = setup_play(conn)
    place = TestFixtures.place_fixture(%{"name" => "Miseno"})
    link = TestFixtures.play_place_fixture(play, place)

    {:ok, view, _html} = live(conn, ~p"/admin/plays/#{play.id}/places")

    view
    |> element("form[phx-submit=update_link][id='link-form-#{link.id}']")
    |> render_submit(%{"play_place" => %{"role" => "mentioned", "note" => "Named, not staged."}})

    assert [updated] = Places.list_play_places(play.id)
    assert updated.role == "mentioned"
    assert updated.note == "Named, not staged."
  end

  test "links reorder", %{conn: conn} do
    {conn, play} = setup_play(conn)
    roma = TestFixtures.place_fixture(%{"name" => "Roma"})
    miseno = TestFixtures.place_fixture(%{"name" => "Miseno"})
    first = TestFixtures.play_place_fixture(play, roma)
    _second = TestFixtures.play_place_fixture(play, miseno)

    {:ok, view, _html} = live(conn, ~p"/admin/plays/#{play.id}/places")

    view |> element("button[phx-click=move_down][phx-value-id='#{first.id}']") |> render_click()

    assert Places.list_play_places(play.id)
           |> Enum.map(&Places.display_name(&1.place, "es")) == ["Miseno", "Roma"]
  end

  test "unlinking keeps the place in the gazetteer", %{conn: conn} do
    {conn, play} = setup_play(conn)
    place = TestFixtures.place_fixture(%{"name" => "Roma"})
    link = TestFixtures.play_place_fixture(play, place)

    {:ok, view, _html} = live(conn, ~p"/admin/plays/#{play.id}/places")

    view |> element("button[phx-click=unlink][phx-value-id='#{link.id}']") |> render_click()

    assert Places.list_play_places(play.id) == []
    assert Places.list_places() != []
  end

  test "a new place is created and linked in one pass", %{conn: conn} do
    {conn, play} = setup_play(conn)
    {:ok, view, _html} = live(conn, ~p"/admin/plays/#{play.id}/places")

    view |> element("button", t("New place")) |> render_click()

    view
    |> form("#place-form",
      place: %{
        "type" => "city",
        "names" => %{"0" => %{"name" => "Alexandría", "language" => "es", "is_preferred" => "true"}}
      }
    )
    |> render_submit()

    assert [link] = Places.list_play_places(play.id)
    assert Places.display_name(link.place, "es") == "Alexandría"
  end
end
```

- [ ] **Step 2: Run it and watch it fail**

```bash
mix test test/emothe_web/live/admin/play_places_live_test.exs
```

Expected: FAIL — no route for `/admin/plays/:id/places`.

- [ ] **Step 3: Write the LiveView**

Create `lib/emothe_web/live/admin/play_places_live.ex`:

```elixir
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
    case Places.link_place(socket.assigns.play.id, place_id, %{"role" => params["role"] || "setting"}) do
      {:ok, link} ->
        log(socket, "create", link)
        {:noreply, socket |> load_links() |> put_flash(:info, gettext("Place added."))}

      {:error, _changeset} ->
        {:noreply,
         put_flash(socket, :error, gettext("That place is already linked to this play."))}
    end
  end

  def handle_event("update_link", %{"id" => id, "play_place" => params}, socket) do
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
    {:noreply, assign(socket, :editing, %Place{names: []})}
  end

  def handle_event("cancel_edit", _params, socket) do
    {:noreply, assign(socket, :editing, nil)}
  end

  @impl true
  def handle_info({:place_saved, place}, socket) do
    {:ok, _} = Places.link_place(socket.assigns.play.id, place.id, %{})

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
            <input type="hidden" name="id" value={link.id} />
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
```

- [ ] **Step 4: Add the route and the context-bar tab**

In `lib/emothe_web/router.ex`, after `live "/plays/:id/sources", PlaySourcesLive, :index`:

```elixir
      live "/plays/:id/places", PlayPlacesLive, :index
```

In `lib/emothe_web/components/layouts.ex`, extend the `active_tab` doc at line 105 to include `:places`, and insert this link between the Sources and Content links:

```elixir
          <.link
            navigate={~p"/admin/plays/#{@play.id}/places"}
            class={ctx_tab_class(@active_tab == :places)}
          >
            {gettext("Places")}
          </.link>
```

- [ ] **Step 5: Run it and watch it pass**

```bash
mix test test/emothe_web/live/admin/play_places_live_test.exs
```

Expected: PASS, 6 tests.

- [ ] **Step 6: Whole suite, format, commit**

```bash
mix test && mix format && mix compile --warnings-as-errors
git add lib/emothe_web test/emothe_web/live/admin/play_places_live_test.exs
git commit -m "feat: a per-play place index, as a peer tab in the context bar"
```

---

### Task 9: The public panel and the static site

`#meta-places` on `/plays/:code`, hidden when the play has none, in the sidebar scroll-spy. Coordinates are stored and not drawn — no map in Phase 1.

The static-site renderer gets the same section **and** the `historical_time` row S2a never added, because leaving one out while adding the other produces a visibly inconsistent panel in the archival output.

**Files:**
- Modify: `lib/emothe/catalogue.ex:69-95`, `lib/emothe_web/live/play_show_live.ex:340,391`, `lib/emothe/export/static_site/renderer.ex:85`
- Test: `test/emothe_web/live/play_show_live_test.exs`, `test/emothe/export/static_site_test.exs`

**Interfaces:**
- Consumes: `Places.display_name/2`, `breadcrumb/3`, `gazetteer/0`, `Authority.url/2`, `PlayLabels.place_role_label/1`.
- Produces: `Catalogue.get_play_with_all!/2` and `get_play_by_code_with_all!/2` preload `play_places: [place: :names]`, ordered by `position`.

- [ ] **Step 1: Write the failing test**

Append to `test/emothe_web/live/play_show_live_test.exs`:

```elixir
  describe "the places panel" do
    defp t(msgid), do: Gettext.gettext(EmotheWeb.Gettext, msgid)

    test "is absent when the play has no places", %{conn: conn} do
      play = Emothe.TestFixtures.play_fixture()
      {:ok, _view, html} = live(conn, ~p"/plays/#{play.code}")

      refute html =~ "meta-places"
    end

    test "lists settings before mentions, with breadcrumb and note", %{conn: conn} do
      play = Emothe.TestFixtures.play_fixture()

      italy =
        Emothe.TestFixtures.place_fixture(%{"name" => "Italia", "type" => "country"})

      roma =
        Emothe.TestFixtures.place_fixture(%{"name" => "Roma", "parent_place_id" => italy.id})

      miseno = Emothe.TestFixtures.place_fixture(%{"name" => "Miseno"})

      Emothe.TestFixtures.play_place_fixture(play, miseno, %{
        "role" => "mentioned",
        "note" => "Named, not staged."
      })

      Emothe.TestFixtures.play_place_fixture(play, roma, %{"role" => "setting"})

      {:ok, _view, html} = live(conn, ~p"/plays/#{play.code}")

      assert html =~ "meta-places"
      assert html =~ "Roma, Italia"
      assert html =~ "Named, not staged."
      assert html =~ t("Places")

      # settings first, whatever order they were linked in
      assert :binary.match(html, "Roma") < :binary.match(html, "Miseno")
    end

    test "a fictional place is marked", %{conn: conn} do
      play = Emothe.TestFixtures.play_fixture()

      atlantis =
        Emothe.TestFixtures.place_fixture(%{
          "name" => "Atlántida",
          "type" => "island",
          "is_fictional" => "true"
        })

      Emothe.TestFixtures.play_place_fixture(play, atlantis)

      {:ok, _view, html} = live(conn, ~p"/plays/#{play.code}")
      assert html =~ t("Fictional")
    end
  end
```

And append to `test/emothe/export/static_site_test.exs`:

```elixir
  test "a play page carries its places and its historical time" do
    play =
      Emothe.TestFixtures.play_fixture(%{
        "is_complete" => true,
        "historical_time" => "siglo_xvii"
      })

    place = Emothe.TestFixtures.place_fixture(%{"name" => "Roma"})
    Emothe.TestFixtures.play_place_fixture(play, place)

    play = Emothe.Catalogue.get_play_with_all!(play.id)
    html = Emothe.Export.StaticSite.Renderer.play_page(play, [], [], nil, [])

    assert html =~ "Roma"
    assert html =~ "17th century"
  end
```

- [ ] **Step 2: Run it and watch it fail**

```bash
mix test test/emothe_web/live/play_show_live_test.exs test/emothe/export/static_site_test.exs
```

Expected: FAIL — `meta-places` missing, and `KeyError` or `NotLoaded` on `play_places`.

- [ ] **Step 3: Preload the links**

In `lib/emothe/catalogue.ex`, add `alias Emothe.Places.PlayPlace` at the top, and in **both** `get_play_with_all!/2` and `get_play_by_code_with_all!/2` add to the preload list:

```elixir
      play_places: {from(pp in PlayPlace, order_by: pp.position), [place: :names]}
```

- [ ] **Step 4: Render the public section**

In `lib/emothe_web/live/play_show_live.ex`, add `alias Emothe.Places` and `alias Emothe.Places.Authority` at the top. After the `#meta-study` section closes (line 340), insert:

```elixir
          <section
            :if={@play.play_places != []}
            id="meta-places"
            class="mb-8 max-w-2xl mx-auto scroll-mt-20 text-sm"
          >
            <dl class="grid grid-cols-[max-content_1fr] gap-x-4 gap-y-2">
              <dt class="text-base-content/50">{gettext("Places")}</dt>
              <dd>
                <ul class="space-y-1">
                  <li :for={link <- sorted_places(@play.play_places)}>
                    <span>{Places.breadcrumb(link.place, @gazetteer, @locale)}</span>
                    <span :if={link.role == "mentioned"} class="text-xs text-base-content/50">
                      ({PlayLabels.place_role_label(link.role)})
                    </span>
                    <span :if={link.place.is_fictional} class="badge badge-outline badge-xs">
                      {gettext("Fictional")}
                    </span>
                    <a
                      :if={Authority.url(link.place.authority, link.place.authority_id)}
                      href={Authority.url(link.place.authority, link.place.authority_id)}
                      target="_blank"
                      class="link text-xs"
                    >
                      {Authority.label(link.place.authority)}
                    </a>
                    <p :if={link.note} class="text-xs text-base-content/60">{link.note}</p>
                  </li>
                </ul>
              </dd>
            </dl>
          </section>
```

Add two private helpers near `maybe_add_section/4`:

```elixir
  # Settings first, then mentions, each keeping its own curated order.
  defp sorted_places(play_places) do
    Enum.sort_by(play_places, fn link -> {link.role != "setting", link.position} end)
  end
```

In `mount/3`, assign the gazetteer and the locale the breadcrumb needs:

```elixir
     |> assign(:gazetteer, Emothe.Places.gazetteer())
     |> assign(:locale, Gettext.get_locale(EmotheWeb.Gettext))
```

And in `build_sections_navigation/2`, after the `meta-study` line:

```elixir
    |> maybe_add_section(play.play_places != [], "meta-places", gettext("Places"))
```

- [ ] **Step 5: Render the static-site section**

In `lib/emothe/export/static_site/renderer.ex`, add `#{render_places(play)}` and `#{render_study(play)}` to the header block right after `#{render_verse_info(play)}`, then add both private functions beside `render_sources/1`:

```elixir
  defp render_study(%{historical_time: nil}), do: ""

  defp render_study(play) do
    note =
      if play.historical_time_note,
        do: "<p class=\"meta-note\">#{escape(play.historical_time_note)}</p>",
        else: ""

    """
          <p class="historical-time">Historical time: #{escape(EmotheWeb.PlayLabels.historical_time_label(play.historical_time))}</p>
    #{note}
    """
  end

  defp render_places(%{play_places: []}), do: ""

  defp render_places(%{play_places: links} = _play) when is_list(links) do
    gazetteer = Emothe.Places.gazetteer()

    items =
      links
      |> Enum.sort_by(fn link -> {link.role != "setting", link.position} end)
      |> Enum.map_join("\n", fn link ->
        role = if link.role == "mentioned", do: " (mentioned)", else: ""
        note = if link.note, do: " — #{escape(link.note)}", else: ""

        "        <li>#{escape(Emothe.Places.breadcrumb(link.place, gazetteer, "es"))}#{role}#{note}</li>"
      end)

    """
          <div class="places">
            <p class="places-label">Places</p>
            <ul>
    #{items}
            </ul>
          </div>
    """
  end

  defp render_places(_play), do: ""
```

- [ ] **Step 6: Run it and watch it pass**

```bash
mix test test/emothe_web/live/play_show_live_test.exs test/emothe/export/static_site_test.exs
```

Expected: PASS.

- [ ] **Step 7: Whole suite, format, commit**

```bash
mix test && mix format && mix compile --warnings-as-errors
git add lib/emothe lib/emothe_web test/emothe_web/live/play_show_live_test.exs test/emothe/export/static_site_test.exs
git commit -m "feat: show a play's places on the public page and in the static site"
```

---

### Task 10: TEI export

`<listPlace>` nests places to express containment; `<setting>` lists the play's links. Two elements because a nested `<place>` can be a pure container, and on import there would otherwise be no way to tell a container from a setting — "leaves are the settings" is wrong, since a play can be set in Italy itself.

**Files:**
- Modify: `lib/emothe/export/tei_xml.ex:11-14,281-289`
- Test: `test/emothe/export/tei_xml_test.exs`

**Interfaces:**
- Consumes: `Places.gazetteer/0`, `Places.ancestors/2`.
- Produces: `<profileDesc>` gains `<settingDesc>` when the play has places. `<place>` carries `xml:id` (the slug), `type`, and `subtype="fictional"` when fictional; `<placeName>` carries `xml:lang` and `type="historical"`; `<location><geo>` is `"lat long"`; `<idno type="wikidata">`; `<setting>` holds one `<placeName ref="#slug" ana="role">` per link, with an inner `<note>` for the link note.

- [ ] **Step 1: Write the failing test**

Append to `test/emothe/export/tei_xml_test.exs`:

```elixir
  describe "places" do
    setup do
      play = play_fixture()

      europe = place_fixture(%{"name" => "Europa", "type" => "continent", "slug" => "europa"})

      italy =
        place_fixture(%{
          "names" => [
            %{"name" => "Italia", "language" => "es", "is_preferred" => "true"},
            %{"name" => "Italy", "language" => "en", "is_preferred" => "true"}
          ],
          "type" => "country",
          "slug" => "italia",
          "parent_place_id" => europe.id
        })

      roma =
        place_fixture(%{
          "name" => "Roma",
          "type" => "city",
          "slug" => "roma",
          "parent_place_id" => italy.id,
          "latitude" => "41.9028",
          "longitude" => "12.4964",
          "authority" => "wikidata",
          "authority_id" => "Q220"
        })

      miseno =
        place_fixture(%{
          "name" => "Miseno",
          "type" => "town",
          "slug" => "miseno",
          "parent_place_id" => italy.id
        })

      play_place_fixture(play, roma, %{"role" => "setting"})
      play_place_fixture(play, miseno, %{"role" => "mentioned", "note" => "Named, not staged."})

      %{xml: Emothe.Export.TeiXml.generate(Emothe.Catalogue.get_play_with_all!(play.id))}
    end

    test "containment is expressed by nesting", %{xml: xml} do
      assert xml =~ ~s(<settingDesc>)
      assert xml =~ ~s(<place xml:id="europa" type="continent">)
      assert :binary.match(xml, ~s(xml:id="europa")) < :binary.match(xml, ~s(xml:id="italia"))
      assert :binary.match(xml, ~s(xml:id="italia")) < :binary.match(xml, ~s(xml:id="roma"))
    end

    test "a place carries its names, coordinates and authority id", %{xml: xml} do
      assert xml =~ ~s(<placeName xml:lang="es">Italia</placeName>)
      assert xml =~ ~s(<placeName xml:lang="en">Italy</placeName>)
      assert xml =~ ~s(<geo>41.9028 12.4964</geo>)
      assert xml =~ ~s(<idno type="wikidata">Q220</idno>)
    end

    test "the play's own links live in setting, with role and note", %{xml: xml} do
      assert xml =~ ~s(<placeName ref="#roma" ana="setting"/>)
      assert xml =~ ~s(ref="#miseno" ana="mentioned")
      assert xml =~ "Named, not staged."
    end

    test "a play with no places emits no settingDesc" do
      play = play_fixture()
      xml = Emothe.Export.TeiXml.generate(Emothe.Catalogue.get_play_with_all!(play.id))
      refute xml =~ "settingDesc"
    end

    test "a fictional place is marked with a subtype and has no location" do
      play = play_fixture()

      atlantis =
        place_fixture(%{
          "name" => "Atlántida",
          "type" => "island",
          "slug" => "atlantida",
          "is_fictional" => "true"
        })

      play_place_fixture(play, atlantis)

      xml = Emothe.Export.TeiXml.generate(Emothe.Catalogue.get_play_with_all!(play.id))

      assert xml =~ ~s(<place xml:id="atlantida" type="island" subtype="fictional">)
      refute xml =~ "<geo>"
    end
  end
```

Make sure the test module imports the fixtures — add `import Emothe.TestFixtures` at the top if it is not already there.

- [ ] **Step 2: Run it and watch it fail**

```bash
mix test test/emothe/export/tei_xml_test.exs
```

Expected: FAIL — no `settingDesc` in the output.

- [ ] **Step 3: Implement**

In `lib/emothe/export/tei_xml.ex`, extend the preload in `generate/1`:

```elixir
    play =
      Emothe.Repo.preload(play, [
        :editors,
        :sources,
        :editorial_notes,
        play_places: [place: :names]
      ])
```

Replace `build_profile_desc/1` and add the builders below it:

```elixir
  defp build_profile_desc(play) do
    {ident, label} = Map.get(@language_ident_labels, play.language || "es", {"es-ES", "Español"})

    children = [
      element(:langUsage, [element(:language, %{ident: ident}, label)])
    ]

    element(:profileDesc, children ++ build_setting_desc(play))
  end

  # Two elements, on purpose. `listPlace` nests every place the play needs *plus every
  # ancestor*, so containment is complete — which means a `<place>` may be a pure
  # container. `setting` is therefore what says which of them the play actually
  # references, because "the leaves are the settings" is wrong: a play can be set in
  # Italy itself.
  defp build_setting_desc(%{play_places: []}), do: []

  defp build_setting_desc(%{play_places: links}) when is_list(links) do
    gazetteer = Emothe.Places.gazetteer()
    ordered = Enum.sort_by(links, fn link -> {link.role != "setting", link.position} end)

    roots =
      ordered
      |> Enum.map(& &1.place)
      |> Enum.flat_map(fn place ->
        [place | Emothe.Places.ancestors(place, gazetteer)]
      end)
      |> Enum.uniq_by(& &1.id)
      |> Enum.filter(&is_nil(&1.parent_place_id))

    wanted =
      ordered
      |> Enum.map(& &1.place)
      |> Enum.flat_map(fn place -> [place | Emothe.Places.ancestors(place, gazetteer)] end)
      |> MapSet.new(& &1.id)

    [
      element(:settingDesc, [
        element(:listPlace, Enum.map(roots, &build_place(&1, gazetteer, wanted))),
        element(:setting, Enum.map(ordered, &build_setting_ref/1))
      ])
    ]
  end

  defp build_setting_desc(_play), do: []

  defp build_place(place, gazetteer, wanted) do
    attrs =
      %{"xml:id" => place.slug, "type" => place.type}
      |> then(fn attrs ->
        if place.is_fictional, do: Map.put(attrs, "subtype", "fictional"), else: attrs
      end)

    children =
      Enum.map(place.names, &build_place_name/1) ++
        build_location(place) ++
        build_place_idno(place) ++
        build_place_note(place) ++
        child_places(place, gazetteer, wanted)

    element(:place, attrs, children)
  end

  defp child_places(place, gazetteer, wanted) do
    gazetteer
    |> Map.values()
    |> Enum.filter(&(&1.parent_place_id == place.id and MapSet.member?(wanted, &1.id)))
    |> Enum.sort_by(& &1.slug)
    |> Enum.map(&build_place(&1, gazetteer, wanted))
  end

  defp build_place_name(name) do
    attrs = if name.language, do: %{"xml:lang" => name.language}, else: %{}
    attrs = if name.is_historical, do: Map.put(attrs, "type", "historical"), else: attrs
    element(:placeName, attrs, name.name)
  end

  defp build_location(%{latitude: nil}), do: []
  defp build_location(%{longitude: nil}), do: []

  defp build_location(place) do
    [element(:location, [element(:geo, "#{place.latitude} #{place.longitude}")])]
  end

  defp build_place_idno(%{authority: nil}), do: []
  defp build_place_idno(%{authority_id: nil}), do: []

  defp build_place_idno(place) do
    [element(:idno, %{type: place.authority}, place.authority_id)]
  end

  defp build_place_note(%{note: nil}), do: []
  defp build_place_note(%{note: ""}), do: []
  defp build_place_note(place), do: [element(:note, place.note)]

  # `@ana` normally points at an interpretation element; a bare token is a project
  # convention, chosen over `@type` because `@type` on a `<placeName>` already means
  # historical-versus-current inside `<listPlace>`, and one attribute with two meanings
  # in one file is how a parser acquires a bug.
  defp build_setting_ref(link) do
    attrs = %{"ref" => "##{link.place.slug}", "ana" => link.role}

    case link.note do
      note when is_binary(note) and note != "" ->
        element(:placeName, attrs, [element(:note, note)])

      _ ->
        element(:placeName, attrs, nil)
    end
  end
```

- [ ] **Step 4: Run it and watch it pass**

```bash
mix test test/emothe/export/tei_xml_test.exs
```

Expected: PASS.

- [ ] **Step 5: Whole suite, format, commit**

```bash
mix test && mix format && mix compile --warnings-as-errors
git add lib/emothe/export/tei_xml.ex test/emothe/export/tei_xml_test.exs
git commit -m "feat: export a play's places as nested listPlace plus setting"
```

---

### Task 11: TEI import

Read `<listPlace>` into places and `<setting>` into links. An existing slug is **left alone**, never overwritten — the gazetteer is curated and the file may be stale. Links are stamped `origin: "tei"`, and a re-import replaces only those.

**Files:**
- Modify: `lib/emothe/import/tei_parser.ex:248-256,267-272`
- Test: `test/emothe/import/tei_parser_test.exs`

**Interfaces:**
- Consumes: `Places.find_or_create_by_slug/1`, `Places.link_place/3`, `Places.delete_tei_play_places/1`, `Places.slugify/1`.
- Produces: `TeiParser.import_file/1` creates places and `origin: "tei"` links from `profileDesc/settingDesc`.

- [ ] **Step 1: Write the failing test**

Append to `test/emothe/import/tei_parser_test.exs`. The helper writing a temp TEI file follows the existing pattern in that file — reuse whatever it already has; if it has none, this is it:

```elixir
  describe "places" do
    @places_tei """
    <?xml version="1.0" encoding="UTF-8"?>
    <TEI xmlns="http://www.tei-c.org/ns/1.0" xml:lang="es">
      <teiHeader>
        <fileDesc>
          <titleStmt><title>Play With Places</title><title key="archivo">PLACES0001</title></titleStmt>
          <publicationStmt><p/></publicationStmt>
          <sourceDesc><p/></sourceDesc>
        </fileDesc>
        <profileDesc>
          <langUsage><language ident="es-ES">Español</language></langUsage>
          <settingDesc>
            <listPlace>
              <place xml:id="italia" type="country">
                <placeName xml:lang="es">Italia</placeName>
                <place xml:id="roma" type="city">
                  <placeName xml:lang="es">Roma</placeName>
                  <placeName xml:lang="en">Rome</placeName>
                  <placeName xml:lang="la" type="historical">Roma Aeterna</placeName>
                  <location><geo>41.9028 12.4964</geo></location>
                  <idno type="wikidata">Q220</idno>
                </place>
                <place xml:id="miseno" type="town">
                  <placeName xml:lang="it">Miseno</placeName>
                </place>
              </place>
            </listPlace>
            <setting>
              <placeName ref="#roma" ana="setting"/>
              <placeName ref="#miseno" ana="mentioned"><note>Named, not staged.</note></placeName>
            </setting>
          </settingDesc>
        </profileDesc>
      </teiHeader>
      <text><body><div1 type="acto" n="1"><head>Acto I</head></div1></body></text>
    </TEI>
    """

    defp import_places_tei(xml \\ @places_tei) do
      path = Path.join(System.tmp_dir!(), "places-#{System.unique_integer([:positive])}.xml")
      File.write!(path, xml)
      on_exit(fn -> File.rm(path) end)
      Emothe.Import.TeiParser.import_file(path)
    end

    test "creates the places, their names and the containment" do
      {:ok, play} = import_places_tei()

      roma = Emothe.Repo.get_by!(Emothe.Places.Place, slug: "roma")
      roma = Emothe.Places.get_place!(roma.id)

      assert roma.type == "city"
      assert roma.latitude == 41.9028
      assert roma.longitude == 12.4964
      assert roma.authority == "wikidata"
      assert roma.authority_id == "Q220"
      assert roma.parent.slug == "italia"

      names = Map.new(roma.names, &{&1.language, &1})
      assert names["es"].name == "Roma"
      assert names["en"].name == "Rome"
      assert names["la"].is_historical

      assert play.code == "PLACES0001"
    end

    test "only the places named in setting become play links" do
      {:ok, play} = import_places_tei()

      links = Emothe.Places.list_play_places(play.id)

      assert Enum.map(links, & &1.place.slug) == ["roma", "miseno"]
      assert Enum.map(links, & &1.role) == ["setting", "mentioned"]
      assert Enum.map(links, & &1.origin) == ["tei", "tei"]
      assert Enum.at(links, 1).note == "Named, not staged."

      # italia is a container, not a setting
      refute "italia" in Enum.map(links, & &1.place.slug)
    end

    test "a re-import replaces its own links and leaves a hand-entered one alone" do
      {:ok, play} = import_places_tei()

      extra = Emothe.TestFixtures.place_fixture(%{"name" => "Atenas"})
      Emothe.TestFixtures.play_place_fixture(play, extra, %{"origin" => "manual"})

      {:ok, _play} = import_places_tei()

      slugs = Emothe.Places.list_play_places(play.id) |> Enum.map(& &1.place.slug)
      assert "roma" in slugs
      assert extra.slug in slugs
      assert length(slugs) == 3
    end

    test "an existing place is left alone, not overwritten" do
      curated =
        Emothe.TestFixtures.place_fixture(%{
          "name" => "Roma",
          "slug" => "roma",
          "type" => "region",
          "note" => "Curated"
        })

      {:ok, _play} = import_places_tei()

      reloaded = Emothe.Places.get_place!(curated.id)
      assert reloaded.type == "region"
      assert reloaded.note == "Curated"
    end

    test "a file with no settingDesc creates no places" do
      xml = String.replace(@places_tei, ~r|<settingDesc>.*</settingDesc>|s, "")
      {:ok, play} = import_places_tei(xml)

      assert Emothe.Places.list_play_places(play.id) == []
      assert Emothe.Places.list_places() == []
    end
  end
```

- [ ] **Step 2: Run it and watch it fail**

```bash
mix test test/emothe/import/tei_parser_test.exs
```

Expected: FAIL — `Emothe.Repo.get_by!/2` raises `Ecto.NoResultsError`, no place was created.

- [ ] **Step 3: Implement**

In `lib/emothe/import/tei_parser.ex`, add `alias Emothe.Places` near the other aliases. Extend `reset_tei_content/1`:

```elixir
  defp reset_tei_content(%Play{id: id} = play) do
    for schema <- [Element, Division, Character] do
      Repo.delete_all(from(r in schema, where: r.play_id == ^id))
    end

    for schema <- [PlayEditor, PlaySource, PlayEditorialNote] do
      Repo.delete_all(from(r in schema, where: r.play_id == ^id and r.origin == "tei"))
    end

    # Only the links, never the places: the gazetteer is corpus-global authority data,
    # and an orphaned place shows in the admin list with a play count of 0.
    Places.delete_tei_play_places(play.id)
  end
```

In `import_header/1`, after the play has been created or updated and before the function returns it, add:

```elixir
    import_places(profile_desc, play)
```

Then add the importer itself:

```elixir
  # `listPlace` supplies the places and their containment; `setting` supplies this
  # play's links. Reading them separately is what keeps a pure container — Italia in
  # `<place xml:id="italia">…<place xml:id="roma">` — from becoming a setting.
  defp import_places(nil, _play), do: :ok

  defp import_places({_name, _attrs, children}, play) do
    case find_child(children, "settingDesc") do
      nil ->
        :ok

      {_n, _a, setting_children} ->
        list_place = find_child(setting_children, "listPlace")
        setting = find_child(setting_children, "setting")

        if list_place, do: import_list_place(list_place, nil)
        if setting, do: import_setting(setting, play)

        :ok
    end
  end

  defp import_list_place({_name, _attrs, children}, parent_id) do
    children
    |> Enum.filter(&match?({"place", _, _}, &1))
    |> Enum.each(&import_place(&1, parent_id))
  end

  defp import_place({_name, attrs, children} = place_el, parent_id) do
    slug = attr_value(attrs, "xml:id") || Places.slugify(first_place_name(children))
    {latitude, longitude} = place_geo(children)

    place_attrs =
      %{
        "slug" => slug,
        "type" => attr_value(attrs, "type") || "other",
        "parent_place_id" => parent_id,
        "is_fictional" => attr_value(attrs, "subtype") == "fictional",
        "latitude" => latitude,
        "longitude" => longitude,
        "note" => place_note(children),
        "names" => place_names(children)
      }
      |> Map.merge(place_idno(children))

    case Places.find_or_create_by_slug(place_attrs) do
      {:ok, place, outcome} ->
        if outcome == :existing do
          Logger.info("TEI import: place #{slug} already exists, left unchanged")
        end

        # Nested <place> elements are this place's children.
        import_list_place(place_el, place.id)

      {:error, changeset} ->
        Logger.warning("TEI import: could not create place #{slug}: #{inspect(changeset.errors)}")
    end
  end

  defp place_names(children) do
    children
    |> Enum.filter(&match?({"placeName", _, _}, &1))
    |> Enum.with_index()
    |> Enum.map(fn {{_n, attrs, _c} = el, index} ->
      language = attr_value(attrs, "xml:lang")

      %{
        "name" => text_content(el),
        "language" => language,
        "is_historical" => attr_value(attrs, "type") == "historical",
        "is_preferred" => attr_value(attrs, "type") != "historical",
        "position" => index
      }
    end)
    |> Enum.reject(&(&1["name"] in [nil, ""]))
    |> dedupe_preferred()
  end

  # The partial index allows one preferred name per language; a file with two
  # non-historical names in the same language would violate it, so the first wins.
  defp dedupe_preferred(names) do
    {names, _seen} =
      Enum.map_reduce(names, MapSet.new(), fn name, seen ->
        key = name["language"]

        if name["is_preferred"] and not MapSet.member?(seen, key) do
          {name, MapSet.put(seen, key)}
        else
          {Map.put(name, "is_preferred", false), seen}
        end
      end)

    names
  end

  defp first_place_name(children) do
    case Enum.find(children, &match?({"placeName", _, _}, &1)) do
      nil -> "place"
      el -> text_content(el)
    end
  end

  defp place_geo(children) do
    with {_n, _a, location_children} <- find_child(children, "location"),
         geo when not is_nil(geo) <- find_child(location_children, "geo"),
         [lat, long] <- geo |> text_content() |> String.split(~r/\s+/, trim: true),
         {latitude, _} <- Float.parse(lat),
         {longitude, _} <- Float.parse(long) do
      {latitude, longitude}
    else
      _ -> {nil, nil}
    end
  end

  defp place_idno(children) do
    case find_child(children, "idno") do
      {_n, attrs, _c} = el ->
        authority = attr_value(attrs, "type")

        if authority in Emothe.Places.Place.authorities() do
          %{"authority" => authority, "authority_id" => text_content(el)}
        else
          %{}
        end

      _ ->
        %{}
    end
  end

  defp place_note(children) do
    case find_child(children, "note") do
      nil -> nil
      el -> text_content(el)
    end
  end

  defp import_setting({_name, _attrs, children}, play) do
    children
    |> Enum.filter(&match?({"placeName", _, _}, &1))
    |> Enum.with_index()
    |> Enum.each(fn {{_n, attrs, name_children}, index} ->
      slug = attrs |> attr_value("ref") |> to_string() |> String.trim_leading("#")

      case Repo.get_by(Emothe.Places.Place, slug: slug) do
        nil ->
          Logger.warning("TEI import: setting references unknown place #{inspect(slug)}")

        place ->
          Places.link_place(play.id, place.id, %{
            "role" => attr_value(attrs, "ana") || "setting",
            "position" => index,
            "note" => setting_note(name_children),
            "origin" => "tei"
          })
      end
    end)
  end

  defp setting_note(children) do
    case find_child(children, "note") do
      nil -> nil
      el -> text_content(el)
    end
  end
```

- [ ] **Step 4: Run it and watch it pass**

```bash
mix test test/emothe/import/tei_parser_test.exs
```

Expected: PASS.

- [ ] **Step 5: Whole suite, format, commit**

```bash
mix test && mix format && mix compile --warnings-as-errors
git add lib/emothe/import/tei_parser.ex test/emothe/import/tei_parser_test.exs
git commit -m "feat: import listPlace and setting, leaving curated places alone"
```

---

### Task 12: Roundtrip, translations, verification

The real fixtures carry no `<listPlace>`, so a roundtrip assertion over them would be vacuous. This proves the loop with a synthetic play instead, and asserts the fixtures still produce zero places so the parser gained no false positives.

**Files:**
- Modify: `test/emothe/export/roundtrip_test.exs`, `priv/gettext/es/LC_MESSAGES/default.po`, `CLAUDE.md`
- Test: as above

**Interfaces:**
- Consumes: everything from Tasks 2–11.
- Produces: no new interface.

- [ ] **Step 1: Write the failing test**

Append to `test/emothe/export/roundtrip_test.exs`:

```elixir
  describe "places roundtrip" do
    test "export, import and re-export produce the same places" do
      play = Emothe.TestFixtures.play_fixture(%{"code" => "ROUNDPLACE1"})

      italy =
        Emothe.TestFixtures.place_fixture(%{
          "name" => "Italia",
          "type" => "country",
          "slug" => "italia"
        })

      roma =
        Emothe.TestFixtures.place_fixture(%{
          "names" => [
            %{"name" => "Roma", "language" => "es", "is_preferred" => "true"},
            %{"name" => "Rome", "language" => "en", "is_preferred" => "true"}
          ],
          "type" => "city",
          "slug" => "roma",
          "parent_place_id" => italy.id,
          "latitude" => "41.9028",
          "longitude" => "12.4964",
          "authority" => "wikidata",
          "authority_id" => "Q220"
        })

      miseno =
        Emothe.TestFixtures.place_fixture(%{
          "name" => "Miseno",
          "type" => "town",
          "slug" => "miseno",
          "parent_place_id" => italy.id
        })

      Emothe.TestFixtures.play_place_fixture(play, roma, %{"role" => "setting"})

      Emothe.TestFixtures.play_place_fixture(play, miseno, %{
        "role" => "mentioned",
        "note" => "Named, not staged."
      })

      first = Emothe.Export.TeiXml.generate(Emothe.Catalogue.get_play_with_all!(play.id))

      path = Path.join(System.tmp_dir!(), "roundtrip-places.xml")
      File.write!(path, first)
      on_exit(fn -> File.rm(path) end)

      {:ok, reimported} = Emothe.Import.TeiParser.import_file(path)
      second = Emothe.Export.TeiXml.generate(Emothe.Catalogue.get_play_with_all!(reimported.id))

      assert settings(second) == settings(first)
      assert place_ids(second) == place_ids(first)
      assert second =~ ~s(<geo>41.9028 12.4964</geo>)
      assert second =~ ~s(<idno type="wikidata">Q220</idno>)
      assert second =~ "Named, not staged."
    end

    defp settings(xml), do: Regex.scan(~r/ref="#([^"]+)" ana="([^"]+)"/, xml)
    defp place_ids(xml), do: Regex.scan(~r/<place xml:id="([^"]+)"/, xml)

    test "the real fixtures still produce no places" do
      # Whatever the existing suite uses to walk the fixture corpus, reuse it. This
      # asserts only that the new parser branch never fires on a file without places.
      assert Emothe.Places.list_places() == []
    end
  end
```

- [ ] **Step 2: Run it and watch it fail**

```bash
mix test test/emothe/export/roundtrip_test.exs
```

Expected: FAIL on the first assertion until Tasks 10 and 11 are both in — if they are, this should pass immediately, in which case confirm by temporarily breaking `build_setting_ref/1` and watching it fail, then reverting.

- [ ] **Step 3: Extract and merge the translations**

```bash
mix gettext.extract --merge
```

`mix gettext.extract --merge` fuzzy-matches new strings onto unrelated existing translations. **Check every entry it marks fuzzy** and fix it. Then fill in the Spanish for every new msgid in `priv/gettext/es/LC_MESSAGES/default.po`:

```
Places → Lugares
New place → Nuevo lugar
Edit place → Editar lugar
Place saved. → Lugar guardado.
Place deleted. → Lugar eliminado.
Place added. → Lugar añadido.
Place updated. → Lugar actualizado.
Place removed. → Lugar eliminado del texto.
Place created and added. → Lugar creado y añadido.
Names → Nombres
Name → Nombre
Add name → Añadir nombre
Preferred → Preferido
Historical → Histórico
Type → Tipo
Contained in → Contenido en
Latitude → Latitud
Longitude → Longitud
Slug → Identificador
Wikidata id → Identificador de Wikidata
Fictional place → Lugar ficticio
Fictional → Ficticio
Note → Nota
Search Wikidata → Buscar en Wikidata
— none — → — ninguno —
Role → Función
Setting → Escenario
Mentioned → Mencionado
Add → Añadir
Add an existing place → Añadir un lugar existente
Note, e.g. Act III only → Nota, p. ej. solo en el acto III
Remove → Quitar
Remove this place from the play? → ¿Quitar este lugar de la obra?
Delete this place? → ¿Eliminar este lugar?
Search any name, in any language → Buscar cualquier nombre, en cualquier idioma
No places yet. → Todavía no hay lugares.
No places recorded for this play. → No hay lugares registrados para esta obra.
One record per place, shared by every play that references it. → Un registro por lugar, compartido por todas las obras que lo referencian.
Where this play is set, and the places it names. → Dónde se sitúa la obra y los lugares que menciona.
Plays → Obras
Authority → Autoridad
Place → Lugar
A place with this name already exists. → Ya existe un lugar con este nombre.
This place is still used by a play. Unlink it there first. → Este lugar todavía se usa en una obra. Quítalo allí primero.
This place contains other places. Move them out first. → Este lugar contiene otros lugares. Muévelos primero.
This place could not be deleted. → No se pudo eliminar este lugar.
That place is already linked to this play. → Ese lugar ya está vinculado a esta obra.
That change could not be saved. → No se pudo guardar ese cambio.
The authority is unavailable. Enter the details by hand. → La autoridad no está disponible. Introduce los datos a mano.
Leave the coordinates empty for a place that cannot be located. → Deja las coordenadas vacías si el lugar no se puede localizar.
Continent → Continente
Country → País
Province → Provincia
Region → Región
District → Distrito
City → Ciudad
Town → Villa
Building → Edificio
Forest → Bosque
River → Río
Lake → Lago
Sea → Mar
Island → Isla
Mountain → Montaña
Other → Otro
```

- [ ] **Step 4: Verify the whole thing**

```bash
mix test
mix format
mix compile --warnings-as-errors
```

Expected: every test passing. Record the new total in the commit message.

- [ ] **Step 5: Update `CLAUDE.md`**

In "What Has Been Implemented", add:

```markdown
- [x] `Emothe.Places` — corpus-global gazetteer on a three-layer model: `places` (referent, self-referencing containment, coordinates, one authority link), `place_names` (surface forms, one preferred per language), `play_places` (per-play index with `role`, `position`, `note`, `origin`). `/admin/places` for the gazetteer, `/admin/plays/:id/places` as a peer context-bar tab, `#meta-places` on `/plays/:code`, and TEI `<settingDesc>` with nested `<listPlace>` plus `<setting>` in both directions. Wikidata behind a swappable `Places.Authority` behaviour, stubbed in test so no test touches the network. Spec: `docs/superpowers/specs/2026-08-04-s9-places-design.md`
```

In the Routes section, under Admin:

```markdown
- `GET /admin/places` - Corpus-global gazetteer: places, their names, hierarchy and authority links (`:manage_places`)
- `GET /admin/plays/:id/places` - The play's place index: role, order, notes (`:manage_places`)
```

In "What Still Needs To Be Done", replace the S9 line with a Phase 2 entry:

```markdown
- [ ] **Places Phase 2** — in-text mentions (`<placeName ref>` in the body, an `element_places` table and the tagging UI), map rendering from the stored coordinates, catalogue browse-by-place, multiple authority links per place, and the FileMaker `pub_LugAccion` import
```

- [ ] **Step 6: Commit**

```bash
git add test/emothe/export/roundtrip_test.exs priv/gettext CLAUDE.md
git commit -m "test: a places TEI roundtrip, plus Spanish and docs

<N> tests passing."
```

---

## Self-review against the spec

| Spec section | Task |
|---|---|
| Schema, all three tables and four constraints | 2 |
| No `name` column; `cast_assoc(names, required: true)` | 2, 3 |
| One preferred per place per language, `coalesce` index | 2 |
| `:restrict` in, `:delete_all` out; `no_assoc_constraint` | 2, 3 |
| Places not archived | n/a — no `deleted_at` added anywhere |
| Vagueness = absent coordinates, no extra column | 2 (schema), 7 (form hint) |
| Opportunistic depth | 2 (nullable FK), 4 (`ancestors` tolerates nil) |
| Unique `(authority, authority_id)` | 2 |
| `Place.types/0` fourteen terms, one axis, geographic kinds | 2 |
| `PlayPlace.roles/0` | 2 |
| Labels in `PlayLabels` | 7 |
| `Emothe.Places` full API | 3, 4, 5 |
| `Place` has `children` / `play_places`; `Play` has `play_places` | 2 |
| Breadcrumbs from `gazetteer/0`, `ponytail:` comment | 4 |
| ActivityLog on every write | 7, 8 |
| Authority behaviour, registry, Wikidata, Stub, config | 6 |
| Multilingual labels seed name rows in one click | 7 |
| Failure never fatal, no test on the network | 6, 7 |
| `/admin/places` with play count and variant search | 7 |
| `/admin/plays/:id/places` as a peer tab | 8 |
| Shared form component | 7 |
| Duplicate-name warning instead of silent suffix | 3 (`find_by_name`), 7 |
| `:manage_places` researcher-level | 1 |
| `#meta-places`, scroll-spy, no map | 9 |
| Static-site renderer | 9 |
| TEI export `listPlace` + `setting` | 10 |
| TEI import, leave-alone, `origin: "tei"` | 11 |
| Roundtrip and fixtures-yield-nothing | 12 |
| Spanish translations | 12 |

**Placeholder scan:** none — every step has runnable code or an exact command.

**Type consistency:** `Places.link_place/3` takes `(play_id, place_id, attrs)` in Tasks 3, 5, 8, 11 and the fixtures. `Places.breadcrumb/3` takes `(place, gazetteer, locale)` in Tasks 4, 7, 8, 9, 10. `Authority.impl().search/2` returns `{:ok, [%{id:, label:, description:}]}` in Tasks 6 and 7. `on_saved` is a 1-arity function taking a `%Place{}` in Tasks 7 and 8 — the gazetteer page ignores the argument, the play page links it.

**Known ordering dependency:** Task 3's test for `delete_place/1` calls `Places.link_place/3`, which is why Task 3 ships a minimal version of it and Task 5 completes it. Do not reorder those two.
