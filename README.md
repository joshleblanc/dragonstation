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

`console:install` reads the version out of the library's own
`app/console/version.rb` and refuses a directory whose name disagrees with it.
This is a rake task rather than an admin screen on purpose: installing a library
means dropping a directory into the repository and running one command, which is
reviewable and reversible. An endpoint that could replace the library every
cartridge is pinned to would be a much worse way to do the same thing.

## Layout

```
app/services/console_library.rb     one vendored library version, as served
app/services/cartridge_stager.rb    the served tree + the manifest
app/services/cartridge_ingest.rb    ZIP -> cartridge, or the reason why not
app/services/console_metadata.rb    the metadata and icon at the game root
app/services/html5_build.rb         the build, with its loader header rewritten
app/controllers/cartridge_runtime_controller.rb   manifest + gamedata + shell
app/controllers/concerns/cross_origin_isolation.rb  COOP/COEP for the wasm build
public/dragonruby/                  the DragonRuby HTML5 wasm build
vendor/console/<version>/           vendored console libraries
lib/tasks/console.rake              console:install, console:status
```

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