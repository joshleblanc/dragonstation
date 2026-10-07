# Install a vendored console library as a selectable version.
#
#   bin/rails console:install                # every library under vendor/console
#   bin/rails console:install VERSION=0.1.0   # just one
#   bin/rails console:install VERSION=0.1.0 DEFAULT=true
#
# This is the admin hook for "update the underlying console library", and it is
# deliberately a rake task rather than a screen. Installing a library means
# dropping a directory into the repository and running one command, which is
# reviewable and reversible; an upload endpoint that could replace the library
# every cartridge is pinned to would be a much worse way to do the same thing.
#
# The version is read from the library's own app/console/version.rb and
# checked against the directory name. A directory that says it is 0.2.0 while
# living at 0.1.0 is refused rather than installed under the wrong label --
# every cartridge pinned to that label would then be pinned to something
# nobody could name.
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
        root.children.select(&:directory?)
      end

    if directories.empty?
      abort "console: nothing to install. Put a library under #{root}/<version>/ first."
    end

    directories.sort_by { |d| d.basename.to_s }.each do |directory|
      version = directory.basename.to_s
      library = ConsoleLibrary.new(version)

      unless library.available?
        warn "console: SKIP #{version} -- no #{ConsoleLibrary::ENTRY_TEMPLATE}"
        next
      end

      declared = library.declared_version

      if declared.blank?
        warn "console: SKIP #{version} -- could not read a version out of app/console/version.rb"
        next
      end

      if declared != version
        abort "console: ABORT #{version} declares itself #{declared}. " \
              "Rename the directory to #{declared}, or fix version.rb."
      end

      record = ConsoleVersion.find_or_initialize_by(version: version)
      record.title ||= "Console #{version}"
      record.notes = "Installed from #{directory.relative_path_from(Rails.root)}."
      record.default = true if make_default
      record.save!

      puts "console: installed #{version} (#{library.require_paths.size} modules, " \
           "fonts: #{library.fonts.join(', ')})#{record.default? ? ' [default]' : ''}"
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
