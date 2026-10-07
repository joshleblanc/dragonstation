# rubyzip is a transitive dependency of activestorage, and Bundler.require only
# requires the gems named in the Gemfile -- not their dependencies. ActiveStorage
# requires zip lazily, deep inside archive analysis, which is a different code
# path from ours. So nothing else loads it: without this line, Zip is defined in
# the test process (the test helper requires it) and undefined everywhere else,
# which is a 500 on the first real upload and a green test suite.
require "zip"

# Turn an uploaded ZIP into a cartridge, or explain why it is not one.
#
# A cart is a directory with a contract: an entry file, code that defines the
# module named after the directory, and every asset it references. A ZIP is
# just a container and knows none of that, so this does three jobs:
#
#   1. refuse the archives that are dangerous rather than malformed --
#      traversal, absolute paths, symlinks, decompression bombs;
#   2. find the single cart inside, and refuse an archive holding several,
#      because a cart has to be one game;
#   3. check the cart owns every asset it names, the way publish-cart does,
#      so a missing sprite is an upload error instead of a blank texture on
#      someone else's page.
#
# The checks are deliberately as strict as publish-cart's. That script learned
# them the hard way, on a build that shipped with an invisible sprite, and the
# failure mode is invisible at every layer above it.
class CartridgeIngest
  class Invalid < StandardError
    attr_reader :problems

    def initialize(problems)
      @problems = Array(problems)
      super(@problems.join("\n"))
    end
  end

  # A cart's own directories. publish-cart greps the source for quoted paths
  # under these roots and refuses to package when one does not resolve inside
  # the cart.
  ASSET_ROOTS = %w[sprites sounds maps data].freeze

  # The same grep publish-cart does, kept deliberately narrow: it wants literal
  # asset paths, not every string in the file. The whole path is captured, not
  # just the directory root -- publish-cart checks each reference individually,
  # so capturing only the root would silently accept every missing asset.
  ASSET_REFERENCE = %r{['"]((?:sprites|sounds|maps|data)/[\w./-]+)['"]}

  # Directories whose presence means a cart is not self-contained. DragonRuby
  # resolves paths against the game root and refuses to stat outside it, so a
  # cart reaching for ../ is broken in a way no upload-time check can fix.
  MAX_FILES = 512
  MAX_TOTAL_BYTES = 32 * 1024 * 1024
  MAX_COMPRESSION_RATIO = 200

  # The console's own diagnostic cart names paths that deliberately do not
  # resolve, because it is the thing testing resolution. publish-cart exempts
  # it by name, and so does this.
  DIAGNOSTIC_CART_NAMES = %w[selftest].freeze

  attr_reader :archive, :user, :console_version, :title

  def initialize(archive:, user:, console_version:, title: nil)
    @archive = archive
    @user = user
    @console_version = console_version
    @title = title
  end

  def call
    entries = read_entries
    cart = locate_cart(entries)

    problems = []
    problems.concat(validate_entry(cart))
    problems.concat(validate_assets(cart)) unless DIAGNOSTIC_CART_NAMES.include?(cart[:name])
    raise Invalid, problems if problems.any?

    build(cart, cart[:entries])
  end

  private
    # name (relative to the cart) => bytes
    def read_entries
      entries = {}

      with_zip do |zip|
        zip.each do |entry|
          next if entry.directory?

          path = safe_path(entry.name)
          raise Invalid, "archive contains a symbolic link: #{entry.name}" if symlink?(entry)

          bytes = entry.get_input_stream { |io| io.read }

          check_budget!(entries, path, entry, bytes)
          entries[path] = bytes
        end
      end

      raise Invalid, "archive is empty" if entries.empty?

      entries
    end

    # The archive reader, behind a method so a test can supply an entry
    # rubyzip will not produce. rubyzip 3.7 always writes ftype :file, even
    # with the symlink bit set, so a symlink archive cannot be built through
    # it -- but archives come from other tools, and the guard below has to
    # hold for those too.
    def with_zip(&block)
      Zip::File.open_buffer(StringIO.new(archive.read), &block)
    rescue Zip::Error => e
      raise Invalid, "could not read the archive: #{e.message}"
    end

    # The one path rule that matters for an archive: nothing may escape the
    # directory it was extracted into. Absolute paths, '..' segments and
    # backslashes are all the same attack wearing different clothes.
    def safe_path(name)
      raise Invalid, "archive contains an absolute path: #{name}" if name.start_with?("/", "\\")

      normalised = name.tr("\\", "/")
      segments = normalised.split("/").reject { |s| s.empty? || s == "." }

      if segments.any? { |s| s == ".." }
        raise Invalid, "archive contains a path that escapes the cart: #{name}"
      end

      if normalised =~ /\0/
        raise Invalid, "archive contains a null byte in a path"
      end

      segments.join("/")
    end

    def symlink?(entry)
      entry.respond_to?(:symlink?) ? entry.symlink? : entry.ftype == :symlink
    rescue NoMethodError
      false
    end

    def check_budget!(entries, path, entry, bytes)
      if entries.size >= MAX_FILES
        raise Invalid, "archive has more than #{MAX_FILES} files"
      end

      compressed = entry.compressed_size.to_i
      if compressed.positive? && bytes.bytesize / compressed > MAX_COMPRESSION_RATIO
        raise Invalid, "#{path} expands #{MAX_COMPRESSION_RATIO}x beyond its compressed size"
      end

      total = entries.values.sum(&:bytesize) + bytes.bytesize
      raise Invalid, "archive expands beyond #{MAX_TOTAL_BYTES / 1024 / 1024}MB" if total > MAX_TOTAL_BYTES
    end

    # Find the one cart directory, whether the archive wraps it or *is* it.
    #
    # Everything downstream works in cart-relative paths ('app/main.rb'), so
    # the wrapping directory is stripped here, once, rather than being carried
    # through validation and storage as a prefix that each step would have to
    # remember to strip.
    def locate_cart(entries)
      candidates = entries.keys.map { |p| p.split("/").first }.uniq
        .select { |top| entries.keys.any? { |p| p.start_with?("#{top}/app/") } }

      if candidates.size > 1
        raise Invalid, "archive contains more than one cart: #{candidates.sort.join(', ')}"
      end

      if candidates.size == 1
        top = candidates.first
        return { name: top, prefix: "#{top}/", entries: strip_prefix(entries, "#{top}/") }
      end

      # The archive is the cart itself: app/main.rb at the root. The cart's
      # name is then the constant its entry file defines, and Console::CartLoader
      # looks it up by directory name, so it is taken from the file.
      if entries.keys.any? { |p| p.start_with?("app/") }
        return { name: nil, prefix: "", entries: entries }
      end

      raise Invalid,
        "no cart found. Expected a directory containing app/main.rb, or an archive of one cart's files."
    end

    # Only what is inside the cart directory, with the directory stripped.
    #
    # A zip of a project folder routinely carries a README or a .gitignore
    # beside the cart. Those are packaging noise: storing them would put files
    # inside the served cart that the game never asked for.
    def strip_prefix(entries, prefix)
      entries
        .select { |path, _| path.start_with?(prefix) }
        .to_h { |path, bytes| [ path.delete_prefix(prefix), bytes ] }
    end

    # The entry file, and the cart's name from it.
    #
    # Order matches the loader and publish-cart: app/main.rb first, then
    # app/<name>.rb.
    def validate_entry(cart)
      files = cart[:entries]
      stem = cart[:name]

      entry_path =
        if files.key?("app/main.rb")
          "app/main.rb"
        elsif stem && files.key?("app/#{stem}.rb")
          "app/#{stem}.rb"
        elsif files.keys.grep(%r{\Aapp/[^/]+\.rb\z}).one?
          files.keys.grep(%r{\Aapp/[^/]+\.rb\z}).first
        end

      if entry_path.nil?
        return [ "#{cart[:name] || 'cart'} has no entry file. " \
                "Expected app/main.rb, or app/<cart name>.rb." ]
      end

      name = stem || constant_from(entry_path)
      if name.blank?
        return [ "#{cart[:name] || 'cart'}: could not work out the cart name from #{entry_path}" ]
      end

      unless name.match?(/\A[a-zA-Z][a-zA-Z0-9_]*\z/)
        return [ "'#{name}' is not a usable cart name. The console looks the cart's class " \
                 "up by directory name, so it has to be a Ruby constant." ]
      end

      cart[:name] = name
      cart[:entry_path] = entry_path
      []
    end

    # The cart's name when the archive is the cart itself, with no directory
    # to take it from.
    #
    # Verbatim from the entry filename, not camelised: Console::CartLoader
    # resolves a cart's class by trying the directory name and then its
    # camelised form, so a cart stored as 'space' finds 'Space' exactly the
    # way the console's own carts/space does. Deriving the constant here
    # instead would store 'Space' and rely on a different branch to match.
    def constant_from(entry_path)
      File.basename(entry_path, ".rb")
    end

    # Every asset the cart's own source names has to be inside the cart.
    #
    # Not a nicety: the served tree contains the cart and nothing else, so a
    # reference that resolves against console-root starter art in a checkout
    # is a file that simply does not exist here. It would load as an invisible
    # sprite and nothing would say so.
    def validate_assets(cart)
      files = cart[:entries]

      referenced = files.each_value.with_object(Set.new) do |bytes, set|
        next if binary?(bytes)
        bytes.scan(ASSET_REFERENCE) { |match| set << match.first }
      end

      missing = referenced.reject { |ref| files.key?(ref) }.sort

      return [] if missing.empty?

      [ "#{cart[:name]} uses assets it does not own:\n" +
        missing.map { |m| "  #{m}\n  move it into the cart directory, or it will not be there" }.join("\n") ]
    end

    # Skip anything with a NUL byte, which is what every real binary asset has
    # and no .rb file has.
    def binary?(bytes)
      bytes.include?("\x00")
    end

    def build(cart, entries)
      cartridge = nil

      Cartridge.transaction do
        cartridge = Cartridge.create!(
          user: user,
          console_version: console_version,
          title: title.presence || console_title(cart) || cart[:name].humanize,
          slug: unique_slug(cart[:name]),
          cart_name: cart[:name],
          entry_path: cart[:entry_path]
        )

        # One filetime for the whole upload. It moves when the cartridge is
        # replaced and never in between, which is what the loader's IndexedDB
        # cache needs: a value that shifted on every request would force a
        # re-download every time without ever telling it anything true.
        filetime = Time.current.to_i

        entries.each do |relative, bytes|
          file = cartridge.cartridge_files.create!(
            path: relative,
            byte_size: bytes.bytesize,
            filetime: filetime
          )
          file.blob.attach(
            io: StringIO.new(bytes.dup.force_encoding(Encoding::BINARY)),
            filename: File.basename(relative),
            content_type: Marcel::MimeType.for(StringIO.new(bytes), name: relative)
          )
        end
      end

      cartridge
    end

    # TITLE, when the cart states one. The same trick --list and publish-cart
    # use, so the listing and the upload can never disagree about a name.
    def console_title(cart)
      bytes = cart[:entries][cart[:entry_path]]
      return nil if bytes.nil?

      bytes[/^TITLE\s*=\s*['"]([^'"]*)['"]\s*$/, 1]
    end

    def unique_slug(seed)
      base = seed.to_s.downcase.gsub(/[^a-z0-9]+/, "-").gsub(/\A-+|-+\z/, "")
      base = "cart" if base.blank?

      slug = base
      n = 1
      while Cartridge.exists?(slug: slug)
        n += 1
        slug = "#{base}-#{n}"
      end
      slug
    end
end
