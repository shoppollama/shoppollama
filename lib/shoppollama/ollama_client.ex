defmodule Shoppollama.OllamaClient do
  @moduledoc """
  A dedicated Ollama client for making requests to the local Ollama server.
  This replaces the OpenAI dependency and provides a clean interface for LLM interactions.
  """

  require Logger

  @default_model "llama3.2:3b"
  @default_endpoint "http://localhost:11434/api/generate"
  @default_timeout 30_000

  @doc """
  Makes a completion request to the Ollama server.

  ## Options

  - `:model` - The model to use (default: "llama3.2:3b")
  - `:temperature` - Controls randomness (0.0 to 1.0, default: 0.7)
  - `:stream` - Whether to stream the response (default: false)
  - `:timeout` - Request timeout in milliseconds (default: 30_000)

  ## Examples

      iex> OllamaClient.completion("What is the capital of France?")
      {:ok, "The capital of France is Paris."}

      iex> OllamaClient.completion("Analyze this text", model: "llama3.2:1b")
      {:ok, "Analysis result..."}
  """
  def completion(prompt, opts \\[]) do
    model = Keyword.get(opts, :model, @default_model)
    temperature = Keyword.get(opts, :temperature, 0.7)
    stream = Keyword.get(opts, :stream, false)
    timeout = Keyword.get(opts, :timeout, @default_timeout)

    request_body = %{
      model: model,
      prompt: prompt,
      temperature: temperature,
      stream: stream
    }

    headers = [
      {"Content-Type", "application/json"},
      {"Accept", "application/json"}
    ]


    case HTTPoison.post(@default_endpoint, Jason.encode!(request_body), headers, timeout: timeout) do
      {:ok, %HTTPoison.Response{status_code: 200, body: body}} ->
        case Jason.decode(body) do
          {:ok, %{"response" => response}} -> {:ok, String.trim(response)}
          {:ok, response} -> {:error, "Unexpected response format: #{inspect(response)}"}
          {:error, decode_error} -> {:error, "JSON decode error: #{inspect(decode_error)}"}
        end

      {:ok, %HTTPoison.Response{status_code: status_code, body: body}} ->
        Logger.error("Ollama request failed with status #{status_code}: #{body}")
        {:error, "Ollama server error: #{status_code}"}

      {:error, %HTTPoison.Error{reason: reason}} ->
        Logger.error("Ollama connection error: #{inspect(reason)}")
        {:error, "Failed to connect to Ollama server: #{inspect(reason)}"}

      {:error, error} ->
        Logger.error("Unexpected Ollama error: #{inspect(error)}")
        {:error, "Unexpected error: #{inspect(error)}"}
    end
  end

  @doc """
  Makes a chat completion request using the OpenAI-compatible API endpoint.
  This is useful for maintaining compatibility with existing LangChain integrations.

  ## Options

  - `:model` - The model to use (default: "llama3.2:3b")
  - `:temperature` - Controls randomness (0.0 to 1.0, default: 0.7)
  - `:max_tokens` - Maximum tokens to generate (optional)
  - `:timeout` - Request timeout in milliseconds (default: 30_000)

  ## Examples

      iex> OllamaClient.chat_completion([%{role: "user", content: "Hello!"}])
      {:ok, "Hello! How can I help you today?"}
  """
  def chat_completion(messages, opts \\[]) when is_list(messages) do
    model = Keyword.get(opts, :model, @default_model)
    temperature = Keyword.get(opts, :temperature, 0.7)
    max_tokens = Keyword.get(opts, :max_tokens)
    timeout = Keyword.get(opts, :timeout, @default_timeout)

    request_body = %{
      model: model,
      messages: messages,
      temperature: temperature,
      stream: false
    }

    request_body = if max_tokens, do: Map.put(request_body, :max_tokens, max_tokens), else: request_body

    headers = [
      {"Content-Type", "application/json"},
      {"Accept", "application/json"}
    ]

    endpoint = "http://localhost:11434/v1/chat/completions"

    case HTTPoison.post(endpoint, Jason.encode!(request_body), headers, timeout: timeout) do
      {:ok, %HTTPoison.Response{status_code: 200, body: body}} ->
        case Jason.decode(body) do
          {:ok, %{"choices" => [%{"message" => %{"content" => content}} | _]}} ->
            {:ok, String.trim(content)}
          {:ok, response} ->
            {:error, "Unexpected response format: #{inspect(response)}"}
          {:error, decode_error} ->
            {:error, "JSON decode error: #{inspect(decode_error)}"}
        end

      {:ok, %HTTPoison.Response{status_code: status_code, body: body}} ->
        Logger.error("Ollama chat completion failed with status #{status_code}: #{body}")
        {:error, "Ollama server error: #{status_code}"}

      {:error, %HTTPoison.Error{reason: reason}} ->
        Logger.error("Ollama connection error: #{inspect(reason)}")
        {:error, "Failed to connect to Ollama server: #{inspect(reason)}"}

      {:error, error} ->
        Logger.error("Unexpected Ollama error: #{inspect(error)}")
        {:error, "Unexpected error: #{inspect(error)}"}
    end
  end

  @doc """
  Convenience function for simple text completion requests.
  """
  def ask(question, opts \\[]) when is_binary(question) do
    completion(question, opts)
  end

  @doc """
  Checks if the Ollama server is available and responsive.

  ## Examples

      iex> OllamaClient.health_check()
      {:ok, "Ollama server is running"}

      iex> OllamaClient.health_check()
      {:error, "Ollama server is not available"}
  """
  def health_check do
    case HTTPoison.get("http://localhost:11434/api/tags", [], timeout: 5_000) do
      {:ok, %HTTPoison.Response{status_code: 200}} ->
        {:ok, "Ollama server is running"}
      {:ok, %HTTPoison.Response{status_code: status_code}} ->
        {:error, "Ollama server returned status: #{status_code}"}
      {:error, %HTTPoison.Error{reason: reason}} ->
        {:error, "Ollama server is not available: #{inspect(reason)}"}
      {:error, error} ->
        {:error, "Health check failed: #{inspect(error)}"}
    end
  end

  @doc """
  Lists available models on the Ollama server.

  ## Examples

      iex> OllamaClient.list_models()
      {:ok, ["llama3.2:3b", "llama3.2:1b", "codellama:7b"]}
  """
  def list_models do
    case HTTPoison.get("http://localhost:11434/api/tags", [], timeout: 10_000) do
      {:ok, %HTTPoison.Response{status_code: 200, body: body}} ->
        case Jason.decode(body) do
          {:ok, %{"models" => models}} ->
            model_names = Enum.map(models, & &1["name"])
            {:ok, model_names}
          {:ok, response} ->
            {:error, "Unexpected response format: #{inspect(response)}"}
          {:error, decode_error} ->
            {:error, "JSON decode error: #{inspect(decode_error)}"}
        end

      {:ok, %HTTPoison.Response{status_code: status_code, body: body}} ->
        {:error, "Failed to list models, status: #{status_code}, body: #{body}"}

      {:error, %HTTPoison.Error{reason: reason}} ->
        {:error, "Connection error: #{inspect(reason)}"}

      {:error, error} ->
        {:error, "Unexpected error: #{inspect(error)}"}
    end
  end
end
