# Authentication, authorization and admin UX — design

Date: 2026-08-02

## Problem

The access model and the admin interface are both incoherent, and they are
incoherent for the same reason: role checks are scattered inline instead of
living in one place.

### Security findings in the current code

1. **`:researcher` is a dead role.** Registration defaults new users to
   `:researcher` (`lib/emothe/accounts/user.ex:13`), but every protected route
   requires `:admin` (`lib/emothe_web/router.ex:110`). A researcher who logs in
   is redirected to `/` and can do exactly what an anonymous visitor can.

2. **Email confirmation is not enforced, contrary to CLAUDE.md.**
   `require_authenticated_user/2` (`lib/emothe_web/user_auth.ex:240-252`) is a
   `cond` with a single `is_nil(current_user)` branch and a `true ->`
   fallthrough. There is no `confirmed_at` check, in that function or in
   `on_mount(:ensure_authenticated)` or `on_mount(:ensure_admin)`. Today you can
   register with any address, never open the confirmation mail, and be logged
   in. The docstring still claims otherwise.

3. **Registration is open to the internet** with no approval gate. No
   `approved_at`, no pending state, no admin queue.

4. **Admin accounts are created by hand in IEx.** No seed, no config, no
   bootstrap; nothing records who is supposed to be an admin.

5. **Sessions are opaque and long-lived.** 60-day tokens and remember-me
   cookies, with no way for a user or an admin to list or revoke active
   sessions. Login throttling is 20 attempts/min/IP, which permits roughly
   28,000 guesses per day against one account from one address.

### UI findings

6. `app.html.heex` and `admin.html.heex` duplicate the navbar and have already
   drifted apart.

7. The admin navbar omits `/admin/users` and `/admin/activity-log` is squeezed
   in; the LiveDashboard is an unlabeled icon. `/admin/users` exists and is
   reachable only by typing the URL.

8. An admin play page stacks four levels of chrome: navbar, breadcrumbs,
   `play_context_bar`, and the content editor's own tabs.

9. `signed_in_path/2` sends non-admins to `/`, because there is nowhere else to
   send them — a symptom of finding 1.

## Decisions

| Question | Decision | Rejected |
|---|---|---|
| How do accounts get created? | Invite-only, admin issues the invite | Self-register + approval queue |
| What does a researcher get? | Flat: all content operations | Per-play assignment; read-only |
| Extensibility | One `Authz` module so per-play scoping is a later, local change | Hard-coding the flat model |
| Navigation | Admin shell with a left sidebar | Patching the horizontal bar |
| Security scope, round one | Baseline hardening + session visibility | Login audit log; MFA; SSO |
| Admin bootstrap | `ADMIN_EMAILS` env var, reconciled at boot | Seeds/mix task only; UI promotion |

SSO was considered and rejected: it means UV's identity provider, SAML or OIDC,
an `Assent`/`Ueberauth` dependency and coordination with university IT. For a
handful of invited accounts, invite-only already provides the control SSO would.
Revisit if the user count reaches dozens or IT mandates it.

## Access model

Two roles, names unchanged: `:admin`, `:researcher`.

Account state is derived from columns, not a status enum:

| State | Shape | Can log in |
|---|---|---|
| Invited | row exists, `hashed_password` NULL, invite token outstanding | no |
| Active | `hashed_password` set, `confirmed_at` set | yes |
| Deactivated | `deactivated_at` set | no |

Accepting an invite proves control of the mailbox, so it sets `confirmed_at` in
the same transaction. Invited users have no separate confirmation step, and
there are no `pending`/`approved` columns — invite-only makes approval implicit.

`deactivated_at` exists because `activity_logs.user_id` references `users`;
revoking access must not delete rows the audit trail depends on. Deactivating
also deletes all of that user's session tokens.

### Migrations

Each belongs to the slice that first needs it:

- **A0** — `users.deactivated_at :utc_datetime`, nullable. A0 enforces it, so A0
  adds it.
- **A1** — `users.hashed_password` becomes nullable (currently `null: false` in
  `priv/repo/migrations/20260212100000_create_users_auth_tables.exs`), because
  invited users have no password until they accept.
- **B1** — `users_tokens.ip_address :string` and `users_tokens.user_agent
  :string`, both nullable.

### `Emothe.Authz`

One module, `can?(user, action, resource \\ nil)`. Every route plug and every
LiveView `on_mount` calls it. No `role == :admin` comparison survives anywhere
else.

```
Researcher: :view_admin, :manage_plays, :edit_content, :manage_editors,
            :manage_sources, :import_tei, :download_export, :archive_play
Admin:      all of the above, plus
            :purge_play, :manage_users, :view_activity_log,
            :deploy_site, :view_dashboard
```

Deactivated and unconfirmed users get `false` for every action, `:view_admin`
included.

### Extension point: per-play assignment

`can?/3` already accepts a resource; the researcher clause ignores it today:

```elixir
def can?(%User{role: :researcher} = u, action, _resource),
  do: active?(u) and action in @researcher_actions
```

Scoping researchers to assigned plays later means adding one clause that matches
`%Play{}` and consults a `play_assignments` join table, plus an assignment UI in
`/admin/users` or the play page. **No call site changes.** This must be recorded
in the module's `@moduledoc` and in CLAUDE.md so role checks do not get
scattered again.

## Authentication lifecycle

**Invite.** `Accounts.invite_user(email, role, invited_by)` creates the user row
without a password, mints a `users_tokens` row with context `"invite"` and a
7-day expiry, and mails a link to `/users/accept-invite/:token` via the
`gen_smtp` adapter already configured. Re-inviting deletes the outstanding token
and issues a fresh one.

**Accept.** The invitee sets a password. One transaction: write
`hashed_password`, set `confirmed_at`, delete the invite token, issue a session.
An expired or already-used token renders "this invitation is no longer valid"
and nothing more — no email enumeration.

**Removed outright, not feature-flagged:** `/users/register`,
`UserRegistrationLive`, `Accounts.register_user/1`, `UserConfirmationLive`,
`UserConfirmationInstructionsLive`, `/users/confirm` and `/users/confirm/:token`.
With invite-only, account confirmation has no reachable path. Email *change*
confirmation stays — a separate token context, still needed. Password reset
stays unchanged.

**The three gates gain their missing check.** `require_authenticated_user/2`,
`on_mount(:ensure_authenticated)` and `on_mount(:ensure_admin)` all become:
authenticated, `confirmed_at` set, `deactivated_at` nil, and — for admin
routes — `Authz.can?/2` for a named action. `:ensure_admin` is replaced by
`{UserAuth, :ensure_can, action}` so the router declares the permission rather
than the role.

**Login throttling, two keys.** `EmotheWeb.RateLimit` keeps 20/min per IP and
gains 10 failures per 15 minutes per email address. Only failures consume
budget. Deliberately a rate limit rather than an account lock, so a stranger
cannot lock a named admin out of their own site by guessing at it.

**Session lifetime** drops from 60 days to 30, for both the DB token and the
remember-me cookie.

**Active sessions.** `/users/settings` gains a table of the user's session
tokens with IP, user agent and creation time, the current session marked, a
per-row revoke, and "sign out everywhere else". `/admin/users` gains "force
logout", which deletes the user's session tokens and broadcasts on the existing
`live_socket_id` topic so open LiveViews disconnect immediately. The
`ip_address`/`user_agent` columns exist because a session list showing only a
timestamp is unreadable and therefore unused.

## Admin bootstrap

`ADMIN_EMAILS="ana@uv.es,bogdan@example.org"` read in `runtime.exs`. A task in
the supervision tree, ordered after `Repo`, reconciles on every boot:

- address with no user → create an invited admin, send the invite
- existing user with a different role → promote to admin
- existing user deactivated → reactivate

Unset in dev and test: no-op. Unset in prod: log an error and do nothing.

Those addresses are **protected**. `/admin/users` will not demote, deactivate or
delete them, and `Authz` enforces this — the template disabling a button is
presentation, not protection. Config is the source of truth, so a compromised
admin session cannot strip co-admins or lock the owner out.

### How an admin gets in

Email and password, at the same `/users/log-in` form everyone uses. There is no
separate admin login.

First boot: the reconciler creates the invited admin row and mails the
accept-invite link; the admin sets a password and is in.

**Break-glass.** The first deploy may not have working SMTP, so the invite mail
that would let you configure the app cannot arrive. `mix emothe.invite` takes
`--print-url`, writing the accept link to stdout instead of sending it, with an
`Emothe.Release.invite_url/1` equivalent for `fly ssh console`. Same escape hatch
when an admin loses a password before mail works, since `/users/reset-password`
also depends on SMTP.

### Deferred, as decisions rather than oversights

Common-password blocklist (NIST recommends one; needs a dependency or a
wordlist), login audit log, MFA, trusted devices, new-device detection, SSO.

MFA, trusted devices and new-device detection are covered under "Designed-for
extension points" below, which records what this design keeps cheap for them.

## Admin UI shell

```
┌────────────────────────────────────────────────────────────┐
│ EMOTHE          ES/EN  ☾  [ana@uv.es ▾]                    │
├──────────────┬─────────────────────────────────────────────┤
│ CONTENT      │  La Virginia — Lope de Vega — EMOTHE0042    │
│  Plays       │  Overview Metadata Editors Sources Content  │
│  Import      │ ┌─────────────────────────────────────────┐ │
│              │ │                                         │ │
│ SITE         │ │           page content                  │ │
│  Export      │ │                                         │ │
│  Activity    │ │                                         │ │
│              │ │                                         │ │
│ SYSTEM       │ │                                         │ │
│  Users       │ │                                         │ │
│  Dashboard   │ └─────────────────────────────────────────┘ │
│ ─────────    │                                             │
│  View site ↗ │                                             │
└──────────────┴─────────────────────────────────────────────┘
```

Two strips above the work instead of four. Sidebar entries are generated from a
list filtered through `Authz.can?/2`, so a researcher does not see SYSTEM and
cannot reach it either — nav and authorization read from one source. That is the
structural fix for `/admin/users` being invisible.

Built with DaisyUI's `drawer` and `menu`, both already in the project.
Off-canvas below `sm` with a hamburger; no custom JavaScript.

**Deduplication.** The identity dropdown, locale toggle and theme toggle exist
twice and have drifted. They become one `<.user_menu>` component shared by both
layouts. `app.html.heex` loses its inline admin links and gains a single "Admin"
entry, shown when `Authz.can?(user, :view_admin)`.

**Breadcrumbs stop rendering.** The `:breadcrumbs` assigns stay in the LiveViews
at first — dead but harmless — and are swept in a follow-up commit. This is what
keeps the shell independent of the LiveViews: they render into `{@inner_content}`
and know nothing about the chrome, and the layout is bound at
`lib/emothe_web/router.ex:113` by one line, so the whole slice reverts by
reverting that line.

**`signed_in_path/2`** switches from `role == :admin` to
`Authz.can?(user, :view_admin)`, so a researcher lands somewhere useful.

**`/admin/users` becomes the invite console:** state badges (invited / active /
deactivated / protected), "Invite user" with email and role, resend invite,
force logout, deactivate and reactivate, role change. Protected addresses render
destructive controls disabled with a tooltip naming `ADMIN_EMAILS`, and `Authz`
rejects the operation regardless of what the form posts.

**Login page** loses its "Register" link and gains one line stating that access
is by invitation.

## Designed-for extension points

None of these are built now. They are the things this design deliberately keeps
cheap, recorded so the next person finds them instead of rediscovering them —
and so nobody breaks them by accident.

### Per-play researcher scoping

Described in full under "Access model" above. One clause in `Emothe.Authz`, one
join table, one assignment UI. No call site changes, because every authorization
question already goes through `can?/3` with the resource in hand.

**Keep true:** no `role == :admin` comparison outside `Authz`. The moment one
reappears, the seam stops working.

### MFA (TOTP)

Session creation funnels through a single `log_in_user/3`
(`lib/emothe_web/user_auth.ex:32`), so a challenge has exactly one insertion
point. Adding TOTP means `users.totp_secret`, `users.totp_confirmed_at`,
`users.backup_codes`, a setup page in `/users/settings`, and a branch that
stashes a pending user id in the session and redirects to a challenge instead of
issuing a token. `nimble_totp` covers the cryptography with no transitive
dependencies. Neither `Authz` nor the admin shell is affected.

**Keep true:** every path that logs someone in goes through `log_in_user/3`. The
invite-accept flow in A1 becomes its second caller, and password reset is a
third — all of them must reach the same challenge, or MFA has a bypass.
Remember-me must also be reconciled with MFA before shipping it; see trusted
devices below.

### Trusted devices

A separate `users_tokens` context with its own expiry, listed in the same active
sessions table B1 builds and revoked by the same control. This is what lets a
known browser skip the TOTP prompt without weakening the password step. Small
once MFA and B1 both exist.

### New-device detection

Reuses B1's `ip_address` and `user_agent` columns plus a template in
`user_notifier.ex` to mail the user when a login looks unfamiliar.

**Keep true:** IP and user agent are weak identifiers — mobile networks rotate
addresses, browsers rewrite their UA string on every update — so false alerts
are expected. This is an alerting signal only. A recognised fingerprint must
never substitute for a password or a TOTP code; it may only suppress a
notification.

## Slices

Order is constrained by one security fact: today anyone can self-register as a
`:researcher`. The moment `Authz` grants researchers content access, every
self-registered row becomes an editor. The door closes before the role gains
power.

| Slice | Ships | Depends on |
|---|---|---|
| **A0** Close the door | `deactivated_at` migration; `confirmed_at` + `deactivated_at` enforced in all three gates; public registration deleted; every existing user row deactivated | — |
| **A1** Invites + bootstrap | nullable-password migration; `invite_user/3`; accept-invite page; `ADMIN_EMAILS` reconciler; `mix emothe.invite` | A0 |
| **A2** Authz | `Emothe.Authz`; inline role checks deleted; researchers gain content access | A1 |
| **B1** Sessions | `ip_address`/`user_agent`; active-sessions UI; force logout; 30-day lifetime; per-email throttle | A0 |
| **C1** Admin shell | sidebar; shared `<.user_menu>`; `signed_in_path`; breadcrumbs off | A2 |
| **C2** Invite console | invite/resend/deactivate/role UI on `/admin/users` | A1, C1 |
| **C3** Cleanup | delete breadcrumb assigns, dead LiveViews, stale gettext; update CLAUDE.md | all |

A0 is worth shipping on its own — it is the actual hole. B1 and C1 are
independent of each other. C1 is discardable without touching anything else.

Between A0 and A1 there is deliberately no way to create an account: A0 removes
registration and A1 introduces invites. This is a dev-only window, and A0's
`mix` console remains available. A0 and A1 should land in the same working
session.

## Testing

Tests are written first, per the repo rule in CLAUDE.md.

**`test/emothe/authz_test.exs`** is the centrepiece: a table over
(role × account state × action) asserting the full matrix, including that a
deactivated admin gets `false` for everything. That table is what makes the
later per-play extension safe to attempt.

**`test/emothe/accounts_test.exs`**: invite create, accept, expire, reuse and
re-invite; deactivation deleting session tokens; the bootstrap reconciler being
idempotent across boots and refusing to demote a protected address.

**`test/emothe_web/user_auth_test.exs`**: the regression that must fail before
A0 — an unconfirmed user reaching `/admin/plays`; a deactivated user rejected; a
researcher allowed and denied per action.

**`test/emothe_web/live/admin/user_list_live_test.exs`**: the invite flow and
protected-address controls.

**`test/support/fixtures.ex`** gains `invited_user_fixture`, and `user_fixture`
switches to a direct insert with `confirmed_at` instead of routing through the
deleted `register_user/1`. Every test calling it breaks in A0 and is updated
there.

## Risks

- **Existing user rows.** Every current row was created by open self-registration
  and none can be trusted. `ADMIN_EMAILS` does not exist yet at A0, so A0
  deactivates all of them unconditionally; A1's reconciler then creates or
  reactivates the configured admins. Not deployed yet, so this is dev data —
  cheap now, impossible to skip later.
- **`ADMIN_EMAILS` unset in production means zero admins and total lockout.**
  Mitigated three ways: the reconciler logs an error at boot;
  `mix emothe.invite --admin` remains permanently as break-glass; the Fly.io
  deployment task gains the secret as a checklist item.
- **Deleting `register_user/1` ripples through tests and seeds.** Enumerated and
  fixed inside A0 rather than discovered later.
