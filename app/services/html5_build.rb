# The DragonRuby HTML5 build, and the one part of it that is per-game.
#
# public/dragonruby/ holds the build exactly as DragonRuby produced it. Almost
# all of it is game-independent: the shell, the wasm module, its worker, the
# stylesheet, and the COOP/COEP shim.
#
# The exception is the loader's header, seven GDragonRuby* variables that
# dragonruby-publish writes per game. Everything after them is generic -- the
# loader still fetches manifest.json and gamedata/ at runtime -- which is why
# this app can serve a cartridge it built no bundle for.
#
# So the header is rewritten per cartridge and the vendored loader is left
# byte-identical to what DragonRuby shipped, which is what makes it checkable
# against a real build:
#
#   diff <(tail -n +8 public/dragonruby/dragonruby-html5-loader.js) \
#        <(tail -n +8 builds/arcade-html5-1.0/dragonruby-html5-loader.js)
class Html5Build
  class Missing < StandardError; end

  ROOT = Rails.public_path.join("dragonruby")

  LOADER = "dragonruby-html5-loader.js"
  GENERATED_LOADER = LOADER

  # The header dragonruby-publish writes, and everything after it is shared.
  # Matched rather than assumed: the block is "one or more `var GDragonRuby*`"
  # at the very top of the file.
  HEADER_PATTERN = /\A(?:var GDragonRuby[A-Za-z]+ = .*\n)+/

  STATIC_FILES = %w[
    index.html
    game.css
    favicon.png
    dragonruby-wasm.js
    dragonruby-wasm.wasm
    dragonruby-wasm.worker.js
    dragonruby-serviceworker.js
  ].freeze

  # Files this build is expected to contain. Checked rather than assumed,
  # because a partial vendor copy fails as a blank canvas with no error.
  REQUIRED = %w[index.html dragonruby-html5-loader.js dragonruby-wasm.js dragonruby-wasm.wasm].freeze

  attr_reader :cartridge

  def self.available?
    REQUIRED.all? { |f| ROOT.join(f).file? }
  end

  def initialize(cartridge)
    @cartridge = cartridge
  end

  # The loader this cartridge is served.
  #
  # The file is served rather than written, so there is no artifact to go stale
  # between the manifest and the loader -- the two are generated from the same
  # cartridge at the same moment.
  def loader
    @loader ||= begin
      source = template
      replaced = source.sub(HEADER_PATTERN, header)

      if replaced == source
        raise Missing,
          "dragonruby-html5-loader.js does not start with a GDragonRuby header block, " \
          "so the per-game values cannot be written. Was the build replaced?"
      end

      replaced
    end
  end

  def metadata = cartridge.stager.metadata

  private
    def template
      @template ||= begin
        path = ROOT.join(LOADER)

        raise Missing, "no HTML5 build at #{path} -- see the README" unless path.file?

        path.read
      end
    end

    def header
      values = {
        "GDragonRubyGameId" => cartridge.cart_name,
        "GDragonRubyGameTitle" => cartridge.title,
        "GDragonRubyDevTitle" => metadata_value("devtitle", "Dragonstation"),
        "GDragonRubyGameVersion" => metadata_value("version", "1.0"),
        "GDragonRubyIcon" => "/#{ConsoleMetadata::ICON_PATH}",
        # Per-game save directory. Matches what the engine writes, so two
        # cartridges cannot read each other's saves out of IndexedDB.
        "GDragonRubyWriteDir" => "/dragonruby-#{cartridge.cart_name}",
        "GDragonRubyOrientation" => metadata_value("orientation", "landscape")
      }

      values.map { |name, value| "var #{name} = #{javascript_string(value)};" }.join("\n") + "\n"
    end

    def metadata_value(key, fallback)
      line = metadata.content.lines.find { |l| l.start_with?("#{key}=") }
      value = line&.split("=", 2)&.last&.strip
      value.presence || fallback
    end

    # A cartridge's title is user-supplied and lands in a generated JavaScript
    # file. A quote or a backslash or a newline in there would break out of the
    # string literal, so anything outside a plain quote is escaped rather than
    # trusted. JSON is the encoder that already knows how.
    def javascript_string(value)
      value.to_json
    end
end
