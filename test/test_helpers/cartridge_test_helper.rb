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

  # A console every test can build a cartridge against: the real checkout,
  # installed through ConsoleLibraryInstall (a bare row would make every read
  # assertion pass against nothing) and marked default. Keyed on the version the
  # checkout declares, so nothing here needs bumping when the console ships.
  def console_version!(version: CartridgeTestHelper.real_console_version)
    ConsoleVersion.find_by(version: version) ||
      install_real_console_library(version).tap { |installed| installed.update!(default: true) }
  end

  # Memoised per process, because it reads the whole tree to get one number.
  def self.real_console_version
    @real_console_version ||= ConsoleLibraryInstall.check!(console_entries)
  end

  def install_real_console_library(version = CartridgeTestHelper.real_console_version)
    ConsoleLibraryInstall.install!(real_console_entries, title: "Console #{version}")
  end

  # Read once per process (font.ttf alone is 3.4MB); installed per test.
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

  def served_bytes(cartridge, path) = cartridge.stager.read(path)
end

ActiveSupport::TestCase.include CartridgeTestHelper
