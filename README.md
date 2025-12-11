# Shoppollama

ShoppOllama is an AI-powered Shopify assistant built with Phoenix LiveView and Elixir. Here's what it does:

Core Purpose: It integrates with Shopify stores and uses local AI models (via Ollama) to provide intelligent assistance for store management.
Key Features:

AI Chat Interface: Offers streaming chat with model selection (gpt-oss:20b, gpt-oss:120b).
Shopify Integration: Connects to stores, syncs data, and enables automation.
RAG System: Uses Retrieval-Augmented Generation with vector embeddings for store data.
Local AI Processing: Leverages Ollama for local AI model execution.
Tech Stack:

Backend: Elixir/Phoenix with LiveView
Database: SQLite with vector search capabilities
AI: Ollama for local model serving
Frontend: Modern, dark-themed UI with real-time updates
The project is currently in development, with plans for features like store automation, real-time data syncing, and a polished UI. It's designed to be a self-hosted alternative to cloud-based Shopify apps, giving store owners more control over their data and AI processing.

To start your Phoenix server:

* Run `mix setup` to install and setup dependencies
* Start Phoenix endpoint with `mix phx.server` or inside IEx with `iex -S mix phx.server`

Now you can visit [`localhost:4000`](http://localhost:4000) from your browser.

Ready to run in production? Please [check our deployment guides](https://hexdocs.pm/phoenix/deployment.html).

## Learn more

* Official website: https://www.phoenixframework.org/
* Guides: https://hexdocs.pm/phoenix/overview.html
* Docs: https://hexdocs.pm/phoenix
* Forum: https://elixirforum.com/c/phoenix-forum
* Source: https://github.com/phoenixframework/phoenix
