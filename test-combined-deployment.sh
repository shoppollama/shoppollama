#!/bin/bash

# Test script for combined EC2 deployment (App + Ollama)

IP="3.238.183.127"
echo "🧪 Testing Combined EC2 Deployment"
echo "=================================="
echo "📍 Instance IP: $IP"
echo ""

# Test 1: Check if application is running
echo "1. Testing Shoppollama app..."
if curl -s -I http://$IP:4000 | grep -q "200 OK"; then
    echo "✅ Shoppollama is accessible"
else
    echo "❌ Shoppollama is not responding"
fi

# Test 2: Check if Ollama is running
echo ""
echo "2. Testing Ollama API..."
if curl -s http://$IP:11434/api/tags | grep -q "llama2"; then
    echo "✅ Ollama API is accessible"
    echo "📦 Available models:"
    curl -s http://$IP:11434/api/tags | grep -o '"name":"[^"]*"' | sed 's/"name":"\(.*\)"/\1/'
else
    echo "❌ Ollama API is not responding"
fi

# Test 3: Test Ollama query
echo ""
echo "3. Testing Ollama query..."
RESPONSE=$(curl -s -X POST http://$IP:11434/api/generate \
  -H "Content-Type: application/json" \
  -d '{
    "model": "llama2",
    "prompt": "What is 2+2?",
    "stream": false
  }')

if echo "$RESPONSE" | grep -q "4"; then
    echo "✅ Ollama is responding correctly"
    echo "💬 Response: $(echo "$RESPONSE" | grep -o '"response":"[^"]*"' | cut -d'"' -f4)"
else
    echo "❌ Ollama query failed"
fi

# Test 4: Check Docker containers
echo ""
echo "4. Checking Docker containers..."
ssh -i shoppollama-key.pem -o StrictHostKeyChecking=no ec2-user@$IP "docker ps --format 'table {{.Names}}\t{{.Status}}\t{{.Ports}}'"

# Test 5: Check resource usage
echo ""
echo "5. Resource usage..."
echo "💾 Disk usage:"
ssh -i shoppollama-key.pem -o StrictHostKeyChecking=no ec2-user@$IP "df -h | grep -E '^/dev/'"
echo ""
echo "🔥 Memory usage:"
ssh -i shoppollama-key.pem -o StrictHostKeyChecking=no ec2-user@$IP "free -h"

echo ""
echo "✅ Testing complete!"
echo ""
echo "📊 Summary:"
echo "- Application URL: http://$IP:4000"
echo "- Ollama API: http://$IP:11434"
echo "- Model: llama2 (3.8GB)"
echo "- Instance type: t4g.large (2 vCPU, 8GB RAM, 50GB Storage)"
