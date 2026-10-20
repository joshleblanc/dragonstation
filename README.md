# Dragonstation

A site for [DragonRuby](https://dragonruby.org) cartridges: upload a cart built
with the cartridge console, and play it in the browser.

Nothing is compiled here. The DragonRuby HTML5 build is a wasm module that asks
the server which files its game is made of and then fetches them, so an
uploaded cart plays unmodified. The console library travels with every cart,
which makes a cart a directory the server describes rather than a file the
server stores.

Two words are used consistently below:

- **cart** — the directory in the console's checkout. `carts/space/`.
- **cartridge** — the same thing after upload, as the site stores it.

## Start here

| If you want to… | Go to |
|---|---|
| Put a game on the site | [Upload a cartridge](#upload-a-cartridge) → [Publish it](#publish-it) |
| Learn the console library | [The console library's documentation](#the-console-librarys-documentation), or the console's own [README](https://github.com/joshleblanc/console) |
| Publish from a terminal | [Publish from the console](#publish-from-the-console) |
| Run the site locally | [Local setup](#local-setup) |
| Install or upgrade the console library | [Install a console library](#install-a-console-library) |
| Operate a deployed site | [Deploying](#deploying), [Where the files live](#where-the-files-live) |
| Understand why it is built this way | [How it works](#how-it-works) |
| Look up a path, a task or a symptom | [Reference](#reference) |

## Contents

- **[Using Dragonstation](#using-dragonstation)** — the product, from a person's point of view
  - [Accounts](#accounts)
  - [Upload a cartridge](#upload-a-cartridge)
  - [Publish it](#publish-it)
  - [Read a cartridge's files](#read-a-cartridges-files)
  - [Get the console](#get-the-console)
  - [Publish from the console](#publish-from-the-console)
  - [The console library's documentation](#the-console-librarys-documentation)
- **[Running Dragonstation](#running-dragonstation)** — running and operating it
  - [Local setup](#local-setup)
  - [Install a console library](#install-a-console-library)
    - [Bootstrapping the first version](#bootstrapping-the-first-version)
    - [Installing is not updating](#installing-is-not-updating)
    - [A version whose bytes are gone](#a-version-whose-bytes-are-gone)
  - [The admin screens](#the-admin-screens)
  - [Where the files live](#where-the-files-live)
  - [Deploying](#deploying)
- **[How it works](#how-it-works)** — the design, and why
  - [What a cartridge is](#what-a-cartridge-is)
  - [How a cart runs](#how-a-cart-runs)
    - [`filesize` is load-bearing](#filesize-is-load-bearing)
  - [Pinning](#pinning)
  - [The console library](#the-console-library)
    - [What the upload is allowed to add](#what-the-upload-is-allowed-to-add)
    - [One guard, two upload paths](#one-guard-two-upload-paths)
  - [Reading a cart's files](#reading-a-carts-files)
    - [Highlighting](#highlighting)
    - [Why the path is a query parameter](#why-the-path-is-a-query-parameter)
  - [Cross-origin isolation](#cross-origin-isolation)
  - [The HTML5 build](#the-html5-build)
  - [Not built yet](#not-built-yet)
- **[Reference](#reference)**
  - [Endpoints](#endpoints)
  - [Rake tasks](#rake-tasks)
  - [Troubleshooting](#troubleshooting)
  - [Layout](#layout)

---

## Using Dragonstation

Everything in this part is something a person does. If you are here to change
the code instead, skip to [How it works](#how-it-works).

### Accounts

Registration is open to anyone.

- **Username** — what your cartridges are published under. Lowercased, with any
  leading `@` stripped. Letters, numbers and underscores only, 3–32 characters.
- **Email** and **password** — at least 8 characters. A forgotten password is
  reset at `/passwords/new`.

**The first account to register becomes the administrator.** A fresh install has
no other way to reach an admin screen, because every admin screen sits behind a
login and there is nobody to log in as. Once an admin exists, later
registrations never take it — even if that admin is deleted afterwards.

That is the one thing worth knowing before you have a console installed:
`/admin/console_versions/new` is where the very first version has to come from,
and nothing else will get it there for you.

### Upload a cartridge

1. Sign in and choose **Upload a cart** in the header.
2. Zip your cart directory.
   - The archive may wrap the cart in a directory, or be the cart itself.
     Either is fine. Two carts in one archive is an error.
   - Zip the *directory*, not its parent. The archive should hold one directory
     that contains `app/`.
3. Choose a console version. The default is preselected, and it is the version
   your cartridge will be pinned to forever.
4. Upload. It arrives as a **draft**.

**What the upload checks**

| Check | Why |
|---|---|
| Exactly one cart in the archive | Two is an error, not a choice |
| An entry file: `app/main.rb`, `app/<cart name>.rb`, or a single `app/*.rb` | The loader needs one |
| The cart name is a Ruby constant — `Space`, not `space-here` | The console looks the cart's class up by directory name |
| Every `sprites/`, `sounds/`, `maps/` and `data/` path your source names is inside your own cart | Nothing is served from console-root starter art, so a borrowed asset would load as an invisible sprite |
| No absolute paths, no `..` segments, no symlinks | The archive is untrusted input |
| At most 512 files, 32MB expanded, and no more than 200:1 compression | Same |

The **title** defaults to `TITLE = '...'` in the entry file, and then to the
cart's name in human form. Set it on the form to override either.

If an upload is refused, the page says which rule it broke. The refusals are
the same ones the console's own `publish-cart` makes, and the same ones the
[API](#publish-from-the-console) makes.

### Publish it

A cartridge's page has the game running at the top and **Publish** underneath.

- While it is a **draft**, only you and the administrators can see it.
- **Publish** makes it public and puts it on the front page. **Unpublish** takes
  it back to a draft.

The URL is a slug derived from the cart's name, and it survives the title being
edited.

### Read a cartridge's files

The cart's page lists every file in the cart. Text files and images open **in
place**, under the list, with the game still running above them.

- `.rb`, `.json`, `.txt`, `.md`, `.yml`, `.yaml`, `.lua` and `.csv` print, with
  syntax highlighting where the language is known.
- Images render at their own size.
- Everything else is offered as a download instead of being guessed at.

Two limits are stated on the page rather than applied silently: printing stops
at 128KB and says so, and a file over 4MB is not read at all.

These are the same bytes the game itself loads. A published cart's source is
not a secret.

### Get the console

The console is what turns a cart into a game: a directory of Ruby, this
library, and the tools that boot it.

From [`/docs`](#the-console-librarys-documentation) or from **Settings**:

| Download | What you get | Who |
|---|---|---|
| `GET /console/library.zip` | The library alone | Anyone — it is public on purpose |
| `GET /console/bundle.zip` | The whole release **plus your publishing key** | Signed-in accounts only |

The bundle unpacks into a checkout of the console and it boots: the entry point,
every script under `bin/`, the starter art, the metadata, the README, and a
`carts/` directory. The library alone is enough to read the docs.

**Every bundle download issues a new key and retires the last one.** The key is
stored only as a digest, so it cannot be shown again — the download is the only
place it exists. Take the copy you are going to use. The plain library download
issues nothing, because it carries no credential.

### Publish from the console

With the bundle unpacked over your checkout and your key in
`dragonstation.json`:

```sh
./publish-site arcade
```

That zips the cart and sends it here. It arrives as a **draft** under your
account, and publishing stays a decision a person makes after seeing it run.

The endpoint, if you are writing your own client:

```
POST /api/carts
Authorization: Bearer <the api_key from dragonstation.json>
archive=<the cart ZIP, as multipart/form-data>

201 {"slug","title","status":"draft","url",...}
401 {"error":"unauthorised"}          a key that is not yours, or one a newer download replaced
422 {"error":...,"problems":[...]}    the refusals, one per line
400 {"error":"no archive"}             nothing was sent
503 {"error":"no console library ..."} nothing to pin the cart to
```

The API applies exactly the same checks as the upload form — traversal,
symlinks, expansion bombs, art a cart names but does not own — and says so in
the message.

### The console library's documentation

`/docs` is public, and it is the reason anyone would upload a cart at all. An
author needs it before they have an account.

It has two halves, and the split is the design:

- **The reference** is read out of the library's own comments
  ([ConsoleDocumentation](app/services/console_documentation.rb)). Every module
  has a header explaining what it is for, and nearly every method has a comment
  saying what it does and why. Nothing here is written by hand — Ripper
  supplies the structure and the lexer supplies the comments, which Ruby does
  not keep in the parse tree. Nothing is evaluated: the library needs
  DragonRuby's `DR` and `$args`, and documentation must not depend on running
  the thing it describes.

  The library's own `# --- heading ---` dividers become section headings,
  because the grouping its author chose is more useful to a reader than any
  order this site could invent. Indented runs inside a comment become
  highlighted code, which is how the library writes its usage samples — the
  header of `cart_loader.rb` *is* the cart contract.

- **The guide** is written here
  ([ConsoleGuide](app/services/console_guide.rb)), because what a cart is and
  how to start one is not written down in the library. Five worked examples,
  each a complete cart that adds one idea to the one before — whole files rather
  than fragments, because pasting a second `def setup` into a cart silently
  replaces the first — plus the hooks table. There is a
  test that every call in them exists in the library, and another that every one
  of them parses as Ruby — a sample that invents a method is worse than no
  sample, because it reads as authoritative.

Every module page links its source, highlighted, served from the library
directory — so it is the same file the game runs. Docs that cannot be checked
against the implementation are a guess.

Both halves describe the **default** console version, and every page says which
one. A cart is pinned to a version, so a mismatch is a real possibility and a
silent one would be indistinguishable from a bug in the library.

**The page is built to be found in.** It opens with a jump nav to its own
sections, because the parts are not in the order a reader meets them in. The
API index is grouped by what a reader is trying to do — drawing, input, the
world — rather than left in require order, which is the order the modules build
on each other and the wrong order to look something up in. A module the
grouping does not name lands in a catch-all rather than vanishing.

A module page lists its own sections, and the modules either side of it in
require order, so a reader who arrived at one module has a way onward.

Two things the extraction has to get right, because the page shows them:

- **A summary is a whole sentence.** The library's headers wrap, so the summary
  is the header's first paragraph reflowed and cut at the end of its first
  sentence. Reading the first source line instead leaves half a sentence in
  the index.
- **An anchor is unique.** Several modules define a method more than once —
  `update` in `animation.rb` and `tween.rb` — and two elements sharing an id
  is invalid HTML, and a link to it jumps to the first and stops there. So the
  second is numbered.

---

## Running Dragonstation

Everything in this part is about keeping the site up and its library healthy.

### Local setup

You need Ruby 3.4.5 (pinned in `.ruby-version`) and a checkout of the console
next to this one, at `../dragonruby/console`.

```sh
bin/setup --skip-server          # bundle install + db:prepare
bin/rails console:install CONSOLE_PATH=../dragonruby/console DEFAULT=true
bin/rails server
```

The install prints what it did:

```
console: installed 0.1.0 (12 modules, fonts: font.ttf, tiny.ttf [default])
```

`bin/rails console:status` reports the same thing at any time:

```
console: 0.1.0   [default]   ok -- 12 modules
```

Then open <http://localhost:3000>, choose **Create account**, and upload a
cart. The first account you register is the administrator.

If you would rather not install the console from a checkout, the browser can do
it: upload a ZIP of the console at `/admin/console_versions/new`. See
[Bootstrapping the first version](#bootstrapping-the-first-version).

### Install a console library

There are two routes, and they do the same thing:

```sh
bin/rails console:install CONSOLE_PATH=/path/to/console [DEFAULT=true] [FORCE=true]
```

or upload a ZIP of the console at `/admin/console_versions/new`.

Both run `ConsoleLibraryInstall.check`, so a library cannot be accepted by the
task and refused by the screen, or the reverse. The task is the better route
when the library is already in a checkout, because it reads the files where they
are rather than asking for them to be zipped first.

| Variable | Meaning |
|---|---|
| `CONSOLE_PATH` | The console checkout. Never `PATH` — that is the shell's, and reading it once reported a missing directory named after every binary on the machine. |
| `DEFAULT` | `true` to make this the version new cartridges are pinned to. |
| `FORCE` | `true` to adopt a row whose label disagrees with its stored files. |

**What gets installed** is the release, not the checkout
([ConsoleRelease](app/services/console_release.rb)): `app/`, `bin/`, `sprites/`
and `metadata/` walked whole, plus `font.ttf`, `tiny.ttf`, `README.md`,
`.gitignore`, `.gitattributes`, `errors/readme.txt` and `carts/README.md`.

A checkout also holds build output, screenshots, the cart you are working on and
`dragonstation.json`. None of that is part of a console version, and installing
all of it is how a 3.9MB release turned into 104MB of blobs and put a live API
key in the library the site serves.

**The version comes from the library itself** — `app/console/version.rb` — and
must be `MAJOR.MINOR.PATCH`. Both paths refuse to install an archive under a
label its own code disagrees with.

Neither path writes to the repository. The files land as blobs against the
version row, and an upload is not a commit.

### Bootstrapping the first version

A fresh host has no console library, and the console's own release script
cannot put one there. `bin/publish-console` refuses to run without
`dragonstation.json`; that file arrives only inside `/console/bundle.zip`; and
that download is built from an installed version — so it is 404 until there is
one. **The console cannot bootstrap the site.**

Two routes that do work:

1. **`bin/rails console:install CONSOLE_PATH=<checkout>`** — needs no key and
   no network. This is the intended first step, and it is what
   [Local setup](#local-setup) runs. On a deployed host the checkout has to be
   reachable from the app, which usually means copying it in and running the
   task inside the container.
2. **`bin/publish-console --pack-only`**, which builds the release ZIP and sends
   nothing, followed by uploading that ZIP at
   `/admin/console_versions/new`. The same install the task does, reached
   through the browser.

After either one, make the version the default. Only then does
`/console/bundle.zip` resolve, which is where `dragonstation.json` comes from —
and from then on `bin/publish-console` works like it is meant to.

### Installing is not updating

Neither path will replace an installed version, and the reason is specific
rather than cautious.

Pinning is what makes a leaderboard run comparable with the run beside it, and
a cartridge's pin is the version *label* — the `console_versions` row.
Overwriting the files behind it would leave every label, every pin and every
admin page looking exactly as they did while changing the code every cartridge
on that version runs. Nothing would report a problem. The scores would simply
stop meaning anything.

So an upload naming an installed version is refused by name, and the way to
ship a change is to bump `MAJOR.MINOR.PATCH` in `app/console/version.rb` and
upload it again as a new version.

`console:install` stays idempotent — re-running it on a checkout registers what
is already there — but it registers, and never rewrites files in place.

There is one exception, and it is not an exception to the rule so much as the
absence of the thing the rule protects. A version that cannot be read has no
bytes anybody has ever run: no manifest, no served module, nothing that could
have been loaded. It is an install that did not finish — an interrupted deploy,
or a deploy onto a fresh container while the blobs still name a disk that is not
there — and `console:install` fills it in rather than adopting the row as it is.

### A version whose bytes are gone

Two states look identical in the database and nothing alike in production:

- a row with no file rows, and
- a row whose file rows are all present and none of the blobs behind them are.

The second is what a redeploy onto a fresh container leaves behind when
`ACTIVE_STORAGE_SERVICE` has changed. A blob records the service it was written
to and reads from that one for the rest of its life, so every row is present
and every object is on the disk being left behind.

So "is this version usable" is a question about storage, and
`ConsoleLibraryFile#readable?` asks it as one — a HEAD against the service the
blob names, not a row count. `ConsoleLibrary#available?` is built on that
rather than on "is there a row named `app/main.rb`", because every guard in the
app is built on `available?`: the admin index, the docs pages, the upload
dropdown, the stager. Asking the database instead meant every one of those
waved a version that serves nothing through, and the first real read then
raised `ActiveStorage::FileNotFoundError` from inside storage.

That error was the reason the symptom was a crash on pages that merely *listed*
versions. Each of those pages wraps its reads in a rescue for
`ConsoleLibrary::Missing` — they exist precisely to show a broken library rather
than die on one — and a storage error is not that exception, so none of them
caught it. Installing a working library beside the broken one did not help
either: the listing walks every version, so it still went through the broken row.

`ConsoleLibrary#read` therefore translates a storage failure into
`ConsoleLibrary::Missing`, which is what that exception has always meant and
what the guards are written against, and `ConsoleVersion.default` skips an
unreadable version in its fallback so a broken row cannot become what every new
cartridge is pinned to. A version an admin has *flagged* as default is honoured
either way: that is a deliberate act, and the admin pages are where it gets
answered.

`console:status` reports the broken state as `MISSING library files`.

### The admin screens

The first account to register is the operator, and `/admin` is the only place
that fact is used.

| Path | What it is |
|---|---|
| `/admin` | Counts, and the two states nothing else reports: a version with no directory, a version with none installed at all |
| `/admin/console_versions` | `console:status` as a page — per version, its state, module count, and the cartridges pinned to it |
| `/admin/console_versions/new` | Upload a library as a version that does not exist yet |
| `/admin/console_versions/:id` | One version: its files, its require order, and the cartridges pinned to it |

Setting the default is a deliberate, separate act rather than a side effect of
uploading. It decides what a *new* cartridge is pinned to and cannot move one
that already exists.

`Admin::BaseController` answers a signed-in non-admin with a **404 rather than
a redirect**, because an admin URL that answers differently for a stranger is
an admin URL that can be written down — and its existing existence is the only
part that matters to whoever finds it. Anonymous visitors are redirected to sign
in, since `require_authentication` runs first.

### Where the files live

Every console library file and every cartridge file is an Active Storage blob.
The service is chosen per environment, and in production it is an environment
variable rather than a line of code:

```yaml
# config/environments/production.rb
config.active_storage.service = ENV.fetch("ACTIVE_STORAGE_SERVICE", "local").to_sym
```

`config/storage.yml` defines `local` (a directory under `storage/`),
`digitalocean` (a private DigitalOcean Spaces bucket — the production service)
and `amazon` (S3, read entirely from the environment).

DigitalOcean and AWS are both `service: S3`, and they are separate entries on
purpose: the service name is what a blob records in `service_name`, so
`copy_blobs TO=<name>` and `blob.service` both speak it. An entry named
`amazon` silently pointed at Spaces is the kind of lie that costs an afternoon.
Spaces' endpoint is derived from its region, so the two cannot go out of step,
and `force_path_style` is false because Spaces wants subdomain-style requests.

Keys come from `config/credentials/production.yml` under `digitalocean`, with
an environment fallback if a deploy would rather inject them:

```sh
bin/rails credentials:edit -e production   # digitalocean.access_key_id / .secret_access_key
```

Region and bucket are deployment facts and live in `config/deploy.yml`:

```yaml
env:
  clear:
    ACTIVE_STORAGE_SERVICE: digitalocean
    DIGITALOCEAN_REGION: nyc3
    DIGITALOCEAN_BUCKET: your-bucket
```

**The bucket is private and must stay private.** Nothing is served from it
directly — every console module and cartridge file is read back through
`CartridgeRuntimeController`, which chooses its own content type. A public
bucket would put the same bytes on the internet twice, one of them without the
`.rb`-only check that stops `app/console/payload.html` being handed to a browser
as `text/html` from this origin.

**Setting the service moves nothing that is already stored.** A blob records the
service it was written to and reads from that one for the rest of its life, so a
deployment that flips the variable and redeploys without copying serves every
cartridge and every library file out of a local disk that no longer exists — on
Kamal, an empty directory on a fresh container. So the failure is not a slow
read but a file that is simply not there. Copy first:

```sh
bin/rails active_storage:copy_blobs TO=digitalocean DRY_RUN=true   # what would move
bin/rails active_storage:copy_blobs TO=digitalocean
```

It reads each blob from the service that blob names, so it is correct while the
two sets are mixed, and safe to interrupt and re-run. Keys are preserved rather
than regenerated, so no attachment is repointed and a URL handed out yesterday
still resolves today.

Note that this app streams library bytes through Rails rather than redirecting
to them (`CartridgeRuntimeController` reads the blob and sends it with a content
type guessed from the path). That works against any service, and is what lets
the served content type be decided per file — but it means every game file is
fetched by the app, so a remote service saves the app's disk, not its bandwidth.

### Deploying

`bin/kamal deploy` — the configuration is `config/deploy.yml`.

| Setting | Where | Notes |
|---|---|---|
| `ACTIVE_STORAGE_SERVICE` | `config/deploy.yml` → `env.clear` | `digitalocean` in production |
| `DIGITALOCEAN_REGION`, `DIGITALOCEAN_BUCKET` | `config/deploy.yml` → `env.clear` | The endpoint is derived from the region |
| `RAILS_MASTER_KEY` | `.kamal/secrets` | Also holds the Spaces keys, if you use credentials |
| `dragonstation_storage:/rails/storage` | `config/deploy.yml` → `volumes` | The database. Keep it: losing it loses every cartridge, user and console version |

Two things to get right on a first deploy:

1. **Copy the blobs before the service changes.** See
   [Where the files live](#where-the-files-live).
2. **Install a console version.** A site with no library cannot accept an upload
   at all, and the admin dashboard says so. To install one on the server, run
   the task inside the container:

   ```sh
   bin/kamal app exec "bin/rails console:install CONSOLE_PATH=/path/to/console DEFAULT=true"
   ```

Then watch it come up with `bin/kamal logs`.

---

## How it works

The reasoning behind the code. Read this when you need to know *why* something
is the way it is, or before changing it.

### What a cartridge is

A cart is a directory with a contract:

```
carts/space/
├── app/space.rb        entry point -- defines the module named after the directory
├── sprites/            its own art
├── sounds/
└── data/
```

Zip that directory and upload it. The archive may contain the cart directory or
be the cart itself; either way it must contain exactly one cart. Two is an
error, not a choice — see
[cartridge_ingest.rb](app/services/cartridge_ingest.rb) for the full list of
refusals.

### How a cart runs

The loader asks two questions, and [CartridgeStager](app/services/cartridge_stager.rb)
answers both:

```
GET /cartridges/space/play/manifest.json     what files exist, how big is each
GET /cartridges/space/play/gamedata/<path>   the bytes of one of them
```

The served tree is the same one `console/publish-cart` stages for a desktop
build:

| Path | Source |
|---|---|
| `app/main.rb` | generated here, pinning exactly this cart |
| `app/console/*.rb` | the pinned console version's library |
| `font.ttf`, `tiny.ttf` | read from the game root, so they cannot live in a cart |
| `carts/<name>/**` | the cartridge's own code and assets, verbatim |

Console-root starter art is deliberately absent. `publish-cart` stages the cart
alone so that a borrowed asset becomes a visibly missing sprite rather than an
invisible dependency on art the build does not contain, and the same rule is
enforced at upload time here.

#### `filesize` is load-bearing

The manifest's `filesize` is not advisory. The loader does:

```js
var len = manifest[i].filesize;
var arr = new Array(len);
```

and fills it from the downloaded bytes. A short read pads the file with zeros, a
long one truncates it, and in both cases it happens silently — the game breaks
later, for a reason that points nowhere near the cause. So every size published
comes from the bytes that will actually be returned, and there is a test that
fetches every file over HTTP and compares it to the number the manifest
declared.

### Pinning

A cartridge is pinned to the console version it was uploaded against, forever.
Installing a new library changes what *new* uploads get and leaves published
games running the code they were built against — which is what makes a
leaderboard run comparable with the run beside it.

### The console library

**The library is public on purpose.** This site already serves every byte of it
to any browser running a cart — it is in the manifest and in `gamedata` — so a
second copy behind a login would imply a restriction that does not exist, and
would break `./update-library` in a terminal that has no session to log in with.
The key is the opposite: it belongs to one account.

**The download is a console, not a library.** The first version of it shipped
only what a browser needs to run a cart, which left whoever unpacked it with a
directory of Ruby and nothing to run it with. `LibraryBundle` now serves the
whole release: the entry point, every script under `bin/` (shell and `.bat`), the
starter art, the metadata, the README, and a `carts/` directory with a README in
it. Unpacking it over a checkout gives you a console that boots.

Two details that took a test to find: the ZIP carries **Unix modes**, because a
console whose scripts arrive non-executable is a console that cannot be run — and
`errors/last.txt`, `builds/` and one reader's `dragonstation.json` are excluded,
because they are that machine's state rather than the console's.

**The release is stored as blobs, not as a directory.** It used to be vendored
under `vendor/console/<version>/`, kept honest by hand: when the console moved,
so did the copy, and nothing but discipline connected the tree to the version
row. It is now one `ConsoleLibraryFile` row per file, each holding an Active
Storage blob, hanging off the `console_versions` row through `has_many`. Three
things follow, and they are the reason it moved:

* a version's files cannot be edited in place, because editing them means
  writing new rows under a version that already exists, and every install of an
  installed version is refused — a cartridge is pinned to the version it was
  uploaded against, and overwriting the bytes would leave every pin pointing at
  code that had changed underneath it;
* an upload is not a change to the repository, so `git status` stays clean and
  there is no untracked tree to review or revert;
* the bytes live wherever `config/storage.yml` says, which is normally off the
  app server entirely.

**The key is stored as a digest and nowhere else.** A SHA-256 digest, because a
key has to be *looked up* by the thing it authenticates — a salted bcrypt digest
cannot answer "is this the key?" without checking every row, which is only
affordable for a password because there is one password to check. The entropy
is 32 bytes of `SecureRandom`.

That has one consequence worth stating plainly: **every personal download issues
a new key and retires the last one**, because the download is the only place the
secret exists. A console holding a retired key is refused with a 401 and told
what to do. The alternative — encrypting the secret so it can be re-shipped —
needs record encryption keys this deployment does not have, and a key nobody can
read is worse than one they have to fetch twice.

**One key per account.** Issuing a new one replaces the old, which is also how a
leaked key is retired; there is no separate revoke, because with one key at a
time "give me a new one" and "this one is dead" are the same request.

A stored release is a console release rather than a bare library, so
`ConsoleLibrary#file_paths` (the manifest, from `app/main.rb`'s require list)
and `LibraryBundle#release_paths` (the download, everything a person needs) are
deliberately different sets. The runtime must serve exactly what it requires;
the download should carry the source.

**Releasing a console is the same shape, for administrators.**
`POST /api/console_versions` runs `ConsoleLibraryInstall` on an uploaded ZIP,
and the credential is resolved to its owner and checked for admin **on every
request**. `403` for an ordinary member, not `401` — the key was fine, the
account was not allowed. Installing a version never makes it the default and
never moves a cartridge: two decisions, both a person's.

The release script is only in an administrator's download, and the public
library — which is what `./update-library` pulls — never carries it. That is a
courtesy, not a control: the file being absent is not the thing stopping
anybody, the endpoint is.

**Publishing reuses the browser's upload.** `Api::CartsController` hands the
archive straight to `CartridgeIngest`, so traversal, symlinks, expansion bombs
and art-a-cart-names-but-does-not-own are all refused exactly as the form
refuses them — and it arrives as a *draft*, because publishing stays a decision
a person makes after seeing the cart run. The only thing the API adds is who the
cart belongs to, which is what the key decides. `Current.user` falls back to the
key's owner, so every other check in the app works unchanged for a key.

An unknown key is a 401, never a redirect to a sign-in form a terminal cannot
answer, and refusals come back as JSON `problems` because the caller is a
script.

#### What the upload is allowed to add

The one thing worth spelling out is `app/main.rb`. `ConsoleLibrary` reads the
require list out of that file and serves exactly those modules to every
cartridge on the version, and `CartridgeRuntimeController` picks the content
type from the extension. A `require 'app/console/payload.html'` would therefore
be served as `text/html` from this origin, to anyone loading a game.

Both install paths refuse a require that is not a `.rb` module directly under
`app/console/`, and refuse a require of anything at all that is missing or lives
outside that directory. The second one is not only a security check:
`ConsoleLibrary::REQUIRE_PATTERN` only matches `app/console/`, so a require of
`app/secrets.rb` would otherwise be *silently ignored* — installed as though it
were fine, then missing from every cartridge's served tree.

#### One guard, two upload paths

`SafeArchive` holds the traversal, symlink and expansion-bomb refusals shared by
the cartridge upload and the library upload. A traversal guard written twice is
a traversal guard that will eventually exist once.

### Reading a cart's files

The cart's page lists what is in the cart, and everything readable opens **in
place** — under the list, with the game still running above it:

```
GET /cartridges/space/files?path=app/space.rb   the contents of one file, as a page
```

Every link targets one `turbo-frame#file_viewer`, so a file is a fetch and a DOM
swap rather than a visit. That is the whole reason: this page is holding a wasm
runtime in a `data-turbo-permanent` iframe, and a Turbo visit would tear it down
and boot the game again to read one file. Opened directly it is an ordinary page,
and without JavaScript every link is a plain page load — only the staying put
is lost, not the reading.

These are the same bytes `play/gamedata/<path>` already serves to the game and to
anyone else — a published cart's source is not a secret — so this is not a new
disclosure. It is the same file with a reader around it.

Two things decide what a page can show. The extension says what the file is
*named*, which is all that is available while listing fifty of them; the bytes
say what it *is*, using the same NUL-byte test `CartridgeIngest` uses to tell
source from asset. A file named `.txt` holding binary is not printed as
mojibake. Printing stops at 128KB and says so — silently stopping mid-file
reads as the whole file — and a file over 4MB is not read at all.

#### Highlighting

[Rouge](https://github.com/rouge-ruby/rouge) marks the source up server-side.
That is not a preference: the file arrives inside a Turbo frame as HTML, so
anything that coloured it in the browser would have to run again on every frame
load and would not run at all with scripting off. Rouge emits classed spans and
the colours live in `application.css` with everything else, so the reader is
themed like the rest of the site.

The lexer comes from the file's name and nothing else — guessing by content
would mean reading the whole file to decide how to read it. A name Rouge does
not know is plain text, which is a correct answer rather than a failure.

Two consequences worth knowing:

- **Colours stop at 64KB.** Rouge emits about five times the source in markup,
  so at the reader's 128KB cap that is half a megabyte of HTML and a fifth of a
  second of lexing per click. Past 64KB a file prints plain, and says that it
  has. An LDTK map is exactly the kind of file that lands here.
- **It is the only `html_safe` string on the site.** Rouge escapes every token it
  emits and adds only its own spans, so the markup is safe to render as-is — but
  a cart is a stranger's upload, so there is a test that feeds the reader a file
  shaped like an attack and asserts it produces no tag.

Which cartridge a path belongs to is decided by the database, never by joining
the path onto a directory, so traversal has nothing to resolve against.
Visibility is the same rule the runtime and the cart's page use, written once in
[CartridgeVisibility](app/controllers/concerns/cartridge_visibility.rb).

#### Why the path is a query parameter

Turbo refuses to navigate any URL whose last path segment ends in one of about
sixty extensions — `.png`, `.json`, `.txt`, `.wav` and the rest — because those
are usually downloads and the browser should handle them natively. A cart is
mostly sprites and data files, so links shaped like files open nothing at all:
they navigate away, which on this page means the game reloads. `.rb` is not on
that list, so a source file appears to work and hides the bug. The path
therefore rides in `?path=`, where no extension exists for Turbo to judge, and
there is a test that fails if a link ever ends in one of those extensions again.

It also retires an older trap. Rails decides the response format by matching
`/\.(\w+)\z/` against the request path, so a URL ending in `.json` asks for a
json template and answers 406 — a route cannot opt out, since `format: false`
stops *routing* from splitting the filename but not that match. With the path
out of the route there is nothing to match. The runtime route still has the
problem, because the loader asks for its files by name, and rebuilds each path
from `params[:path]` and `params[:format]` instead.

### Cross-origin isolation

The wasm build uses threads, and `SharedArrayBuffer` is gated behind
cross-origin isolation. Every response on the play path therefore carries:

```
Cross-Origin-Opener-Policy: same-origin
Cross-Origin-Embedder-Policy: require-corp
```

The play page that embeds the iframe carries them too, because a nested
browsing context is only isolated when the embedding document opts in.

This is worth spelling out because the loader has a fallback. When it finds no
`SharedArrayBuffer`, it registers `dragonruby-serviceworker.js` — a shim that
rewrites these same headers onto every response from the client side, then
reloads the page so the document becomes controlled by it. With the headers set
here, `SharedArrayBuffer` is present on the first load and that path is never
entered.

It is worth having the headers anyway. The shim's fetch handler returns
`undefined` when the network fails, so a single failed request becomes an
unhandled rejection, a dead page, and a reload loop — which is exactly the
failure the service worker is supposed to prevent.

### The HTML5 build

`public/dragonruby/` is a DragonRuby **7.21** html5 build, copied verbatim from
a `dragonruby-publish` run.

It used to be the 6.16 build that shipped with the postcarts proof of concept,
and that one **booted the engine and then stopped, before its first game tick.**
Every cartridge was a blank grey canvas: the engine initialised render, read its
metadata, and never ran the cart. It was worth being precise about that, because
none of the obvious checks catch it — the response was byte-exact, the status
was 200, there was no exception, and a cart whose `render` fills the screen with
solid red still produced grey.

Nearly all of the build is game-independent. The exception is the **loader
header** — seven `GDragonRuby*` variables that `dragonruby-publish` writes per
game:

```js
var GDragonRubyGameId = "arcade";
var GDragonRubyGameTitle = "Space Rocks";
var GDragonRubyDevTitle = "Console";
var GDragonRubyGameVersion = "1.0";
var GDragonRubyIcon = "/metadata/icon.png";
var GDragonRubyWriteDir = "/dragonruby-arcade";
var GDragonRubyOrientation = "landscape";
```

Everything after them is generic — the loader still fetches `manifest.json` and
`gamedata/` at runtime, exactly as before. So [Html5Build](app/services/html5_build.rb)
rewrites just that header per cartridge and leaves the vendored loader
byte-identical to what DragonRuby shipped, which is what makes it checkable:

```sh
diff <(tail -n +8 public/dragonruby/dragonruby-html5-loader.js) \
     <(tail -n +8 builds/arcade-html5-1.0/dragonruby-html5-loader.js)
```

That is why this app can serve a cartridge it never bundled. It also means
**there is no per-cartridge build step**: upload, and it plays.

To refresh the vendored build:

```sh
cd <dragonruby>/console
./publish-cart somecart --platforms=html5
cp builds/somecart-html5-1.0/{index.html,game.css,favicon.png,dragonruby-*.js,dragonruby-wasm.wasm} \
   <dragonstation>/public/dragonruby/
```

Do not copy `manifest.json` or `gamedata/` — those belong to the cart that was
built, not to the build.

### Not built yet

This is the core slice only: upload a cart, play it in the browser. Not here:

- **ratings and reviews** — no `Rating` model yet
- **leaderboards** — these need a console-library API for a running cart to
  submit a score with, which is its own design problem: it changes the library
  every cartridge is pinned to, so it wants pinning in place and settled first
- **editing a cartridge** — upload is create-only; `edit`/`update`/`destroy`
  routes are generated but unimplemented
- **desktop builds** — `dragonruby-publish --platforms=linux-amd64` works from
  the same cart, and the staging logic here is already its Ruby half, but
  nothing shells out to it. The web build no longer needs it: see above.

---

## Reference

### Endpoints

| Method | Path | Auth | What it does |
|---|---|---|---|
| `GET` | `/` | — | Published cartridges |
| `GET` | `/cartridges/:slug` | — (drafts: owner, admins) | Play a cartridge; publish or unpublish it |
| `PATCH` | `/cartridges/:slug/publish` | owner | Publish (`state=published`) or unpublish (`state=draft`) |
| `GET` | `/cartridges/:slug/files?path=` | same as the cart | One file of a cart, read as text |
| `GET` | `/cartridges/:slug/play/manifest.json` | — | Which files exist, and how big each one is |
| `GET` | `/cartridges/:slug/play/gamedata/*path` | — | The bytes of one file |
| `GET` | `/cartridges/:slug/play/*file` | — | The loader shell: `index.html`, `game.css`, the wasm |
| `GET` | `/docs` | — | The console library's documentation |
| `GET` | `/docs/:slug` | — | One module's API |
| `GET` | `/docs/:slug/source` | — | That module's source, highlighted |
| `GET` | `/console/library.zip` | — | The library alone. Public on purpose |
| `GET` | `/console/bundle.zip` | session | The whole console, plus your publishing key |
| `GET` | `/settings` | session | Your key and the console download |
| `POST` | `/settings/api_key` | session | Issue a key, or replace the one you have |
| `POST` | `/api/carts` | Bearer key | Publish a cart from the console |
| `POST` | `/api/console_versions` | Bearer key, admin | Install a console version |
| `POST` | `/registration` | — | Create an account |
| `POST` / `DELETE` | `/session` | — | Sign in, sign out |
| `GET` / `POST` | `/passwords/*` | — | Reset a password |
| `GET` | `/admin` | admin | Counts and library state |
| `GET` | `/admin/console_versions` | admin | Installed versions |
| `GET` | `/admin/console_versions/new` | admin | Upload a library |
| `POST` | `/admin/console_versions` | admin | Install the uploaded library |
| `PATCH` | `/admin/console_versions/:id/default` | admin | Set or clear the default |
| `GET` | `/up` | — | Health check: 200 if the app boots cleanly, 500 otherwise |

### Rake tasks

| Task | What it does |
|---|---|
| `bin/rails console:install CONSOLE_PATH=… [DEFAULT=true] [FORCE=true]` | Install a console library from a checkout |
| `bin/rails console:status` | Report which versions are installed and usable |
| `bin/rails active_storage:copy_blobs TO=<service> [DRY_RUN=true]` | Copy blobs to another storage service |

`console:status` reports three states:

| State | Meaning |
|---|---|
| `ok -- N modules` | Installed and readable |
| `MISSING library files` | The row exists, its blobs cannot be read. Re-run `console:install` with the same path — it fills the version in |
| `MISLABELLED (declares X)` | The row's label disagrees with its stored files. Install the version the files declare, or re-run with `FORCE=true` to adopt the row as it is |

### Troubleshooting

| Symptom | What it means | What to do |
|---|---|---|
| "No console library is available to build against yet." | No readable default version | `bin/rails console:status`, then [install one](#install-a-console-library) |
| `/docs` is a 404 | The same: no readable default version | Install a console version |
| The upload is refused with "uses assets it does not own" | The source names a `sprites/`, `sounds/`, `maps/` or `data/` path the cart does not contain | Move the file into the cart directory |
| The upload is refused with "has no entry file" | No `app/main.rb`, no `app/<cart name>.rb`, and not exactly one `app/*.rb` | Check the zip's structure |
| The upload is refused with "is not a usable cart name" | The directory name is not a Ruby constant | Rename it to `Space`, not `space-here` |
| The upload is refused with "archive contains more than one cart" | Two cart directories in one archive | One cart per archive |
| `console:status` says `MISSING library files` | The row exists, its blobs cannot be read | Re-run `console:install` with the same `CONSOLE_PATH` |
| `console:status` says `MISLABELLED` | The row's label and its files disagree | Install the version the files declare, or use `FORCE=true` |
| The API answers 401 | The key is missing, wrong, or was replaced by a newer download | Download the bundle again |
| The API answers 403 | The key is fine; the account is not an administrator | Use an admin's key |
| The API answers 422 | The archive was refused | Read `problems` — the same list the form shows |
| The API answers 503 | No console library to pin the cart to | Install one |
| The password reset email never arrives | Production has no SMTP configured — `config.action_mailer.smtp_settings` is commented out in `config/environments/production.rb` | Configure SMTP and credentials, then retry |
| The game is a blank grey canvas | The vendored build is the 6.16 one, which boots the engine and stops before the first tick | Refresh `public/dragonruby/` from a 7.21 build — [The HTML5 build](#the-html5-build) |
| Clicking a file link reloads the game | A link ended in a file extension Turbo refuses to navigate | Should be impossible: the path rides in `?path=`. There is a test for it — file a bug |

### Layout

```
app/services/console_library.rb     one library version, read from its blobs
app/services/console_library_install.rb  a new version, from an archive or a directory
app/services/console_release.rb      what a console is, as opposed to a checkout
app/models/console_library_file.rb   one file of a version, as a blob + a path
app/services/concerns/safe_archive.rb    the ZIP refusals both upload paths share
app/services/cartridge_stager.rb    the served tree + the manifest
app/services/cartridge_ingest.rb    ZIP -> cartridge, or the reason why not
app/services/console_metadata.rb    the metadata and icon at the game root
app/services/html5_build.rb         the build, with its loader header rewritten
app/controllers/cartridge_runtime_controller.rb   manifest + gamedata + shell
app/controllers/admin/base_controller.rb          the admin gate: a 404, not a redirect
app/controllers/admin/console_versions_controller.rb   versions, and installing one
app/controllers/concerns/cross_origin_isolation.rb  COOP/COEP for the wasm build
public/dragonruby/                  the DragonRuby HTML5 wasm build
config/storage.yml                  where the blobs live: local disk or a bucket
lib/tasks/console.rake              console:install, console:status
lib/tasks/active_storage.rake       active_storage:copy_blobs, moving to a bucket
```
