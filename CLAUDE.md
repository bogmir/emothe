# EMOTHE - Digital Theatre Play Management System

Web application for managing, cataloguing, and presenting digitized early modern European theatre plays (16th-17th century). Allows humanities researchers to input play data, export to TEI-XML/PDF/HTML, and provides public presentation pages with statistics. Based on the existing EMOTHE project at https://emothe.uv.es.

## Tech Stack

- Elixir 1.19.5 / Erlang/OTP 28.1 (via asdf, see `.tool-versions`)
- Phoenix 1.8.3, LiveView 1.1.22, Tailwind 4.x
- PostgreSQL with UUID primary keys
- OpenTelemetry (Phoenix, Ecto, Bandit auto-instrumented; stdout exporter in dev)
- Saxy for TEI-XML parsing, xml_builder for TEI-XML generation
- Typst CLI for PDF generation
- Deployment target: Fly.io (later)

## Project Structure

```
lib/
├── emothe/
│   ├── catalogue.ex                  # Play CRUD, search, listing context
│   ├── catalogue/
│   │   ├── play.ex                   # Core play schema (UUID PK)
│   │   ├── play_editor.ex            # Editors/reviewers
│   │   ├── play_source.ex            # Bibliographic sources
│   │   └── play_editorial_note.ex    # Front matter notes (dedications, editorial notes)
│   ├── play_content.ex               # Content management context (divisions, elements, characters)
│   ├── play_content/
│   │   ├── character.ex              # Dramatis personae
│   │   ├── division.ex               # Acts, scenes, prologues (self-referencing tree)
│   │   └── element.ex                # Speeches, verse lines, stage directions, prose (self-referencing tree)
│   ├── statistics.ex                 # Compute & cache play statistics
│   ├── statistics/
│   │   └── play_statistic.ex         # Cached JSONB statistics per play
│   ├── accounts.ex                   # User registration, login, session context
│   ├── accounts/
│   │   ├── user.ex                   # User schema (email, hashed_password, role)
│   │   ├── user_token.ex             # Session and email tokens
│   │   └── user_notifier.ex          # Email notification templates
│   ├── import/
│   │   └── tei_parser.ex             # TEI-XML importer (handles UTF-16 files)
│   └── export/
│       ├── tei_xml.ex                # Generate TEI-XML from DB
│       ├── html.ex                   # Standalone HTML document export
│       └── pdf.ex                    # PDF via Typst CLI
└── emothe_web/
    ├── router.ex
    ├── user_auth.ex                  # Auth plugs & LiveView on_mount hooks
    ├── live/
    │   ├── play_catalogue_live.ex    # Public: /plays - searchable catalogue
    │   ├── play_show_live.ex         # Public: /plays/:code - play text, characters, stats
    │   ├── user_registration_live.ex # /users/register
    │   ├── user_login_live.ex        # /users/log-in
    │   ├── user_settings_live.ex     # /users/settings (email & password)
    │   ├── user_forgot_password_live.ex
    │   ├── user_reset_password_live.ex
    │   ├── user_confirmation_live.ex
    │   ├── user_confirmation_instructions_live.ex
    │   └── admin/
    │       ├── play_list_live.ex     # Admin: /admin/plays - manage plays
    │       ├── play_form_live.ex     # Admin: /admin/plays/new|:id/edit
    │       ├── play_detail_live.ex   # Admin: /admin/plays/:id - detail + exports
    │       └── import_live.ex        # Admin: /admin/plays/import - TEI file import
    ├── controllers/
    │   ├── user_session_controller.ex # Login/logout session handling
    │   └── admin/
    │       └── export_controller.ex  # Download endpoints for TEI/HTML/PDF
    └── components/
        ├── play_text.ex              # Play text rendering (speeches, verses, stage dirs)
        └── statistics_panel.ex       # Modern stats visualization (cards, bar charts)
```

## Database Schema

All tables use UUID primary keys. Key relationships:

- `users` - email/password auth with role (`:admin`, `:researcher`), confirmation, tokens
- `users_tokens` - session tokens, email confirmation/reset tokens
- `plays` has_many `play_editors`, `play_sources`, `play_editorial_notes`, `characters`, `play_divisions`, `play_elements`
- `play_divisions` self-references via `parent_id` (acts contain scenes)
- `play_elements` self-references via `parent_id` (speeches contain line_groups contain verse_lines)
- `play_elements` belongs_to `characters` (for speaker attribution)
- `play_statistics` stores computed JSONB data per play

Element types: `speech`, `stage_direction`, `verse_line`, `prose`, `line_group`
Division types: `acto`, `escena`, `prologo`, `argumento`, `dedicatoria`, `elenco`, `front`

## Routes

### Public
- `GET /` - Home page
- `GET /plays` - Public play catalogue with search
- `GET /plays/:code` - Public play presentation (text, characters, statistics tabs)

### Authentication
- `GET /users/register` - Registration (redirects if already logged in)
- `GET /users/log-in` - Login (redirects if already logged in)
- `POST /users/log-in` - Create session
- `DELETE /users/log-out` - Destroy session
- `GET /users/settings` - Email & password settings (requires auth)
- `GET /users/reset-password` - Forgot password
- `GET /users/reset-password/:token` - Reset password form
- `GET /users/confirm` - Resend confirmation instructions
- `GET /users/confirm/:token` - Confirm account

### Admin (requires admin role)
- `GET /admin/plays` - Play management list
- `GET /admin/plays/new` - Create play
- `GET /admin/plays/:id/edit` - Edit play metadata
- `GET /admin/plays/:id` - Play detail (structure, stats, export buttons)
- `GET /admin/plays/import` - Import TEI-XML files (upload, server path, or directory)
- `GET /admin/plays/:id/export/tei` - Download TEI-XML
- `GET /admin/plays/:id/export/html` - Download HTML
- `GET /admin/plays/:id/export/pdf` - Download PDF

## TEI-XML Format

The importer handles the TEI P5 format used by EMOTHE/Artelope. Key mappings:
- `teiHeader/fileDesc` -> play metadata, editors, sources
- `text/front/div[@type="elenco"]/castList` -> characters
- `text/front/div[@type="dedicatoria|introduccion_editor"]` -> editorial notes
- `text/body/div1[@type="acto"]` -> act divisions
- `text/body/div1/div2[@type="escena"]` -> scene subdivisions
- `sp` -> speech elements with `who` -> character reference
- `lg` -> line groups with verse type (redondilla, romance_tirada, etc.)
- `l` -> verse lines with line numbering, split line markers (part I/M/F)
- `stage` -> stage directions

Sample TEI files are at `~/Downloads/tei_files/` (UTF-16 encoded).

## Getting Started

```bash
cd ~/Projects/emothe
mix deps.get
mix ecto.create
mix ecto.migrate
mix test
mix phx.server
```

Then visit:
- http://localhost:4000/admin/plays/import to import TEI files
- http://localhost:4000/plays to browse the catalogue

## What Has Been Implemented

- [x] Phoenix 1.8.3 project scaffold with all dependencies
- [x] OpenTelemetry configuration (Phoenix, Ecto, Bandit auto-instrumentation)
- [x] 7 database migrations (plays, editors, sources, notes, characters, divisions, elements, statistics)
- [x] All Ecto schemas with changesets and associations
- [x] `Emothe.Catalogue` context - play CRUD with search (title, author, code)
- [x] `Emothe.PlayContent` context - characters, divisions, elements; full content tree loading
- [x] `Emothe.Statistics` context - computes acts, scenes, verse distribution, split verses, prose fragments, stage directions, asides, character appearances; caches as JSONB
- [x] `Emothe.Import.TeiParser` - parses UTF-16 TEI-XML files into DB (handles BOM, encoding detection, full TEI structure mapping)
- [x] `Emothe.Export.TeiXml` - reconstructs TEI-XML from DB using xml_builder
- [x] `Emothe.Export.Html` - standalone HTML document with CSS styling
- [x] `Emothe.Export.Pdf` - PDF generation via Typst CLI
- [x] Public catalogue page (`/plays`) with search
- [x] Public play presentation page (`/plays/:code`) with Text/Characters/Statistics tabs, line number and stage direction toggles
- [x] Statistics panel with modern cards and CSS bar charts
- [x] Admin play list with search and delete
- [x] Admin play create/edit form
- [x] Admin play detail page with structure overview and export buttons
- [x] Admin TEI import page (file upload)
- [x] Export controller (TEI-XML, HTML, PDF download endpoints)
- [x] Authentication with bcrypt (registration, login, password reset, email confirmation)
- [x] Role-based access control (`:admin`, `:researcher` roles)
- [x] Admin route protection (requires admin role via plug + LiveView on_mount)
- [x] Compile & fix errors (all modules compile cleanly)
- [x] TEI parser test suite - metadata, cast list, duplicate characters, acts/scenes, speeches/verses, prose, editorial notes, UTF-16 encoding
- [x] Duplicate character xml_id handling in TEI importer (`create_character_unless_exists`)
- [x] Manual play content editor at `/admin/plays/:id/content` - characters, divisions, elements with modal forms
- [x] Navigation overhaul: two layouts (public app + admin), breadcrumbs, play context bar for admin play pages
- [x] Collapsible sidebar with scroll spy (IntersectionObserver) on public play page
- [x] Theme toggle (system/light/dark) in navbar
- [x] EMOTHE home page with catalogue CTA
- [x] "Edit in Admin" link on public play page for logged-in users
- [x] DaisyUI component migration (catalogue, play show, admin pages)

## What Still Needs To Be Done

### High Priority
- [ ] **Create initial admin user** - promote a registered user to admin via IEx: `Emothe.Accounts.get_user_by_email("...") |> Emothe.Accounts.User.role_changeset(%{role: "admin"}) |> Emothe.Repo.update()`
- [ ] **Fly.io deployment** configuration (Dockerfile, fly.toml, runtime.exs)

### Medium Priority
- [x] **Aside detection** in TEI importer (detects `<stage type="delivery">[Aparte.]</stage>` and `<seg type="aside">` patterns)
- [ ] **Verse type statistics** - distribution of verse types (redondilla, romance, etc.)
- [ ] **Pagination** on catalogue pages for large collections
- [ ] **Install Typst** for PDF export to work (`cargo install typst-cli` or download binary)

### Low Priority / Future
- [ ] **TEI import improvements** - handle more TEI variants, better error reporting
- [ ] **Full-text search** with PostgreSQL tsvector
- [ ] **User management** admin page (list users, change roles)
- [ ] **Activity log** - track who imported/edited what
- [ ] **TEI validation** - validate exported XML against TEI schema
- [ ] **Responsive mobile design** refinements
- [ ] **API endpoints** for programmatic access
- [ ] **Batch export** - export multiple plays at once
- [ ] **Custom OTel spans** for TEI import, export, statistics computation

## Key Decisions

- **TEI Import first**: Primary data entry via XML import, not manual forms
- **Typst for PDF**: Modern typesetting system, great for scholarly documents
- **Saxy for XML**: SAX-style streaming parser; uses `Saxy.SimpleForm` to parse into tree
- **UUID primary keys**: All tables use `binary_id` for eventual distributed deployment
- **JSONB statistics**: Cached stats stored as a JSON blob, recomputed on demand
- **Self-referencing trees**: Both divisions and elements use `parent_id` for hierarchy
- **bcrypt authentication**: Standard Phoenix auth pattern with session tokens, email confirmation, password reset
- **Role-based access**: Two roles (`:admin`, `:researcher`); admin routes protected via plug + LiveView `on_mount`
