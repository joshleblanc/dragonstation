# Console::UI -- immediate-mode widgets.
#
# Widgets are described as data and drawn through Console::Draw. There is no
# retained widget tree: you ask for a widget, it draws itself and reports its
# state. That keeps the API small and keeps a prototype's UI readable top to
# bottom.
#
#   b = ui.button x: 40, y: 300, w: 200, h: 44, text: 'START'
#   goto :play if b[:clicked]
#
#   ui.panel x: 20, y: 20, w: 260, h: 120, title: 'STATS'
#   ui.bar x: 40, y: 60, w: 200, value: hp, max: max_hp
#   ui.label x: 40, y: 100, text: "HP: #{hp}"
#
# Every widget takes ONE options hash and returns a Hash describing what
# happened (at least :rect, plus :hover/:clicked/:value/:index as relevant).
# One hash per widget is not just style: mruby binds a trailing `key: value`
# list to the FIRST optional parameter of a method, so multi-parameter widget
# signatures silently swallow their geometry. One hash sidesteps that entirely
# and matches the draw.* helpers.
#
# Widgets are keyboard/gamepad navigable by default: hold a pointer over a
# button (or press direction keys on a menu) and :accept activates it.
module Console
  class UI
    attr_reader :console

    def initialize(console)
      @console = console
    end

    def draw
      @console.draw
    end

    def input
      @console.input
    end

    def store
      @console.ui_store
    end

    # Resolve a widget's box from its options, honouring either `y:` (bottom-left
    # origin, DragonRuby's convention) or `top:` (distance from the top of the
    # screen, which is how UI is usually specified). Widgets use this so that
    # `top:` works everywhere consistently.
    def box(opts, w, h)
      x = opts[:x] || 0
      if opts[:top]
        Geom.anchored_top x, opts[:top], w, h, @console.args.grid
      else
        { x: x, y: opts[:y] || 0, w: w, h: h }
      end
    end

    # --- text -------------------------------------------------------------

    # A text label. Returns the measured rect.
    def label(options = {})
      opts = options.dup
      x = opts[:x] || 0
      y = opts[:y] || 0
      text = opts.delete(:text)
      text = '' if text.nil?
      align = opts.delete(:align)
      if align == :center
        opts[:anchor_x] = 0.5
        opts[:anchor_y] = 0.5
      end
      draw.text text.to_s, opts.merge(x: x, y: y)
    end

    # A label with a solid plate behind it, for HUD counters over a busy
    # background.
    def chip(options = {})
      opts = options.dup
      x = opts[:x] || 0
      y = opts[:y] || 0
      text = opts.delete(:text).to_s
      bg = opts.delete(:bg) || Style.get(:panel_d)
      pad = opts.delete(:pad) || 6
      tr = draw.text text, opts.merge(x: x + pad, y: y + pad)
      box = { x: x, y: y, w: tr[:w] + (pad * 2), h: tr[:h] + (pad * 2) }
      draw.rect box.merge(color: bg)
      box
    end

    # --- containers -------------------------------------------------------

    # A panel with an optional title bar. Returns the inner content rect.
    def panel(options = {})
      opts = options.dup
      x = opts[:x] || 0
      y = opts[:y] || 0
      w = opts.delete(:w) || 0
      h = opts.delete(:h) || 0
      title = opts.delete(:title)
      title_h = opts.delete(:title_h) || 28
      pad = opts.delete(:pad) || Style.get(:pad)
      color = opts.delete(:color) || Style.get(:panel)
      alpha = opts.delete(:alpha)
      border_color = opts.delete(:border_color)
      r = box(opts, w, h)
      x = r[:x]
      y = r[:y]

      draw.panel r.merge(color: color, alpha: alpha, border_color: border_color)
      top = y + h
      if title
        draw.rect x: x, y: top - title_h, w: w, h: title_h,
                  color: opts[:title_color] || Style.get(:panel_d)
        draw.text title, x: x + pad, y: top - (title_h / 2.0),
                  anchor_y: 0.5, color: Style.get(:accent)
        draw.line x, top - title_h, x + w, top - title_h, Style.get(:border)
        top -= title_h
      end
      inner = Geom.inset({ x: x, y: y, w: w, h: h }, pad)
      inner[:h] = (top - pad) - inner[:y]
      inner
    end

    # --- indicators -------------------------------------------------------

    # A progress bar. Returns the rect, the fill width and a clamped fraction.
    def bar(options = {})
      opts = options.dup
      x = opts[:x] || 0
      y = opts[:y] || 0
      w = opts.delete(:w) || 100
      h = opts.delete(:h) || 18
      value = opts.delete(:value) || 0
      max = opts.delete(:max)
      max = value if max.nil?
      color = opts.delete(:color) || Style.get(:accent)
      bg = opts.delete(:bg) || Style.get(:panel_d)
      show_text = opts.delete(:text)
      show_counts = opts.delete(:show_counts)
      border = opts.delete(:border)

      r = box(opts, w, h)
      x = r[:x]
      y = r[:y]
      fill = draw.bar r, value, max, color: color, bg: bg, border: border

      if show_text
        caption = show_text.is_a?(Symbol) ? show_text.to_s : show_text
        caption = "#{value}/#{max} #{caption}" if show_counts
        draw.text caption, x: x + (w / 2.0), y: y + (h / 2.0),
                  anchor_x: 0.5, anchor_y: 0.5, color: Style.get(:text)
      end

      { rect: r, fill: fill, perc: Geom.perc(value, max), max: max,
        value: value }
    end

    # Segmented meter: one cell per unit, filled up to `value`.
    def pips(options = {})
      opts = options.dup
      x = opts[:x] || 0
      y = opts[:y] || 0
      w = opts.delete(:w) || 100
      h = opts.delete(:h) || 14
      gap = opts.delete(:gap) || 3
      value = opts.delete(:value) || 0
      max = opts.delete(:max) || value
      count = max.to_i
      count = 1 if count < 1
      color = opts.delete(:color) || Style.get(:accent)
      off = opts.delete(:off_color) || Style.get(:panel_d)

      r = box(opts, w, h)
      x = r[:x]
      y = r[:y]
      cells = Geom.columns(r, count, gap)
      filled = value.to_i
      cells.each_with_index do |c, i|
        draw.rect c.merge(color: (i < filled ? color : off))
      end
      { rect: r, cells: cells, value: value }
    end

    # A slider bound to console UI state. Click to focus, then use left/right
    # (or the dpad) to adjust.
    def slider(options = {})
      opts = options.dup
      x = opts[:x] || 0
      y = opts[:y] || 0
      w = opts.delete(:w) || 160
      h = opts.delete(:h) || 24
      min = opts.delete(:min) || 0
      max = opts.delete(:max) || 100
      step = opts.delete(:step) || 5
      key = opts.delete(:key)
      color = opts.delete(:color) || Style.get(:accent)

      r = box(opts, w, h)
      x = r[:x]
      y = r[:y]
      focus_key = key || "slider_#{x}_#{y}"
      focused = store[focus_key] ? true : false
      value = key ? (store[key] || min) : min
      value = value.clamp(min, max)

      track_rect = r
      if input.pointer_inside?(track_rect) && input.pointer_pressed?
        store[focus_key] = true
        focused = true
      elsif input.pressed?(:cancel)
        store.delete focus_key
        focused = false
      end

      changed = false
      if focused
        if input.pressed?(:right)
          value += step
          changed = true
        end
        if input.pressed?(:left)
          value -= step
          changed = true
        end
        value = value.clamp(min, max)
        store[key] = value if key
      end

      track = { x: x, y: y + ((h - 8) / 2.0), w: w, h: 8 }
      draw.rect track.merge(color: Style.get(:panel_d))
      perc = Geom.perc(value - min, max - min)
      draw.rect x: track[:x], y: track[:y], w: track[:w] * perc, h: track[:h],
                 color: color
      knob_w = 14.0
      knob_x = x + ((w - knob_w) * perc)
      draw.rect x: knob_x, y: y, w: knob_w, h: h,
                 color: (focused ? :white : color)
      draw.text value.to_s, x: x + w + 8, y: y + (h / 2.0), anchor_y: 0.5,
                color: Style.get(:muted)

      { rect: track_rect, value: value, min: min, max: max,
        focused: focused, perc: perc, changed: changed }
    end

    # --- interactive ------------------------------------------------------

    # A button. `:clicked` is true on the frame it is activated, by pointer or
    # by :accept while focused.
    def button(options = {})
      opts = options.dup
      x = opts[:x] || 0
      y = opts[:y] || 0
      w = opts.delete(:w) || 120
      h = opts.delete(:h) || 36
      text = opts.delete(:text) || ''
      id = opts.delete(:id) || text
      on_click = opts.delete(:on_click)
      color = opts.delete(:color) || Style.get(:panel)
      active_color = opts.delete(:active_color) || Style.get(:accent)
      text_color = opts.delete(:text_color) || Style.get(:text)
      disabled = opts.delete(:disabled) ? true : false

      r = box(opts, w, h)
      x = r[:x]
      y = r[:y]
      key = "btn_#{id}"
      hovered = !disabled && input.pointer_inside?(r)
      focused = store['ui_focus'] == key

      if hovered
        store[key] = true
      end
      if input.pointer_pressed? && hovered
        store['ui_focus'] = key
        focused = true
      end
      if input.pressed?(:cancel)
        store.delete key
        focused = false
      end
      if focused && input.pressed?(:accept)
        store['ui_focus'] = key
      end

      clicked = false
      if !disabled && hovered && input.pointer_pressed?
        clicked = true
      end
      if !disabled && focused && input.pressed?(:accept)
        clicked = true
      end
      on_click.call(id) if clicked && on_click

      bg = if disabled
            Style.get(:panel_d)
          elsif clicked || focused
            active_color
          else
            color
          end
      tc = disabled ? Style.get(:muted) : text_color
      draw.rect r.merge(color: bg)
      draw.border r.merge(color: Style.get(:border)), 1
      draw.text text, x: x + (w / 2.0), y: y + (h / 2.0),
                anchor_x: 0.5, anchor_y: 0.5, color: tc

      { rect: r, hovered: hovered, focused: focused, clicked: clicked,
        disabled: disabled, id: id, text: text }
    end

    # A checkbox bound to console UI state. Returns the new value.
    def checkbox(options = {})
      opts = options.dup
      x = opts[:x] || 0
      y = opts[:y] || 0
      key = opts.delete(:key)
      text = opts.delete(:text) || ''
      box = opts.delete(:box) || 22

      r = box(opts, box, box)
      x = r[:x]
      y = r[:y]
      value = store[key] ? true : false
      clicked = input.pointer_inside?(r) && input.pointer_pressed?
      if clicked
        value = !value
        store[key] = value
      end
      draw.border r.merge(color: Style.get(:accent)), 2
      draw.rect Geom.inset(r, 5).merge(color: Style.get(:accent)) if value
      draw.text text, x: x + box + 10, y: y + (box / 2.0), anchor_y: 0.5
      { rect: r, value: value, changed: clicked }
    end

    # A vertical list with keyboard/gamepad navigation.
    #
    #   m = ui.menu x: 640, y: 200, items: ['PLAY', 'OPTIONS'], key: 'main'
    #   goto :play if m[:clicked] == 'PLAY'
    def menu(options = {})
      opts = options.dup
      items = opts.delete(:items) || []
      x = opts[:x] || 0
      y = opts[:y] || 0
      width = opts.delete(:w) || 260
      row_h = opts.delete(:row_h) || Style.get(:row_h)
      gap = opts.delete(:gap) || Style.get(:row_gap)
      key = opts.delete(:key) || 'menu'
      color = opts.delete(:color) || Style.get(:panel)
      active_color = opts.delete(:active_color) || Style.get(:accent)
      on_select = opts.delete(:on_select)

      index = store["menu_index_#{key}"] || opts.delete(:selected) || 0
      index = 0 if index < 0
      index = items.size - 1 if items.size > 0 && index > items.size - 1

      anchor = box(opts, width, row_h)
      x = anchor[:x]
      y = anchor[:y]

      rects = []
      hovered_index = -1
      items.each_with_index do |item, i|
        cell = { x: x, y: y + (i * (row_h + gap)), w: width, h: row_h }
        rects << cell
        hovered_index = i if input.pointer_inside?(cell)
      end

      clicked = nil
      if hovered_index >= 0
        index = hovered_index
        if input.pointer_pressed?
          clicked = items[index]
        end
      elsif items.size > 0
        # Keyboard / gamepad navigation when the pointer is not on the menu.
        if input.pressed?(:up)
          index -= 1
          index = items.size - 1 if index < 0
        end
        if input.pressed?(:down)
          index += 1
          index = 0 if index > items.size - 1
        end
        if input.pressed?(:accept)
          clicked = items[index]
        end
      end
      store["menu_index_#{key}"] = index
      on_select.call(items[index]) if clicked && on_select

      rects.each_with_index do |cell, i|
        selected = i == index
        draw.rect cell.merge(color: (selected ? active_color : color))
        draw.border cell.merge(color: Style.get(:border)), 1 unless selected
        draw.text items[i].to_s,
                  x: cell[:x] + (cell[:w] / 2.0),
                  y: cell[:y] + (cell[:h] / 2.0),
                  anchor_x: 0.5, anchor_y: 0.5,
                  color: (selected ? :dark : Style.get(:text))
      end

      total_h = (rects.size * (row_h + gap)) - gap
      { index: index, clicked: clicked, items: rects, labels: items,
        rect: { x: x, y: y, w: width, h: total_h },
        hovered: hovered_index >= 0 }
    end

    # --- HUD --------------------------------------------------------------

    # The debug/status overlay. Toggle with :debug_toggle (F1).
    def hud(_options = {})
      return nil unless @console.show_hud
      grid = @console.args.grid
      lines = []
      lines << "fps #{DR.current_framerate.round}"
      lines << "scene #{@console.scenes.current_name} depth #{@console.scenes.depth}"
      counts = @console.kind_counts
      lines << "entities #{@console.entities.size} " \
               "#{counts.map { |k, v| "#{k}:#{v}" }.join(' ')}".strip
      lines << "tweens #{@console.tweens.tweens.size} " \
               "timers #{@console.tweens.timers.size} " \
               "tickers #{@console.tweens.tickers.size}"

      missing = Sprites.missing_names
      unless missing.size == 0
        lines << "MISSING SPRITES #{missing.size}"
        missing.first(5).each { |m| lines << "  #{m}" }
      end

      pad = 8
      line_h = 16
      box_w = 320
      box_h = (lines.size * line_h) + (pad * 2)
      bx = grid.w - box_w - 10
      by = grid.h - box_h - 10
      draw.rect x: bx, y: by, w: box_w, h: box_h, color: :black, alpha: 180
      lines.each_with_index do |line, i|
        draw.text line, x: bx + pad, y: by + pad + (i * line_h),
                  size_enum: -3, color: Style.get(:text)
      end
      { rect: { x: bx, y: by, w: box_w, h: box_h }, lines: lines }
    end

    # A centred modal card for title / pause / game-over screens.
    def card(options = {})
      opts = options.dup
      grid = @console.args.grid
      w = opts.delete(:w) || 420
      h = opts.delete(:h) || 300
      dim = opts.key?(:dim) ? opts.delete(:dim) : true
      color = opts.delete(:color) || Style.get(:panel)
      alpha = opts.delete(:alpha)
      if dim
        draw.rect x: 0, y: 0, w: grid.w, h: grid.h, color: :black,
                  alpha: opts.delete(:dim_alpha) || 170
      end
      r = Geom.place(Geom.screen_rect(grid),
                     x: 0.5, y: 0.5, w: w, h: h,
                     anchor_x: 0.5, anchor_y: 0.5)
      draw.panel r.merge(color: color, alpha: alpha)
      r
    end
  end
end