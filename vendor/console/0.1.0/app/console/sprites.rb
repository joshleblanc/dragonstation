# Console::Sprites -- name -> texture resolution, plus procedural generation.
#
# Two jobs:
#
# 1. RESOLUTION. Carts refer to sprites by short name (`:star`,
#    `:'misc/star'`) instead of by path. The index is built once at boot by
#    walking the sprites tree of the booted cart, then the console's own
#    (DR.list_files is not recursive). The cart's files win, so two carts can
#    both have a `sprites/hero.png` without colliding.
#
# 2. ZERO-ART PROTOTYPING. `auto` will synthesise a placeholder texture for any
#    name that has no file, so a cart can be written and played before any art
#    exists. Generated textures are deterministic, so they double as test
#    fixtures.
module Console
  module Sprites
    extend self

    # The logical directory art lives in. Every path built from it goes through
    # Console::Assets, so it is a name and not a location.
    ROOT = Assets::SPRITES_DIR

    class << self
      attr_reader :registry, :generated, :missing
    end

    @registry = {}
    @generated = {}
    @missing = []
    @indexed = false

    # --- indexing ---------------------------------------------------------

    # Build the name -> path index. Cheap enough to call once at boot.
    #
    # The cart's own tree is walked first, so a cart's `hero.png` shadows the
    # console's; the console root is then walked as starter art. `||=` in walk
    # is what makes "first one wins" true.
    def index!
      @registry = {}
      @indexed = false
      walk "#{Assets.root}/#{ROOT}", '' if Assets.scoped?
      walk ROOT, ''
      @indexed = true
      self
    end

    def indexed?
      @indexed
    end

    def walk(dir, prefix)
      return unless DR.stat_file(dir)
      DR.list_files(dir).each do |entry|
        full = "#{dir}/#{entry}"
        key = prefix.empty? ? entry : "#{prefix}/#{entry}"
        info = DR.stat_file full
        next unless info
        if info[:file_type] == :directory
          walk full, key
        else
          base = key
          ext = base.split('.').last
          stem = base[0, base.length - ext.length - 1]
          # Register the extension-less key, preferring the shallowest match.
          @registry[stem] ||= full
          @registry[key] ||= full
        end
      end
    end

    # Register an explicit alias. Use this for names that should be short.
    # A path is resolved against the booted cart, so `register :ship,
    # 'sprites/hero/idle/0.png'` inside a cart means that cart's file.
    def register(name, path)
      @registry[name.to_s] = Assets.resolve path
    end

    # --- resolution -------------------------------------------------------

    # Resolve a sprite reference to something renderable.
    #
    # Order: explicit registry -> index (with and without extension) ->
    # already-generated procedural texture -> a visible warning + :solid.
    def path(name)
      # Already-generated textures are addressed by symbol.
      return name if name.is_a?(Symbol) && generated?(name)

      key = name.to_s
      hit = @registry[key]
      hit ||= @registry[Console::Str.chop(key, '.png')]
      if hit
        # It resolved after all: stop reporting it as missing, or the warning
        # would outlive the problem.
        @missing.delete key
        return hit
      end
      return key.to_sym if @generated[key]

      # A string that already looks like a real asset path is resolved against the
      # cart, so `draw_sprite('sprites/blue.png')` finds the cart's own copy
      # even if the index has not been built.
      return Assets.resolve key if key.include? '/'

      note_missing key
      :solid
    end

    def note_missing(key)
      @missing << key unless @missing.include?(key)
    end

    def missing_names
      @missing.dup
    end

    def exists?(name)
      key = name.to_s
      return true if @registry[key] || @generated[key]
      false
    end

    def generated?(name)
      @generated.key?(name.to_s) || @generated.key?(name)
    end

    # Natural [w, h] of a sprite reference.
    #
    # get_sprite_rect only understands file paths, so generated textures are
    # measured from the pixel array itself.
    def size(name, args = nil)
      p = path(name)
      if p.is_a?(Symbol) && generated?(p)
        pa = (args || $args).pixel_array(p)
        return [pa.width, pa.height]
      end
      begin
        rect = DR.get_sprite_rect p
        [rect.w, rect.h]
      rescue
        [0, 0]
      end
    end

    # --- animation groups -------------------------------------------------

    # Collect a numbered directory of frames into an ordered Array of paths.
    #
    # `sprites/hero/run/0.png .. 3.png` -> frames('hero/run')
    #
    # Falls back to a single frame holding the base sprite. The directory is
    # resolved like every other asset, so this reads the booted cart's frames.
    def frames(group)
      dir = Assets.resolve "#{ROOT}/#{group}"
      return [] unless DR.stat_file(dir)
      entries = DR.list_files(dir)
      pngs = []
      entries.each do |e|
        full = "#{dir}/#{e}"
        info = DR.stat_file full
        next unless info
        next unless info[:file_type] == :regular
        next unless e.end_with?('.png')
        pngs << [numeric_prefix(e), full]
      end
      return [] if pngs.size == 0
      pngs.sort_by { |n, _| n }.map { |_, p| p }
    end

    def animation?(group)
      frames(group).size > 1
    end

    # True if every entry in `name` looks like an indexed frame.
    def numeric_prefix(filename)
      stem = filename.split('.').first
      num = stem.split('-').last.to_i
      Console::Str.digits?(stem) ? num : 9999
    end

    # --- procedural generation -------------------------------------------

    # Create (or fetch) a procedural texture. `auto` is the forgiving version:
    # it never overwrites a real file on disk.
    def auto(args, name, w = 16, h = 16, color = :accent, pattern = :solid)
      key = name.to_s
      return key.to_sym if @generated[key]
      return @registry[key] if @registry[key]
      generate args, key, w, h, color, pattern
      key.to_sym
    end

    # Force-generate a texture, even if a file exists.
    def generate(args, name, w, h, color = :accent, pattern = :solid)
      key = name.to_s
      pa = args.pixel_array(key.to_sym)
      pa.width = w
      pa.height = h
      rgb = Palette.to_a(color)
      case pattern
      when :solid
        pa.pixels.fill(rgba(rgb), 0, w * h)
      when :checker
        checker args, key, w, h, rgb
      when :stripes
        stripes args, key, w, h, rgb
      when :frame
        frame_pixels args, key, w, h, rgb
      when :circle
        circle args, key, w, h, rgb
      when :ring
        ring args, key, w, h, rgb
      else
        pa.pixels.fill(rgba(rgb), 0, w * h)
      end
      @generated[key] = true
      @registry[key] = key.to_sym
      key.to_sym
    end

    # 8-bit helpers -------------------------------------------------------

    def rgba(rgb, a = 255)
      (a << 24) | ((rgb[2] & 255) << 16) | ((rgb[1] & 255) << 8) | (rgb[0] & 255)
    end

    # Pixel arrays index from the top-left, while the console talks in
    # bottom-left screen coordinates. These helpers take bottom-left coords.
    def put(args, key, x, y, value)
      pa = args.pixel_array(key.to_sym)
      return if x < 0 || y < 0 || x >= pa.width || y >= pa.height
      row = pa.height - y - 1
      pa.pixels[(row * pa.width) + x] = value
    end

    # NOTE: Numeric#zmod? is a boolean divisibility predicate
    # ("is this evenly divisible?"), NOT a modulo. Use % for modulo maths.
    def checker(args, key, w, h, rgb)
      pa = args.pixel_array(key.to_sym)
      dim = rgba([(rgb[0] / 2).to_i, (rgb[1] / 2).to_i, (rgb[2] / 2).to_i])
      h.times do |y|
        w.times do |x|
          put args, key, x, y, (((x + y) % 2) == 0 ? rgba(rgb) : dim)
        end
      end
      pa
    end

    def stripes(args, key, w, h, rgb)
      dim = rgba([(rgb[0] / 2).to_i, (rgb[1] / 2).to_i, (rgb[2] / 2).to_i])
      h.times do |y|
        w.times do |x|
          put args, key, x, y, ((y % 4) < 2 ? rgba(rgb) : dim)
        end
      end
    end

    def frame_pixels(args, key, w, h, rgb)
      inner = rgba([(rgb[0] / 3).to_i, (rgb[1] / 3).to_i, (rgb[2] / 3).to_i])
      h.times do |y|
        w.times do |x|
          edge = x < 1 || y < 1 || x >= w - 1 || y >= h - 1
          put args, key, x, y, (edge ? rgba(rgb) : inner)
        end
      end
    end

    def circle(args, key, w, h, rgb)
      cx = (w - 1) / 2.0
      cy = (h - 1) / 2.0
      rad = [cx, cy].min
      h.times do |y|
        w.times do |x|
          dx = x - cx
          dy = y - cy
          inside = ((dx * dx) + (dy * dy)) <= (rad * rad)
          put args, key, x, y, (inside ? rgba(rgb) : 0x00000000)
        end
      end
    end

    def ring(args, key, w, h, rgb)
      cx = (w - 1) / 2.0
      cy = (h - 1) / 2.0
      rad = [cx, cy].min
      inner = rad - 2
      h.times do |y|
        w.times do |x|
          dx = x - cx
          dy = y - cy
          d = (dx * dx) + (dy * dy)
          edge = d <= (rad * rad) && d >= (inner * inner)
          put args, key, x, y, (edge ? rgba(rgb) : 0x00000000)
        end
      end
    end
  end
end