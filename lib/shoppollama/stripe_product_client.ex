defmodule Shoppollama.StripeProductClient do
  @moduledoc """
  Handles all product operations exclusively through Stripe API.
  This module ensures no product data is stored in local databases.
  """

  require Logger
  alias Shoppollama.ProductParser

  @doc """
  Creates a product exclusively in Stripe with comprehensive validation
  """
  def create_product(product_data) do
    with :ok <- validate_product_data(product_data),
         {:ok, stripe_product} <- create_stripe_product(product_data),
         {:ok, stripe_price} <- create_stripe_price(stripe_product.id, product_data),
         {:ok, payment_link} <- create_payment_link(stripe_price.id, product_data.title),
         {:ok, updated_product} <- update_product_with_payment_link(stripe_product.id, payment_link.url),
         {:ok, _verification} <- verify_product_name(updated_product, product_data.title) do
      {:ok, %{
        stripe_product: updated_product,
        stripe_price: stripe_price,
        payment_link: payment_link,
        verified_name: updated_product.name
      }}
    else
      {:error, reason} -> {:error, reason}
    end
  end

  @doc """
  Retrieves a product exclusively from Stripe
  """
  def get_product(product_id) do
    case Stripe.Product.retrieve(product_id) do
      {:ok, product} ->
        # Also get the associated prices
        case get_product_prices(product_id) do
          {:ok, prices} ->
            result = format_product_with_prices(product, prices)
            # Get payment link URL from product metadata
            result_with_payment_link = case product.metadata["payment_link_url"] do
              nil -> result
              payment_link_url -> Map.put(result, :payment_link_url, payment_link_url)
            end
            {:ok, result_with_payment_link}
          
          {:error, reason} ->
            Logger.warning("Could not retrieve prices for product #{product_id}: #{reason}")
            # Return product without price info
            {:ok, format_product(product)}
        end

      {:error, %Stripe.Error{} = error} ->
        Logger.error("Failed to retrieve Stripe product #{product_id}: #{error.message}")
        {:error, "Product not found: #{error.message}"}

      {:error, reason} ->
        Logger.error("Failed to retrieve Stripe product #{product_id}: #{inspect(reason)}")
        {:error, "Failed to retrieve product: #{inspect(reason)}"}
    end
  end

  @doc """
  Lists products exclusively from Stripe with pagination
  """
  def list_products(opts \\ []) do
    limit = Keyword.get(opts, :limit, 10)
    starting_after = Keyword.get(opts, :starting_after)
    
    params = %{limit: limit}
    params = if starting_after, do: Map.put(params, :starting_after, starting_after), else: params

    case Stripe.Product.list(params) do
      {:ok, %{data: products, has_more: has_more}} ->
        formatted_products = Enum.map(products, &format_product/1)
        
        result = %{
          products: formatted_products,
          has_more: has_more,
          count: length(formatted_products)
        }
        
        {:ok, result}

      {:error, %Stripe.Error{} = error} ->
        Logger.error("Failed to list Stripe products: #{error.message}")
        {:error, "Failed to list products: #{error.message}"}

      {:error, reason} ->
        Logger.error("Failed to list Stripe products: #{inspect(reason)}")
        {:error, "Failed to list products: #{inspect(reason)}"}
    end
  end

  @doc """
  Updates a product exclusively in Stripe
  """
  def update_product(product_id, updates) do
    with :ok <- validate_product_updates(updates),
         {:ok, updated_product} <- Stripe.Product.update(product_id, updates) do
      
      Logger.info("Successfully updated Stripe product: #{product_id}")
      {:ok, format_product(updated_product)}
    else
      {:error, %Stripe.Error{} = error} ->
        Logger.error("Failed to update Stripe product #{product_id}: #{error.message}")
        {:error, "Failed to update product: #{error.message}"}

      {:error, reason} ->
        Logger.error("Failed to update Stripe product #{product_id}: #{inspect(reason)}")
        {:error, reason}
    end
  end

  @doc """
  Deletes a product exclusively from Stripe
  """
  def delete_product(product_id) do
    case Stripe.Product.delete(product_id) do
      {:ok, _deleted_product} ->
        Logger.info("Successfully deleted Stripe product: #{product_id}")
        {:ok, :deleted}

      {:error, %Stripe.Error{} = error} ->
        Logger.error("Failed to delete Stripe product #{product_id}: #{error.message}")
        {:error, "Failed to delete product: #{error.message}"}

      {:error, reason} ->
        Logger.error("Failed to delete Stripe product #{product_id}: #{inspect(reason)}")
        {:error, "Failed to delete product: #{inspect(reason)}"}
    end
  end

  @doc """
  Gets the total count of products in Stripe
  """
  def get_product_count do
    # Stripe doesn't have a direct count API, so we need to list with limit 1 and check has_more
    case Stripe.Product.list(%{limit: 1}) do
      {:ok, %{data: []}} ->
        {:ok, 0}
        
      {:ok, _} ->
        # For accurate count, we'd need to paginate through all products
        # For now, return an estimate or implement full pagination if needed
        {:ok, :many}

      {:error, %Stripe.Error{} = error} ->
        Logger.error("Failed to get Stripe product count: #{error.message}")
        {:error, "Failed to get product count: #{error.message}"}

      {:error, reason} ->
        Logger.error("Failed to get Stripe product count: #{inspect(reason)}")
        {:error, "Failed to get product count: #{inspect(reason)}"}
    end
  end

  # Private helper functions

  defp validate_product_data(product_data) do
    cond do
      is_nil(product_data.title) or String.trim(product_data.title) == "" ->
        {:error, "Product title is required"}
      
      is_nil(product_data.price) or product_data.price <= 0 ->
        {:error, "Product price must be greater than 0"}
      
      String.length(product_data.title) > 250 ->
        {:error, "Product title must be 250 characters or less"}
      
      product_data.description && String.length(product_data.description) > 5000 ->
        {:error, "Product description must be 5000 characters or less"}
      
      true ->
        :ok
    end
  end

  defp validate_product_updates(updates) do
    cond do
      Map.has_key?(updates, :name) and (is_nil(updates.name) or String.trim(updates.name) == "") ->
        {:error, "Product name cannot be empty"}
      
      Map.has_key?(updates, :name) and String.length(updates.name) > 250 ->
        {:error, "Product name must be 250 characters or less"}
      
      Map.has_key?(updates, :description) and updates.description && String.length(updates.description) > 5000 ->
        {:error, "Product description must be 5000 characters or less"}
      
      true ->
        :ok
    end
  end

  defp create_stripe_product(product_data) do
    params = %{
      name: product_data.title,
      description: product_data.description || "#{product_data.title} - Created via ShoppOllama",
      type: "good",
      metadata: %{
        source: "shoppollama",
        product_type: product_data.product_type || "general",
        vendor: product_data.vendor || "ShoppOllama",
        inventory: to_string(product_data.inventory || 10),
        created_via: "stripe_only_storage"
      }
    }

    case Stripe.Product.create(params) do
      {:ok, product} ->
        {:ok, product}

      {:error, %Stripe.Error{} = error} ->
        {:error, "Stripe product creation failed: #{error.message}"}

      {:error, reason} ->
        {:error, "Stripe product creation failed: #{inspect(reason)}"}
    end
  end

  defp create_stripe_price(product_id, product_data) do
    # Convert price to cents (Stripe expects amounts in smallest currency unit)
    unit_amount = round(product_data.price * 100)

    params = %{
      product: product_id,
      unit_amount: unit_amount,
      currency: "usd",
      metadata: %{
        source: "shoppollama",
        original_price: to_string(product_data.price)
      }
    }

    case Stripe.Price.create(params) do
      {:ok, price} ->
        {:ok, price}

      {:error, %Stripe.Error{} = error} ->
        {:error, "Stripe price creation failed: #{error.message}"}

      {:error, reason} ->
        {:error, "Stripe price creation failed: #{inspect(reason)}"}
    end
  end

  defp create_payment_link(price_id, product_title) do
    params = %{
      line_items: [
        %{
          price: price_id,
          quantity: 1
        }
      ],
      metadata: %{
        source: "shoppollama",
        product_title: product_title
      }
    }

    case Stripe.PaymentLink.create(params) do
      {:ok, payment_link} ->
        {:ok, payment_link}

      {:error, %Stripe.Error{} = error} ->
        {:error, "Stripe payment link creation failed: #{error.message}"}

      {:error, reason} ->
        {:error, "Stripe payment link creation failed: #{inspect(reason)}"}
    end
  end

  defp update_product_with_payment_link(product_id, payment_link_url) do
    params = %{
      metadata: %{
        payment_link_url: payment_link_url
      }
    }

    case Stripe.Product.update(product_id, params) do
      {:ok, updated_product} ->
        {:ok, updated_product}

      {:error, %Stripe.Error{} = error} ->
        {:error, "Failed to update product with payment link: #{error.message}"}

      {:error, reason} ->
        {:error, "Failed to update product with payment link: #{inspect(reason)}"}
    end
  end

  defp get_product_prices(product_id) do
    case Stripe.Price.list(%{product: product_id}) do
      {:ok, %{data: prices}} ->
        {:ok, prices}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp get_payment_link_for_price(price_id) do
    # List payment links and find one that uses this price
    case Stripe.PaymentLink.list(%{}) do
      {:ok, %{data: payment_links}} ->
        payment_link = Enum.find(payment_links, fn link ->
          case link.line_items do
            %{data: items} when is_list(items) ->
              Enum.any?(items, fn item ->
                case item.price do
                  %{id: ^price_id} -> true
                  _ -> false
                end
              end)
            _ -> false
          end
        end)
        
        case payment_link do
          %{url: url} -> {:ok, url}
          nil -> {:error, "No payment link found for price"}
        end

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp format_product(product) do
    %{
      id: product.id,
      title: product.name,
      description: product.description,
      images: product.images || [],
      metadata: product.metadata,
      created_at: product.created,
      updated_at: product.updated
    }
  end

  defp format_product_with_prices(product, prices) do
    primary_price = List.first(prices)
    
    base_product = format_product(product)
    
    if primary_price do
      Map.merge(base_product, %{
        price: primary_price.unit_amount / 100,
        price_id: primary_price.id,
        currency: primary_price.currency
      })
    else
      base_product
    end
  end

  @doc """
  Checks if Stripe is properly configured
  """
  def configured? do
    case Application.get_env(:stripity_stripe, :api_key) do
      nil -> false
      "" -> false
      _key -> true
    end
  end

  # New function to verify product name after creation
  defp verify_product_name(stripe_product, expected_name) do
    if stripe_product.name == expected_name do
      {:ok, %{verified: true, actual_name: stripe_product.name, expected_name: expected_name}}
    else
      {:error, "Product name mismatch: expected '#{expected_name}', got '#{stripe_product.name}'"}
    end
  end
end