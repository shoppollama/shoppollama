defmodule Shoppollama.ProductParser do
  @moduledoc """
  Parses natural language messages to extract product information
  """

  def parse_product_message(message) do
    message = String.downcase(message)

    # Extract price
    price = extract_price(message)

    # Extract product type/title
    title = extract_title(message, price)

    # Extract color if mentioned
    color = extract_color(message)

    # Build the final title
    final_title = build_title(title, color)

    # Extract description
    description = extract_description(message, final_title)

    %{
      title: final_title,
      description: description,
      price: price,
      vendor: "ShoppOllama",
      product_type: classify_product_type(message),
      inventory: 10
    }
  end

  defp extract_price(message) do
    # Look for $XX.XX or $XX patterns
    case Regex.run(~r/\$(\d+(?:\.\d{2})?)/, message) do
      [_, price_str] -> price_str
      # Default price
      nil -> "19.99"
    end
  end

  defp extract_title(message, price) do
    # Remove price and common words, extract the core product
    clean_message =
      message
      |> String.replace(~r/\$\d+(?:\.\d{2})?/, "")
      |> String.replace(~r/\b(create|make|add|new|a|an|the|for)\b/, "")
      |> String.trim()

    # Extract the main product noun
    cond do
      String.contains?(clean_message, "t-shirt") or String.contains?(clean_message, "tee") ->
        "T-Shirt"

      String.contains?(clean_message, "hoodie") or String.contains?(clean_message, "sweatshirt") ->
        "Hoodie"

      String.contains?(clean_message, "jacket") ->
        "Jacket"

      String.contains?(clean_message, "pants") or String.contains?(clean_message, "jeans") ->
        "Pants"

      String.contains?(clean_message, "dress") ->
        "Dress"

      String.contains?(clean_message, "shirt") ->
        "Shirt"

      String.contains?(clean_message, "shoes") or String.contains?(clean_message, "sneakers") ->
        "Shoes"

      true ->
        "Product"
    end
  end

  defp extract_color(message) do
    colors = [
      "black",
      "white",
      "red",
      "blue",
      "green",
      "yellow",
      "purple",
      "pink",
      "orange",
      "gray",
      "grey",
      "brown"
    ]

    Enum.find(colors, fn color ->
      String.contains?(message, color)
    end)
  end

  defp build_title(base_title, nil), do: base_title
  defp build_title(base_title, color), do: "#{String.capitalize(color)} #{base_title}"

  defp extract_description(message, title) do
    "<p>#{String.capitalize(title)} created by ShoppOllama AI assistant.</p><p>Original request: \"#{message}\"</p>"
  end

  defp classify_product_type(message) do
    cond do
      String.contains?(message, "t-shirt") or String.contains?(message, "tee") -> "Apparel"
      String.contains?(message, "hoodie") or String.contains?(message, "sweatshirt") -> "Apparel"
      String.contains?(message, "jacket") or String.contains?(message, "shirt") -> "Apparel"
      String.contains?(message, "pants") or String.contains?(message, "jeans") -> "Apparel"
      String.contains?(message, "dress") -> "Apparel"
      String.contains?(message, "shoes") or String.contains?(message, "sneakers") -> "Footwear"
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
      "product"
    ]

    has_creation_word = Enum.any?(creation_keywords, &String.contains?(message, &1))
    has_product_word = Enum.any?(product_keywords, &String.contains?(message, &1))

    has_creation_word and has_product_word
  end
end
