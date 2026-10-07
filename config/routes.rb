Rails.application.routes.draw do
  resource :session
  resource :registration, only: %i[new create]
  resources :passwords, param: :token

  # Cartridges are addressed by slug, so a published game keeps a URL that
  # survives its title being edited.
  resources :cartridges, param: :slug do
    patch :publish, on: :member
  end

  # Account settings: the publishing key and the console download. Behind the
  # login, because the download it produces carries that account's key.
  resource :settings, only: %i[show]
  post "settings/api_key", to: "settings#rotate_api_key", as: :settings_api_key

  # Handing the library to a console. The library is open -- the site serves
  # every byte of it to run a cart anyway -- and the bundle additionally carries
  # the reader's API key, so it is behind the login it belongs to.
  get "console/library.zip", to: "downloads#library", as: :library_download
  get "console/bundle.zip", to: "downloads#bundle", as: :console_bundle

  # Publishing a cart from the console. Key-authenticated, so it carries no
  # session and no CSRF token: the Authorization header is the credential and
  # a cross-site form post cannot set one.
  post "api/carts", to: "api/carts#create"

  # Releasing a new console version. Same door, and the same key; the difference
  # is that this one needs an administrator's key, checked per request.
  post "api/console_versions", to: "api/console_versions#create"

  # The console library's documentation. Public: it is the reason anyone uploads
  # a cart, and an author needs it before they have an account. Declared before
  # the cartridge routes below only because "/docs/..." and "/cartridges/..."
  # could not collide anyway -- this one is a fixed prefix.
  get "docs", to: "docs#index", as: :docs
  get "docs/:slug/source", to: "docs#source", as: :doc_source
  get "docs/:slug", to: "docs#show", as: :doc

  # One file of a cart, read as text. The path rides in the query string, not
  # the route, because Turbo will not navigate a URL whose last segment ends in
  # one of ~60 extensions (.png, .json, .txt, .wav...) -- it leaves those to the
  # browser so downloads stay downloads. A cart page full of sprites and .json
  # maps would then open nothing at all. Here the last segment is always
  # "files", and a path in a query parameter has no extension to judge.
  #
  # That also retires the format trap below: with no extension in the path,
  # Rails' /\.(\w+)\z/ has nothing to match, so the response is HTML already.
  get "cartridges/:cartridge_id/files",
    to: "cartridge_files#show", as: :cartridge_file

  # Operator screens. Behind Admin::BaseController, which answers a non-admin
  # with a 404 rather than a redirect, so the area does not advertise itself.
  namespace :admin do
    root "dashboard#show"

    resources :console_versions, only: %i[index show new create] do
      patch :default, on: :member
    end
  end

  # The runtime. Declared before the catch-all below it, because the build's
  # own files are also served from this path: the shell asks for game.css and
  # dragonruby-html5-loader.js as siblings of index.html, and they have to
  # resolve without shadowing the two dynamic endpoints.
  #
  # The loader asks for manifest.json first, then gamedata/<path> for every
  # file the manifest names.
  get "cartridges/:cartridge_id/play/manifest.json",
    to: "cartridge_runtime#manifest", as: :cartridge_manifest
  get "cartridges/:cartridge_id/play/gamedata/*path",
    to: "cartridge_runtime#data", as: :cartridge_data
  get "cartridges/:cartridge_id/play/*file",
    to: "cartridge_runtime#shell", as: :cartridge_shell

  # Reveal health status on /up that returns 200 if the app boots with no exceptions, otherwise 500.
  # Can be used by load balancers and uptime monitors to verify that the app is live.
  get "up" => "rails/health#show", as: :rails_health_check

  root "cartridges#index"
end
