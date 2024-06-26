import { Resource } from 'ember-resources/core';
import { service } from '@ember/service';
import { tracked } from '@glimmer/tracking';
import { restartableTask, Task, TaskInstance } from 'ember-concurrency';
import { registerDestructor } from '@ember/destroyable';
import { logger } from '@cardstack/runtime-common';
import LoaderService from '../services/loader-service';
import type MessageService from '../services/message-service';

const log = logger('resource:file');

interface Args {
  named: {
    relativePath: string;
    realmURL: string;
    content: string | undefined;
    lastModified: string | undefined;
    onStateChange?: (state: FileResource['state']) => void;
  };
}

export type FileResource =
  | {
      state: 'server-error';
      url: string;
      loading: TaskInstance<void> | null;
    }
  | {
      state: 'not-found';
      url: string;
      loading: TaskInstance<void> | null;
    }
  | {
      state: 'ready';
      content: string;
      name: string;
      url: string;
      loading: TaskInstance<void> | null;
      lastModified: string;
      writeTask: Task<void, [content: string, flushLoader?: boolean]>;
      close(): void;
    };

class _FileResource extends Resource<Args> {
  private declare _url: string;
  private onStateChange?: ((state: FileResource['state']) => void) | undefined;
  private subscription: { url: string; unsubscribe: () => void } | undefined;
  @tracked content: string | undefined;
  @tracked state: FileResource['state'] = 'ready';
  @tracked lastModified: string | undefined;
  @service declare loaderService: LoaderService;
  @service declare messageService: MessageService;

  constructor(owner: unknown) {
    super(owner);
    registerDestructor(this, () => {
      if (this.subscription) {
        this.subscription.unsubscribe();
        this.subscription = undefined;
      }
    });
  }

  modify(_positional: never[], named: Args['named']) {
    let { relativePath, realmURL, content, lastModified, onStateChange } =
      named;
    this._url = realmURL + relativePath;
    this.onStateChange = onStateChange;
    if (content !== undefined) {
      this.content = content;
      this.lastModified = lastModified;
    } else {
      // get the initial content if we haven't already been seeded with initial content
      this.read.perform();
    }

    let path = `${realmURL}_message`;

    if (this.subscription && this.subscription.url !== path) {
      this.subscription.unsubscribe();
      this.subscription = undefined;
    }

    if (!this.subscription) {
      this.subscription = {
        url: path,
        unsubscribe: this.messageService.subscribe(path, () =>
          this.read.perform()
        ),
      };
    }
  }

  get url() {
    return this._url;
  }

  get name() {
    return this._url.split('/').pop()!;
  }

  get loading() {
    return this.read.last;
  }

  private read = restartableTask(async () => {
    let prevState = this.state;
    let response = await this.loaderService.loader.fetch(this.url, {
      headers: {
        Accept: 'application/vnd.card+source',
      },
    });
    if (!response.ok) {
      log.error(
        `Could not get file ${this.url}, status ${response.status}: ${
          response.statusText
        } - ${await response.text()}`
      );
      if (response.status === 404) {
        this.state = 'not-found';
      } else {
        this.state = 'server-error';
      }
      if (this.onStateChange && this.state !== prevState) {
        this.onStateChange(this.state);
      }
      return;
    }
    let lastModified = response.headers.get('last-modified') || undefined;
    if (this.lastModified === lastModified) {
      return;
    }
    this.lastModified = lastModified;
    this.content = await response.text();
    this.state = 'ready';
    if (this.onStateChange && this.state !== prevState) {
      this.onStateChange(this.state);
    }
  });

  writeTask = restartableTask(async (content: string, flushLoader?: true) => {
    let response = await this.loaderService.loader.fetch(this.url, {
      method: 'POST',
      headers: {
        Accept: 'application/vnd.card+source',
      },
      body: content,
    });
    if (!response.ok) {
      let errorMessage = `Could not write file ${this.url}, status ${
        response.status
      }: ${response.statusText} - ${await response.text()}`;
      log.error(errorMessage);
      throw new Error(errorMessage);
    }
    if (this.state === 'not-found') {
      // TODO think about the "unauthorized" scenario
      throw new Error(
        'this should be impossible--we are creating the specified path'
      );
    }

    this.content = content;
    this.lastModified = response.headers.get('last-modified') || undefined;
    if (flushLoader) {
      this.loaderService.reset();
    }
  });
}

export function file(parent: object, args: () => Args['named']): FileResource {
  return _FileResource.from(parent, () => ({
    named: args(),
  })) as unknown as FileResource;
}
