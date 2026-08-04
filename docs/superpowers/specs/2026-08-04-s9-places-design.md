# S9 — Places and toponyms (Phase 1)

**Date:** 2026-08-04
**Status:** approved, not yet implemented
**Roadmap:** `docs/superpowers/plans/2026-08-01-filemaker-import-slices.md`, slice S9 (was S2b)
**Depends on:** S0b (`origin` on importer-written child tables), the existing TEI parser and exporter
**Blocks:** the FileMaker place-of-action import, which is a separate slice and contains no code from
this one

## Why this slice, and why the app before the import

`pub_LugAccion` in the FileMaker export was originally S2b, a `plays.place_of_action` string
alongside `historical_time`. It is not that. The field is a **toponym**, a play carries several, and
the export already gives three levels of geography:

```
EMOTHE0038  <ul><li>Rome. [Italy]. Europe</li>
                <li>Alexandria. [Egypt]. Africa</li>
                <li>Athens. [Greece]. Europe</li>
                <li>( Miseno ) [Italy]. Europe</li></ul>
```

A string column cannot hold that, and the roadmap's governing rule — *the export is a bootstrap, not
a dependency* — means the app must be able to record, edit and publish places without the NDJSON
existing at all. So the feature is built first and imported into second.

**`plays.place_of_action` is never created.** It is superseded by this design; nobody should add it
later out of habit.

## The model

Three layers, which is where digital-humanities editions converge and what TEI P5's names-and-places
module encodes:

| Layer | Table | What it is |
|---|---|---|
| Place | `places` | One stable referent, real or fictional. Language-independent facts: type, containing place, coordinates, authority link. |
| Place name | `place_names` | A surface string tagged with a language, optionally marked historical. Many names, one place. |
| Mention | *Phase 2* | An occurrence at a point in a play's text. Not built here. |

Between the place and the play sits a link table, `play_places`, which is the Phase 1 deliverable: a
**play-level place index**, not in-text tagging.

`Constantinopla` / `Constantinople` / `İstanbul` / `Bizancio` are therefore four `place_names` rows
on one `places` row, and the multilingual problem disappears into the schema instead of being solved
per query.

### Places are corpus-global

One `places` row is shared by every play that references it. That is what makes "every play set in
Italy" answerable at all, and it is why deletion is constrained rather than cascading — see below.

## Schema

Three tables, one migration file.

```elixir
create table(:places, primary_key: false) do
  add :id,   :binary_id, primary_key: true
  add :slug, :string, null: false                 # TEI xml:id, corpus-unique
  add :type, :string, null: false                 # Place.types/0 slug
  add :parent_place_id, references(:places, type: :binary_id, on_delete: :restrict)
  add :latitude,     :float                       # nil = not pinned
  add :longitude,    :float
  add :is_fictional, :boolean, default: false, null: false
  add :authority,    :string                      # "wikidata" | "geonames" | "tgn" | "pleiades"
  add :authority_id, :string                      # "Q220"
  add :note,         :text
  timestamps(type: :utc_datetime)
end

create unique_index(:places, [:slug])
create index(:places, [:parent_place_id])
create unique_index(:places, [:authority, :authority_id], where: "authority_id IS NOT NULL")

create table(:place_names, primary_key: false) do
  add :id,       :binary_id, primary_key: true
  add :place_id, references(:places, type: :binary_id, on_delete: :delete_all), null: false
  add :name,     :string, null: false
  add :language, :string                          # nil = language-neutral
  add :is_preferred,  :boolean, default: false, null: false
  add :is_historical, :boolean, default: false, null: false
  add :position, :integer, default: 0
  timestamps(type: :utc_datetime)
end

create index(:place_names, [:place_id])
create unique_index(:place_names, ["place_id", "coalesce(language, '')"],
                    where: "is_preferred",
                    name: :one_preferred_name_per_place_and_language)

create table(:play_places, primary_key: false) do
  add :id,       :binary_id, primary_key: true
  add :play_id,  references(:plays,  type: :binary_id, on_delete: :delete_all), null: false
  add :place_id, references(:places, type: :binary_id, on_delete: :restrict),   null: false
  add :role,     :string, default: "setting", null: false
  add :position, :integer, default: 0
  add :note,     :text
  add :origin,   :string, default: "manual", null: false
  timestamps(type: :utc_datetime)
end

create unique_index(:play_places, [:play_id, :place_id])
create index(:play_places, [:place_id])
```

### Six decisions, with their reasons

**No `name` column on `places`.** TEI's `<place>` has no name of its own and neither does ours. A
denormalized copy alongside `place_names` is the same string stored twice, with no constraint able to
keep the two in step, and every future write path — the admin form, the TEI importer, the Wikidata
fetch, the FileMaker sync — is another chance to update one and not the other. The failure is silent:
the gazetteer list shows one form, the play page and the TEI export show another, and both are
plausible. With one copy the disagreement is unrepresentable.

The cost is real and accepted: reads need `preload(:names)`, and sorting by name in SQL would need a
join. Phase 1 sidesteps the join because the gazetteer is a hundred rows — `Places.list_places/0`
loads all of them and sorts in Elixir. That shortcut gets a `ponytail:` comment naming its ceiling
(roughly thousands of places, at which point sorting and pagination move into SQL).

The hole this opens — a place with zero names — is closed by `cast_assoc(:names, required: true)` in
the context. That is application-enforced, weaker than a `NOT NULL`, and preferred anyway: a nameless
place is visible the first time anyone opens the list, whereas two disagreeing name copies survive
for months.

**One preferred name per place *per language*.** Not one per place. The app is bilingual and the
whole point of the layer is multilingual names, so a Spanish UI must be able to prefer `Roma` while
an English one prefers `Rome`. `coalesce(language, '')` appears in the index because Postgres treats
`NULL`s as distinct, and without it three language-less names could all be flagged preferred.

**`on_delete: :restrict` into `places`, `:delete_all` out of it.** The asymmetry is the rule *cascade
along composition, restrict along association*. A `place_name` is part of a place and has no
independent existence, so it goes when the place goes. A `play_places` row is a relationship between
two independently existing things, so deleting one end must not erase the other end's data: an admin
removing `Roma` would otherwise silently strip a documented setting from twelve plays, logged as one
action rather than twelve. `:nilify_all` is not an option — `place_id` is `NOT NULL`, because a link
row with no place asserts nothing. `parent_place_id` is `:restrict` for the same reason one level up.

`Places.delete_place/1` converts the constraint into a changeset error rather than an exception:

```elixir
place
|> Ecto.Changeset.change()
|> Ecto.Changeset.no_assoc_constraint(:play_places, message: "is still used by one or more plays")
|> Ecto.Changeset.no_assoc_constraint(:children,    message: "is the parent of other places")
|> Repo.delete()
```

**Places are not archived.** Plays use `deleted_at` because other rows depend on them. Here
`:restrict` already guarantees the only deletable place is one nothing references, and an
unreferenced place is a typo or a duplicate with no history worth keeping.

**A place that cannot be located has no coordinates, and no extra column.** "Woods in Transylvania"
is a real referent that will never have a point: it becomes a place row with `type: "other"`, a
parent of Transylvania, `latitude`/`longitude` nil, and a note. TEI requires no `<geo>`, so it
exports cleanly. `is_fictional` stays reserved for its actual meaning — no real referent at all,
Atlántida — and is not overloaded.

The accepted consequence: "cannot be located" and "nobody has typed the coordinates yet" look
identical in the admin list. If that distinction is ever wanted it is one boolean, added then.

**Depth is opportunistic, never required.** A place may have no parent. The importer builds whatever
chain the source hands it (`Rome. [Italy]. Europe` → find-or-create three rows) and a hand-entered
place can stand alone. Nothing forces a curator to construct Europe → Romania → Transylvania before
saving "Woods".

**One authority entity, one place row.** The unique index on `(authority, authority_id)` — partial,
because most places have neither — makes "two rows for one referent" structurally impossible whenever
both carry an authority link. Same QID means the same referent by definition. This is the only
mechanical defence against duplicates that exists: `type` is in no uniqueness constraint, so two rows
named `Miseno` typed `town` and `port` would otherwise both be accepted as `miseno` and `miseno-2`.
The rest of the defence is behavioural and lives in the UI — the typeahead searches every name
variant in every language, and a slug collision is surfaced rather than silently suffixed, because
`-2` is evidence that a row by that name already exists.

## Vocabularies

```elixir
Place.types/0      # continent country province region district city town
                   # building forest river lake sea island mountain other
PlayPlace.roles/0  # setting mentioned
```

Both are slugs, validated with `validate_inclusion`, translated at display time. Labels go into the
existing `EmotheWeb.PlayLabels` — `place_type_label/1` and `place_role_label/1` — rather than a new
module: it is already the single home for translated vocabularies, and a second module with the same
job is how the statistics-panel act labels drifted before.

### Two rules the type list has to obey

**One axis only.** Every term answers the same question — *what kind of geographic feature is this* —
and never a second one. `port` was proposed and rejected on exactly this ground: `town` classifies a
settlement, `port` describes a function, and Naples is both. An enum holds one value, so mixing axes
forces a false either/or, and each false either/or is a duplicate with a rationale behind it, which is
harder to clean up than a duplicate with none. If "port" turns out to matter editorially it goes in
the note now and becomes a second dimension later, if researchers ask to filter on it.

**Geographic kinds, not set-design terms.** `garden`, `street`, `room`, `inn`, `battlefield` describe
*unnamed generic settings* — TEI's `<locale>` inside `<setting>`, a different concept from a named
referent with coordinates. A garden is not a toponym and will never carry a QID. A *specific named*
garden — the Buen Retiro — is a `building` with a name and a location and does belong here. Without
this boundary the vocabulary heads for fifty terms.

`forest` is in the list on evidence rather than taste: the worked example that settled the hierarchy
design was "woods in Transylvania", and in a list without `forest` it falls through to `other`. When
the motivating example lands in the escape hatch, a term is missing.

Extending the list is a three-line change and no migration — the column is a plain string. **Removing
or renaming** a term is a data migration, because rows already carry the old slug, so the list errs
toward too few terms rather than too many. Curators cannot add terms at runtime: that needs a lookup
table plus a second admin CRUD page, which the S2a spec already considered and rejected for the same
reason, and a closed vocabulary is what makes grouping, filtering and the TEI `@type` mean anything.

`role` defaults to `"setting"`. `"mentioned"` exists because the FileMaker export encodes it —
`( Miseno )` — and because "where is this play set" and "what places does it name" are different
editorial questions. In-text mentions are Phase 2 and a different table; this is a property of the
play-level link.

## Context and modules

New context directory `lib/emothe/places/`, beside `catalogue/` and `play_content/` rather than
inside either, because the data is corpus-global.

```
lib/emothe/places.ex
lib/emothe/places/place.ex
lib/emothe/places/place_name.ex
lib/emothe/places/play_place.ex
lib/emothe/places/authority.ex
lib/emothe/places/authority/wikidata.ex
lib/emothe/places/authority/stub.ex          # test implementation
```

### `Emothe.Places`

```elixir
# gazetteer
list_places(opts \\ [])          # names preloaded, :play_count virtual field, sorted in Elixir
gazetteer()                      # %{id => place}, names preloaded — one query, feeds breadcrumbs
get_place!(id)
create_place(attrs)              # cast_assoc(:names, required: true)
update_place(place, attrs)
delete_place(place)              # {:error, changeset} when referenced
find_or_create_by_slug(attrs)    # importers; existing slug is left alone and reported
slugify(name)                    # NFD-normalised, accent-stripped, collision-suffixed
search_names(term, opts \\ [])   # matches any variant, for the link and parent typeaheads

# derived
display_name(place, locale \\ "es")
ancestors(place, gazetteer)      # root-first
breadcrumb(place, gazetteer)     # "Woods, Transylvania, Romania, Europe"

# the play-level index
list_play_places(play)           # ordered, role-grouped, place and names preloaded
link_place(play, place, attrs)
update_play_place(play_place, attrs)
unlink_place(play_place)
reorder_play_places(play, ids)
```

`display_name/2` is a fallback chain, which is what the per-language preferred index makes possible:
preferred-in-locale → any-in-locale → preferred-in-any-language → first.

Breadcrumbs are built from the `gazetteer/0` map rather than by walking parents with queries. One
small query, no N+1, no recursion; the public play page loads the whole gazetteer to render two
places, which is wasteful in principle and free in practice at this size. Marked with a `ponytail:`
comment pointing at a recursive CTE.

`Place` carries `belongs_to :parent, Place` plus `has_many :children, Place` and
`has_many :play_places` — the last two are what `no_assoc_constraint/3` above needs in order to turn
the two `:restrict` violations into changeset errors.

`Emothe.Catalogue.Play` gains `has_many :play_places`, and the public play loader preloads
`play_places: [place: :names]`.

Every create, update, delete, link and unlink is logged through `Emothe.ActivityLog` with
`resource_type` `"place"` or `"play_place"`, using the existing allowed actions
(`create update delete import export role_change`) — no new action.

### The authority seam

```elixir
@callback search(term :: String.t(), opts :: keyword()) ::
            {:ok, [%{id: String.t(), label: String.t(), description: String.t() | nil}]}
            | {:error, atom()}

@callback fetch(id :: String.t()) ::
            {:ok, %{
               labels: %{String.t() => String.t()},                  # "es" => "Roma"
               latitude: float() | nil,
               longitude: float() | nil,
               type_hint: String.t() | nil,                          # P31, mapped to Place.types/0
               parent: %{id: String.t(), label: String.t()} | nil,   # P17
               url: String.t()
             }}
            | {:error, atom()}
```

`Authority.registry/0` returns `%{slug, label, url_pattern, module}` per authority. `Wikidata` is the
only implementation with `search/2` and `fetch/1`; `geonames`, `tgn` and `pleiades` exist as
link-out targets with no module until someone wants them. `Stub` is the test implementation, so the
behaviour has two implementations from the start rather than the single-implementation interface the
repo's conventions warn about.

`Wikidata` uses the `req` already in `mix.exs`: `wbsearchentities` for the typeahead in the current
locale with an `en` fallback, then `Special:EntityData/<id>.json` on selection for `P625`
coordinates, `P17` country and `P31` instance-of. Two consequences justify the typeahead's cost over
a pasted ID: selecting an entity **seeds the `place_names` rows in es/en/fr/it in one click**, which
is the entire point of the names layer, and `P17` supplies the parent.

Failure is never fatal. 5s timeout, no retry, `{:error, :unavailable}` renders inline, and every
field stays hand-typeable — a curator with no network can still do the whole job. `config/test.exs`
selects `Stub`, so **no test touches the network**; the Wikidata response parser is tested against a
checked-in fixture through `Req.Test`.

## Admin UI

### `/admin/places` — the gazetteer

`EmotheWeb.Admin.PlaceListLive`. A corpus-global page, so it lives in the sidebar's **Content** group
with `hero-map-pin-micro`, not in the play context bar.

Search box hits `place_names`, so typing `Istanbul` finds the place whose preferred form is
`Constantinopla`. Table columns: preferred name with ancestor breadcrumb, type badge, coordinate and
authority badges, and **play count** — the number that tells a curator whether a delete will be
refused before they try it. Delete renders the changeset error as a flash.

### `/admin/plays/:id/places` — the per-play index

`EmotheWeb.Admin.PlayPlacesLive`. A **peer tab in the play context bar**, at the same level as
Metadata, Editors, Sources and Content, inserted between Sources and Content. Not nested inside
Content.

Table: breadcrumb, role, note, reorder, unlink. "Add place" is a typeahead over the local gazetteer;
no match offers `Create "Woods"`, which opens the shared modal prefilled with the typed name and
links the result on save.

### `EmotheWeb.Admin.PlaceFormComponent`

One modal, two call sites — the unit worth isolating, so there is exactly one place-editing surface.
Fields: name rows (name, language, preferred, historical), type, parent, authority search,
latitude/longitude, `is_fictional`, note, and the slug, auto-derived and editable.

A name that collides with an existing place's name **warns and offers that place** instead of silently
suffixing the slug to `miseno-2`. The suffix is the mechanism of last resort — two genuinely different
places can share a name — but it must never be the thing that quietly hides a duplicate.

Name rows use the framework mechanism rather than hand-rolled add/remove:

```elixir
cast_assoc(:names, required: true, sort_param: :names_order, drop_param: :names_delete)
```

Wikidata typeahead: 300 ms debounce, 3-character minimum. On select, `fetch/1` fills a name row per
language returned, the coordinates and the type hint. Parent handling stays honest rather than
clever: when `P17`'s country matches a local place by `authority_id` or name it is preselected;
otherwise the form shows `Wikidata: in Italy (Q38) — not in your gazetteer` and the curator decides.
**No place row is ever created silently from a network response.**

### Authorization

`Emothe.Authz` gains `:manage_places` in `@researcher_actions`, gating both routes and the sidebar
entry. Both routes sit inside the existing `:admin` live_session, exactly as sources and editors do —
`pipe_through` needs no new pipeline, because every researcher action is granted together and the
live_session's `{:ensure_can, :view_admin}` hook already covers entry.

**Researcher-level, decided rather than defaulted.** Places are the first thing in this codebase that
is *content* — the researchers' domain — and simultaneously *corpus-wide* — everything else
corpus-wide is admin-only. Both readings are defensible, so here is the reasoning, because the next
person will ask.

What a researcher can actually do with it is narrower than "corpus-wide" suggests: edit the names,
type, parent or coordinates of a shared place; delete a place **no** play references; create a
duplicate; attach the wrong authority entity. Deleting a place out from under twelve plays is not on
the list — the foreign key refuses it.

Against restricting it: the people who know that Miseno is in the Bay of Naples are the researchers,
not the admins, and there is roughly one admin. Admin-only would make *adding a place* a prerequisite
a researcher cannot satisfy, so the task "record where this play is set" stalls on three of four
entries. That ends in one of three ways — the work queues behind one person, the admin becomes a
data-entry clerk for judgements they are less qualified to make, or researchers quietly stop recording
places. It would also make places the only content thing a researcher cannot touch, next to editing
the text, the cast list, the bibliography and archiving the play outright.

The real protection against the two plausible accidents is not a permission. A rename that changes
eleven other plays is prevented by *seeing* "used by 12 plays" beside the edit button; a duplicate is
prevented by a search that matches every name variant in every language. Both are in this design, and
an admin searching in the wrong language creates the identical duplicate.

**The recorded upgrade, if it is ever needed:** additive stays free, mutative narrows. This is the
extension `Authz`'s `@moduledoc` already advertises, and it needs no call-site changes because every
caller passes the resource:

```elixir
def can?(%User{role: :researcher} = user, :manage_places, %Place{} = place) do
  Accounts.active?(user) and Places.play_count(place) <= 1
end
```

**The tripwire that should trigger it:** more than a handful of researchers, or a researcher who is
not a project member — an external contributor, a student cohort. Researcher-level is safe because
"everyone with an account is someone I can talk to" is currently true. When it stops being true, add
the clause.

## Public presentation

A `#meta-places` section on `/plays/:code`, beside `#meta-study`, hidden when the play has no places,
registered in the sidebar scroll-spy:

```elixir
|> maybe_add_section(play.play_places != [], "meta-places", gettext("Places"))
```

Settings first, then mentioned. Each row is the breadcrumb, the optional note, a marker when the
place is fictional, and an outbound link to the authority when one is set. **No map** — coordinates
are stored and not drawn.

`Emothe.Export.StaticSite.Renderer` gets the same section, otherwise the archival site carries less
than the app it was generated from. The HTML, PDF and EPUB exports are untouched: they are reading
documents, not metadata records.

## TEI import and export

Both directions ship in Phase 1. Without export a researcher can type forty places, export the TEI
and watch them vanish — the archival format goes lossy, which is the thing the existing roundtrip
suite exists to prevent.

### The trap, and the shape that avoids it

Hierarchy is expressed by nesting `<place>` inside `<place>`, which means `Italy` can appear in a
file purely as a container. On import there is then no way to distinguish a container from a place
the play is actually set in, and guessing "leaves are the settings" is wrong — a play can be set in
Italy itself.

So the two concerns get two elements, and the importer reads each for exactly one thing:

```xml
<profileDesc>
  <langUsage>…</langUsage>
  <settingDesc>
    <listPlace>
      <place xml:id="europa" type="continent">
        <placeName xml:lang="es">Europa</placeName>
        <place xml:id="italia" type="country">
          <placeName xml:lang="es">Italia</placeName>
          <placeName xml:lang="en">Italy</placeName>
          <place xml:id="roma" type="city">
            <placeName xml:lang="es">Roma</placeName>
            <placeName xml:lang="en">Rome</placeName>
            <location><geo>41.9028 12.4964</geo></location>
            <idno type="wikidata">Q220</idno>
          </place>
          <place xml:id="miseno" type="city">
            <placeName xml:lang="it">Miseno</placeName>
          </place>
        </place>
      </place>
    </listPlace>
    <setting>
      <placeName ref="#roma" ana="setting"/>
      <placeName ref="#miseno" ana="mentioned"><note>Named, not staged.</note></placeName>
    </setting>
  </settingDesc>
</profileDesc>
```

- **`<listPlace>`** ↔ `places` + `place_names`. The nesting *is* `parent_place_id`. The exported set
  is the play's places plus every ancestor, so the tree is always complete.
- **`<setting>`** ↔ `play_places`, in document order (`position`), `@ana` carrying `role` and the
  inner `<note>` carrying the link note. `@ana` normally points at an interpretation element; using a
  bare `setting` / `mentioned` token is a **project convention**, documented in the exporter's
  `@moduledoc`. It is preferred over `@type` because `@type` on `<placeName>` already means
  historical-versus-current inside `<listPlace>`, and one attribute with two meanings in one file is
  how a parser acquires a bug.
- `xml:id` ↔ `places.slug`. Corpus-unique, therefore document-unique for free.
- `is_historical` ↔ `<placeName type="historical">`.
- `is_fictional` ↔ `<place type="city" subtype="fictional">`, using TEI's `att.typed` pair so `@type`
  can keep carrying our `Place.types/0` slug. A fictional place also simply has no `<location>`.

Considered and rejected: TEI 4's `<standOff><listPlace>`, the right home for a whole-corpus
gazetteer. We export one play's subset per file, so `settingDesc` fits and needs no new top-level
element.

### Import policy

Follows the precedent S2a set for curated data:

- A slug that already exists is **left alone and reported**, never overwritten. The gazetteer is
  curated; the file may be stale.
- An unknown slug creates the place, its names and its ancestors.
- Links are written with `origin: "tei"`, and a re-import deletes only that play's `"tei"` links —
  the S0b rule, which is why `play_places` carries `origin` at all.
- **A `places` row is never deleted by an import.** A place left with no links shows in the gazetteer
  with a play count of 0 and is removed by hand. No garbage collection.

No `plays` column is added, so `@platform_owned` in `lib/emothe/import/tei_parser.ex` needs no entry.
The sibling rule applies instead: the new child table carries `origin`.

## Testing

TDD per `CLAUDE.md` — failing test first, whole suite before any completion claim.

| File | Covers |
|---|---|
| `test/emothe/places_test.exs` | names required; one preferred per language, including the `NULL`-language case; ancestors and breadcrumb; delete refused when linked and when a parent; `find_or_create_by_slug` idempotence and leave-alone policy; `search_names` matching a non-preferred variant; `slugify` collisions; **a second place with the same `authority_id` is rejected, and two places with no authority are not** |
| `test/emothe/places/authority/wikidata_test.exs` | parsing a checked-in `test/fixtures/wikidata/Q220.json` — `P625`, `P17`, `P31`, labels — plus 404, malformed-body and timeout paths, all through `Req.Test` |
| `test/emothe_web/live/admin/place_list_live_test.exs` | create, edit, search, delete blocked with its flash, name collision warns and offers the existing place |
| `test/emothe_web/live/admin/play_places_live_test.exs` | link, role change, reorder, unlink, create-and-link inline, tab renders in the context bar |
| `test/emothe_web/live/play_show_live_test.exs` | section absent when the play has no places; breadcrumb, note and fictional marker when it does |
| `test/emothe/export/tei_xml_test.exs` | nesting, `<geo>`, `<idno>`, `<setting>` refs, `@ana`, note, historical name type |
| `test/emothe/import/tei_parser_test.exs` | the same shapes read back; container places do not become links; existing slug left alone; `origin: "tei"` |
| `test/emothe/export/roundtrip_test.exs` | synthetic play export → import → export equality; and the real fixtures still yield zero places |
| `test/emothe/authz_test.exs` | `:manage_places` for researcher and admin, denied to inactive |

`test/support/fixtures.ex` gains `place_fixture/1` and `play_place_fixture/2`. Spanish translations
for every new string, since the default locale is `es` — assertions go through
`Gettext.gettext(EmotheWeb.Gettext, …)`, never literal English.

## Implementation order

This is a large slice for one spec — three tables, two LiveViews, a shared form component, a network
integration and both TEI directions. It stays one spec because the pieces are meaningless apart: a
gazetteer with no play link publishes nothing, and a TEI export with no editor breaks the "no import
without an editor" rule. The plan should sequence it so each step is independently verifiable and the
app is never left half-wired:

1. Migration, schemas, `Emothe.Places` context, `:manage_places` in `Authz`
2. `Authority` behaviour, `Stub`, `Wikidata`, response-parsing tests against the checked-in fixture
3. `PlaceFormComponent` and `/admin/places` — the gazetteer is usable end to end
4. `/admin/plays/:id/places` and the context-bar tab
5. `#meta-places` on the public play page, then the same section in the static-site renderer
6. TEI export of `<listPlace>` + `<setting>`
7. TEI import of the same, with the leave-alone policy and `origin: "tei"`
8. Roundtrip test, Spanish translations, full-suite verification

Steps 1–4 are the feature. Steps 6–7 are what keep the archival format honest. Nothing here touches
FileMaker.

## Out of scope

Phase 2 and beyond, listed so the boundary is explicit:

- In-text mentions — `<placeName ref="#roma">` in the body, an `element_places` table, and the
  tagging UI
- Map rendering; coordinates are stored in Phase 1 and not drawn
- Catalogue browse or filter by place
- Multiple authority links on one place (Wikidata *and* TGN); Phase 1 stores one, and the upgrade is
  a `place_authority_ids` child table
- Date ranges on names (`from`/`to`), which is TGN territory
- `play_sources.pub_place` becoming a place link
- **Any FileMaker code.** The `pub_LugAccion` import is the next slice and this one ships without it

## Decided since first draft

- **`:manage_places` is researcher-level**, with the `play_count <= 1` narrowing recorded as the
  upgrade and its tripwire named. See Authorization above.
- **`port` is not a type**, on the one-axis rule. `forest`, `province` and `district` are in;
  `forest` on the evidence of the design's own worked example.
- **`(authority, authority_id)` is uniquely indexed**, so one authority entity cannot become two place
  rows, and a slug collision warns instead of silently suffixing.

## Open questions

Flagged rather than silently decided. None blocks the implementation plan; each has a stated default.

1. **The `type` vocabulary's fourteen terms** still want a researcher's eye before the migration bakes
   them in — specifically whether `province` and `region` are distinct enough to keep both, and
   whether an early-modern kingdom such as Naples is a `country`, a `region` or a `province`. The
   one-axis and geographic-kinds rules above are what any addition has to satisfy.
2. **Which languages the name-language select offers.** Default: the five corpus languages plus a
   blank for language-neutral. Free text is the alternative.
3. **Is `setting` / `mentioned` enough for `role`?**
4. **Fictional places on the public page** — marked as such, or rendered indistinguishably?

## Done when

- A researcher can create a place with several names in several languages, give it a parent, attach a
  Wikidata entity by searching for it, and see it in a corpus-wide gazetteer at `/admin/places`
- A researcher can attach places to a play from a peer tab in the play context bar, set each one's
  role and note, reorder them, and unlink them
- The places appear on `/plays/:code` in `#meta-places` and in the generated static site
- A TEI export carries the places and a re-import of that file reproduces them exactly, without
  overwriting a curated gazetteer row
- Deleting a referenced place fails with a message naming the reason
- `mix test` passes whole, `mix format` clean, `mix compile --warnings-as-errors` clean
