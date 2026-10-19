# Turn an uploaded ZIP into a cartridge, or explain why it is not one.
#
# A cart is a directory with a contract: an entry file, a class named after the
# directory, and every asset it references. The checks are as strict as the
# console's publish-cart, which learned them from a build that shipped with an
# invisible sprite: a missing asset must be an upload error, not a blank texture
# on someone else's page.
class CartridgeIngest
  include SafeArchive

  class Invalid < SafeArchive::Rejected; end

  # The same grep publish-cart does: literal paths under a cart's own asset
  # directories. The whole path is captured so each reference is checked.
  ASSET_REFERENCE = %r{['"]((?:sprites|sounds|maps|data)/[\w./-]+)['"]}

  # The console's self-test cart names unresolvable paths on purpose;
  # publish-cart exempts it by name, and so does this.
  DIAGNOSTIC_CART_NAMES = %w[selftest].freeze

  CONSTANT_NAME = /\A[a-zA-Z][a-zA-Z0-9_]*\z/

  attr_reader :archive, :user, :console_version, :title

  def initialize(archive:, user:, console_version:, title: nil)
    @archive = archive
    @user = user
    @console_version = console_version
    @title = title
  end

  def call
    directory, files = unwrap(read_entries)

    entry_path = entry_path_for(files, directory)
    raise Invalid, "#{directory || 'cart'} has no entry file. Expected app/main.rb, or app/<cart name>.rb." unless entry_path

    # With no wrapping directory the cart's name comes from its entry file,
    # verbatim: Console::CartLoader tries the name and then its camelised form.
    name = directory || File.basename(entry_path, ".rb")
    unless name.match?(CONSTANT_NAME)
      raise Invalid, "'#{name}' is not a usable cart name. The console looks the cart's class " \
                     "up by directory name, so it has to be a Ruby constant."
    end

    problems = DIAGNOSTIC_CART_NAMES.include?(name) ? [] : asset_problems(name, files)
    raise Invalid, problems if problems.any?

    build(name, entry_path, files)
  end

  private
    def archive_subject = "cart"

    # Same order as the loader and publish-cart.
    def entry_path_for(files, directory)
      return "app/main.rb" if files.key?("app/main.rb")
      return "app/#{directory}.rb" if directory && files.key?("app/#{directory}.rb")

      top_level = files.keys.grep(%r{\Aapp/[^/]+\.rb\z})
      top_level.first if top_level.one?
    end

    # The served tree holds the cart and nothing else, so an asset outside it
    # would load as an invisible sprite with no error anywhere.
    def asset_problems(name, files)
      missing = files.each_value.with_object(Set.new) { |bytes, refs|
        # A NUL byte marks a binary asset; no source file has one.
        bytes.scan(ASSET_REFERENCE) { |(ref)| refs << ref } unless bytes.include?("\x00")
      }.reject { |ref| files.key?(ref) }.sort

      return [] if missing.empty?

      [ "#{name} uses assets it does not own:\n" +
        missing.map { |m| "  #{m}\n  move it into the cart directory, or it will not be there" }.join("\n") ]
    end

    def build(name, entry_path, files)
      Cartridge.transaction do
        cartridge = Cartridge.create!(
          user: user,
          console_version: console_version,
          title: title.presence || declared_title(files[entry_path]) || name.humanize,
          slug: unique_slug(name),
          cart_name: name,
          entry_path: entry_path
        )

        # One filetime per upload: the loader's IndexedDB cache re-downloads
        # when it moves, so it must move on replacement and never in between.
        filetime = Time.current.to_i

        files.each do |path, bytes|
          file = cartridge.cartridge_files.create!(path: path, byte_size: bytes.bytesize, filetime: filetime)
          file.blob.attach(
            io: StringIO.new(bytes.b),
            filename: File.basename(path),
            content_type: Marcel::MimeType.for(StringIO.new(bytes), name: path)
          )
        end

        cartridge
      end
    end

    # TITLE = '...' in the entry file, as --list and publish-cart read it.
    def declared_title(source)
      source&.[](/^TITLE\s*=\s*['"]([^'"]*)['"]\s*$/, 1)
    end

    def unique_slug(seed)
      base = seed.downcase.gsub(/[^a-z0-9]+/, "-").gsub(/\A-+|-+\z/, "").presence || "cart"

      slug = base
      n = 1
      slug = "#{base}-#{n += 1}" while Cartridge.exists?(slug: slug)
      slug
    end
end
