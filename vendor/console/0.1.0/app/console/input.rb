# Console::Input -- one action vocabulary across keyboard, controller and
# pointer.
#
# A cart asks `input.pressed?(:accept)` and never has to care whether the
# player is on a keyboard, a gamepad, or a touchscreen. The snapshot is taken
# once at the top of the frame (see Input#snapshot) so repeated queries during
# a frame are cheap and consistent.
module Console
  class Input
    # Logical actions, mapped below. Extending ACTIONS is enough to add a
    # button everywhere.
    ACTIONS = %i[up down left right accept cancel pause
                action_1 action_2 action_3 action_4
                debug_toggle].freeze

    attr_reader :args
    attr_reader :actions
    attr_reader :text_buffer
    attr_accessor :text_enabled

    def initialize(args)
      @args = args
      @actions = {}
      @text_buffer = []
      @device = :keyboard
      @pointer_down_prev = false
      @text_enabled = false
      @text_buffer = []
      ACTIONS.each { |a| @actions[a] = new_action }
    end

    def new_action
      { held: false, pressed: false, released: false }
    end

    # Recompute the frame snapshot. Called once per tick by Console#tick.
    def refresh
      @actions.each_value do |a|
        a[:released] = a[:held]
        a[:pressed] = false
      end

      # Directional actions: DragonRuby already merges arrows + WASD + dpad +
      # left analog for these.
      set :up, args.inputs.up
      set :down, args.inputs.down
      set :left, args.inputs.left
      set :right, args.inputs.right

      # Keyboard confirm/cancel.
      k = args.inputs.keyboard
      confirm_key = k.key_down_or_held?(:enter) || k.key_down_or_held?(:space)
      cancel_key = k.key_down_or_held?(:escape) ||
                  k.key_down_or_held?(:backspace)
      confirm_press = k.key_down?(:enter) || k.key_down?(:space)
      cancel_press = k.key_down?(:escape) || k.key_down?(:backspace)

      # Controller confirm/cancel. `accept`/`cancel` are top-level properties,
      # but they are NOT valid arguments to the dynamic key lookups, so we
      # resolve the physical button instead and swap it on a Switch Pro pad
      # (which physically relabels a/b).
      @controller = args.inputs.controller_one
      accept_btn = c_accept_button
      cancel_btn = c_cancel_button
      set :accept, confirm_key || pad_held?(accept_btn), confirm_press || pad_down?(accept_btn)
      set :cancel, cancel_key || pad_held?(cancel_btn), cancel_press || pad_down?(cancel_btn)
      set :pause, k.key_down_or_held?(:escape) || pad_held?(:start)
      set :debug_toggle, k.key_down_or_held?(:f1)

      # Shoulder/menu buttons.
      set :action_1, k.key_down_or_held?(:q) || pad_held?(:l1)
      set :action_2, k.key_down_or_held?(:w) || pad_held?(:r1)
      set :action_3, pad_held?(:l2)
      set :action_4, pad_held?(:r2)

      refresh_pointer

      @device = args.inputs.last_active || @device
      # DragonRuby warns if args.inputs.text is read without text input being
      # started, so only poll it while a cart has opted in.
      @text_buffer = @text_enabled ? args.inputs.text.to_a : []
    end

    # Start collecting typed characters. Required before `typed` returns
    # anything; on touch devices this raises the on-screen keyboard.
    def enable_text
      @text_enabled = true
      DR.start_text_input
    end

    def disable_text
      @text_enabled = false
      DR.stop_text_input
    end

    # --- queries ---------------------------------------------------------

    def held?(action)
      a = @actions[action]
      a ? a[:held] : false
    end

    def pressed?(action)
      a = @actions[action]
      a ? a[:pressed] : false
    end

    def released?(action)
      a = @actions[action]
      a[:released] && !a[:held] ? true : false
    end

    def any_pressed?(*list)
      list.flatten.each { |a| return true if pressed?(a) }
      false
    end

    # -1.0 .. 1.0, analog when available.
    def axis_x
      args.inputs.left_right_perc
    end

    def axis_y
      args.inputs.up_down_perc
    end

    def axis_vector
      { x: axis_x, y: axis_y }
    end

    def last_device
      @device
    end

    def controller_connected?
      args.inputs.controller_one.connected
    end

    # --- pointer ---------------------------------------------------------

    # A single pointer abstraction covering mouse and first touch point.
    # x/y are in screen space, already offset by the console camera.
    def pointer
      @pointer
    end

    def pointer_down?
      @pointer ? @pointer[:down] : false
    end

    def pointer_pressed?
      @pointer ? @pointer[:pressed] : false
    end

    def pointer_released?
      @pointer ? @pointer[:released] : false
    end

    def pointer_inside?(r)
      @pointer ? Geom.contains?(r, @pointer[:x], @pointer[:y]) : false
    end

    # True on the frame the pointer went down inside `r`.
    def clicked?(r)
      pointer_pressed? && pointer_inside?(r)
    end

    # --- text ------------------------------------------------------------

    # Characters typed since the last frame (requires DR.start_text_input).
    def typed
      @text_buffer
    end

    def text_entered?(ch = nil)
      return false if @text_buffer.size == 0
      return true if ch.nil?
      @text_buffer.include?(ch)
    end

    private

    def set(action, held, pressed = nil)
      a = @actions[action]
      return unless a
      was_held = a[:held]
      if held
        a[:held] = true
        a[:pressed] = pressed.nil? ? !was_held : pressed
      else
        a[:held] = false
        a[:pressed] = false
      end
    end

    # A Nintendo Switch Pro Controller relabels a/b, so the confirm button is
    # physically `b` on that pad and `a` everywhere else.
    def switch_pro?
      name = @controller.name.to_s.downcase
      name.include?('switch') && name.include?('pro')
    end

    def c_accept_button
      switch_pro? ? :b : :a
    end

    def c_cancel_button
      switch_pro? ? :a : :b
    end

    # Dynamic key lookups raise for buttons a given pad does not expose, and a
    # disconnected pad has no keys at all. Both are normal, not errors.
    def pad_held?(button)
      @controller.key_down_or_held?(button)
    rescue
      false
    end

    def pad_down?(button)
      @controller.key_down?(button)
    rescue
      false
    end

    def refresh_pointer
      m = args.inputs.mouse
      x = m.x
      y = m.y
      if m.respond_to?(:has_focus) && !m.has_focus
        finger = args.inputs.finger_left
        if finger
          x = finger.x
          y = finger.y
        end
      end
      down = m.button_left
      pressed = m.key_down.left
      released = m.key_up.left
      @pointer_down_prev = down
      @pointer = { x: x, y: y, down: down, pressed: pressed, released: released }
    end
  end
end