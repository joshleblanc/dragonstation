# Publishing a cart from the console.
#
# The one door in that a cart arrives without a session cookie, authenticated
# by the API key the reader's bundle carries. The key says whose cart it is;
# everything else about the upload is the same upload the browser form does, so
# the refusals -- traversal, symlinks, expansion bombs, a cart that references
# art it does not own -- are CartridgeIngest's, unchanged and already tested.
#
# It lands as a *draft*, like the form does. Publishing is the one decision on
# this site with a visible consequence, and it stays a decision a person makes
# after seeing the cart run.
module Api
  class CartsController < ApplicationController
    # Authenticated by key, not by session, so the session check is skipped
    # rather than satisfied -- a missing key has to be a 401 here, never a
    # redirect to a sign-in form a terminal cannot answer.
    allow_unauthenticated_access

    skip_forgery_protection

    before_action :authenticate_key!

    # POST /api/carts
    #
    #   Authorization: Bearer ds_...
    #   archive=<the cart ZIP>
    def create
      # Refused before anything is read, rather than defaulted: a console with no
      # default has a problem, and shipping against whatever happens to be
      # newest is how two carts end up on different libraries.
      version = ConsoleVersion.default

      if version.nil? || !version.available?
        return render json: { error: "no console library is available to build against" },
          status: :service_unavailable
      end

      archive = params[:archive]

      if archive.blank?
        return render json: {
          error: "no archive",
          problems: [ "send the cart as multipart/form-data under `archive`" ]
        }, status: :bad_request
      end

      cartridge = CartridgeIngest.new(
        archive: archive,
        user: Current.user,
        console_version: version,
        title: params[:title]
      ).call

      render json: {
        id: cartridge.id,
        slug: cartridge.slug,
        title: cartridge.title,
        status: cartridge.draft? ? "draft" : "published",
        url: cartridge_url(cartridge),
        console_version: cartridge.console_version.version
      }, status: :created
    rescue CartridgeIngest::Invalid => e
      # The same refusals the form reports, as JSON, because the caller is a
      # script and a redirect to the upload page with a flash is no use to it.
      render json: { error: "that archive is not a cart I can run", problems: e.problems },
        status: :unprocessable_content
    end

    private
      def authenticate_key!
        key = ApiKey.from_authorization(request.authorization)

        return render json: { error: "unauthorised" }, status: :unauthorized unless key

        Current.api_key = key
      end
  end
end
