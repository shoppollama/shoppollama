defmodule ShoppollamaWeb.PageController do
  use ShoppollamaWeb, :controller
  alias Shoppollama.PageCreator

  def home(conn, _params) do
    render(conn, :home)
  end

  def product(conn, %{"product_id" => product_id}) do
    case PageCreator.get_page_html(product_id) do
      {:ok, html} ->
        conn
        |> put_resp_content_type("text/html")
        |> send_resp(200, html)
      
      {:error, _reason} ->
        conn
        |> put_resp_content_type("text/html")
        |> send_resp(404, "<html><body><h1>Product not found</h1></body></html>")
    end
  end
end
