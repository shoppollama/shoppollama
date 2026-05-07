defmodule ShoppollamaWeb.S3UploadTest do
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
  
  describe "S3Upload.sign_form_upload/3" do
    test "successfully generates signed upload fields" do
      config = %{
        region: System.get_env("AWS_REGION", "us-east-1")
      }
      
      bucket = "shoppollama-images-dev"
      opts = [
        key: "test/test-image.jpg",
        content_type: "image/jpeg",
        max_file_size: 5_000_000,
        expires_in: :timer.hours(1)
      ]
      
      {:ok, fields} = S3Upload.sign_form_upload(config, bucket, opts)
      
      # Verify required fields are present
      assert Map.has_key?(fields, "key")
      assert Map.has_key?(fields, "policy")
      assert Map.has_key?(fields, "x-amz-credential")
      assert Map.has_key?(fields, "x-amz-algorithm")
      assert Map.has_key?(fields, "x-amz-date")
      assert Map.has_key?(fields, "x-amz-signature")
      
      # Verify values
      assert fields["key"] == "test/test-image.jpg"
      assert fields["x-amz-algorithm"] == "AWS4-HMAC-SHA256"
      assert fields["acl"] == "public-read"
      assert fields["content-type"] == "image/jpeg"
    end
    
    test "includes correct bucket and content type in policy" do
      config = %{
        region: System.get_env("AWS_REGION", "us-east-1")
      }
      
      bucket = "shoppollama-images-dev"
      opts = [
        key: "test/document.pdf",
        content_type: "application/pdf",
        max_file_size: 10_000_000,
        expires_in: :timer.minutes(30)
      ]
      
      {:ok, fields} = S3Upload.sign_form_upload(config, bucket, opts)
      
      # Decode and verify policy contains correct conditions
      policy = Base.decode64!(fields["policy"])
      policy_json = Jason.decode!(policy)
      
      # Check bucket condition
      bucket_condition = Enum.find(policy_json["conditions"], fn
        %{"bucket" => ^bucket} -> true
        _ -> false
      end)
      assert bucket_condition != nil
      
      # Check key condition
      key_condition = Enum.find(policy_json["conditions"], fn
        ["eq", "$key", "test/document.pdf"] -> true
        _ -> false
      end)
      assert key_condition != nil
      
      # Check content type condition
      content_type_condition = Enum.find(policy_json["conditions"], fn
        ["eq", "$Content-Type", "application/pdf"] -> true
        _ -> false
      end)
      assert content_type_condition != nil
    end
    
    test "generates unique signature for each request" do
      config = %{
        region: System.get_env("AWS_REGION", "us-east-1")
      }
      
      bucket = "shoppollama-images-dev"
      opts = [
        key: "test/unique-file.png",
        content_type: "image/png",
        max_file_size: 1_000_000,
        expires_in: :timer.hours(1)
      ]
      
      # Generate two signatures
      {:ok, fields1} = S3Upload.sign_form_upload(config, bucket, opts)
      # Sleep a bit to ensure different timestamp
      Process.sleep(1000)
      {:ok, fields2} = S3Upload.sign_form_upload(config, bucket, opts)
      
      # Signatures should be different due to different timestamps
      assert fields1["x-amz-signature"] != fields2["x-amz-signature"]
      assert fields1["x-amz-date"] != fields2["x-amz-date"]
    end
    
    test "works with explicit AWS credentials" do
      config = %{
        region: System.get_env("AWS_REGION", "us-east-1"),
        access_key_id: System.get_env("AWS_ACCESS_KEY_ID"),
        secret_access_key: System.get_env("AWS_SECRET_ACCESS_KEY")
      }
      
      bucket = "shoppollama-images-dev"
      opts = [
        key: "test/explicit-creds.jpg",
        content_type: "image/jpeg",
        max_file_size: 2_000_000,
        expires_in: :timer.hours(2)
      ]
      
      {:ok, fields} = S3Upload.sign_form_upload(config, bucket, opts)
      
      assert Map.has_key?(fields, "x-amz-signature")
      assert String.length(fields["x-amz-signature"]) == 64  # SHA256 hex length
    end
  end
  
  describe "credential detection" do
    test "detects AWS credentials from environment" do
      # Test that the module can find credentials from environment variables
      assert System.get_env("AWS_ACCESS_KEY_ID") != nil
      assert System.get_env("AWS_SECRET_ACCESS_KEY") != nil
      assert System.get_env("AWS_REGION") != nil
    end
  end
end
