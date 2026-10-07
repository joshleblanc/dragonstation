# Console::Scene -- the scene controller.
#
# DragonRuby has no scene system; every sample hand-rolls a `current_scene` /
# `next_scene` pair. This module formalises that, adds a stack, and gives each
# scene four optional hooks:
#
#   enter     called once when the scene becomes active
#   update    every frame while active
#   render    every frame while active
#   leave     called once when the scene stops being active
#
# The hook is called `render`, not `draw`: `draw` is the console's rendering
# object (`draw.rect`, `draw.sprite`), and a scene that defined `draw` would
# shadow it and recurse.
#
# A scene can be a Symbol paired with a class, a class, or a bare block set:
#
#   scene :title, TitleScene
#   scene :play, PlayScene
#
#   goto :play                 # replace the whole stack
#   push :pause                # overlay, keeps :play underneath
#   pop                        # back to :play
#
# Scene changes are committed at the END of the frame, so calling goto from
# inside update never leaves the frame half-run. Each scene gets its own state
# hash under `args.state.console.scenes[name]`, so leaving a scene and coming
# back does not lose data.
module Console
  # A registered scene definition.
  class SceneDef
    attr_reader :name, :klass, :options

    def initialize(name, klass = nil, options = {})
      @name = name.to_sym
      @klass = klass
      @options = options
    end

    # Build the per-scene instance. `kind` is :class, :block, or :none.
    def kind
      return :class if @klass.is_a?(Class)
      return :block if @klass.respond_to?(:call)
      :none
    end
  end

  class SceneController
    attr_reader :defs, :stack
    attr_accessor :current

    def initialize(args)
      @args = args
      @defs = {}
      @stack = []
      @current = nil
      @current_instance = nil
      @pending = nil
      @pending_push = false
      @pending_pop = false
      @pending_clear = false
      @enter_hooks = {}
      @leave_hooks = {}
      @history = []
    end

    def args
      @args
    end

    def tick_count
      Kernel.tick_count
    end

    # --- registration -----------------------------------------------------

    def define(name, klass = nil, options = {})
      d = SceneDef.new name, klass, options
      mix_in_api d.klass
      @defs[d.name] = d
      d
    end

    # Give a scene class the console's API as bare method calls, so a scene can
    # say `draw.rect` / `spawn` / `sfx` instead of `Console.draw.rect`.
    def mix_in_api(klass)
      return unless klass.is_a?(Class)
      return if klass.include?(Console::API)
      klass.include Console::API
    rescue
      nil
    end

    def defined?(name)
      @defs.key?(name.to_sym)
    end

    def names
      @defs.keys
    end

    # Per-scene state, created on first access.
    def store(name)
      root = @args.state.console_scenes ||= {}
      root[name.to_sym] ||= {}
    end

    # --- hooks ------------------------------------------------------------

    # Run a block whenever a scene is entered.
    def on_enter(name, &block)
      (@enter_hooks[name.to_sym] ||= []) << block
    end

    # Run a block whenever a scene is left.
    def on_leave(name, &block)
      (@leave_hooks[name.to_sym] ||= []) << block
    end

    # --- navigation -------------------------------------------------------

    def pending?
      !@pending.nil? || @pending_pop || @pending_clear
    end

    # Replace the entire stack with `name`.
    def goto(name)
      @pending = name.to_sym
      @pending_push = false
      @pending_pop = false
      @pending_clear = false
      name
    end

    # Push a scene on top of the current one.
    def push(name)
      @pending = name.to_sym
      @pending_push = true
      @pending_pop = false
      @pending_clear = false
      name
    end

    def pop
      @pending_pop = true
      @pending_push = false
      @pending_clear = false
      nil
    end

    # Quit back to the first scene.
    def unwind
      @pending_clear = true
      @pending_pop = false
      nil
    end

    def depth
      @stack.size
    end

    def current_name
      @current
    end

    def instance
      @current_instance
    end

    def active?(name)
      @current == name.to_sym
    end

    def underneath?(name)
      return false if @stack.size < 2
      @stack[@stack.size - 2] == name.to_sym
    end

    # --- frame ------------------------------------------------------------

    # Update and draw the active scene, then commit any pending change. Called
    # once per frame by Console#tick.
    def run(draw_enabled = true)
      # A pending change (the first goto, or a new frame's request) is
      # committed up front so the scene activated here gets its update too.
      commit if pending?
      # A scene's `enter` may itself request a change.
      commit if pending?

      if @current
        dispatch :update, @current_instance
        dispatch :render, @current_instance if draw_enabled
      end

      # Anything requested during update is applied now, so the next frame
      # runs the new scene and this one never sees a half-applied change.
      commit if pending?
    end

    # Draw the scenes underneath the top one, dimmed. Used by pause overlays.
    def draw_below(draw_arg)
      return if @stack.size < 2
      under = @stack[@stack.size - 2]
      d = @defs[under]
      return unless d
      inst = instance_for under, d
      dispatch :render, inst
      draw_arg.rect x: 0, y: 0, w: @args.grid.w, h: @args.grid.h,
                     color: :black, alpha: 160
    end

    def dispatch(hook, inst)
      d = @defs[@current]
      return unless d
      if d.kind == :class
        return unless inst.respond_to?(hook)
        return unless inst.method(hook).arity == 0
        inst.send hook
      elsif d.kind == :block
        return unless d.klass.respond_to?(:[])
        return unless d.klass.key?(hook)
        d.klass[hook].call inst
      end
    end

    private

    def activate(name)
      d = @defs[name]
      unless d
        puts "Console: scene #{name} is not defined; ignoring."
        return
      end
      @current_instance = instance_for name, d
      dispatch :enter, @current_instance
      (@enter_hooks[name.to_sym] || []).each { |h| h.call @current_instance }
      # A scene may immediately request another change (common for routing
      # guards), so give it a chance before drawing anything.
      commit if pending?
    end

    def leave(name)
      return if name.nil?
      d = @defs[name]
      inst = @current_instance
      if d
        dispatch_leave d, inst
      end
      (@leave_hooks[name.to_sym] || []).each { |h| h.call inst }
      @current_instance = nil
    end

    def dispatch_leave(d, inst)
      if d.kind == :class
        return unless inst.respond_to?(:leave)
        return unless inst.method(:leave).arity == 0
        inst.leave
      elsif d.kind == :block
        return unless d.klass.respond_to?(:[])
        return unless d.klass.key?(:leave)
        d.klass[:leave].call inst
      end
    end

    def instance_for(name, d)
      case d.kind
      when :class
        d.klass.new
      when :block
        d.klass
      else
        nil
      end
    end

    def commit
      if @pending_clear
        @pending_clear = false
        return if @stack.empty?
        top = @stack.pop
        leave top
        @current = @stack.last
        @current_instance = nil
        return
      end

      if @pending_pop
        @pending_pop = false
        return if @stack.size <= 1
        top = @stack.pop
        leave top
        @current = @stack.last
        @current_instance = nil
        return
      end

      return if @pending.nil?
      name = @pending
      @pending = nil

      if @pending_push
        @pending_push = false
        return if @stack.include?(name)
        @stack.push name
      else
        # `goto` replaces the stack: leave whatever was actually active, then
        # reset the stack to just the new scene.
        leave @current if @current
        @stack = [name]
      end

      @history.push @current
      @history = @history.last(32)
      @current = @stack.last
      @current_instance = nil
      activate @current
    end
  end
end