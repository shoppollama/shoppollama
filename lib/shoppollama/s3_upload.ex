defmodule Shoppollama.S3Upload do
  @moduledoc """
  Dependency-free S3 Form Upload using HTTP POST sigv4

  https://docs.aws.amazon.com/AmazonS3/latest/API/sigv4-post-example.html
  """

  @doc """
  Signs a form upload.

  The configuration can either:
  1. Contain explicit AWS credentials:
     * `:region` - The AWS region, such as "us-east-1"
     * `:access_key_id` - The AWS access key id
     * `:secret_access_key` - The AWS secret access key
  2. Or it will automatically use AWS CLI credentials if not provided

  Returns a map of form fields to be used on the client via the JavaScript `FormData` API.

  ## Options

    * `:key` - The required key of the object to be uploaded.
    * `:max_file_size` - The required maximum allowed file size in bytes.
    * `:content_type` - The required MIME type of the file to be uploaded.
    * `:expires_in` - The required expiration time in milliseconds from now
      before the signed upload expires.

  ## Examples

      # Using environment variables
      config = %{
        region: "us-east-1",
        access_key_id: System.fetch_env!("AWS_ACCESS_KEY_ID"),
        secret_access_key: System.fetch_env!("AWS_SECRET_ACCESS_KEY")
      }

      # Using AWS CLI credentials (automatic)
      config = %{region: "us-east-1"}

      {:ok, fields} =
        SimpleS3Upload.sign_form_upload(config, "my-bucket",
          key: "public/my-file-name",
          content_type: "image/png",
          max_file_size: 10_000,
          expires_in: :timer.hours(1)
        )

  """
  def sign_form_upload(config, bucket, opts) do
    key = Keyword.fetch!(opts, :key)
    max_file_size = Keyword.fetch!(opts, :max_file_size)
    content_type = Keyword.fetch!(opts, :content_type)
    expires_in = Keyword.fetch!(opts, :expires_in)

    # Get AWS credentials from config or AWS CLI
    aws_config = get_aws_config(config)

    expires_at = DateTime.add(DateTime.utc_now(), expires_in, :millisecond)
    amz_date = amz_date(expires_at)
    credential = credential(aws_config, expires_at)

    encoded_policy =
      Base.encode64("""
      {
        "expiration": "#{DateTime.to_iso8601(expires_at)}",
        "conditions": [
          {"bucket":  "#{bucket}"},
          ["eq", "$key", "#{key}"],
          ["eq", "$Content-Type", "#{content_type}"],
          ["content-length-range", 0, #{max_file_size}],
          {"x-amz-server-side-encryption": "AES256"},
          {"x-amz-credential": "#{credential}"},
          {"x-amz-algorithm": "AWS4-HMAC-SHA256"},
          {"x-amz-date": "#{amz_date}"}
        ]
      }
      """)

    fields = %{
      "key" => key,
      "content-type" => content_type,
      "x-amz-server-side-encryption" => "AES256",
      "x-amz-credential" => credential,
      "x-amz-algorithm" => "AWS4-HMAC-SHA256",
      "x-amz-date" => amz_date,
      "policy" => encoded_policy,
      "x-amz-signature" => signature(aws_config, expires_at, encoded_policy)
    }

    {:ok, fields}
  end

  defp amz_date(time) do
    time
    |> NaiveDateTime.to_iso8601()
    |> String.split(".")
    |> List.first()
    |> String.replace("-", "")
    |> String.replace(":", "")
    |> Kernel.<>("Z")
  end

  defp credential(%{} = config, %DateTime{} = expires_at) do
    "#{config.access_key_id}/#{short_date(expires_at)}/#{config.region}/s3/aws4_request"
  end

  defp signature(config, %DateTime{} = expires_at, encoded_policy) do
    config
    |> signing_key(expires_at, "s3")
    |> sha256(encoded_policy)
    |> Base.encode16(case: :lower)
  end

  defp signing_key(%{} = config, %DateTime{} = expires_at, service) when service in ["s3"] do
    amz_date = short_date(expires_at)
    %{secret_access_key: secret, region: region} = config

    ("AWS4" <> secret)
    |> sha256(amz_date)
    |> sha256(region)
    |> sha256(service)
    |> sha256("aws4_request")
  end

  defp short_date(%DateTime{} = expires_at) do
    expires_at
    |> amz_date()
    |> String.slice(0..7)
  end

  defp sha256(secret, msg), do: :crypto.mac(:hmac, :sha256, secret, msg)

  # Get AWS configuration from explicit config or AWS CLI
  defp get_aws_config(config) do
    if Map.has_key?(config, :access_key_id) && Map.has_key?(config, :secret_access_key) do
      # Use explicit credentials from config
      config
    else
      # Try to get credentials from AWS CLI
      case get_aws_cli_credentials() do
        {:ok, creds} ->
          %{
            region: config[:region] || "us-east-1",
            access_key_id: creds[:access_key_id],
            secret_access_key: creds[:secret_access_key]
          }
        _error ->
          # Fallback to environment variables
          %{
            region: config[:region] || System.get_env("AWS_REGION", "us-east-1"),
            access_key_id: System.get_env("AWS_ACCESS_KEY_ID"),
            secret_access_key: System.get_env("AWS_SECRET_ACCESS_KEY")
          }
      end
    end
  end

  # Parse AWS CLI credentials from ~/.aws/credentials
  defp get_aws_cli_credentials() do
    # First check if environment variables are set (from .env)
    access_key = System.get_env("AWS_ACCESS_KEY_ID")
    secret_key = System.get_env("AWS_SECRET_ACCESS_KEY")
    
    if access_key && secret_key do
      {:ok, %{access_key_id: access_key, secret_access_key: secret_key}}
    else
      # Try to read from AWS CLI credentials file
      home_dir = System.user_home()
      credentials_file = Path.join(home_dir, ".aws/credentials")
      
      if File.exists?(credentials_file) do
        content = File.read!(credentials_file)
        
        # Try to find the default profile credentials
        case parse_aws_credentials(content, "default") do
          {:ok, creds} -> {:ok, creds}
          _ -> 
            # Try to get from `aws configure list` command
            get_aws_cli_credentials_from_command()
        end
      else
        get_aws_cli_credentials_from_command()
      end
    end
  end

  # Parse credentials file content for a specific profile
  defp parse_aws_credentials(content, profile) do
    case Regex.run(~r/\[#{profile}\][\s\S]*?aws_access_key_id = (.+)[\s\S]*?aws_secret_access_key = (.+)/, content) do
      [_, access_key, secret_key] ->
        {:ok, %{access_key_id: String.trim(access_key), secret_access_key: String.trim(secret_key)}}
      _ ->
        {:error, :not_found}
    end
  end

  # Get credentials using AWS CLI command
  defp get_aws_cli_credentials_from_command() do
    case System.cmd("aws", ["configure", "get", "aws_access_key_id"], stderr_to_stdout: true) do
      {access_key, 0} ->
        case System.cmd("aws", ["configure", "get", "aws_secret_access_key"], stderr_to_stdout: true) do
          {secret_key, 0} ->
            {:ok, %{access_key_id: String.trim(access_key), secret_access_key: String.trim(secret_key)}}
          _ -> {:error, :no_secret_key}
        end
      _ -> {:error, :no_access_key}
    end
  end
end
