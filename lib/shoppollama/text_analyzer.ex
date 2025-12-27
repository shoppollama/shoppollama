defmodule Shoppollama.TextAnalyzer do
  @moduledoc """
  Advanced text analysis module that utilizes LLM capabilities to extract
  key information, entities, and patterns from user input text.
  
  This module provides comprehensive text processing including:
  - Entity recognition (products, prices, colors, sizes, etc.)
  - Pattern matching for complex descriptions
  - Context-aware information extraction
  - Multi-product request handling
  """

  alias Shoppollama.OllamaClient
  require Logger

  @doc """
  Analyzes the complete user input text and extracts all relevant information,
  entities, and patterns while maintaining context and accuracy.
  
  Returns a structured map containing:
  - entities: List of identified entities (products, prices, colors, etc.)
  - intent: The user's primary intent (create_product, query_store, etc.)
  - products: List of product information if multiple products detected
  - context: Additional contextual information
  - confidence: Confidence score for the analysis
  """
  def analyze_text(input_text, context \\ %{}) do
    with {:ok, entities} <- extract_entities(input_text),
         {:ok, intent} <- determine_intent(input_text, entities),
         {:ok, products} <- extract_products(input_text, entities),
         {:ok, additional_context} <- extract_context(input_text, context) do
      
      analysis = %{
        entities: entities,
        intent: intent,
        products: products,
        context: Map.merge(context, additional_context),
        confidence: calculate_confidence(entities, intent, products),
        original_text: input_text,
        timestamp: DateTime.utc_now()
      }
      
      {:ok, analysis}
    else
      {:error, reason} -> {:error, reason}
      error -> {:error, "Analysis failed: #{inspect(error)}"}
    end
  end

  @doc """
  Extracts entities from the input text using LLM-powered analysis.
  
  Identifies:
  - Product names and types
  - Prices and monetary values
  - Colors, sizes, and attributes
  - Quantities and measurements
  - Brand names and categories
  """
  def extract_entities(text) do
    prompt = """
    Analyze the following text and extract all relevant entities in JSON format.
    
    Text: "#{text}"
    
    Extract the following entity types:
    - products: Physical items, digital products, albums, songs, clothing, electronics, etc. (e.g., "shirt", "album", "phone", "dreams of my papa album")
    - prices: Only numerical monetary values with currency symbols (e.g., "$25", "12.30")
    - attributes: Physical characteristics like colors, sizes, materials, styles
    - quantities: Numbers indicating amounts or counts
    - brands: Company or brand names
    - actions: Action verbs like create, make, buy, sell
    
    Examples:
    - "I want to buy a red shirt for $25" → products: ["shirt"], prices: ["$25"], attributes: {"colors": ["red"]}
    - "create a page for my dreams of my papa album for 12.30" → products: ["dreams of my papa album"], prices: ["12.30"], actions: ["create"]
    
    Return ONLY a valid JSON object with the structure:
    {
      "products": ["product1", "product2"],
      "prices": ["$19.99", "12.30"],
      "attributes": {"colors": ["red", "blue"], "sizes": ["large"]},
      "quantities": ["10", "5 pieces"],
      "brands": ["Nike", "Apple"],
      "actions": ["create", "make", "add"]
    }
    """

    case call_llm(prompt) do
      {:ok, response} -> 
        IO.inspect(response, label: "Entity extraction response")
        result = parse_entities_response(response)
        IO.inspect(result, label: "Parsed entities")
        result
      {:error, reason} -> {:error, reason}
    end
  end

  @doc """
  Determines the user's primary intent from the analyzed text.
  """
  def determine_intent(text, entities) do
    prompt = """
    Based on the following text and extracted entities, determine the user's primary intent.
    
    Text: "#{text}"
    Entities: #{inspect(entities)}
    
    Possible intents:
    - create_product: User wants to create/add a new product
    - query_store: User is asking about store information/statistics
    - send_sms: User wants to send a text message
    - general_chat: General conversation or questions
    - modify_product: User wants to edit existing products
    - list_products: User wants to see existing products
    
    Return ONLY the intent name as a string (e.g., "create_product")
    """

    case call_llm(prompt) do
      {:ok, response} -> 
        intent = String.trim(response) |> String.replace("\"", "")
        {:ok, String.to_atom(intent)}
      {:error, reason} -> {:error, reason}
    end
  end

  @doc """
  Extracts detailed product information for product creation intents.
  """
  def extract_products(text, entities) do
    case Map.get(entities, :products, []) do
      [] -> {:ok, []}
      products when is_list(products) ->
        extract_detailed_products(text, products, entities)
    end
  end

  defp extract_detailed_products(text, products, entities) do
    prompt = """
    You are a JSON extraction expert. Extract detailed product information from the text and return ONLY a valid JSON array.

    Text: "#{text}"
    Identified Products: #{inspect(products)}
    All Entities: #{inspect(entities)}

    CRITICAL: You must return ONLY a JSON array. Do not include any explanations, markdown formatting, or additional text.

    For each product, extract:
    - name: Clean product name (preserve exact case from original text)
    - type: Product category
    - price: Numerical price value
    - attributes: Colors, sizes, materials, etc.
    - description: Product description

    Example format:
    [
      {
        "name": "Product Name",
        "type": "album",
        "price": 12.30,
        "attributes": {},
        "description": "A music album"
      }
    ]

    Your response must start with [ and end with ].
    """

    case call_llm(prompt) do
      {:ok, response} -> 
        case parse_products_response(response) do
          {:ok, parsed_products} -> 
            # Post-process to preserve original case and fix price formatting
            corrected_products = Enum.map(parsed_products, fn product ->
              product
              |> correct_product_name_case(text)
              |> correct_price_format()
            end)
            {:ok, corrected_products}
          {:error, reason} -> {:error, reason}
        end
      {:error, reason} -> {:error, reason}
    end
  end

  @doc """
  Extracts additional contextual information from the text.
  """
  def extract_context(text, existing_context) do
    prompt = """
    Extract additional contextual information from the following text that might be relevant
    for understanding the user's request better.
    
    Text: "#{text}"
    Existing Context: #{inspect(existing_context)}
    
    Look for:
    - Urgency indicators ("urgent", "asap", "quickly")
    - Preferences ("prefer", "like", "want")
    - Constraints ("under $X", "within budget", "limited")
    - Timeline information ("today", "next week", "by Friday")
    - Special requirements or notes
    
    Return ONLY a valid JSON object:
    {
      "urgency": "normal|high|urgent",
      "preferences": ["preference1", "preference2"],
      "constraints": ["budget under $50"],
      "timeline": "today",
      "notes": ["additional note"]
    }
    """

    case call_llm(prompt) do
      {:ok, response} -> parse_context_response(response)
      {:error, reason} -> {:ok, %{}} # Return empty context on error
    end
  end

  # Private helper functions

  # Public function for direct LLM calls from other modules
  def call_llm_direct(prompt) do
    call_llm(prompt)
  end

  defp call_llm(prompt) do
    case OllamaClient.completion(prompt, model: "llama3.2:3b", temperature: 0.7, timeout: 30_000) do
      {:ok, content} -> {:ok, content}
      {:error, reason} -> 
        Logger.error("TextAnalyzer failed: #{inspect(reason)}")
        {:error, reason}
    end
  end

  defp parse_entities_response(response) do
    json_content = extract_json_from_markdown(response)
    case Jason.decode(json_content) do
      {:ok, entities} -> {:ok, atomize_keys(entities)}
      {:error, _} -> 
        # Log the response for debugging
        require Logger
        Logger.error("Failed to parse LLM response as JSON: #{inspect(response)}")
        # Fallback to basic parsing if JSON parsing fails
        {:ok, extract_basic_entities(response)}
    end
  end

  defp parse_products_response(response) do
    Logger.debug("Raw LLM response for products: #{inspect(response)}")
    
    json_content = extract_json_from_markdown(response)
    Logger.debug("Extracted JSON content: #{inspect(json_content)}")
    
    case Jason.decode(json_content) do
      {:ok, products} when is_list(products) -> 
        Logger.debug("Successfully parsed products: #{inspect(products)}")
        {:ok, Enum.map(products, &atomize_keys/1)}
      {:ok, product} when is_map(product) -> 
        Logger.debug("Successfully parsed single product: #{inspect(product)}")
        {:ok, [atomize_keys(product)]}
      {:error, decode_error} -> 
        Logger.error("Failed to parse LLM response as JSON: #{inspect(decode_error)}")
        Logger.error("Response was: #{inspect(response)}")
        {:ok, []}
    end
  end

  defp parse_context_response(response) do
    json_content = extract_json_from_markdown(response)
    case Jason.decode(json_content) do
      {:ok, context} -> {:ok, atomize_keys(context)}
      {:error, _} -> {:ok, %{}}
    end
  end

  defp extract_json_from_markdown(response) do
    # Try to extract JSON from markdown code blocks first
    case Regex.run(~r/```(?:json)?\s*\n?([\s\S]*?)\n?```/, response, capture: :all_but_first) do
      [json_content] -> String.trim(json_content)
      nil -> 
        # If no code blocks, try to extract JSON object from text
        case Regex.run(~r/\{[\s\S]*\}/, response) do
          [json_content] -> String.trim(json_content)
          nil -> response  # Return original if no JSON found
        end
    end
  end

  defp atomize_keys(map) when is_map(map) do
    Map.new(map, fn {k, v} -> {String.to_atom(k), v} end)
  end
  defp atomize_keys(other), do: other

  defp correct_product_name_case(product, original_text) do
    # Find the original case of the product name in the user's text
    product_name = Map.get(product, :name, "")
    
    # Create a case-insensitive regex to find the original name
    escaped_name = Regex.escape(product_name)
    case Regex.run(~r/#{escaped_name}/i, original_text) do
      [original_case_name] -> 
        # Replace the LLM's capitalized name with the original case
        Map.put(product, :name, original_case_name)
      nil -> 
        # If exact match not found, try to find partial matches
        find_original_case_partial_match(product, original_text)
    end
  end

  defp find_original_case_partial_match(product, original_text) do
    product_name = Map.get(product, :name, "")
    words = String.split(product_name, " ")
    
    # Try to find each word in the original text and reconstruct
    original_words = Enum.map(words, fn word ->
      escaped_word = Regex.escape(word)
      case Regex.run(~r/#{escaped_word}/i, original_text) do
        [original_word] -> original_word
        nil -> word  # Keep LLM's version if not found
      end
    end)
    
    corrected_name = Enum.join(original_words, " ")
    Map.put(product, :name, corrected_name)
  end

  defp correct_price_format(product) do
    case Map.get(product, :price) do
      price when is_number(price) ->
        # If price looks like it was incorrectly parsed (e.g., 12.30 when it should be 1230.00)
        # Check if it's a small decimal that might represent a large whole number
        if price > 0 and price < 100 and rem(trunc(price * 100), 100) != 0 do
          # Convert decimal like 12.30 back to whole number 1230
          corrected_price = trunc(price * 100)
          Map.put(product, :price, corrected_price)
        else
          product
        end
      _ -> product
    end
  end

  defp extract_basic_entities(text) do
    # Fallback entity extraction using regex patterns
    %{
      products: extract_product_names(text),
      prices: extract_price_values(text),
      attributes: %{
        colors: extract_colors(text),
        sizes: extract_sizes(text)
      },
      actions: extract_action_words(text)
    }
  end

  defp extract_product_names(text) do
    # Basic product name extraction
    text
    |> String.split()
    |> Enum.filter(&(String.length(&1) > 2))
    |> Enum.take(3)
  end

  defp extract_price_values(text) do
    # Extract potential prices using LLM
    prompt = """
    Extract all price amounts from this text. 
    IMPORTANT: Numbers without decimal points are whole dollar amounts (e.g., "1230" = 1230.00, "25" = 25.00).
    Return only the numerical values separated by commas. If no prices found, return 'none'.
    Examples:
    - "for 1230" should return "1230.00"
    - "for 12.30" should return "12.30"
    - "costs 25" should return "25.00"
    Text: #{text}
    """
    
    case call_llm_direct(prompt) do
      {:ok, response} ->
        if String.trim(response) == "none" do
          []
        else
          String.split(response, ",")
          |> Enum.map(&String.trim/1)
          |> Enum.filter(fn price -> price != "" end)
        end
      {:error, _} -> []
    end
  end

  defp extract_colors(text) do
    colors = ~w(red blue green yellow black white pink purple orange brown gray grey)
    colors
    |> Enum.filter(&String.contains?(String.downcase(text), &1))
  end

  defp extract_sizes(text) do
    sizes = ~w(small medium large xl xxl xs s m l)
    sizes
    |> Enum.filter(&String.contains?(String.downcase(text), &1))
  end

  defp extract_action_words(text) do
    actions = ~w(create make add new build generate produce)
    actions
    |> Enum.filter(&String.contains?(String.downcase(text), &1))
  end

  defp calculate_confidence(entities, intent, products) do
    # Simple confidence calculation based on extracted information
    base_confidence = 0.5
    
    entity_bonus = if map_size(entities) > 2, do: 0.2, else: 0.0
    intent_bonus = if intent != :general_chat, do: 0.2, else: 0.0
    product_bonus = if length(products) > 0, do: 0.1, else: 0.0
    
    min(base_confidence + entity_bonus + intent_bonus + product_bonus, 1.0)
  end
end