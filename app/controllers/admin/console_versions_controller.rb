module Admin
  # The console library, as an operator sees it.
  #
  # The index is `console:status` with a web page around it, including the two
  # states that task reports and that nothing else on the site shows: a version
  # whose directory is missing, and a version whose directory disagrees with the
  # version.rb inside it. Both are visible here because both silently break
  # every cartridge pinned to that version.
  #
  # `default` only decides what a *new* upload is pinned to. It cannot move a
  # cartridge that already exists, which is why it is safe to change and why
  # changing it is worth a screen.
  class ConsoleVersionsController < BaseController
    before_action :load_console_version, only: %i[show default]

    def index
      @versions = ConsoleVersion.default_first.includes(:cartridges).to_a
      @default = ConsoleVersion.default
    end

    def show
      @pinned = @console_version.cartridges.includes(:user).order(created_at: :desc)
      @declared = read_library { |library| library.declared_version }
      @fonts = read_library { |library| library.fonts } || []
      @modules = module_rows
    end

    def new
      @archive = nil
    end

    def create
      archive = params.dig(:console_library_install, :archive)

      if archive.blank?
        return redirect_to new_admin_console_version_path, alert: "Choose a ZIP of a console library."
      end

      @console_version = ConsoleLibraryInstall.new(
        archive: archive,
        title: params.dig(:console_library_install, :title),
        notes: params.dig(:console_library_install, :notes)
      ).call

      redirect_to admin_console_version_path(@console_version),
        notice: "Installed console #{@console_version.version}. " \
                "It is not the default, so existing cartridges are unaffected."
    rescue ConsoleLibraryInstall::Invalid => e
      # The file input cannot be repopulated, so the problems go above the form
      # rather than into it.
      flash.now[:alert] = "That archive is not a console library I can install:\n#{e.problems.join("\n")}"
      render :new, status: :unprocessable_content
    end

    # Which library a new upload gets. A single flag, cleared everywhere else in
    # the same transaction so two defaults can never race into being true.
    def default
      if params[:state] == "default"
        ConsoleVersion.transaction do
          ConsoleVersion.where.not(id: @console_version.id).update_all(default: false)
          @console_version.update!(default: true)
        end

        redirect_to admin_console_version_path(@console_version),
          notice: "New uploads will be pinned to #{@console_version.version}."
      else
        @console_version.update!(default: false)

        redirect_to admin_console_version_path(@console_version),
          notice: "#{@console_version.version} is no longer the default."
      end
    end

    private
      def load_console_version
        @console_version = ConsoleVersion.find(params[:id])
      end

    # A version row can outlive its directory, or disagree with it, and the file it
    # names can be deleted from a checkout underneath the row. None of that may
    # take the page down: the whole purpose of this page is to show a library
    # that is broken.
    #
    # So every read of the directory is wrapped, and an unreadable answer is
    # simply not shown rather than raised.
    def read_library
      return nil unless @console_version.available?

      yield @console_version.library
    rescue ConsoleLibrary::Missing, SystemCallError
      nil
    end

    # [require path, bytes] in require order, with a size the page can print for
    # every row. Order is load-bearing, so it is never sorted.
    def module_rows
      paths = read_library { |library| library.require_paths } || []
      library = @console_version.library

      paths.map do |path|
        size =
          begin
            library.size_of(path)
          rescue ConsoleLibrary::Missing, SystemCallError
            nil
          end

        [ path, size ]
      end
    end
  end
end
