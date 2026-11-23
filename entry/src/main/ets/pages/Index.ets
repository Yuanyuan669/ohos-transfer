import common from '@ohos.app.ability.common';
import fs from '@ohos.file.fs';
import image from '@ohos.multimedia.image';
import picker from '@ohos.file.picker';
import connection from '@ohos.net.connection';
import { TransferServer } from '../service/TransferServer';
import { PreviewSource } from '../service/PreviewSource';
import { AlbumSaver } from '../service/AlbumSaver';
import { Log } from '../common/Logger';

// 导入大小上限：正常照片/文档远小于此，仅用于拦截异常膨胀（见 copyToInbox 注释）。
const MAX_IMPORT_BYTES: number = 2 * 1024 * 1024 * 1024;

@Entry
@Component
struct Index {
  @State running: boolean = false;
  @State pin: string = '------';
  @State urlText: string = '正在获取手机 IP…';
  @State logText: string = '';
  @State files: string[] = [];
  @State sizeText: string = '';
  @State showPreview: boolean = false;
  @State previewTitle: string = '';
  @State previewKind: string = '';
  @State previewText: string = '';
  @State previewPhoto: image.PixelMap | null = null;
  private server: TransferServer | null = null;
  private inbox: string = '';

  aboutToAppear(): void {
    const ctx: common.UIAbilityContext = getContext(this) as common.UIAbilityContext;
    this.inbox = ctx.filesDir + '/inbox';
    this.server = new TransferServer(this.inbox);
    this.server.onLog = (line: string) => {
      // 电脑端每 3 秒轮询 /api/list，会持续刷「连接关闭 #id」，对用户是误导。
      if (line.indexOf('连接关闭') === 0) {
        return;
      }
      this.appendLog(line);
    };
    this.server.onFilesChanged = () => {
      this.loadFiles();
    };
    this.refreshIp();
    this.startServer();
  }

  aboutToDisappear(): void {
    this.closePreview();
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

  private appendLog(line: string): void {
    this.logText = (line + '\n' + this.logText).substring(0, 1200);
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

  private openPreview(name: string): void {
    const kind: string = PreviewSource.kind(name);
    Log.info('preview tap ' + name + ' kind=' + kind);
    if (kind.length === 0) {
      this.appendLog('『' + name + '』暂不支持预览，请在电脑端下载');
      return;
    }
    const path: string = this.inbox + '/' + name;
    this.closePreview();
    this.previewTitle = name;
    this.previewKind = kind;
    if (kind === 'image') {
      this.showPreview = true;
      PreviewSource.decodeImage(path).then((pm: image.PixelMap | null) => {
        if (pm === null) {
          this.closePreview();
          this.appendLog('图片解码失败：' + name);
          return;
        }
        if (!this.showPreview || this.previewTitle !== name) {
          PreviewSource.releaseMap(pm);
          return;
        }
        this.previewPhoto = pm;
      });
    } else {
      this.previewText = PreviewSource.readText(path);
      this.showPreview = true;
    }
  }

  private closePreview(): void {
    this.showPreview = false;
    this.previewText = '';
    this.releasePreviewPhoto();
  }

  private saveToAlbum(): void {
    if (!AlbumSaver.isImage(this.previewTitle)) {
      this.appendLog('该文件不是图片，无法保存到相册');
      return;
    }
    const ctx: common.UIAbilityContext = getContext(this) as common.UIAbilityContext;
    const path: string = this.inbox + '/' + this.previewTitle;
    AlbumSaver.saveImage(ctx, path, this.previewTitle).then((ok: boolean) => {
      this.appendLog(ok ? ('已保存到相册：' + this.previewTitle) : '保存到相册失败');
    });
  }

  private releasePreviewPhoto(): void {
    const pm: image.PixelMap | null = this.previewPhoto;
    this.previewPhoto = null;
    if (pm !== null) {
      PreviewSource.releaseMap(pm);
    }
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
      const options: picker.DocumentSelectOptions = new picker.DocumentSelectOptions();
      options.maxSelectNumber = 20;
      const p: picker.DocumentViewPicker = new picker.DocumentViewPicker();
      const uris: string[] = await p.select(options);
      if (uris.length === 0) {
        return;
      }
      this.appendLog('正在导入 ' + uris.length + ' 个文件…');
      let ok: number = 0;
      for (let i = 0; i < uris.length; i++) {
        if (await this.copyToInbox(uris[i], this.nameFromUri(uris[i]))) {
          ok++;
        }
      }
      this.loadFiles();
      this.appendLog('已导入 ' + ok + ' 个文件');
    } catch (e) {
      Log.warn('document picker failed: ' + (e as Error).message);
    }
  }

  private async importPhotos(): Promise<void> {
    try {
      const po: picker.PhotoSelectOptions = new picker.PhotoSelectOptions();
      po.MIMEType = picker.PhotoViewMIMETypes.IMAGE_TYPE;
      po.maxSelectNumber = 20;
      const pv: picker.PhotoViewPicker = new picker.PhotoViewPicker();
      const res: picker.PhotoSelectResult = await pv.select(po);
      const uris: string[] = res.photoUris;
      if (uris.length === 0) {
        return;
      }
      this.appendLog('正在导入 ' + uris.length + ' 张图片…');
      let ok: number = 0;
      for (let i = 0; i < uris.length; i++) {
        let name: string = this.nameFromUri(uris[i]);
        // 相册 uri 的末段可能不带扩展名，补一个默认值，保证后续预览/保存能识别类型。
        if (name.lastIndexOf('.') < 0) {
          name = name + '.jpg';
        }
        if (await this.copyToInbox(uris[i], name)) {
          ok++;
        }
      }
      this.loadFiles();
      this.appendLog('已导入 ' + ok + ' 张图片');
    } catch (e) {
      Log.warn('photo picker failed: ' + (e as Error).message);
    }
  }

  private nameFromUri(uri: string): string {
    let name: string = uri;
    const slash: number = name.lastIndexOf('/');
    if (slash >= 0) {
      name = name.substring(slash + 1);
    }
    try {
      name = decodeURIComponent(name);
    } catch (e) {
    }
    return name;
  }

  private async copyToInbox(uri: string, name: string): Promise<boolean> {
    if (name.length === 0 || name.indexOf('/') >= 0 || name.indexOf('\\') >= 0 || name.indexOf('..') >= 0) {
      name = 'import_' + Date.now();
    }
    const dest: string = this.inbox + '/' + name;
    // PhotoViewPicker 返回的媒体库 fd 在循环 readSync 下不会前进，会反复读到开头 64KB；
    // 旧的同步 do/while 据此死循环写出 200MB+ 重复块并阻塞 UI 线程触发 ANR（卡死后被系统杀）。
    // 改用原生异步 copyFile：不依赖 fd 位置语义、不阻塞主线程，并用 statSync 校验真实大小。
    let srcSize: number = -1;
    try {
      srcSize = fs.statSync(uri).size;
    } catch (e) {
      srcSize = -1;
    }
    if (srcSize > MAX_IMPORT_BYTES) {
      this.appendLog('导入失败：' + name + '（超过 2GB 上限）');
      return false;
    }
    let src: fs.File | null = null;
    try {
      if (fs.accessSync(dest)) {
        fs.unlinkSync(dest);
      }
      src = fs.openSync(uri, fs.OpenMode.READ_ONLY);
      await fs.copyFile(src.fd, dest);
      const got: number = fs.statSync(dest).size;
      if (got <= 0 || got > MAX_IMPORT_BYTES || (srcSize > 0 && got !== srcSize)) {
        fs.unlinkSync(dest);
        this.appendLog('导入失败：' + name + '（大小异常 ' + got + '/' + srcSize + '）');
        return false;
      }
      return true;
    } catch (e) {
      try {
        if (fs.accessSync(dest)) {
          fs.unlinkSync(dest);
        }
      } catch (e2) {
      }
      Log.warn('import copy failed ' + name + ': ' + (e as Error).message);
      this.appendLog('导入失败：' + name);
      return false;
    } finally {
      if (src !== null) {
        try {
          fs.closeSync(src.fd);
        } catch (e) {
        }
      }
    }
  }

  @Builder
  PreviewOverlay() {
    Column() {
      Row() {
        Text(this.previewTitle)
          .fontSize(15)
          .fontColor('#E7EDF5')
          .layoutWeight(1)
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
        Button('关闭')
          .fontSize(13)
          .height(30)
          .backgroundColor('#243041')
          .onClick(() => {
            this.closePreview();
          })
      }
      .width('100%')
      .padding({ left: 18, right: 18, top: 44, bottom: 10 })

      if (this.previewKind === 'image') {
        Column() {
          if (this.previewPhoto !== null) {
            Image(this.previewPhoto)
              .objectFit(ImageFit.Contain)
              .width('100%')
              .height('100%')
          } else {
            Text('解码中…')
              .fontSize(14)
              .fontColor('#8FA0B5')
          }
        }
        .width('100%')
        .layoutWeight(1)
        .onClick(() => {
          this.closePreview();
        })

        if (AlbumSaver.isImage(this.previewTitle)) {
          Row() {
            SaveButton({
              icon: SaveIconStyle.LINES,
              text: SaveDescription.SAVE_IMAGE,
              buttonType: ButtonType.Capsule
            })
              .onClick((event: ClickEvent, result: SaveButtonOnClickResult) => {
                if (result === SaveButtonOnClickResult.SUCCESS) {
                  this.saveToAlbum();
                } else {
                  this.appendLog('保存授权失败，请重试');
                }
              })
          }
          .width('100%')
          .justifyContent(FlexAlign.Center)
          .padding({ top: 8, bottom: 20 })
        }
      } else {
        Scroll() {
          Column() {
            Text(this.previewText.length > 0 ? this.previewText : '（空文件）')
              .fontSize(12)
              .fontColor('#D5DEEC')
              .width('100%')
              .textAlign(TextAlign.Start)
          }
          .width('100%')
          .alignItems(HorizontalAlign.Start)
          .constraintSize({ minHeight: '100%' })
        }
        .width('100%')
        .layoutWeight(1)
        .padding({ left: 18, right: 18, bottom: 14 })
      }
    }
    .width('100%')
    .height('100%')
    .backgroundColor('#0B0E12')
    .alignItems(HorizontalAlign.Start)
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

      Row({ space: 6 }) {
        Text('收件箱')
          .fontSize(15)
          .fontWeight(FontWeight.Medium)
          .fontColor('#E7EDF5')
        Text(this.sizeText)
          .fontSize(11)
          .fontColor('#8FA0B5')
          .layoutWeight(1)
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
        Button('图片')
          .fontSize(12)
          .height(30)
          .backgroundColor('#243041')
          .onClick(() => {
            this.importPhotos();
          })
        Button('文件')
          .fontSize(12)
          .height(30)
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
          .onClick(() => {
            this.openPreview(name);
          })
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
    .bindContentCover($$this.showPreview, this.PreviewOverlay(), {
      onDisappear: () => {
        this.releasePreviewPhoto();
      }
    })
  }
}
