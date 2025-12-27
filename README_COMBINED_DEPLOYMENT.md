# Combined EC2 Deployment (App + Ollama)

This guide explains how to deploy Shoppollama and Ollama on the same EC2 instance for better performance and simplified management.

## Deployment Options

### Option 1: Standard Combined Deployment (t3.large)

Deploy both Shoppollama and Ollama on a t3.large instance:

```bash
./deploy-ec2-combined.sh
```

**Instance Specifications:**
- Type: t3.large
- vCPU: 2
- RAM: 8 GB
- Storage: EBS (default)
- Cost: ~$0.0832/hour (~$60/month)

**Use Case:**
- Good for development and testing
- Supports smaller models (Llama 2 7B, Mistral 7B)
- Adequate for light to moderate traffic

### Option 2: GPU-Enabled Deployment (g4dn.xlarge)

Deploy with GPU support for better LLM performance:

```bash
./deploy-ec2-gpu.sh
```

**Instance Specifications:**
- Type: g4dn.xlarge
- vCPU: 4
- RAM: 16 GB
- GPU: NVIDIA T4 (16 GB VRAM)
- Storage: EBS (default)
- Cost: ~$0.526/hour (~$380/month)

**Use Case:**
- Production workloads
- Supports larger models (Llama 2 70B, CodeLlama 34B)
- Faster inference times
- Multiple concurrent users

## Architecture

Both deployment scripts create a Docker Compose setup with:

```
┌─────────────────────────────────────┐
│           EC2 Instance              │
│  ┌─────────────┐  ┌──────────────┐  │
│  │ Shoppollama │  │    Ollama    │  │
│  │   (Port     │  │   (Port      │  │
│  │    4000)    │  │   11434)     │  │
│  └─────────────┘  └──────────────┘  │
│                                     │
│  Docker Compose orchestrates both   │
│  services with shared networking    │
└─────────────────────────────────────┘
```

## Configuration

The application automatically detects Ollama's location through the `OLLAMA_BASE_URL` environment variable:

- In combined deployments: `OLLAMA_BASE_URL=http://ollama:11434`
- In separate deployments: `OLLAMA_BASE_URL=http://localhost:11434`

## Model Management

### Default Model
The deployment automatically pulls `llama2` as the default model.

### Changing Models
To use a different model:

```bash
# SSH into the instance
ssh -i shoppollama-key.pem ec2-user@<PUBLIC_IP>

# Pull a new model
docker-compose exec ollama ollama pull <model-name>

# Available models:
# - llama2 (7B)
# - llama2:13b (13B)
# - codellama (7B)
# - mistral (7B)
# - neural-chat (7B)
# - dolphin-mixtral (8x7B)
```

### Listing Models
```bash
docker-compose exec ollama ollama list
```

## Monitoring

### Check Service Status
```bash
# SSH into the instance
ssh -i shoppollama-key.pem ec2-user@<PUBLIC_IP>

# Check running containers
docker-compose ps

# View application logs
docker-compose logs shoppollama

# View Ollama logs
docker-compose logs ollama
```

### GPU Monitoring (for g4dn instances)
```bash
# Check GPU utilization
docker-compose exec ollama nvidia-smi

# Monitor GPU usage in real-time
docker-compose exec ollama watch nvidia-smi
```

## Performance Optimization

### For GPU Instances:
1. Use quantized models for better performance
2. Adjust context window size based on VRAM
3. Monitor GPU temperature and utilization

### For CPU Instances:
1. Stick to smaller models (7B parameters or less)
2. Consider model quantization
3. Monitor CPU and memory usage

## Scaling Considerations

### Vertical Scaling
- Upgrade to larger instance types in the same family
- t3.large → t3.xlarge → t3.2xlarge
- g4dn.xlarge → g4dn.2xlarge → g4dn.4xlarge

### Horizontal Scaling
- Deploy multiple app containers behind a load balancer
- Use a shared Ollama service or multiple Ollama instances
- Consider using EFS for shared model storage

## Cost Optimization

1. **Use Spot Instances** for non-production workloads
2. **Schedule Start/Stop** for development environments
3. **Right-size Instances** based on actual usage
4. **Use Savings Plans** for predictable workloads

## Troubleshooting

### Ollama Not Responding
```bash
# Check if Ollama is running
docker-compose ps ollama

# Restart Ollama
docker-compose restart ollama

# Check logs
docker-compose logs ollama
```

### Application Can't Connect to Ollama
```bash
# Verify network connectivity
docker-compose exec shoppollama curl http://ollama:11434/api/tags

# Check environment variables
docker-compose exec shoppollama env | grep OLLAMA
```

### Out of Memory Errors
1. Check instance memory usage: `free -h`
2. Monitor Docker stats: `docker stats`
3. Consider upgrading to a larger instance
4. Use smaller models or quantization

## Security Considerations

1. **Network Security**: Ollama is only exposed internally (port 11434)
2. **API Security**: Consider adding authentication for production
3. **Model Security**: Only use models from trusted sources
4. **Regular Updates**: Keep Docker images and dependencies updated

## Migration from Separate Instances

If you're currently running Shoppollama and Ollama on separate instances:

1. Backup your data from both instances
2. Run the combined deployment script
3. Restore data if needed
4. Update DNS/load balancer to point to new instance
5. Decommission old instances

## Support

For issues related to:
- **Deployment**: Check CloudFormation/EC2 logs
- **Application**: Check Docker logs
- **Ollama**: Check Ollama documentation at https://github.com/ollama/ollama
- **GPU Issues**: Check NVIDIA driver logs and CUDA compatibility
