# POST /api/console_versions -- releasing a console from bin/publish-console.
#
# Admin only, checked here: the release script being absent from non-admin
# downloads is a courtesy, and anyone can curl this with any key.
module Api
  class ConsoleVersionsController < BaseController
    before_action :require_admin!

    def create
      if params[:archive].blank?
        return render_problems("no archive", "send the console as multipart/form-data under `archive`", :bad_request)
      end

      console_version = ConsoleLibraryInstall.new(
        archive: params[:archive],
        title: params[:title],
        notes: params[:notes]
      ).call

      render json: {
        version: console_version.version,
        title: console_version.title,
        # Never the default: choosing to build against it is a person's call.
        default: console_version.default,
        modules: console_version.library.require_paths.size,
        url: admin_console_version_url(console_version)
      }, status: :created
    rescue ConsoleLibraryInstall::Invalid => e
      render_problems("that archive is not a console I can install", e.problems, :unprocessable_content)
    end

    private
      def require_admin!
        return if Current.user.admin?

        render_problems("forbidden", "releasing a console version is an administrator's job", :forbidden)
      end
  end
end
