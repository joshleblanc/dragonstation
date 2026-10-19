# What a console release is, as opposed to what a machine developing one has
# lying around. Both the download (LibraryBundle) and the checkout install
# (ConsoleLibraryInstall) read this list; when they kept their own, a rake
# install stored 104MB of builds/ and WIP carts against a 3.9MB release.
#
# An allowlist, like bin/publish-console's: shipping a file should be a
# decision. It is also what keeps dragonstation.json -- a live API key sitting
# in the checkout -- out of the stored library.
class ConsoleRelease
  # Walked whole. app/ rather than the require list: a console carries its
  # source, including modules not required yet.
  DIRECTORIES = %w[app bin sprites metadata].freeze

  # Named, not walked. errors/last.txt is somebody's last crash, and shots/ is
  # --shot output; neither is a release.
  FILES = %w[
    font.ttf
    tiny.ttf
    README.md
    .gitignore
    .gitattributes
    errors/readme.txt
    carts/README.md
  ].freeze

  # Part of the release, but LibraryBundle only hands them to admins. That is a
  # courtesy, not the control: /api/console_versions checks the key's owner.
  RELEASE_SCRIPTS = %w[bin/publish-console bin/publish-console.bat].freeze

  # The release paths out of a set of known paths.
  def self.paths(paths)
    known = paths.to_set
    found = paths.select { |path| DIRECTORIES.any? { |dir| path.start_with?("#{dir}/") } }

    (found + FILES.select { |path| known.include?(path) }).uniq.sort.freeze
  end

  # The same answer from a directory on disk. Dir.glob skips dotfiles, which
  # is why FILES names them.
  def self.paths_on_disk(directory)
    directory = Pathname.new(directory.to_s)

    walked = DIRECTORIES.flat_map do |dir|
      Dir.glob("#{dir}/**/*", base: directory).select { |path| (directory + path).file? }
    end

    (walked + FILES.select { |path| (directory + path).file? }).uniq.sort.freeze
  end
end
