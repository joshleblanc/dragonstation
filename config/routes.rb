Rails.application.routes.draw do
  resource :session
  resource :registration, only: %i[new create]
  resources :passwords, param: :token

  # Cartridges are addressed by slug, so a published game keeps a URL that
  # survives its title being edited.
  resources :cartridges, param: :slug do
    patch :publish, on: :member
  end

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
