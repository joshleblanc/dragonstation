# What a console release is: the files that make up a console, as opposed to
# what a machine that develops one happens to have lying around.
#
# Two places need this answer and they used to keep it separately, which is how
# they came to disagree. `LibraryBundle` builds a download out of a stored
# library; `ConsoleLibraryInstall` reads a checkout. Both were "the console", and
# a checkout installed through the rake task picked up whatever else was in the
# directory -- 294 files of `builds/` output and somebody's finished cart under
# `carts/`, 104MB against the 3.9MB a release actually is. So the list lives here
# and both read it.
#
# The list is an allowlist, not a denylist, for the same reason
# `bin/publish-console` names its contents explicitly: adding a file to the
# console should be a decision, not something that starts shipping to every
# reader because nobody remembered to exclude it. It is also what keeps
# `dragonstation.json` -- a live API key, gitignored but sitting right there in
# the checkout -- out of the stored library, where it has no business being.
class ConsoleRelease
  # Whole directories, walked as they are.
  #
  # app/ rather than the require list, deliberately: the runtime serves exactly
  # what app/main.rb requires, but a *console* should carry its source, so a
  # module that exists but is not yet required still arrives.
  DIRECTORIES = %w[app bin sprites metadata].freeze

  # Individual files, named rather than walked.
  #
  # errors/ is here as its readme and not as a directory: errors/last.txt is
  # written by whichever cart crashed last, and a release should not ship
  # somebody else's crash. shots/ is written by --shot and is not a release at
  # all.
  FILES = %w[
    font.ttf
    tiny.ttf
    README.md
    .gitignore
    .gitattributes
    errors/readme.txt
    carts/README.md
  ].freeze

  # Releasing a new console version is an administrator's job, and the script
  # that does it is only in an administrator's bundle.
  #
  # It lives in the console repository like any other script -- one copy, not one
  # per download -- and is held back rather than shipped to everyone, both
  # because handing out an admin capability to every reader is noise, and because
  # the public download is what `./update-library` pulls.
  #
  # Nothing here is the control: `/api/console_versions` resolves the key to its
  # owner and refuses anybody who is not an admin. This is the convenience.
  #
  # Still part of the release, so it is stored with the version and an
  # administrator's bundle can hand it back out.
  RELEASE_SCRIPTS = %w[bin/publish-console bin/publish-console.bat].freeze

  # Every path in a release, out of a set of known paths.
  #
  # This includes RELEASE_SCRIPTS: they are part of a console, and withholding
  # them is `LibraryBundle`'s decision about a *download*, not a fact about what
  # a release is.
  def self.paths(paths)
    found = DIRECTORIES.flat_map { |dir| under(paths, dir) } + FILES

    found.select { |path| paths.include?(path) }.uniq.sort.freeze
  end

  # The same answer, from a directory rather than from a set of paths.
  #
  # Walks only DIRECTORIES and stats only FILES. Dotfiles do not turn up in the
  # walk, which is why FILES names .gitignore and .gitattributes explicitly.
  def self.paths_on_disk(directory)
    directory = Pathname.new(directory.to_s)

    walked = DIRECTORIES.flat_map do |dir|
      Dir.glob("#{dir}/**/*", base: directory).select { |path| (directory + path).file? }
    end

    found = walked + FILES.select { |path| (directory + path).file? }

    found.uniq.sort.freeze
  end

  def self.under(paths, directory)
    prefix = "#{directory}/"

    paths.select { |path| path.start_with?(prefix) }
  end
  private_class_method :under
end
