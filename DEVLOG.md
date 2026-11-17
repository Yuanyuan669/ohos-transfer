# ohos-transfer DEVLOG

> 目的：记录设计决策、踩坑与当前状态，避免上下文压缩后重复踩坑。
> 相关：`D:\ohos-device\docs\APP-ROADMAP.md`、`docs/research/APP-FILETRANSFER.md`

## 2026-11-17 MVP

- 设计：普通应用内 `TCPSocketServer` 监听 `0.0.0.0:8080`；PC 浏览器访问 `http://<手机IP>:8080/?pin=xxxxxx`；
  6 位 PIN；`PUT /u/<name>` 上传、`GET /f/<name>` 下载、`GET /api/list` 列表、`GET /` 页面（拖拽上传）；
  文件落在沙箱 `filesDir/inbox`；`hdc` 脚本兜底（push/list/pull）。
- 实测：5 MB 中文名上传→下载 SHA256 一致；错误 PIN 401；切后台 45 s 端口仍 LISTEN；退出（terminateSelf）释放端口。

## 踩坑

1. **`fs.writeSync(fd, body.buffer)` 会把 header 也写进文件**：`body` 是 `Uint8Array.subarray`，其 `.buffer` 包含整个请求。
   → 修法：`body.buffer.slice(body.byteOffset, body.byteOffset + body.byteLength)`。
2. **`TCPSocketServer` 没有 `close()`**（API 11 d.ts）：只能 `off('connect')`；真正释放靠进程退出。
   → UI 用“退出”（`terminateSelf`），不提供“停止监听”假动作。
3. **`listen` 参数类型**：不要找 `TCPSocketServerListenOptions`；用 `socket.NetAddress`（`{address, port, family}`）。
4. **`on('message')` 回调**：参数是匿名 `{message: ArrayBuffer, remoteInfo}`，SDK 无导出类型；本地定义接口即可。
5. **Git Bash 路径转换**：`/data/...` 会被 MSYS 转成 Windows 路径，hdc 报 mutex 路径错误。
   → 脚本里 `export MSYS_NO_PATHCONV=1`、`MSYS2_ARG_CONV_EXCL="*"`。
6. **hdc push 到沙箱要 chown/chmod**：root `cp` 后属主是 root，应用无法写；
   → `chown $(stat -c %u inbox):$(stat -c %g inbox)` + `chmod 660`。
7. **每次 `hdc install -r` 会重置默认输入法为 Kika**；测试后恢复 homeime。
8. **picker 文件索引限制**：外部 cp 到 Documents/Download 后 picker 仍显示 0 项，需真实下载/文件管理建文件；picker→fd 代码已实现但待人工验证。

## 2026-11-17 M4：PIN 防爆破

- 设计：全局连续失败计数，5 次错误 PIN → 锁定 60 s（HTTP 429），成功即清零；重启应用解除。
- 实测：正确 PIN 200；连续 5 次错误 401；锁定期内即使 PIN 正确也返回 429；重启后新 PIN 正常，上传 200。
- 选择全局计数而非按 IP：TCPSocketConnection 不直接暴露远端的可靠 IP，且家庭场景单客户端足够。

## 2026-11-17 M5：大文件流式上传

- 原实现会把整个 body 缓存在内存，MAX_BODY=64MB，大文件必失败。改为 **边收边写**：
  解析到 PUT /u/<name> 并鉴权通过后立即 openSync(TRUNC)，后续每个 socket 消息直接 writeSync 到文件，完成后回 200；断连时关闭 fd 并记录中断。
- 鉴权提前到头部解析阶段（checkAuth），未授权不落盘；仍然使用 5 次失败锁定 60s。
- 上限提升到 8GB（MAX_UPLOAD），非上传请求仍限制 64MB。
- 实测：100MB（104857600B）上传 32.7s（约 3.2MB/s），下载 28.5s，两端 SHA256 完全一致。

## 待办

- M3：picker 导入已实现（DocumentViewPicker → 复制进 inbox），但测试机文件索引为空，需人工造文件验证。
- M5：1GB 压测、Wi-Fi 抖动、并发。
- 可选：`PUT` 支持 chunked/分片、断点续传。
