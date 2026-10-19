# The vendored DragonRuby HTML5 build, and the one per-game part of it.
#
# public/dragonruby/ is the build exactly as DragonRuby shipped it, except the
# loader's header: seven GDragonRuby* variables dragonruby-publish writes per
# game. Everything after them is generic (the loader fetches manifest.json and
# gamedata/ at runtime), so the header is rewritten per cartridge and the rest
# stays byte-identical and checkable against a real build:
#
#   diff <(tail -n +8 public/dragonruby/dragonruby-html5-loader.js) \
#        <(tail -n +8 builds/arcade-html5-1.0/dragonruby-html5-loader.js)
class Html5Build
  class Missing < StandardError; end

  ROOT = Rails.public_path.join("dragonruby")

  LOADER = "dragonruby-html5-loader.js"

  HEADER_PATTERN = /\A(?:var GDragonRuby[A-Za-z]+ = .*\n)+/

  # Served as-is. An allowlist, because the route takes a filename from the URL.
  STATIC_FILES = %w[
    index.html
    game.css
    favicon.png
    dragonruby-wasm.js
    dragonruby-wasm.wasm
    dragonruby-wasm.worker.js
    dragonruby-serviceworker.js
  ].freeze

  # A partial vendor copy fails as a blank canvas with no error, so check.
  REQUIRED = %w[index.html dragonruby-html5-loader.js dragonruby-wasm.js dragonruby-wasm.wasm].freeze

  def self.available? = REQUIRED.all? { |f| ROOT.join(f).file? }

  attr_reader :cartridge

  def initialize(cartridge)
    @cartridge = cartridge
  end

  def loader
    @loader ||= begin
      replaced = template.sub(HEADER_PATTERN, header)
      if replaced == template
        raise Missing, "#{LOADER} does not start with a GDragonRuby header block, " \
                       "so the per-game values cannot be written. Was the build replaced?"
      end

      replaced
    end
  end

  private
    def template
      @template ||= begin
        path = ROOT.join(LOADER)
        raise Missing, "no HTML5 build at #{path} -- see the README" unless path.file?

        path.read
      end
    end

    def header
      metadata = cartridge.stager.metadata

      {
        "GDragonRubyGameId" => cartridge.cart_name,
        "GDragonRubyGameTitle" => cartridge.title,
        "GDragonRubyDevTitle" => metadata["devtitle"].presence || "Dragonstation",
        "GDragonRubyGameVersion" => metadata["version"].presence || "1.0",
        "GDragonRubyIcon" => "/#{ConsoleMetadata::ICON_PATH}",
        # Per-game save directory, so cartridges cannot read each other's saves.
        "GDragonRubyWriteDir" => "/dragonruby-#{cartridge.cart_name}",
        "GDragonRubyOrientation" => metadata["orientation"].presence || "landscape"
      }.map { |name, value| "var #{name} = #{value.to_json};\n" }.join # to_json: titles are user input
    end
end
