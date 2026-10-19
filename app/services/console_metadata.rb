# metadata/game_metadata.txt and metadata/icon.png, which DragonRuby reads from
# the game root -- so, like publish-cart, they are generated per cartridge.
# Not decoration: the HTML5 build reads the icon to draw the click-to-play
# overlay, and without it the game sits on a canvas that can never start.
#
# publish-cart's rules, learned the hard way:
#
#   * start from the cart's own file if it ships one, else the console's;
#   * rewrite only gameid and gametitle -- every later key (hd, highdpi,
#     orientation, ...) is real engine behaviour and must survive;
#   * the first six keys are positional, so a file missing one is refused
#     rather than served with every later value shifted across.
class ConsoleMetadata
  class Invalid < StandardError; end

  PATH = "metadata/game_metadata.txt"
  ICON_PATH = "metadata/icon.png"

  REQUIRED_KEYS = %w[devid devtitle gameid gametitle version icon].freeze

  attr_reader :cartridge, :library

  def initialize(cartridge:, library:)
    @cartridge = cartridge
    @library = library
  end

  def content
    @content ||= begin
      lines = source_lines.dup

      # A cart's own file states its own identity; only blanks are filled in.
      own = cart_file(PATH).present?
      { "gameid" => cartridge.cart_name, "gametitle" => cartridge.title }.each do |key, value|
        lines = put(lines, key, value) unless own && value_in(lines, key).present?
      end

      # Presence, not value: a blank gametitle= is fine, a missing line is not.
      missing = REQUIRED_KEYS.reject { |key| lines.any? { |l| l.start_with?("#{key}=") } }
      raise Invalid, "metadata is missing required keys: #{missing.join(' ')}" if missing.any?

      lines.join("\n").b
    end
  end

  # One value from the served metadata, or nil.
  def [](key) = value_in(content.split("\n"), key)

  # The cart's own icon wins, as in publish-cart.
  def icon
    @icon ||= (cart_file(ICON_PATH) || library.read(value_in(source_lines, "icon").presence || ICON_PATH)).b
  end

  private
    def cart_file(path)
      @cart_files ||= {}
      return @cart_files[path] if @cart_files.key?(path)

      @cart_files[path] = cartridge.cartridge_files.find_by(path: path)&.blob&.download
    end

    def source_lines
      @source_lines ||= (cart_file(PATH) || library.read(PATH)).split("\n", -1).tap { |l| l.pop if l.last == "" }
    end

    def value_in(lines, key)
      lines.find { |l| l.start_with?("#{key}=") }&.split("=", 2)&.last&.strip
    end

    # A missing key is left missing, for the required-keys check to refuse.
    def put(lines, key, value)
      lines.map { |line| line.start_with?("#{key}=") ? "#{key}=#{value}" : line }
    end
end
