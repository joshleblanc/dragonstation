# rubyzip is a transitive dependency of activestorage, which only requires it
# lazily. Without this line Zip is defined in tests (the helpers require it)
# and undefined in production -- a 500 on the first real upload.
require "zip"

# Reading an uploaded ZIP without letting it name anything outside the
# directory it lands in. Both upload paths -- carts and console libraries --
# go through here, so the traversal guard exists exactly once:
#
#   * no absolute paths, '..' segments, backslash spellings, or NUL bytes;
#   * no symlinks;
#   * a ceiling on file count, expanded size and compression ratio.
#
# rubyzip never *writes* a symlink entry, so these refusals are reachable only
# by archives from other tools -- which is exactly why they must hold alone.
#
# Includers supply `archive` (an IO), an `Invalid < SafeArchive::Rejected`
# class, and `archive_subject` for messages ("cart", "console library").
module SafeArchive
  class Rejected < StandardError
    attr_reader :problems

    def initialize(problems)
      @problems = Array(problems)
      super(@problems.join("\n"))
    end
  end

  MAX_FILES = 512
  MAX_TOTAL_BYTES = 32 * 1024 * 1024
  # A .rb full of comments compresses a long way, so this leaves room for text.
  MAX_COMPRESSION_RATIO = 200

  private
    def reject!(message)
      raise self.class::Invalid, message
    end

    # Every file in the archive as relative path => bytes, refusals applied.
    def read_entries
      entries = {}
      total = 0

      with_zip do |zip|
        zip.each do |entry|
          next if entry.directory?

          path = safe_path(entry.name)
          reject!("archive contains a symbolic link: #{entry.name}") if symlink?(entry)

          bytes = entry.get_input_stream(&:read)
          total += bytes.bytesize
          check_budget!(entries.size, path, entry, bytes, total)
          entries[path] = bytes
        end
      end

      reject!("archive is empty") if entries.empty?
      entries
    end

    # Behind a method so a test can supply an entry rubyzip will not produce.
    def with_zip(&block)
      Zip::File.open_buffer(StringIO.new(archive.read), &block)
    rescue Zip::Error => e
      reject!("could not read the archive: #{e.message}")
    end

    def safe_path(name)
      reject!("archive contains an absolute path: #{name}") if name.start_with?("/", "\\")
      reject!("archive contains a null byte in a path") if name.include?("\0")

      segments = name.tr("\\", "/").split("/").reject { |s| s.empty? || s == "." }
      reject!("archive contains a path that escapes the #{archive_subject}: #{name}") if segments.include?("..")

      segments.join("/")
    end

    def symlink?(entry)
      entry.respond_to?(:symlink?) ? entry.symlink? : entry.ftype == :symlink
    end

    def check_budget!(count, path, entry, bytes, total)
      reject!("archive has more than #{MAX_FILES} files") if count >= MAX_FILES

      compressed = entry.compressed_size.to_i
      if compressed.positive? && bytes.bytesize / compressed > MAX_COMPRESSION_RATIO
        reject!("#{path} expands #{MAX_COMPRESSION_RATIO}x beyond its compressed size")
      end

      reject!("archive expands beyond #{MAX_TOTAL_BYTES / 1024 / 1024}MB") if total > MAX_TOTAL_BYTES
    end

    # [directory name or nil, entries relative to it].
    #
    # Zipping a folder and zipping its contents are both normal, so the archive
    # may wrap the tree in one directory or be the tree. Anything beside that
    # directory (a README, a .gitignore) is packaging noise and is dropped.
    def unwrap(entries)
      wrapped = entries.keys.map { |path| path.split("/").first }.uniq
        .select { |top| entries.keys.any? { |path| path.start_with?("#{top}/app/") } }

      if wrapped.size > 1
        reject!("archive contains more than one #{archive_subject}: #{wrapped.sort.join(', ')}")
      end

      if (top = wrapped.first)
        prefix = "#{top}/"
        return [ top, entries.filter_map { |path, bytes| [ path.delete_prefix(prefix), bytes ] if path.start_with?(prefix) }.to_h ]
      end

      return [ nil, entries ] if entries.keys.any? { |path| path.start_with?("app/") }

      reject!("no #{archive_subject} found. Expected a directory containing app/main.rb, " \
              "or an archive of one #{archive_subject}'s files.")
    end
end
