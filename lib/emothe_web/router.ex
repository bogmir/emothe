defmodule EmotheWeb.Router do
  use EmotheWeb, :router

  import EmotheWeb.UserAuth

  pipeline :browser do
    plug :accepts, ["html"]
    plug :fetch_session
    plug :fetch_live_flash
    plug :put_root_layout, html: {EmotheWeb.Layouts, :root}
    plug :protect_from_forgery
    plug :put_secure_browser_headers
    plug :fetch_current_user
  end

  pipeline :demo_browser do
    plug :accepts, ["html"]
    plug :fetch_session
    plug :fetch_live_flash
    plug :put_root_layout, html: {EmotheWeb.Layouts, :demo_root}
    plug :protect_from_forgery
    plug :put_secure_browser_headers
    plug :fetch_current_user
  end

  pipeline :api do
    plug :accepts, ["json"]
  end

  # Public routes
  scope "/", EmotheWeb do
    pipe_through :browser

    get "/", PageController, :home

    # Public export endpoints
    get "/export/:id/tei", ExportController, :tei
    get "/export/:id/html", ExportController, :html
    get "/export/:id/pdf", ExportController, :pdf

    # Public play catalogue and presentation
    live_session :public,
      on_mount: [{EmotheWeb.UserAuth, :mount_current_user}] do
      live "/plays", PlayCatalogueLive, :index
      live "/plays/:code", PlayShowLive, :show
    end
  end

  ## Authentication routes

  scope "/", EmotheWeb do
    pipe_through [:browser, :redirect_if_user_is_authenticated]

    live_session :redirect_if_user_is_authenticated,
      on_mount: [{EmotheWeb.UserAuth, :redirect_if_user_is_authenticated}] do
      live "/users/register", UserRegistrationLive, :new
      live "/users/log-in", UserLoginLive, :new
      live "/users/reset-password", UserForgotPasswordLive, :new
      live "/users/reset-password/:token", UserResetPasswordLive, :edit
    end

    post "/users/log-in", UserSessionController, :create
  end

  scope "/", EmotheWeb do
    pipe_through [:browser, :require_authenticated_user]

    live_session :require_authenticated_user,
      on_mount: [{EmotheWeb.UserAuth, :ensure_authenticated}] do
      live "/users/settings", UserSettingsLive, :edit
      live "/users/settings/confirm-email/:token", UserSettingsLive, :confirm_email
    end
  end

  scope "/", EmotheWeb do
    pipe_through [:browser]

    delete "/users/log-out", UserSessionController, :delete

    live_session :current_user,
      on_mount: [{EmotheWeb.UserAuth, :mount_current_user}] do
      live "/users/confirm/:token", UserConfirmationLive, :edit
      live "/users/confirm", UserConfirmationInstructionsLive, :new
    end
  end

  # Admin routes - requires admin role
  scope "/admin", EmotheWeb.Admin do
    pipe_through [:browser, :require_authenticated_user, :require_admin_user]

    live_session :admin,
      layout: {EmotheWeb.Layouts, :admin},
      on_mount: [{EmotheWeb.UserAuth, :ensure_admin}] do
      live "/plays", PlayListLive, :index
      live "/plays/new", PlayFormLive, :new
      live "/plays/:id/edit", PlayFormLive, :edit
      live "/plays/import", ImportLive, :index
      live "/plays/:id", PlayDetailLive, :show
      live "/plays/:id/content", PlayContentEditorLive, :index
    end

    # Export endpoints
    get "/plays/:id/export/tei", ExportController, :tei
    get "/plays/:id/export/html", ExportController, :html
    get "/plays/:id/export/pdf", ExportController, :pdf
  end

  # LiveDashboard for admin users (all environments)
  import Phoenix.LiveDashboard.Router

  scope "/admin" do
    pipe_through [:browser, :require_authenticated_user, :require_admin_user]

    live_dashboard "/dashboard", metrics: EmotheWeb.Telemetry
  end

  # Swoosh mailbox preview in development only
  if Application.compile_env(:emothe, :dev_routes) do
    scope "/dev" do
      pipe_through :browser

      forward "/mailbox", Plug.Swoosh.MailboxPreview
    end

    scope "/demo/ui", EmotheWeb do
      pipe_through :demo_browser

      get "/", DemoUIController, :index
      get "/public/catalogue", DemoUIController, :public_catalogue
      get "/public/play", DemoUIController, :public_play
      get "/admin/plays", DemoUIController, :admin_plays
      get "/admin/play", DemoUIController, :admin_play
      get "/admin/import", DemoUIController, :admin_import
    end
  end
end
