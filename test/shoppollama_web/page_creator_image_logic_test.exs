defmodule ShoppollamaWeb.PageCreatorImageLogicTest do
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
  
  describe "PageCreator image URL logic" do
    test "generate_product_page_html uses provided image_url" do
      # Test that when image_url is provided, it's used in the HTML
      s3_image_url = "https://shoppollama-images-dev.s3.us-east-1.amazonaws.com/uploads/test/product-image.jpg"
      
      product_data = %{
        id: "prod_123",
        title: "Test Product",
        price: 9.99,
        description: "A test product",
        image_url: s3_image_url
      }
      
      html = PageCreator.generate_product_page_html(product_data)
      
      # Verify
      assert String.contains?(html, s3_image_url), "HTML should contain the S3 image URL"
      refute String.contains?(html, "/images/default-product.png"), "HTML should not use default image"
      
      IO.puts("\n=== PageCreator Image Logic Test ===")
      IO.puts("✅ When image_url is provided, it's used in HTML")
      IO.puts("✅ Default image is not used when image_url is provided")
    end
    
    test "generate_product_page_html uses default when no image_url" do
      # Test that when image_url is nil, default is used
      product_data = %{
        id: "prod_456",
        title: "Product No Image",
        price: 5.99,
        description: "A product without image",
        image_url: nil
      }
      
      html = PageCreator.generate_product_page_html(product_data)
      
      # Verify
      assert String.contains?(html, "/images/default-product.png"), "HTML should use default image when no image_url"
      
      IO.puts("\n=== Default Image Test ===")
      IO.puts("✅ When image_url is nil, default image is used")
    end
  end
end
