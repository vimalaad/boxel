import Service, { service } from '@ember/service';

import { buildWaiter } from '@ember/test-waiters';

import { cached } from '@glimmer/tracking';

import { restartableTask } from 'ember-concurrency';
import { TrackedMap } from 'tracked-built-ins';

import { RealmInfo, RealmPaths } from '@cardstack/runtime-common';

import ENV from '@cardstack/host/config/environment';

import type CardService from '@cardstack/host/services/card-service';
import type LoaderService from '@cardstack/host/services/loader-service';

import RealmService from './realm';

const waiter = buildWaiter('realm-info-service:waiter');
const { ownRealmURL } = ENV;

type RealmInfoWithPermissions = RealmInfo & {
  canRead: boolean;
  canWrite: boolean;
};

export default class RealmInfoService extends Service {
  @service declare loaderService: LoaderService;
  @service declare cardService: CardService;
  @service declare realm: RealmService;

  cachedRealmURLsForURL: Map<string, string> = new Map(); // Has the file url already been resolved to a realm url?
  cachedRealmInfos: TrackedMap<string, RealmInfoWithPermissions> =
    new TrackedMap(); // Has the realm url already been resolved to a realm info?
  cachedPublicReadableRealms: Map<string, boolean> = new Map();
  cachedFetchTasks: Map<string, Promise<Response>> = new Map();

  async fetchRealmURL(url: string): Promise<URL | undefined> {
    let realmURLString = this.getRealmURLFromCache(url);
    if (!realmURLString) {
      let response = await this.loaderService.loader.fetch(url, {
        method: 'HEAD',
      });
      realmURLString = response.headers.get('x-boxel-realm-url') ?? undefined;
    }
    let realmURL;
    if (realmURLString) {
      this.cachedRealmURLsForURL.set(url, realmURLString);
      realmURL = new URL(realmURLString);
    }

    return realmURL;
  }

  private getRealmURLFromCache(url: string) {
    let realmURLString = this.cachedRealmURLsForURL.get(url);
    if (!realmURLString) {
      realmURLString = Array.from(this.cachedRealmURLsForURL.values()).find(
        (realmURL) => url.includes(realmURL),
      );
    }
    return realmURLString;
  }

  async isPublicReadable(realmURL: URL): Promise<boolean> {
    let realmURLString = realmURL.href;
    if (this.cachedPublicReadableRealms.has(realmURLString)) {
      return this.cachedPublicReadableRealms.get(realmURLString)!;
    }
    let response = await this.loaderService.loader.fetch(realmURL, {
      method: 'HEAD',
    });
    let isPublicReadable = Boolean(
      response.headers.get('x-boxel-realm-public-readable'),
    );
    this.cachedPublicReadableRealms.set(realmURLString, isPublicReadable);

    return isPublicReadable;
  }

  // When realmUrl is provided, it will fetch realm info from that url, otherwise it will first
  // try to fetch the realm url from the file url
  async fetchRealmInfo(params: {
    realmURL?: URL;
    fileURL?: string;
  }): Promise<RealmInfoWithPermissions> {
    let { realmURL, fileURL } = params;
    let url = realmURL?.href ?? fileURL;
    if (!url) {
      throw new Error("Must provide either 'realmUrl' or 'fileUrl'");
    }
    let info: RealmInfo | undefined;

    try {
      info = this.realm.info(url);
    } catch (err: any) {
      if (err.code !== 'RealmNotReady') {
        throw err;
      }
      await this.loaderService.loader.fetch(url, { method: 'HEAD' });
      info = this.realm.info(url);
    }
    return {
      ...info,
      canRead: this.realm.canRead(url),
      canWrite: this.realm.canWrite(url),
    };
  }

  fetchAllKnownRealmInfos = restartableTask(async () => {
    let paths = this.cardService.realmURLs.map(
      (path) => new RealmPaths(new URL(path)).url,
    );
    let token = waiter.beginAsync();
    try {
      await Promise.all(
        paths.map(
          async (path) =>
            await this.fetchRealmInfo({ realmURL: new URL(path) }),
        ),
      );
    } finally {
      waiter.endAsync(token);
    }
  });

  // Currently the personal realm has not yet been implemented,
  // until then default to the realm serving the host app if it is writable,
  // otherwise default to the first writable realm lexically
  @cached
  get userDefaultRealm(): { path: string; info: RealmInfo } {
    let infos = this.cardService.realmURLs.map((realmURL) => {
      return {
        canWrite: this.realm.canWrite(realmURL),
        info: this.realm.info(realmURL),
      };
    });

    let writeableRealms = infos
      .filter((i) => i.canWrite)
      .sort((i, j) => i.info.name.localeCompare(j.info.name));

    let ownRealm = writeableRealms.find((i) => i.info.url === ownRealmURL);
    if (ownRealm) {
      return { path: ownRealm.info.url, info: ownRealm.info };
    } else {
      let first = writeableRealms[0];
      return { path: first.info.url, info: first.info };
    }
  }
}
