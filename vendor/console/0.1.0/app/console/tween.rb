# Console::Tween -- frame-driven interpolation and a tick scheduler.
#
# Tweening removes the "remember the start value, then lerp every frame"
# boilerplate that otherwise shows up in every prototype.
#
#   tween(entity, :x, to: 400, in: 30)                # linear over 30 ticks
#   tween(entity, :alpha, to: 0, in: 30, ease: :out)
#   tween(entity, :y, from: 100, to: 0, in: 60, delay: 20)
#   tween(entity, :w, to: 64, in: 20, on_done: -> { sfx :land })
#
# The scheduler handles deferred work, the other half of prototype ergonomics:
#
#   after 30 { spawn Enemy, x: 100, y: 100 }          # in half a second
#   every 60, immediate: true { next_wave }
module Console
  class Tween
    # Easing curves take a 0..1 progress and return 0..1.
    EASINGS = {
      linear: ->(p) { p },
      in: ->(p) { p * p },
      out: ->(p) { 1.0 - ((1.0 - p) * (1.0 - p)) },
      in_out: ->(p) { p < 0.5 ? (2.0 * p * p) : (1.0 - (((-2.0 * p) + 2.0) ** 2) / 2.0) },
      smooth: ->(p) { p * p * (3.0 - (2.0 * p)) },
      # elasticOut deliberately overshoots past 1 mid-curve; that is the point.
      elastic: ->(p) { elastic_out p },
      bounce: ->(p) { bounce p }
    }

    # Penner bounceOut. Each branch offsets the *original* progress exactly
    # once, which is what makes the curve finish at 1.
    def self.bounce(p)
      n = 7.5625
      d = 2.75
      if p < (1.0 / d)
        n * p * p
      elsif p < (2.0 / d)
        q = p - (1.5 / d)
        (n * q * q) + 0.75
      elsif p < (2.5 / d)
        q = p - (2.25 / d)
        (n * q * q) + 0.9375
      else
        q = p - (2.625 / d)
        (n * q * q) + 0.984375
      end
    end

    # Penner elasticOut: anchored at 0 and 1, overshooting in between.
    def self.elastic_out(p)
      return 0.0 if p <= 0.0
      return 1.0 if p >= 1.0
      ((2 ** (-10 * p)) * Math.sin((((p * 10) - 0.75) * (2 * Math::PI)) / 3.0)) + 1
    end

    attr_reader :target, :property, :to, :duration, :delay, :on_done, :ease_name
    attr_reader :cycle

    def initialize(target, property, options)
      @target = target
      @property = property.to_sym
      @to = options[:to]
      @duration = (options[:in] || 30).to_i
      @duration = 1 if @duration < 1
      @delay = (options[:delay] || 0).to_i
      @ease_name = (options[:ease] || :linear).to_sym
      @ease = EASINGS[@ease_name] || EASINGS[:linear]
      @on_done = options[:on_done]
      @loops = options[:loops] || 1
      @yoyo = options[:yoyo] ? true : false
      @cycle = 0
      @started_at = options[:now] || Kernel.tick_count
      @done = false
      @from = options.key?(:from) ? options[:from] : nil
      @origin = @from
      @reverse = false
    end

    # Lock in the value we are tweening away from.
    def capture!
      @origin = @from.nil? ? @target[@property] : @from
      self
    end

    # The value this pass starts from.
    def from_value
      @reverse ? @to : @origin
    end

    def to_value
      @reverse ? @origin : @to
    end

    def done?
      @done
    end

    def progress(now = Kernel.tick_count)
      return 0.0 if @duration == 0
      elapsed = now - @started_at - @delay
      return 0.0 if elapsed < 0
      p = elapsed.to_f / @duration
      p > 1.0 ? 1.0 : p
    end

    # Advance to `now` (defaults to the current tick). Returns true while the
    # tween is still running. Passing an explicit tick makes tweens testable
    # without sleeping through real frames.
    def update(now = Kernel.tick_count)
      return false if @done
      return true if (now - @started_at) < @delay

      p = progress(now)
      t = @ease.call p
      a = from_value
      b = to_value
      apply a, b, t, p

      return true if p < 1.0

      # Finished one pass. Either loop again or finish.
      if @cycle + 1 < @loops
        @cycle += 1
        if @yoyo
          # Reverse direction, keeping the same endpoints, so an even number of
          # yoyo cycles lands back where it started.
          @reverse = !@reverse
        else
          # Re-loop from wherever the last pass finished.
          @origin = @target[@property]
        end
        @started_at = now
        return true
      end

      apply a, b, 1.0, 1.0
      @done = true
      @on_done.call @target if @on_done
      false
    end

    private

    def apply(a, b, t, p)
      if a.is_a?(Numeric) && b.is_a?(Numeric)
        @target[@property] = a + ((b - a) * t)
      elsif b.nil?
        @target.delete @property
      elsif p >= 1.0
        @target[@property] = b
      else
        @target[@property] = a
      end
    end
  end

  # The console's tween list plus its tick scheduler.
  class TweenHost
    attr_reader :tweens, :timers, :tickers

    def initialize
      @tweens = []
      @timers = []
      @tickers = []
    end

    def tick_count
      Kernel.tick_count
    end

    # --- tweening ---------------------------------------------------------

    # Tween one property of a Hash-like target. Returns the Tween so callers
    # can cancel or inspect it.
    def tween(target, property, options = {})
      t = Tween.new target, property, options
      t.capture!
      @tweens << t
      t
    end

    # Tween several properties of one target with identical timing.
    def tween_all(target, properties, options = {})
      properties.map do |prop|
        spec = {}
        options.each { |k, v| spec[k] = v }
        tween target, prop, spec
      end
    end

    def cancel_tweens(target, property = nil)
      @tweens.reject! do |t|
        next false unless t.target.equal?(target)
        property.nil? || t.property == property.to_sym
      end
    end

    def cancel_tween(tween)
      @tweens.delete tween
    end

    def tweening?(target)
      @tweens.any? { |t| t.target.equal?(target) }
    end

    # --- scheduling -------------------------------------------------------

    # Run a block once, `ticks` frames from now. Returns a handle you can pass
    # to cancel_timer.
    def after(ticks, &block)
      entry = { at: tick_count + ticks.to_i, block: block }
      @timers << entry
      entry
    end

    # Run a block on a fixed cadence. `immediate: true` also runs it now.
    def every(ticks, options = {}, &block)
      period = ticks.to_i
      period = 1 if period < 1
      entry = { period: period,
                next_at: tick_count + (options[:immediate] ? 0 : period),
                block: block }
      @tickers << entry
      entry
    end

    # Run a block once, on the next frame.
    def next_tick(&block)
      after 0, &block
    end

    def cancel_timer(entry)
      @timers.delete entry
    end

    def cancel_ticker(entry)
      @tickers.delete entry
    end

    def pending_timers
      @timers.size
    end

    # --- frame ------------------------------------------------------------

    # Advance everything. Timers fire before tickers, which fire before
    # tweens, so a timer that starts a tween behaves predictably.
    def update
      now = tick_count

      due = @timers.select { |t| t[:at] <= now }
      @timers = @timers - due
      due.each { |t| t[:block].call }

      firing = @tickers.select { |t| t[:next_at] <= now }
      firing.each do |t|
        t[:next_at] = now + t[:period]
        t[:block].call
      end

      @tweens.each { |t| t.update }
      @tweens.reject! { |t| t.done? }
    end

    def clear
      @tweens = []
      @timers = []
      @tickers = []
    end
  end
end