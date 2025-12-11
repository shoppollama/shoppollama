defmodule Shoppollama.ProductParser do
  @moduledoc """
  Parses natural language messages to extract product information.
  Enhanced with LLM-powered text analysis for better entity extraction.
  """

  alias Shoppollama.TextAnalyzer
  require Logger

  def parse_product_message(message) do
    case parse_with_text_analyzer(message) do
      {:ok, product_data} -> product_data
      {:error, reason} ->
        Logger.error("TextAnalyzer failed: #{reason}")
        {:error, reason}
    end
  end

  @doc """
  Enhanced parsing using TextAnalyzer for comprehensive information extraction.
  """
  def parse_with_text_analyzer(message) do
    case TextAnalyzer.analyze_text(message) do
      {:ok, analysis} -> build_product_from_analysis(analysis, message)
      {:error, reason} -> {:error, reason}
    end
  end



  defp build_product_from_analysis(analysis, original_message) do
    case analysis.products do
      [product | _] -> 
        case build_enhanced_product(product, analysis, original_message) do
          {:ok, product_data} -> {:ok, product_data}
          {:error, reason} -> {:error, reason}
        end
      [] -> {:error, "No products found in analysis"}
    end
  end

  defp build_enhanced_product(product, analysis, original_message) when is_map(product) do
    # Extract price from analysis
    price = extract_price_from_analysis(analysis) || 19.99

    # Build title from analyzed product data
    title = build_enhanced_title(product, analysis)

    # Generate description using LLM analysis
    description = build_enhanced_description(product, analysis, original_message)

    product_data = %{
      title: title,
      description: description,
      price: price,
      vendor: "ShoppOllama",
      product_type: Map.get(product, :type, "general"),
      inventory: 10,
      # Additional enhanced fields
      attributes: Map.get(product, :attributes, %{}),
      confidence: analysis.confidence,
      analysis_timestamp: analysis.timestamp
    }

    {:ok, product_data}
  end

  defp build_enhanced_product(product, _analysis, _original_message) do
    Logger.error("Invalid product data received: #{inspect(product)}")
    {:error, "Invalid product data structure"}
  end

  defp extract_price_from_analysis(analysis) do
    case Map.get(analysis.entities, :prices, []) do
      [price_str | _] -> parse_price_string(price_str)
      [] -> nil
    end
  end

  defp parse_price_string(price_str) do
    # Remove currency symbols and parse
    clean_price = String.replace(price_str, ~r/[^\d.]/, "")
    case Float.parse(clean_price) do
      {price, _} -> price
      :error -> nil
    end
  end

  defp build_enhanced_title(product, analysis) do
    base_name = Map.get(product, :name, "Product")
    
    # Clean music product names by removing type suffixes
    cleaned_name = clean_music_product_name(base_name, Map.get(product, :type))
    
    attributes = Map.get(product, :attributes, %{})

    # Add color if available
    title_with_color = case Map.get(attributes, "color") do
      nil -> cleaned_name
      color -> "#{String.capitalize(color)} #{cleaned_name}"
    end

    # Add unique ID
    build_title_with_unique_id(title_with_color, Map.get(attributes, "color"))
  end

  defp clean_music_product_name(name, product_type) when is_binary(name) do
    # For music products, remove common type suffixes
    music_types = ["mixtape", "album", "tape", "music", "song", "track", "ep", "single"]
    
    if product_type in music_types or Enum.any?(music_types, &String.contains?(String.downcase(name), &1)) do
      # Remove music type suffixes from the end of the name
      cleaned = Enum.reduce(music_types, name, fn type, acc ->
        # Remove type from end (case insensitive)
        acc
        |> String.replace(~r/\s+#{type}\s*$/i, "")
        |> String.replace(~r/^#{type}\s+/i, "")
      end)
      
      # Clean up extra whitespace
      String.trim(cleaned)
    else
      name
    end
  end
  
  defp clean_music_product_name(name, _), do: name

  defp build_enhanced_description(product, analysis, original_message) do
    base_description = Map.get(product, :description, "")

    if String.length(base_description) > 10 do
      base_description
    else
      "A quality product from ShoppOllama"
    end
  end













  defp build_title(base_title, nil), do: base_title
  defp build_title(base_title, color), do: "#{String.capitalize(color)} #{base_title}"

  # Updated function to build title without unique ID for user-specified names
  defp build_title_with_unique_id(base_title, color) do
    # For user-specified names, don't add unique ID
    build_title(base_title, color)
  end

  # Generate unique identifier using timestamp and random number
  defp generate_unique_id do
    timestamp = DateTime.utc_now() |> DateTime.to_unix(:millisecond)
    random = :rand.uniform(999)
    "#{timestamp}-#{random}"
  end



  defp classify_product_type(message) do
    cond do
      String.contains?(message, "t-shirt") or String.contains?(message, "tee") -> "Apparel"
      String.contains?(message, "hoodie") or String.contains?(message, "sweatshirt") -> "Apparel"
      String.contains?(message, "jacket") or String.contains?(message, "shirt") -> "Apparel"
      String.contains?(message, "pants") or String.contains?(message, "jeans") -> "Apparel"
      String.contains?(message, "dress") -> "Apparel"
      String.contains?(message, "shoes") or String.contains?(message, "sneakers") -> "Footwear"
      String.contains?(message, "mixtape") or String.contains?(message, "album") or String.contains?(message, "music") -> "Music"
      true -> "General"
    end
  end

  def is_product_creation_request?(message) do
    message = String.downcase(message)

    creation_keywords = ["create", "make", "add", "new product", "generate"]

    product_keywords = [
      "t-shirt",
      "shirt",
      "hoodie",
      "jacket",
      "pants",
      "dress",
      "shoes",
      "mixtape",
      "album",
      "music",
      "product",
      "plan",
      "service",
      "item"
    ]

    has_creation_word = Enum.any?(creation_keywords, &String.contains?(message, &1))
    has_product_word = Enum.any?(product_keywords, &String.contains?(message, &1))

    has_creation_word and has_product_word
  end

  def is_page_creation_request?(message) do
    message = String.downcase(message)

    page_keywords = ["page", "website", "site", "landing page"]
    creation_keywords = ["create", "make", "build", "generate"]

    has_page_word = Enum.any?(page_keywords, &String.contains?(message, &1))
    has_creation_word = Enum.any?(creation_keywords, &String.contains?(message, &1))

    has_page_word and has_creation_word
  end
end
