import { cryptoFramework } from '@kit.CryptoArchitectureKit';

// Ordinary IDs are not credentials. Capability tokens retain 256 cryptographic random bits.
export function newMarkdownId(): string {
  const date = new Date();
  const parts: number[] = [date.getFullYear(), date.getMonth() + 1, date.getDate(), date.getHours(), date.getMinutes(), date.getSeconds()];
  const timestamp = parts.map((value: number, index: number) => String(value).padStart(index === 0 ? 4 : 2, '0')).join('');
  const alphabet = 'abcdefghijklmnopqrstuvwxyz0123456789';
  const bytes = cryptoFramework.createRandom().generateRandomSync(7).data;
  let suffix = '';
  for (let index = 0; index < bytes.length; index++) suffix += alphabet.charAt(bytes[index] % alphabet.length);
  return timestamp + '-' + suffix;
}

export function newMarkdownToken(): string {
  const bytes = cryptoFramework.createRandom().generateRandomSync(32).data;
  let token = '';
  for (let index = 0; index < bytes.length; index++) token += bytes[index].toString(16).padStart(2, '0');
  return token;
}
