const http = require('node:http');
const {
  Counter,
  Histogram,
  Registry,
  collectDefaultMetrics
} = require('prom-client');

const PORT = 3000;
const VERSION = 'v2';

const registry = new Registry();

collectDefaultMetrics({ register: registry });

const httpRequests = new Counter({
  name: 'http_requests_total',
  help: 'Total HTTP requests',
  labelNames: ['method', 'route', 'status'],
  registers: [registry]
});

const httpDuration = new Histogram({
  name: 'http_request_duration_seconds',
  help: 'HTTP request duration in seconds',
  labelNames: ['method', 'route', 'status'],
  buckets: [0.05, 0.1, 0.2, 0.3, 0.5, 0.8, 1.5, 3, 10],
  registers: [registry]
});

const server = http.createServer(async (req, res) => {
  // Prometheus 메트릭 제공
  if (req.url === '/metrics') {
    try {
      const metrics = await registry.metrics();
      res.setHeader('Content-Type', registry.contentType);
      res.writeHead(200);
      return res.end(metrics);
    } catch {
      res.writeHead(500);
      return res.end('Metrics collection failed');
    }
  }

  res.setHeader('Content-Type', 'application/json');

  // 기존 ALB 헬스체크 유지
  if (req.url === '/health') {
    res.writeHead(200);
    return res.end(JSON.stringify({ status: 'UP' }));
  }

  // HTTP 요청 수 및 응답 시간 측정
  const start = process.hrtime.bigint();

  const route = req.url === '/' ? '/' : 'other';
  const methods = ['GET', 'POST', 'PUT', 'PATCH', 'DELETE', 'HEAD', 'OPTIONS'];
  const method = methods.includes(req.method) ? req.method : 'OTHER';

  res.once('finish', () => {
    const duration =
      Number(process.hrtime.bigint() - start) / 1e9;

    const labels = {
      method,
      route,
      status: String(res.statusCode)
    };

    httpRequests.inc(labels);
    httpDuration.observe(labels, duration);
  });

  // 기존 서비스 응답 유지
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
