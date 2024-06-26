import { module, test, skip } from 'qunit';
import GlimmerComponent from '@glimmer/component';
import { setupRenderingTest } from 'ember-qunit';
import { baseRealm } from '@cardstack/runtime-common';
import { Realm } from '@cardstack/runtime-common/realm';
import { Loader } from '@cardstack/runtime-common/loader';
import CardEditor from '@cardstack/host/components/card-editor';
import { renderComponent } from '../../helpers/render-component';
import CardCatalogModal from '@cardstack/host/components/card-catalog-modal';
import {
  testRealmURL,
  shimModule,
  setupCardLogs,
  setupLocalIndexing,
  TestRealmAdapter,
  TestRealm,
  saveCard,
} from '../../helpers';
import { waitFor, fillIn, click } from '@ember/test-helpers';
import type LoaderService from '@cardstack/host/services/loader-service';
import { Card } from 'https://cardstack.com/base/card-api';
import CreateCardModal from '@cardstack/host/components/create-card-modal';
import CardPrerender from '@cardstack/host/components/card-prerender';
import { shimExternals } from '@cardstack/host/lib/externals';

let cardApi: typeof import('https://cardstack.com/base/card-api');
let string: typeof import('https://cardstack.com/base/string');
let updateFromSerialized: (typeof cardApi)['updateFromSerialized'];

module('Integration | card-editor', function (hooks) {
  let loader: Loader;
  let adapter: TestRealmAdapter;
  let realm: Realm;
  setupRenderingTest(hooks);
  setupLocalIndexing(hooks);
  setupCardLogs(
    hooks,
    async () => await Loader.import(`${baseRealm.url}card-api`)
  );

  async function loadCard(url: string): Promise<Card> {
    let { createFromSerialized, recompute } = cardApi;
    let result = await realm.searchIndex.card(new URL(url));
    if (!result || result.type === 'error') {
      throw new Error(
        `cannot get instance ${url} from the index: ${
          result ? result.error.detail : 'not found'
        }`
      );
    }
    let card = await createFromSerialized<typeof Card>(
      result.doc.data,
      result.doc,
      new URL(result.doc.data.id),
      {
        loader: Loader.getLoaderFor(createFromSerialized),
      }
    );
    await recompute(card, { loadFields: true });
    return card;
  }

  hooks.beforeEach(async function () {
    Loader.addURLMapping(
      new URL(baseRealm.url),
      new URL('http://localhost:4201/base/')
    );
    shimExternals();
    let loader = (this.owner.lookup('service:loader-service') as LoaderService)
      .loader;
    cardApi = await loader.import(`${baseRealm.url}card-api`);
    string = await loader.import(`${baseRealm.url}string`);
    updateFromSerialized = cardApi.updateFromSerialized;

    adapter = new TestRealmAdapter({
      'pet.gts': `
        import { contains, field, Component, Card } from "https://cardstack.com/base/card-api";
        import StringCard from "https://cardstack.com/base/string";

        export class Pet extends Card {
          @field name = contains(StringCard);
          static embedded = class Embedded extends Component<typeof this> {
            <template>
              <h3 data-test-pet={{@model.name}}>
                <@fields.name/>
              </h3>
            </template>
          }
        }
      `,
      'fancy-pet.gts': `
        import { contains, field, Component, Card } from "https://cardstack.com/base/card-api";
        import StringCard from "https://cardstack.com/base/string";
        import { Pet } from "./pet";

        export class FancyPet extends Pet {
          @field favoriteToy = contains(StringCard);
          static embedded = class Embedded extends Component<typeof this> {
            <template>
              <h3 data-test-pet={{@model.name}}>
                <@fields.name/>
                (plays with <@fields.favoriteToy/>)
              </h3>
            </template>
          }
        }
      `,
      'person.gts': `
        import { contains, linksTo, field, Component, Card } from "https://cardstack.com/base/card-api";
        import StringCard from "https://cardstack.com/base/string";
        import { Pet } from "./pet";

        export class Person extends Card {
          @field firstName = contains(StringCard);
          @field pet = linksTo(Pet);
          static isolated = class Embedded extends Component<typeof this> {
            <template>
              <h2 data-test-person={{@model.firstName}}>
                <@fields.firstName/>
              </h2>
              Pet: <@fields.pet/>
            </template>
          }
        }
      `,
      'Pet/mango.json': {
        data: {
          type: 'card',
          id: `${testRealmURL}Pet/mango`,
          attributes: {
            name: 'Mango',
          },
          meta: {
            adoptsFrom: {
              module: `${testRealmURL}pet`,
              name: 'Pet',
            },
          },
        },
      },
      'Pet/vangogh.json': {
        data: {
          type: 'card',
          id: `${testRealmURL}Pet/vangogh`,
          attributes: {
            name: 'Van Gogh',
          },
          meta: {
            adoptsFrom: {
              module: `${testRealmURL}pet`,
              name: 'Pet',
            },
          },
        },
      },
      'Pet/ringo.json': {
        data: {
          type: 'card',
          id: `${testRealmURL}Pet/ringo`,
          attributes: {
            name: 'Ringo',
            favoriteToy: 'sneaky snake',
          },
          meta: {
            adoptsFrom: {
              module: `${testRealmURL}fancy-pet`,
              name: 'FancyPet',
            },
          },
        },
      },
      'Person/hassan.json': {
        data: {
          type: 'card',
          id: `${testRealmURL}Person/hassan`,
          attributes: {
            firstName: 'Hassan',
          },
          relationships: {
            pet: {
              links: {
                self: `${testRealmURL}Pet/mango`,
              },
            },
          },
          meta: {
            adoptsFrom: {
              module: `${testRealmURL}person`,
              name: 'Person',
            },
          },
        },
      },
      'Person/mariko.json': {
        data: {
          type: 'card',
          id: `${testRealmURL}Person/mariko`,
          attributes: {
            firstName: 'Mariko',
          },
          relationships: {
            pet: {
              links: {
                self: null,
              },
            },
          },
          meta: {
            adoptsFrom: {
              module: `${testRealmURL}person`,
              name: 'Person',
            },
          },
        },
      },
    });
    realm = await TestRealm.createWithAdapter(adapter, this.owner);
    loader.registerURLHandler(new URL(realm.url), realm.handle.bind(realm));
    await realm.ready;
  });

  test('renders card in edit (default) format', async function (assert) {
    let { field, contains, Card, Component } = cardApi;
    let { default: StringCard } = string;
    class TestCard extends Card {
      @field firstName = contains(StringCard);
      @field nickName = contains(StringCard, {
        computeVia: function (this: TestCard) {
          return `${this.firstName}-poo`;
        },
      });
      @field lastName = contains(StringCard);
      static isolated = class Isolated extends Component<typeof this> {
        <template>
          <div data-test-firstName><@fields.firstName /></div>
          <div data-test-nickName><@fields.nickName /></div>
          <div data-test-lastName><@fields.lastName /></div>
        </template>
      };
    }
    await shimModule(`${testRealmURL}test-cards`, { TestCard }, loader);
    let card = new TestCard({ firstName: 'Mango', lastName: 'Abdel-Rahman' });
    await saveCard(
      card,
      `${testRealmURL}test-cards/test-card`,
      Loader.getLoaderFor(updateFromSerialized)
    );

    await renderComponent(
      class TestDriver extends GlimmerComponent {
        <template>
          <CardEditor @card={{card}} />
          <CardPrerender />
        </template>
      }
    );

    await waitFor('[data-test-field="firstName"]'); // we need to wait for the card instance to load
    assert.dom('[data-test-field="firstName"] input').hasValue('Mango');
    assert.dom('[data-test-field="nickName"]').containsText('Mango-poo');
    assert
      .dom('[data-test-field="nickName"] input')
      .doesNotExist('computeds do not have an input field');
    assert.dom('[data-test-field="lastName"] input').hasValue('Abdel-Rahman');
  });

  test('can change card format', async function (assert) {
    let { field, contains, Card, Component } = cardApi;
    let { default: StringCard } = string;
    class TestCard extends Card {
      @field firstName = contains(StringCard);
      static isolated = class Isolated extends Component<typeof this> {
        <template>
          <div data-test-isolated-firstName><@fields.firstName /></div>
        </template>
      };
      static embedded = class Embedded extends Component<typeof this> {
        <template>
          <div data-test-embedded-firstName><@fields.firstName /></div>
        </template>
      };
      static edit = class Edit extends Component<typeof this> {
        <template>
          <div data-test-edit-firstName><@fields.firstName /></div>
        </template>
      };
    }
    await shimModule(`${testRealmURL}test-cards`, { TestCard }, loader);

    let card = new TestCard({ firstName: 'Mango' });
    await saveCard(
      card,
      `${testRealmURL}test-cards/test-card`,
      Loader.getLoaderFor(updateFromSerialized)
    );

    await renderComponent(
      class TestDriver extends GlimmerComponent {
        <template>
          <CardEditor @card={{card}} @format='isolated' />
          <CardPrerender />
        </template>
      }
    );
    await waitFor('[data-test-isolated-firstName]'); // we need to wait for the card instance to load
    assert.dom('[data-test-isolated-firstName]').hasText('Mango');
    assert.dom('[data-test-embedded-firstName]').doesNotExist();
    assert.dom('[data-test-edit-firstName]').doesNotExist();

    await click('.format-button.embedded');
    assert.dom('[data-test-isolated-firstName]').doesNotExist();
    assert.dom('[data-test-embedded-firstName]').hasText('Mango');
    assert.dom('[data-test-edit-firstName]').doesNotExist();

    await click('.format-button.edit');
    assert.dom('[data-test-isolated-firstName]').doesNotExist();
    assert.dom('[data-test-embedded-firstName]').doesNotExist();
    assert.dom('[data-test-edit-firstName] input').hasValue('Mango');
  });

  test('edited card data is visible in different formats', async function (assert) {
    let { field, contains, Card, Component } = cardApi;
    let { default: StringCard } = string;
    class TestCard extends Card {
      @field firstName = contains(StringCard);
      static isolated = class Isolated extends Component<typeof this> {
        <template>
          <div data-test-isolated-firstName><@fields.firstName /></div>
        </template>
      };
      static embedded = class Embedded extends Component<typeof this> {
        <template>
          <div data-test-embedded-firstName><@fields.firstName /></div>
        </template>
      };
      static edit = class Edit extends Component<typeof this> {
        <template>
          <div data-test-edit-firstName><@fields.firstName /></div>
        </template>
      };
    }
    await shimModule(`${testRealmURL}test-cards`, { TestCard }, loader);
    let card = new TestCard({ firstName: 'Mango' });
    await saveCard(
      card,
      `${testRealmURL}test-cards/test-card`,
      Loader.getLoaderFor(updateFromSerialized)
    );
    await renderComponent(
      class TestDriver extends GlimmerComponent {
        <template>
          <CardEditor @card={{card}} />
          <CardPrerender />
        </template>
      }
    );

    await waitFor('[data-test-edit-firstName] input'); // we need to wait for the card instance to load
    await fillIn('[data-test-edit-firstName] input', 'Van Gogh');

    await click('.format-button.embedded');
    assert.dom('[data-test-embedded-firstName]').hasText('Van Gogh');

    await click('.format-button.isolated');
    assert.dom('[data-test-isolated-firstName]').hasText('Van Gogh');
  });

  test('can choose a card for a linksTo field that has an existing value', async function (assert) {
    let card = await loadCard(`${testRealmURL}Person/hassan`);
    await renderComponent(
      class TestDriver extends GlimmerComponent {
        <template>
          <CardEditor @card={{card}} />
          <CardCatalogModal />
          <CardPrerender />
        </template>
      }
    );

    assert.dom('[data-test-pet="Mango"]').containsText('Mango');

    await click('[data-test-remove-card]');
    await click('[data-test-choose-card]');
    await waitFor(
      '[data-test-card-catalog-modal] [data-test-card-catalog-item]'
    );

    assert
      .dom('[data-test-card-catalog-modal] [data-test-card-catalog-item]')
      .exists({ count: 3 });
    assert.dom(`[data-test-select="${testRealmURL}Pet/vangogh"]`).exists();
    assert.dom(`[data-test-select="${testRealmURL}Pet/ringo"]`).exists();
    assert
      .dom(`[data-test-card-catalog-item="${testRealmURL}Pet/mango"`)
      .exists();
    await click(`[data-test-select="${testRealmURL}Pet/vangogh"]`);
    await click('[data-test-card-catalog-go-button]');

    assert
      .dom('[data-test-card-catalog-modal]')
      .doesNotExist('card catalog modal dismissed');
    assert.dom('[data-test-pet="Van Gogh"]').containsText('Van Gogh');
  });

  test('can choose a card for a linksTo field that has no existing value', async function (assert) {
    let card = await loadCard(`${testRealmURL}Person/mariko`);
    await renderComponent(
      class TestDriver extends GlimmerComponent {
        <template>
          <CardEditor @card={{card}} />
          <CardCatalogModal />
          <CardPrerender />
        </template>
      }
    );

    assert.dom('[data-test-choose-card]').exists();
    assert.dom('button[data-test-remove-card]').doesNotExist();

    await click('[data-test-choose-card]');
    await waitFor(
      '[data-test-card-catalog-modal] [data-test-card-catalog-item]'
    );
    await click(`[data-test-select="${testRealmURL}Pet/vangogh"]`);
    await click('[data-test-card-catalog-go-button]');

    assert
      .dom('[data-test-card-catalog-modal]')
      .doesNotExist('card catalog modal dismissed');
    assert.dom('[data-test-pet="Van Gogh"]').containsText('Van Gogh');
    assert
      .dom('button[data-test-remove-card]')
      .hasProperty('disabled', false, 'remove button is enabled');
  });

  test('can remove the link for a linksTo field', async function (assert) {
    let card = await loadCard(`${testRealmURL}Person/hassan`);
    await renderComponent(
      class TestDriver extends GlimmerComponent {
        <template>
          <CardEditor @card={{card}} />
          <CardCatalogModal />
          <CardPrerender />
        </template>
      }
    );

    assert.dom('[data-test-pet="Mango"]').containsText('Mango');
    assert.dom('[data-test-choose-card]').doesNotExist();

    await click('[data-test-remove-card]');

    assert.dom('[data-test-pet="Mango"]').doesNotExist();
    assert.dom('button[data-test-remove-card]').doesNotExist();
    assert.dom('[data-test-choose-card]').exists();
  });

  test('can create a new card to populate a linksTo field', async function (assert) {
    let card = await loadCard(`${testRealmURL}Person/mariko`);
    await renderComponent(
      class TestDriver extends GlimmerComponent {
        <template>
          <CardEditor @card={{card}} />
          <CardCatalogModal />
          <CreateCardModal />
          <CardPrerender />
        </template>
      }
    );

    await click('[data-test-choose-card]');
    await waitFor('[data-test-create-new]');
    await click('[data-test-create-new]');
    await waitFor('[data-test-create-new-card="Pet"]');

    assert.dom('[data-test-field="name"] input').exists();
    await fillIn('[data-test-field="name"] input', 'Simba');
    assert.dom('[data-test-field="name"] input').hasValue('Simba');

    await click('[data-test-create-new-card="Pet"] [data-test-save-card]');
    await waitFor('[data-test-pet="Simba"]');
    assert.dom('[data-test-create-new-card="Pet"]').doesNotExist();
    assert.dom('[data-test-remove-card]').exists();

    await click('[data-test-save-card]');

    await waitFor('[data-test-person="Mariko"]');
    assert.dom('[data-test-person="Mariko"]').hasText('Mariko');
    assert.dom('[data-test-pet="Simba"]').hasText('Simba');
  });

  skip('can create a specialized a new card to populate a linksTo field');
});
