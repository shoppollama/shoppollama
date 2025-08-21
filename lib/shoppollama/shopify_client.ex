defmodule Shoppollama.ShopifyClient do
  @moduledoc """
  Handles Shopify API interactions for product management
  """

  require Logger

  @base_url "https://silicon-valley-shirts.myshopify.com"
  @api_version "2024-07"

  def create_product(product_data) do
    headers = [
      {"Content-Type", "application/json"},
      {"X-Shopify-Access-Token", get_access_token()}
    ]

    url = "#{@base_url}/admin/api/#{@api_version}/products.json"

    body = %{
      product: %{
        title: product_data.title,
        body_html: product_data.description || "<p>#{product_data.title}</p>",
        vendor: product_data.vendor || "ShoppOllama",
        product_type: product_data.product_type || "General",
        status: "active",
        variants: [
          %{
            price: product_data.price,
            inventory_quantity: product_data.inventory || 10,
            inventory_management: "shopify",
            inventory_policy: "deny"
          }
        ]
      }
    }

    case Req.post(url, json: body, headers: headers) do
      {:ok, %{status: 201, body: response}} ->
        product = response["product"]

        admin_url =
          "https://admin.shopify.com/store/silicon-valley-shirts/products/#{product["id"]}"

        {:ok,
         %{
           id: product["id"],
           title: product["title"],
           handle: product["handle"],
           admin_url: admin_url,
           store_url: "#{@base_url}/products/#{product["handle"]}"
         }}

      {:ok, %{status: status, body: body}} ->
        Logger.error("Shopify API error: #{status} - #{inspect(body)}")
        {:error, "Failed to create product: #{body["errors"] || "Unknown error"}"}

      {:error, reason} ->
        Logger.error("Request failed: #{inspect(reason)}")
        {:error, "Network error: #{inspect(reason)}"}
    end
  end

  def get_products(limit \\ 10) do
    headers = [
      {"X-Shopify-Access-Token", get_access_token()}
    ]

    url = "#{@base_url}/admin/api/#{@api_version}/products.json?limit=#{limit}"

    case Req.get(url, headers: headers) do
      {:ok, %{status: 200, body: response}} ->
        products =
          Enum.map(response["products"], fn product ->
            %{
              id: product["id"],
              title: product["title"],
              handle: product["handle"],
              admin_url:
                "https://admin.shopify.com/store/silicon-valley-shirts/products/#{product["id"]}"
            }
          end)

        {:ok, products}

      {:error, reason} ->
        Logger.error("Failed to fetch products: #{inspect(reason)}")
        {:error, reason}
    end
  end

  def get_product_count do
    headers = [
      {"X-Shopify-Access-Token", get_access_token()}
    ]

    url = "#{@base_url}/admin/api/#{@api_version}/products/count.json"

    case Req.get(url, headers: headers) do
      {:ok, %{status: 200, body: response}} ->
        {:ok, response["count"]}

      {:ok, %{status: status, body: body}} ->
        Logger.error("Shopify API error (count): #{status} - #{inspect(body)}")
        {:error, "Failed to fetch product count: #{body["errors"] || "Unknown error"}"}

      {:error, reason} ->
        Logger.error("Request failed (count): #{inspect(reason)}")
        {:error, reason}
    end
  end

  defp get_access_token do
    # For now, we'll use environment variable
    # In production, you'd use proper OAuth flow
    System.get_env("SHOPIFY_ACCESS_TOKEN") ||
      raise "SHOPIFY_ACCESS_TOKEN environment variable not set"
  end
end
