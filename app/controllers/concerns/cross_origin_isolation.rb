# Cross-origin isolation, so the wasm build has SharedArrayBuffer.
#
# SharedArrayBuffer is gated behind cross-origin isolation, which is what lets
# DragonRuby's build use threads. It requires two headers together:
#
#   Cross-Origin-Opener-Policy: same-origin    the document gets its own group
#   Cross-Origin-Embedder-Policy: require-corp the document only embeds
#                                             resources that agree to be embedded
#
# Without them the loader finds no SharedArrayBuffer, and its fallback is to
# register dragonruby-serviceworker.js -- a client-side shim that rewrites
# these same headers onto every response, then reloads the page so the document
# becomes controlled by it. That path works, but it costs a reload, depends on
# service workers being available and permitted, and its own fetch handler
# returns undefined when the network fails, which turns one failed request into
# an unhandled rejection and a dead page.
#
# The server can simply send the headers, which is the thing the shim exists to
# work around. Then SharedArrayBuffer is present on the first load, the loader
# skips the service worker entirely, and none of that path is reachable.
module CrossOriginIsolation
  extend ActiveSupport::Concern

  included do
    # A before_action, not an after_action: send_file and send_data build the
    # body directly, and headers set after that point do not reliably reach the
    # Rack response.
    before_action :set_cross_origin_isolation_headers
  end

  # A nested browsing context is only cross-origin isolated if the document
  # embedding it opts in as well, so the page carrying the iframe needs COEP
  # too. Everything it loads is same-origin, which require-corp permits.
  def self.opener_policy = "same-origin"
  def self.embedder_policy = "require-corp"

  private
    def set_cross_origin_isolation_headers
      response.set_header "Cross-Origin-Opener-Policy", CrossOriginIsolation.opener_policy
      response.set_header "Cross-Origin-Embedder-Policy", CrossOriginIsolation.embedder_policy
    end
end
