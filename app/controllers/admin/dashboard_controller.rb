module Admin
  # What an operator needs to see at a glance, and nothing else.
  #
  # The counts are here because they answer the two questions that decide
  # whether anything else on this screen needs doing: is there a console version
  # a new upload would even be able to build against, and are the versions that
  # exist actually on disk.
  class DashboardController < BaseController
    def show
      @users = User.count
      @cartridges = Cartridge.count
      @published = Cartridge.published.count

      @versions = ConsoleVersion.default_first.to_a
      @unusable = @versions.reject(&:available?)
      @default = ConsoleVersion.default
    end
  end
end
