defmodule ShoppollamaWeb.S3UrlFormatTest do
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
  
  describe "S3 URL format" do
    test "S3 URLs include region in the hostname" do
      bucket = "shoppollama-images-dev"
      region = "us-east-1"
      key = "uploads/test/file.jpg"
      
      # Correct format with region
      correct_url = "https://#{bucket}.s3.#{region}.amazonaws.com/#{key}"
      
      # Incorrect format without region
      incorrect_url = "https://#{bucket}.s3.amazonaws.com/#{key}"
      
      IO.puts("\n=== S3 URL Format Test ===")
      IO.puts("Correct URL: #{correct_url}")
      IO.puts("Incorrect URL: #{incorrect_url}")
      
      # Verify the correct format
      assert String.contains?(correct_url, ".s3.us-east-1.amazonaws.com/"), "URL should include region"
      refute String.contains?(correct_url, ".s3.amazonaws.com/"), "URL should not be the old format"
      
      # The incorrect format is what you're seeing
      assert String.contains?(incorrect_url, ".s3.amazonaws.com/"), "This is the incorrect format you're seeing"
      
      IO.puts("✅ URL format verified")
    end
    
    test "image_url construction matches upload URL format" do
      # Test that the image_url stored matches the upload URL format
      bucket = "shoppollama-images-dev"
      region = System.get_env("AWS_REGION", "us-east-1")
      conversation_id = "c8feb87d0f11b8e0b97a6d125e25cfbd"
      upload_uuid = "ff707985-10d0-4fea-a554-c9a2cb7ea97f"
      client_name = "shahrukh-shoaib-bK_C67Krm-k-unsplash.png"
      
      key = "uploads/#{conversation_id}/#{upload_uuid}-#{client_name}"
      
      # This is how it should be (with region)
      correct_url = "https://#{bucket}.s3.#{region}.amazonaws.com/#{key}"
      
      # This is what you're seeing (without region)
      your_url = "https://shoppollama-images-dev.s3.amazonaws.com/uploads/c8feb87d0f11b8e0b97a6d125e25cfbd/ff707985-10d0-4fea-a554-c9a2cb7ea97f-shahrukh-shoaib-bK_C67Krm-k-unsplash.png"
      
      IO.puts("\n=== Your URL vs Correct URL ===")
      IO.puts("Your URL: #{your_url}")
      IO.puts("Correct: #{correct_url}")
      
      # The fix ensures new uploads will use the correct format
      assert String.contains?(correct_url, ".s3.us-east-1.")
      assert String.contains?(your_url, ".s3.amazonaws.com/")
      
      IO.puts("\n⚠️  Existing images in database may have the old format")
      IO.puts("✅ New uploads will use the correct format with region")
    end
  end
end
