# The console library's documentation, browsable on the site.
#
# Public, and deliberately so: these pages are the reason anyone would upload a
# cart at all, and a cart's author needs them before they have an account.
#
# The content comes from two places, and the split matters. The reference half is
# read out of the library's own comments (ConsoleDocumentation), so it cannot go
# stale. The guide half is written here (ConsoleGuide), because what a cart is
# and how to start one is not written down anywhere in the library.
#
# Both describe the *default* console version. A cartridge is pinned to a
# version, and an old version's docs are of no use to someone writing a cart
# today -- but the version is stated on every page, because a cart written
# against a different one is a real possibility and a silent mismatch would be
# indistinguishable from a bug in the library.
class DocsController < ApplicationController
  allow_unauthenticated_access

  before_action :load_documentation

  # The guide, then the reference index.
  def index
    @guide = ConsoleGuide.new
    @modules = @documentation.modules
  end

  # One module's API: every method it defines, in the order the library wrote
  # them, under the library's own section headings.
  def show
    @module = @documentation.find(params[:slug])

    head :not_found unless @module
  end

  # The library's source for one module.
  #
  # Docs that cannot be checked against the implementation are a guess. This is
  # the implementation, and it is the same file the game runs -- served from the
  # library directory, so what is read here is exactly what a cart gets.
  def source
    @module = @documentation.find(params[:slug])

    return head :not_found unless @module

    @source = @documentation.library.read(@module.path)
    @highlighted = FileHighlighter.new(@module.path, @source.force_encoding(Encoding::UTF_8)).call
  rescue ConsoleLibrary::Missing => e
    head :not_found
  end

  private
    def load_documentation
      @console_version = ConsoleVersion.default
      return head :not_found unless @console_version&.available?

      @documentation = ConsoleDocumentation.new(@console_version)
    end
end
