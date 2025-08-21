local in_event_handlers = false
local did_change = false

for line in lines do
  -- Find the select_reasoning event handler and add connect_store after it
  if line:match('^%s*def handle_event%("select_reasoning"') then
    print(line)
    in_event_handlers = true
  elseif in_event_handlers and line:match('^%s*end%s*$') then
    -- Print the end of select_reasoning handler
    print(line)
    print('')
    -- Add the connect_store handler
    print('  @impl true')
    print('  def handle_event("connect_store", _params, socket) do')
    print('    {:noreply, redirect(socket, to: "/auth/shopify")}')
    print('  end')
    in_event_handlers = false
    did_change = true
  else
    print(line)
  end
end
defmodule ShoppollamaWeb.ChatLive do
  use ShoppollamaWeb, :live_view
  alias Phoenix.PubSub
  alias Shoppollama.ShopifyClient
  alias Shoppollama.ProductParser
  alias Shoppollama.{Repo, Store}

  @impl true
  def mount(_params, _session, socket) do
    if connected?(socket) do
      PubSub.subscribe(Shoppollama.PubSub, "chat:updates")
    end

    {:ok,
     socket
     |> assign(:messages, [])
     |> assign(:current_message, "")
     |> assign(:selected_model, "gpt-oss:20b")
     |> assign(:reasoning_effort, "medium")
     |> assign(:ollama_connected, true)
     |> assign(:store_connected, check_store_connection())
     |> assign(:thinking, false)
     |> stream(:messages, [])}
  end

  @impl true
  def handle_event("send_message", %{"message" => message}, socket) when message != "" do
    user_message = %{
      id: System.unique_integer([:positive]),
      role: :user,
      content: String.trim(message),
      timestamp: DateTime.utc_now()
    }

    # Add user message to stream
    socket = stream_insert(socket, :messages, user_message)

    # Start thinking state
    socket = assign(socket, :thinking, true)

    # Check message type and route accordingly
    cond do
      ProductParser.is_product_creation_request?(message) ->
        send(self(), {:create_product, message})

      is_store_query?(message) ->
        send(self(), {:handle_store_query, message})

      true ->
        send(self(), {:call_ollama, message})
    end

    {:noreply,
     socket
     |> assign(:current_message, "")
     |> assign(:thinking, true)}
  end

  def handle_event("send_message", _params, socket), do: {:noreply, socket}

  @impl true
  def handle_event("update_message", %{"message" => message}, socket) do
    {:noreply, assign(socket, :current_message, message)}
  end

  @impl true
  def handle_event("select_model", %{"model" => model}, socket) do
    {:noreply, assign(socket, :selected_model, model)}
  end

  @impl true
  def handle_event("select_reasoning", %{"reasoning" => reasoning}, socket) do
    {:noreply, assign(socket, :reasoning_effort, reasoning)}
  end

  @impl true
  def handle_event("connect_store", _params, socket) do
    {:noreply, redirect(socket, to: "/auth/shopify")}
  end

  @impl true
  def handle_info({:create_product, message}, socket) do
    # Parse the product details from the message
    product_data = ProductParser.parse_product_message(message)

    case ShopifyClient.create_product(product_data) do
      {:ok, product} ->
        ai_message = %{
          id: System.unique_integer([:positive]),
          role: :assistant,
          content: create_success_message(product),
          timestamp: DateTime.utc_now(),
          model: socket.assigns.selected_model
        }

        {:noreply,
         socket
         |> stream_insert(:messages, ai_message)
         |> assign(:thinking, false)
         |> assign(:store_connected, true)}

      {:error, error} ->
        ai_message = %{
          id: System.unique_integer([:positive]),
          role: :assistant,
          content:
            "❌ Sorry, I couldn't create the product: #{error}\n\nMake sure your SHOPIFY_ACCESS_TOKEN is set correctly in your environment variables.",
          timestamp: DateTime.utc_now(),
          model: socket.assigns.selected_model
        }

        {:noreply,
         socket
         |> stream_insert(:messages, ai_message)
         |> assign(:thinking, false)
         |> assign(:store_connected, false)}
    end
  end

  @impl true
  def handle_info({:handle_store_query, message}, socket) do
    response = handle_store_statistics(message)

    ai_message = %{
      id: System.unique_integer([:positive]),
      role: :assistant,
      content: response,
      timestamp: DateTime.utc_now(),
      model: socket.assigns.selected_model
    }

    {:noreply,
     socket
     |> stream_insert(:messages, ai_message)
     |> assign(:thinking, false)}
  end

  @impl true
  def handle_info({:call_ollama, message}, socket) do
    # Simulate AI response for now - we'll replace with real Ollama integration
    ai_response = generate_ai_response(message, socket.assigns.selected_model)

    ai_message = %{
      id: System.unique_integer([:positive]),
      role: :assistant,
      content: ai_response,
      timestamp: DateTime.utc_now(),
      model: socket.assigns.selected_model
    }

    {:noreply,
     socket
     |> stream_insert(:messages, ai_message)
     |> assign(:thinking, false)}
  end

  defp create_success_message(product) do
    """
    ✅ **Product created successfully!**

    **#{product.title}** has been added to your Shopify store.

    🔗 **Quick Links:**
    • [View in Admin](#{product.admin_url}) - Edit and manage the product
    • [View in Store](#{product.store_url}) - See how customers will see it

    Product ID: `#{product.id}`
    Handle: `#{product.handle}`

    The product is now live and ready for customers! 🎉
    """
  end

  defp is_store_query?(message) do
    message = String.downcase(message)

    query_keywords = [
      "how many products",
      "product count",
      "number of products",
      "total products",
      "how many items"
    ]

    Enum.any?(query_keywords, &String.contains?(message, &1))
  end

  defp handle_store_statistics(message) do
    case ShopifyClient.get_product_count() do
      {:ok, count} ->
        """
        📊 **Store Statistics**

        You currently have **#{count} products** in your Silicon Valley Shirts store.

        🏪 **Store Details:**
        • Store: silicon-valley-shirts.myshopify.com
        • Total Products: #{count}
        • [View All Products](https://admin.shopify.com/store/silicon-valley-shirts/products)

        💡 **Need help?** I can help you create more products, analyze your inventory, or manage your store!
        """

      {:error, error} ->
        """
        ❌ **Could not fetch store statistics**

        Error: #{error}

        Please make sure your SHOPIFY_ACCESS_TOKEN is set correctly in your environment variables.
        """
    end
  end

  # Simulate AI responses until we implement Ollama
  defp generate_ai_response(message, model) do
    # Simulate thinking time
    Process.sleep(1500)

    cond do
      String.contains?(String.downcase(message), "store") ->
        "I can help you connect your Shopify store! Once connected, I'll be able to analyze your products, orders, and customers. Would you like me to guide you through the setup process?"

      String.contains?(String.downcase(message), "product") ->
        "I'd be happy to help with product management! I can assist with generating descriptions, optimizing titles, managing inventory, and analyzing product performance. What specific product tasks can I help you with?\n\n💡 **Try saying**: \"Create a black t-shirt for $25\" to see me create a product in your store!"

      String.contains?(String.downcase(message), "sales") ->
        "Sales analytics are one of my specialties! I can help you track revenue trends, identify best-selling products, analyze customer behavior, and optimize your sales funnel. Connect your store to get detailed insights."

      true ->
        "Hello! I'm ShoppOllama, your AI-powered Shopify assistant running on #{model}. I can help you manage your store, analyze data, automate tasks, and much more. How can I assist you today?\n\n💡 **Try creating a product**: \"Create a red hoodie for $45\""
    end
  end

  defp check_store_connection do
    case Repo.get_by(Store, is_active: true) do
      nil -> false
      _store -> true
    end
  end
end
