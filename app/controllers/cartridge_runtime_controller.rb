# Serves one cartridge to the DragonRuby HTML5 build:
#
#   play/manifest.json    every file in the served tree, with exact sizes
#   play/gamedata/<path>  the bytes of one of them
#   play/<file>           the build itself, served beside index.html so its
#                         relative requests resolve to this cartridge
#
# Public, because the loader is an iframe fetching anonymously; drafts are
# hidden per cartridge by CartridgeVisibility.
class CartridgeRuntimeController < ApplicationController
  include CrossOriginIsolation
  include CartridgeVisibility

  allow_unauthenticated_access
  skip_forgery_protection

  before_action :load_visible_cartridge

  def shell
    name = build_file_name
    return head :not_found unless name

    if name == Html5Build::LOADER
      send_data @cartridge.stager.build.loader, type: content_type_for(name), disposition: "inline"
      # Per-cartridge bytes that change with the title. Set after send_data,
      # which would otherwise overwrite Cache-Control.
      response.headers["Cache-Control"] = "no-cache"
    else
      send_file Html5Build::ROOT.join(name), type: content_type_for(name), disposition: "inline",
        headers: { "Cache-Control" => "public, max-age=300" }
    end
  end

  def manifest
    render json: @cartridge.manifest
  end

  def data
    stager = @cartridge.stager
    path = served_path_candidates.find { |candidate| stager.resolve(candidate) }
    return head :not_found unless path

    file = stager.resolve(path)
    # The ETag must agree with the manifest's filetime, or the browser cache
    # and the loader's IndexedDB cache disagree about what is current.
    response.set_header "ETag", %(W/"#{file.path}-#{file.filetime}-#{file.byte_size}")
    send_data stager.read(path), type: content_type_for(path), disposition: "inline",
      headers: { "Cache-Control" => "public, max-age=31536000, immutable" }
  end

  private
    # Rails strips the last extension off a glob as the format, so
    # gamedata/app/console/core.rb arrives as path="app/console/core",
    # format="rb". The manifest decides which spelling is real.
    def served_path_candidates
      raw = params[:path].to_s
      [ (params[:format].present? ? "#{raw}.#{params[:format]}" : nil), raw ].compact.uniq
    end

    # Exactly one spelling here: a looser fallback would answer index.html.bak
    # with index.html, and a cache would believe it.
    def build_file_name
      raw = params[:file].to_s
      name = if raw.blank? then "index.html"
      elsif params[:format].present? then "#{raw}.#{params[:format]}"
      else raw
      end

      name if Html5Build::STATIC_FILES.include?(name) || name == Html5Build::LOADER
    end

    # for(name:) -- the positional argument is data to sniff. Served as
    # octet-stream, index.html downloads instead of rendering, so no rescue.
    def content_type_for(path)
      Marcel::MimeType.for(name: path.to_s) || "application/octet-stream"
    end
end
