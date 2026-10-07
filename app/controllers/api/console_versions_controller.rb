# Releasing a new console version to the site.
#
# The same install the admin upload screen does, for the console that is going
# to become the new default: one ZIP, validated by ConsoleLibraryInstall, and
# never overwriting a version that already exists.
#
# **Admin only, checked here rather than in the client.** The console that ships
# a release script is a different download from the one everybody gets, but the
# file being absent is a courtesy, not a control -- anyone can curl this
# endpoint with any key they like. So the credential is resolved to its owner
# and the owner has to be an admin, and the bundle's extra file is only a
# convenience for somebody who already is one.
module Api
  class ConsoleVersionsController < ApplicationController
    # Key-authenticated, like the cart API: a missing key has to be a 401 here,
    # never a redirect to a sign-in form a terminal cannot answer.
    allow_unauthenticated_access

    skip_forgery_protection

    before_action :authenticate_admin!

    # POST /api/console_versions
    #
    #   Authorization: Bearer ds_...
    #   archive=<the console ZIP>
    def create
      archive = params[:archive]

      if archive.blank?
        return render json: {
          error: "no archive",
          problems: [ "send the console as multipart/form-data under `archive`" ]
        }, status: :bad_request
      end

      console_version = ConsoleLibraryInstall.new(
        archive: archive,
        title: params[:title],
        notes: params[:notes]
      ).call

      render json: {
        version: console_version.version,
        title: console_version.title,
        # Never the default: installing a version and choosing to build against
        # it are two decisions, and the second one is a person's.
        default: console_version.default,
        modules: ConsoleDocumentation.new(console_version).modules.size,
        url: admin_console_version_url(console_version)
      }, status: :created
    rescue ConsoleLibraryInstall::Invalid => e
      render json: { error: "that archive is not a console I can install", problems: e.problems },
        status: :unprocessable_content
    end

    private
      def authenticate_admin!
        key = ApiKey.from_authorization(request.authorization)

        return render json: { error: "unauthorised" }, status: :unauthorized unless key
        return forbidden unless key.user.admin?

        Current.api_key = key
      end

      def forbidden
        render json: {
          error: "forbidden",
          problems: [ "releasing a console version is an administrator's job" ]
        }, status: :forbidden
      end
  end
end
