# rubyzip is a transitive dependency of activestorage, and Bundler.require only
# requires the gems named in the Gemfile -- not their dependencies. ActiveStorage
# requires zip lazily, deep inside archive analysis, which is a different code
# path from this one. So nothing else loads it: without this line, Zip is
# defined in the test process (the test helper requires it) and undefined
# everywhere else, which is a 500 on the first real upload and a green suite.
require "zip"

# Reading an uploaded ZIP without letting it name anything outside the
# directory it is meant to land in.
#
# Two things on this site take a ZIP from a browser and turn it into files on
# disk -- a cart upload and a console library install -- and both are protected
# by the same four rules:
#
#   * no absolute paths, no '..' segments, no backslash spellings of them, and
#     no NUL bytes, because a path that names somewhere else is not a path that
#     is being unpacked;
#   * no symlinks, for the same reason: a link is a name that points out of the
#     directory it was written into;
#   * a hard ceiling on file count, total expanded bytes and compression ratio,
#     so a small archive cannot fill the disk or the process's memory.
#
# They live here rather than in whichever service needed them first because a
# traversal guard written twice is a traversal guard that will eventually exist
# once. rubyzip 3.7 always writes ftype :file even when the symlink bit is set,
# so a hostile archive cannot be *built* through it -- these refusals are
# reachable only by archives from other tools, which is exactly why they have to
# hold on their own.
#
# An includer supplies two things: a reader called `archive`, and (optionally)
# an `Invalid` error class for refusals, so each service keeps the exception
# type it documents and its callers already rescue.
module SafeArchive
  class Rejected < StandardError
    attr_reader :problems

    def initialize(problems)
      @problems = Array(problems)
      super(@problems.join("\n"))
    end
  end

  # A file count ceiling well above a real library or cart, and well below the
  # number at which "this is a bomb" stops being a guess.
  MAX_FILES = 512

  MAX_TOTAL_BYTES = 32 * 1024 * 1024

  # A .rb full of comments compresses far past this, so the ratio has to leave
  # room for text before it means anything.
  MAX_COMPRESSION_RATIO = 200

  private
    # What the archive is a container *of*, for error messages. Overridden by
    # each includer so "escapes the cart" does not end up on a library.
    def archive_subject = "archive"

    # The error class refusals raise. Resolved per instance rather than lexically
    # so an includer's own Invalid is used, not this module's.
    def archive_rejection_class
      if self.class.const_defined?(:Invalid, false)
        self.class.const_get(:Invalid, false)
      else
        Rejected
      end
    end

    def reject!(message)
      raise archive_rejection_class, message
    end

    # Every file in the archive as relative path => bytes, with the refusal
    # rules already applied. Directory entries are skipped: an archive of a
    # directory tree carries them, and the files are what get written.
    def read_entries
      entries = {}

      with_zip do |zip|
        zip.each do |entry|
          next if entry.directory?

          path = safe_path(entry.name)
          reject!("archive contains a symbolic link: #{entry.name}") if symlink?(entry)

          bytes = entry.get_input_stream { |io| io.read }

          check_budget!(entries, path, entry, bytes)
          entries[path] = bytes
        end
      end

      reject!("archive is empty") if entries.empty?

      entries
    end

    # The archive reader, behind a method so a test can supply an entry rubyzip
    # will not produce. Takes no arguments: it reads the includer's `archive`,
    # which is what lets a test replace the whole reader with a stub.
    def with_zip(&block)
      Zip::File.open_buffer(StringIO.new(archive.read), &block)
    rescue Zip::Error => e
      reject!("could not read the archive: #{e.message}")
    end

    # The one path rule that matters for an archive: nothing may escape the
    # directory it was extracted into. Absolute paths, '..' segments and
    # backslashes are all the same attack wearing different clothes.
    def safe_path(name)
      reject!("archive contains an absolute path: #{name}") if name.start_with?("/", "\\")

      normalised = name.tr("\\", "/")
      segments = normalised.split("/").reject { |s| s.empty? || s == "." }

      if segments.any? { |s| s == ".." }
        reject!("archive contains a path that escapes the #{archive_subject}: #{name}")
      end

      reject!("archive contains a null byte in a path") if normalised =~ /\0/

      segments.join("/")
    end

    def symlink?(entry)
      entry.respond_to?(:symlink?) ? entry.symlink? : entry.ftype == :symlink
    rescue NoMethodError
      false
    end

    # The bomb checks, applied per file as it is read so the budget covers the
    # archive rather than only what survives it.
    def check_budget!(entries, path, entry, bytes)
      if entries.size >= MAX_FILES
        reject!("archive has more than #{MAX_FILES} files")
      end

      compressed = entry.compressed_size.to_i
      if compressed.positive? && bytes.bytesize / compressed > MAX_COMPRESSION_RATIO
        reject!("#{path} expands #{MAX_COMPRESSION_RATIO}x beyond its compressed size")
      end

      total = entries.values.sum(&:bytesize) + bytes.bytesize
      reject!("archive expands beyond #{MAX_TOTAL_BYTES / 1024 / 1024}MB") if total > MAX_TOTAL_BYTES
    end
end
