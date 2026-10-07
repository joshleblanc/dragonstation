# Dragonstation

A site for [DragonRuby](https://dragonruby.org) cartridges: upload a cart built
with the cartridge console, and play it in the browser.

The interesting part is that nothing is compiled here. The DragonRuby HTML5
build is a wasm module that asks the server which files its game is made of and
then fetches them; Dragonstation answers that question per cartridge. The
console library travels with every cart, so a cart is a directory that the
server describes rather than a file the server stores.

```
bin/rails db:prepare
bin/rails console:install DEFAULT=true
bin/rails server
```

Then sign in, upload a ZIP of a cart directory, and publish it.

## What a cartridge is

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
error, not a choice &mdash; see
[cartridge_ingest.rb](app/services/cartridge_ingest.rb) for the full list of
refusals.

## How a cart runs

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

### `filesize` is load-bearing

The manifest's `filesize` is not advisory. The loader does:

```js
var len = manifest[i].filesize;
var arr = new Array(len);
```

and fills it from the downloaded bytes. A short read pads the file with zeros, a
long one truncates it, and in both cases it happens silently &mdash; the game
breaks later, for a reason that points nowhere near the cause. So every size
published comes from the bytes that will actually be returned, and there is a
test that fetches every file over HTTP and compares it to the number the
manifest declared.

## Installing and publishing from the console

The console in `~/dev/dragonruby/console` and this site are two halves of one
workflow, and both halves can be done from a terminal:

```
GET  /console/library.zip    the library alone, public
GET  /console/bundle.zip     the library plus the reader's key, behind login
POST /api/carts              publish a cart, authenticated by that key
```

**The library is public on purpose.** This site already serves every byte of it
to any browser running a cart -- it is in the manifest and in `gamedata` -- so a
second copy behind a login would imply a restriction that does not exist, and
would break `./update-library` in a terminal that has no session to log in with.
The key is the opposite: it belongs to one account.

**The download is a console, not a library.** The first version of it shipped
only what a browser needs to run a cart, which left whoever unpacked it with a
directory of Ruby and nothing to run it with. `LibraryBundle` now serves the
whole release vendored under `vendor/console/<version>/`: the entry point, every
script under `bin/` (shell and `.bat`), the starter art, the metadata, the
README, and a `carts/` directory with a README in it. Unpacking it over a
checkout gives you a console that boots.

Two details that took a test to find: the ZIP carries **Unix modes**, because a
console whose scripts arrive non-executable is a console that cannot be run --
and `errors/last.txt`, `builds/` and one reader's `dragonstation.json` are
excluded, because they are that machine's state rather than the console's.

That vendored tree is a copy of `~/dev/dragonruby/console`, and keeping it
honest is manual: when the console moves, so does this copy. `vendor/console/`
is deliberately not wired into autoloading -- it is data, served, not code.

**The key is stored as a digest and nowhere else.** A SHA-256 digest, because a
key has to be *looked up* by the thing it authenticates -- a salted bcrypt digest
cannot answer "is this the key?" without checking every row, which is only
affordable for a password because there is one password to check. The entropy
is 32 bytes of `SecureRandom`.

That has one consequence worth stating plainly: **every personal download issues
a new key and retires the last one**, because the download is the only place the
secret exists. A console holding a retired key is refused with a 401 and told
what to do. The alternative -- encrypting the secret so it can be re-shipped --
needs record encryption keys this deployment does not have, and a key nobody can
read is worse than one they have to fetch twice.

**One key per account.** Issuing a new one replaces the old, which is also how a
leaked key is retired; there is no separate revoke, because with one key at a
time "give me a new one" and "this one is dead" are the same request.

`vendor/console/<version>/` is now a console release rather than a bare library,
so `ConsoleLibrary#file_paths` (the manifest, from `app/main.rb`'s require list)
and `LibraryBundle#release_paths` (the download, everything a person needs) are
deliberately different sets. The runtime must serve exactly what it requires; the
download should carry the source.

**Releasing a console is the same shape, for administrators.**
`POST /api/console_versions` runs `ConsoleLibraryInstall` on an uploaded ZIP, and
the credential is resolved to its owner and checked for admin **on every
request**. `403` for an ordinary member, not `401` -- the key was fine, the
account was not allowed. Installing a version never makes it the default and
never moves a cartridge: two decisions, both a person's.

The release script is only in an administrator's download, and the public
library -- which is what `./update-library` pulls -- never carries it. That is a
courtesy, not a control: the file being absent is not the thing stopping
anybody, the endpoint is.

**Publishing reuses the browser's upload.** `Api::CartsController` hands the
archive straight to `CartridgeIngest`, so traversal, symlinks, expansion bombs
and art-a-cart-names-but-does-not-own are all refused exactly as the form
refuses them -- and it arrives as a *draft*, because publishing stays a decision
a person makes after seeing the cart run. The only thing the API adds is who the
cart belongs to, which is what the key decides. `Current.user` falls back to the
key's owner, so every other check in the app works unchanged for a key.

An unknown key is a 401, never a redirect to a sign-in form a terminal cannot
answer, and refusals come back as JSON `problems` because the caller is a
script.

## Documentation

`/docs` is the console library's documentation, and it is public: it is the
reason anyone would upload a cart, and an author needs it before they have an
account.

It is built from two sources, and the split is the design:

- **The reference is read out of the library's own comments**
  ([ConsoleDocumentation](app/services/console_documentation.rb)). Every module
  has a header explaining what it is for and nearly every method has a comment
  saying what it does and why. Those comments are maintained alongside the code
  by whoever changed it last; a hand-written copy would be a second source of
  truth that is wrong within a release, and wrong *silently*, because stale
  docs still read as docs. So nothing here is written by hand &mdash; Ripper
  supplies the structure and the lexer supplies the comments, which Ruby does
  not keep in the parse tree. Nothing is evaluated: the library needs
  DragonRuby's `DR` and `$args`, and documentation must not depend on running
  the thing it describes.

  The library's own `# --- heading ---` dividers become section headings,
  because the grouping its author chose is more useful to a reader than any
  order this site could invent. Indented runs inside a comment become
  highlighted code, which is how the library writes its usage samples &mdash; the
  header of `cart_loader.rb` *is* the cart contract.

- **The guide is written here** ([ConsoleGuide](app/services/console_guide.rb)),
  because what a cart is and how to start one is not written down in the
  library. Five worked examples, each the smallest thing that does the job,
  plus the hooks table. There is a test that every call in them exists in the
  library, and another that every one of them parses as Ruby &mdash; a sample
  that invents a method is worse than no sample, because it reads as
  authoritative.

Every module page links its source, highlighted, served from the library
directory &mdash; so it is the same file the game runs. Docs that cannot be
checked against the implementation are a guess.

Both describe the **default** console version, and every page says which one. A
cart is pinned to a version, so a mismatch is a real possibility and a silent
one would be indistinguishable from a bug in the library.

## Reading a cart's files

The cart's page lists what is in the cart, and everything readable opens **in
place** &mdash; under the list, with the game still running above it:

```
GET /cartridges/space/files?path=app/space.rb   the contents of one file, as a page
```

Every link targets one `turbo-frame#file_viewer`, so a file is a fetch and a DOM
swap rather than a visit. That is the whole reason: this page is holding a wasm
runtime in a `data-turbo-permanent` iframe, and a Turbo visit would tear it down
and boot the game again to read one file. Opened directly it is an ordinary page,
and without JavaScript every link is a plain page load &mdash; only the staying
put is lost, not the reading.

These are the same bytes `play/gamedata/<path>` already serves to the game and to
anyone else &mdash; a published cart's source is not a secret &mdash; so this is
not a new disclosure. It is the same file with a reader around it: Ruby and data
files print, images render at their own size, and anything else is offered as a
download instead of being guessed at.

Two things decide what a page can show. The extension says what the file is
*named*, which is all that is available while listing fifty of them; the bytes
say what it *is*, using the same NUL-byte test `CartridgeIngest` uses to tell
source from asset. A file named `.txt` holding binary is not printed as mojibake.
Printing stops at 128KB and says so &mdash; silently stopping mid-file reads as
the whole file &mdash; and a file over 4MB is not read at all.

### Highlighting

[Rouge](https://github.com/rouge-ruby/rouge) marks the source up server-side.
That is not a preference: the file arrives inside a Turbo frame as HTML, so
anything that coloured it in the browser would have to run again on every frame
load and would not run at all with scripting off. Rouge emits classed spans and
the colours live in `application.css` with everything else, so the reader is
themed like the rest of the site.

The lexer comes from the file's name and nothing else &mdash; guessing by
content would mean reading the whole file to decide how to read it. A name Rouge
does not know is plain text, which is a correct answer rather than a failure.

Two consequences worth knowing:

- **Colours stop at 64KB.** Rouge emits about five times the source in markup, so
  at the reader's 128KB cap that is half a megabyte of HTML and a fifth of a
  second of lexing per click. Past 64KB a file prints plain, and says that it
  has. An LDTK map is exactly the kind of file that lands here.
- **It is the only `html_safe` string on the site.** Rouge escapes every token it
  emits and adds only its own spans, so the markup is safe to render as-is &mdash;
  but a cart is a stranger's upload, so there is a test that feeds the reader a
  file shaped like an attack and asserts it produces no tag.

Which cartridge a path belongs to is decided by the database, never by joining
the path onto a directory, so traversal has nothing to resolve against.
Visibility is the same rule the runtime and the cart's page use, written once in
[CartridgeVisibility](app/controllers/concerns/cartridge_visibility.rb).

### Why the path is a query parameter

Turbo refuses to navigate any URL whose last path segment ends in one of about
sixty extensions &mdash; `.png`, `.json`, `.txt`, `.wav` and the rest &mdash;
because those are usually downloads and the browser should handle them natively.
A cart is mostly sprites and data files, so links shaped like files open nothing
at all: they navigate away, which on this page means the game reloads. `.rb` is
not on that list, so a source file appears to work and hides the bug. The path
therefore rides in `?path=`, where no extension exists for Turbo to judge, and
there is a test that fails if a link ever ends in one of those extensions again.

It also retires an older trap. Rails decides the response format by matching
`/\.(\w+)\z/` against the request path, so a URL ending in `.json` asks for a
json template and answers 406 &mdash; a route cannot opt out, since `format: false`
stops *routing* from splitting the filename but not that match. With the path
out of the route there is nothing to match. The runtime route still has the
problem, because the loader asks for its files by name, and rebuilds each path
from `params[:path]` and `params[:format]` instead.

## Accounts

Registration is open. A username is the public identity a cartridge is
published under, so it is normalised (lowercased, any leading `@` stripped) and
held to a constant-safe shape: letters, numbers and underscores only. That is
not decoration — the console looks a cart's class up by directory name, and a
cartridge's URL slug derives from it.

The **first account to register becomes an admin.** A fresh install has no other
way to reach an admin screen, because every admin screen sits behind a login and
there is nobody to log in as. Once an admin exists, later registrations never
take it, even if that admin is deleted afterwards.

## Pinning

A cartridge is pinned to the console version it was uploaded against, forever.
Installing a new library changes what *new* uploads get and leaves published
games running the code they were built against &mdash; which is what makes a
leaderboard run comparable with the run beside it.

To add a version:

```sh
cp -r /path/to/console vendor/console/0.2.0     # trim it to app/ + fonts
bin/rails console:install VERSION=0.2.0 DEFAULT=true
bin/rails console:status
```

or upload a ZIP at `/admin/console_versions/new`.

`console:install` reads the version out of the library's own
`app/console/version.rb` and refuses a directory whose name disagrees with it.
The upload screen reads it from the same file and installs under it, so an
archive cannot be installed under a label its own code disagrees with.

Both paths run the same checks through `ConsoleLibraryInstall.inspect`, so a
library cannot be accepted by the task and refused by the screen, or the
reverse. The task is still the better route when the library is already in a
checkout: an upload lands in `vendor/console/` as untracked files, where
`git status` shows it and a commit records who added it.

### Installing is not updating

Neither path will replace an installed version, and the reason is specific
rather than cautious. Pinning is what makes a leaderboard run comparable with
the run beside it, and a cartridge's pin is the version *label* &mdash; the
`console_versions` row. Overwriting `vendor/console/0.2.0/` would leave every
label, every pin and every admin page looking exactly as they did while changing
the code every cartridge on that version runs. Nothing would report a problem.
The scores would simply stop meaning anything.

So an upload naming an installed version is refused by name, and the way to ship
a change is to bump `MAJOR.MINOR.PATCH` in `app/console/version.rb` and upload it
again as a new version. `console:install` stays idempotent &mdash; re-running it
on a checkout registers what is already there &mdash; but it registers, and never
rewrites files in place.

### What the upload is allowed to add

The one thing worth spelling out is `app/main.rb`. `ConsoleLibrary` reads the
require list out of that file and serves exactly those modules to every
cartridge on the version, and `CartridgeRuntimeController` picks the content
type from the extension. A `require 'app/console/payload.html'` would therefore
be served as `text/html` from this origin, to anyone loading a game.

Both install paths refuse a require that is not a `.rb` module directly under
`app/console/`, and refuse a require of anything at all that is missing or lives
outside that directory. The second one is not only a security check:
`ConsoleLibrary::REQUIRE_PATTERN` only matches `app/console/`, so a require of
`app/secrets.rb` would otherwise be *silently ignored* &mdash; installed as though
it were fine, then missing from every cartridge's served tree.

### One guard, two upload paths

`SafeArchive` holds the traversal, symlink and expansion-bomb refusals shared by
the cartridge upload and the library upload. A traversal guard written twice is
a traversal guard that will eventually exist once.

## Layout

```
app/services/console_library.rb     one vendored library version, as served
app/services/console_library_install.rb  a new version, from an archive or a directory
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
vendor/console/<version>/           vendored console libraries
lib/tasks/console.rake              console:install, console:status
```

## Admin

The first account to register is the operator, and `/admin` is the only place
that fact is used. `Admin::BaseController` answers a signed-in non-admin with a
404 rather than a redirect, because an admin URL that answers differently for a
stranger is an admin URL that can be written down &mdash; and its existing
existence is the only part that matters to whoever finds it. Anonymous visitors
are redirected to sign in, since `require_authentication` runs first.

Two screens so far:

| Path | What it is |
|---|---|
| `/admin` | counts, and the two states nothing else reports: a version with no directory, a version with none installed at all |
| `/admin/console_versions` | `console:status` as a page &mdash; per version, its state, module count, and the cartridges pinned to it |
| `/admin/console_versions/new` | upload a library as a version that does not exist yet |

Setting the default is a deliberate, separate act rather than a side effect of
uploading. It decides what a *new* cartridge is pinned to and cannot move one
that already exists.

## SharedArrayBuffer and cross-origin isolation

The wasm build uses threads, and `SharedArrayBuffer` is gated behind
cross-origin isolation. Every response on the play path therefore carries:

```
Cross-Origin-Opener-Policy: same-origin
Cross-Origin-Embedder-Policy: require-corp
```

The play page that embeds the iframe carries them too, because a nested
browsing context is only isolated when the embedding document opts in.

This is worth spelling out because the loader has a fallback. When it finds no
`SharedArrayBuffer`, it registers `dragonruby-serviceworker.js` &mdash; a shim
that rewrites these same headers onto every response from the client side, then
reloads the page so the document becomes controlled by it. With the headers set
here, `SharedArrayBuffer` is present on the first load and that path is never
entered.

It is worth having the headers anyway. The shim's fetch handler returns
`undefined` when the network fails, so a single failed request becomes an
unhandled rejection, a dead page, and a reload loop &mdash; which is exactly
the failure the service worker is supposed to prevent.

## The HTML5 build

`public/dragonruby/` is a DragonRuby **7.21** html5 build, copied verbatim from
a `dragonruby-publish` run.

It used to be the 6.16 build that shipped with the postcarts proof of concept,
and that one **booted the engine and then stopped, before its first game tick.**
Every cartridge was a blank grey canvas: the engine initialised render, read its
metadata, and never ran the cart. It was worth being precise about that, because
none of the obvious checks catch it -- the response was byte-exact, the status
was 200, there was no exception, and a cart whose `render` fills the screen with
solid red still produced grey.

Nearly all of the build is game-independent. The exception is the **loader
header** -- seven `GDragonRuby*` variables that `dragonruby-publish` writes per
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

Everything after them is generic -- the loader still fetches `manifest.json` and
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

Do not copy `manifest.json` or `gamedata/` -- those belong to the cart that was
built, not to the build.

## Not built yet

This is the core slice only: upload a cart, play it in the browser. Not here:

- **ratings and reviews** &mdash; no `Rating` model yet
- **leaderboards** &mdash; these need a console-library API for a running cart to
  submit a score with, which is its own design problem: it changes the library
  every cartridge is pinned to, so it wants pinning in place and settled first
- **editing a cartridge** &mdash; upload is create-only; `edit`/`update`/`destroy`
  routes are generated but unimplemented
- **desktop builds** &mdash; `dragonruby-publish --platforms=linux-amd64` works
  from the same cart, and the staging logic here is already its Ruby half, but
  nothing shells out to it. The web build no longer needs it: see above.