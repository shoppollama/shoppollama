defmodule ShoppollamaWeb.S3ImageAccessTest do
  use ExUnit.Case, async: false
  
  describe "S3 URL access success" do
    test "verifies image URL returns 200 OK" do
      # The URL that was previously failing
      url = "https://shoppollama-images-dev.s3.us-east-1.amazonaws.com/uploads/42c23bae963f0ba3efd390e62e4ea646/76c10ac2-37e3-4cae-87a8-3b3a788c4b51-shahrukh-shoaib-bK_C67Krm-k-unsplash.png"
      
      # Make the request
      case HTTPoison.get(url) do
        {:ok, %HTTPoison.Response{status_code: 200, body: body}} ->
          # Verify we get an image response
          assert String.starts_with?(body, <<137, 80, 78, 71, 13, 10, 26, 10>>)  # PNG signature
          
          IO.puts("\n✅ Successfully accessed image!")
          IO.puts("Status Code: 200")
          IO.puts("Content-Type: image/png")
          IO.puts("Content-Length: #{byte_size(body)} bytes")
          
        {:ok, %HTTPoison.Response{status_code: status}} ->
          flunk("Expected 200 OK, but got status #{status}")
          
        {:error, reason} ->
          flunk("Request failed with error: #{inspect(reason)}")
      end
    end
    
    test "verifies response headers for successful image access" do
      url = "https://shoppollama-images-dev.s3.us-east-1.amazonaws.com/uploads/42c23bae963f0ba3efd390e62e4ea646/76c10ac2-37e3-4cae-87a8-3b3a788c4b51-shahrukh-shoaib-bK_C67Krm-k-unsplash.png"
      
      case HTTPoison.head(url) do
        {:ok, %HTTPoison.Response{status_code: 200, headers: headers}} ->
          # Verify expected headers are present
          header_map = 
            headers
            |> Enum.map(fn {k, v} -> {String.downcase(k), v} end)
            |> Map.new()
          
          assert header_map["content-type"] == "image/png"
          assert header_map["server"] == "AmazonS3"
          assert header_map["x-amz-server-side-encryption"] == "AES256"
          assert header_map["content-length"] == "936749"
          
          IO.puts("\n✅ HEAD request returns 200 with correct headers")
          
        {:ok, %HTTPoison.Response{status_code: status}} ->
          flunk("Expected 200 OK for HEAD, but got status #{status}")
          
        {:error, reason} ->
          flunk("HEAD request failed with error: #{inspect(reason)}")
      end
    end
    
    test "demonstrates curl equivalent behavior" do
      url = "https://shoppollama-images-dev.s3.us-east-1.amazonaws.com/uploads/42c23bae963f0ba3efd390e62e4ea646/76c10ac2-37e3-4cae-87a8-3b3a788c4b51-shahrukh-shoaib-bK_C67Krm-k-unsplash.png"
      
      # Execute curl command with HEAD request to avoid downloading the image
      {output, _exit_code} = System.cmd("curl", ["-s", "-I", "-w", "%{http_code}", url], stderr_to_stdout: true)
      
      # Extract status code from the end of output
      http_code = String.slice(output, -3..-1)
      
      assert http_code == "200"
      assert output =~ "HTTP/1.1 200 OK"
      assert output =~ "Content-Type: image/png"
      
      IO.puts("\n✅ curl command also returns 200 OK")
      IO.puts("HTTP Status: #{http_code}")
    end
  end
end
