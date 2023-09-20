import Component from '@glimmer/component';
import { service } from '@ember/service';
import { type CardDef } from 'https://cardstack.com/base/card-api';
import { type RealmInfo } from '@cardstack/runtime-common';
import {
  InstanceDefinitionContainer,
  ModuleDefinitionContainer,
  ClickableModuleDefinitionContainer,
} from './definition-container';
import { Ready } from '@cardstack/host/resources/file';
import { tracked } from '@glimmer/tracking';
import moment from 'moment';
import { type AdoptionChainResource } from '@cardstack/host/resources/adoption-chain';
import { hash, array } from '@ember/helper';
import type OperatorModeStateService from '../../services/operator-mode-state-service';
import { action } from '@ember/object';

interface Args {
  Element: HTMLElement;
  Args: {
    realmInfo: RealmInfo | null;
    realmIconURL: string | null | undefined;
    readyFile: Ready;
    cardInstance: CardDef | undefined;
    adoptionChain?: AdoptionChainResource;
    delete: () => void;
  };
}

export default class CardInheritancePanel extends Component<Args> {
  @tracked cardInstance: CardDef | undefined;
  @service declare operatorModeStateService: OperatorModeStateService;

  @action
  updateCodePath(url: URL | undefined) {
    if (url) {
      this.operatorModeStateService.updateCodePath(url);
    }
  }

  get adoptionChainTypes() {
    return this.args.adoptionChain?.types;
  }

  <template>
    <div class='container' ...attributes>

      {{#if @cardInstance}}
        {{! JSON case when visting, eg Author/1.json }}
        {{#each this.adoptionChainTypes as |t|}}
          <InstanceDefinitionContainer
            @name={{@cardInstance.title}}
            @fileExtension='.JSON'
            @realmInfo={{@realmInfo}}
            @realmIconURL={{@realmIconURL}}
            @infoText={{this.lastModified}}
            @actions={{array
              (hash label='Delete' handler=@delete icon='icon-trash')
            }}
          />
          <div>Adopts from</div>

          <ClickableModuleDefinitionContainer
            @name={{t.displayName}}
            @fileExtension={{this.fileExtension}}
            @realmInfo={{@realmInfo}}
            @realmIconURL={{@realmIconURL}}
            @onSelectDefinition={{this.updateCodePath}}
            @url={{t.module}}
          />
        {{/each}}
      {{else}}
        {{! Module case when visting, eg author.gts }}
        {{#each this.adoptionChainTypes as |t|}}
          <ModuleDefinitionContainer
            @name={{t.displayName}}
            @fileExtension={{this.fileExtension}}
            @realmInfo={{@realmInfo}}
            @realmIconURL={{@realmIconURL}}
            @infoText={{this.lastModified}}
            @isActive={{true}}
            @actions={{array
              (hash label='Delete' handler=@delete icon='icon-trash')
            }}
          />
          <div>Inherits from</div>
          <ClickableModuleDefinitionContainer
            @name={{t.super.displayName}}
            @fileExtension={{this.fileExtension}}
            @realmInfo={{@realmInfo}}
            @realmIconURL={{@realmIconURL}}
            @onSelectDefinition={{this.updateCodePath}}
            @url={{t.super.module}}
          />
        {{/each}}
      {{/if}}
    </div>
    <style>
      .container {
        display: flex;
        flex-direction: column;
        gap: var(--boxel-sp-xs);
      }
    </style>
  </template>

  get lastModified() {
    if (this.args.readyFile.lastModified != undefined) {
      return `Last saved ${moment(this.args.readyFile.lastModified).fromNow()}`;
    }
    return;
  }

  get fileExtension() {
    if (!this.args.cardInstance) {
      return '.' + this.args.readyFile.url.split('.').pop() || '';
    } else {
      return '';
    }
  }
}
