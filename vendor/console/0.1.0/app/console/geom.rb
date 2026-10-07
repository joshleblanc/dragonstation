# Console::Geom -- rect/point helpers.
#
# Everything here is pure: it takes numbers and hashes and returns numbers or
# hashes. Nothing touches DragonRuby's outputs.
#
# NOTE: DragonRuby gives engine-built hashes (eg. Layout.rect) a `center`
# key, but a plain `{x:, y:, w:, h:}` hash returns `nil` for `.center`. So
# every helper in this library uses Console::Geom.center instead of `.center`
# so that it works uniformly on hand-built hashes.
module Console
  module Geom
    extend self

    def rect(x, y, w, h)
      { x: x, y: y, w: w, h: h }
    end

    # The geometric centre of a rect.
    #
    # This is the middle of the box, NOT the anchor point: DragonRuby's own
    # `Layout.rect` reports a `center` of that shape, and mixing the two up is
    # the classic off-by-half-a-sprite bug. Anchors describe where x/y sit, so
    # they deliberately do not affect the centre.
    def center(r)
      { x: r[:x] + (r[:w] / 2.0),
        y: r[:y] + (r[:h] / 2.0) }
    end

    def center_x(r)
      center(r).x
    end

    def center_y(r)
      center(r).y
    end

    def right(r)
      r[:x] + r[:w]
    end

    def top(r)
      r[:y] + r[:h]
    end

    def area(r)
      r[:w] * r[:h]
    end

    # Shrink (or grow, with negative padding) a rect on all sides.
    def inset(r, amount)
      inset_xy r, amount, amount
    end

    def inset_xy(r, dx, dy)
      { x: r[:x] + dx,
        y: r[:y] + dy,
        w: r[:w] - (dx * 2),
        h: r[:h] - (dy * 2) }
    end

    # Split a rect into a row of `count` columns, leaving `gap` px between.
    # Used by UI::Bar and UI::Menu so spacing logic lives in one place.
    def columns(r, count, gap = 0)
      return [] if count <= 0
      total_gap = gap * (count - 1)
      w = (r[:w] - total_gap) / count.to_f
      out = []
      count.times do |i|
        out << { x: r[:x] + (i * (w + gap)),
                 y: r[:y],
                 w: w,
                 h: r[:h] }
      end
      out
    end

    def rows(r, count, gap = 0)
      return [] if count <= 0
      total_gap = gap * (count - 1)
      h = (r[:h] - total_gap) / count.to_f
      out = []
      count.times do |i|
        out << { x: r[:x],
                 y: r[:y] + (i * (h + gap)),
                 w: r[:w],
                 h: h }
      end
      out
    end

    # Position a rect inside `bounds` using fractional placement. This is the
    # workhorse behind every `place:` option in the UI toolkit.
    #
    #   place(bounds, {x: 0.5, y: 0.5, anchor_x: 0.5, anchor_y: 0.5})
    def place(bounds, spec)
      ax = spec[:anchor_x] || 0.0
      ay = spec[:anchor_y] || 0.0
      fx = spec[:x] || 0.0
      fy = spec[:y] || 0.0
      w = spec[:w] || 0
      h = spec[:h] || 0
      {
        x: bounds[:x] + (bounds[:w] * fx) - (w * ax),
        y: bounds[:y] + (bounds[:h] * fy) - (h * ay),
        w: w,
        h: h
      }
    end

    # The full screen as a rect, using the live logical grid. Preferred over
    # Layout.allscreen_rect, which does not track the actual viewport.
    def screen_rect(grid)
      { x: 0, y: 0, w: grid.w, h: grid.h }
    end

    def from_grid_pct(grid, x_pct, y_pct, w_pct = 1.0, h_pct = 1.0)
      place screen_rect(grid),
            x: x_pct, y: y_pct, w: grid.w * w_pct, h: grid.h * h_pct
    end

    # Margin all four edges of the screen inward.
    def safe_rect(grid, margin)
      inset screen_rect(grid), margin
    end

    # Clamp a rect so it fits inside `bounds` without changing its size.
    def clamp_inside(r, bounds)
      out = { x: r[:x], y: r[:y], w: r[:w], h: r[:h] }
      max_x = bounds[:x] + bounds[:w] - out[:w]
      max_y = bounds[:y] + bounds[:h] - out[:h]
      out[:x] = out[:x].clamp(bounds[:x], max_x < bounds[:x] ? bounds[:x] : max_x)
      out[:y] = out[:y].clamp(bounds[:y], max_y < bounds[:y] ? bounds[:y] : max_y)
      out
    end

    def contains?(r, px, py)
      px >= r[:x] && px < r[:x] + r[:w] &&
        py >= r[:y] && py < r[:y] + r[:h]
    end

    # Shrink a rect until it fits a square, preserving aspect ratio. Handy for
    # letterboxing artwork inside a panel.
    def contain(inner, outer)
      if inner[:w] <= 0 || inner[:h] <= 0
        return { x: outer[:x], y: outer[:y], w: outer[:w], h: outer[:h] }
      end
      scale = [outer[:w] / inner[:w].to_f, outer[:h] / inner[:h].to_f].min
      w = inner[:w] * scale
      h = inner[:h] * scale
      { x: outer[:x] + ((outer[:w] - w) / 2.0),
        y: outer[:y] + ((outer[:h] - h) / 2.0),
        w: w,
        h: h }
    end

    # Fraction of `max` that `value` represents, clamped to 0..1.
    #
    # A max of zero (or nil) means "no scale to divide by", and yields 0
    # rather than Infinity/NaN. Shared by Draw#bar and UI#bar so the two can
    # never disagree.
    def perc(value, max)
      return 0.0 if max.nil?
      m = max.to_f
      return 0.0 if m <= 0.0
      v = value.to_f / m
      v < 0.0 ? 0.0 : (v > 1.0 ? 1.0 : v)
    end

    # --- top-down layout ---------------------------------------------------
    #
    # DragonRuby's origin is bottom-left, which is correct for game worlds but
    # awkward for menus: counting upward from the bottom edge of a list is
    # nobody's mental model. These helpers think from the top of the screen,
    # which is how UI is normally specified.

    # Convert "y pixels down from the top of the screen" into the bottom-left
    # origin y that DragonRuby expects.
    def top(y, grid = nil)
      g = grid || $args.grid
      g.h - y
    end

    # Build a rect whose TOP edge sits `top_y` pixels below the top of the
    # screen. This is the shape you want for UI: "this panel starts 120px from
    # the top", instead of the far more error-prone "y = screen_h - 120 - h".
    def anchored_top(x, top_y, w, h, grid = nil)
      g = grid || $args.grid
      { x: x, y: g.h - top_y - h, w: w, h: h }
    end

    # Read a rect out of a widget/draw spec, honouring either `y:` (DragonRuby
    # bottom-left) or `top:` (distance from the top of the screen).
    #
    # Returns nil when the spec carries neither, so callers can tell "anchored
    # to the top" from "anchored to the bottom".
    def spec_top(opts, w, h, grid = nil)
      return nil unless opts[:top]
      anchored_top opts[:x] || 0, opts[:top], w, h, grid
    end

    # Lay out `count` rows downward from the top, returning the rect for row
    # `index`. Rows are as tall as they need to be for `line_h`.
    def row_from_top(top_y, index, width, line_h, gap = 0)
      y = (top_y - ((index + 1) * line_h) + line_h) - (index * gap)
      { x: 0, y: y, w: width, h: line_h }
    end

    # A full-width strip at `top_y`, `h` tall, running from the left edge.
    def strip(top_y, h, width = nil)
      grid = $args.grid
      w = width || grid.w
      { x: 0, y: grid.h - top_y - h, w: w, h: h }
    end

    def distance(a, b)
      Geometry.distance a, b
    end

    def angle(a, b)
      Geometry.angle a, b
    end
  end
end