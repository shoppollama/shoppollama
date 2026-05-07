defmodule ShoppollamaWeb.ImageUploadHTMLTest do
  use ExUnit.Case, async: false
  
  alias Shoppollama.PageCreator
  
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
  
  describe "Image appears in product page HTML" do
    test "product page HTML contains uploaded S3 image URL" do
      # Create a product with an S3 image URL
      s3_image_url = "https://shoppollama-images-dev.s3.us-east-1.amazonaws.com/uploads/test-123/test-image.jpg"
      
      product_data = %{
        id: "prod_test123",
        title: "Shah Kush Mixtape",
        price: 0.99,
        description: "A quality product from ShoppOllama",
        image_url: s3_image_url,
        payment_link_url: "https://buy.stripe.com/test_123"
      }
      
      # Generate the HTML
      html = PageCreator.generate_product_page_html(product_data)
      
      IO.puts("\n=== Image in HTML Test ===")
      IO.puts("Product: #{product_data.title}")
      IO.puts("S3 Image URL: #{s3_image_url}")
      
      # Verify the HTML contains the S3 URL
      assert String.contains?(html, s3_image_url), "HTML should contain the S3 image URL"
      assert String.contains?(html, "src=\"#{s3_image_url}\""), "HTML should have the S3 URL in img src attribute"
      assert String.contains?(html, "class=\"hero-image\""), "HTML should have the hero-image class"
      
      # Verify it's NOT using the default placeholder
      refute String.contains?(html, "/images/default-product.png"), "HTML should not use default product image when S3 URL is provided"
      
      IO.puts("✅ HTML contains S3 image URL!")
      IO.puts("✅ Image is not the default placeholder!")
      
      # Show a snippet of the HTML with the image
      IO.puts("\nImage tag found in HTML (first 200 chars of img tag):")
      
      # Find the img tag with the S3 URL
      img_start = String.split(html, "<img src=\"#{s3_image_url}")
      case img_start do
        [_before, img_with_rest] ->
          img_tag = "<img src=\"#{s3_image_url}" <> String.slice(img_with_rest, 0, 100)
          IO.puts(img_tag)
        _ ->
          IO.puts("Could not extract img tag snippet")
      end
    end
    
    test "product page uses default image when no S3 URL provided" do
      # Create a product without an image URL
      product_data = %{
        id: "prod_test456",
        title: "No Image Product",
        price: 1.99,
        description: "A product without an image",
        image_url: nil,
        payment_link_url: "https://buy.stripe.com/test_456"
      }
      
      # Generate the HTML
      html = PageCreator.generate_product_page_html(product_data)
      
      IO.puts("\n=== Default Image Test ===")
      IO.puts("Product: #{product_data.title}")
      
      # Verify the HTML contains the default image
      assert String.contains?(html, "/images/default-product.png"), "HTML should contain default image when no S3 URL"
      assert String.contains?(html, "src=\"/images/default-product.png\""), "HTML should have default image in img src"
      
      IO.puts("✅ HTML uses default image when no S3 URL provided!")
    end
    
    test "simulated upload flow generates correct S3 URL" do
      # Simulate the upload flow from chat_live.ex
      conversation_id = "conv-#{System.unique_integer()}"
      upload_uuid = "#{System.unique_integer()}-#{System.unique_integer()}"
      client_name = "mixtape-cover.jpg"
      
      # This is how the key is built in presign_upload
      key = "uploads/#{conversation_id}/#{upload_uuid}-#{client_name}"
      bucket = "shoppollama-images-dev"
      region = System.get_env("AWS_REGION", "us-east-1")
      
      # This is how the S3 URL is built after upload
      s3_url = "https://#{bucket}.s3.#{region}.amazonaws.com/#{key}"
      
      IO.puts("\n=== Upload Flow Simulation ===")
      IO.puts("Conversation ID: #{conversation_id}")
      IO.puts("Upload UUID: #{upload_uuid}")
      IO.puts("Client Name: #{client_name}")
      IO.puts("Generated Key: #{key}")
      IO.puts("S3 URL: #{s3_url}")
      
      # Create product with this S3 URL
      product_data = %{
        id: "prod_flow_test",
        title: "Test Mixtape",
        price: 5.99,
        image_url: s3_url,
        description: "A test product"
      }
      
      # Generate HTML
      html = PageCreator.generate_product_page_html(product_data)
      
      # Verify the flow works
      assert String.contains?(html, s3_url), "HTML should contain the uploaded image URL"
      assert String.contains?(html, "alt=\"Test Mixtape\""), "HTML should have correct alt text"
      
      IO.puts("✅ Upload flow generates correct S3 URL in HTML!")
    end
  end
end
