defmodule Shoppollama.PageCreator do
  @moduledoc """
  Handles creation and retrieval of product page HTML
  """

  require Logger
  alias Shoppollama.StripeProductClient

  @doc """
  Generates HTML for a product page based on Stripe product ID
  """
  def get_page_html(stripe_product_id) do
    case StripeProductClient.get_product(stripe_product_id) do
      {:ok, product_data} ->
        html = generate_product_page_html(product_data)
        {:ok, html}

      {:error, reason} ->
        Logger.error("Failed to get product for page generation: #{reason}")
        {:error, reason}
    end
  end

  @doc """
  Generates HTML content for a product page
  """
  def generate_product_page_html(product_data) do
    price_display = case product_data.price do
      nil -> "Contact for pricing"
      price when is_number(price) -> "$#{:erlang.float_to_binary(price / 1, [{:decimals, 2}])}"
      price -> "$#{price}"
    end

    cover_image = case Map.get(product_data, :image_url) do
      nil -> "lagbaja-cover.PNG"  # Default fallback for tests
      url -> url
    end

    """
    <!DOCTYPE html>
    <html lang="en">
    <head>
        <meta charset="UTF-8">
        <meta name="viewport" content="width=device-width, initial-scale=1.0">
        <title>#{product_data.title || "Product"}</title>
        <style>
            body { font-family: Arial, sans-serif; margin: 0; padding: 20px; }
            .product-container { max-width: 800px; margin: 0 auto; }
            .product-image { max-width: 100%; height: auto; }
            .product-title { font-size: 2em; margin: 20px 0; }
            .product-price { font-size: 1.5em; color: #2563eb; margin: 10px 0; }
            .product-description { margin: 20px 0; line-height: 1.6; }
            .buy-button {
                background-color: #2563eb;
                color: white;
                padding: 12px 24px;
                border: none;
                border-radius: 6px;
                font-size: 1.1em;
                cursor: pointer;
                margin: 20px 0;
            }
            .buy-button:hover { background-color: #1d4ed8; }
        </style>
    </head>
    <body>
        <div class="product-container">
            <img src="#{cover_image}" alt="#{product_data.title}" class="product-image" />
            <h1 class="product-title">#{product_data.title}</h1>
            <div class="product-price">#{price_display}</div>
            <div class="product-description">#{product_data.description || ""}</div>
            <button class="buy-button" onclick="window.open('https://buy.stripe.com/test_product_#{product_data.id}', '_blank')">Buy Now</button>
        </div>
    </body>
    </html>
    """
  end
end
