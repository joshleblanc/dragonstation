# Install a console library from a checkout, as a selectable version.
#
#   bin/rails console:install CONSOLE_PATH=~/dev/dragonruby/console
#   bin/rails console:install CONSOLE_PATH=~/dev/dragonruby/console DEFAULT=true
#   bin/rails console:install CONSOLE_PATH=~/dev/dragonruby/console FORCE=true
#
# This registers libraries that arrived by git. There is also an upload screen
# at /admin/console_versions/new, which is the same install for a library that
# arrives as a ZIP from a browser.
#
# They share ConsoleLibraryInstall.inspect, so the two paths ask the same
# questions and accept the same libraries -- there is no way to slip a library
# past the task that the screen would refuse, or the reverse. What the screen
# will not do, and this task can, is *replace* nothing: registering a version
# that is already installed is idempotent here, while an upload naming an
# installed version is refused outright. Either way the bytes behind an
# installed version are never rewritten in place, because a cartridge is pinned
# to them forever.
#
# The version is read from the library's own app/console/version.rb. A checkout
# that says it is 0.2.0 while being offered as 0.1.0 is refused rather than
# installed under the wrong label -- every cartridge pinned to that label would
# then be pinned to something nobody could name.
#
# The library used to live in vendor/console/<version>/ and this task scanned
# for it there. It is in storage now, so CONSOLE_PATH names the checkout to
# read. Nothing is written to the repository.
#
# CONSOLE_PATH, and not PATH: PATH is the shell's own, and reading it here meant
# a bare `console:install` expanded the entire environment PATH and reported a
# missing directory named after every binary on the machine. The test helpers
# already used CONSOLE_PATH to find the same checkout.
namespace :console do
  desc "Install a console library from a checkout (CONSOLE_PATH=/path/to/console)"
  task install: :environment do
    path = ENV["CONSOLE_PATH"].presence
    make_default = ActiveModel::Type::Boolean.new.cast(ENV.fetch("DEFAULT", "false"))
    force = ActiveModel::Type::Boolean.new.cast(ENV.fetch("FORCE", "false"))

    abort "console: no CONSOLE_PATH given. Run: bin/rails console:install CONSOLE_PATH=/path/to/console" if path.nil?

    directory = Pathname.new(File.expand_path(path))

    unless directory.directory?
      abort "console: no directory at #{directory}"
    end

    declared, problems = ConsoleLibraryInstall.inspect(directory)

    if problems.any?
      abort "console: #{directory} is not a console library I can install --\nconsole:        " \
            "#{problems.join("\nconsole:        ")}"
    end

    installed = ConsoleVersion.find_by(version: declared)

    if installed.nil?
      install_new(directory, declared, make_default: make_default)
    elsif !installed.available?
      restore_unreadable(directory, installed, make_default: make_default)
    else
      adopt(installed, directory, declared, make_default: make_default, force: force)
    end
  end

  desc "Report which console versions are installed and usable"
  task status: :environment do
    versions = ConsoleVersion.order(:version)

    if versions.empty?
      puts "console: none installed. Run: bin/rails console:install CONSOLE_PATH=/path/to/console"
    else
      versions.each do |v|
        state =
          if !v.available?            then "MISSING library files"
          elsif !v.library.label_matches_contents? then "MISLABELLED (declares #{v.library.declared_version})"
          else "ok -- #{v.library.require_paths.size} modules"
          end
        puts format("console: %-8s %-12s %s", v.version, v.default? ? "[default]" : "", state)
      end
    end
  end

  # A version that cannot be read: the row is there and nothing is behind it.
  #
  # Two shapes reach here, and they are the same state as far as anything that
  # reads the library is concerned. Either the install never wrote its file rows,
  # or it did and the blobs are on a service this process cannot fetch them from
  # -- a deploy that changed ACTIVE_STORAGE_SERVICE and came up on a fresh
  # container, which is exactly what lib/tasks/active_storage.rake describes. The
  # second is the one that used to fall through to adopt, which reported
  # "already installed" for a version that serves nothing and then died reading
  # it. So the test is whether the library can be read, not how many rows it has.
  #
  # Its own branch rather than the adopt one, because adopting is exactly the
  # wrong verb -- it registers a label and moves on, which would leave the row
  # serving nothing while reporting success. FORCE does not apply either: FORCE
  # means "adopt the row as it is", and as it is, it is unreadable.
  def restore_unreadable(directory, installed, make_default:)
    # Reloaded, because asking whether the version was readable above built the
    # library that answered no, and that object still holds the file list it read
    # then. ConsoleVersion#reload exists for exactly this: the repair happens
    # behind the row, and every holder of the object has to see the version it
    # just became.
    console_version = ConsoleLibraryInstall.restore!(directory, installed).reload

    console_version.update!(
      title: "Console #{console_version.version}",
      notes: "Restored from #{directory}."
    )
    apply_default(console_version, make_default)

    puts "console: #{console_version.version} was installed but could not be read, and " \
         "served nothing. Filled in from #{directory}."
    puts "console: #{console_version.library.require_paths.size} modules, " \
         "fonts: #{console_version.library.fonts.join(', ')}" \
         "#{console_version.default? ? ' [default]' : ''}"

    console_version
  end

  def install_new(directory, declared, make_default:)
    console_version = ConsoleLibraryInstall.install!(directory, title: "Console #{declared}")

    apply_default(console_version, make_default)

    library = console_version.library
    puts "console: installed #{declared} " \
         "(#{library.require_paths.size} modules, fonts: #{library.fonts.join(', ')})" \
         "#{console_version.default? ? ' [default]' : ''}"
    console_version
  end

  # Re-registering the version that is already there is a no-op, which is
  # what makes this task safe to run on every deploy. The files are not
  # rewritten either way -- FORCE says *adopt* the row, not *replace* the
  # blobs, because replacing them is the thing pinning exists to prevent.
  def adopt(installed, directory, declared, make_default:, force:)
    installed.title = "Console #{declared}"
    installed.notes = "Installed from #{directory}."
    installed.default = true if make_default
    installed.save!

    puts "console: #{declared} is already installed (#{installed.console_library_files.count} files)"
    puts "console: NOT rewritten. To change #{declared}, bump MAJOR/MINOR/PATCH in " \
         "app/console/version.rb and install that instead."

    # The one thing worth stopping for: the row's label and the bytes behind it
    # disagreeing. Every cartridge pinned to the label would then run code that
    # says it is something else. The files hang off the row, so this is a
    # broken install rather than a normal state -- but it is exactly the drift
    # pinning cannot catch, because pinning is what preserved it.
    #
    # This compares the row's *label* against what the stored library declares.
    # Comparing the checkout's declared version against the installed library's
    # would compare a number with itself and fire on every run, which is what
    # used to happen: the task aborted on its own idempotent re-run, and so
    # could never be the deploy step it is documented to be.
    unless installed.library.label_matches_contents? || force
      abort "console: #{declared} is labelled #{installed.version} but its stored files " \
            "declare #{installed.library.declared_version}. The row and the library " \
            "disagree, and every cartridge pinned to #{installed.version} runs them. " \
            "Re-run with FORCE=true to adopt the row as it is."
    end

    installed
  end

  # One default, cleared everywhere else in the same transaction so two
  # defaults can never race into being true.
  def apply_default(console_version, make_default)
    return unless make_default

    ConsoleVersion.where(default: true).where.not(id: console_version.id).update_all(default: false)
    console_version.update!(default: true)
  end
end
