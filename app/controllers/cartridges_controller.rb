class CartridgesController < ApplicationController
  include CrossOriginIsolation
  include CartridgeVisibility

  allow_unauthenticated_access only: %i[index show]

  def index
    @cartridges = Cartridge.published.recent_first.includes(:user, :console_version)
    @console_version = ConsoleVersion.default
  end

  def show
    # has_one_attached is blob_attachment -> blob; there is no :blob association.
    @cartridge = Cartridge
      .includes(:user, :console_version, cartridge_files: { blob_attachment: :blob })
      .find_by!(slug: params[:slug])

    return head :not_found unless visible_cartridge?

    @owned = owner?
  end

  def new
    load_upload_form
  end

  def create
    version = requested_console_version

    unless version&.available?
      return redirect_to new_cartridge_path, alert: "No console library is available to build against yet."
    end

    archive = params.dig(:cartridge, :archive)
    return redirect_to new_cartridge_path, alert: "Choose a ZIP of your cart to upload." if archive.blank?

    @cartridge = CartridgeIngest.new(
      archive: archive,
      user: Current.user,
      console_version: version,
      title: params.dig(:cartridge, :title)
    ).call

    redirect_to @cartridge, notice: "Uploaded #{@cartridge.title}. It is a draft until you publish it."
  rescue CartridgeIngest::Invalid => e
    load_upload_form(version)
    flash.now[:alert] = "That archive is not a cart I can run:\n#{e.problems.join("\n")}"
    render :new, status: :unprocessable_content
  end

  # Separate from editing: going live is a decision, not a field.
  def publish
    @cartridge = Cartridge.find_by!(slug: params[:slug])
    return head :not_found unless owner?

    if params[:state] == "published"
      @cartridge.publish!
      redirect_to @cartridge, notice: "#{@cartridge.title} is published."
    else
      @cartridge.unpublish!
      redirect_to @cartridge, notice: "#{@cartridge.title} is back to a draft."
    end
  end

  private
    def load_upload_form(version = ConsoleVersion.default)
      @cartridge = Cartridge.new
      @console_version = version
      @console_versions = ConsoleVersion.default_first
    end

    # The version asked for if it can actually be read -- a pin to an
    # unreadable one is a cartridge that can never boot -- else the default.
    def requested_console_version
      requested = ConsoleVersion.find_by(id: params.dig(:cartridge, :console_version_id).presence)
      return requested if requested&.available?

      ConsoleVersion.default
    end
end
