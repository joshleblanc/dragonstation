# Install a vendored console library as a selectable version.
#
#   bin/rails console:install                # every library under vendor/console
#   bin/rails console:install VERSION=0.1.0   # just one
#   bin/rails console:install VERSION=0.1.0 DEFAULT=true
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
# installed version is refused outright. Either way the bytes under
# vendor/console/<version>/ are never rewritten in place, because a cartridge
# is pinned to them forever.
#
# The version is read from the library's own app/console/version.rb and checked
# against the directory name. A directory that says it is 0.2.0 while living at
# 0.1.0 is refused rather than installed under the wrong label -- every
# cartridge pinned to that label would then be pinned to something nobody could
# name.
namespace :console do
  desc "Register vendored console libraries under vendor/console"
  task install: :environment do
    root = ConsoleLibrary.root
    requested = ENV["VERSION"].presence
    make_default = ActiveModel::Type::Boolean.new.cast(ENV.fetch("DEFAULT", "false"))

    abort "console: no vendor/console directory at #{root}" unless root.directory?

    directories =
      if requested
        [ root.join(requested) ]
      else
        # Dot-prefixed directories are an install staging itself; they are not
        # libraries, and one left behind by an interrupted upload must not be
        # mistaken for one.
        root.children.select { |child| child.directory? && !child.basename.to_s.start_with?(".") }
      end

    if directories.empty?
      abort "console: nothing to install. Put a library under #{root}/<version>/ first."
    end

    skipped = []

    directories.sort_by { |d| d.basename.to_s }.each do |directory|
      label = directory.basename.to_s
      declared, problems = ConsoleLibraryInstall.inspect(directory)

      # A library that is not a library is skipped rather than fatal, so one bad
      # directory does not stop the rest of a checkout registering. It still
      # fails the task at the end, because a silent skip reads as success.
      if problems.any?
        skipped << label
        warn "console: SKIP #{label} -- #{problems.join("\nconsole:        ")}"
        next
      end

      if declared != label
        abort "console: ABORT #{label} declares itself #{declared}. " \
              "Rename the directory to #{declared}, or fix version.rb."
      end

      record = ConsoleVersion.find_or_initialize_by(version: declared)
      record.title ||= "Console #{declared}"
      record.notes = "Installed from #{directory.relative_path_from(Rails.root)}."
      record.default = true if make_default
      record.save!

      modules = ConsoleLibrary.new(record).require_paths.size

      puts "console: installed #{declared} (#{modules} modules, " \
           "fonts: #{ConsoleLibrary.new(record).fonts.join(', ')})" \
           "#{record.default? ? ' [default]' : ''}"
    end

    unless skipped.empty?
      abort "console: #{skipped.size} #{skipped.size == 1 ? 'directory' : 'directories'} " \
            "skipped (#{skipped.join(', ')}). Nothing was registered for " \
            "#{skipped.size == 1 ? 'it' : 'them'}."
    end
  end

  desc "Report which console versions are installed and usable"
  task status: :environment do
    versions = ConsoleVersion.order(:version)

    if versions.empty?
      puts "console: none installed. Run: bin/rails console:install"
    else
      versions.each do |v|
        state =
          if !v.available?            then "MISSING library directory"
          elsif !v.library.label_matches_contents? then "MISLABELLED (declares #{v.library.declared_version})"
          else "ok -- #{v.library.require_paths.size} modules"
          end
        puts format("console: %-8s %-12s %s", v.version, v.default? ? "[default]" : "", state)
      end
    end
  end
end
