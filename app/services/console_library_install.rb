require "securerandom"

# Install a console library as a version that did not exist before.
#
# This is the screen-side counterpart to `bin/rails console:install`, and it is
# deliberately more restricted than that task in one direction and equal to it
# in every other. What it will not do is touch an installed version:
#
#   * a cartridge is pinned to its console version forever, and pinning is the
#     only thing that makes two leaderboard runs comparable. Overwriting the
#     files behind 0.1.0 would change the code every cartridge on 0.1.0 runs
#     while leaving the version row -- and therefore every pin, and every pin
#     in the UI -- exactly as it was. Nothing would look wrong. The scores would
#     just stop meaning anything;
#   * so a version that is already installed is refused by name, and the way to
#     ship a change is to bump the version in app/console/version.rb. The
#     archive carries its own version number, so it cannot disagree with the
#     label it is stored under.
#
# Everything else is the same validation the rake task performs, run through
# the same ConsoleLibrary reader, so a library that installs here is a library
# `console:status` will call ok.
#
# The bytes land in ActiveStorage, one blob per file, addressed by path through
# ConsoleLibraryFile. That is what makes the pinning above structural rather
# than a promise: the row owns the files, so there is no tree in the working
# copy for an upload to quietly overwrite and no way to edit a version's source
# without going through an install that refuses to run.
class ConsoleLibraryInstall
  class Invalid < SafeArchive::Rejected; end

  include SafeArchive

  # The version ConsoleVersion requires. ConsoleLibrary only uses the version it
  # is given to compare against what the library declares, and a candidate has
  # to be read before anything knows what that is -- so it is read under a
  # placeholder and the declared value replaces it below.
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

    publish(tree, validate(tree))
  end

  # Install a library from a checkout on disk, or from bytes already in hand.
  #
  # This is what `bin/rails console:install` calls. It refuses a library that is
  # already installed rather than adopting it, because the task asks first and
  # only calls this once it knows the version is free.
  def self.install!(source, title: nil, notes: nil)
    tree = source.is_a?(Hash) ? source : directory_entries(source)

    declared, problems = inspect(tree)

    raise Invalid, problems if problems.any?

    new(archive: nil, title: title, notes: notes).publish(tree, declared)
  end

  # A checkout's files as path => bytes, in the same shape read_entries returns
  # for an upload. The single definition of "a console on disk", used by both
  # inspection and installation so the two cannot disagree about what a checkout
  # contains.
  #
  # Only the release, and not the directory around it. A checkout is a console
  # plus whatever the person developing it has accumulated -- build output,
  # screenshots, the cart they are working on -- and reading all of it stored
  # 104MB where a release is 3.9MB. It also read `dragonstation.json`, a live
  # API key, into the library the site serves. ConsoleRelease is the allowlist;
  # see it for why it is an allowlist.
  def self.directory_entries(directory)
    directory = Pathname.new(directory.to_s)

    ConsoleRelease.paths_on_disk(directory).to_h do |path|
      [ path, (directory + path).binread ]
    end
  end

  # Whether these bytes are a library this app can install, and under what
  # version. Returns [version_or_nil, problems].
  #
  # Both install paths ask this. The upload asks it about an archive; the rake
  # task asks it about a checkout on disk. Same questions and the same answers
  # either way, so a library is never accepted through one and refused through
  # the other.
  #
  # It deliberately does *not* ask whether the version is already installed.
  # That is an update rule, and the task that registers a checkout's own
  # libraries must stay idempotent.
  #
  # `entries:` is path => bytes. A Pathname is read off the disk, because that
  # is the shape a checkout arrives in.
  def self.inspect(entries)
    tree =
      case entries
      when Hash then entries
      else
        directory = Pathname.new(entries.to_s)

        unless directory.directory?
          return [ nil, [ "#{directory} is not a directory." ] ]
        end

        directory_entries(directory)
      end

    probe = ConsoleLibrary.new(PLACEHOLDER_VERSION, entries: tree)

    problems = module_problems(probe)
    declared = declared_version(probe)

    if declared.blank?
      problems << "#{ConsoleLibrary::MODULE_PREFIX}version.rb is missing or has no MAJOR/MINOR/PATCH " \
                  "constants, so there is no version to install this as"
    elsif !VERSION_FORMAT.match?(declared)
      problems << "#{declared.inspect} is not a version I can use. It must be MAJOR.MINOR.PATCH, " \
                  "like 0.2.0 -- that string is the row every cartridge pinned to it is shown under."
    end

    [ declared, problems ]
  end

  # Store the library: the row first, then one blob per file beneath it.
  #
  # Public because it is the one step both install paths share -- `call` for an
  # archive, `install!` for a checkout -- and each reaches it with an explicit
  # receiver. It is also the whole reason those two paths cannot disagree.
  #
  # The row goes first because the files belong to it. If a blob fails to
  # attach the transaction rolls the row back and nothing is left behind --
  # the reverse order would leave an unusable version selectable.
  def publish(entries, version)
    ConsoleVersion.transaction do
      console_version = ConsoleVersion.create!(
        version: version,
        title: title.presence || "Console #{version}",
        notes: notes.presence || "Installed from an uploaded ZIP."
      )

      self.class.attach_files(console_version, entries)

      console_version
    end
  end

  # Put the files behind a row that exists but cannot be read.
  #
  # "No files" means no *readable* files, and there are two shapes of it: a row
  # the install never wrote file rows for, and a row whose rows are all present
  # and whose blobs are on a service this process cannot fetch them from -- a
  # migration from a directory the blobs had not been copied into yet, an
  # interrupted deploy, a deploy onto a fresh container while the blobs named a
  # disk that is not there. Every other path refuses to touch either, because the
  # one rule here is that the bytes behind an installed version are never
  # rewritten, and a cartridge pinned to it would run whatever turned up
  # afterwards.
  #
  # That rule is about the bytes. A row with no bytes has no bytes anybody has
  # ever run: there is no manifest, no served module, nothing that could have
  # been loaded. So filling it in cannot change what a cartridge runs -- it can
  # only turn a version that serves nothing into one that serves something. This
  # is the one case where the task repairs rather than adopts.
  #
  # The version these bytes declare still has to be the row's version. Anything
  # else would be the exact drift `label_matches_contents?` exists to catch,
  # created here instead of detected there.
  def self.restore!(source, console_version)
    entries = source.is_a?(Hash) ? source : directory_entries(source)

    declared, problems = inspect(entries)

    problems = problems.dup
    if declared.present? && declared != console_version.version
      problems << "these files declare #{declared}, but the row is labelled " \
                  "#{console_version.version}. Refusing to fill in a version whose label " \
                  "its contents disagree with."
    end

    raise Invalid, problems if problems.any?

    ConsoleVersion.transaction do
      # The rows a did-not-finish install left behind are not the library. They
      # point at blobs on a service that does not have them, or at nothing, and
      # path is unique per version, so they have to go before the real ones can
      # land. Destroying them changes nothing a cartridge could run: a version
      # that cannot be read serves no tree at all today, which is the same
      # argument that makes writing files here safe in the first place. Rolled
      # back with the attach if the attach fails.
      console_version.console_library_files.destroy_all

      attach_files(console_version, entries)
      console_version
    end
  end

  # One blob per file, on the row that owns them.
  #
  # Created rather than built on a relation: each file is attached with its own
  # blob, so this is one INSERT and one blob write per file.
  #
  # Public for the same reason `publish` is. Two call sites reach this -- the
  # instance method `publish` and the class method `restore!` -- and a private
  # class method would be reachable from only one of them.
  def self.attach_files(console_version, entries)
    entries.sort.each do |path, bytes|
      file = console_version.console_library_files.create!(path: path, byte_size: bytes.bytesize)
      file.blob.attach(io: StringIO.new(bytes), filename: File.basename(path))
    end

    console_version
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

    # Everything wrong with the library, collected before anything is refused, so
    # one upload produces one list rather than one error per attempt.
    #
    # The candidate is read straight from the bytes. There is nothing to stage
    # and nothing to clean up, because at this point no row and no blob exists.
    def validate(tree)
      declared, problems = self.class.inspect(tree)

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
  #
  # One check, not two. When the library was a directory it was worth asking
  # whether a directory for this version existed without a row for it -- a state
  # that could only be produced by hand, and which `console:install` would later
  # adopt under a label nobody chose. Storage has no such state: the files hang
  # off the row, so a version with files but no row is not reachable, and a row
  # with no files is simply a broken install rather than a separate hazard.
  def occupancy_problems(version)
    return [] unless ConsoleVersion.exists?(version: version)

    [ "console #{version} is already installed. Cartridges are pinned to the version they " \
      "were uploaded against and are never moved, so an installed version is never " \
      "replaced. Bump MAJOR/MINOR/PATCH in app/console/version.rb and upload again." ]
  end
end
