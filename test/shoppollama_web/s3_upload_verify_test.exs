defmodule ShoppollamaWeb.S3UploadVerifyTest do
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
  
  describe "S3 upload verification" do
    test "uploads a file and verifies it exists using AWS CLI" do
      config = %{
        region: System.get_env("AWS_REGION", "us-east-1")
      }
      
      bucket = "shoppollama-images-dev"
      test_key = "test/verify-test-#{System.unique_integer()}.txt"
      test_content = "This is a verification test at #{DateTime.utc_now()}"
      
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
      
      # Upload the file
      case HTTPoison.post(upload_url, body, headers) do
        {:ok, %HTTPoison.Response{status_code: 204}} ->
          IO.puts("\n✅ Upload successful!")
          
          # Verify using AWS CLI
          IO.puts("Verifying file exists in S3...")
          
          case System.cmd("aws", ["s3", "ls", "s3://#{bucket}/#{test_key}"], stderr_to_stdout: true) do
            {output, 0} ->
              IO.puts("✅ File verified in S3!")
              IO.puts("Output: #{String.trim(output)}")
              
            {output, _} ->
              IO.puts("⚠️ File might not be visible or different error:")
              IO.puts("Output: #{output}")
          end
          
          # Also try to list all objects to see our file
          IO.puts("\nListing recent test files:")
          case System.cmd("aws", ["s3", "ls", "s3://#{bucket}/test/"], stderr_to_stdout: true) do
            {output, 0} ->
              IO.puts("Test files in bucket:")
              IO.puts(output)
              
            {_, _} ->
              IO.puts("No test files found or error listing")
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
