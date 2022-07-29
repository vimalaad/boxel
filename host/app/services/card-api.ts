import Service from '@ember/service';
import { task, timeout } from 'ember-concurrency';
import { taskFor } from 'ember-concurrency-ts';
import { baseRealm } from '@cardstack/runtime-common';
import config from 'runtime-spike/config/environment';
export type { RenderedCard } from 'https://cardstack.com/base/render-card';

export type API = typeof import('https://cardstack.com/base/card-api');
type RenderCardResource =
  typeof import('https://cardstack.com/base/render-card');

export default class CardAPI extends Service {
  #api: API | undefined;
  #renderCard: RenderCardResource | undefined;

  constructor(properties: object) {
    super(properties);
    taskFor(this.load).perform();
  }

  get api() {
    if (!this.#api) {
      throw new Error(
        `bug: card API has not loaded yet--make sure to await this.loaded before using the api`
      );
    }
    return this.#api;
  }

  get render() {
    if (!this.#renderCard) {
      throw new Error(
        `bug: card API has not loaded yet--make sure to await this.loaded before using the api`
      );
    }
    return this.#renderCard.render;
  }

  get loaded(): Promise<void> {
    // TODO probably there is a more elegant way to express this in EC
    return new Promise(async (res) => {
      while (taskFor(this.load).isRunning) {
        await timeout(10);
      }
      res();
    });
  }

  @task private async load(): Promise<void> {
    if (config.environment === 'test') {
      this.#api = await import(
        /* webpackIgnore: true */ 'http://localhost:4201/base/card-api' + ''
      );
      this.#renderCard = await import(
        /* webpackIgnore: true */ 'http://localhost:4201/base/render-card' + ''
      );
    } else {
      this.#api = await import(
        /* webpackIgnore: true */ `${baseRealm.url}card-api`
      );
      this.#renderCard = await import(
        /* webpackIgnore: true */ `${baseRealm.url}render-card`
      );
    }
  }
}
