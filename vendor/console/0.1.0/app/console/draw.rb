# Console::Draw -- the rendering helper layer.
#
# Thin, predictable sugar over args.outputs. Every method returns the rect it
# drew (or the measured text rect), so calls can be chained or fed into
# hit-testing without recomputing geometry.
#
# Every method accepts either absolute pixel coordinates (`x:`, `y:`) or a
# fractional `place:` spec relative to the current bounds rect. Bounds are set
# with `within`, which restores itself afterwards.
#
#   draw.within(panel_rect) do
#     draw.text 'READY', place: { x: 0.0, y: 1.0, anchor_y: 1.0 }
#     draw.panel place: { x: 0.5, y: 0.5, w: 200, h: 40,
#                         anchor_x: 0.5, anchor_y: 0.5 }
#   end
module Console
  class Draw
    attr_reader :args
    attr_accessor :camera

    def initialize(args)
      @args = args
      @bounds_stack = []
      @camera = nil
    end

    def outputs
      @args.outputs
    end

    # --- bounds management -----------------------------------------------

    def bounds
      @bounds_stack.size > 0 ? @bounds_stack.last : default_bounds
    end

    def default_bounds
      grid = @args.grid
      { x: 0, y: 0, w: grid.w, h: grid.h }
    end

    # Evaluate the block with `r` as the current bounds. Restores the previous
    # bounds even if the block raises, so a cart bug cannot corrupt later draws.
    def within(r)
      @bounds_stack.push r
      begin
        yield self
      ensure
        @bounds_stack.pop
      end
    end

    # Resolve a position spec into a concrete rect.
    #
    # Two coordinate systems, chosen by the presence of `place:`:
    #
    #   draw.rect x: 10, y: 20, w: 30, h: 40
    #     -> absolute screen pixels (the common case)
    #
    #   draw.rect place: { x: 0.5, y: 0.5, w: 30, h: 40,
    #                      anchor_x: 0.5, anchor_y: 0.5 }
    #     -> fractions of the current bounds rect
    #
    # Keeping these distinct is deliberate: an absolute x of 10 must never be
    # reinterpreted as "10 times the bounds width".
    def resolve(spec)
      spec ||= {}
      if spec[:place]
        inner = spec[:place]
        base = bounds
        # Inside `place:`, x/y/w/h are all FRACTIONS of the bounds rect:
        #
        #   draw.rect place: { x: 0.5, y: 0.5, w: 0.25, h: 0.1,
        #                      anchor_x: 0.5, anchor_y: 0.5 }
        #
        # A top-level w:/h: overrides with ABSOLUTE pixels, which is what
        # sprites and text need:
        #
        #   draw.sprite place: { x: 0.5, y: 0.5, anchor_x: 0.5,
        #                       anchor_y: 0.5 }, w: 32, h: 32
        w = inner[:w].nil? ? spec[:w] : base[:w] * inner[:w]
        h = inner[:h].nil? ? spec[:h] : base[:h] * inner[:h]
        if spec[:fill]
          w = base[:w] if w.nil?
          h = base[:h] if h.nil?
        end
        Geom.place(base,
                   x: inner[:x] || 0.0,
                   y: inner[:y] || 0.0,
                   w: w || 0, h: h || 0,
                   anchor_x: inner[:anchor_x] || 0.0,
                   anchor_y: inner[:anchor_y] || 0.0)
      else
        # `top:` anchors to the top of the screen, which is how UI is normally
        # specified; `y:` stays bottom-left, which is how worlds are.
        if spec[:top]
          Geom.anchored_top spec[:x] || 0.0, spec[:top],
                            spec[:w] || 0, spec[:h] || 0, @args.grid
        else
          { x: spec[:x] || 0.0,
            y: spec[:y] || 0.0,
            w: spec[:w] || 0,
            h: spec[:h] || 0 }
        end
      end
    end

    # Map world coordinates to screen when a camera is active. Without a
    # camera this is a no-op, so screen-space and world-space drawing share
    # one code path.
    #
    # NOTE: camera zoom scales rect geometry but not font size. Labels keep
    # their pixel size so HUD text stays legible at any zoom.
    def transform(r)
      return r unless @camera && @camera.active?
      off = @camera.current_offset
      zoom = @camera.zoom
      return r if zoom == 1.0 && off[:x] == 0 && off[:y] == 0
      cx = @args.grid.w / 2.0
      cy = @args.grid.h / 2.0
      { x: ((r[:x] - off[:x]) * zoom) + (cx * (1.0 - zoom)),
        y: ((r[:y] - off[:y]) * zoom) + (cy * (1.0 - zoom)),
        w: r[:w] * zoom,
        h: r[:h] * zoom }
    end

    # --- primitives ------------------------------------------------------

    # A filled rectangle.
    #
    # DragonRuby 7.21 deprecates `outputs.solids` in favour of a sprite whose
    # path is :solid, so that is what we emit -- same pixels, one collection,
    # and solids share the sprite pipeline's texture caching.
    def rect(spec = {})
      color = spec[:color] || :white
      alpha = spec[:alpha]
      r = resolve strip_color(spec)
      outputs.sprites << r.merge(Palette.to_hash(color, alpha)).merge(path: :solid)
      r
    end

    # An unfilled rectangle, drawn `thickness` times inset.
    def border(spec = {}, thickness = 1)
      color = spec[:color] || Style.get(:border)
      alpha = spec[:alpha]
      r = resolve strip_color(spec)
      thickness.times do |i|
        outputs.borders << { x: r[:x] + i,
                             y: r[:y] + i,
                             w: r[:w] - (i * 2),
                             h: r[:h] - (i * 2) }.merge(Palette.to_hash(color, alpha))
      end
      r
    end

    # A panel: filled background plus a 1px border.
    def panel(spec = {})
      color = spec[:color] || Style.get(:panel)
      alpha = spec[:alpha]
      border_color = spec[:border_color]
      r = resolve spec
      rect(absolute(r).merge(color: color, alpha: alpha))
      border(absolute(r).merge(color: border_color || Style.get(:border)))
      r
    end

    # Draw a sprite. If w/h are omitted the texture's natural size is used,
    # which is what you want for pixel-art.
    def sprite(spec = {})
      path = spec[:path]
      # A Symbol that is not a generated texture is a sprite *name*; resolve it
      # so carts can write draw.sprite path: :hero without ceremony.
      if path.is_a?(Symbol)
        path = Sprites.path(path) unless Sprites.generated?(path)
      elsif path.is_a?(String)
        # A path written by hand is cart-relative, exactly as it is everywhere
        # else in the API.
        path = Assets.resolve path
      end
      color = spec[:color]
      alpha = spec[:alpha]
      natural = natural_size(path, spec[:w], spec[:h])
      r = resolve strip_color(spec.merge(w: natural[0], h: natural[1]))
      prim = r.merge(path: path)
      if color
        prim = prim.merge(Palette.to_hash(color, alpha))
      elsif alpha
        prim = prim.merge(Palette.to_hash(:white, alpha))
      end
      outputs.sprites << apply_sprite_extras(prim, spec)
      r
    end

    # Draw a crop of a sprite sheet by absolute source coordinates.
    def sprite_frame(spec = {})
      src = spec[:source] || {}
      sprite(spec.merge(source_x: src[:x], source_y: src[:y],
                        source_w: src[:w], source_h: src[:h]))
    end

    # Draw frame `index` of a horizontally laid out sheet.
    def sprite_sheet_frame(spec = {})
      fw = spec[:frame_w]
      fh = spec[:frame_h]
      cols = spec[:frame_count] || 1
      i = spec[:frame_index] || 0
      sprite(spec.merge(source_x: i * fw,
                        source_y: 0,
                        source_w: fw,
                        source_h: fh))
    end

    # Text. Returns the visual rect the text occupies, positioned in screen
    # space, so callers can lay out or hit-test without re-measuring.
    def text(str, spec = {})
      color = spec[:color] || Style.get(:text)
      alpha = spec[:alpha]
      size_enum = spec[:size_enum]
      size_px = spec[:size_px]
      font = spec[:font]
      align = spec[:align]
      ax = spec[:anchor_x] || (align == :center ? 0.5 : nil)
      ay = spec[:anchor_y] || (align == :center ? 0.5 : nil)
      str = str.to_s
      tw, th = measure(str, size_enum, size_px, font)

      box = strip_color(spec).merge(w: tw, h: th)
      # Resolve the anchor point itself. DragonRuby positions a label relative
      # to its own text box when anchor_x/anchor_y are supplied, so the anchor
      # keys must not be folded into the box here as well -- that would apply
      # the anchor twice and push every centred string right by half its width.
      box.delete :anchor_x
      box.delete :anchor_y
      pt = resolve box
      lab_ax = ax || 0.0
      lab_ay = ay || 0.0

      label = { x: pt[:x], y: pt[:y], text: str,
                anchor_x: lab_ax, anchor_y: lab_ay }
      label.merge!(Palette.to_hash(color, alpha))
      label[:size_enum] = size_enum if size_enum
      label[:size_px] = size_px if size_px
      label[:font] = font if font
      outputs.labels << label

      { x: pt[:x] - (tw * lab_ax), y: pt[:y] - (th * lab_ay),
        w: tw, h: th }
    end

    # A line of arbitrary thickness (offset copies along the normal).
    def line(x1, y1, x2, y2, color = :white, thickness = 1)
      c = Palette.to_hash color
      thickness = 1 if thickness < 1
      dx = x2 - x1
      dy = y2 - y1
      len = Math.sqrt((dx * dx) + (dy * dy))
      if len == 0.0
        outputs.lines << { x: x1, y: y1, x2: x2, y2: y2 }.merge(c)
        return
      end
      nx = -dy / len
      ny = dx / len
      thickness.times do |i|
        off = i - ((thickness - 1) / 2.0)
        outputs.lines << { x: x1 + (nx * off), y: y1 + (ny * off),
                           x2: x2 + (nx * off), y2: y2 + (ny * off) }.merge(c)
      end
    end

    # --- composites ------------------------------------------------------

    # A horizontal progress bar occupying `r`. Returns the fill width.
    def bar(r, value, max, spec = {})
      bg = spec[:bg] || Style.get(:panel_d)
      fg = spec[:color] || Style.get(:accent)
      perc = Geom.perc value, max
      rect(x: r[:x], y: r[:y], w: r[:w], h: r[:h], color: bg)
      fill_w = r[:w] * perc
      rect(x: r[:x], y: r[:y], w: fill_w, h: r[:h], color: fg) if fill_w > 0
      border(r) if spec[:border]
      fill_w
    end

    # Draw a lattice of cells, one per grid slot. Returns the cell rects so
    # callers can reuse them for selection or hit-testing.
    #
    #   draw.grid x: 0, y: 0, w: 200, h: 100, cols: 8, rows: 4
    #   draw.grid place: { x: 0.5, y: 0.5, w: 200, h: 100 }, cols: 8, rows: 4
    def grid(spec = {})
      r = resolve spec
      cols = spec[:cols] || 1
      rows_count = spec[:rows] || 1
      color = spec[:color] || Style.get(:border)
      gap = spec[:gap] || 1

      col_rects = Geom.columns(r, cols, gap)
      cell_h = (r[:h] - ((rows_count - 1) * gap)) / rows_count.to_f
      out = []
      rows_count.times do |iy|
        col_rects.each do |c|
          cell = { x: c[:x], y: r[:y] + (iy * (cell_h + gap)),
                   w: c[:w], h: cell_h }
          border cell.merge(color: color)
          out << cell
        end
      end
      out
    end

    # --- measurement -----------------------------------------------------

    def measure(str, size_enum = nil, size_px = nil, font = nil)
      opts = {}
      opts[:size_enum] = size_enum if size_enum
      opts[:size_px] = size_px if size_px
      opts[:font] = font if font
      if opts.size > 0
        DR.calcstringbox str.to_s, **opts
      else
        DR.calcstringbox str.to_s
      end
    end

    def text_rect(str, spec = {})
      tw, th = measure(str, spec[:size_enum], spec[:size_px], spec[:font])
      { w: tw, h: th }
    end

    # Natural pixel size of a texture.
    def sprite_size(path)
      natural_size path, nil, nil
    end

    private

    def absolute(r)
      { x: r[:x], y: r[:y], w: r[:w], h: r[:h] }
    end

    def strip_color(spec)
      out = {}
      spec.each { |k, v| out[k] = v unless k == :color || k == :alpha }
      out
    end

    def natural_size(path, w, h)
      return [w, h] if w && h
      begin
        natural = DR.get_sprite_rect path
        return [w, natural.h] if w && natural.h
        return [natural.w, h] if h && natural.w
        [natural.w, natural.h]
      rescue
        # :solid and other non-texture paths have no measurable size.
        [w || 0, h || 0]
      end
    end

    SPRITE_EXTRA_KEYS = %i[angle angle_anchor_x angle_anchor_y
                           flip_horizontally flip_vertically
                           blendmode_enum blendmode scale_quality_enum
                           tile_x tile_y tile_w tile_h
                           source_x source_y source_w source_h
                           z a r g b].freeze

    def apply_sprite_extras(prim, spec)
      SPRITE_EXTRA_KEYS.each do |k|
        prim[k] = spec[k] if spec[k]
      end
      prim
    end
  end
end