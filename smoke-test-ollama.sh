#!/bin/bash

# Smoke test for ShoppOllama Ollama integration
# This script tests if the application is using real Ollama responses

echo "🧪 Running ShoppOllama Smoke Test..."
echo "=================================="

# Test 1: Check if Ollama is running
echo "1. Checking Ollama status..."
ssh -i shoppollama-key.pem -o StrictHostKeyChecking=no ec2-user@3.238.183.127 "sudo docker ps | grep shoppollama-ollama-1" > /dev/null
if [ $? -eq 0 ]; then
    echo "✅ Ollama container is running"
else
    echo "❌ Ollama container is not running"
    exit 1
fi

# Test 2: Check if the model is loaded
echo "2. Checking if llama3.2:3b model is loaded..."
MODEL_STATUS=$(ssh -i shoppollama-key.pem -o StrictHostKeyChecking=no ec2-user@3.238.183.127 "sudo docker logs shoppollama-ollama-1 2>&1 | grep -E 'llama runner started' | tail -1")
if [[ $MODEL_STATUS == *"llama runner started"* ]]; then
    echo "✅ Model is loaded and ready"
else
    echo "❌ Model is not ready"
    echo "Recent logs:"
    ssh -i shoppollama-key.pem -o StrictHostKeyChecking=no ec2-user@3.238.183.127 "sudo docker logs shoppollama-ollama-1 --tail 10"
    exit 1
fi

# Test 3: Check application logs for fallback responses
echo "3. Checking for fallback responses in logs..."
echo "Watching logs for new messages... (send a test message in the web UI now)"
echo "Press Ctrl+C to stop watching"

# Monitor logs for the generic fallback message
ssh -i shoppollama-key.pem -o StrictHostKeyChecking=no ec2-user@3.238.183.127 "sudo docker logs -f shoppollama-shoppollama-1" | grep --line-buffered -E "(Hello! I'm ShoppOllama|AI is thinking|Ollama connection error|TextAnalyzer failed)"

# Test 4: Direct Ollama API test
echo ""
echo "4. Testing direct Ollama API call..."
ssh -i shoppollama-key.pem -o StrictHostKeyChecking=no ec2-user@3.238.183.127 "sudo docker exec shoppollama-ollama-1 timeout 30 ollama run llama3.2:3b 'Say hello' 2>/dev/null" | head -1

echo ""
echo "=================================="
echo "Smoke test complete!"
echo ""
echo "If you see 'Hello! I'm ShoppOllama...' in the logs above, the app is using fallback responses."
echo "If you see actual AI responses, the integration is working!"
