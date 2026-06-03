const http = require('http');
const fs = require('fs');
const path = require('path');

const port = Number(process.env.PORT || 57830);
const root = path.resolve(__dirname, '..', 'build', 'web');
const types = {
  '.html': 'text/html',
  '.js': 'text/javascript',
  '.css': 'text/css',
  '.json': 'application/json',
  '.png': 'image/png',
  '.jpg': 'image/jpeg',
  '.jpeg': 'image/jpeg',
  '.svg': 'image/svg+xml',
  '.wasm': 'application/wasm',
  '.ico': 'image/x-icon',
};

http
  .createServer((req, res) => {
    const urlPath = decodeURIComponent(req.url.split('?')[0]);
    let filePath = path.join(root, urlPath === '/' ? 'index.html' : urlPath);
    if (!filePath.startsWith(root)) {
      res.writeHead(403);
      res.end('Forbidden');
      return;
    }

    fs.stat(filePath, (statError, stat) => {
      if (statError || !stat.isFile()) {
        filePath = path.join(root, 'index.html');
      }
      fs.readFile(filePath, (readError, data) => {
        if (readError) {
          res.writeHead(404);
          res.end('Not found');
          return;
        }
        res.writeHead(200, {
          'Content-Type': types[path.extname(filePath)] || 'application/octet-stream',
          'Cache-Control': 'no-store',
        });
        res.end(data);
      });
    });
  })
  .listen(port, '127.0.0.1');
