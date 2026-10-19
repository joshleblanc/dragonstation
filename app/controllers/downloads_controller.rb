# The default console version as a ZIP. The library is public (every byte is
# already served to run carts, and ./update-library has no session); the
# bundle adds the reader's API key, so it needs a login.
class DownloadsController < ApplicationController
  allow_unauthenticated_access only: %i[library]

  before_action :load_bundle

  def library
    send_bundle cache: "public, max-age=300"
  end

  def bundle
    # A key in the body must never sit in a shared cache.
    send_bundle cache: "no-store, private"
  end

  private
    def load_bundle
      @console_version = ConsoleVersion.default
      return head :not_found unless @console_version&.available?

      @bundle = LibraryBundle.new(@console_version)
    end

    def send_bundle(cache:)
      # A fresh key every download: the secret is never stored, so this is the
      # only place it exists, and a second download retires the first.
      admin = Current.user&.admin? || false
      secret = Current.user&.issue_api_key!
      credentials = secret && @bundle.credentials(api_key: secret, site_url: request.base_url, admin: admin)

      send_data @bundle.zip(release_tool: admin, credentials: credentials).read,
        filename: @bundle.filename, type: "application/zip", disposition: "attachment"

      # After send_data, which derives its own Cache-Control.
      response.headers["Cache-Control"] = cache
    end
end
