require "test_helper"

# What it means for a library to be readable.
#
# The predicate every guard in the app is built on -- the admin index, the docs
# pages, the upload dropdown, the stager -- and the one that was wrong. It used
# to answer a question about the database ("is there a row named app/main.rb?")
# and was read as an answer about storage. A version whose blobs had been left
# behind on a disk this container does not have passed every one of those guards
# and then raised ActiveStorage::FileNotFoundError out of the first real read,
# which nothing in the app rescues.
class ConsoleLibraryTest < ActiveSupport::TestCase
  setup { @version = install_console_library("0.1.0") }

  test "an installed library is available" do
    assert @version.available?
  end

  test "a version with no files at all is not available" do
    assert_not ConsoleVersion.create!(version: "9.9.9").available?
  end

  test "a library whose bytes are gone is not available" do
    # The rows are all still there. That is the state a fresh deploy leaves when
    # the blobs name a service it does not have.
    lose_the_blobs!(@version)

    assert_not @version.reload.available?
  end

  test "reading a file whose bytes are gone raises Missing rather than a storage error" do
    lose_the_blobs!(@version)

    # This is the assertion the whole fix rests on. Every guard around a broken
    # library in this app rescues ConsoleLibrary::Missing and nothing else, so a
    # storage error escaping here is a 500 on every page that merely listed
    # versions -- and installing a working library beside it changed nothing,
    # because the listing still walked the broken row.
    assert_raises(ConsoleLibrary::Missing) { @version.library.read("app/main.rb") }
  end

  test "the require list of a library whose bytes are gone raises Missing" do
    lose_the_blobs!(@version)

    assert_raises(ConsoleLibrary::Missing) { @version.library.require_paths }
  end

  test "the size of a file is answered from the row, so it survives a lost blob" do
    # Deliberately not rescued by this change: byte_size was denormalised at
    # install precisely so the manifest can be built without touching storage.
    lose_the_blobs!(@version)

    assert_equal @version.console_library_files.find_by!(path: "app/main.rb").byte_size,
      @version.library.size_of("app/main.rb")
  end

  test "a candidate library is available from what it was handed" do
    # No storage is involved in a candidate, so the blob check must not run --
    # inspect runs it against every upload before a single row exists.
    assert candidate_library("0.1.0").available?
  end

  test "a candidate missing its entry point is not available" do
    entries = console_library_entries("0.1.0").except(ConsoleLibrary::ENTRY_TEMPLATE)

    assert_not ConsoleLibrary.new("0.1.0", entries: entries).available?
  end

  # The content token is what the documentation cache is keyed on, so the only
  # property that matters is that it moves when the bytes do and stays put when
  # they do not.
  test "the content token is the same for two readers of one library" do
    assert_equal @version.library.content_token, @version.reload.library.content_token
  end

  test "the content token moves when the library's files do" do
    before = @version.library.content_token

    # restore! is the only thing that writes files behind an installed version,
    # and it does it by replacing the rows and their blobs, which is what the
    # token is reading.
    ConsoleLibraryInstall.restore!(console_library_entries("0.1.0"), @version.reload)

    refute_equal before, @version.library.content_token
  end

  test "a library whose blobs are gone still has a content token" do
    # The blob is optional here on purpose: an install that cannot be read is
    # still a state with an identity, and asking for the token is how the
    # documentation cache keys that state rather than raising.
    lose_the_blobs!(@version)

    assert_predicate @version.library.content_token, :present?
  end
end
