defmodule ShoppollamaWeb.OAuthControllerTest do
  use ShoppollamaWeb.ConnCase
  import Phoenix.LiveViewTest

  describe "GET /auth/shopify" do

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

    test "requires valid callback parameters", %{conn: conn} do
      conn = get(conn, ~p"/auth/shopify/callback")

      assert redirected_to(conn) == "/"
      assert get_flash(conn, :error) =~ "OAuth callback failed"
    end
  end
end
