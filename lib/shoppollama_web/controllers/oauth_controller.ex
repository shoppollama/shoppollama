defmodule ShoppollamaWeb.OAuthController do
  use ShoppollamaWeb, :controller
  require Logger
  alias Shoppollama.{Repo, Store}

  @shopify_api_key "356e5aa3ba68f30312214f7cfdfd92da"
  @redirect_uri "http://localhost:4000/auth/shopify/callback"
  @scopes "read_products,write_products"

  def authorize(conn, %{"shop" => shop}) do
    # Validate shop domain
    shop = sanitize_shop_domain(shop)

    if valid_shop_domain?(shop) do
      # Generate state for CSRF protection
      state = generate_state()

      # Store state in session
      conn = put_session(conn, :oauth_state, state)

      # Build authorization URL
      auth_url = build_auth_url(shop, state)

      redirect(conn, external: auth_url)
    else
      conn
      |> put_flash(:error, "Invalid shop domain")
      |> redirect(to: "/")
    end
  end

  def authorize(conn, _params) do
    # Render form to enter shop domain
    render(conn, :authorize)
  end

  def callback(conn, %{"code" => code, "shop" => shop, "state" => state}) do
    # Verify state for CSRF protection
    session_state = get_session(conn, :oauth_state)

    if state == session_state do
      shop = sanitize_shop_domain(shop)

      case exchange_code_for_token(code, shop) do
        {:ok, access_token} ->
          # Save store to database
          store_params = %{
            shop_domain: shop,
            access_token: access_token,
            shop_name: extract_shop_name(shop),
            is_active: true
          }

          case create_or_update_store(store_params) do
            {:ok, store} ->
              # Store the access token securely in session
              conn = put_session(conn, :shopify_access_token, access_token)
              conn = put_session(conn, :shopify_shop, shop)
              conn = put_session(conn, :store_id, store.id)

              conn
              |> put_flash(:info, "Successfully connected to Shopify store: #{shop}")
              |> redirect(to: "/")

            {:error, changeset} ->
              Logger.error("Failed to save store: #{inspect(changeset.errors)}")

              conn
              |> put_flash(:error, "Connected to Shopify but failed to save store information")
              |> redirect(to: "/")
          end

        {:error, reason} ->
          Logger.error("OAuth token exchange failed: #{inspect(reason)}")

          conn
          |> put_flash(:error, "Failed to connect to Shopify: #{reason}")
          |> redirect(to: "/")
      end
    else
      conn
      |> put_flash(:error, "Invalid OAuth state. Possible CSRF attack.")
      |> redirect(to: "/")
    end
  end

  def callback(conn, params) do
    Logger.warning("OAuth callback missing required params: #{inspect(params)}")

    conn
    |> put_flash(:error, "OAuth callback failed - missing required parameters")
    |> redirect(to: "/")
  end

  defp create_or_update_store(store_params) do
    case Repo.get_by(Store, shop_domain: store_params.shop_domain) do
      nil ->
        # Create new store
        %Store{}
        |> Store.changeset(store_params)
        |> Repo.insert()

      existing_store ->
        # Update existing store
        existing_store
        |> Store.changeset(store_params)
        |> Repo.update()
    end
  end

  defp extract_shop_name(shop_domain) do
    shop_domain
    |> String.replace(".myshopify.com", "")
    |> String.replace("-", " ")
    |> String.split(" ")
    |> Enum.map(&String.capitalize/1)
    |> Enum.join(" ")
  end

  defp sanitize_shop_domain(shop) do
    shop
    |> String.trim()
    |> String.downcase()
    |> String.replace(~r/^https?:\/\//, "")
    |> String.replace(~r/\/$/, "")
    |> then(fn domain ->
      if String.ends_with?(domain, ".myshopify.com") do
        domain
      else
        "#{domain}.myshopify.com"
      end
    end)
  end

  defp valid_shop_domain?(shop) do
    String.match?(shop, ~r/^[a-zA-Z0-9\-]+\.myshopify\.com$/)
  end

  defp generate_state do
    :crypto.strong_rand_bytes(32) |> Base.url_encode64()
  end

  defp build_auth_url(shop, state) do
    query_params = %{
      client_id: @shopify_api_key,
      scope: @scopes,
      redirect_uri: @redirect_uri,
      state: state
    }

    query_string = URI.encode_query(query_params)
    "https://#{shop}/admin/oauth/authorize?#{query_string}"
  end

  defp exchange_code_for_token(code, shop) do
    url = "https://#{shop}/admin/oauth/access_token"

    body = %{
      client_id: @shopify_api_key,
      client_secret: get_client_secret(),
      code: code
    }

    case Req.post(url, json: body) do
      {:ok, %{status: 200, body: response}} ->
        {:ok, response["access_token"]}

      {:ok, %{status: status, body: body}} ->
        {:error, "HTTP #{status}: #{inspect(body)}"}

      {:error, reason} ->
        {:error, inspect(reason)}
    end
  end

  defp get_client_secret do
    System.get_env("SHOPIFY_CLIENT_SECRET") ||
      raise "SHOPIFY_CLIENT_SECRET environment variable not set"
  end
end
