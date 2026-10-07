require "test_helper"

# The loader's contract, exercised over real HTTP responses.
#
# The decisive assertion is that every filesize the manifest publishes is the
# exact byte length of what comes back for that path. The loader allocates
# `new Array(manifest.filesize)` and fills it from the response, so a wrong
# number does not error -- it writes a padded or truncated file into DragonRuby's
# virtual filesystem, and the game breaks later for a reason that points nowhere
# near the cause.
class CartridgeRuntimeControllerTest < ActionDispatch::IntegrationTest
  setup do
    console_version!
    @cartridge = ingest(space_cart, user: users(:one))
    @cartridge.publish!
  end

  test "the manifest is the shape the loader JSON.parses" do
    get manifest_path

    assert_response :success
    parsed = JSON.parse(response.body)

    assert_kind_of Hash, parsed
    parsed.each do |name, meta|
      assert_kind_of Integer, meta["filesize"], "#{name} has no integer filesize"
      assert_kind_of Integer, meta["filetime"], "#{name} has no integer filetime"
      assert_operator meta["filesize"], :>=, 0
    end
  end

  test "every file the manifest lists is served at exactly its declared size" do
    manifest = fetch_manifest

    assert_operator manifest.size, :>, 20, "expected the library and the cart in the manifest"

    manifest.each do |path, meta|
      get data_path(path)

      assert_response :success, "gamedata/#{path} was not served"
      assert_equal meta["filesize"], response.body.b.bytesize,
        "manifest declares #{meta['filesize']} for #{path}, response carried #{response.body.b.bytesize}"
    end
  end

  test "the served bytes are the file, not merely a file of the right length" do
    get data_path("carts/space/app/space.rb")

    assert_response :success
    assert_includes response.body, "class Space"
    assert_includes response.body, "TITLE = 'space'"
  end

  test "serves the generated entry point rather than anything the cart uploaded" do
    get data_path("app/main.rb")

    assert_response :success
    assert_includes response.body, "pin('carts/space')"
  end

  test "serves the console library the cartridge is pinned to" do
    get data_path("app/console/core.rb")

    assert_response :success
    assert_includes response.body, "module Console"
  end

  test "serves both fonts" do
    get data_path("font.ttf")
    assert_response :success
    assert_operator response.body.b.bytesize, :>, 100_000

    get data_path("tiny.ttf")
    assert_response :success
  end

  test "the shell loads the HTML5 loader" do
    get "/cartridges/#{@cartridge.slug}/play/index.html"

    assert_response :success
    assert_includes response.body, "dragonruby-html5-loader.js"
  end

  # The regression that matters most here. Every runtime test asserts a 200 and
  # the right bytes, which is not enough: served as application/octet-stream or
  # with a Content-Disposition of attachment, the browser downloads
  # index.html instead of rendering it and the build stops working while every
  # request still returns 200.
  test "serves the shell as HTML to be rendered, not as a file to download" do
    get "/cartridges/#{@cartridge.slug}/play/index.html"

    assert_response :success
    assert_equal "text/html", response.media_type
    assert_match(/\binline\b/, response.headers["Content-Disposition"].to_s)
  end

  test "serves every build file with a content type a browser will act on" do
    {
      "game.css" => "text/css",
      "dragonruby-html5-loader.js" => "text/javascript",
      "dragonruby-wasm.js" => "text/javascript",
      "dragonruby-wasm.worker.js" => "text/javascript",
      "dragonruby-wasm.wasm" => "application/wasm",
      "favicon.png" => "image/png"
    }.each do |file, expected|
      get "/cartridges/#{@cartridge.slug}/play/#{file}"

      assert_response :success, "#{file} was not served"
      assert_equal expected, response.media_type, "#{file} was served as #{response.media_type}"
    end
  end

  test "serves fonts with their own content type" do
    get data_path("font.ttf")

    assert_response :success
    assert_equal "font/ttf", response.media_type
  end

  test "every served file gets some content type" do
    # The loader reads gamedata as an arraybuffer and does not care what this
    # says, but octet-stream-everywhere is the shape of the bug above, so no
    # file should silently land there.
    fetch_manifest.each_key do |path|
      get data_path(path)

      assert_response :success
      assert response.media_type.present?, "#{path} was served with no content type"
    end
  end

  # SharedArrayBuffer is gated behind cross-origin isolation. Without these the
  # loader finds no SharedArrayBuffer and falls back to registering a service
  # worker to fake them -- which costs a reload and breaks on any failed
  # request. The server sends them instead, so that fallback is unreachable.
  test "the shell is cross-origin isolated, so the wasm build gets SharedArrayBuffer" do
    get "/cartridges/#{@cartridge.slug}/play/index.html"

    assert_equal "same-origin", response.headers["Cross-Origin-Opener-Policy"]
    assert_equal "require-corp", response.headers["Cross-Origin-Embedder-Policy"]
  end

  test "every build file is cross-origin isolated" do
    %w[index.html dragonruby-wasm.js dragonruby-wasm.wasm].each do |file|
      get "/cartridges/#{@cartridge.slug}/play/#{file}"

      assert_equal "same-origin", response.headers["Cross-Origin-Opener-Policy"], "#{file} had no COOP"
      assert_equal "require-corp", response.headers["Cross-Origin-Embedder-Policy"], "#{file} had no COEP"
    end
  end

  test "game files are cross-origin isolated" do
    fetch_manifest.each_key do |path|
      get data_path(path)

      assert_equal "require-corp", response.headers["Cross-Origin-Embedder-Policy"], "#{path} had no COEP"
    end
  end

  test "the page carrying the iframe opts into isolating it" do
    # A nested browsing context is only cross-origin isolated when the
    # embedding document opts in too, so the play page needs COEP as well.
    get cartridge_path(@cartridge)

    assert_response :success
    assert_equal "require-corp", response.headers["Cross-Origin-Embedder-Policy"]
  end

  test "the COOP/COEP service worker is never needed" do
    # The loader only registers the shim when SharedArrayBuffer is missing. With
    # the headers in place it is unreachable, and the file is still served so
    # that nothing 404s if a stale registration asks for it.
    get "/cartridges/#{@cartridge.slug}/play/dragonruby-serviceworker.js"

    assert_response :success
  end

  test "the shell serves the wasm build the loader needs" do
    %w[dragonruby-html5-loader.js dragonruby-wasm.js dragonruby-wasm.wasm dragonruby-wasm.worker.js game.css].each do |file|
      get "/cartridges/#{@cartridge.slug}/play/#{file}"

      assert_response :success, "#{file} was not served"
    end
  end

  test "does not serve build files that are not on the whitelist" do
    get "/cartridges/#{@cartridge.slug}/play/index.html.bak"
    assert_response :not_found

    get "/cartridges/#{@cartridge.slug}/play/../../../Gemfile"
    assert_response :not_found
  end

  test "does not serve a file that is not in the manifest" do
    get data_path("app/console/not_a_module.rb")
    assert_response :not_found

    get data_path("carts/other/app/other.rb")
    assert_response :not_found
  end

  test "refuses a path that escapes the cartridge" do
    get data_path("../../../config/master.key")
    assert_response :not_found

    get data_path("carts/space/../../../../etc/passwd")
    assert_response :not_found
  end

  test "a draft is not visible to an anonymous visitor" do
    draft = ingest(named_cart("draft"), user: users(:one))

    assert draft.draft?

    get manifest_path(draft.slug)
    assert_response :not_found

    get "/cartridges/#{draft.slug}"
    assert_response :not_found
  end

  # The owner is sent straight here after uploading, so if the page 404s for
  # them the upload looks like it failed even though it worked.
  test "the owner can open their own draft's page" do
    draft = ingest(named_cart("draft"), user: users(:one))
    sign_in_as users(:one)

    get cartridge_path(draft)

    assert_response :success
    assert_select "h1", text: draft.title
    assert_select ".draft-banner"
  end

  test "the owner can publish from their draft's page" do
    draft = ingest(named_cart("draft"), user: users(:one))
    sign_in_as users(:one)

    get cartridge_path(draft)

    assert_select "form[action=?]", publish_cartridge_path(draft)
  end

  test "a stranger cannot open someone else's draft" do
    draft = ingest(named_cart("draft"), user: users(:one))
    sign_in_as users(:two)

    get cartridge_path(draft)

    assert_response :not_found
  end

  test "an anonymous visitor cannot open someone else's draft" do
    draft = ingest(named_cart("draft"), user: users(:one))

    get cartridge_path(draft)

    assert_response :not_found
  end

  test "a draft is visible to its owner" do
    draft = ingest(named_cart("draft"), user: users(:one))
    sign_in_as users(:one)

    get manifest_path(draft.slug)

    assert_response :success
  end

  test "a draft is visible to an admin" do
    draft = ingest(named_cart("draft"), user: users(:one))
    users(:two).update!(admin: true)
    sign_in_as users(:two)

    get manifest_path(draft.slug)

    assert_response :success
  end

  test "one cartridge cannot read another's files" do
    other = ingest(named_cart("other"), user: users(:two))
    other.publish!

    get "/cartridges/#{other.slug}/play/gamedata/carts/space/app/space.rb"

    assert_response :not_found
  end

  test "an unknown cartridge is a 404" do
    get manifest_path("no-such-cart")

    assert_response :not_found
  end

  test "published cartridges appear in the gallery" do
    get root_path

    assert_response :success
    assert_select "h2", text: @cartridge.title
  end

  test "drafts stay out of the gallery" do
    ingest(named_cart("draft"), user: users(:one))

    get root_path

    assert_response :success
    assert_select "h2", text: /draft/i, count: 0
  end

  test "the owner can publish and unpublish" do
    sign_in_as users(:one)

    patch publish_path(@cartridge, state: "draft")
    assert_redirected_to cartridge_path(@cartridge)
    assert @cartridge.reload.draft?

    # Unpublishing hides it from the public, not from its owner -- they still
    # need to be able to run it while they work on it.
    get manifest_path
    assert_response :success

    sign_out
    get manifest_path
    assert_response :not_found

    sign_in_as users(:one)
    patch publish_path(@cartridge.reload, state: "published")
    assert @cartridge.reload.published?

    sign_out
    get manifest_path
    assert_response :success
  end

  test "a stranger cannot publish" do
    sign_in_as users(:two)

    patch publish_path(@cartridge, state: "draft")

    assert_response :not_found
    assert @cartridge.reload.published?
  end

  test "an anonymous visitor cannot reach the upload form" do
    get new_cartridge_path

    assert_redirected_to new_session_path
  end

  test "a signed-in member can upload a cart through the form" do
    sign_in_as users(:one)

    archive = build_archive(space_cart)

    post cartridges_path, params: {
      cartridge: { archive: fixture_file_upload_from(archive, "space.zip") }
    }

    cartridge = Cartridge.order(:id).last
    assert_redirected_to cartridge_path(cartridge)
    assert_equal "space", cartridge.cart_name
    assert cartridge.draft?
  end

  test "an invalid archive re-renders the form with the reason" do
    sign_in_as users(:one)

    archive = build_archive({ "notes.txt" => "not a cart" })

    post cartridges_path, params: {
      cartridge: { archive: fixture_file_upload_from(archive, "nope.zip") }
    }

    assert_response :unprocessable_content
    assert_select "pre.flash-alert", /no cart found/
  end

  private
    def fixture_file_upload_from(io, name)
      Rack::Test::UploadedFile.new(
        StringIO.new(io.read), "application/zip", original_filename: name
      )
    end

    def fetch_manifest
      get manifest_path
      assert_response :success
      JSON.parse(response.body)
    end

    def manifest_path(slug = @cartridge.slug)
      "/cartridges/#{slug}/play/manifest.json"
    end

    def data_path(path, slug = @cartridge.slug)
      "/cartridges/#{slug}/play/gamedata/#{path}"
    end

    def publish_path(cartridge, state:)
      "/cartridges/#{cartridge.slug}/publish?state=#{state}"
    end
end
