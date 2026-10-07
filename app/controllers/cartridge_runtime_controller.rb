# Serves one cartridge to the DragonRuby HTML5 build.
#
# This is the postcarts embed controller generalised from a file to a tree.
# The loader asks two questions before it will run anything, and this answers
# both:
#
#   GET play/manifest.json    what files exist, and exactly how big each is
#   GET play/gamedata/<path>  the bytes of one of them
#
# Everything else under play/ is the HTML5 build itself -- the shell, the
# loader, the wasm module and its worker -- served out of public/dragonruby.
#
# The whole point is that the console library travels with every cartridge.
# A cart on its own is a directory of methods nothing implements; the library
# is what gives them meaning, so the manifest is not just the cart's files but
# the pinned console version's files beside them. Which is also why the served
# entry point pins the cart: the tree contains exactly one, and the pin is what
# stops the build from booting anything else if a second one ever appears.
class CartridgeRuntimeController < ApplicationController
  include CrossOriginIsolation
  include CartridgeVisibility

  # The HTML5 build, copied from a DragonRuby html5 publish. Serving it from
  # here rather than from public/ is what keeps every request relative to the
  # cartridge: index.html asks for game.css and dragonruby-html5-loader.js as
  # siblings, and from here those resolve to the same play/ path.
  BUILD_ROOT = Html5Build::ROOT

  # Everything in the build except the loader, which is generated per cartridge
  # because its header names the game. A whitelist, because this route takes a
  # path from the URL and the whole point of the manifest is that it names
  # files -- an open-ended route would serve any file in the build directory by
  # name.
  BUILD_FILES = Html5Build::STATIC_FILES

  before_action :load_cartridge
  skip_forgery_protection

  # The runtime is public: the loader is a browser iframe with no session, and
  # it fetches manifest.json and every game file anonymously. Visibility is
  # decided per cartridge in load_cartridge instead -- published is public,
  # draft is owner-and-admin only.
  allow_unauthenticated_access

  # index.html, and every static file the HTML5 build loads as a sibling.
  def shell
    name = resolved_build_file

    return head :not_found unless name

    # The loader is generated per cartridge, so its bytes are only correct for the
    # cartridge at this URL: the header names the game, and editing a title
    # changes them without changing the path. Revalidate rather than cache
    # blindly -- ETag is computed from the content, so an unchanged loader
    # costs a 304.
    if name == Html5Build::GENERATED_LOADER
      send_data @cartridge.stager.build.loader,
        type: content_type_for(name),
        disposition: "inline"

      # Set after send_data: send_file_headers! derives Cache-Control from
      # expires_in and would otherwise overwrite anything passed in headers:.
      response.headers["Cache-Control"] = "no-cache"
      return
    end

    send_file BUILD_ROOT.join(name),
      type: content_type_for(name),
      disposition: "inline",
      headers: { "Cache-Control" => "public, max-age=300" }
  end

  # The manifest. One JSON object, filename => { filesize, filetime }.
  #
  # filesize is not advisory. The loader allocates a buffer of exactly that
  # length and fills it from the response, so a wrong number here corrupts the
  # file in the virtual filesystem silently -- a short one pads with zeros,
  # a long one truncates. Every size below comes from the bytes that will
  # actually be returned.
  def manifest
    render json: @cartridge.manifest
  end

  # One file from the served tree.
  def data
    file = resolved_served_file

    # The manifest listed it and the loader asked for it, or it never existed.
    # Either way the loader's own error message is the useful one.
    return head :not_found unless file

    send_data bytes_for(file),
      type: content_type_for(file.path),
      disposition: "inline",
      headers: cache_headers(file)
  end

  private
    # Rails takes the last dot off a glob route as a format separator, so
    # gamedata/app/console/core.rb arrives as path="app/console/core",
    # format="rb". Both spellings are tried and the manifest decides which one
    # is real -- it is the authority on what this cartridge serves, so asking
    # it beats trying to re-derive the original string.
    def path_candidates
      raw = params[:path].to_s
      format = params[:format]

      candidates = []
      candidates << "#{raw}.#{format}" if format.present?
      candidates << raw
      candidates.uniq
    end

    def resolved_served_file
      path_candidates.lazy.map { |candidate| @cartridge.stager.resolve(candidate) }.find(&:present?)
    end

    # Same reconstruction, but exactly one candidate and then the whitelist.
    # Offering a looser fallback here would answer a request for
    # index.html.bak with index.html: harmless, but it means the URL and the
    # response disagree, which is the kind of thing that makes a cache lie.
    def resolved_build_file
      raw = params[:file].to_s
      format = params[:format]

      name =
        if raw.blank? then "index.html"
        elsif format.present? then "#{raw}.#{format}"
        else raw
        end

      # The loader is not in BUILD_FILES because it is not a file on disk, but
      # index.html asks for it by name as a sibling, so it has to resolve.
      BUILD_FILES.include?(name) || name == Html5Build::GENERATED_LOADER ? name : nil
    end

    def load_cartridge
      @cartridge = Cartridge.find_by!(slug: params[:cartridge_id])

      # A draft is visible to the person writing it and to nobody else. The
      # runtime path is public, so this is the only thing standing between an
      # unpublished game and the internet.
      head :not_found unless visible_cartridge?
    end

    def bytes_for(file)
      case file.source
      when :generated       then @cartridge.stager.entry_source
      when :library         then @cartridge.console_version.library.read(file.path)
      when :metadata        then metadata_bytes(file.path)
      when :cartridge_file  then cartridge_file(file).blob.download
      else raise "unknown file source: #{file.source}"
      end
    end

    def metadata_bytes(path)
      metadata = @cartridge.stager.metadata
      path == ConsoleMetadata::PATH ? metadata.content : metadata.icon
    end

    def cartridge_file(file)
      # Served paths are prefixed with the cart directory; stored paths are
      # cart-relative. Strip the prefix rather than trusting the URL to have
      # arrived in one particular shape.
      relative = file.path.delete_prefix("#{@cartridge.cart_prefix}/")
      @cartridge.cartridge_files.find_by!(path: relative)
    end

    # Cache by filetime, not by URL alone.
    #
    # The loader keeps its own IndexedDB copy and re-downloads when filetime
    # moves, so the filetime in the manifest and the ETag here have to be the
    # same number or the two disagree and the browser serves a stale file the
    # loader believed it had updated.
    def cache_headers(file)
      etag = %(W/"#{file.path}-#{file.filetime}-#{file.byte_size}")
      response.set_header "ETag", etag
      { "Cache-Control" => "public, max-age=31536000, immutable" }
    end

    # Marcel's signature is for(name:) or for(extension:). The positional argument
    # is *data to sniff*, not a path to look at, and there is no pathname:
    # keyword -- passing one raises.
    #
    # That distinction matters more than it looks. Served as
    # application/octet-stream, a browser downloads index.html instead of
    # rendering it, and the build silently stops working with a 200 on every
    # request. So this deliberately does not rescue: a wrong Marcel call should
    # fail loudly here, not quietly downgrade every content type on the site.
    def content_type_for(path)
      Marcel::MimeType.for(name: path.to_s) || "application/octet-stream"
    end
end
