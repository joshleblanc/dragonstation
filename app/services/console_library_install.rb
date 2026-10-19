# Install a console library as a new version, from an uploaded ZIP (`call`),
# a checkout on disk (`install!`), or into a row whose files were lost
# (`restore!`). All three run the same `check`, so a library accepted through
# one is never refused through another.
#
# An installed version is never overwritten. Cartridges are pinned to their
# version forever, and rewriting the files behind 0.1.0 would change what every
# 0.1.0 cartridge runs while every pin still looked intact. To ship a change,
# bump app/console/version.rb.
class ConsoleLibraryInstall
  include SafeArchive

  class Invalid < SafeArchive::Rejected; end

  VERSION_FORMAT = /\A\d+\.\d+\.\d+\z/

  # Every require in app/main.rb -- not just the ones ConsoleLibrary serves,
  # which would silently drop a require outside app/console/ and ship a library
  # that fails at boot.
  REQUIRE = /^require\s+'([^']+)'\s*$/

  # What app/main.rb may pull into the served tree. The .rb is not a formality:
  # a required app/console/payload.html would be served as text/html from this
  # origin to everyone who loads a game.
  ALLOWED_MODULE = %r{\Aapp/console/[\w.-]+\.rb\z}

  attr_reader :archive, :title, :notes

  def initialize(archive:, title: nil, notes: nil)
    @archive = archive
    @title = title
    @notes = notes
  end

  def call
    _, tree = unwrap(read_entries)
    version = self.class.check!(tree)

    if ConsoleVersion.exists?(version: version)
      raise Invalid, "console #{version} is already installed. Cartridges are pinned to the version they " \
                     "were uploaded against and are never moved, so an installed version is never " \
                     "replaced. Bump MAJOR/MINOR/PATCH in app/console/version.rb and upload again."
    end

    self.class.publish(tree, version, title: title, notes: notes)
  end

  private def archive_subject = "console library"

  class << self
    # A checkout or path => bytes Hash, as a new version.
    def install!(source, title: nil, notes: nil)
      tree = entries_for(source)
      publish(tree, check!(tree), title: title, notes: notes)
    end

    # Fill in a row whose files cannot be read: never written, or left behind
    # on a storage service this process cannot reach. The no-rewrite rule is
    # about bytes someone may have run, and an unreadable version served
    # nothing -- so this is the one case where writing behind a row is safe.
    # The files must still declare the row's own version.
    def restore!(source, console_version)
      tree = entries_for(source)
      declared, problems = check(tree)

      if declared.present? && declared != console_version.version
        problems << "these files declare #{declared}, but the row is labelled " \
                    "#{console_version.version}. Refusing to fill in a version whose label " \
                    "its contents disagree with."
      end
      raise Invalid, problems if problems.any?

      ConsoleVersion.transaction do
        # Stale rows point at missing blobs, and path is unique per version.
        console_version.console_library_files.destroy_all
        attach_files(console_version, tree)
      end
    end

    # [declared version or nil, problems]. Deliberately silent on whether the
    # version is taken: that is an upload rule, and the rake task must stay
    # idempotent.
    def check(source)
      probe = ConsoleLibrary.new("0.0.0", entries: entries_for(source))
      problems = module_problems(probe)
      declared = probe.declared_version

      if declared.blank?
        problems << "#{ConsoleLibrary::MODULE_PREFIX}version.rb is missing or has no MAJOR/MINOR/PATCH " \
                    "constants, so there is no version to install this as"
      elsif !VERSION_FORMAT.match?(declared)
        problems << "#{declared.inspect} is not a version I can use. It must be MAJOR.MINOR.PATCH, " \
                    "like 0.2.0 -- that string is the row every cartridge pinned to it is shown under."
      end

      [ declared, problems ]
    end

    def check!(tree)
      declared, problems = check(tree)
      raise Invalid, problems if problems.any?

      declared
    end

    # A checkout's release files as path => bytes. Only ConsoleRelease's
    # allowlist: a checkout also holds builds, screenshots, WIP carts and
    # dragonstation.json -- a live API key.
    def directory_entries(directory)
      directory = Pathname.new(directory.to_s)
      ConsoleRelease.paths_on_disk(directory).to_h { |path| [ path, (directory + path).binread ] }
    end

    def publish(tree, version, title: nil, notes: nil)
      ConsoleVersion.transaction do
        console_version = ConsoleVersion.create!(
          version: version,
          title: title.presence || "Console #{version}",
          notes: notes.presence || "Installed from an uploaded ZIP."
        )
        attach_files(console_version, tree)
      end
    end

    private
      def entries_for(source)
        source.is_a?(Hash) ? source : directory_entries(source)
      end

      def attach_files(console_version, tree)
        tree.sort.each do |path, bytes|
          file = console_version.console_library_files.create!(path: path, byte_size: bytes.bytesize)
          file.blob.attach(io: StringIO.new(bytes), filename: File.basename(path))
        end

        console_version
      end

      def module_problems(probe)
        entry = ConsoleLibrary::ENTRY_TEMPLATE
        prefix = ConsoleLibrary::MODULE_PREFIX

        unless probe.available?
          return [ "there is no #{entry}. That file is the require list " \
                   "the library travels with, and a version without it serves nothing." ]
        end

        required = probe.entry_source.scan(REQUIRE).flatten
        problems = []
        problems << "#{entry} requires nothing under #{prefix}, so there is no library in this archive." if required.empty?

        required.each do |path|
          if !path.start_with?(prefix)
            problems << "#{entry} requires #{path}, which is not under #{prefix}. Only modules in that " \
                        "directory travel with a cartridge, so this require would be missing at runtime " \
                        "and every game on this version would fail to boot."
          elsif !ALLOWED_MODULE.match?(path)
            problems << "#{entry} requires #{path}. Only .rb modules directly under #{prefix} can be " \
                        "added, because this require list is exactly what gets served to the browser " \
                        "for every cartridge pinned to the version."
          elsif !probe.file?(path)
            problems << "#{entry} requires #{path}, which is missing from the library. A missing " \
                        "module is a cartridge that boots and then fails."
          end
        end

        problems.uniq
      end
  end
end
