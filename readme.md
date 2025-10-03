# Updator

A lightweight GitHub webhook server for automated deployments. Listens for GitHub release events and triggers deployment scripts automatically.

## Features

- 🔐 Secure webhook verification using HMAC SHA-256
- 🚀 Automatic deployment on release publication
- 🎯 Simple Express.js server
- ⚡ Easy to set up and configure
- 🔔 Real-time event logging

## Prerequisites

- Node.js (v14 or higher)
- npm or yarn
- A GitHub repository
- A deployment script

## Installation

1. Clone the repository:
```bash
git clone <your-repo-url>
cd updator
```

2. Install dependencies:
```bash
npm install
```

3. Set up environment variables:
```bash
export WEBHOOK_SECRET="your-secret-key"
```

## Configuration

### 1. Update Deployment Script Path

Edit `index.js` line 42 to point to your deployment script:
```javascript
exec('bash /path/to/your/deploy.sh', (err, stdout, stderr) => {
  // ...
});
```

### 2. Set Webhook Secret

The webhook secret can be configured via environment variable:
```bash
export WEBHOOK_SECRET="your-secret-key"
```

Or it defaults to `'test'` (not recommended for production).

### 3. Configure Port (Optional)

The server runs on port `8000` by default. You can modify this in `index.js`:
```javascript
const PORT = 8000;
```

## Usage

Start the server:
```bash
node index.js
```

You should see:
```
✅ Webhook server listening on http://localhost:8000
```

### Running in Production

For production, consider using a process manager like PM2:

```bash
npm install -g pm2
pm2 start index.js --name updator
pm2 save
pm2 startup
```

## GitHub Webhook Setup

1. Go to your GitHub repository
2. Navigate to **Settings** → **Webhooks** → **Add webhook**
3. Configure the webhook:
   - **Payload URL**: `http://your-server:8000/local-chat/new-release`
   - **Content type**: `application/json`
   - **Secret**: Enter the same secret you set in `WEBHOOK_SECRET`
   - **Events**: Select "Let me select individual events" → Check "Releases"
4. Click **Add webhook**

### Testing the Webhook

After setup, create a new release in your GitHub repository. The server will:
1. Verify the webhook signature
2. Log the event
3. Execute your deployment script automatically

## How It Works

1. GitHub sends a webhook POST request when a release is published
2. The server verifies the request signature using HMAC SHA-256
3. If valid and the event is a `release` publication, it executes the deployment script
4. Logs are output to the console with emoji indicators:
   - 🔔 Event received
   - 🚀 Release detected
   - ✅ Successful deployment
   - ❌ Deployment failed
   - ⚠️ Invalid signature

## API Endpoint

### POST `/local-chat/new-release`

Receives GitHub webhook events for releases.

**Headers:**
- `x-hub-signature-256`: GitHub's HMAC signature
- `x-github-event`: Event type (e.g., "release")

**Response:**
- `200 OK`: Webhook processed successfully
- `401 Unauthorized`: Invalid signature

## Security Considerations

- ✅ Always use a strong webhook secret in production
- ✅ Use HTTPS in production environments
- ✅ Implement rate limiting for production deployments
- ✅ Validate and sanitize inputs if extending functionality
- ✅ Run behind a reverse proxy (e.g., Nginx) for production

## Troubleshooting

### Webhook not triggering

1. Check server logs for incoming requests
2. Verify the webhook secret matches between GitHub and your server
3. Ensure your server is accessible from the internet
4. Check GitHub webhook delivery history in repository settings

### Deployment script fails

1. Verify the script path in `index.js`
2. Check script permissions (`chmod +x deploy.sh`)
3. Review logs for error messages

## License

ISC

## Contributing

Feel free to open issues or submit pull requests for improvements.

---

Built for home lab automated deployments 🏠

