declare module 'ember-focus-trap/modifiers/focus-trap' {
  import { FunctionBasedModifier } from 'ember-modifier';
  import { type EmptyObject } from '@ember/component/helper';
  import { type Options } from 'focus-trap';

  const focusTrap: FunctionBasedModifier<{
    Args: {
      // https://ember-focus-trap.netlify.app/docs/arguments/
      Named: {
        isActive?: boolean;
        isPaused?: boolean;
        shouldSelfFocus?: boolean;
        focusTrapOptions?: Partial<Options>;
      };
      Positional: EmptyObject;
    };
    Element: HTMLElement;
  }>;

  export default focusTrap;
}
