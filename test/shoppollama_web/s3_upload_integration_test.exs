defmodule ShoppollamaWeb.S3UploadIntegrationTest do
  use ExUnit.Case, async: false
  
  alias Shoppollama.S3Upload
  
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
  
  describe "S3 upload integration" do
    test "can generate upload URL and upload a small test file" do
      config = %{
        region: System.get_env("AWS_REGION", "us-east-1")
      }
      
      bucket = "shoppollama-images-dev"
      test_key = "test/integration-test-#{System.unique_integer()}.txt"
      
      opts = [
        key: test_key,
        content_type: "text/plain",
        max_file_size: 1_000_000,
        expires_in: :timer.hours(1)
      ]
      
      # Generate signed upload fields
      {:ok, fields} = S3Upload.sign_form_upload(config, bucket, opts)
      
      # Verify all required fields
      required_fields = ["key", "policy", "x-amz-credential", "x-amz-algorithm", 
                        "x-amz-date", "x-amz-signature", "acl", "content-type"]
      
      Enum.each(required_fields, fn field ->
        assert Map.has_key?(fields, field), "Missing field: #{field}"
      end)
      
      # Create test file content
      test_content = "This is a test file uploaded at #{DateTime.utc_now()}"
      
      # Prepare form data for upload
      form_data = Enum.map(fields, fn {k, v} -> {k, v} end) ++
                  [{"file", test_content}]
      
      # Print the upload URL for manual testing
      upload_url = "https://#{bucket}.s3.#{config.region}.amazonaws.com"
      IO.puts("\n=== S3 Upload Test ===")
      IO.puts("Upload URL: #{upload_url}")
      IO.puts("File key: #{test_key}")
      IO.puts("Content: #{test_content}")
      IO.puts("\nYou can test this upload with curl:")
      IO.puts("curl -X POST #{upload_url} \\")
      IO.puts("  -F 'key=#{fields["key"]}' \\")
      IO.puts("  -F 'policy=#{fields["policy"]}' \\")
      IO.puts("  -F 'x-amz-credential=#{fields["x-amz-credential"]}' \\")
      IO.puts("  -F 'x-amz-algorithm=#{fields["x-amz-algorithm"]}' \\")
      IO.puts("  -F 'x-amz-date=#{fields["x-amz-date"]}' \\")
      IO.puts("  -F 'x-amz-signature=#{fields["x-amz-signature"]}' \\")
      IO.puts("  -F 'acl=#{fields["acl"]}' \\")
      IO.puts("  -F 'content-type=#{fields["content-type"]}' \\")
      IO.puts("  -F 'file=#{test_content}'")
      IO.puts("===================\n")
      
      # Verify the signature is valid format
      assert String.length(fields["x-amz-signature"]) == 64
      assert String.match?(fields["x-amz-signature"], ~r/^[a-f0-9]+$/)
      
      # Verify policy is valid base64
      assert {:ok, _policy_json} = Base.decode64(fields["policy"])
      
      # Verify credential format
      assert String.contains?(fields["x-amz-credential"], System.get_env("AWS_ACCESS_KEY_ID"))
      assert String.contains?(fields["x-amz-credential"], config.region)
      assert String.contains?(fields["x-amz-credential"], "s3")
    end
    
    test "generates different signatures for different files" do
      config = %{
        region: System.get_env("AWS_REGION", "us-east-1")
      }
      
      bucket = "shoppollama-images-dev"
      
      opts1 = [
        key: "test/file1.jpg",
        content_type: "image/jpeg",
        max_file_size: 5_000_000,
        expires_in: :timer.hours(1)
      ]
      
      opts2 = [
        key: "test/file2.png",
        content_type: "image/png",
        max_file_size: 5_000_000,
        expires_in: :timer.hours(1)
      ]
      
      {:ok, fields1} = S3Upload.sign_form_upload(config, bucket, opts1)
      {:ok, fields2} = S3Upload.sign_form_upload(config, bucket, opts2)
      
      # Should generate different signatures for different files
      assert fields1["x-amz-signature"] != fields2["x-amz-signature"]
      assert fields1["key"] != fields2["key"]
      assert fields1["content-type"] != fields2["content-type"]
    end
  end
end
