require "zip"

# The console, as a ZIP, for someone to keep and work in.
#
# Two shapes, and the difference is a secret:
#
#   library.zip   the library alone, and public
#   bundle.zip    the library plus the reader's API key, and theirs alone
#
# The library is public because the site already serves every byte of it to any
# browser that runs a cart -- it is in the manifest and in gamedata. Publishing
# a second copy behind a login would imply a restriction that does not exist,
# and would break `./update-library` in a terminal that has no session to log
# in with. The key is the opposite: it belongs to one account and is stored
# nowhere but here.
#
# **This is a working console, not just a library.** The first version shipped
# only what a browser needs to run a cart, which left the downloader with a
# directory of Ruby and nothing to run it with: no entry point, no scripts, no
# carts directory to put a cart in. So the ZIP is the console release -- the
# same tree the library is stored as -- and unpacking it over a checkout replaces
# the library in place.
class LibraryBundle
  # Where the console looks for its site credentials. Named after the site so
  # it is obvious what it is when it turns up in a git status.
  CREDENTIALS_PATH = "dragonstation.json"

  # Whole directories, walked as they are.
  #
  # app/ rather than the require list, deliberately: the runtime serves exactly
  # what app/main.rb requires, but a *console* should carry its source, so a
  # module that exists but is not yet required still arrives.
  RELEASE_DIRECTORIES = %w[app bin sprites metadata].freeze

  # Individual files, named rather than walked.
  #
  # errors/ is here as its readme and not as a directory: errors/last.txt is
  # written by whichever cart crashed last, and a download should not ship
  # somebody else's crash. shots/ is written by --shot and is not in the release
  # at all.
  RELEASE_FILES = %w[
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
  # per download -- and is held back here rather than shipped to everyone, both
  # because handing out an admin capability to every reader is noise, and because
  # the public download is what `./update-library` pulls, and a console that
  # grew a release tool should not grow one for people who cannot use it.
  #
  # Nothing here is the control: `/api/console_versions` resolves the key to its
  # owner and refuses anybody who is not an admin. This is the convenience.
  RELEASE_SCRIPTS = %w[bin/publish-console bin/publish-console.bat].freeze

  # Deliberately not a dotfile: a dotfile is invisible to `ls`, and this is the
  # first thing a reader should see in an unpacked console.
  attr_reader :library

  def initialize(console_version)
    @library =
      console_version.is_a?(ConsoleLibrary) ? console_version : ConsoleLibrary.new(console_version)
  end

  def console_version = library.console_version

  # Every file in the release, relative and forward-slashed.
  #
  # `release_tool:` adds the script only an administrator can use, and only if
  # the stored library actually has it -- an older release does not, and
  # a download that promised a file it could not read would be worse than one
  # without it.
  #
  # Sorted, so two downloads of the same version produce the same archive in the
  # same order -- which is what makes "did anything change?" a question with an
  # answer.
  def release_paths(release_tool: false)
    paths = @release_paths ||= base_release_paths

    # Only the ones this library actually has: an older release without the
    # batch file should still be given a working shell script.
    tool = RELEASE_SCRIPTS.select { |path| library.file?(path) }
    return paths if !release_tool || tool.empty?

    (paths + tool).sort.freeze
  end

  # The ZIP. `credentials:` is nil for the public library, or a Hash for the
  # reader's own bundle.
  #
  # The mode is stored, because a console whose scripts arrive non-executable is
  # a console that cannot be run: `unzip` restores it, and the Windows .bat files
  # are the path there anyway. A tool that ignores it leaves the reader running
  # `chmod +x bin/*` once, which the README says.
  def zip(release_tool: false, credentials: nil)
    buffer = Zip::OutputStream.write_buffer(::StringIO.new(+"".b)) do |zip|
      release_paths(release_tool: release_tool).each do |path|
        zip.put_next_entry(entry_for(path))
        zip.write(library.read(path))
      end

      if credentials
        zip.put_next_entry(entry_for(CREDENTIALS_PATH, mode: EXECUTABLE))
        zip.write(JSON.pretty_generate(credentials))
      end
    end

    buffer.rewind
    buffer
  end

  # What the console needs to publish a cart: where to send it, and the key
  # that says whose cart it is.
  #
  # Both URLs are absolute because the script that reads this has no idea where
  # the site lives -- it is a terminal in a checkout, not a page with a host.
  #
  # `admin:` is what the download key unlocks. The server checks it again on
  # every release; this is here so the console can say "you cannot do this"
  # before it builds a ZIP.
  def credentials(api_key:, site_url:, admin: false)
    credentials = {
      "console_version" => console_version.version,
      "api_key" => api_key,
      "publish_url" => File.join(site_url, "api/carts"),
      "site_url" => site_url,
      "issued_at" => Time.current.iso8601,
      "admin" => admin
    }

    credentials["release_url"] = File.join(site_url, "api/console_versions") if admin

    credentials
  end

  # What the download is called, so the browser saves it something useful.
  def filename = "console-#{console_version.version}.zip"

  private
    # Everything in the release, minus the release tool itself: that is the
    # public library, and the admin bundle is this plus one file.
    #
    # The release is the library's stored paths, not the require list: a
    # *console* should carry its source, so a module that exists but is not yet
    # required still arrives. Sorted so two downloads of the same version
    # produce the same archive in the same order.
    def base_release_paths
      (RELEASE_DIRECTORIES.flat_map { |dir| library.paths_under(dir) } + RELEASE_FILES - RELEASE_SCRIPTS)
        .select { |path| library.file?(path) }
        .uniq
        .sort
        .freeze
    end

    EXECUTABLE = 0o755
    PLAIN = 0o644

    # rubyzip has no public way to say "this entry is executable": it derives the
    # mode from the file the entry was written from, and every entry here is
    # written from memory. So the mode is set here, in the one place that knows
    # the ivar it lands in. Subclassed rather than poked at from outside so the
    # reach is visible and has a name.
    class ExecutableEntry < Zip::Entry
      def initialize(name, mode)
        super("", name)

        @unix_perms = mode
      end
    end

    # Everything is traversable and readable; bin/ is runnable.
    def entry_for(path, mode: nil)
      ExecutableEntry.new(path, mode || (path.start_with?("bin/") ? EXECUTABLE : PLAIN))
    end
end
