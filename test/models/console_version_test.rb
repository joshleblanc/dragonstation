require "test_helper"

# Which version a new upload gets pinned to.
#
# A pin is permanent, so the one path here that picks a version nobody chose is
# the one that has to be careful.
class ConsoleVersionTest < ActiveSupport::TestCase
  test "with nothing installed there is no default" do
    assert_nil ConsoleVersion.default
  end

  test "the fallback is the newest version" do
    install_console_library("0.1.0")
    install_console_library("0.2.0")

    assert_equal "0.2.0", ConsoleVersion.default.version
  end

  test "the fallback skips a version whose bytes are gone" do
    install_console_library("0.1.0")
    # Installed second, so it is the newest -- which is exactly how a later deploy
    # leaves a version on top of a working one.
    broken = install_console_library("0.2.0")
    lose_the_blobs!(broken)

    # Pinning a cartridge to the broken one produces a game that can never boot,
    # and the pin is what makes it permanent. The fallback falls through to the
    # version that can actually serve something.
    assert_equal "0.1.0", ConsoleVersion.default.version
  end

  test "the fallback skips a version with no files at all" do
    broken = ConsoleVersion.create!(version: "0.2.0")
    install_console_library("0.1.0")
    broken.touch

    assert_equal "0.1.0", ConsoleVersion.default.version
  end

  test "the fallback is nil when nothing can be read" do
    lose_the_blobs!(install_console_library("0.1.0"))

    assert_nil ConsoleVersion.default
  end

  test "a flagged version is the default even when it cannot be read" do
    # Deliberate, and the reason the fallback above is careful: an admin has
    # chosen this, and the admin pages are where that gets answered. Silently
    # building new cartridges against a different version would be worse.
    broken = install_console_library("0.2.0").tap { |v| v.update!(default: true) }
    install_console_library("0.1.0")
    lose_the_blobs!(broken)

    assert_equal "0.2.0", ConsoleVersion.default.version
  end

  test "a flagged version wins over a newer readable one" do
    install_console_library("0.1.0").update!(default: true)
    install_console_library("0.2.0")

    assert_equal "0.1.0", ConsoleVersion.default.version
  end
end
