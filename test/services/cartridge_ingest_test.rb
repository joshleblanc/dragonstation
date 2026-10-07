require "test_helper"

class CartridgeIngestTest < ActiveSupport::TestCase
  setup { @version = console_version! }

  test "accepts a cart wrapped in its own directory" do
    cartridge = ingest(space_cart, user: users(:one))

    assert_equal "space", cartridge.cart_name
    assert_equal "app/space.rb", cartridge.entry_path
    assert_equal "space", cartridge.slug
    assert_equal "space", cartridge.title
    assert_equal @version, cartridge.console_version
    assert cartridge.draft?
  end

  test "stores every file cart-relative with a byte-exact size" do
    cartridge = ingest(
      space_cart("space/sprites/hero.png" => "\x89PNG\r\n\x1A\n binary \x00 bytes"),
      user: users(:one)
    )

    file = cartridge.cartridge_files.find_by!(path: "sprites/hero.png")

    assert_equal file.blob.byte_size, file.byte_size
    assert_equal "\x89PNG\r\n\x1A\n binary \x00 bytes".b.bytesize, file.byte_size
  end

  test "ignores files that sit beside the cart rather than inside it" do
    cartridge = ingest(
      space_cart("README.md" => "# my project", ".gitignore" => "tmp/"),
      user: users(:one)
    )

    paths = cartridge.cartridge_files.pluck(:path)

    assert_includes paths, "app/space.rb"
    assert_not_includes paths, "README.md"
    assert_not_includes paths, ".gitignore"
  end

  test "accepts an archive that is the cart itself, naming it from the entry file" do
    cartridge = ingest(
      { "app/space.rb" => "class Space; end" },
      user: users(:one)
    )

    assert_equal "space", cartridge.cart_name
    assert_equal "app/space.rb", cartridge.entry_path
  end

  test "prefers app/main.rb over an app/<name>.rb entry file" do
    cartridge = ingest(
      {
        "space/app/main.rb" => "class Space; end",
        "space/app/space.rb" => "raise 'should not be the entry'"
      },
      user: users(:one)
    )

    assert_equal "app/main.rb", cartridge.entry_path
  end

  test "takes the uploader's title over the cart's own TITLE" do
    cartridge = ingest(space_cart, user: users(:one), title: "Space Rocks")

    assert_equal "Space Rocks", cartridge.title
  end

  # --- refusals -------------------------------------------------------

  test "refuses a path that escapes the cart" do
    assert_rejected space_cart("space/../../../etc/passwd" => "root"), /escapes the cart/
  end

  test "refuses a nested path that escapes the cart" do
    assert_rejected space_cart("space/sprites/../../outside.png" => "x"), /escapes the cart/
  end

  test "refuses an absolute path in an entry name" do
    # rubyzip refuses to *write* an entry with an absolute name, so an archive
    # containing one cannot be built with it. Archives come from other tools,
    # so the guard still has to hold on its own rather than lean on the writer.
    ingest = CartridgeIngest.new(archive: StringIO.new(""), user: users(:one), console_version: @version)

    error = assert_raises(CartridgeIngest::Invalid) { ingest.send(:safe_path, "/etc/passwd") }

    assert_match(/absolute path/, error.message)
  end

  test "refuses a backslash traversal" do
    ingest = CartridgeIngest.new(archive: StringIO.new(""), user: users(:one), console_version: @version)

    error = assert_raises(CartridgeIngest::Invalid) { ingest.send(:safe_path, "..\\..\\windows\\system32") }

    assert_match(/escapes the cart/, error.message)
  end

  test "refuses a symlink entry" do
    # rubyzip 3.7 always writes ftype :file, even with the symlink bit set, so
    # a symlink archive cannot be built through it. The guard still earns a
    # test: archives come from other tools, and a symlink entry is a path that
    # names somewhere else.
    entry = Struct.new(:name, :directory?, :symlink?).new("space/sprites/link", false, true)
    zip = Object.new
    zip.define_singleton_method(:each) { |&block| block.call(entry) }

    ingest = CartridgeIngest.new(archive: StringIO.new("zipbytes"), user: users(:one), console_version: @version)
    ingest.define_singleton_method(:with_zip) { |&block| block.call(zip) }

    error = assert_raises(CartridgeIngest::Invalid) { ingest.call }

    assert_match(/symbolic link/, error.message)
  end

  test "refuses an archive holding more than one cart" do
    assert_rejected(
      space_cart("arcade/app/arcade.rb" => "class Arcade; end"),
      /more than one cart/
    )
  end

  test "refuses an archive with no cart in it" do
    assert_rejected({ "notes.txt" => "hello" }, /no cart found/)
  end

  test "refuses a cart with no entry file" do
    # A cart directory with an app/ in it but no .rb to boot from.
    assert_rejected({ "space/app/notes.txt" => "just a note" }, /no entry file/)
  end

  test "refuses a cart that references an asset it does not own" do
    assert_rejected(
      { "space/app/space.rb" => "class Space; def render; draw_sprite 'sprites/missing.png'; end; end" },
      /uses assets it does not own.*sprites\/missing\.png/m
    )
  end

  test "accepts a cart that owns every asset it references" do
    cartridge = ingest(
      {
        "space/app/space.rb" => "class Space; def render; draw_sprite 'sprites/hero.png'; end; end",
        "space/sprites/hero.png" => "\x89PNG\x00"
      },
      user: users(:one)
    )

    assert_equal 2, cartridge.cartridge_files.count
  end

  test "does not read asset references out of binary files" do
    # A PNG can contain bytes that look like a quoted path. Grepping raw binary
    # would invent missing-asset errors out of compressed data.
    cartridge = ingest(
      space_cart("space/sprites/hero.png" => "\x89PNG\x00'sprites/nope.png' more\x00"),
      user: users(:one)
    )

    assert_equal "space", cartridge.cart_name
  end

  test "exempts the console's own diagnostic cart from the asset check" do
    cartridge = ingest(
      { "selftest/app/selftest.rb" => "class Selftest; def render; draw 'sprites/absent.png'; end; end" },
      user: users(:one)
    )

    assert_equal "selftest", cartridge.cart_name
  end

  test "refuses a cart whose directory name is not a Ruby constant" do
    assert_rejected(
      { "my-game/app/my-game.rb" => "class Something; end" },
      /not a usable cart name/
    )
  end

  test "refuses an archive that expands past the file limit" do
    many = space_cart
    600.times { |i| many["space/data/file#{i}.txt"] = "x" }

    assert_rejected many, /more than 512 files/
  end

  test "refuses an empty archive" do
    assert_rejected({}, /empty/)
  end

  test "gives two uploads of the same cart different slugs" do
    first = ingest(space_cart, user: users(:one))
    second = ingest(space_cart, user: users(:two))

    assert_equal "space", first.slug
    assert_equal "space-2", second.slug
  end

  # This one exists because of a bug this file could not see.
  #
  # rubyzip reaches the app as a dependency of activestorage, and Bundler.require
  # requires only the gems named in the Gemfile -- not their dependencies.
  # ActiveStorage requires zip lazily inside archive analysis, a different code
  # path from ours. So the only thing that had ever loaded Zip was the require at
  # the top of the test helper: the suite was green and every real upload was a
  # 500 on `uninitialized constant CartridgeIngest::Zip`.
  #
  # Nothing in this process can catch that, because this process loaded zip long
  # before the service was asked for it. So this shells out to a process that
  # booted the app and nothing else.
  #
  # Development, not test: the test environment eager-loads under CI and pulls in
  # capybara, either of which would load zip and hide the thing being tested. The
  # script only inspects constants, so touching the development database is not a
  # concern.
  test "the app loads rubyzip itself, not the test suite around it" do
    script = <<~RUBY
      raise "zip was already loaded by something other than the app" if defined?(Zip)

      CartridgeIngest # autoloaded the way a request autoloads it

      raise "CartridgeIngest did not require zip" unless defined?(Zip)
      puts "ok"
    RUBY

    path = Rails.root.join("tmp/zip_require_probe.rb")
    File.write(path, script)

    output = IO.popen(
      [ { "RAILS_ENV" => "development" }, "bin/rails", "runner", path.to_s ],
      err: %i[child out],
      &:read
    )

    assert_equal "ok", output.strip.lines.last&.strip,
      "booting the app alone did not load zip:\n#{output}"
  ensure
    FileUtils.rm_f(Rails.root.join("tmp/zip_require_probe.rb"))
  end
end
