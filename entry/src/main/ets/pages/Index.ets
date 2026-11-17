import common from '@ohos.app.ability.common';
import fs from '@ohos.file.fs';
import picker from '@ohos.file.picker';
import connection from '@ohos.net.connection';
import { TransferServer } from '../service/TransferServer';
import { Log } from '../common/Logger';

@Entry
@Component
struct Index {
  @State running: boolean = false;
  @State pin: string = '------';
  @State urlText: string = '正在获取手机 IP…';
  @State logText: string = '';
  @State files: string[] = [];
  @State sizeText: string = '';
  private server: TransferServer | null = null;
  private inbox: string = '';

  aboutToAppear(): void {
    const ctx: common.UIAbilityContext = getContext(this) as common.UIAbilityContext;
    this.inbox = ctx.filesDir + '/inbox';
    this.server = new TransferServer(this.inbox);
    this.server.onLog = (line: string) => {
      this.logText = (line + '\n' + this.logText).substring(0, 1200);
    };
    this.server.onFilesChanged = () => {
      this.loadFiles();
    };
    this.refreshIp();
    this.startServer();
  }

  aboutToDisappear(): void {
    if (this.server !== null) {
      this.server.stop();
    }
  }

  private startServer(): void {
    if (this.server === null) {
      return;
    }
    this.server.start();
    // listen 是异步的，稍后同步状态
    setTimeout(() => {
      if (this.server !== null) {
        this.running = this.server.running;
        this.pin = this.server.pin;
        this.loadFiles();
      }
    }, 400);
  }

  private stopServer(): void {
    if (this.server !== null) {
      this.server.stop();
      this.running = false;
    }
  }

  private loadFiles(): void {
    if (this.server === null) {
      return;
    }
    const names: string[] = this.server.listFiles();
    this.files = names;
    let total: number = 0;
    for (let i = 0; i < names.length; i++) {
      total += this.server.sizeOf(names[i]);
    }
    this.sizeText = names.length + ' 个文件 · ' + this.human(total);
  }

  private human(n: number): string {
    if (n < 1024) {
      return n + ' B';
    }
    if (n < 1048576) {
      return (n / 1024).toFixed(1) + ' KB';
    }
    if (n < 1073741824) {
      return (n / 1048576).toFixed(1) + ' MB';
    }
    return (n / 1073741824).toFixed(2) + ' GB';
  }

  private refreshIp(): void {
    connection.getDefaultNet().then((net: connection.NetHandle) => {
      return connection.getConnectionProperties(net);
    }).then((props: connection.ConnectionProperties) => {
      const addrs: connection.LinkAddress[] = props.linkAddresses;
      let ip: string = '';
      for (let i = 0; i < addrs.length; i++) {
        const a: string = addrs[i].address.address;
        if (a.length > 0 && a !== '127.0.0.1' && a.indexOf(':') < 0) {
          ip = a;
          break;
        }
      }
      this.urlText = ip.length > 0 ? ('http://' + ip + ':8080/?pin=' + this.pin) : '未连 Wi-Fi（可用 USB: hdc fport tcp:8080 tcp:8080）';
    }).catch(() => {
      this.urlText = '未连 Wi-Fi（可用 USB: hdc fport tcp:8080 tcp:8080）';
    });
    setTimeout(() => {
      if (this.urlText.indexOf('http://') === 0 && this.urlText.indexOf('------') >= 0 && this.pin !== '------') {
        this.refreshIp();
      }
    }, 600);
  }

  private async importFiles(): Promise<void> {
    try {
      const ctx: common.UIAbilityContext = getContext(this) as common.UIAbilityContext;
      const options: picker.DocumentSelectOptions = new picker.DocumentSelectOptions();
      options.maxSelectNumber = 20;
      const p: picker.DocumentViewPicker = new picker.DocumentViewPicker();
      const uris: string[] = await p.select(options);
      for (let i = 0; i < uris.length; i++) {
        this.copyIntoInbox(uris[i]);
      }
      this.loadFiles();
      this.server?.onLog('已导入 ' + uris.length + ' 个文件');
    } catch (e) {
      Log.warn('picker failed: ' + (e as Error).message);
    }
  }

  private copyIntoInbox(uri: string): void {
    let name: string = uri;
    const slash: number = name.lastIndexOf('/');
    if (slash >= 0) {
      name = name.substring(slash + 1);
    }
    try {
      name = decodeURIComponent(name);
    } catch (e) {
    }
    const dest: string = this.inbox + '/' + name;
    const src: fs.File = fs.openSync(uri, fs.OpenMode.READ_ONLY);
    const dst: fs.File = fs.openSync(dest, fs.OpenMode.CREATE | fs.OpenMode.WRITE_ONLY | fs.OpenMode.TRUNC);
    const buf: ArrayBuffer = new ArrayBuffer(64 * 1024);
    let read: number = 0;
    do {
      read = fs.readSync(src.fd, buf, { offset: 0, length: buf.byteLength });
      if (read > 0) {
        fs.writeSync(dst.fd, buf.slice(0, read));
      }
    } while (read > 0);
    fs.closeSync(src.fd);
    fs.closeSync(dst.fd);
  }

  build() {
    Column() {
      Row() {
        Column({ space: 4 }) {
          Text('快传')
            .fontSize(30)
            .fontWeight(FontWeight.Bold)
            .fontColor('#E7EDF5')
          Text('手机 ⇄ 电脑 · 同一 Wi-Fi')
            .fontSize(13)
            .fontColor('#8FA0B5')
        }
        .layoutWeight(1)
        .alignItems(HorizontalAlign.Start)

        Button(this.running ? '退出' : '重试')
          .fontSize(15)
          .backgroundColor(this.running ? '#7A2E2E' : '#2F6FED')
          .onClick(() => {
            if (this.running) {
              const ctx: common.UIAbilityContext = getContext(this) as common.UIAbilityContext;
              this.stopServer();
              ctx.terminateSelf();
            } else {
              this.startServer();
            }
          })
      }
      .width('100%')

      Column({ space: 10 }) {
        Text(this.running ? ('PIN ' + this.pin) : '服务未启动')
          .fontSize(26)
          .fontWeight(FontWeight.Medium)
          .fontColor(this.running ? '#6EA8FF' : '#8FA0B5')
          .letterSpacing(3)
        Text(this.urlText)
          .fontSize(13)
          .fontColor('#B9C6D6')
          .textAlign(TextAlign.Center)
        Text('电脑浏览器打开上面的地址（或先 hdc fport tcp:8080 tcp:8080 再访问 127.0.0.1:8080）')
          .fontSize(11)
          .fontColor('#72839A')
          .textAlign(TextAlign.Center)
      }
      .width('100%')
      .padding({ top: 18, bottom: 16 })
      .margin({ top: 14 })
      .backgroundColor('#151A21')
      .borderRadius(14)

      Row() {
        Text('收件箱')
          .fontSize(15)
          .fontWeight(FontWeight.Medium)
          .fontColor('#E7EDF5')
          .layoutWeight(1)
        Text(this.sizeText)
          .fontSize(12)
          .fontColor('#8FA0B5')
        Button('导入文件')
          .fontSize(12)
          .height(30)
          .margin({ left: 10 })
          .backgroundColor('#243041')
          .onClick(() => {
            this.importFiles();
          })
      }
      .width('100%')
      .margin({ top: 16 })

      List({ space: 4 }) {
        ForEach(this.files, (name: string) => {
          ListItem() {
            Row() {
              Text(name)
                .fontSize(13)
                .fontColor('#D5DEEC')
                .layoutWeight(1)
                .maxLines(1)
                .textOverflow({ overflow: TextOverflow.Ellipsis })
              Text(this.human(this.server !== null ? this.server.sizeOf(name) : 0))
                .fontSize(11)
                .fontColor('#72839A')
                .margin({ left: 10 })
            }
            .width('100%')
            .padding({ left: 4, right: 4, top: 8, bottom: 8 })
            .border({ width: { bottom: 1 }, color: '#232B35' })
          }
        }, (name: string) => name)
      }
      .width('100%')
      .layoutWeight(1)
      .margin({ top: 6 })

      Text(this.logText.length > 0 ? this.logText : '日志：等待电脑连接…')
        .fontSize(10)
        .fontColor('#6A7A8F')
        .width('100%')
        .height(70)
        .margin({ top: 8 })
    }
    .width('100%')
    .height('100%')
    .padding({ left: 22, right: 22, top: 24, bottom: 16 })
    .backgroundColor('#0F1216')
  }
}
