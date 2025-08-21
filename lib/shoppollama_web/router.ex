local in_browser_scope = false
local did_change = false

for line in lines do
  -- escape special chars with % when matching literally, ie:: `%^  %$  %(  %)  %%  %.  %[  %]  %*  %+  %-  %?`
  if line:match('^%s*scope%s+"/",%s*ShoppollamaWeb%s+do%s*$') then
    in_browser_scope = true
    print(line)
  elseif in_browser_scope and line:match('^%s*live%s+"/",%s*ChatLive%s*$') then
    -- print the existing route
    print(line)
    -- add oauth routes after the main route
    print('')
    print('    # OAuth routes for Shopify')
    print('    get "/auth/shopify", OAuthController, :authorize')
    print('    get "/auth/shopify/callback", OAuthController, :callback')
    did_change = true
  elseif line:match('^%s*end%s*$') and in_browser_scope then
    -- we found closing `end` delimiter, and WE REMEMBER TO PRINT IT
    in_browser_scope = false
    print(line)
  else
    print(line)
  end
end
defmodule ShoppollamaWeb.Router do
  use ShoppollamaWeb, :router

  pipeline :browser do
    plug :accepts, ["html"]
    plug :fetch_session
    plug :fetch_live_flash
    plug :put_root_layout, html: {ShoppollamaWeb.Layouts, :root}
    plug :protect_from_forgery
    plug :put_secure_browser_headers
  end

  pipeline :api do
    plug :accepts, ["json"]
  end

  scope "/", ShoppollamaWeb do
    pipe_through :browser

    live "/", ChatLive

    # OAuth routes for Shopify
    get "/auth/shopify", OAuthController, :authorize
    get "/auth/shopify/callback", OAuthController, :callback
  end

  # Other scopes may use custom stacks.
  # scope "/api", ShoppollamaWeb do
  #   pipe_through :api
  # end

  # Enable LiveDashboard and Swoosh mailbox preview in development
  if Application.compile_env(:shoppollama, :dev_routes) do
    # If you want to use the LiveDashboard in production, you should put
    # it behind authentication and allow only admins to access it.
    # If your application does not have an admins-only section yet,
    # you can use Plug.BasicAuth to set up some basic authentication
    # as long as you are also using SSL (which you should anyway).
    import Phoenix.LiveDashboard.Router

    scope "/dev" do
      pipe_through :browser

      live_dashboard "/dashboard", metrics: ShoppollamaWeb.Telemetry
      forward "/mailbox", Plug.Swoosh.MailboxPreview
    end
  end
end
