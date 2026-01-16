defmodule ShoppollamaWeb.PageCreatorImageTest do
  use ExUnit.Case, async: false
  
  alias Shoppollama.PageCreator
  alias Shoppollama.Repo
  alias Shoppollama.Product
  
  # Load environment variables from .env file for testing
  setup_all do
    env_file = Path.join(__DIR__, "../../.env")
    if File.exists?(env_file) do
      env_file
      |> File.read!()
      |> String.split("\n")
      |> Enum.each(fn line ->
        line = String.trim(line)
        if line != "" and not String.starts_with?(line, "#") do
          [key, value] = String.split(line, "=", parts: 2)
          System.put_env(String.trim(key), String.trim(value, "\""))
        end
      end)
    end
    
    :ok
  end
  
  describe "PageCreator.get_page_html/1" do
    test "includes image_url from local database when available" do
      # Create a product in the database with an image_url
      stripe_product_id = "prod_test_image_123"
      s3_image_url = "https://shoppollama-images-dev.s3.us-east-1.amazonaws.com/uploads/test/cover.jpg"
      
      # Create product record
      product = %Product{
        id: Ecto.UUID.generate(),
        stripe_product_id: stripe_product_id,
        name: "Test Product",
        description: "Test Description",
        price_cents: 999,
        currency: "usd",
        image_url: s3_image_url,
        image_filename: "cover.jpg",
        image_content_type: "image/jpeg"
      }
      
      # Mock the database query
      defmodule MockRepo do
        def get_by(Product, stripe_product_id: id) do
          if id == "prod_test_image_123" do
            %Product{
              id: Ecto.UUID.generate(),
              stripe_product_id: id,
              name: "Test Product",
              image_url: "https://shoppollama-images-dev.s3.us-east-1.amazonaws.com/uploads/test/cover.jpg"
            }
          else
            nil
          end
        end
      end
      
      # Temporarily replace Repo
      original_repo = Application.get_env(:shoppollama, :repo)
      Application.put_env(:shoppollama, :repo, MockRepo)
      
      # Mock StripeProductClient
      defmodule MockStripeClient do
        def get_product("prod_test_image_123") do
          {:ok, %{
            id: "prod_test_image_123",
            name: "Test Product",
            description: "Test Description",
            price: 9.99
          }}
        end
      end
      
      # Test the function
      result = PageCreator.get_page_html("prod_test_image_123")
      
      # Restore original repo
      Application.put_env(:shoppollama, :repo, original_repo)
      
      # Verify
      assert {:ok, html} = result
      assert String.contains?(html, s3_image_url), "HTML should contain the S3 image URL from database"
      refute String.contains?(html, "/images/default-product.png"), "HTML should not use default image"
      
      IO.puts("\n=== PageCreator Integration Test ===")
      IO.puts("✅ PageCreator retrieves image_url from database")
      IO.puts("✅ HTML contains uploaded image URL")
    end
  end
end
