require "test_helper"

# metadata/game_metadata.txt and metadata/icon.png are load-bearing, not
# decoration. The HTML5 build calls FS.readFile('/metadata/icon.png') to draw
# the click-to-play overlay; when that path is absent from the manifest the read
# throws inside startClickToPlay and the game never reaches the click that would
# start it. It also reads the metadata for the game's identity, which is why the
# engine reported "hello-SDL" before this existed.
class ConsoleMetadataTest < ActiveSupport::TestCase
  setup do
    @version = console_version!
    @cartridge = ingest(space_cart, user: users(:one), title: "Space Rocks")
    @metadata = @cartridge.stager.metadata
  end

  test "is part of the served tree" do
    manifest = @cartridge.manifest

    assert_includes manifest, ConsoleMetadata::PATH
    assert_includes manifest, ConsoleMetadata::ICON_PATH
  end

  test "declares exactly the size the runtime serves" do
    manifest = @cartridge.manifest

    assert_equal @metadata.content.bytesize, manifest[ConsoleMetadata::PATH][:filesize]
    assert_equal @metadata.icon.bytesize, manifest[ConsoleMetadata::ICON_PATH][:filesize]
  end

  test "rewrites the cart's identity" do
    values = metadata_values

    assert_equal "space", values["gameid"]
    assert_equal "Space Rocks", values["gametitle"]
  end

  test "preserves every key that decides engine behaviour" do
    # The first six lines are positional; everything after is read by name.
    # Writing a fresh six-line file drops these, and the build stops matching
    # the checkout it was tested against with nothing to say so.
    values = metadata_values

    assert_equal "false", values["hd"]
    assert_equal "false", values["highdpi"]
  end

  test "keeps all six positional keys, in order" do
    keys = @metadata.content.lines.map { |l| l.split("=").first }

    assert_equal ConsoleMetadata::REQUIRED_KEYS, keys.first(6)
  end

  test "the icon is a real PNG the overlay can draw" do
    assert @metadata.icon.bytesize > 100
    assert_equal "\x89PNG".b, @metadata.icon[0, 4].b
  end

  test "a cart's own metadata wins, and is only filled where it is blank" do
    own = <<~TXT
      devid=megacorp
      devtitle=Megacorp
      gameid=my-own-id
      gametitle=
      version=2.5
      icon=metadata/icon.png
      orientation=landscape
    TXT

    cartridge = ingest(
      space_cart(
        "space/metadata/game_metadata.txt" => own,
        "space/metadata/icon.png" => "\x89PNG\r\n\x1A\n mine"
      ),
      user: users(:two)
    )

    values = cartridge.stager.metadata.content.lines.map { |l| l.chomp.split("=", 2) }.to_h

    # Its own identity is kept; the blank title is filled in.
    assert_equal "my-own-id", values["gameid"]
    assert_equal "space", values["gametitle"]
    # Its own engine settings are kept verbatim.
    assert_equal "Megacorp", values["devtitle"]
    assert_equal "2.5", values["version"]
    assert_equal "landscape", values["orientation"]
  end

  test "a cart's own icon wins over the console's" do
    cartridge = ingest(
      space_cart("space/metadata/icon.png" => "\x89PNG\r\n\x1A\n mine"),
      user: users(:two)
    )

    assert_equal "\x89PNG\r\n\x1A\n mine".b, cartridge.stager.metadata.icon.b
  end

  test "refuses metadata missing a positional key rather than serving it scrambled" do
    # A file missing one of the six shifts every later value across, because the
    # engine reads them positionally.
    truncated = "devid=x\ndevtitle=y\ngameid=z\n"

    cartridge = ingest(
      space_cart("space/metadata/game_metadata.txt" => truncated),
      user: users(:two)
    )

    error = assert_raises(ConsoleMetadata::Invalid) { cartridge.stager.metadata.content }

    assert_match(/missing required keys/, error.message)
    assert_match(/gametitle/, error.message)
  end

  private
    def metadata_values
      @metadata.content.lines.map { |l| l.chomp.split("=", 2) }.to_h
    end
end
