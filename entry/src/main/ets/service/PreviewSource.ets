import fs from '@ohos.file.fs';
import image from '@ohos.multimedia.image';
import util from '@ohos.util';
import { Log } from '../common/Logger';

const IMAGE_EXT: string[] = ['jpg', 'jpeg', 'png', 'webp', 'bmp', 'gif', 'heic', 'heif'];
const TEXT_EXT: string[] = [
  'txt', 'md', 'json', 'log', 'csv', 'xml', 'ini', 'yaml', 'yml',
  'js', 'ts', 'ets', 'py', 'sh', 'html', 'css'
];
const MAX_EDGE: number = 1280;
const MAX_TEXT_BYTES: number = 64 * 1024;

export class PreviewSource {
  static ext(name: string): string {
    const dot: number = name.lastIndexOf('.');
    if (dot < 0) {
      return '';
    }
    return name.substring(dot + 1).toLowerCase();
  }

  // 'image' / 'text' / ''（不支持预览）
  static kind(name: string): string {
    const e: string = PreviewSource.ext(name);
    if (IMAGE_EXT.indexOf(e) >= 0) {
      return 'image';
    }
    if (TEXT_EXT.indexOf(e) >= 0) {
      return 'text';
    }
    return '';
  }

  static async decodeImage(path: string): Promise<image.PixelMap | null> {
    let file: fs.File | null = null;
    let source: image.ImageSource | null = null;
    try {
      file = fs.openSync(path, fs.OpenMode.READ_ONLY);
      source = image.createImageSource(file.fd);
      const size: image.Size = { width: MAX_EDGE, height: MAX_EDGE };
      const opts: image.DecodingOptions = { editable: false, desiredSize: size };
      const pm: image.PixelMap = await source.createPixelMap(opts);
      return pm;
    } catch (e) {
      Log.warn('preview decode failed ' + path + ': ' + (e as Error).message);
      return null;
    } finally {
      if (source !== null) {
        await source.release();
      }
      if (file !== null) {
        fs.closeSync(file);
      }
    }
  }

  static readText(path: string): string {
    let file: fs.File | null = null;
    try {
      const st: fs.Stat = fs.statSync(path);
      if (st.size <= 0) {
        return '';
      }
      const want: number = st.size > MAX_TEXT_BYTES ? MAX_TEXT_BYTES : st.size;
      const buf: ArrayBuffer = new ArrayBuffer(want);
      file = fs.openSync(path, fs.OpenMode.READ_ONLY);
      const read: number = fs.readSync(file.fd, buf, { offset: 0, length: want });
      if (read <= 0) {
        return '';
      }
      const decoder: util.TextDecoder = new util.TextDecoder('utf-8');
      let text: string = decoder.decode(new Uint8Array(buf.slice(0, read)));
      if (st.size > MAX_TEXT_BYTES) {
        text += '\n\n…（仅预览前 64 KB，完整文件请在电脑端下载）';
      }
      return text;
    } catch (e) {
      Log.warn('preview read failed ' + path + ': ' + (e as Error).message);
      return '（无法读取该文件：' + (e as Error).message + '）';
    } finally {
      if (file !== null) {
        fs.closeSync(file);
      }
    }
  }

  static releaseMap(pm: image.PixelMap | null): void {
    if (pm === null) {
      return;
    }
    pm.release().catch((e: Error) => {
      Log.warn('pixelmap release failed: ' + e.message);
    });
  }
}
