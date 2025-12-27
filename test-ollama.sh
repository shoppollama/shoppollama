#!/bin/bash

echo "Testing Ollama availability on EC2 instance..."
echo "=========================================="

# Test 1: Check if Ollama is running
echo "1. Testing Ollama health check:"
ssh -i shoppollama-key.pem -o StrictHostKeyChecking=no ec2-user@50.19.214.31 "curl -s http://localhost:11434/api/tags 2>/dev/null | head -3 || echo 'Ollama not responding'"

echo ""
echo "2. Testing application logs for Ollama activity:"
ssh -i shoppollama-key.pem -o StrictHostKeyChecking=no ec2-user@50.19.214.31 "sudo docker logs shoppollama 2>&1 | grep -i 'ollama\|mock' | tail -5 || echo 'No Ollama activity found'"

echo ""
echo "3. Checking if we can access the chat page:"
curl -s http://50.19.214.31:4000 | grep -q "shoppollama" && echo "✅ Chat page accessible" || echo "❌ Chat page not accessible"

echo ""
echo "4. Simulating a simple web request to trigger activity:"
curl -s -X POST http://50.19.214.31:4000 -H "Content-Type: application/x-www-form-urlencoded" \
  -d "_csrf_token=test&_mount_attempts=0" > /dev/null 2>&1

echo "5. Checking logs after request:"
ssh -i shoppollama-key.pem -o StrictHostKeyChecking=no ec2-user@50.19.214.31 "sudo docker logs shoppollama 2>&1 | tail -10"
