# Console::Palette -- named colors and a tiny style table.
#
# Every draw helper defaults its colors from this table, so a cart can restyle
# the whole console by assigning to Palette instead of touching call sites.
module Console
  module Palette
    extend self

    COLORS = {
      black:   [0, 0, 0],
      white:   [255, 255, 255],
      gray:    [128, 128, 128],
      dark:    [24, 24, 32],
      panel:   [40, 42, 56],
      panel_d: [28, 29, 40],
      accent:  [96, 200, 255],
      accent2: [255, 176, 64],
      good:    [96, 220, 140],
      warn:    [255, 200, 72],
      bad:     [255, 88, 88],
      text:    [232, 236, 244],
      muted:   [150, 156, 172],
      shadow:  [0, 0, 0, 160]
    }

    # Resolve a color given as a symbol, [r,g,b], [r,g,b,a], or {r:,g:,b:,a:}.
    # Returns a hash ready to merge into a primitive.
    def to_hash(color, alpha = nil)
      rgb = if color.is_a?(Symbol)
              COLORS[color] || COLORS[:white]
            elsif color.is_a?(Array)
              color
            elsif color.is_a?(Hash)
              [color[:r] || 255, color[:g] || 255, color[:b] || 255]
            else
              COLORS[:white]
            end
      a = alpha
      a = rgb[3] if a.nil? && rgb.size > 3
      h = { r: rgb[0], g: rgb[1], b: rgb[2] }
      h[:a] = a if a
      h
    end

    # Convenience for the common "give me an rgba triplet" case.
    def to_a(color)
      h = to_hash color
      [h[:r], h[:g], h[:b]]
    end
  end

  # Console::Style -- default visual constants for the built-in widgets.
  module Style
    extend self

    DEFAULTS = {
      font: 'tiny.ttf',
      size_enum: 0,
      size_px: nil,
      text: :text,
      muted: :muted,
      panel: :panel,
      panel_d: :panel_d,
      border: :muted,
      accent: :accent,
      pad: 6,
      row_h: 34,
      row_gap: 6
    }

    def get(key)
      DEFAULTS[key]
    end
  end
end