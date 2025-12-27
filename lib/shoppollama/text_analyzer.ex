defmodule Shoppollama.TextAnalyzer do
  @moduledoc """
  LLM-powered text analysis module for extracting product information.
  """

  alias Shoppollama.OllamaClient
  require Logger

  def analyze_text(input_text, context \\ %{}) do
    case extract_with_llm(input_text) do
      {:ok, result} ->
        {:ok, %{
          entities: Map.get(result, :entities, %{}),
          intent: Map.get(result, :intent, :create_product),
          products: Map.get(result, :products, []),
          context: context,
          confidence: 0.8,
          original_text: input_text,
          timestamp: DateTime.utc_now()
        }}
      {:error, reason} -> 
        Logger.error("TextAnalyzer failed: #{inspect(reason)}")
        {:error, reason}
    end
  end

  defp extract_with_llm(text) do
    # Simple prompt that works on EC2 - tested manually
    prompt = "Extract product name and price from: #{text}. Return JSON only: {name, price}"

    case OllamaClient.completion(prompt, model: "qwen2:1.5b", temperature: 0.0, timeout: 120_000) do
      {:ok, response} ->
        Logger.info("LLM response: #{response}")
        parse_llm_response(response, text)
      {:error, reason} -> 
        {:error, reason}
    end
  end

  defp parse_llm_response(response, original_text) do
    # Find JSON in response
    json_str = extract_json(response)
    
    case Jason.decode(json_str) do
      {:ok, parsed} ->
        # Handle simple {name, price} format - check various key formats from different models
        name = Map.get(parsed, "name") || Map.get(parsed, "Name") || Map.get(parsed, "product")
        price = parse_price(Map.get(parsed, "price") || Map.get(parsed, "Price"))
        
        if name do
          # Preserve original case from input text
          corrected_name = find_original_case(name, original_text)
          products = [%{"name" => corrected_name, "price" => price, "attributes" => %{}}]
          {:ok, %{intent: :create_product, products: products, entities: %{}}}
        else
          # Try complex format as fallback
          products = Map.get(parsed, "products", [])
          {:ok, %{intent: :create_product, products: products, entities: %{}}}
        end
      {:error, _} ->
        Logger.error("Failed to parse LLM JSON: #{json_str}")
        {:error, "Failed to parse JSON from LLM"}
    end
  end

  defp find_original_case(llm_name, original_text) do
    # Find the original case of the product name in the user's text
    llm_lower = String.downcase(llm_name)
    original_lower = String.downcase(original_text)
    
    if String.contains?(original_lower, llm_lower) do
      # Find position and extract with original case
      case :binary.match(original_lower, llm_lower) do
        {start, len} -> String.slice(original_text, start, len)
        :nomatch -> llm_name
      end
    else
      llm_name
    end
  end

  defp parse_price(price) when is_number(price), do: price
  defp parse_price(price) when is_binary(price) do
    # Remove $ and parse as float
    clean = String.replace(price, ~r/[^\d.]/, "")
    case Float.parse(clean) do
      {num, _} -> num
      :error -> 19.99
    end
  end
  defp parse_price(_), do: 19.99

  defp extract_json(response) do
    # Find content between first { and last }
    chars = String.graphemes(response)
    first_idx = Enum.find_index(chars, &(&1 == "{"))
    last_idx = length(chars) - 1 - Enum.find_index(Enum.reverse(chars), &(&1 == "}"))
    
    if first_idx && last_idx && last_idx >= first_idx do
      chars |> Enum.slice(first_idx..last_idx) |> Enum.join()
    else
      response
    end
  end
end