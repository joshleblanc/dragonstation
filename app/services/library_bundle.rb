require "zip"

# The console release as a ZIP, in two shapes that differ by one secret:
#
#   library.zip   the release, public -- every byte is already served to any
#                 browser running a cart, and ./update-library has no session
#   bundle.zip    the release plus the reader's API key in dragonstation.json
#
# It is the whole release, not just what a browser needs, so unpacking it over
# a checkout gives a console that runs.
class LibraryBundle
  CREDENTIALS_PATH = "dragonstation.json"

  EXECUTABLE = 0o755
  PLAIN = 0o644

  attr_reader :library

  def initialize(console_version)
    @library = console_version.library
  end

  def console_version = library.console_version

  # Sorted, so two downloads of one version are the same archive. The admin's
  # release scripts are added only when this library actually has them.
  def release_paths(release_tool: false)
    paths = ConsoleRelease.paths(library.paths) - ConsoleRelease::RELEASE_SCRIPTS
    paths += ConsoleRelease::RELEASE_SCRIPTS.select { |path| library.file?(path) } if release_tool
    paths.sort
  end

  # `credentials:` is nil for the public library, or a Hash for a bundle.
  def zip(release_tool: false, credentials: nil)
    buffer = Zip::OutputStream.write_buffer(StringIO.new(+"".b)) do |zip|
      release_paths(release_tool: release_tool).each do |path|
        zip.put_next_entry(entry_for(path))
        zip.write(library.read(path))
      end

      if credentials
        zip.put_next_entry(entry_for(CREDENTIALS_PATH))
        zip.write(JSON.pretty_generate(credentials))
      end
    end

    buffer.rewind
    buffer
  end

  # Absolute URLs, because the reader is a terminal with no idea where the site
  # lives. `admin` only lets the console fail early; the server checks again.
  def credentials(api_key:, site_url:, admin: false)
    {
      "console_version" => console_version.version,
      "api_key" => api_key,
      "publish_url" => File.join(site_url, "api/carts"),
      "site_url" => site_url,
      "issued_at" => Time.current.iso8601,
      "admin" => admin
    }.tap { |c| c["release_url"] = File.join(site_url, "api/console_versions") if admin }
  end

  def filename = "console-#{console_version.version}.zip"

  private
    # Entries written from memory get no mode from rubyzip, and scripts that
    # arrive non-executable are a console that cannot run. unzip restores this.
    def entry_for(path)
      Zip::Entry.new("", path).tap do |entry|
        entry.unix_perms = path.start_with?("bin/") ? EXECUTABLE : PLAIN
      end
    end
end
