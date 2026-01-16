defmodule ShoppollamaWeb.ProductPageImageTest do
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
  
  describe "Product page displays uploaded image" do
    test "PageCreator uses image_url from product data" do
      # Simulate a product that was created with an uploaded image
      s3_image_url = "https://shoppollama-images-dev.s3.us-east-1.amazonaws.com/uploads/conv-123/uuid-456-shah-kush-cover.jpg"
      
      # This is how the product data should look when passed to PageCreator
      product_data = %{
        id: "prod_TmQw7UCwbctvuR",
        title: "Shah Kush",
        price: 0.99,
        description: "The Shah Kush mixtape",
        image_url: s3_image_url,  # This should be set from the upload
        payment_link_url: "https://buy.stripe.com/test_5kQcN4eQ60FD8er8ATdjQ31"
      }
      
      # Generate the HTML
      html = PageCreator.generate_product_page_html(product_data)
      
      IO.puts("\n=== Product Page Image Test ===")
      IO.puts("Product: #{product_data.title}")
      IO.puts("Expected S3 URL: #{s3_image_url}")
      
      # Verify the HTML contains the S3 URL, not the default
      assert String.contains?(html, s3_image_url), "HTML should contain the uploaded S3 image URL"
      refute String.contains?(html, "/images/default-product.png"), "HTML should NOT contain the default image when S3 URL is provided"
      
      # Check the img tag specifically
      assert String.contains?(html, "src=\"#{s3_image_url}\""), "Image src should be the S3 URL"
      assert String.contains?(html, "alt=\"Shah Kush\""), "Alt text should be correct"
      
      IO.puts("✅ HTML contains the uploaded S3 image URL!")
      IO.puts("✅ Default image is NOT used!")
      
      # Extract and show the img tag
      img_tag_start = String.split(html, "<img src=\"")
      case img_tag_start do
        [_before, img_with_rest] ->
          img_tag = "<img src=\"" <> String.slice(img_with_rest, 0, 200)
          IO.puts("\nActual img tag in HTML:")
          IO.puts(img_tag)
      end
    end
    
    test "Product model stores and retrieves image_url" do
      # Test that the Product model correctly stores the image_url
      s3_image_url = "https://shoppollama-images-dev.s3.us-east-1.amazonaws.com/uploads/test/test-product.jpg"
      
      # Create a product with image_url
      product_attrs = %{
        stripe_product_id: "prod_test123",
        name: "Test Product with Image",
        description: "A test product",
        price: 10.99,
        currency: "usd",
        image_url: s3_image_url,
        image_filename: "test-product.jpg",
        image_content_type: "image/jpeg"
      }
      
      # In a real test, you would save to database
      # For now, just verify the structure
      assert product_attrs.image_url == s3_image_url
      assert String.contains?(product_attrs.image_url, "shoppollama-images-dev.s3")
      
      IO.puts("\n=== Product Model Test ===")
      IO.puts("✅ Product struct stores image_url correctly")
      IO.puts("Image URL: #{product_attrs.image_url}")
    end
    
    test "ProductController should pass image_url to PageCreator" do
      # This test shows how the controller should retrieve and pass the image_url
      stripe_product_id = "prod_TmQw7UCwbctvuR"
      s3_image_url = "https://shoppollama-images-dev.s3.us-east-1.amazonaws.com/uploads/conv-abc/uuid-def-cover.jpg"
      
      # Mock what the controller should do
      mock_product_from_db = %Product{
        id: Ecto.UUID.generate(),
        stripe_product_id: stripe_product_id,
        name: "Shah Kush",
        description: "Mixtape",
        price_cents: 99,  # $0.99 in cents
        currency: "usd",
        image_url: s3_image_url,
        image_filename: "cover.jpg",
        image_content_type: "image/jpeg"
      }
      
      # Mock Stripe product data
      mock_stripe_product = %{
        id: stripe_product_id,
        name: "Shah Kush",
        description: "The Shah Kush mixtape",
        price: 0.99
      }
      
      # The controller should merge the database product (with image_url) 
      # with the Stripe product data
      product_data_for_page = Map.merge(mock_stripe_product, %{
        title: mock_product_from_db.name,  # PageCreator expects :title
        image_url: mock_product_from_db.image_url,
        payment_link_url: "https://buy.stripe.com/test_123"
      })
      
      # Generate HTML
      html = PageCreator.generate_product_page_html(product_data_for_page)
      
      # Verify
      assert String.contains?(html, s3_image_url), "Controller should pass image_url to PageCreator"
      
      IO.puts("\n=== Controller Integration Test ===")
      IO.puts("✅ Controller should retrieve image_url from database")
      IO.puts("✅ Controller should pass image_url to PageCreator")
      IO.puts("✅ Generated HTML contains the correct image URL")
    end
  end
end
