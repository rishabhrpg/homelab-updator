module.exports = {
  apps: [
    {
      name: 'homelab-updator',
      script: './index.js',
      
      // Instance settings
      instances: 1,
      exec_mode: 'fork',
      
      // Auto-restart settings
      autorestart: true,
      watch: false,
      max_memory_restart: '200M',
      
      // Environment variables
      env: {
        NODE_ENV: 'production',
        PORT: 8000
      },
      
      // Logging
      error_file: './logs/error.log',
      out_file: './logs/out.log',
      log_file: './logs/combined.log',
      time: true,
      log_date_format: 'YYYY-MM-DD HH:mm:ss Z',
      
      // Advanced settings
      min_uptime: '10s',
      max_restarts: 10,
      restart_delay: 4000,
      
      // Merge logs from cluster instances
      merge_logs: true,
      
      // Don't auto restart if app crashes too many times
      exp_backoff_restart_delay: 100
    }
  ]
};
