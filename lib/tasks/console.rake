# Install a console library from a checkout, as a selectable version.
#
#   bin/rails console:install CONSOLE_PATH=~/dev/dragonruby/console [DEFAULT=true] [FORCE=true]
#
# The same ConsoleLibraryInstall.check as the admin upload screen, so neither
# path accepts a library the other refuses. Unlike the screen, re-running for an
# installed version is a no-op rather than an error, which makes this safe on
# every deploy. Either way an installed version's bytes are never rewritten.
#
# CONSOLE_PATH, never PATH: that is the shell's, and reading it once reported a
# missing directory named after every binary on the machine.
module ConsoleTask
  module_function

  def say(message) = puts("console: #{message}")

  def summary(console_version)
    library = console_version.library
    "#{library.require_paths.size} modules, fonts: #{library.fonts.join(', ')}" \
      "#{' [default]' if console_version.default?}"
  end

  def install_new(directory, declared, make_default:)
    console_version = ConsoleLibraryInstall.install!(directory, title: "Console #{declared}")
    console_version.make_default! if make_default

    say "installed #{declared} (#{summary(console_version)})"
  end

  # The row exists but its bytes cannot be read -- never written, or left on a
  # storage service this process cannot reach. Adopting it would report success
  # for a version that serves nothing, so it is filled in instead.
  def restore(directory, installed, make_default:)
    # Reloaded: asking available? memoized the empty library.
    console_version = ConsoleLibraryInstall.restore!(directory, installed).reload
    console_version.update!(title: "Console #{console_version.version}", notes: "Restored from #{directory}.")
    console_version.make_default! if make_default

    say "#{console_version.version} was installed but could not be read, and served nothing. " \
        "Filled in from #{directory}."
    say summary(console_version)
  end

  # FORCE adopts the row as it is; it never replaces the blobs.
  def adopt(installed, directory, declared, make_default:, force:)
    installed.update!(title: "Console #{declared}", notes: "Installed from #{directory}.")
    installed.make_default! if make_default

    say "#{declared} is already installed (#{installed.console_library_files.count} files)"
    say "NOT rewritten. To change #{declared}, bump MAJOR/MINOR/PATCH in app/console/version.rb and install that instead."

    # The row's label against what its *stored* files declare. Comparing the
    # checkout against itself fired on every idempotent re-run.
    return if force || installed.library.label_matches_contents?

    abort "console: #{declared} is labelled #{installed.version} but its stored files " \
          "declare #{installed.library.declared_version}. The row and the library " \
          "disagree, and every cartridge pinned to #{installed.version} runs them. " \
          "Re-run with FORCE=true to adopt the row as it is."
  end
end

namespace :console do
  desc "Install a console library from a checkout (CONSOLE_PATH=/path/to/console)"
  task install: :environment do
    path = ENV["CONSOLE_PATH"].presence
    abort "console: no CONSOLE_PATH given. Run: bin/rails console:install CONSOLE_PATH=/path/to/console" unless path

    boolean = ActiveModel::Type::Boolean.new
    make_default = boolean.cast(ENV.fetch("DEFAULT", "false"))
    force = boolean.cast(ENV.fetch("FORCE", "false"))

    directory = Pathname.new(File.expand_path(path))
    abort "console: no directory at #{directory}" unless directory.directory?

    declared, problems = ConsoleLibraryInstall.check(directory)
    if problems.any?
      abort "console: #{directory} is not a console library I can install --\n" +
            problems.map { |p| "console:        #{p}" }.join("\n")
    end

    installed = ConsoleVersion.find_by(version: declared)

    if installed.nil?
      ConsoleTask.install_new(directory, declared, make_default: make_default)
    elsif !installed.available?
      ConsoleTask.restore(directory, installed, make_default: make_default)
    else
      ConsoleTask.adopt(installed, directory, declared, make_default: make_default, force: force)
    end
  end

  desc "Report which console versions are installed and usable"
  task status: :environment do
    versions = ConsoleVersion.order(:version)

    if versions.empty?
      ConsoleTask.say "none installed. Run: bin/rails console:install CONSOLE_PATH=/path/to/console"
    end

    versions.each do |v|
      state =
        if !v.available? then "MISSING library files"
        elsif !v.library.label_matches_contents? then "MISLABELLED (declares #{v.library.declared_version})"
        else "ok -- #{v.library.require_paths.size} modules"
        end
      puts format("console: %-8s %-12s %s", v.version, v.default? ? "[default]" : "", state)
    end
  end
end
