# Combined EC2 Deployment Summary

## ✅ Successfully Deployed

Your Shoppollama application and Ollama are now running on the same EC2 instance.

### 📍 Instance Details
- **Instance ID**: i-01db3c4ed56bc79d7
- **Public IP**: 3.238.183.127
- **Instance Type**: t4g.large (ARM64)
- **Storage**: 50GB EBS (gp3)
- **Region**: us-east-1

### 🔗 Access URLs
- **Application**: http://3.238.183.127:4000
- **Ollama API**: http://3.238.183.127:11434

### 🏗️ Architecture
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

### 📦 Services Running
1. **Shoppollama Container**
   - Image: 279714322890.dkr.ecr.us-east-1.amazonaws.com/shoppollama:local-20251227-161742
   - Port: 4000
   - Environment: Production with Ollama integration

2. **Ollama Container**
   - Image: ollama/ollama:latest
   - Port: 11434
   - Model: llama2 (3.8GB)

### 🔧 Configuration
- Database: SQLite at `/app/data/shoppollama.db`
- Ollama Integration: Internal Docker network (http://ollama:11434)
- Security Group: Open ports 22, 4000, 11434

### 📊 Resource Usage
- **Disk**: 11GB used / 50GB total (22%)
- **Memory**: 5.9GB used / 7.7GB total
- **CPU**: 2 cores (ARM64)

### 🚀 Deployment Scripts Created
1. `deploy-ec2-combined.sh` - Standard combined deployment (t4g.large, 50GB)
2. `deploy-ec2-gpu.sh` - GPU-enabled deployment (g4dn.xlarge, 100GB)
3. `test-combined-deployment.sh` - Test script for verification

### 💰 Cost Estimate
- **t4g.large**: ~$0.0832/hour (~$60/month)
- **Storage**: ~$4.25/month (50GB gp3)
- **Data Transfer**: Varies based on usage

### 🔄 Management Commands

#### SSH into Instance
```bash
ssh -i shoppollama-key.pem ec2-user@3.238.183.127
```

#### Check Services
```bash
docker ps
docker-compose ps
```

#### View Logs
```bash
docker logs shoppollama-shoppollama-1
docker logs shoppollama-ollama-1
```

#### Restart Services
```bash
cd /var/www/shoppollama
docker-compose restart
```

#### Update Model
```bash
docker-compose exec ollama ollama pull <model-name>
```

### 📝 Next Steps
1. Configure a proper domain name with SSL
2. Set up monitoring and alerts
3. Configure backup for the database
4. Consider using AWS Secrets Manager for sensitive data

### 🛠️ Troubleshooting
- If Ollama is slow, consider upgrading to GPU instance
- Monitor memory usage with larger models
- Check logs for any application errors
- Ensure security group allows necessary ports

### 🎉 Success!
Both services are running successfully on a single EC2 instance, reducing complexity and improving performance by eliminating network latency between services.
