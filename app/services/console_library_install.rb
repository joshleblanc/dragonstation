require "fileutils"
require "securerandom"

# Install a console library from an uploaded ZIP, as a version that did not
# exist before.
#
# This is the screen-side counterpart to `bin/rails console:install`, and it is
# deliberately more restricted than that task in one direction and equal to it
# in every other. What it will not do is touch an installed version:
#
#   * a cartridge is pinned to its console version forever, and pinning is the
#     only thing that makes two leaderboard runs comparable. Overwriting
#     vendor/console/0.1.0/ would change the code every cartridge on 0.1.0
#     runs while leaving the version row -- and therefore every pin, and every
#     pin in the UI -- exactly as it was. Nothing would look wrong. The scores
#     would just stop meaning anything;
#   * so a version that is already installed is refused by name, and the way to
#     ship a change is to bump the version in app/console/version.rb. The
#     archive carries its own version number, so it cannot disagree with the
#     directory it lands in.
#
# Everything else is the same validation the rake task performs, run through the
# same ConsoleLibrary reader, so a library that installs here is a library
# `console:status` will call ok.
#
# The files land in the repository rather than in a blob, which is what keeps an
# upload reviewable: `git status` shows the new directory, and the diff that
# installs a new version is the diff that introduced it.
class ConsoleLibraryInstall
  class Invalid < SafeArchive::Rejected; end

  include SafeArchive

  # The version ConsoleVersion requires, and ConsoleLibrary only uses the
  # version it is given to build a default path -- which this call overrides.
  # The archive's own version.rb is read separately, below.
  PLACEHOLDER_VERSION = "0.0.0".freeze

  VERSION_FORMAT = /\A\d+\.\d+\.\d+\z/.freeze

  # Every require line app/main.rb writes, not just the ones ConsoleLibrary will
  # act on.
  #
  # ConsoleLibrary::REQUIRE_PATTERN only matches requires under app/console/,
  # so a require of app/secrets.rb is *silently dropped*: it is not served, and
  # not refused either. The library would install happily and every cartridge on
  # it would boot and then fail on a module the served tree does not contain.
  # Reading the whole require list is what turns that into an upload error.
  REQUIRE = /^require\s+'([^']+)'\s*$/.freeze

  # What app/main.rb is allowed to pull into the served tree.
  #
  # ConsoleLibrary reads the require list out of app/main.rb and serves exactly
  # those modules, so that list is the only thing standing between an admin
  # upload and the content every pinned cartridge serves. It is worth being
  # precise about the harm, because it is not obvious: a require of
  # 'app/console/payload.html' is served by CartridgeRuntimeController through
  # Marcel as text/html, from this origin, to anyone who loads the game. The
  # .rb extension is not a formality -- it is the difference between code the
  # engine loads and markup the browser renders.
  ALLOWED_MODULE = %r{\Aapp/console/[\w.-]+\.rb\z}.freeze

  attr_reader :archive, :title, :notes

  def initialize(archive:, title: nil, notes: nil)
    @archive = archive
    @title = title
    @notes = notes
  end

  def call
    entries = read_entries
    tree = locate_library(entries)
    staged = stage(tree)

    begin
      publish(staged, validate(staged))
    ensure
      # A no-op once the directory has been renamed into place.
      FileUtils.rm_rf(staged)
    end
  end

  # Whether a directory is a library this app can install, and under what
  # version. Returns [version_or_nil, problems].
  #
  # Both install paths ask this. The upload asks it about a directory that
  # arrived as an archive; `bin/rails console:install` asks it about one that
  # arrived by git. Same questions and the same answers either way, so a
  # library is never accepted through the repository and refused through the
  # browser, or the reverse.
  #
  # It deliberately does *not* ask whether the version is already installed.
  # That is an update rule, and the task that registers a checkout's own
  # libraries must stay idempotent.
  def self.inspect(directory)
    probe = ConsoleLibrary.new(PLACEHOLDER_VERSION, directory: Pathname.new(directory))

    problems = module_problems(probe)
    declared = declared_version(probe)

    if declared.blank?
      problems << "#{ConsoleLibrary::MODULE_PREFIX}version.rb is missing or has no MAJOR/MINOR/PATCH " \
                  "constants, so there is no version to install this as"
    elsif !VERSION_FORMAT.match?(declared)
      problems << "#{declared.inspect} is not a version I can use. It must be MAJOR.MINOR.PATCH, " \
                  "like 0.2.0 -- that string is the directory name and the label every cartridge " \
                  "pinned to it is shown."
    end

    [ declared, problems ]
  end

  private
    def archive_subject = "console library"

    # The library files, whether the archive wraps them in a directory or is the
    # directory itself -- the same two shapes a cart upload accepts, because
    # both are made by zipping a folder.
    def locate_library(entries)
      tops = entries.keys.map { |path| path.split("/").first }.uniq
      wrapped = tops.select { |top| entries.keys.any? { |path| path.start_with?("#{top}/app/") } }

      if wrapped.size > 1
        reject!("archive contains more than one console library: #{wrapped.sort.join(", ")}")
      end

      return strip_prefix(entries, "#{wrapped.first}/") if wrapped.size == 1
      return entries if entries.keys.any? { |path| path.start_with?("app/") }

      reject!(
        "no console library found. Expected a directory containing " \
        "#{ConsoleLibrary::ENTRY_TEMPLATE}, or an archive of one library's files."
      )
    end

    def strip_prefix(entries, prefix)
      entries
        .select { |path, _| path.start_with?(prefix) }
        .to_h { |path, bytes| [ path.delete_prefix(prefix), bytes ] }
    end

    # Write the candidate tree beside its final home so that publishing is a
    # rename within one directory rather than a copy across filesystems.
    #
    # Dot-prefixed so `console:install`, which scans this directory, walks past
    # anything left behind by an install that died mid-flight.
    def stage(entries)
      FileUtils.mkdir_p(ConsoleLibrary.root)
      staged = ConsoleLibrary.root.join(".incoming-#{SecureRandom.hex(8)}")
      FileUtils.mkdir_p(staged)

      entries.each do |relative, bytes|
        path = staged.join(relative)
        FileUtils.mkdir_p(path.dirname)
        File.binwrite(path, bytes)
      end

      staged
    end

    # Everything wrong with the archive, collected before anything is refused, so
    # one upload produces one list rather than one error per attempt.
    def validate(staged)
      declared, problems = self.class.inspect(staged)

      # The update rule only applies once the library itself is sound; there is
      # no point telling someone 0.2.0 is taken when the real problem is that
      # the archive is not a library.
      problems = problems.dup
      problems.concat(occupancy_problems(declared)) if problems.empty?

      raise Invalid, problems if problems.any?

      declared
    end

  # The checks behind `inspect`. They take a probe and no state of their own,
  # so they live on the class rather than on an instance that would have to be
  # built with an archive it never reads.
  def self.declared_version(probe)
    probe.declared_version
  rescue ConsoleLibrary::Missing
    nil
  end

  def self.module_problems(probe)
    unless probe.available?
      return [ "there is no #{ConsoleLibrary::ENTRY_TEMPLATE}. That file is the require list " \
               "the library travels with, and a version without it serves nothing." ]
    end

    required = probe.entry_source.scan(REQUIRE).flatten
    served = probe.require_paths

    problems = []

    if required.empty?
      problems << "#{ConsoleLibrary::ENTRY_TEMPLATE} requires nothing under #{ConsoleLibrary::MODULE_PREFIX}, " \
                  "so there is no library in this archive."
    end

    required.each do |path|
      if !path.start_with?(ConsoleLibrary::MODULE_PREFIX)
        problems << "#{ConsoleLibrary::ENTRY_TEMPLATE} requires #{path}, which is not under " \
                    "#{ConsoleLibrary::MODULE_PREFIX}. Only modules in that directory travel with a " \
                    "cartridge, so this require would be missing at runtime and every game on this " \
                    "version would fail to boot."
      elsif !ALLOWED_MODULE.match?(path)
        problems << "#{ConsoleLibrary::ENTRY_TEMPLATE} requires #{path}. Only .rb modules directly " \
                    "under #{ConsoleLibrary::MODULE_PREFIX} can be added, because this require list " \
                    "is exactly what gets served to the browser for every cartridge pinned to the version."
      end
    end

    served.each do |path|
      problems << "#{ConsoleLibrary::ENTRY_TEMPLATE} requires #{path}, which is not present. It is " \
                  "is missing from the library. A missing module is a cartridge that boots and then fails." unless probe.file?(path)
    end

    problems.uniq
  end

  # The rule that makes this an install rather than an update.
  private
    def occupancy_problems(version)
      problems = []

      if ConsoleVersion.exists?(version: version)
        problems << "console #{version} is already installed. Cartridges are pinned to the version they " \
                    "were uploaded against and are never moved, so an installed version is never " \
                    "replaced. Bump MAJOR/MINOR/PATCH in app/console/version.rb and upload again."
      end

      if ConsoleLibrary.root.join(version).directory?
        problems << "#{ConsoleLibrary.root.join(version).relative_path_from(Rails.root)} already exists. " \
                    "Remove or rename it before installing #{version}."
      end

      problems
    end

    def publish(staged, version)
      target = ConsoleLibrary.root.join(version)

      FileUtils.mv(staged.to_s, target.to_s)

      begin
        ConsoleVersion.create!(
          version: version,
          title: title.presence || "Console #{version}",
          notes: notes.presence || "Installed from an uploaded ZIP."
        )
      rescue StandardError
        # The row is what makes the version selectable; without it the directory
        # is invisible to everything except `console:install`, which would later
        # adopt it under a label nobody chose. Put it back rather than leave
        # that behind.
        FileUtils.mv(target.to_s, staged.to_s)
        raise
      end

      ConsoleVersion.find_by!(version: version)
    end
end
