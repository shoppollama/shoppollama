defmodule ShoppollamaWeb.OAuthControllerTest do
  use ShoppollamaWeb.ConnCase
  import Phoenix.LiveViewTest

  describe "GET /auth/shopify" do
    test "renders the authorization form", %{conn: conn} do
      conn = get(conn, ~p"/auth/shopify")

      assert html_response(conn, 200) =~ "Connect Your Shopify Store"
      assert html_response(conn, 200) =~ "Store Domain"
      assert html_response(conn, 200) =~ ".myshopify.com"
      assert html_response(conn, 200) =~ "Connect to Shopify"
    end

    test "redirects to Shopify OAuth with valid shop domain", %{conn: conn} do
      conn = get(conn, ~p"/auth/shopify?shop=2v9s7r-uz")

      assert redirected_to(conn, 302) =~ "https://2v9s7r-uz.myshopify.com/admin/oauth/authorize"
      assert redirected_to(conn, 302) =~ "client_id=356e5aa3ba68f30312214f7cfdfd92da"
      assert redirected_to(conn, 302) =~ "scope=read_products%2Cwrite_products"

      assert redirected_to(conn, 302) =~
               "redirect_uri=http%3A%2F%2Flocalhost%3A4000%2Fauth%2Fshopify%2Fcallback"

      assert redirected_to(conn, 302) =~ "state="

      # Verify state is stored in session
      assert get_session(conn, :oauth_state)
    end

    test "handles full myshopify.com domain", %{conn: conn} do
      conn = get(conn, ~p"/auth/shopify?shop=2v9s7r-uz.myshopify.com")

      assert redirected_to(conn, 302) =~ "https://2v9s7r-uz.myshopify.com/admin/oauth/authorize"
    end

    test "rejects invalid shop domain", %{conn: conn} do
      conn = get(conn, ~p"/auth/shopify?shop=invalid@domain")

      assert redirected_to(conn) == "/"
      assert get_flash(conn, :error) == "Invalid shop domain"
    end
  end

  describe "GET /auth/shopify/callback" do
    test "exchanges code for access token with valid callback", %{conn: conn} do
      # Set up session state
      state = "test_state_123"
      conn = conn |> init_test_session(%{oauth_state: state})

      # Mock successful token exchange
      expect(HTTPoison, :post, fn _url, _body, _headers ->
        {:ok,
         %HTTPoison.Response{
           status_code: 200,
           body: Jason.encode!(%{"access_token" => "test_token_123"})
         }}
      end)

      conn =
        get(
          conn,
          ~p"/auth/shopify/callback?code=test_code&shop=2v9s7r-uz.myshopify.com&state=#{state}"
        )

      assert redirected_to(conn) == "/"

      assert get_flash(conn, :info) =~
               "Successfully connected to Shopify store: 2v9s7r-uz.myshopify.com"

      assert get_session(conn, :shopify_access_token) == "test_token_123"
      assert get_session(conn, :shopify_shop) == "2v9s7r-uz.myshopify.com"
    end

    test "rejects callback with invalid state (CSRF protection)", %{conn: conn} do
      # Set up session with different state
      conn = conn |> init_test_session(%{oauth_state: "correct_state"})

      conn =
        get(
          conn,
          ~p"/auth/shopify/callback?code=test_code&shop=2v9s7r-uz.myshopify.com&state=wrong_state"
        )

      assert redirected_to(conn) == "/"
      assert get_flash(conn, :error) == "Invalid OAuth state. Possible CSRF attack."
    end

    test "handles token exchange failure", %{conn: conn} do
      state = "test_state_123"
      conn = conn |> init_test_session(%{oauth_state: state})

      # Mock failed token exchange
      expect(HTTPoison, :post, fn _url, _body, _headers ->
        {:ok,
         %HTTPoison.Response{
           status_code: 400,
           body: Jason.encode!(%{"errors" => "invalid_request"})
         }}
      end)

      conn =
        get(
          conn,
          ~p"/auth/shopify/callback?code=invalid_code&shop=2v9s7r-uz.myshopify.com&state=#{state}"
        )

      assert redirected_to(conn) == "/"
      assert get_flash(conn, :error) =~ "Failed to connect to Shopify"
    end
  end
end
