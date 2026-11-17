import socket from '@ohos.net.socket';
import fs from '@ohos.file.fs';
import util from '@ohos.util';
import { Log } from '../common/Logger';

const MAX_BODY: number = 64 * 1024 * 1024;
const CHUNK: number = 64 * 1024;

interface MsgInfo {
  message: ArrayBuffer;
}

interface ParsedReq {
  method: string;
  path: string;
  query: Map<string, string>;
  headers: Map<string, string>;
  headerLen: number;
  contentLength: number;
}

class ConnState {
  chunks: Uint8Array = new Uint8Array(0);
  req: ParsedReq | null = null;
  handled: boolean = false;
}

function encoder(): util.TextEncoder {
  return new util.TextEncoder();
}

function decoder(): util.TextDecoder {
  return new util.TextDecoder();
}

function concat(a: Uint8Array, b: Uint8Array): Uint8Array {
  const out: Uint8Array = new Uint8Array(a.length + b.length);
  out.set(a, 0);
  out.set(b, a.length);
  return out;
}

function headerEndIndex(buf: Uint8Array): number {
  for (let i = 0; i + 3 < buf.length; i++) {
    if (buf[i] === 13 && buf[i + 1] === 10 && buf[i + 2] === 13 && buf[i + 3] === 10) {
      return i;
    }
  }
  return -1;
}

function safeName(name: string): boolean {
  if (name.length === 0 || name.length > 200) {
    return false;
  }
  if (name.indexOf('..') >= 0 || name.indexOf('/') >= 0 || name.indexOf('\\') >= 0) {
    return false;
  }
  return true;
}

export class TransferServer {
  private server: socket.TCPSocketServer | null = null;
  private inbox: string = '';
  private states: Map<number, ConnState> = new Map<number, ConnState>();
  public pin: string = '';
  public port: number = 8080;
  public running: boolean = false;
  public onLog: (line: string) => void = (line: string) => {
  };
  public onFilesChanged: () => void = () => {
  };
  private failCount: number = 0;
  private lockUntil: number = 0;

  constructor(inboxDir: string) {
    this.inbox = inboxDir;
    try {
      fs.mkdirSync(inboxDir);
    } catch (e) {
      // already exists
    }
  }

  public listFiles(): string[] {
    try {
      const names: string[] = fs.listFileSync(this.inbox);
      return names.sort();
    } catch (e) {
      return [];
    }
  }

  public sizeOf(name: string): number {
    try {
      const st: fs.Stat = fs.statSync(this.inbox + '/' + name);
      return st.size;
    } catch (e) {
      return 0;
    }
  }

  public start(): void {
    if (this.running) {
      return;
    }
    this.pin = '' + Math.floor(100000 + Math.random() * 900000);
    const srv: socket.TCPSocketServer = socket.constructTCPSocketServerInstance();
    this.server = srv;
    const options: socket.NetAddress = {
      address: '0.0.0.0',
      port: this.port,
      family: 1
    };
    srv.listen(options).then(() => {
      this.running = true;
      this.log('监听 0.0.0.0:' + this.port + ' 成功');
      srv.on('connect', (conn: socket.TCPSocketConnection) => {
        this.onConnect(conn);
      });
    }).catch((e: Error) => {
      this.running = false;
      this.log('监听失败: ' + e.message);
    });
  }

  public stop(): void {
    if (this.server !== null) {
      try {
        this.server.off('connect');
      } catch (e) {
      }
    }
    this.states.clear();
    this.running = false;
    this.log('已停止监听');
  }

  private log(line: string): void {
    Log.info('[transfer] ' + line);
    this.onLog(line);
  }

  private onConnect(conn: socket.TCPSocketConnection): void {
    const id: number = conn.clientId;
    this.states.set(id, new ConnState());
    this.log('PC 已连接 #' + id);
    conn.on('message', (info: MsgInfo) => {
      const st: ConnState | null = this.states.get(id) ?? null;
      if (st === null || st.handled) {
        return;
      }
      const chunk: Uint8Array = new Uint8Array(info.message);
      st.chunks = concat(st.chunks, chunk);
      if (st.req === null) {
        const idx: number = headerEndIndex(st.chunks);
        if (idx < 0) {
          if (st.chunks.length > 64 * 1024) {
            st.handled = true;
            this.sendText(conn, 431, 'header too large');
          }
          return;
        }
        st.req = this.parseRequest(st.chunks, idx);
        if (st.req === null) {
          st.handled = true;
          this.sendText(conn, 400, 'bad request');
          return;
        }
      }
      const need: number = st.req.headerLen + st.req.contentLength;
      if (st.chunks.length < need) {
        if (st.chunks.length > MAX_BODY) {
          st.handled = true;
          this.sendText(conn, 413, 'too large');
        }
        return;
      }
      st.handled = true;
      const body: Uint8Array = st.chunks.subarray(st.req.headerLen, need);
      this.handle(conn, st.req, body);
    });
    conn.on('close', () => {
      this.states.delete(id);
      this.log('连接关闭 #' + id);
    });
  }

  private parseRequest(buf: Uint8Array, headerEnd: number): ParsedReq | null {
    try {
      const headText: string = decoder().decode(buf.subarray(0, headerEnd));
      const lines: string[] = headText.split('\r\n');
      if (lines.length === 0) {
        return null;
      }
      const first: string[] = lines[0].split(' ');
      if (first.length < 2) {
        return null;
      }
      const req: ParsedReq = {
        method: first[0],
        path: '/',
        query: new Map<string, string>(),
        headers: new Map<string, string>(),
        headerLen: headerEnd + 4,
        contentLength: 0
      };
      const rawPath: string = first[1];
      const q: number = rawPath.indexOf('?');
      if (q >= 0) {
        req.path = rawPath.substring(0, q);
        const qs: string = rawPath.substring(q + 1);
        const pairs: string[] = qs.split('&');
        for (let i = 0; i < pairs.length; i++) {
          const kv: string[] = pairs[i].split('=');
          if (kv.length >= 1) {
            const k: string = decodeURIComponent(kv[0]);
            const v: string = kv.length > 1 ? decodeURIComponent(kv[1]) : '';
            req.query.set(k, v);
          }
        }
      } else {
        req.path = rawPath;
      }
      for (let i = 1; i < lines.length; i++) {
        const c: number = lines[i].indexOf(':');
        if (c > 0) {
          const k: string = lines[i].substring(0, c).trim().toLowerCase();
          const v: string = lines[i].substring(c + 1).trim();
          req.headers.set(k, v);
        }
      }
      const cl: string | undefined = req.headers.get('content-length');
      req.contentLength = cl !== undefined ? Number(cl) : 0;
      if (Number.isNaN(req.contentLength) || req.contentLength < 0) {
        req.contentLength = 0;
      }
      return req;
    } catch (e) {
      return null;
    }
  }

  private authorized(req: ParsedReq): boolean {
    const q: string | undefined = req.query.get('pin');
    if (q !== undefined && q === this.pin) {
      return true;
    }
    const h: string | undefined = req.headers.get('x-pin');
    return h !== undefined && h === this.pin;
  }

  private handle(conn: socket.TCPSocketConnection, req: ParsedReq, body: Uint8Array): void {
    this.log(req.method + ' ' + req.path);
    if (Date.now() < this.lockUntil) {
      this.sendText(conn, 429, 'too many attempts');
      return;
    }
    if (!this.authorized(req)) {
      this.failCount++;
      if (this.failCount >= 5) {
        this.lockUntil = Date.now() + 60000;
        this.failCount = 0;
        this.log('PIN 连续失败 5 次，锁定 60 秒');
      }
      this.sendText(conn, 401, 'PIN 错误或缺失');
      return;
    }
    this.failCount = 0;
    this.lockUntil = 0;
    if (req.method === 'GET' && (req.path === '/' || req.path === '/index.html')) {
      this.sendHtml(conn, this.pageHtml());
      return;
    }
    if (req.method === 'GET' && req.path === '/api/list') {
      const names: string[] = this.listFiles();
      const items: string[] = [];
      for (let i = 0; i < names.length; i++) {
        items.push('{"name":"' + this.escapeJson(names[i]) + '","size":' + this.sizeOf(names[i]) + '}');
      }
      this.sendJson(conn, '{"files":[' + items.join(',') + ']}');
      return;
    }
    if (req.method === 'GET' && req.path.indexOf('/f/') === 0) {
      const name: string = decodeURIComponent(req.path.substring(3));
      if (!safeName(name)) {
        this.sendText(conn, 400, 'bad name');
        return;
      }
      this.sendFile(conn, name);
      return;
    }
    if ((req.method === 'PUT' || req.method === 'POST') && req.path.indexOf('/u/') === 0) {
      const name: string = decodeURIComponent(req.path.substring(3));
      if (!safeName(name)) {
        this.sendText(conn, 400, 'bad name');
        return;
      }
      this.saveFile(conn, name, body);
      return;
    }
    this.sendText(conn, 404, 'not found');
  }

  private sendText(conn: socket.TCPSocketConnection, code: number, text: string): void {
    const bytes: Uint8Array = encoder().encode(text);
    const head: string = 'HTTP/1.1 ' + code + ' ' + (code === 200 ? 'OK' : 'ERR')
      + '\r\nContent-Type: text/plain; charset=utf-8\r\nContent-Length: ' + bytes.length
      + '\r\nConnection: close\r\n\r\n';
    conn.send({ data: head }).then(() => {
      return conn.send({ data: bytes.buffer });
    }).then(() => {
      conn.close();
    }).catch(() => {
      try {
        conn.close();
      } catch (e) {
      }
    });
  }

  private sendJson(conn: socket.TCPSocketConnection, json: string): void {
    const bytes: Uint8Array = encoder().encode(json);
    const head: string = 'HTTP/1.1 200 OK\r\nContent-Type: application/json; charset=utf-8\r\nContent-Length: '
      + bytes.length + '\r\nAccess-Control-Allow-Origin: *\r\nConnection: close\r\n\r\n';
    conn.send({ data: head }).then(() => {
      return conn.send({ data: bytes.buffer });
    }).then(() => {
      conn.close();
    }).catch(() => {
      try {
        conn.close();
      } catch (e) {
      }
    });
  }

  private sendHtml(conn: socket.TCPSocketConnection, html: string): void {
    const bytes: Uint8Array = encoder().encode(html);
    const head: string = 'HTTP/1.1 200 OK\r\nContent-Type: text/html; charset=utf-8\r\nContent-Length: '
      + bytes.length + '\r\nCache-Control: no-store\r\nConnection: close\r\n\r\n';
    conn.send({ data: head }).then(() => {
      return conn.send({ data: bytes.buffer });
    }).then(() => {
      conn.close();
    }).catch(() => {
      try {
        conn.close();
      } catch (e) {
      }
    });
  }

  private sendFile(conn: socket.TCPSocketConnection, name: string): void {
    const path: string = this.inbox + '/' + name;
    let file: fs.File | null = null;
    let size: number = 0;
    try {
      size = fs.statSync(path).size;
      file = fs.openSync(path, fs.OpenMode.READ_ONLY);
    } catch (e) {
      this.sendText(conn, 404, 'file not found');
      return;
    }
    const head: string = 'HTTP/1.1 200 OK\r\nContent-Type: application/octet-stream\r\nContent-Length: '
      + size + '\r\nContent-Disposition: attachment; filename*=UTF-8\'\''
      + encodeURIComponent(name) + '\r\nConnection: close\r\n\r\n';
    let offset: number = 0;
    const buf: ArrayBuffer = new ArrayBuffer(CHUNK);
    conn.send({ data: head }).then(async () => {
      if (file === null) {
        return;
      }
      while (offset < size) {
        const read: number = fs.readSync(file.fd, buf, { offset: offset, length: Math.min(CHUNK, size - offset) });
        if (read <= 0) {
          break;
        }
        await conn.send({ data: buf.slice(0, read) });
        offset += read;
      }
      fs.closeSync(file.fd);
      conn.close();
    }).catch(() => {
      try {
        if (file !== null) {
          fs.closeSync(file.fd);
        }
      } catch (e) {
      }
      try {
        conn.close();
      } catch (e) {
      }
    });
  }

  private saveFile(conn: socket.TCPSocketConnection, name: string, body: Uint8Array): void {
    const path: string = this.inbox + '/' + name;
    try {
      const file: fs.File = fs.openSync(path, fs.OpenMode.CREATE | fs.OpenMode.WRITE_ONLY | fs.OpenMode.TRUNC);
      const out: ArrayBuffer = body.buffer.slice(body.byteOffset, body.byteOffset + body.byteLength);
      fs.writeSync(file.fd, out);
      fs.closeSync(file.fd);
      this.log('收到 ' + name + ' (' + body.length + 'B)');
      this.onFilesChanged();
      this.sendText(conn, 200, 'ok');
    } catch (e) {
      this.sendText(conn, 500, 'write failed');
    }
  }

  private escapeJson(s: string): string {
    return s.split('\\').join('\\\\').split('"').join('\\"');
  }

  private pageHtml(): string {
    const pin: string = this.pin;
    return '<!doctype html><html><head><meta charset="utf-8">'
      + '<meta name="viewport" content="width=device-width,initial-scale=1">'
      + '<title>快传</title><style>'
      + 'body{background:#0f1216;color:#e7edf5;font-family:system-ui,-apple-system,"Segoe UI",sans-serif;margin:0;padding:28px}'
      + 'h1{font-size:22px;margin:0 0 6px}.sub{color:#8fa0b5;font-size:13px;margin-bottom:20px}'
      + '.drop{border:1px dashed #3a4757;border-radius:14px;padding:40px;text-align:center;color:#9fb0c4;background:#151a21}'
      + '.drop.hover{border-color:#4f8cff;background:#182231}'
      + 'input[type=file]{display:none}button{background:#2f6fed;color:#fff;border:0;border-radius:9px;padding:10px 16px;font-size:14px;cursor:pointer}'
      + '#list{margin-top:22px}.row{display:flex;justify-content:space-between;align-items:center;padding:11px 4px;border-bottom:1px solid #232b35;font-size:14px}'
      + 'a{color:#6ea8ff;text-decoration:none}.muted{color:#72839a;font-size:12px}'
      + '</style></head><body>'
      + '<h1>快传 · 手机与电脑互传</h1><div class="sub">PIN ' + pin + ' · 拖拽文件到下面，或点击选择</div>'
      + '<div class="drop" id="drop">把文件拖到这里，或<label for="f" style="color:#6ea8ff;cursor:pointer">点击选择</label>'
      + '<input id="f" type="file" multiple></div><div id="list"></div>'
      + '<script>var PIN="' + pin + '";'
      + 'function fmt(n){if(n<1024)return n+" B";if(n<1048576)return (n/1024).toFixed(1)+" KB";return (n/1048576).toFixed(1)+" MB"}'
      + 'function load(){fetch("/api/list?pin="+PIN).then(function(r){return r.json()}).then(function(j){'
      + 'var h="";j.files.forEach(function(f){h+=\'<div class="row"><span>\'+f.name+\' <span class="muted">\'+fmt(f.size)+\'</span></span>\''
      + '+\'<a href="/f/\'+encodeURIComponent(f.name)+\'?pin=\'+PIN+\'">下载</a></div>\'});'
      + 'document.getElementById("list").innerHTML=h||\'<div class="muted" style="margin-top:18px">收件箱还是空的</div>\'})}'
      + 'function up(files){var i=0;function next(){if(i>=files.length){load();return}var f=files[i++];'
      + 'fetch("/u/"+encodeURIComponent(f.name)+"?pin="+PIN,{method:"PUT",body:f}).then(function(){next()},function(){alert("上传失败: "+f.name);next()})}next()}'
      + 'var d=document.getElementById("drop"),inp=document.getElementById("f");'
      + 'inp.onchange=function(){up(inp.files);inp.value=""};'
      + 'd.ondragover=function(e){e.preventDefault();d.classList.add("hover")};'
      + 'd.ondragleave=function(){d.classList.remove("hover")};'
      + 'd.ondrop=function(e){e.preventDefault();d.classList.remove("hover");up(e.dataTransfer.files)};'
      + 'd.onclick=function(e){if(e.target===d){inp.click()}};load();setInterval(load,3000);'
      + '</script></body></html>';
  }
}
