// @ts-ignore
import { precompileTemplate } from '@ember/template-compilation';
import { render, getContext } from '@ember/test-helpers';

import { ComponentLike } from '@glint/template';

import { baseRealm, Loader } from '@cardstack/runtime-common';

import type {
  BaseDef,
  Format,
  Field,
} from 'https://cardstack.com/base/card-api';

async function cardApi(
  loader: Loader,
): Promise<typeof import('https://cardstack.com/base/card-api')> {
  return await loader.import(`${baseRealm.url}card-api`);
}

export async function renderComponent(C: ComponentLike) {
  await render(
    precompileTemplate(`<C/>`, { strictMode: true, scope: () => ({ C }) }),
  );
}

export async function renderCard(
  loader: Loader,
  card: BaseDef,
  format: Format,
  field?: Field,
) {
  let api = await cardApi(loader);
  await api.recompute(card, { recomputeAllFields: true });
  await renderComponent(api.getComponent(card, format, field));
  return (getContext() as { element: Element }).element;
}
