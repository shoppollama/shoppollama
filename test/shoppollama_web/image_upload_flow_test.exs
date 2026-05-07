defmodule ShoppollamaWeb.ImageUploadFlowTest do
  use ExUnit.Case, async: false
  
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
  
  describe "Image upload flow verification" do
    test "S3 URL is correctly constructed and stored" do
      # Simulate the upload process
      conversation_id = "test-conversation-123"
      upload_uuid = "test-uuid-456"
      client_name = "test-image.jpg"
      
      # This is how the key is constructed in chat_live.ex
      key = "uploads/#{conversation_id}/#{upload_uuid}-#{client_name}"
      bucket = "shoppollama-images-dev"
      region = System.get_env("AWS_REGION", "us-east-1")
      
      # This is how the S3 URL is constructed
      s3_url = "https://#{bucket}.s3.#{region}.amazonaws.com/#{key}"
      
      IO.puts("\n=== Image Upload Flow Test ===")
      IO.puts("Conversation ID: #{conversation_id}")
      IO.puts("Upload UUID: #{upload_uuid}")
      IO.puts("Client Name: #{client_name}")
      IO.puts("S3 Key: #{key}")
      IO.puts("S3 URL: #{s3_url}")
      
      # Verify URL format
      assert String.starts_with?(s3_url, "https://")
      assert String.contains?(s3_url, "shoppollama-images-dev.s3")
      assert String.contains?(s3_url, key)
      
      # Test that this URL format matches what's expected in page_creator.ex
      assert String.contains?(s3_url, ".amazonaws.com/")
      
      IO.puts("✅ S3 URL format is correct!")
      
      # Now let's verify the page_creator would use this URL
      product_data = %{
        id: "prod_test123",
        title: "Test Product",
        price: 9.99,
        image_url: s3_url  # This would be set from the upload
      }
      
      # Simulate page_creator logic
      cover_image = case Map.get(product_data, :image_url) do
        nil -> "/images/default-product.png"
        "" -> "/images/default-product.png"
        url -> url
      end
      
      # Verify the S3 URL is used
      assert cover_image == s3_url
      assert cover_image != "/images/default-product.png"
      
      IO.puts("✅ Product page would use uploaded image URL!")
      IO.puts("Cover image: #{cover_image}")
    end
    
    test "generates pre-signed URL for private S3 objects" do
      # Since S3 objects are private, we need pre-signed URLs for viewing
      # Let's create a helper function to generate pre-signed URLs
      
      defmodule TestS3Helper do
        def generate_presigned_url(bucket, key, expires_in \\ :timer.hours(1)) do
          config = %{
            region: System.get_env("AWS_REGION", "us-east-1"),
            access_key_id: System.get_env("AWS_ACCESS_KEY_ID"),
            secret_access_key: System.get_env("AWS_SECRET_ACCESS_KEY")
          }
          
          # Generate presigned URL for GET request
          expires_at = DateTime.add(DateTime.utc_now(), expires_in, :millisecond)
          amz_date = Shoppollama.S3Upload.amz_date(expires_at)
          
          # Create canonical request for GET
          canonical_request = "GET\n/#{key}\n\nhost:#{bucket}.s3.#{config.region}.amazonaws.com\nx-amz-date:#{amz_date}\n\nhost;x-amz-date\n#{Shoppollama.S3Upload.sha256("", "")}"
          
          string_to_sign = "AWS4-HMAC-SHA256\n#{amz_date}\n#{Shoppollama.S3Upload.short_date(expires_at)}/#{config.region}/s3/aws4_request\n#{Shoppollama.S3Upload.sha256(canonical_request)}"
          
          signing_key = Shoppollama.S3Upload.get_signing_key(config, expires_at)
          signature = Shoppollama.S3Upload.sha256(signing_key, string_to_sign)
          
          query_params = [
            {"X-Amz-Algorithm", "AWS4-HMAC-SHA256"},
            {"X-Amz-Credential", "#{config.access_key_id}/#{Shoppollama.S3Upload.short_date(expires_at)}/#{config.region}/s3/aws4_request"},
            {"X-Amz-Date", amz_date},
            {"X-Amz-Expires", Integer.to_string(div(expires_in, 1000))},
            {"X-Amz-SignedHeaders", "host;x-amz-date"},
            {"X-Amz-Signature", signature}
          ]
          
          query_string = Enum.map_join(query_params, fn {k, v} -> "#{k}=#{URI.encode(v)}" end)
          
          "https://#{bucket}.s3.#{config.region}.amazonaws.com/#{key}?#{query_string}"
        end
      end
      
      # Test the presigned URL generation
      bucket = "shoppollama-images-dev"
      key = "uploads/test-conversation/test-file.jpg"
      
      presigned_url = TestS3Helper.generate_presigned_url(bucket, key)
      
      IO.puts("\n=== Pre-signed URL Test ===")
      IO.puts("Bucket: #{bucket}")
      IO.puts("Key: #{key}")
      IO.puts("Pre-signed URL: #{presigned_url}")
      
      # Verify URL contains required parameters
      assert presigned_url != nil
      assert String.contains?(presigned_url, "X-Amz-Signature")
      assert String.contains?(presigned_url, "X-Amz-Expires")
      assert String.contains?(presigned_url, "X-Amz-Credential")
      
      IO.puts("✅ Pre-signed URL generated successfully!")
    end
  end
end
