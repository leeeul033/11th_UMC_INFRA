const http = require('node:http');

const PORT = 3000;
const VERSION = 'v1';

const server = http.createServer((req, res) => {
  res.setHeader('Content-Type', 'application/json');

  if (req.url === '/health') {
    res.writeHead(200);
    return res.end(JSON.stringify({ status: 'UP' }));
  }

  res.writeHead(200);
  res.end(JSON.stringify({
    message: 'UMC INFRA Deployment Lab',
    version: VERSION
  }));
});

server.listen(PORT, '0.0.0.0', () => {
  console.log(`Server listening on port ${PORT}`);
});

process.on('SIGTERM', () => server.close());
