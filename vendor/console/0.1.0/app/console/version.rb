# Console::Version -- kept separate so the version string is in exactly one
# place and can be asserted against by the self test.
module Console
  module Version
    MAJOR = 0
    MINOR = 1
    PATCH = 0
    STRING = "#{MAJOR}.#{MINOR}.#{PATCH}"

    # The DragonRuby runtime this was verified against.
    DRAGONRUBY_TARGET = '7.21'

    def self.to_s
      STRING
    end

    def self.full
      "console #{STRING} (targets DragonRuby #{DRAGONRUBY_TARGET})"
    end
  end
end