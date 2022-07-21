import { RealmAdapter, Kind, FileRef } from "@cardstack/runtime-common";
import {
  readdirSync,
  existsSync,
  writeFileSync,
  statSync,
  ensureDirSync,
  ensureFileSync,
  readFileSync,
} from "fs-extra";
import { join } from "path";

export class NodeRealm implements RealmAdapter {
  constructor(private realmDir: string) {}

  async *readdir(
    path: string,
    opts?: { create?: true }
  ): AsyncGenerator<{ name: string; path: string; kind: Kind }, void> {
    if (opts?.create) {
      ensureDirSync(path);
    }
    let absolutePath = join(this.realmDir, path);
    let entries = readdirSync(absolutePath, { withFileTypes: true });
    for await (let entry of entries) {
      let isDirectory = entry.isDirectory();
      let isFile = entry.isFile();
      if (!isDirectory && !isFile) {
        continue;
      }
      let { name } = entry;
      yield {
        name,
        path: join(path, name),
        kind: isDirectory ? "directory" : "file",
      };
    }
  }

  async openFile(path: string): Promise<FileRef | undefined> {
    let absolutePath = join(this.realmDir, path);
    if (!existsSync(absolutePath)) {
      return undefined;
    }
    let { mtime } = statSync(absolutePath);
    // holding off on streaming this--the webstream that our realm uses is not
    // the same as the read stream that is used by Koa's response body (as well
    // as the fs.createStream used by node). At some point we need to get this
    // all sorted out
    let content = readFileSync(absolutePath);
    return {
      path,
      content,
      lastModified: mtime.getTime(),
    };
  }

  async write(
    path: string,
    contents: string
  ): Promise<{ lastModified: number }> {
    let absolutePath = join(this.realmDir, path);
    ensureFileSync(absolutePath);
    writeFileSync(absolutePath, contents);
    let { mtime } = statSync(absolutePath);
    return { lastModified: mtime.getTime() };
  }
}
