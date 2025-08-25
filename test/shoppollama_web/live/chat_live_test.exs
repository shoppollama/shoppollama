defmodule ShoppollamaWeb.ChatLiveTest do
  use ShoppollamaWeb.ConnCase
  import Phoenix.LiveViewTest
  alias Shoppollama.{Repo, Store}

  describe "ChatLive OAuth Integration" do

    test "displays store connection status correctly", %{conn: conn} do
      # Create a store in the database to simulate connected state
      {:ok, _store} =
        %Store{}
        |> Store.changeset(%{
          shop_domain: "2v9s7r-uz.myshopify.com",
          access_token: "test_token",
          shop_name: "Test Store",
          is_active: true
        })
        |> Repo.insert()

      # Start the LiveView
      {:ok, view, _html} = live(conn, "/")

      # Should show "Store Connected" since we have an active store
      assert has_element?(view, "button", "Store Connected")
      refute has_element?(view, "button", "Connect Store")
    end


  end
end
