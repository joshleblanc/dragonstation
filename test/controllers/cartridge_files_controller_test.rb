require "test_helper"

# Reading a cart's files as text.
#
# The runtime already serves these bytes to anyone, for the game to load, so
# nothing here is a new disclosure -- it is the same file with a reader around
# it. What the tests are really about is the two ways that can go wrong: showing
# something that is not text, and showing a file that belongs to someone else.
class CartridgeFilesControllerTest < ActionDispatch::IntegrationTest
  PNG = "\x89PNG\r\n\x1A\n binary \x00 bytes".b

  setup do
    console_version!
    @cartridge = ingest(
      space_cart(
        "space/lib/colors.rb" => "# cart art\nCOLORS = ['red', 'green']\n",
        "space/data/level.json" => '{"name":"cave","width":8}',
        "space/sprites/hero.png" => PNG,
        "space/sounds/beep.wav" => "RIFF \x00\x00\x00\x00WAVE".b
      ),
      user: users(:one)
    )
    @cartridge.publish!
  end

  # The whole point of the page: a cart's source is readable on the cart's page.
  test "shows the contents of a Ruby file" do
    get file_path("app/space.rb")

    assert_response :success
    assert_select "pre.source", /class Space/
    assert_select "pre.source", /TITLE = 'space'/
    assert_select "h1", /app\/space\.rb/
  end

# Highlighting costs about five times the source in markup, so a big file prints
# plain. It has to say so, or a map with no colours reads as a broken feature.
test "a file too big to highlight prints plain and says why" do
  # Varied content, not a repeated line: SafeArchive refuses anything that
  # compresses past 200x, which is exactly what a repeated line looks like.
  bulk = bulk_text(FileHighlighter::HIGHLIGHT_LIMIT + 100)
  cartridge = ingest(named_cart("big", "big/notes.rb" => bulk), user: users(:one))
  cartridge.publish!

  get file_path("notes.rb", cartridge.slug)

  assert_response :success
  assert_select "pre.source span", count: 0
  assert_select ".muted", /Printed plain rather than coloured/
end

test "prints a data file, not only Ruby" do
    get file_path("data/level.json")

    assert_response :success
    assert_select "pre.source", /"name":"cave"/
  end

  # The file's own words are not markup. This is the only html_safe string the
  # site renders, and a cart is a stranger's upload, so the property is checked
  # rather than assumed: Rouge marks up what it lexes and escapes the rest, and
  # these are the two ways that would stop being true.
  test "a file shaped like an attack cannot produce a tag" do
    payload = %q{PAYLOAD = "<img src=x onerror=alert(1)>" "<script>alert(2)</script>"}
    cartridge = ingest(named_cart("evil", "evil/data/payload.rb" => payload), user: users(:one))
    cartridge.publish!

    get file_path("data/payload.rb", cartridge.slug)

    assert_response :success
    assert_select "pre.source img", count: 0
    assert_select "pre.source script", count: 0
    assert_includes response.body, "&lt;img"
    assert_includes response.body, "&lt;script&gt;"
    # Still highlighted, so the escaping happened inside a lexer rather than by
    # giving up on the file.
    assert_select "pre.source span", minimum: 1
  end

  # Highlighting is what the reader is for: a cart is source first, and a wall
  # of uncoloured Ruby is a wall of unreadable Ruby.
  test "prints Ruby with its keywords, strings and comments marked" do
    get file_path("lib/colors.rb")

    assert_response :success
    assert_select "pre.source span.c1", /cart art/
    assert_select "pre.source span.no", /COLORS/
    assert_select "pre.source span.s1", /'red'/
  end

  test "marks up the entry file's own keywords" do
    get file_path("app/space.rb")

    assert_select "pre.source span.k", /class/
    assert_select "pre.source span.k", /def/
    assert_select "pre.source span.nc", /Space/
  end

  test "highlights JSON with its own lexer, not as Ruby" do
    get file_path("data/level.json")

    assert_response :success
    assert_select "pre.source span", minimum: 1
    assert_select "pre.source span.k", count: 0
  end

  # A name Rouge has no lexer for still prints; plain text is a correct answer
  # here rather than a failure.
  test "prints a file with no known lexer as plain text" do
    cartridge = ingest(
      named_cart("prose", "prose/notes.txt" => "Just words, and no lexer.\n"),
      user: users(:one)
    )
    cartridge.publish!

    get file_path("notes.txt", cartridge.slug)

    assert_response :success
    assert_select "pre.source", /no lexer/
    assert_select "pre.source span", count: 0
  end

  test "the cart page links every file it can show" do
    get cartridge_path(@cartridge)

    assert_response :success
    assert_select "a[href=?]", file_path("app/space.rb"), text: "app/space.rb"
    assert_select "a[href=?]", file_path("data/level.json"), text: "data/level.json"
    assert_select "a[href=?]", file_path("sprites/hero.png"), text: "sprites/hero.png"
  end

  # Reading a file must not be a visit. This page holds a running game in a
  # permanent iframe, and a Turbo visit rebuilds the whole wasm runtime behind
  # it -- so the links target a frame and nothing else on the page moves.
  test "the cart page opens files into a frame instead of navigating" do
    get cartridge_path(@cartridge)

    assert_select "turbo-frame#file_viewer"
    assert_select "a[href=?][data-turbo-frame=?]", file_path("app/space.rb"), "file_viewer",
      text: "app/space.rb"
  end

  # The constraint that makes it work, and the one a tidy URL would break.
  #
  # Turbo leaves any URL ending in one of ~60 extensions -- .png, .json, .txt,
  # .wav -- to the browser, so a download still downloads. A cart is mostly
  # sprites and data files, so links shaped like files open nothing at all and
  # navigate away instead. The path therefore rides in the query string, where
  # there is no extension for Turbo to judge.
  test "no file link ends in an extension Turbo refuses to navigate" do
    # Turbo's own list, as of the version this app ships.
    unvisitable = %w[.7z .bmp .csv .css .gif .ico .jpeg .jpg .js .json .mp3 .mp4 .ogg
                     .pdf .png .svg .tar .txt .wav .webm .webp .xml .zip]

    get cartridge_path(@cartridge)

    assert_select "a[data-turbo-frame=?]", "file_viewer" do |links|
      assert links.any?, "expected the file list to have links"

      links.each do |link|
        pathname = URI.parse(link["href"]).path

        refute_includes unvisitable, File.extname(pathname),
          "#{pathname} ends in an extension Turbo will not navigate"
      end
    end
  end

  # Turbo lifts the matching frame out of the response, so the file has to
  # arrive inside one with that id.
  test "the response carries the contents in the frame the page targets" do
    get file_path("app/space.rb")

    assert_response :success
    assert_select "turbo-frame#file_viewer" do
      assert_select "pre.source", /class Space/
    end
  end

  # Closing is a frame load too, not a visit back to the page.
  test "the viewer closes without leaving the cart" do
    get file_path("app/space.rb")

    assert_select "a[href=?][data-turbo-frame=?]", cartridge_path(@cartridge), "file_viewer",
      text: "Close"
  end

  # A download inside a frame would otherwise land in the frame as text.
  test "a download inside the frame is not loaded into the frame" do
    get file_path("sounds/beep.wav")

    assert_select "a[data-turbo-frame=_top]",
      href: "/cartridges/#{@cartridge.slug}/play/gamedata/carts/space/sounds/beep.wav"
  end

  test "an asset the page cannot show is listed without a link" do
    get cartridge_path(@cartridge)

    # A sound is not something to read, so the page does not offer to read it.
    assert_select "a[href=?]", file_path("sounds/beep.wav"), count: 0
    assert_select "code", text: "sounds/beep.wav"
  end

  # An image is shown from the route the loader itself uses, so the preview and
  # the game cannot disagree about which bytes these are.
  test "renders an image from the route the game loads it through" do
    get file_path("sprites/hero.png")

    assert_response :success
    assert_select "img[src=?]", "/cartridges/#{@cartridge.slug}/play/gamedata/carts/space/sprites/hero.png"
    assert_select "pre.source", count: 0
  end

  test "says an asset is not text instead of printing it" do
    get file_path("sounds/beep.wav")

    assert_response :success
    assert_select "pre.source", count: 0
    assert_select "a[href=?]", "/cartridges/#{@cartridge.slug}/play/gamedata/carts/space/sounds/beep.wav"
  end

  # The extension is a guess, and a guess a cart's author controls. Bytes with a
  # NUL in them are what every real binary has and no source file has -- the
  # same test CartridgeIngest uses, so the two cannot disagree about a file.
  test "does not print bytes that are not text, whatever the file is called" do
    cartridge = ingest(
      named_cart("liar", "liar/data/notes.txt" => "text until \x00\xFC\xFD then noise".b),
      user: users(:one)
    )
    cartridge.publish!

    get file_path("data/notes.txt", cartridge.slug)

    assert_response :success
    assert_select "pre.source", count: 0
  end

  test "truncates a file too long to print and says so" do
    cartridge = ingest(
      named_cart("long", "long/notes.txt" => "TITLE = 'space'\n#{bulk_text(CartridgeFilesController::TEXT_LIMIT)}"),
      user: users(:one)
    )
    cartridge.publish!

    get file_path("notes.txt", cartridge.slug)

    assert_response :success
    assert_select "pre.source", /TITLE = 'space'/
    # Silently stopping would read as the whole file.
    assert_select ".muted", /Showing the first/
  end

  # Reading a file to show its first 128KB is a bad trade at 4MB, and the
  # download is the honest answer.
  test "offers a download rather than reading a file too large to print" do
    cartridge = ingest(
      named_cart("huge", "huge/data/big.txt" => Random.new(1234).bytes(CartridgeFilesController::READ_LIMIT + 1)),
      user: users(:one)
    )
    cartridge.publish!

    get file_path("data/big.txt", cartridge.slug)

    assert_response :success
    assert_select "pre.source", count: 0
    assert_select "a", text: /Download it/
  end

  test "does not serve a file that is not in the cartridge" do
    get file_path("app/console/core.rb")
    assert_response :not_found

    get file_path("app/not_a_thing.rb")
    assert_response :not_found
  end

  test "refuses a path that escapes the cartridge" do
    get file_path("../../config/master.key")
    assert_response :not_found

    get file_path("../other/app/other.rb")
    assert_response :not_found
  end

  # The reader looks files up by their stored path, so one cart cannot read
  # another's source by naming it -- including a cart of the same name under a
  # different console version.
  test "one cartridge cannot read another's files" do
    other = ingest(named_cart("other"), user: users(:two))
    other.publish!

    get file_path("app/space.rb", other.slug)

    assert_response :not_found
  end

  test "an unknown cartridge is a 404" do
    get file_path("app/space.rb", "no-such-cart")

    assert_response :not_found
  end

  test "a draft is not readable by an anonymous visitor" do
    draft = ingest(named_cart("draft"), user: users(:one))

    assert draft.draft?

    get file_path("app/draft.rb", draft.slug)
    assert_response :not_found
  end

  test "a draft is not readable by a stranger" do
    draft = ingest(named_cart("draft"), user: users(:one))
    sign_in_as users(:two)

    get file_path("app/draft.rb", draft.slug)

    assert_response :not_found
  end

  test "the owner can read their own draft" do
    draft = ingest(named_cart("draft"), user: users(:one))
    sign_in_as users(:one)

    get file_path("app/draft.rb", draft.slug)

    assert_response :success
    assert_select "pre.source", /class Draft/
  end

  test "an admin can read a draft" do
    draft = ingest(named_cart("draft"), user: users(:one))
    users(:two).update!(admin: true)
    sign_in_as users(:two)

    get file_path("app/draft.rb", draft.slug)

    assert_response :success
  end

  private
    def file_path(path, slug = @cartridge.slug)
      "/cartridges/#{slug}/files?path=#{CGI.escape(path)}"
    end

    # Enough text to trip the reader's cap, and varied enough that SafeArchive
    # does not read it as a decompression bomb -- which is exactly what a run of
    # one repeated character looks like.
    def bulk_text(size)
      alphabet = ("a".."z").to_a
      Array.new(size) { alphabet.sample }.join
    end
end
