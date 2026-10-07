require "test_helper"

# The manifest is the contract between this server and the DragonRuby HTML5
# loader. The loader allocates a buffer of exactly manifest.filesize and fills
# it from the response, so a wrong number does not raise -- it writes a padded
# or truncated file into the game's virtual filesystem and the failure surfaces
# later, somewhere else, pointing nowhere near the cause.
#
# These tests are mostly about that number.
class CartridgeStagerTest < ActiveSupport::TestCase
  setup do
    @version = console_version!
    @cartridge = ingest(space_cart, user: users(:one))
    @stager = @cartridge.stager
    @manifest = @stager.manifest
  end

  test "manifest sizes are the exact byte length of every file it serves" do
    @manifest.each do |path, meta|
      bytes = served_bytes(@cartridge, path)

      assert_equal bytes.bytesize, meta[:filesize],
        "manifest says #{meta[:filesize]} for #{path}, server returns #{bytes.bytesize}"
    end
  end

  test "sizes are byte counts, not character counts" do
    # A cart file with multi-byte UTF-8 in it. Character length would be
    # smaller than byte length, and the loader would write a file short by
    # exactly the difference -- which parses as a syntax error at the end of
    # the file rather than as a bad manifest.
    cartridge = ingest(
      space_cart("space/app/notes.rb" => "# café naïve ✓\n"),
      user: users(:two)
    )

    path = "carts/space/app/notes.rb"
    bytes = served_bytes(cartridge, path)
    text = bytes.dup.force_encoding(Encoding::UTF_8)

    assert_operator bytes.bytesize, :>, text.length
    assert_equal bytes.bytesize, cartridge.manifest[path][:filesize]
  end

  test "manifest carries the console library, the cart, and a generated entry point" do
    assert_includes @manifest, "app/main.rb"
    assert_includes @manifest, "app/console/core.rb"
    assert_includes @manifest, "font.ttf"
    assert_includes @manifest, "carts/space/app/space.rb"

    assert @manifest.keys.count { |p| p.start_with?("app/console/") } > 1
  end

  test "manifest carries every font the library ships" do
    assert_includes @manifest, "font.ttf"
    assert_includes @manifest, "tiny.ttf"
  end

  test "carries no console-root starter art" do
    # publish-cart stages the cart alone so a borrowed asset becomes a visibly
    # missing sprite. Nothing outside the cart and the library is served, so
    # the same reasoning holds here.
    stray = @manifest.keys.select { |p| p.start_with?("sprites/") && !p.start_with?("carts/") }

    assert_empty stray
  end

  test "the generated entry point pins exactly this cart" do
    source = @stager.entry_source

    assert_match "pin('carts/space')", source
  end

  test "the generated entry point requires the library in the library's own order" do
    source = @stager.entry_source
    required = source.scan(/^require '([^']+)'$/).flatten
    library_order = @version.library.require_paths

    assert_equal library_order, required
    assert_equal "app/console/version.rb", required.first
    assert_equal "app/console/core.rb", required.last
  end

  test "the generated entry point follows the console's own boot shape" do
    source = @stager.entry_source

    assert_match(/module Main/, source)
    assert_match(/def boot/, source)
    assert_match(/def tick/, source)
    assert_match(/Console\.tick args/, source)
  end

  test "every served path resolves back to a file" do
    @manifest.each_key do |path|
      assert @stager.resolve(path), "#{path} is in the manifest but resolve() cannot find it"
    end
  end

  test "resolve returns nothing for a path the cartridge does not serve" do
    assert_nil @stager.resolve("app/console/not_a_module.rb")
    assert_nil @stager.resolve("carts/other/app/other.rb")
    assert_nil @stager.resolve("../../etc/passwd")
  end

  test "the library travels with the cart under the cart's own prefix" do
    # The cart never hardcodes its own name; Console::CartLoader finds it.
    # cart_prefix is the one place that name is written down.
    assert_equal "carts/space", @cartridge.cart_prefix
    assert @manifest.keys.any? { |p| p.start_with?("carts/space/") }
  end

  test "filetime is stable across reads" do
    # The loader re-downloads a cached file whenever filetime moves, so a value
    # that shifted per request would defeat its cache without telling it
    # anything true.
    first = @cartridge.manifest
    second = Cartridge.find(@cartridge.id).manifest

    assert_equal first, second
  end

  test "the denormalised size never drifts from the blob it came from" do
    @cartridge.cartridge_files.each do |file|
      assert_equal file.blob.byte_size, file.byte_size, "#{file.path} drifted"
    end
  end

  test "a cartridge keeps serving the library version it was pinned to" do
    # The whole reason a cartridge has a console_version_id: installing a new
    # library must not change what an already-published game runs.
    Dir.mktmpdir do |root|
      write_library(root, "0.1.0", "OLD LIBRARY")
      write_library(root, "0.9.0", "NEW LIBRARY")

      with_library_root(root) do
        old = console_version!
        old.update!(default: true)
        pinned = ingest(space_cart, user: users(:one), console_version: old)

        # A new library arrives and becomes the default for new uploads.
        fresh = ConsoleVersion.create!(version: "0.9.0", default: true)
        assert_equal fresh, ConsoleVersion.default

        # The old cartridge does not move.
        pinned.reload
        assert_equal old, pinned.console_version
        assert_includes pinned.manifest.keys, "app/console/marker.rb"
        assert_includes served_bytes(pinned, "app/console/marker.rb"), "OLD LIBRARY"

        # And a cartridge uploaded now does move.
        newcomer = ingest(space_cart, user: users(:two))
        assert_equal fresh, newcomer.console_version
        assert_includes served_bytes(newcomer, "app/console/marker.rb"), "NEW LIBRARY"
      end
    end
  end

  test "a console version whose directory is missing fails loudly rather than silently" do
    orphan = ConsoleVersion.create!(version: "9.9.9")

    refute orphan.available?
    assert_raises(CartridgeStager::MissingLibrary) do
      Cartridge.create!(
        user: users(:one), console_version: orphan, title: "orphan",
        slug: "orphan", cart_name: "orphan", entry_path: "app/orphan.rb"
      ).manifest
    end
  end

  private
    def write_library(root, version, marker)
      dir = File.join(root, version, "app", "console")
      FileUtils.mkdir_p(dir)
      # A library carries metadata and an icon too: the build reads
      # /metadata/icon.png to draw the click-to-play overlay, so a fixture
      # without them is not a library anything can actually run.
      FileUtils.mkdir_p(File.join(root, version, "metadata"))

      File.write(File.join(root, version, "app", "main.rb"),
        "require 'app/console/version.rb'\nrequire 'app/console/marker.rb'\n")
      File.write(File.join(dir, "version.rb"),
        "module Console\n  module Version\n    MAJOR = #{version.split('.').join("\n    ")}\n  end\nend\n")
      File.write(File.join(dir, "marker.rb"), "# #{marker}\n")
      File.write(File.join(root, version, "metadata", "game_metadata.txt"), <<~TXT)
        devid=dragonruby
        devtitle=Console
        gameid=console
        gametitle=Console
        version=1.0
        icon=metadata/icon.png
        highdpi=false
      TXT
      File.binwrite(File.join(root, version, "metadata", "icon.png"), "\x89PNG\r\n\x1A\n #{marker}")
    end

  # ConsoleLibraryTestHelper#with_library_root does the swap, including
  # clearing ConsoleVersion's memoized library so a row loaded before the
  # swap cannot keep reading the real vendor directory.
end
