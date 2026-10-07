require "zip"

# Builds cartridge archives in memory, so a test can describe an upload as a
# hash of paths to bytes and get a real ZIP back.
#
# The point of building real archives rather than stubbing the extractor is
# that most of what CartridgeIngest refuses -- traversal, absolute paths,
# symlinks, expansion bombs -- only exists at that layer.
module CartridgeTestHelper
  # Per-process memo of the console checkout's files. Module-level because it is
  # shared by every test in the process and outlives any one test's transaction.
  def self.console_entries
    @console_entries ||= ConsoleLibraryInstall.directory_entries(console_checkout)
  end

  def self.console_checkout
    path = ENV["CONSOLE_PATH"].presence || Rails.root.join("../dragonruby/console").to_s

    unless File.directory?(path)
      raise "console checkout not found at #{path}. Set CONSOLE_PATH to a console checkout."
    end

    path
  end

  def build_archive(entries)
    buffer = Zip::OutputStream.write_buffer(StringIO.new(+"")) do |zip|
      entries.each do |path, content|
        zip.put_next_entry(path)
        zip.write(content)
      end
    end
    buffer.rewind
    buffer
  end

  # The smallest thing CartridgeIngest will accept: one cart directory, an
  # entry file, a class matching the directory name.
  def space_cart(extra = {})
    named_cart("space", extra)
  end

  # A minimal cart under any name. Separate from space_cart so a test can make
  # a *second* cart in the same process -- merging a different cart's files
  # into space_cart's would be an archive with two carts in it, which is an
  # error for exactly the reason CartridgeIngest refuses one.
  def named_cart(name, extra = {})
    {
      "#{name}/app/#{name}.rb" => <<~RUBY
        TITLE = '#{name}'

        class #{name.capitalize}
          def setup; end
          def update; end
          def render; end
        end
      RUBY
    }.merge(extra)
  end

  # A console every test can build a cartridge against.
  #
  # Installed through ConsoleLibraryInstall rather than created as a bare row.
  # Most of what the suite exercises is *reading* a library -- the manifest, the
  # documentation pages, the release bundle -- and a row with no files behind it
  # would make those assertions pass against nothing. Marked default in the same
  # breath: the app's rule is that a fresh install with no flag set still uploads
  # something, and a test that pinned a version and got a different default would
  # be testing the fixture rather than the code.
  #
  # The real console checkout, so the library under test is the one that ships.
  # CONSOLE_PATH points at it; the sibling checkout is the default because that is
  # where it lives next to this repository.
  def console_version!(version: CONSOLE_VERSION)
    ConsoleVersion.find_by(version: version) ||
      install_real_console_library(version).tap { |installed| installed.update!(default: true) }
  end

  CONSOLE_VERSION = "0.1.0"

  # Where the console checkout is. Tests that need a real library read it from
  # here rather than from a copy in this repository, which is what the storage
  # change removed.
  def console_checkout
    path = ENV["CONSOLE_PATH"].presence || Rails.root.join("../dragonruby/console").to_s

    unless File.directory?(path)
      raise "console checkout not found at #{path}. Set CONSOLE_PATH to a console checkout."
    end

    path
  end

  # Install the real library, straight from the checkout, through the same
  # ConsoleLibraryInstall the rake task and the upload screen use.
  def install_real_console_library(version = CONSOLE_VERSION)
    ConsoleLibraryInstall.install!(real_console_entries, title: "Console #{version}")
  end

  # The checkout's files, read once per process.
  #
  # The suite installs this library in hundreds of tests, and the tree includes
  # font.ttf at 3.4MB -- reading it per test turns a fast suite into a slow one
  # for no gain. The install itself still happens per test, because that is what
  # the tests are about; only the read is shared.
  def real_console_entries = CartridgeTestHelper.console_entries

  def console_checkout = CartridgeTestHelper.console_checkout

  # Uploads get whatever the default is, the same way the controller picks it.
  def ingest(entries, user:, console_version: nil, title: nil)
    CartridgeIngest.new(
      archive: build_archive(entries),
      user: user,
      console_version: console_version || ConsoleVersion.default,
      title: title
    ).call
  end

  def assert_rejected(entries, matching, user: users(:one), console_version: nil)
    error = assert_raises(CartridgeIngest::Invalid) do
      ingest(entries, user: user, console_version: console_version || console_version!)
    end
    assert_match matching, error.message
    error
  end

  # The bytes the runtime would serve for one path of a cartridge's manifest.
  def served_bytes(cartridge, path)
    file = cartridge.stager.resolve(path)

    case file.source
    when :generated      then cartridge.stager.entry_source
    when :library        then cartridge.console_version.library.read(path)
    when :metadata       then cartridge.stager.metadata.public_send(
      path == ConsoleMetadata::PATH ? :content : :icon
    )
    when :cartridge_file
      cartridge.cartridge_files
        .find_by!(path: path.delete_prefix("#{cartridge.cart_prefix}/"))
        .blob.download
    end
  end
end

ActiveSupport::TestCase.include CartridgeTestHelper
