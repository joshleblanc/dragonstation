# Handing the console library to someone.
#
# Two downloads, because they differ by exactly one secret. The library is
# already public -- the site serves every byte of it to run a cart -- so
# /console/library.zip is open and needs no session, which is what lets the
# console's own ./update-library refresh itself from a terminal. The bundle
# additionally carries the reader's API key, so it is behind the login it
# belongs to.
#
# Both are built from the *default* console version, because that is the version
# a new upload is pinned to. A reader who downloads this and builds a cart gets
# the library their cart will actually run against.
class DownloadsController < ApplicationController
  # A library nobody can download is a library nobody can update, and the
  # console has no session to authenticate with.
  allow_unauthenticated_access only: %i[library]

  before_action :authenticate_uploader!, only: %i[bundle]
  before_action :load_bundle

  # The library alone.
  def library
    send_bundle cache: "public, max-age=300"
  end

  # The library plus this account's publishing credentials.
  def bundle
    # The key is in the body, so this must never be cached: a shared cache
    # holding one person's key is one leaked key.
    send_bundle cache: "no-store, private"
  end

  private
    def load_bundle
      @console_version = ConsoleVersion.default
      return head :not_found unless @console_version&.available?

      @bundle = LibraryBundle.new(@console_version)
    end

    def send_bundle(cache:)
      # A fresh key on every download, because the secret is never stored and
      # this is the only place it exists. That is the trade for keeping it out
      # of the database: a second download retires the first, and the console
      # that held it will be told exactly what to do when it fails.
      #
      # The alternative -- encrypting the secret so it can be re-shipped --
      # needs record encryption keys this deployment does not have, and an
      # unreadable key is worse than one the reader has to fetch twice.
      admin = Current.user&.admin? || false
      secret = Current.user&.issue_api_key!

      zip = @bundle.zip(
        release_tool: admin,
        credentials: secret && @bundle.credentials(
          api_key: secret,
          site_url: request.base_url,
          admin: admin
        )
      )

      send_data zip.read,
        filename: @bundle.filename,
        type: "application/zip",
        disposition: "attachment"

      # After send_data, which builds the body itself and derives its own
      # Cache-Control from the disposition -- overriding anything passed above.
      # The library is cacheable; a body containing someone's key is not.
      response.headers["Cache-Control"] = cache
    end

    def authenticate_uploader!
      return if Current.user

      session[:return_to_after_authenticating] = request.url
      redirect_to new_session_path
    end
end
