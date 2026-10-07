require "zip"

# Builds cartridge archives in memory, so a test can describe an upload as a
# hash of paths to bytes and get a real ZIP back.
#
# The point of building real archives rather than stubbing the extractor is
# that most of what CartridgeIngest refuses -- traversal, absolute paths,
# symlinks, expansion bombs -- only exists at that layer.
module CartridgeTestHelper
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

  def console_version!(version: "0.1.0")
    ConsoleVersion.find_or_create_by!(version: version) do |record|
      record.title = "Console #{version}"
      record.default = true
    end
  end

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
