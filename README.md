# Shoppollama

> **Open Source Agentic Commerce Platform built on Ollama and Stripe — Run DeepSeek, Llama3 & GPT-oss out of the box**

Shoppollama is an AI-powered commerce platform built with Phoenix LiveView and Elixir. It uses local AI models via Ollama (i.e. Llama3 and gpt-oss). It ships with its MCP server for payment testing powered by Stripe and Tidewave.

## Features

- **AI Chat Interface** — Streaming chat with model selection (DeepSeek, Llama3, GPT-oss)
- **Stripe Integration** — Connect to Stripe for payments and product management
- **Local AI Processing** — Run models locally with Ollama for privacy and control

## Tech Stack

- **Backend:** Elixir/Phoenix with LiveView
- **AI:** Ollama for local model serving and inference
- **Payments:** Stripe along with Tidewave MCP for development testing

---

## Getting Started

### Prerequisites

- Elixir 1.15+
- Erlang/OTP
- [Ollama](https://ollama.ai) installed and running
- Stripe Connect account (for payment features)
- Tidewave MCP server for payment testing

### 1. Install and Pull an Ollama Model

```bash
# Install Ollama (macOS)
brew install ollama

# Start Ollama server
ollama serve
```

In a new terminal, pull a model:

```bash
#  Llama3 - recommended for general use
ollama pull llama3.2:3b

# GPT-oss - alternative option
ollama pull gpt-oss:20b
```

### 2. Setup the Project

```bash
# Install dependencies and setup database
mix setup
```

### 3. Configure Environment

Copy values to your `.env` (i.e. Stripe keys):

```bash
STRIPE_SECRET_KEY=sk_test_...
STRIPE_PUBLISHABLE_KEY=pk_test_...
```

### 4. Start the Server

```bash
# Start Phoenix inside IEx (recommended for development)
iex -S mix phx.server
```

Visit [`localhost:4000`](http://localhost:4000) in your browser.

---

## Deploy to AWS with Pulumi

Shoppollama includes infrastructure-as-code for deploying to AWS using Pulumi.

### Prerequisites

- [Pulumi CLI](https://www.pulumi.com/docs/install/)
- [AWS CLI](https://aws.amazon.com/cli/) configured with credentials
- Node.js (for Pulumi TypeScript)

### Quick Deploy

```bash
# Install Pulumi
curl -fsSL https://get.pulumi.com | sh

# Configure AWS credentials
aws configure

# Run the deploy script
./deploy.sh
```

### Manual Deploy

```bash
# Install Node dependencies
npm install

# Select or create a stack
pulumi stack select dev  # or: pulumi stack init dev

# Preview the deployment
pulumi preview

# Deploy
pulumi up
```

The deployment creates:
- VPC with public subnets
- EC2 instances (t3.medium by default)
- Application Load Balancer
- Security groups

After deployment, get your URL:

```bash
pulumi stack output loadBalancerUrl
```

### Destroy Infrastructure

```bash
./destroy.sh
# or: pulumi destroy
```

---

## Development

```bash
# Run tests
mix test

# Start IEx with the app loaded
iex -S mix

# Start server in IEx
iex -S mix phx.server

# Reset database
mix ecto.reset
```

## Learn More

- [Phoenix Framework](https://www.phoenixframework.org/)
- [Ollama](https://ollama.ai)
- [Stripe API](https://stripe.com/docs/api)
- [Pulumi AWS](https://www.pulumi.com/docs/clouds/aws/)
