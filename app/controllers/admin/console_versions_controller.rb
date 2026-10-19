module Admin
  # `console:status` with a web page around it, including the broken states
  # (unreadable, mislabelled) that silently break every pinned cartridge.
  # `default` only decides what a *new* upload is pinned to.
  class ConsoleVersionsController < BaseController
    before_action :load_console_version, only: %i[show default]

    def index
      @versions = ConsoleVersion.default_first.includes(:cartridges).to_a
      @default = ConsoleVersion.default
    end

    def show
      @pinned = @console_version.cartridges.includes(:user).order(created_at: :desc)

      # This page exists to show a broken library, so it must not raise on one.
      library = @console_version.library
      readable = @console_version.available?
      @declared = readable ? library.declared_version : nil
      @fonts = readable ? library.fonts : []
      @modules = (readable ? library.require_paths : []).map do |path|
        [ path, (library.size_of(path) if library.file?(path)) ]
      end
    rescue ConsoleLibrary::Missing
      @declared, @fonts, @modules = nil, [], []
    end

    def new
    end

    def create
      archive = params.dig(:console_library_install, :archive)
      return redirect_to new_admin_console_version_path, alert: "Choose a ZIP of a console library." if archive.blank?

      @console_version = ConsoleLibraryInstall.new(
        archive: archive,
        title: params.dig(:console_library_install, :title),
        notes: params.dig(:console_library_install, :notes)
      ).call

      redirect_to admin_console_version_path(@console_version),
        notice: "Installed console #{@console_version.version}. " \
                "It is not the default, so existing cartridges are unaffected."
    rescue ConsoleLibraryInstall::Invalid => e
      flash.now[:alert] = "That archive is not a console library I can install:\n#{e.problems.join("\n")}"
      render :new, status: :unprocessable_content
    end

    def default
      if params[:state] == "default"
        @console_version.make_default!
        notice = "New uploads will be pinned to #{@console_version.version}."
      else
        @console_version.update!(default: false)
        notice = "#{@console_version.version} is no longer the default."
      end

      redirect_to admin_console_version_path(@console_version), notice: notice
    end

    private
      def load_console_version
        @console_version = ConsoleVersion.find(params[:id])
      end
  end
end
