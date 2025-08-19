defmodule ShoppollamaWeb.ChatLive do
  use ShoppollamaWeb, :live_view
  alias Phoenix.PubSub

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
     |> assign(:store_connected, false)
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

    # Send to Ollama (we'll implement this service next)
    send(self(), {:call_ollama, message})

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

  # Simulate AI responses until we implement Ollama
  defp generate_ai_response(message, model) do
    # Simulate thinking time
    Process.sleep(1500)

    cond do
      String.contains?(String.downcase(message), "store") ->
        "I can help you connect your Shopify store! Once connected, I'll be able to analyze your products, orders, and customers. Would you like me to guide you through the setup process?"

      String.contains?(String.downcase(message), "product") ->
        "I'd be happy to help with product management! I can assist with generating descriptions, optimizing titles, managing inventory, and analyzing product performance. What specific product tasks can I help you with?"

      String.contains?(String.downcase(message), "sales") ->
        "Sales analytics are one of my specialties! I can help you track revenue trends, identify best-selling products, analyze customer behavior, and optimize your sales funnel. Connect your store to get detailed insights."

      true ->
        "Hello! I'm ShoppOllama, your AI-powered Shopify assistant running on #{model}. I can help you manage your store, analyze data, automate tasks, and much more. How can I assist you today?"
    end
  end
end
