defmodule ShoppollamaWeb.S3UploadRealTest do
  use ExUnit.Case, async: false
  
  # We'll use HTTPoison to make the actual upload request
  # You need to add {:httpoison, "~> 2.0"} to your dependencies if not already there
  
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
  
  describe "Real S3 upload and verification" do
    test "uploads a file to S3 and verifies it exists" do
      config = %{
        region: System.get_env("AWS_REGION", "us-east-1")
      }
      
      bucket = "shoppollama-images-dev"
      test_key = "test/real-upload-test-#{System.unique_integer()}.txt"
      test_content = "This is a real test file uploaded at #{DateTime.utc_now()}"
      
      # Generate signed upload fields
      opts = [
        key: test_key,
        content_type: "text/plain",
        max_file_size: 1_000_000,
        expires_in: :timer.hours(1)
      ]
      
      {:ok, fields} = Shoppollama.S3Upload.sign_form_upload(config, bucket, opts)
      
      # Create multipart form data
      boundary = "----formdata-boundary-#{System.unique_integer()}"
      
      form_parts = Enum.map(fields, fn {k, v} ->
        "--#{boundary}\r\nContent-Disposition: form-data; name=\"#{k}\"\r\n\r\n#{v}\r\n"
      end)
      
      file_part = "--#{boundary}\r\nContent-Disposition: form-data; name=\"file\"; filename=\"test.txt\"\r\nContent-Type: text/plain\r\n\r\n#{test_content}\r\n"
      
      body = (form_parts ++ [file_part, "--#{boundary}--\r\n"])
             |> Enum.join("")
      
      # Make the POST request to S3
      upload_url = "https://#{bucket}.s3.#{config.region}.amazonaws.com"
      
      headers = [
        {"Content-Type", "multipart/form-data; boundary=#{boundary}"}
      ]
      
      IO.puts("\n=== Real S3 Upload Test ===")
      IO.puts("Uploading to: #{upload_url}")
      IO.puts("File key: #{test_key}")
      IO.puts("Content: #{test_content}")
      IO.puts("========================\n")
      
      case HTTPoison.post(upload_url, body, headers) do
        {:ok, %HTTPoison.Response{status_code: 204}} ->
          IO.puts("✅ Upload successful!")
          
          # Now verify the file exists by trying to fetch it
          file_url = "https://#{bucket}.s3.#{config.region}.amazonaws.com/#{test_key}"
          
          case HTTPoison.get(file_url) do
            {:ok, %HTTPoison.Response{status_code: 200, body: ^test_content}} ->
              IO.puts("✅ File verified in S3 bucket!")
              IO.puts("Public URL: #{file_url}")
              
            {:ok, %HTTPoison.Response{status_code: 200, body: body}} ->
              IO.puts("⚠️ File exists but content doesn't match")
              IO.puts("Expected: #{test_content}")
              IO.puts("Got: #{body}")
              
            {:ok, response} ->
              IO.puts("❌ Failed to verify file: #{response.status_code}")
              
            {:error, reason} ->
              IO.puts("❌ Error verifying file: #{inspect(reason)}")
          end
          
        {:ok, %HTTPoison.Response{status_code: status, body: body}} when status in [400, 403] ->
          IO.puts("❌ Upload failed with status #{status}")
          IO.puts("Response: #{body}")
          
          # Try to parse the error
          if String.contains?(body, "<Error>") do
            IO.puts("\nS3 Error Details:")
            # Extract error message
            case Regex.run(~r/<Message>(.+?)<\/Message>/s, body) do
              [_, message] -> IO.puts("Message: #{message}")
              _ -> :no_message
            end
            
            case Regex.run(~r/<Code>(.+?)<\/Code>/s, body) do
              [_, code] -> IO.puts("Code: #{code}")
              _ -> :no_code
            end
          end
          
        {:ok, response} ->
          IO.puts("❌ Unexpected response: #{inspect(response)}")
          
        {:error, reason} ->
          IO.puts("❌ Upload error: #{inspect(reason)}")
      end
    end
    
    test "uploads an image file to S3" do
      config = %{
        region: System.get_env("AWS_REGION", "us-east-1")
      }
      
      bucket = "shoppollama-images-dev"
      test_key = "test/image-test-#{System.unique_integer()}.jpg"
      
      # Create a simple 1x1 pixel JPEG (base64 encoded)
      # This is a tiny valid JPEG image
      jpeg_base64 = "/9j/4AAQSkZJRgABAQEAYABgAAD/2wBDAAEBAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQH/2wBDAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQH/wAARCAABAAEDASIAAhEBAxEB/8QAFQABAQAAAAAAAAAAAAAAAAAAAAv/xAAUEAEAAAAAAAAAAAAAAAAAAAAA/8QAFQEBAQAAAAAAAAAAAAAAAAAAAAX/xAAUEQEAAAAAAAAAAAAAAAAAAAAA/9oADAMBAAIRAxEAPwA/8A8A"
      
      jpeg_binary = Base.decode64!(jpeg_base64)
      
      # Generate signed upload fields
      opts = [
        key: test_key,
        content_type: "image/jpeg",
        max_file_size: 5_000_000,
        expires_in: :timer.hours(1)
      ]
      
      {:ok, fields} = Shoppollama.S3Upload.sign_form_upload(config, bucket, opts)
      
      # Create multipart form data
      boundary = "----formdata-boundary-#{System.unique_integer()}"
      
      form_parts = Enum.map(fields, fn {k, v} ->
        "--#{boundary}\r\nContent-Disposition: form-data; name=\"#{k}\"\r\n\r\n#{v}\r\n"
      end)
      
      file_part = "--#{boundary}\r\nContent-Disposition: form-data; name=\"file\"; filename=\"test.jpg\"\r\nContent-Type: image/jpeg\r\n\r\n#{jpeg_binary}\r\n"
      
      body = (form_parts ++ [file_part, "--#{boundary}--\r\n"])
             |> Enum.join("")
      
      # Make the POST request to S3
      upload_url = "https://#{bucket}.s3.#{config.region}.amazonaws.com"
      
      headers = [
        {"Content-Type", "multipart/form-data; boundary=#{boundary}"}
      ]
      
      IO.puts("\n=== Image Upload Test ===")
      IO.puts("Uploading image to: #{upload_url}")
      IO.puts("File key: #{test_key}")
      IO.puts("File size: #{byte_size(jpeg_binary)} bytes")
      IO.puts("========================\n")
      
      case HTTPoison.post(upload_url, body, headers) do
        {:ok, %HTTPoison.Response{status_code: 204}} ->
          IO.puts("✅ Image upload successful!")
          
          # Verify the image exists
          file_url = "https://#{bucket}.s3.#{config.region}.amazonaws.com/#{test_key}"
          
          case HTTPoison.head(file_url) do
            {:ok, %HTTPoison.Response{status_code: 200}} ->
              IO.puts("✅ Image verified in S3 bucket!")
              IO.puts("Public URL: #{file_url}")
              
            {:ok, response} ->
              IO.puts("❌ Failed to verify image: #{response.status_code}")
              
            {:error, reason} ->
              IO.puts("❌ Error verifying image: #{inspect(reason)}")
          end
          
        {:ok, %HTTPoison.Response{status_code: status, body: body}} ->
          IO.puts("❌ Upload failed with status #{status}")
          IO.puts("Response: #{body}")
          
        {:error, reason} ->
          IO.puts("❌ Upload error: #{inspect(reason)}")
      end
    end
  end
end
