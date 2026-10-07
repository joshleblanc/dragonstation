class CartridgesController < ApplicationController
  include CrossOriginIsolation
  include CartridgeVisibility

  # Browsing and playing are public. Uploading is not.
  allow_unauthenticated_access only: %i[index show]

  before_action :authenticate_uploader!, only: %i[new create]
  before_action :load_owned_cartridge, only: %i[publish]

  def index
    @cartridges = Cartridge.published.recent_first.includes(:user, :console_version)
    @console_versions = ConsoleVersion.default_first
  end

  def show
    # Public, but a draft is only visible to the person who wrote it -- which
    # visible_cartridge? decides, resolving the session for us.

    # has_one_attached is backed by an ActiveStorage::Attachment, so the preload
    # path is blob_attachment -> blob. includes(cartridge_files: :blob) raises,
    # because no such association exists.
    @cartridge = Cartridge
      .includes(:user, :console_version, cartridge_files: { blob_attachment: :blob })
      .find_by!(slug: params[:slug])

    return head :not_found unless visible_cartridge?

    @owned = owner?
  end

  def new
    @cartridge = Cartridge.new
    @console_version = ConsoleVersion.default
    @console_versions = ConsoleVersion.default_first
  end

  def create
    version = resolve_console_version

    unless version&.available?
      return redirect_to new_cartridge_path, alert: "No console library is available to build against yet."
    end

    archive = params.dig(:cartridge, :archive)

    if archive.blank?
      return redirect_to new_cartridge_path, alert: "Choose a ZIP of your cart to upload."
    end

    @cartridge = CartridgeIngest.new(
      archive: archive,
      user: Current.user,
      console_version: version,
      title: params.dig(:cartridge, :title)
    ).call

    redirect_to @cartridge, notice: "Uploaded #{@cartridge.title}. It is a draft until you publish it."
  rescue CartridgeIngest::Invalid => e
    # The form re-renders with the problems, so it needs the same context a
    # first visit would have built.
    @cartridge = Cartridge.new
    @console_version = version
    @console_versions = ConsoleVersion.default_first
    flash.now[:alert] = "That archive is not a cart I can run:\n#{e.problems.join("\n")}"
    render :new, status: :unprocessable_content
  end

  # Draft <-> published.
  #
  # Separate from update rather than an attribute on the form, because whether
  # something is live is not a field anyone edits -- it is a decision, and it
  # is the only one on this site with a visible consequence.
  def publish
    if params[:state] == "published"
      @cartridge.publish!
      redirect_to @cartridge, notice: "#{@cartridge.title} is published."
    else
      @cartridge.unpublish!
      redirect_to @cartridge, notice: "#{@cartridge.title} is back to a draft."
    end
  end

  private
    def load_owned_cartridge
      @cartridge = Cartridge.find_by!(slug: params[:slug])
      head :not_found unless Current.user && (Current.user.admin? || Current.user == @cartridge.user)
    end
    def owner?
      Current.user.present? && (Current.user.admin? || Current.user == @cartridge&.user)
    end

    def authenticate_uploader!
      return if Current.user

      session[:return_to_after_authenticating] = request.url
      redirect_to new_session_path
    end

    # The console version a cartridge is pinned to.
    #
    # Explicit when asked for, but only ever to a version that is actually
    # installed -- a row pointing at a missing directory would produce a
    # cartridge that cannot boot. Otherwise whatever is default, so the common
    # case needs no thought from the uploader.
    def resolve_console_version
      requested = params.dig(:cartridge, :console_version_id).presence

      if requested
        found = ConsoleVersion.find_by(id: requested)
        return found if found&.available?
      end

      version = ConsoleVersion.default
      version if version&.available?
    end
end
