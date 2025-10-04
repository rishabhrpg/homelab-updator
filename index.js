require('dotenv').config();
const express = require('express');
const bodyParser = require('body-parser');
const crypto = require('crypto');

const app = express();

// Load configuration from .env
const PORT = process.env.PORT || 8000;
const WEBHOOK_SECRET = process.env.SECRET || 'test';

// Middleware to parse JSON
app.use(bodyParser.json());

// Verify GitHub signature
function verifySignature(req) {
  const signature = req.headers['x-hub-signature-256'];
  if (!signature) return false;

  const hmac = crypto.createHmac('sha256', WEBHOOK_SECRET);
  const digest =
    'sha256=' + hmac.update(JSON.stringify(req.body)).digest('hex');

  return crypto.timingSafeEqual(Buffer.from(signature), Buffer.from(digest));
}

app.post('/local-chat/new-release', (req, res) => {
  if (!verifySignature(req)) {
    console.log('⚠️ Invalid signature, ignoring');
    return res.status(401).send('Invalid signature');
  }

  const event = req.headers['x-github-event'];
  console.log(`🔔 Received GitHub event: ${event}`);

  if (event === 'release' && req.body.action === 'published') {
    const release = req.body.release;
    console.log(`🚀 New release published: ${release.tag_name}`);
    console.log(`📝 Release notes: ${release.body}`);

    // Extract tarball URL from release
    const tarballUrl = release.tarball_url;
    const tagName = release.tag_name;

    console.log(`📦 Tarball URL: ${tarballUrl}`);

    // 👉 Trigger deploy script with tarball URL and tag name
    const { spawn } = require('child_process');
    
    console.log('🔧 Starting deployment...');
    const deployProcess = spawn('bash', [
      '/home/super/home-lab/local-chat/deploy.sh',
      tarballUrl,
      tagName
    ]);

    // Stream stdout in real-time
    deployProcess.stdout.on('data', (data) => {
      process.stdout.write(data);
    });

    // Stream stderr in real-time
    deployProcess.stderr.on('data', (data) => {
      process.stderr.write(data);
    });

    // Handle process completion
    deployProcess.on('close', (code) => {
      if (code === 0) {
        console.log('✅ Deploy completed successfully');
      } else {
        console.error(`❌ Deploy failed with exit code ${code}`);
      }
    });

    // Handle process errors
    deployProcess.on('error', (err) => {
      console.error('❌ Failed to start deploy script:', err);
    });
  }

  res.status(200).send('ok');
});

app
  .listen(PORT, () => {
    console.log(`✅ Webhook server listening on http://localhost:${PORT}`);
  })
  .on('error', (error) => {
    console.error('❌ Webhook server error:', error);
  });
