import fs from '@ohos.file.fs';
import common from '@ohos.app.ability.common';
import photoAccessHelper from '@ohos.file.photoAccessHelper';
import { Log } from '../common/Logger';

const IMAGE_EXT: string[] = ['jpg', 'jpeg', 'png', 'webp', 'bmp', 'gif', 'heic', 'heif'];
const BUFFER: number = 64 * 1024;

export class AlbumSaver {
  static isImage(name: string): boolean {
    const dot: number = name.lastIndexOf('.');
    if (dot < 0) {
      return false;
    }
    return IMAGE_EXT.indexOf(name.substring(dot + 1).toLowerCase()) >= 0;
  }

  // 需要配合 SaveButton 安全组件：点击 SUCCESS 后获得临时写权限，再调用本方法。
  static async saveImage(ctx: common.Context, filePath: string, name: string): Promise<boolean> {
    const dot: number = name.lastIndexOf('.');
    const ext: string = dot >= 0 ? name.substring(dot + 1).toLowerCase() : 'jpg';
    let helper: photoAccessHelper.PhotoAccessHelper | null = null;
    let src: fs.File | null = null;
    let dst: fs.File | null = null;
    let uri: string = '';
    try {
      helper = photoAccessHelper.getPhotoAccessHelper(ctx);
      const options: photoAccessHelper.CreateOptions = { title: name.length > 0 ? name : ('transfer_' + Date.now()) };
      uri = await helper.createAsset(photoAccessHelper.PhotoType.IMAGE, ext, options);
      src = fs.openSync(filePath, fs.OpenMode.READ_ONLY);
      dst = fs.openSync(uri, fs.OpenMode.WRITE_ONLY | fs.OpenMode.CREATE);
      const buf: ArrayBuffer = new ArrayBuffer(BUFFER);
      let read: number = 0;
      do {
        read = fs.readSync(src.fd, buf, { offset: 0, length: buf.byteLength });
        if (read > 0) {
          fs.writeSync(dst.fd, buf.slice(0, read));
        }
      } while (read > 0);
      return true;
    } catch (e) {
      Log.warn('save to album failed: ' + (e as Error).message);
      return false;
    } finally {
      if (dst !== null) {
        try {
          fs.closeSync(dst.fd);
        } catch (e) {
        }
      }
      if (src !== null) {
        try {
          fs.closeSync(src.fd);
        } catch (e) {
        }
      }
    }
  }
}