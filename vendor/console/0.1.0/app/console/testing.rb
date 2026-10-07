# Console::Test -- a tiny in-engine test harness.
#
# Tests run inside the real DragonRuby runtime, so they exercise the actual
# renderer, the actual output collections and the actual mruby build rather
# than a stand-in. Failures are collected, printed, and summarised in a single
# machine-readable line the runner script can grep.
#
#   class MySuite
#     include Console::Test
#
#     def setup
#       @thing = []
#     end
#
#     test 'does the thing' do
#       assert_equal 2, @thing.size
#     end
#   end
#
# Each `test` block is evaluated against a fresh instance of the suite, so
# `setup` runs first and instance state does not leak between tests.
module Console
  module Test
    # Populated by the `test` macro; each entry is [suite_class, name, block].
    def self.registry
      @registry ||= []
    end

    def self.clear
      @registry = []
    end

    # `include Console::Test` gives a suite the class-level `test` macro and
    # the instance-level assertions.
    def self.included(base)
      base.extend ClassLevel
    end

    module ClassLevel
      # Declare a test. Runs against a fresh instance of this suite.
      def test(name, &block)
        Console::Test.registry << [self, name.to_s, block]
      end
    end

    # --- assertions -------------------------------------------------------

    def assert(condition, message = nil)
      Console::Test.record condition, message || 'expected condition to be true'
    end

    def refute(condition, message = nil)
      Console::Test.record !condition, message || 'expected condition to be false'
    end

    def assert_equal(expected, actual, message = nil)
      ok = expected == actual
      msg = message || "expected #{expected.inspect}, got #{actual.inspect}"
      Console::Test.record ok, msg
    end

    def assert_almost_equal(expected, actual, tolerance = 0.001, message = nil)
      ok = (expected - actual).abs <= tolerance
      msg = message || "expected #{expected} +/- #{tolerance}, got #{actual}"
      Console::Test.record ok, msg
    end

    def refute_equal(expected, actual, message = nil)
      ok = expected != actual
      Console::Test.record ok,
                           message || "expected NOT #{expected.inspect}, got #{actual.inspect}"
    end

    def assert_nil(actual, message = nil)
      Console::Test.record actual.nil?,
                           message || "expected nil, got #{actual.inspect}"
    end

    def assert_not_nil(actual, message = nil)
      Console::Test.record !actual.nil?, message || 'expected non-nil'
    end

    def assert_includes(collection, member, message = nil)
      ok = collection.include? member
      Console::Test.record ok,
                           message || "expected #{collection.inspect} to include #{member.inspect}"
    end

    def refute_includes(collection, member, message = nil)
      ok = !collection.include?(member)
      Console::Test.record ok,
                           message || "expected #{collection.inspect} NOT to include #{member.inspect}"
    end

    def assert_between(value, low, high, message = nil)
      ok = value >= low && value <= high
      Console::Test.record ok, message || "expected #{value} to be within #{low}..#{high}"
    end

    def assert_raises(message = nil)
      raised = false
      begin
        yield
      rescue
        raised = true
      end
      Console::Test.record raised, message || 'expected the block to raise'
    end

    # --- running ----------------------------------------------------------

    def self.passes
      @passes ||= 0
    end

    def self.total
      @total ||= 0
    end

    def self.failures
      @failures ||= []
    end

    def self.record(ok, message)
      @passes = passes + (ok ? 1 : 0)
      @total = total + 1
      failures << "[#{@current_suite}##{@current_test}] #{message}" unless ok
      ok
    end

    # Run every registered suite. Returns a summary Hash.
    def self.run(args = nil)
      @passes = 0
      @total = 0
      @failures = []

      registry.each do |entry|
        klass = entry[0]
        name = entry[1]
        block = entry[2]
        @current_suite = klass.to_s
        @current_test = name
        begin
          instance = klass.new
          instance.setup if instance.respond_to?(:setup)
          instance.instance_eval(&block)
        rescue => e
          @total += 1
          @failures << "[#{klass}##{name}] raised #{e.class}: #{e.message}"
        end
      end

      report
    end

    def self.report
      status = @failures.size == 0 ? 'PASS' : 'FAIL'
      puts ''
      puts '=' * 62
      if status == 'PASS'
        puts "TEST RESULT: PASS (#{registry.size} tests, #{@passes} assertions)"
      else
        puts "TEST RESULT: FAIL (#{@failures.size} failures, #{@passes} passed of #{@total} assertions)"
        @failures.each { |f| puts "  x #{f}" }
      end
      puts '=' * 62
      {
        status: status,
        passes: @passes,
        failures: @failures.size,
        total: @total,
        tests: registry.size
      }
    end

    # One line for a CI script to grep.
    def self.summary_line(summary)
      "CONSOLE_TEST_STATUS=#{summary[:status]} " \
        "TESTS=#{summary[:tests]} " \
        "ASSERTIONS=#{summary[:total]} " \
        "FAILURES=#{summary[:failures]}"
    end
  end
end