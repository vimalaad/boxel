import Component from '@glimmer/component';
import { tracked } from '@glimmer/tracking';
import { on } from '@ember/modifier';
import { action } from '@ember/object';
import { restartableTask } from 'ember-concurrency';
import { service } from '@ember/service';
import type CardService from '../services/card-service';
import type { Card, Format } from 'https://cardstack.com/base/card-api';
import FormatPicker from './format-picker';
import Preview from './preview';
import Button from '@cardstack/boxel-ui/components/button';

interface Signature {
  Args: {
    card: Card;
    format?: Format;
    onCancel?: () => void;
    onSave?: (card: Card) => void;
  };
}

const formats: Format[] = ['isolated', 'embedded', 'edit'];

export default class CardEditor extends Component<Signature> {
  <template>
    <FormatPicker
      @formats={{this.formats}}
      @format={{this.format}}
      @setFormat={{this.setFormat}}
    />
    <Preview @format={{this.format}} @card={{@card}} />
    <div class='buttons'>
      {{! @glint-ignore glint doesn't know about EC task properties }}
      {{#if this.write.last.isRunning}}
        <span data-test-saving>Saving...</span>
      {{else}}
        {{#if @onCancel}}
          <Button
            data-test-cancel-create
            {{on 'click' @onCancel}}
            @size='tall'
          >Cancel</Button>
        {{/if}}
        <Button
          data-test-save-card
          {{on 'click' this.save}}
          @kind='primary'
          @size='tall'
        >Save</Button>
      {{/if}}
    </div>
    <style>
      .buttons {
        text-align: right;
      }
    </style>
  </template>

  formats = formats;
  @service declare cardService: CardService;
  @tracked format: Format = this.args.format ?? 'edit';

  @action
  setFormat(format: Format) {
    this.format = format;
  }

  @action
  save() {
    this.write.perform();
  }

  private write = restartableTask(async () => {
    let card = await this.cardService.saveModel(this.args.card);
    this.args.onSave?.(card);
    this.format = 'isolated';
  });
}
