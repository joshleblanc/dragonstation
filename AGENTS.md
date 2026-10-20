# AGENTS.md

A site for [DragonRuby](https://dragonruby.org) cartridges: upload a cart built with the
cartridge console, and play it in the browser.

## Setup commands

- Install deps:  `bundle install` (Ruby 3.4.5, pinned in `.ruby-version`)
- Prepare:       `bin/rails db:prepare && bin/rails console:install CONSOLE_PATH=../dragonruby/console DEFAULT=true`
- After changing the console (see below): `bin/rails console:install CONSOLE_PATH=../dragonruby/console DEFAULT=true`
- Start dev:     `bin/rails server`
- Test:          `bin/rails db:test:prepare test`
- System tests:  `bin/rails test:system` (Capybara + Selenium; CI runs this job, no `test/system` yet)
- Lint:          `bin/rubocop`
- Security scan: `bin/brakeman --no-pager`, `bin/bundler-audit`, `bin/importmap audit`
- Whole CI suite locally: `bin/ci`
- Deploy:        `bin/kamal deploy` (config in `config/deploy.yml`)

## The sibling console checkout

The DragonRuby console lives at `../dragonruby/console` — its own git repo, not a subdirectory of
this one. **Both halves usually change together:** this site pins console library versions that the
console releases, so a library change is not finished until both sides move.

Run from *that* directory, not from here: `bin/run <cart>` (boot a cart), `bin/publish-cart`,
`bin/publish-site <cart>` (POST a cart straight to this site), `bin/publish-console` (release the
console here as a new version), `bin/update-library` (pull the library back from a site). All of
them take `--dry-run` and `--help`.

This file describes only this repo. For the console side read `../dragonruby/console/README.md`,
and keep each repo's own tests green on its own.

## Project layout

- `app/controllers/` — including `admin/`, `api/`, and the play-path `cartridge_runtime_controller.rb`
- `app/services/` — the real domain: ingest, staging, console library, HTML5 build
- `app/services/console_release.rb` — what a console *is*, as opposed to a checkout. Both install paths
  read this list; a checkout also holds `builds/`, `shots/`, your WIP cart, and `dragonstation.json`
- `app/services/concerns/safe_archive.rb` — the ZIP refusals **both** upload paths must share
- `app/models/` — `Cartridge`, `CartridgeFile`, `ConsoleVersion`, `ConsoleLibraryFile`, `User`, `ApiKey`
- `app/javascript/` — importmap + Stimulus (no bundler, no npm)
- `public/dragonruby/` — vendored DragonRuby 7.21 html5 build, verbatim except the loader header
- `lib/tasks/` — `console.rake` (`console:install`, `console:status`), `active_storage.rake`
- `test/` — Minitest, mirrors `app/`; shared setup in `test/test_helpers/`
- `config/storage.yml` — where blobs live: local disk, or the private DigitalOcean Spaces bucket
  (`digitalocean`). Region/bucket come from `config/deploy.yml`; the endpoint is derived from the
  region. Switching the service moves nothing — a blob records its own — so `active_storage:copy_blobs`
  runs first

## Code style

- Omakase Ruby (`rubocop-rails-omakase`), inherited in `.rubocop.yml`; `test/fixtures/**` is excluded
- Comments explain **why**, not what — the repo's own comments carry design rationale; match that
- Prefer server-side ERB/Turbo Frames over new JavaScript; several features deliberately work with
  scripting off, and marked-up HTML is the reason
- No Node toolchain: JS comes from `config/importmap.rb`, pinned by `bin/importmap audit`

## Testing instructions

- Minitest; test files sit next to the type they cover (`test/services/html5_build_test.rb`)
- Fixtures: `fixtures :all`, parallel workers via number of processors; fixtures are **data** and some
  are deliberately wrong — do not "fix" one to make a test pass
- Reuse helpers from `test/test_helpers/` instead of re-creating sessions, cartridges, or libraries
- Run `bin/rubocop` and `bin/rails db:test:prepare test` before opening a PR; all four CI jobs must be green

## PR & commit conventions

- Branch from `main`; never push to it directly
- Conventional commits: `feat:` / `fix:` / `chore:` / `docs:` / `refactor:`
- Dependabot manages `bundler` and `github-actions` — expect its PRs, don't hand-bump versions
- Update `README.md` in the same change when behavior moves; it is the design document for this app

## Documentation

`README.md` is the whole documentation, in three layers plus a reference:

- **Using Dragonstation** — what a person does. Endpoints, tasks and limits are stated as
  they are, so a behavior change means editing this layer.
- **Running Dragonstation** — running and operating the site.
- **How it works** — the design rationale. This is the layer to read before changing behavior,
  and to extend when a change has a reason worth recording.
- **Reference** — the endpoint table, the rake-task table, troubleshooting and layout. These are
  **generated from the code's behavior and must be updated in the same commit** as any change to
  a route, a task, an upload limit or a failure mode.

The README carries a linked table of contents near the top. When you add or rename a heading,
add or rename its entry there too, and keep the anchors in sync — a broken link is a doc bug.

## Security

- Never commit secrets: `.env*` and `/config/*.key` are gitignored; `config/master.key` stays untracked
- Uploads are untrusted archives — route both upload paths through `SafeArchive`; do not add a
  third path that reads a ZIP without it
- The Spaces bucket is **private and must stay private**. Everything is read back through
  `CartridgeRuntimeController`; a public bucket puts the library bytes on the internet a second
  time, without the `.rb`-only check that `ConsoleLibraryInstall::ALLOWED_MODULE` enforces
- `Admin::BaseController` answers a signed-in non-admin with a **404, not a redirect**. Keep it that way
- The play path depends on `Cross-Origin-Opener-Policy: same-origin` +
  `Cross-Origin-Embedder-Policy: require-corp`; removing them breaks `SharedArrayBuffer` and the wasm build
- `manifest.json`'s `filesize` is load-bearing — the loader allocates an array of exactly that size

## Domain invariants worth knowing before you change anything

- There is **no per-cartridge build step** — the vendored loader fetches `manifest.json` and
  `gamedata/` at runtime, which is why an uploaded cart can play unmodified
- Only `Html5Build`'s loader header (the seven `GDragonRuby*` vars) is per-cartridge; the rest of
  `public/dragonruby/` stays byte-identical to what DragonRuby shipped, and that diff is checkable
- Pinning is deliberate: setting the default console version never moves a cartridge already pinned
- `test:system` and `/admin` exist; ratings, leaderboards, editing, and desktop builds do not
- `console:install` takes `CONSOLE_PATH`, **never `PATH`** — that is the shell's, and reading it meant a bare
  `console:install` reported a missing directory named after every binary on the machine
- The console cannot bootstrap the site: `bin/publish-console` needs `dragonstation.json`, which ships inside
  `/console/bundle.zip`, which 404s until a version is installed. Use the rake task, or `--pack-only` + the
  admin upload screen