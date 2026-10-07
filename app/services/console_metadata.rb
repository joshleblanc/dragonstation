# The game metadata a cartridge is served with, and its icon.
#
# DragonRuby reads metadata/game_metadata.txt from the GAME ROOT -- the path is
# hardcoded in the engine, which is exactly why a cart can never cause the engine
# to read its own copy. console/publish-cart solves this by generating the file
# per cart at the root of the staging directory, and the served tree needs the
# same two files for the same reason:
#
#   the HTML5 build calls FS.readFile('/metadata/icon.png') to draw the
#   click-to-play overlay. If that path is not in the manifest, the read throws
#   inside startClickToPlay, the overlay never appears, and the game sits on an
#   empty canvas waiting for a click that can never come.
#
# So this is not decoration. Two of these files are load-bearing for the game
# starting at all.
#
# The rewriting rules are publish-cart's, because they were learned the hard way:
#
#   * start from the console's file, or from the cart's own when it ships one;
#   * rewrite only gameid and gametitle, never write a fresh six-line file;
#   * the first six lines are positional, and every key after them -- hd,
#     highdpi, orientation, aspect_mode, sprites_directory -- is read by name
#     and decides real engine behaviour.
#
# Writing a fresh six-line file drops the rest, and the build quietly stops
# matching the checkout it was tested against.
class ConsoleMetadata
  class Invalid < StandardError; end

  PATH = "metadata/game_metadata.txt"
  ICON_PATH = "metadata/icon.png"

  # Positional. A file missing one shifts every value after it across, so it is
  # refused rather than served scrambled.
  REQUIRED_KEYS = %w[devid devtitle gameid gametitle version icon].freeze

  # Rewritten per cartridge, because they are the cartridge's identity.
  IDENTITY_KEYS = %w[gameid gametitle].freeze

  attr_reader :cartridge, :library

  def initialize(cartridge:, library:)
    @cartridge = cartridge
    @library = library
  end

  # The metadata file's bytes.
  def content
    @content ||= begin
      lines = source_lines.dup

      # A cart's own metadata states its own identity, so it is only filled in
      # where the cart left it blank rather than overruled. Done before the
      # check below, because a blank value is still a present key.
      if cart_own_metadata?
        lines = put(lines, "gameid", cartridge.cart_name) if value_of(lines, "gameid").blank?
        lines = put(lines, "gametitle", cartridge.title) if value_of(lines, "gametitle").blank?
      else
        lines = put(lines, "gameid", cartridge.cart_name)
        lines = put(lines, "gametitle", cartridge.title)
      end

      # Presence, not value: publish-cart checks that the line exists, which is
      # what "positional" means for the first six. A cart that ships
      # gametitle= with nothing after it is stating its identity blank for us to
      # fill; a file missing the line entirely would shift every later value
      # across, and is refused.
      missing = REQUIRED_KEYS.reject { |key| key?(lines, key) }

      unless missing.empty?
        raise Invalid, "metadata is missing required keys: #{missing.join(' ')}"
      end

      lines.join("\n").dup.force_encoding(Encoding::BINARY)
    end
  end

  # The icon's bytes.
  #
  # A cart's own icon wins, exactly as it does in publish-cart, which is how
  # each cart ends up with its own icon rather than the console's.
  def icon
    @icon ||= begin
      bytes = cart_own_file(ICON_PATH)

      if bytes
        bytes.dup.force_encoding(Encoding::BINARY)
      else
        declared = value_of(source_lines, "icon")
        library.read(declared.presence || ICON_PATH).dup.force_encoding(Encoding::BINARY)
      end
    end
  end

  private
    def cart_own_metadata? = cart_own_file(PATH).present?

    def cart_own_file(path)
      file = cartridge.cartridge_files.find_by(path: path)
      file&.blob&.download
    end

    def source_lines
      @source_lines ||= begin
        bytes = cart_own_file(PATH) || library.read(PATH)
        bytes.split("\n", -1).tap { |l| l.pop if l.last == "" }
      end
    end

    def key?(lines, key)
      lines.any? { |l| l.start_with?("#{key}=") }
    end

    def value_of(lines, key)
      line = lines.find { |l| l.start_with?("#{key}=") }
      line && line.split("=", 2).last.to_s.strip
    end

    def put(lines, key, value)
      replaced = false

      lines.map do |line|
        if line.start_with?("#{key}=")
          replaced = true
          "#{key}=#{value}"
        else
          line
        end
      end.tap do
        # Only ever appended when the key was absent, which the validation
        # above already refuses. Defensive rather than reachable.
        lines << "#{key}=#{value}" unless replaced
      end
    end
end
