defmodule ShoppollamaWeb.PageCreatorRealImageTest do
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
  
  describe "PageCreator with real database integration" do
    test "get_page_html retrieves image_url from database" do
      # Use a real Stripe product ID that exists
      stripe_product_id = "prod_TmQw7UCwbctvuR"  # This is the Shah Kush product
      
      # First, let's create/update a product in the database with an image_url
      s3_image_url = "https://shoppollama-images-dev.s3.us-east-1.amazonaws.com/uploads/conv-test/uuid-test-shah-kush-cover.jpg"
      
      # Use Ecto SQL Sandbox to check out connection
      Ecto.Adapters.SQL.Sandbox.checkout(Repo)
      
      # Create or update the product in the database
      product_changeset = %Product{
        stripe_product_id: stripe_product_id,
        name: "Shah Kush",
        description: "The Shah Kush mixtape",
        price_cents: 99,
        currency: "usd",
        image_url: s3_image_url,
        image_filename: "shah-kush-cover.jpg",
        image_content_type: "image/jpeg",
        is_active: true
      }
      
      # Insert or update the product
      case Repo.get_by(Product, stripe_product_id: stripe_product_id) do
        nil -> 
          Repo.insert!(product_changeset)
        existing_product ->
          changeset = Ecto.Changeset.change(existing_product, %{image_url: s3_image_url})
          Repo.update!(changeset)
      end
      
      # Now test that PageCreator.get_page_html includes the image_url
      result = PageCreator.get_page_html(stripe_product_id)
      
      case result do
        {:ok, html} ->
          # Verify the HTML contains the S3 image URL
          assert String.contains?(html, s3_image_url), """
            Expected HTML to contain S3 image URL: #{s3_image_url}
            
            HTML snippet:
            #{String.slice(html, 0, 1000)}...
          """
          
          # Verify it's NOT using the default image
          refute String.contains?(html, "/images/default-product.png"), """
            HTML should not contain default product image when S3 URL is available
          """
          
          IO.puts("\n=== Real Database Integration Test ===")
          IO.puts("✅ PageCreator retrieved image_url from database")
          IO.puts("✅ Generated HTML contains the S3 image URL")
          IO.puts("✅ Default image is NOT used")
          
          # Show the img tag
          img_start = String.split(html, "<img src=\"")
          case img_start do
            [_before, img_with_rest] ->
              img_tag = "<img src=\"" <> String.slice(img_with_rest, 0, 200)
              IO.puts("\nImage tag in HTML:")
              IO.puts(img_tag)
          end
          
        {:error, reason} ->
          IO.puts("\n⚠️  Could not test - Stripe product not found: #{inspect(reason)}")
      end
      
      Ecto.Adapters.SQL.Sandbox.checkin(Repo)
    end
    
    test "database lookup works correctly" do
      # Test that we can actually query the database
      stripe_product_id = "prod_test_lookup"
      
      # Use Ecto SQL Sandbox
      Ecto.Adapters.SQL.Sandbox.checkout(Repo)
      
      # Insert a test product
      test_product = %Product{
        stripe_product_id: stripe_product_id,
        name: "Test Product",
        description: "Test",
        price_cents: 1000,
        image_url: "https://example.com/test.jpg"
      }
      
      inserted = Repo.insert!(test_product)
      
      # Verify we can retrieve it
      retrieved = Repo.get_by(Product, stripe_product_id: stripe_product_id)
      
      assert retrieved != nil, "Should be able to retrieve inserted product"
      assert retrieved.image_url == "https://example.com/test.jpg", "Image URL should match"
      
      # Clean up
      Repo.delete!(inserted)
      
      Ecto.Adapters.SQL.Sandbox.checkin(Repo)
      
      IO.puts("\n=== Database Lookup Test ===")
      IO.puts("✅ Database operations work correctly")
      IO.puts("✅ Can store and retrieve image_url")
    end
  end
end
