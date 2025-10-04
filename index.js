const express = require('express');
const bodyParser = require('body-parser');
const crypto = require('crypto');

const app = express();
const PORT = 8000;

// Middleware to parse JSON
app.use(bodyParser.json());

// Your GitHub webhook secret (set the same in GitHub)
const WEBHOOK_SECRET = process.env.WEBHOOK_SECRET || 'test';

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
    const { exec } = require('child_process');
    exec(
      `bash /home/super/home-lab/local-chat/deploy.sh "${tarballUrl}" "${tagName}"`,
      (err, stdout, stderr) => {
        if (err) {
          console.error('❌ Deploy failed:', err);
          console.error('Error details:', stderr);
          return;
        }
        console.log('✅ Deploy success:', stdout);
        if (stderr) {
          console.log('Deploy warnings:', stderr);
        }
      }
    );
  }

  res.status(200).send('ok');
});

app.listen(
  PORT,
  () => {
    console.log(`✅ Webhook server listening on http://localhost:${PORT}`);
  },
  (error) => {
    console.error('❌ Webhook server error:', error);
  }
);
