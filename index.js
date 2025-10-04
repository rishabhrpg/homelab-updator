require('dotenv').config();
const express = require('express');
const bodyParser = require('body-parser');
const crypto = require('crypto');
const path = require('path');

const app = express();

// Load configuration from .env
const PORT = process.env.PORT || 8000;
const WEBHOOK_SECRET = process.env.SECRET || 'test';
const DEPLOY_SCRIPT = process.env.DEPLOY_SCRIPT || path.join(__dirname, 'deploy-script.sh');

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
  const action = req.body.action;
  const deliveryId = req.headers['x-github-delivery'];
  
  console.log('━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━');
  console.log(`🔔 Received GitHub event: ${event}`);
  console.log(`📋 Action: ${action}`);
  console.log(`🆔 Delivery ID: ${deliveryId}`);
  console.log(`⏰ Timestamp: ${new Date().toISOString()}`);
  
  if (event === 'release') {
    const release = req.body.release;
    if (release) {
      console.log(`🏷️  Tag: ${release.tag_name || 'N/A'}`);
      console.log(`📛 Name: ${release.name || 'N/A'}`);
    }
  }

  if (event === 'release' && action === 'published') {
    const release = req.body.release;
    console.log('✅ This is a published release - triggering deployment!');
    console.log(`📝 Release notes: ${release.body}`);

    const tagName = release.tag_name;
    let downloadUrl = null;
    
    // Check if there are any uploaded assets (pre-built files)
    if (release.assets && release.assets.length > 0) {
      console.log(`📦 Found ${release.assets.length} release asset(s):`);
      
      // List all assets
      release.assets.forEach((asset, index) => {
        const sizeMB = (asset.size / 1024 / 1024).toFixed(2);
        console.log(`   ${index + 1}. ${asset.name} (${sizeMB} MB)`);
      });
      
      // Find first .tar.gz or .tgz asset
      const tarballAsset = release.assets.find(asset => 
        asset.name.endsWith('.tar.gz') || asset.name.endsWith('.tgz')
      );
      
      if (tarballAsset) {
        downloadUrl = tarballAsset.browser_download_url;
        console.log(`✅ Using pre-built asset: ${tarballAsset.name}`);
        console.log(`📦 Download URL: ${downloadUrl}`);
      } else {
        console.log('⚠️  No .tar.gz/.tgz asset found, falling back to source tarball');
        downloadUrl = release.tarball_url;
        console.log(`📦 Source tarball URL: ${downloadUrl}`);
      }
    } else {
      console.log('⚠️  No assets uploaded, using source tarball (will require building)');
      downloadUrl = release.tarball_url;
      console.log(`📦 Source tarball URL: ${downloadUrl}`);
    }

    if (!downloadUrl) {
      console.error('❌ No download URL available');
      res.status(500).send('No download URL');
      return;
    }

    // 👉 Trigger deploy script with download URL and tag name
    const { spawn } = require('child_process');
    
    console.log('🔧 Starting deployment process...');
    console.log(`📂 Script path: ${DEPLOY_SCRIPT}`);
    console.log(`🔗 Args: ["${downloadUrl}", "${tagName}"]`);
    console.log('━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━');
    
    const deployProcess = spawn('bash', [
      DEPLOY_SCRIPT,
      downloadUrl,
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
      console.log('━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━');
      if (code === 0) {
        console.log('✅ Deploy completed successfully');
      } else {
        console.error(`❌ Deploy failed with exit code ${code}`);
      }
      console.log('━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━');
    });

    // Handle process errors
    deployProcess.on('error', (err) => {
      console.error('━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━');
      console.error('❌ Failed to start deploy script:', err);
      console.error('💡 Make sure the script exists and is executable');
      console.error(`📂 Looking for: ${DEPLOY_SCRIPT}`);
      console.error('━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━');
    });
  } else {
    console.log(`⏭️  Skipping - not a published release (action: ${action})`);
    console.log('━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━');
  }

  res.status(200).send('ok');
});

app
  .listen(PORT, () => {
    console.log('━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━');
    console.log(`✅ Webhook server listening on http://localhost:${PORT}`);
    console.log(`🔐 Using webhook secret: ${WEBHOOK_SECRET === 'test' ? '⚠️  DEFAULT (change in production!)' : '✅ Custom secret configured'}`);
    console.log(`📡 Endpoint: POST /local-chat/new-release`);
    console.log(`📜 Deploy script: ${DEPLOY_SCRIPT}`);
    console.log('━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━');
  })
  .on('error', (error) => {
    console.error('❌ Webhook server error:', error);
  });
