defmodule ShoppollamaWeb.PageController do
  use ShoppollamaWeb, :controller

  def home(conn, _params) do
    render(conn, :home)
  end
end
