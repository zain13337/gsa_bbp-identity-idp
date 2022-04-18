import { render } from '@testing-library/react';
import userEvent from '@testing-library/user-event';
import PersonalKeyInput from './personal-key-input';

describe('PersonalKeyInput', () => {
  it('accepts a value with dashes', () => {
    const value = '0000-0000-0000-0000';
    const { getByRole } = render(<PersonalKeyInput />);

    const input = getByRole('textbox') as HTMLInputElement;
    userEvent.type(input, value);

    expect(input.value).to.equal(value);
  });

  it('accepts a value without dashes', () => {
    const value = '0000000000000000';
    const { getByRole } = render(<PersonalKeyInput />);

    const input = getByRole('textbox') as HTMLInputElement;
    userEvent.type(input, value);

    expect(input.value).to.equal(value);
  });

  it('does not accept a code longer than one with dashes', () => {
    const { getByRole } = render(<PersonalKeyInput />);

    const input = getByRole('textbox') as HTMLInputElement;
    userEvent.type(input, '0000-0000-0000-00000');

    expect(input.value).to.equal('0000-0000-0000-0000');
  });
});